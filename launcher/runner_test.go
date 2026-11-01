package main

import (
	"path/filepath"
	"runtime"
	"testing"
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
			loadedCore, err := loadCore(corePath, systemDirectory, saveDirectory)
			if err != nil {
				t.Fatalf("loadCore failed: %v", err)
			}
			defer loadedCore.Close()

			if err := loadedCore.LoadGame(romPath); err != nil {
				t.Fatalf("LoadGame failed: %v", err)
			}

			av := loadedCore.avInfo
			if av.geometry.baseWidth != 160 || av.geometry.baseHeight != 144 {
				t.Errorf("unexpected AV geometry: %dx%d (expected 160x144)", av.geometry.baseWidth, av.geometry.baseHeight)
			}

			framesRendered := 0

			for i := 0; i < 60; i++ {
				loadedCore.retroRun()
				if loadedCore.frameReady {
					if loadedCore.frameWidth != 160 || loadedCore.frameHeight != 144 {
						t.Fatalf("unexpected frame size: %dx%d", loadedCore.frameWidth, loadedCore.frameHeight)
					}
					framesRendered++
					loadedCore.frameReady = false
				}
			}

			if framesRendered == 0 {
				t.Fatalf("expected rendered frames, got 0")
			}

			audioData := make([]byte, 1024)
			bytesRead, err := loadedCore.audioBuf.Read(audioData)
			if err != nil {
				t.Fatalf("audioBuf.Read failed: %v", err)
			}
			if bytesRead != 1024 {
				t.Fatalf("expected 1024 bytes read from audio buffer, got %d", bytesRead)
			}
		})
	}
}
