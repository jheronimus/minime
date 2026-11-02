package main

import (
	"fmt"
	"path/filepath"
	"sync"
	"unsafe"

	"github.com/ebitengine/purego"
)

// Pixel formats negotiated via retro_set_environment(envSetPixelFormat).
const (
	pixelFormat0RGB1555 = iota // 15-bit (1-bit unused, 5-R, 5-G, 5-B)
	pixelFormatXRGB8888        // 32-bit (8-unused, 8-R, 8-G, 8-B)
	pixelFormatRGB565          // 16-bit (5-R, 6-G, 5-B)
)

// Active libretro environment commands handled by the runner.
const (
	envGetCanDupe            = 3
	envGetSystemDirectory    = 9
	envSetPixelFormat        = 10
	envGetVariableUpdate     = 17
	envGetSaveDirectory      = 31
	envGetCoreOptionsVersion = 52
)

// Libretro device types.
const deviceJoypad = 1

// gameGeometry matches libretro's struct retro_game_geometry.
type gameGeometry struct {
	baseWidth  uint32
	baseHeight uint32
	_          uint32  // maxWidth
	_          uint32  // maxHeight
	_          float32 // aspectRatio
	_          uint32  // padding
}

// systemTiming matches libretro's struct retro_system_timing.
type systemTiming struct {
	fps        float64
	sampleRate float64
}

// systemAVInfo matches libretro's struct retro_system_av_info.
type systemAVInfo struct {
	geometry gameGeometry
	timing   systemTiming
}

// gameInfo matches libretro's struct retro_game_info.
type gameInfo struct {
	path *byte
	data unsafe.Pointer
	size uintptr
	_    *byte // meta
}

// RetroCore manages the dynamic library lifecycle and Libretro C ABI bindings.
type RetroCore struct {
	handle uintptr

	retroInit                    func()
	retroDeinit                  func()
	retroSetEnvironment          func(uintptr)
	retroSetVideoRefresh         func(uintptr)
	retroSetAudioSample          func(uintptr)
	retroSetAudioSampleBatch     func(uintptr)
	retroSetInputPoll            func(uintptr)
	retroSetInputState           func(uintptr)
	retroSetControllerPortDevice func(uint32, uint32)
	retroRun                     func()
	retroLoadGame                func(*gameInfo) bool
	retroUnloadGame              func()
	retroGetSystemAVInfo         func(*systemAVInfo)

	pixelFormat uint32
	avInfo      systemAVInfo

	systemDir []byte
	saveDir   []byte

	romData []byte
	romPath []byte

	onVideo func(data unsafe.Pointer, width, height, pitch int, format uint32)
	onAudio func(samples []int16)
	onInput func(port, id uint32) int16
}

// Package-level trampoline target required because purego.NewCallback cannot capture closures.
var (
	bridgeMutex  sync.Mutex
	activeBridge *RetroCore
)

// LoadCore dynamically loads a libretro core library and binds its C entry points.
func LoadCore(corePath, systemDir, saveDir string) (*RetroCore, error) {
	absPath, err := filepath.Abs(corePath)
	if err != nil {
		return nil, fmt.Errorf("resolve core path %s: %w", corePath, err)
	}

	handle, err := purego.Dlopen(absPath, purego.RTLD_NOW|purego.RTLD_GLOBAL)
	if err != nil {
		return nil, fmt.Errorf("dlopen core %s: %w", absPath, err)
	}

	c := &RetroCore{
		handle:      handle,
		pixelFormat: pixelFormat0RGB1555,
		systemDir:   append([]byte(systemDir), 0),
		saveDir:     append([]byte(saveDir), 0),
	}

	bindSymbol := func(target any, name string) error {
		sym, err := purego.Dlsym(handle, name)
		if err != nil {
			return fmt.Errorf("dlsym %s: %w", name, err)
		}
		purego.RegisterFunc(target, sym)
		return nil
	}

	symbols := []struct {
		target any
		name   string
	}{
		{&c.retroInit, "retro_init"},
		{&c.retroDeinit, "retro_deinit"},
		{&c.retroSetEnvironment, "retro_set_environment"},
		{&c.retroSetVideoRefresh, "retro_set_video_refresh"},
		{&c.retroSetAudioSample, "retro_set_audio_sample"},
		{&c.retroSetAudioSampleBatch, "retro_set_audio_sample_batch"},
		{&c.retroSetInputPoll, "retro_set_input_poll"},
		{&c.retroSetInputState, "retro_set_input_state"},
		{&c.retroSetControllerPortDevice, "retro_set_controller_port_device"},
		{&c.retroRun, "retro_run"},
		{&c.retroLoadGame, "retro_load_game"},
		{&c.retroUnloadGame, "retro_unload_game"},
		{&c.retroGetSystemAVInfo, "retro_get_system_av_info"},
	}

	for _, s := range symbols {
		if err := bindSymbol(s.target, s.name); err != nil {
			_ = purego.Dlclose(handle)
			return nil, err
		}
	}

	bridgeMutex.Lock()
	activeBridge = c
	bridgeMutex.Unlock()

	c.retroSetEnvironment(purego.NewCallback(libretroEnvironmentCallback))
	c.retroSetVideoRefresh(purego.NewCallback(libretroVideoCallback))
	c.retroSetAudioSample(purego.NewCallback(func(left, right uintptr) uintptr { return 0 }))
	c.retroSetAudioSampleBatch(purego.NewCallback(libretroAudioBatchCallback))
	c.retroSetInputPoll(purego.NewCallback(func() uintptr { return 0 }))
	c.retroSetInputState(purego.NewCallback(libretroInputStateCallback))

	c.retroInit()
	c.retroSetControllerPortDevice(0, deviceJoypad)

	return c, nil
}

