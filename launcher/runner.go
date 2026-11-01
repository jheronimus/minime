package main

import (
	"archive/zip"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"time"
	"unsafe"

	"github.com/ebitengine/oto/v3"
	"github.com/ebitengine/purego"
	"github.com/hajimehoshi/ebiten/v2"
)

// Types, constants and builders

var activeCore *core

type core struct {
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

	frameWidth  int
	frameHeight int
	frameRGBA   []byte
	frameReady  bool

	audioBuf  *audioBuffer
	inputMask uint16

	romData []byte
	romPath []byte

	audioContext *oto.Context
	audioPlayer  *oto.Player
	coreImage    *ebiten.Image
	fps          float64

	monitor *Monitor
}

func loadCore(coreFilePath, systemDirectory, saveDirectory string) (*core, error) {
	absoluteCorePath, err := filepath.Abs(coreFilePath)
	if err != nil {
		return nil, fmt.Errorf("resolve core path %s: %w", coreFilePath, err)
	}

	handle, err := purego.Dlopen(absoluteCorePath, purego.RTLD_NOW|purego.RTLD_GLOBAL)
	if err != nil {
		return nil, fmt.Errorf("dlopen core %s: %w", absoluteCorePath, err)
	}

	loadedCore := &core{
		handle:      handle,
		pixelFormat: pixelFormat0RGB1555,
		audioBuf:    &audioBuffer{data: make([]byte, defaultAudioCapacity)},
		systemDir:   append([]byte(systemDirectory), 0),
		saveDir:     append([]byte(saveDirectory), 0),
	}

	bindSymbol := func(target any, symbolName string) error {
		sym, err := purego.Dlsym(handle, symbolName)
		if err != nil {
			return fmt.Errorf("dlsym %s: %w", symbolName, err)
		}
		purego.RegisterFunc(target, sym)
		return nil
	}

	symbolBindings := []struct {
		target any
		name   string
	}{
		{&loadedCore.retroInit, "retro_init"},
		{&loadedCore.retroDeinit, "retro_deinit"},
		{&loadedCore.retroSetEnvironment, "retro_set_environment"},
		{&loadedCore.retroSetVideoRefresh, "retro_set_video_refresh"},
		{&loadedCore.retroSetAudioSample, "retro_set_audio_sample"},
		{&loadedCore.retroSetAudioSampleBatch, "retro_set_audio_sample_batch"},
		{&loadedCore.retroSetInputPoll, "retro_set_input_poll"},
		{&loadedCore.retroSetInputState, "retro_set_input_state"},
		{&loadedCore.retroSetControllerPortDevice, "retro_set_controller_port_device"},
		{&loadedCore.retroRun, "retro_run"},
		{&loadedCore.retroLoadGame, "retro_load_game"},
		{&loadedCore.retroUnloadGame, "retro_unload_game"},
		{&loadedCore.retroGetSystemAVInfo, "retro_get_system_av_info"},
	}

	for _, binding := range symbolBindings {
		if err := bindSymbol(binding.target, binding.name); err != nil {
			return nil, err
		}
	}

	activeCore = loadedCore

	loadedCore.retroSetEnvironment(purego.NewCallback(onEnvironment))
	loadedCore.retroSetVideoRefresh(purego.NewCallback(refreshVideo))
	loadedCore.retroSetAudioSample(purego.NewCallback(func(left, right uintptr) uintptr { return 0 }))
	loadedCore.retroSetAudioSampleBatch(purego.NewCallback(refreshAudio))
	loadedCore.retroSetInputPoll(purego.NewCallback(func() uintptr { return 0 }))
	loadedCore.retroSetInputState(purego.NewCallback(onInputState))

	loadedCore.retroInit()
	loadedCore.retroSetControllerPortDevice(0, deviceJoypad)

	return loadedCore, nil
}

// Main function

