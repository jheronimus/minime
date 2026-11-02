package main

import (
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"runtime"

	"github.com/ebitengine/oto/v3"
)

func main() {
	if runtime.GOOS == "linux" {
		if _, err := os.Stat("/mnt/sdcard"); err == nil {
			_ = os.Chdir("/mnt/sdcard")
		}
	}

	coreExtension := ".dylib"
	if runtime.GOOS == "linux" {
		coreExtension = ".so"
	}
	defaultCore := filepath.Join(".cache", "cores", "gambatte_libretro"+coreExtension)
	if runtime.GOOS == "linux" {
		systemCore := "/usr/lib/libretro/gambatte_libretro.so"
		if _, err := os.Stat(systemCore); err == nil {
			defaultCore = systemCore
		}
	}

	var (
		coreFlag    string
		romFlag     string
		sysDirFlag  string
		saveDirFlag string
	)

	args := os.Args[1:]
	if len(args) > 0 && args[0] == "run" {
		args = args[1:]
	}

	fs := flag.NewFlagSet("minime", flag.ExitOnError)
	fs.StringVar(&coreFlag, "core", defaultCore, "Path to Libretro core (.dylib or .so)")
	fs.StringVar(&romFlag, "rom", "roms/gb/compo/Tobu Tobu Girl (World) (Unl).zip", "Path to ROM file")
	fs.StringVar(&sysDirFlag, "sysdir", ".cache/system", "Libretro system directory")
	fs.StringVar(&saveDirFlag, "savedir", ".cache/saves", "Libretro save directory")

	if err := fs.Parse(args); err != nil {
		fmt.Fprintf(os.Stderr, "failed to parse arguments: %v\n", err)
		os.Exit(1)
	}

	if _, err := os.Stat(coreFlag); err != nil {
		fmt.Fprintf(os.Stderr, "core not found: %s\nRun 'task fetch-cores' to download it.\n", coreFlag)
		os.Exit(1)
	}
	if _, err := os.Stat(romFlag); err != nil {
		fmt.Fprintf(os.Stderr, "ROM not found: %s\n", romFlag)
		os.Exit(1)
	}

	if err := os.MkdirAll(sysDirFlag, 0755); err != nil {
		fmt.Fprintf(os.Stderr, "failed to create system directory: %v\n", err)
		os.Exit(1)
	}
	if err := os.MkdirAll(saveDirFlag, 0755); err != nil {
		fmt.Fprintf(os.Stderr, "failed to create save directory: %v\n", err)
		os.Exit(1)
	}

	// 1. Initialize long-lived platform services
	platform := NewPlatformService()
	defer func() {
		_ = platform.Close()
	}()

	input := NewInputService()
	defer func() {
		_ = input.Close()
	}()

	// 2. Initialize shared audio device context (48 kHz 16-bit stereo)
	otoCtx, ready, err := oto.NewContext(&oto.NewContextOptions{
		SampleRate:   outputSampleRate,
		ChannelCount: 2,
		Format:       oto.FormatSignedInt16LE,
	})
	if err != nil {
		fmt.Fprintf(os.Stderr, "failed to initialize audio context: %v\n", err)
		os.Exit(1)
	}
	<-ready
	if err := otoCtx.Err(); err != nil {
		fmt.Fprintf(os.Stderr, "audio device error: %v\n", err)
		os.Exit(1)
	}

	// 3. Initialize hardware display (Linux DRM KMS dumb buffer) or desktop fallback
	display, err := NewDisplay()
	if err != nil {
		fmt.Fprintf(os.Stderr, "warning: native display initialization failed: %v\n", err)
	}
	if display != nil {
		defer func() {
			_ = display.Close()
		}()
	}

	// 4. Launch game session
	session, err := NewGameSession(SessionConfig{
		CorePath:     coreFlag,
		ROMPath:      romFlag,
		SystemDir:    sysDirFlag,
		SaveDir:      saveDirFlag,
		Platform:     platform,
		Input:        input,
		AudioContext: otoCtx,
		Display:      display,
	})
	if err != nil {
		fmt.Fprintf(os.Stderr, "failed to create game session: %v\n", err)
		os.Exit(1)
	}

	if err := session.Run(); err != nil {
		fmt.Fprintf(os.Stderr, "game session error: %v\n", err)
		os.Exit(1)
	}
}
