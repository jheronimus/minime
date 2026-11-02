package main

import (
	"archive/zip"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"time"
	"unsafe"

	"github.com/ebitengine/oto/v3"
	"github.com/hajimehoshi/ebiten/v2"
)

// SessionConfig provides the dependencies needed to execute an emulation session.
type SessionConfig struct {
	CorePath     string
	ROMPath      string
	SystemDir    string
	SaveDir      string
	Platform     *PlatformService
	Input        *InputService
	AudioContext *oto.Context
	Display      Display
}

// GameSession coordinates execution of an active Libretro core and ROM.
type GameSession struct {
	core     *RetroCore
	platform *PlatformService
	input    *InputService
	display  Display

	audioBuf    *AudioBuffer
	audioPlayer *oto.Player
	videoConv   VideoConverter

	fps         float64
	latestFrame Frame
	frameReady  bool
}

// NewGameSession loads the core and ROM, binding all subsystems for execution.
func NewGameSession(cfg SessionConfig) (*GameSession, error) {
	romData, entryPath, err := loadROMFile(cfg.ROMPath)
	if err != nil {
		return nil, fmt.Errorf("read ROM %s: %w", cfg.ROMPath, err)
	}

	core, err := LoadCore(cfg.CorePath, cfg.SystemDir, cfg.SaveDir)
	if err != nil {
		return nil, fmt.Errorf("load core %s: %w", cfg.CorePath, err)
	}

	if err := core.LoadGame(entryPath, romData); err != nil {
		_ = core.Close()
		return nil, fmt.Errorf("core load game: %w", err)
	}

	av := core.AVInfo()
	fps := av.timing.fps
	if fps <= 0 {
		fps = 60.0
	}

	sampleRate := int(av.timing.sampleRate)
	if sampleRate <= 0 {
		sampleRate = 44100
	}

	audioBuf := NewAudioBuffer()
	audioBuf.SetRates(sampleRate, outputSampleRate)

	var audioPlayer *oto.Player
	if cfg.AudioContext != nil {
		audioPlayer = cfg.AudioContext.NewPlayer(audioBuf)
		// 60ms player buffer size to absorb scheduling jitter
		audioPlayer.SetBufferSize(outputSampleRate * 4 * 60 / 1000)
		audioPlayer.Play()
	}

	s := &GameSession{
		core:        core,
		platform:    cfg.Platform,
		input:       cfg.Input,
		display:     cfg.Display,
		audioBuf:    audioBuf,
		audioPlayer: audioPlayer,
		fps:         fps,
	}

	core.SetCallbacks(
		func(data unsafe.Pointer, width, height, pitch int, format uint32) {
			s.latestFrame = s.videoConv.Convert(data, width, height, pitch, format)
			s.frameReady = true
		},
		func(samples []int16) {
			s.audioBuf.WriteSamples(samples)
		},
		func(port, id uint32) int16 {
			if (s.input.State() & (1 << id)) != 0 {
				return 1
			}
			return 0
		},
	)

	return s, nil
}

// Run executes the emulation loop until the user exits or an error occurs.
func (s *GameSession) Run() error {
	defer func() {
		_ = s.Close()
	}()

	if s.display != nil {
		return s.runNativeLoop()
	}

	return s.runDesktopLoop()
}

func (s *GameSession) runNativeLoop() error {
	frameDuration := time.Duration(float64(time.Second) / s.fps)
	ticker := time.NewTicker(frameDuration)
	defer ticker.Stop()

	for {
		<-ticker.C

		s.pollHotkeys()
		s.core.Step()

		if s.frameReady {
			_ = s.display.Show(s.latestFrame)
			s.frameReady = false
		}
	}
}