func runGame(coreFilePath, romFilePath, systemDirectory, saveDirectory string) error {
	loadedCore, err := loadCore(coreFilePath, systemDirectory, saveDirectory)
	if err != nil {
		return fmt.Errorf("load core %s: %w", coreFilePath, err)
	}
	defer func() {
		_ = loadedCore.Close()
	}()

	if err := loadedCore.LoadGame(romFilePath); err != nil {
		return fmt.Errorf("load game %s: %w", romFilePath, err)
	}

	geometry := loadedCore.avInfo.geometry
	width := int(geometry.baseWidth)
	height := int(geometry.baseHeight)
	if width <= 0 {
		width = 160
	}
	if height <= 0 {
		height = 144
	}
	loadedCore.coreImage = ebiten.NewImage(width, height)

	fps := loadedCore.avInfo.timing.fps
	if fps <= 0 {
		fps = 60.0
	}
	loadedCore.fps = fps

	sampleRate := int(loadedCore.avInfo.timing.sampleRate)
	if sampleRate <= 0 {
		sampleRate = 44100
	}

	otoCtx, ready, err := oto.NewContext(&oto.NewContextOptions{
		SampleRate:   sampleRate,
		ChannelCount: 2,
		Format:       oto.FormatSignedInt16LE,
	})
	if err != nil {
		return fmt.Errorf("create audio context: %w", err)
	}
	<-ready
	if err := otoCtx.Err(); err != nil {
		return fmt.Errorf("audio device init: %w", err)
	}

	loadedCore.audioContext = otoCtx
	player := otoCtx.NewPlayer(loadedCore.audioBuf)
	loadedCore.audioPlayer = player
	loadedCore.audioPlayer.Play()

	mon, err := NewMonitor()
	if err == nil {
		loadedCore.monitor = mon
	}

	// Try native hardware display first (e.g. Linux DRM KMS on handhelds)
	nativeDisp, err := NewDisplay()
	if err == nil && nativeDisp != nil {
		defer func() {
			_ = nativeDisp.Close()
		}()
		return runNativeGameLoop(loadedCore, nativeDisp)
	}

	// Desktop simulator fallback via Ebitengine (macOS / PC)
	return runEbitenGameLoop(loadedCore)
}

func runNativeGameLoop(loadedCore *core, disp Display) error {
	fps := loadedCore.fps
	if fps <= 0 {
		fps = 60.0
	}
	frameDuration := time.Duration(float64(time.Second) / fps)
	ticker := time.NewTicker(frameDuration)
	defer ticker.Stop()

	for {
		<-ticker.C

		if loadedCore.monitor != nil {
			select {
			case ev := <-loadedCore.monitor.Events():
				switch ev.Type {
				case EventPowerSuspend:
					if loadedCore.audioPlayer != nil {
						loadedCore.audioPlayer.Pause()
					}
					_ = loadedCore.monitor.Suspend()
					if loadedCore.audioPlayer != nil {
						loadedCore.audioPlayer.Play()
					}
				case EventVolumeChanged:
					if loadedCore.audioPlayer != nil {
						if vol, ok := ev.Data.(int); ok {
							loadedCore.audioPlayer.SetVolume(float64(vol) / 100.0)
						}
					}
				}
			default:
			}
		}

		loadedCore.inputMask = pollInputMask()
		loadedCore.retroRun()

		if loadedCore.frameReady {
			_ = disp.Present(loadedCore.frameRGBA, loadedCore.frameWidth, loadedCore.frameHeight)
			loadedCore.frameReady = false
		}
	}
}

func runEbitenGameLoop(loadedCore *core) error {
	windowWidth := 640
	windowHeight := 480
	if loadedCore.monitor != nil {
		state := loadedCore.monitor.State()
		if state.DisplayWidth > 0 && state.DisplayHeight > 0 {
			windowWidth = state.DisplayWidth
			windowHeight = state.DisplayHeight
		}
	}

	ebiten.SetWindowTitle("Minime")
	ebiten.SetWindowSize(windowWidth, windowHeight)
	ebiten.SetWindowResizingMode(ebiten.WindowResizingModeEnabled)
	ebiten.SetTPS(int(loadedCore.fps + 0.5))

	if err := ebiten.RunGame(loadedCore); err != nil && !errors.Is(err, ebiten.Termination) {
		return fmt.Errorf("run game loop: %w", err)
	}
	return nil
}

// Helpers

func (loadedCore *core) LoadGame(gameFilePath string) error {
	absoluteRomPath, err := filepath.Abs(gameFilePath)
	if err != nil {
		return fmt.Errorf("resolve rom path %s: %w", gameFilePath, err)
	}

	var data []byte
	entryPath := absoluteRomPath

	if strings.EqualFold(filepath.Ext(absoluteRomPath), ".zip") {
		zipReader, err := zip.OpenReader(absoluteRomPath)
		if err != nil {
			return fmt.Errorf("open zip archive %s: %w", absoluteRomPath, err)
		}
		defer func() {
			_ = zipReader.Close()
		}()

		if len(zipReader.File) == 0 {
			return fmt.Errorf("empty zip archive: %s", gameFilePath)
		}

		firstEntry := zipReader.File[0]
		entryReader, err := firstEntry.Open()
		if err != nil {
			return fmt.Errorf("open entry %s in zip: %w", firstEntry.Name, err)
		}
		defer func() {
			_ = entryReader.Close()
		}()

		data, err = io.ReadAll(entryReader)
		if err != nil {
			return fmt.Errorf("read entry %s in zip: %w", firstEntry.Name, err)
		}
		entryPath = filepath.Join(filepath.Dir(absoluteRomPath), firstEntry.Name)
	} else {
		data, err = os.ReadFile(absoluteRomPath)
		if err != nil {
			return fmt.Errorf("read ROM file %s: %w", absoluteRomPath, err)
		}
	}

	loadedCore.romData = data
	loadedCore.romPath = append([]byte(entryPath), 0)

	game := gameInfo{
		path: &loadedCore.romPath[0],
		data: unsafe.Pointer(&loadedCore.romData[0]),
		size: uintptr(len(loadedCore.romData)),
	}

	if !loadedCore.retroLoadGame(&game) {
		return fmt.Errorf("core failed to load game: %s", gameFilePath)
	}

	loadedCore.retroGetSystemAVInfo(&loadedCore.avInfo)
	return nil
}