// SetCallbacks binds runtime output consumers to core events.
func (c *RetroCore) SetCallbacks(
	videoCb func(data unsafe.Pointer, width, height, pitch int, format uint32),
	audioCb func(samples []int16),
	inputCb func(port, id uint32) int16,
) {
	c.onVideo = videoCb
	c.onAudio = audioCb
	c.onInput = inputCb
}

// LoadGame informs the core to parse and initialize the loaded ROM.
func (c *RetroCore) LoadGame(gamePath string, data []byte) error {
	c.romData = data
	c.romPath = append([]byte(gamePath), 0)

	info := gameInfo{
		path: &c.romPath[0],
		data: unsafe.Pointer(&c.romData[0]),
		size: uintptr(len(c.romData)),
	}

	if !c.retroLoadGame(&info) {
		return fmt.Errorf("core failed to load game: %s", gamePath)
	}

	c.retroGetSystemAVInfo(&c.avInfo)
	return nil
}

// Step advances the Libretro core by one emulation frame.
func (c *RetroCore) Step() {
	bridgeMutex.Lock()
	activeBridge = c
	bridgeMutex.Unlock()

	c.retroRun()
}

// Close unloads the game and releases the dynamic library.
func (c *RetroCore) Close() error {
	bridgeMutex.Lock()
	if activeBridge == c {
		activeBridge = nil
	}
	bridgeMutex.Unlock()

	if c.retroUnloadGame != nil {
		c.retroUnloadGame()
	}
	if c.retroDeinit != nil {
		c.retroDeinit()
	}
	if c.handle != 0 {
		return purego.Dlclose(c.handle)
	}
	return nil
}

// AVInfo returns the reported geometry and timing of the loaded core.
func (c *RetroCore) AVInfo() systemAVInfo {
	return c.avInfo
}

// Libretro C callback trampolines

func libretroEnvironmentCallback(cmd uintptr, data unsafe.Pointer) uintptr {
	bridgeMutex.Lock()
	c := activeBridge
	bridgeMutex.Unlock()

	if c == nil || data == nil {
		return 0
	}

	switch cmd {
	case envSetPixelFormat:
		format := *(*uint32)(data)
		if format <= pixelFormatRGB565 {
			c.pixelFormat = format
			return 1
		}
	case envGetCanDupe:
		*(*bool)(data) = true
		return 1
	case envGetSystemDirectory:
		*(*uintptr)(data) = uintptr(unsafe.Pointer(&c.systemDir[0]))
		return 1
	case envGetSaveDirectory:
		*(*uintptr)(data) = uintptr(unsafe.Pointer(&c.saveDir[0]))
		return 1
	case envGetVariableUpdate:
		*(*bool)(data) = false
		return 1
	case envGetCoreOptionsVersion:
		*(*uint32)(data) = 0
		return 1
	}
	return 0
}

func libretroVideoCallback(frameData unsafe.Pointer, width, height, pitch uintptr) uintptr {
	bridgeMutex.Lock()
	c := activeBridge
	bridgeMutex.Unlock()

	if c == nil || c.onVideo == nil || frameData == nil || width == 0 || height == 0 {
		return 0
	}

	c.onVideo(frameData, int(width), int(height), int(pitch), c.pixelFormat)
	return 0
}

func libretroAudioBatchCallback(data unsafe.Pointer, frames uintptr) uintptr {
	bridgeMutex.Lock()
	c := activeBridge
	bridgeMutex.Unlock()

	if c == nil || c.onAudio == nil || data == nil || frames == 0 {
		return 0
	}

	samples := unsafe.Slice((*int16)(data), int(frames)*2)
	c.onAudio(samples)
	return frames
}

func libretroInputStateCallback(port, device, index, id uintptr) uintptr {
	bridgeMutex.Lock()
	c := activeBridge
	bridgeMutex.Unlock()

	if c == nil || c.onInput == nil || port != 0 || device != deviceJoypad || id > 15 {
		return 0
	}

	return uintptr(c.onInput(uint32(port), uint32(id)))
}