func (s *GameSession) runDesktopLoop() error {
	w, h := 640, 480
	if s.platform != nil {
		st := s.platform.State()
		if st.DisplayWidth > 0 && st.DisplayHeight > 0 {
			w, h = st.DisplayWidth, st.DisplayHeight
		}
	}

	ebiten.SetWindowTitle("Minime")
	ebiten.SetWindowSize(w, h)
	ebiten.SetWindowResizingMode(ebiten.WindowResizingModeEnabled)
	ebiten.SetTPS(int(s.fps + 0.5))

	if err := ebiten.RunGame(s); err != nil && !errors.Is(err, ebiten.Termination) {
		return fmt.Errorf("desktop game loop: %w", err)
	}
	return nil
}

// Update implements ebiten.Game.
func (s *GameSession) Update() error {
	if ebiten.IsKeyPressed(ebiten.KeyEscape) {
		return ebiten.Termination
	}
	s.pollHotkeys()
	s.core.Step()
	return nil
}

// Draw implements ebiten.Game.
func (s *GameSession) Draw(screen *ebiten.Image) {
	if s.frameReady {
		DrawFrame(screen, s.latestFrame)
		s.frameReady = false
	}
}

// Layout implements ebiten.Game.
func (s *GameSession) Layout(w, h int) (int, int) {
	if w <= 0 || h <= 0 {
		return 640, 480
	}
	return w, h
}

func (s *GameSession) pollHotkeys() {
	if s.input == nil {
		return
	}

	select {
	case ev := <-s.input.Events():
		switch ev {
		case HotkeyVolumeUp:
			if s.platform != nil {
				s.platform.AdjustVolume(true)
				if runtime.GOOS != "linux" && s.audioPlayer != nil {
					s.audioPlayer.SetVolume(float64(s.platform.Volume()) / 100.0)
				}
			}
		case HotkeyVolumeDown:
			if s.platform != nil {
				s.platform.AdjustVolume(false)
				if runtime.GOOS != "linux" && s.audioPlayer != nil {
					s.audioPlayer.SetVolume(float64(s.platform.Volume()) / 100.0)
				}
			}
		case HotkeyBrightnessUp:
			if s.platform != nil {
				s.platform.AdjustBrightness(true)
			}
		case HotkeyBrightnessDown:
			if s.platform != nil {
				s.platform.AdjustBrightness(false)
			}
		case HotkeyPowerSuspend:
			if s.platform != nil {
				if s.audioPlayer != nil {
					s.audioPlayer.Pause()
				}
				_ = s.platform.Suspend()
				if s.audioPlayer != nil {
					s.audioPlayer.Play()
				}
			}
		}
	default:
	}
}

// Close gracefully releases session resources.
func (s *GameSession) Close() error {
	if s.audioPlayer != nil {
		s.audioPlayer.PauseAndStopReading()
	}
	if s.core != nil {
		_ = s.core.Close()
	}
	return nil
}

// loadROMFile extracts ROM data from zip archives or reads flat binary files.
func loadROMFile(romPath string) ([]byte, string, error) {
	absPath, err := filepath.Abs(romPath)
	if err != nil {
		return nil, "", fmt.Errorf("resolve rom path %s: %w", romPath, err)
	}

	if !strings.EqualFold(filepath.Ext(absPath), ".zip") {
		data, err := os.ReadFile(absPath)
		if err != nil {
			return nil, "", fmt.Errorf("read rom: %w", err)
		}
		return data, absPath, nil
	}

	zr, err := zip.OpenReader(absPath)
	if err != nil {
		return nil, "", fmt.Errorf("open zip %s: %w", absPath, err)
	}
	defer func() {
		_ = zr.Close()
	}()

	if len(zr.File) == 0 {
		return nil, "", fmt.Errorf("empty zip archive: %s", romPath)
	}

	first := zr.File[0]
	entryReader, err := first.Open()
	if err != nil {
		return nil, "", fmt.Errorf("open zip entry %s: %w", first.Name, err)
	}
	defer func() {
		_ = entryReader.Close()
	}()

	data, err := io.ReadAll(entryReader)
	if err != nil {
		return nil, "", fmt.Errorf("read zip entry %s: %w", first.Name, err)
	}

	virtualPath := filepath.Join(filepath.Dir(absPath), first.Name)
	return data, virtualPath, nil
}
