package main

import (
	"path/filepath"
	"runtime"
	"testing"
	"unsafe"
)

func TestGambatteCore(t *testing.T) {
	if runtime.GOOS != "darwin" {
		t.Skip("local test runs on macOS")
	}

	corePath := filepath.Join("..", ".cache", "cores", "gambatte_libretro.dylib")
	systemDirectory := filepath.Join("..", ".cache", "system")
	saveDirectory := filepath.Join("..", ".cache", "saves")

	testROMs := []string{
		filepath.Join("..", "roms", "gb", "compo", "Tobu Tobu Girl (World) (Unl).zip"),
		filepath.Join("..", "roms", "gb", "compo", "Retroid (World) (Unl).zip"),
		filepath.Join("..", "roms", "gb", "Deadeus (World) (Unl).zip"),
	}

	for _, romPath := range testROMs {
		romName := filepath.Base(romPath)
		t.Run(romName, func(t *testing.T) {
			romData, entryPath, err := loadROMFile(romPath)
			if err != nil {
				t.Fatalf("loadROMFile failed: %v", err)
			}

			core, err := LoadCore(corePath, systemDirectory, saveDirectory)
			if err != nil {
				t.Fatalf("LoadCore failed: %v", err)
			}
			defer func() {
				_ = core.Close()
			}()

			if err := core.LoadGame(entryPath, romData); err != nil {
				t.Fatalf("core.LoadGame failed: %v", err)
			}

			av := core.AVInfo()
			if av.geometry.baseWidth != 160 || av.geometry.baseHeight != 144 {
				t.Errorf("unexpected AV geometry: %dx%d (expected 160x144)", av.geometry.baseWidth, av.geometry.baseHeight)
			}

			var (
				framesRendered int
				latestFrame    Frame
				videoConv      VideoConverter
				audioBuf       = NewAudioBuffer()
			)

			audioBuf.SetRates(int(av.timing.sampleRate), outputSampleRate)

			core.SetCallbacks(
				func(data unsafe.Pointer, width, height, pitch int, format uint32) {
					latestFrame = videoConv.Convert(data, width, height, pitch, format)
					framesRendered++
				},
				func(samples []int16) {
					audioBuf.WriteSamples(samples)
				},
				func(port, id uint32) int16 {
					return 0
				},
			)

			for i := 0; i < 60; i++ {
				core.Step()
				if latestFrame.Width > 0 {
					if latestFrame.Width != 160 || latestFrame.Height != 144 {
						t.Fatalf("unexpected frame size: %dx%d", latestFrame.Width, latestFrame.Height)
					}
				}
			}

			if framesRendered == 0 {
				t.Fatalf("expected rendered frames, got 0")
			}

			audioData := make([]byte, 1024)
			bytesRead, err := audioBuf.Read(audioData)
			if err != nil {
				t.Fatalf("audioBuf.Read failed: %v", err)
			}
			if bytesRead != 1024 {
				t.Fatalf("expected 1024 bytes read from audio buffer, got %d", bytesRead)
			}
		})
	}
}