func (loadedCore *core) Close() error {
	if activeCore == loadedCore {
		activeCore = nil
	}
	if loadedCore.monitor != nil {
		_ = loadedCore.monitor.Close()
	}
	if loadedCore.audioPlayer != nil {
		loadedCore.audioPlayer.PauseAndStopReading()
	}
	if loadedCore.retroUnloadGame != nil {
		loadedCore.retroUnloadGame()
	}
	if loadedCore.retroDeinit != nil {
		loadedCore.retroDeinit()
	}
	if loadedCore.handle != 0 {
		return purego.Dlclose(loadedCore.handle)
	}
	return nil
}

func (loadedCore *core) Update() error {
	if ebiten.IsKeyPressed(ebiten.KeyEscape) {
		return ebiten.Termination
	}

	if loadedCore.monitor != nil {
		select {
		case ev := <-loadedCore.monitor.Events():
			switch ev.Type {
			case EventPowerSuspend:
				if loadedCore.audioPlayer != nil {
					loadedCore.audioPlayer.Pause()
				}
				_ = loadedCore.monitor.Suspend()
				if loadedCore.audioPlayer != nil {
					loadedCore.audioPlayer.Play()
				}
			case EventVolumeChanged:
				if loadedCore.audioPlayer != nil {
					if vol, ok := ev.Data.(int); ok {
						loadedCore.audioPlayer.SetVolume(float64(vol) / 100.0)
					}
				}
			}
		default:
		}
	}

	loadedCore.inputMask = pollInputMask()
	loadedCore.retroRun()
	return nil
}

func (loadedCore *core) Draw(screen *ebiten.Image) {
	if loadedCore.frameReady {
		width := loadedCore.frameWidth
		height := loadedCore.frameHeight
		if loadedCore.coreImage == nil || loadedCore.coreImage.Bounds().Dx() != width || loadedCore.coreImage.Bounds().Dy() != height {
			loadedCore.coreImage = ebiten.NewImage(width, height)
		}
		loadedCore.coreImage.WritePixels(loadedCore.frameRGBA[:width*height*4])
		loadedCore.frameReady = false
	}

	if loadedCore.coreImage == nil {
		return
	}

	screenBounds := screen.Bounds()
	screenWidth := float64(screenBounds.Dx())
	screenHeight := float64(screenBounds.Dy())
	coreWidth := float64(loadedCore.coreImage.Bounds().Dx())
	coreHeight := float64(loadedCore.coreImage.Bounds().Dy())
	if coreWidth <= 0 || coreHeight <= 0 {
		return
	}

	scale := screenWidth / coreWidth
	if screenHeight/coreHeight < scale {
		scale = screenHeight / coreHeight
	}

	scaledWidth := coreWidth * scale
	scaledHeight := coreHeight * scale
	offsetX := (screenWidth - scaledWidth) / 2
	offsetY := (screenHeight - scaledHeight) / 2

	options := &ebiten.DrawImageOptions{}
	options.Filter = ebiten.FilterNearest
	options.GeoM.Scale(scale, scale)
	options.GeoM.Translate(offsetX, offsetY)

	screen.DrawImage(loadedCore.coreImage, options)
}

func (loadedCore *core) Layout(outsideWidth, outsideHeight int) (int, int) {
	if outsideWidth <= 0 || outsideHeight <= 0 {
		return 640, 480
	}
	return outsideWidth, outsideHeight
}

func onEnvironment(command uintptr, data unsafe.Pointer) uintptr {
	if activeCore == nil {
		return 0
	}
	switch command {
	case envSetPixelFormat:
		if data != nil {
			format := *(*uint32)(data)
			if format <= pixelFormatRGB565 {
				activeCore.pixelFormat = format
				return 1
			}
		}
	case envGetCanDupe:
		if data != nil {
			*(*bool)(data) = true
			return 1
		}
	case envGetSystemDirectory:
		if data != nil {
			*(*uintptr)(data) = uintptr(unsafe.Pointer(&activeCore.systemDir[0]))
			return 1
		}
	case envGetSaveDirectory:
		if data != nil {
			*(*uintptr)(data) = uintptr(unsafe.Pointer(&activeCore.saveDir[0]))
			return 1
		}
	case envGetVariableUpdate:
		if data != nil {
			*(*bool)(data) = false
			return 1
		}
	case envGetCoreOptionsVersion:
		if data != nil {
			*(*uint32)(data) = 0
			return 1
		}
	default:
		return 0
	}
	return 0
}
