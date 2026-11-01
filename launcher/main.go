package main

import (
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
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
		if _, err := os.Stat(defaultCore); err != nil {
			systemCore := "/usr/lib/libretro/gambatte_libretro.so"
			if _, err := os.Stat(systemCore); err == nil {
				defaultCore = systemCore
			}
		}
	}

	var (
		coreFlag    string
		romFlag     string
		sysDirFlag  string
		saveDirFlag string
	)

	arguments := os.Args[1:]
	if len(arguments) > 0 && arguments[0] == "run" {
		arguments = arguments[1:]
	}

	flagSet := flag.NewFlagSet("minime", flag.ExitOnError)
	flagSet.StringVar(&coreFlag, "core", defaultCore, "Path to Libretro core (.dylib or .so)")
	flagSet.StringVar(&romFlag, "rom", "roms/gb/compo/Tobu Tobu Girl (World) (Unl).zip", "Path to ROM file")
	flagSet.StringVar(&sysDirFlag, "sysdir", ".cache/system", "Libretro system directory")
	flagSet.StringVar(&saveDirFlag, "savedir", ".cache/saves", "Libretro save directory")

	if err := flagSet.Parse(arguments); err != nil {
		fmt.Fprintf(os.Stderr, "failed to parse arguments: %v\n", err)
		os.Exit(1)
	}

	if _, err := os.Stat(coreFlag); err != nil {
		fmt.Fprintf(os.Stderr, "core not found: %s\nRun 'task core:fetch' to download it.\n", coreFlag)
		os.Exit(1)
	}

	if _, err := os.Stat(romFlag); err != nil {
		fmt.Fprintf(os.Stderr, "ROM not found: %s\n", romFlag)
		os.Exit(1)
	}

	if err := os.MkdirAll(sysDirFlag, 0755); err != nil {
		fmt.Fprintf(os.Stderr, "failed to create system directory %s: %v\n", sysDirFlag, err)
		os.Exit(1)
	}
	if err := os.MkdirAll(saveDirFlag, 0755); err != nil {
		fmt.Fprintf(os.Stderr, "failed to create save directory %s: %v\n", saveDirFlag, err)
		os.Exit(1)
	}

	if err := runGame(coreFlag, romFlag, sysDirFlag, saveDirFlag); err != nil {
		fmt.Fprintf(os.Stderr, "failed to run game: %v\n", err)
		os.Exit(1)
	}
}
