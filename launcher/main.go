package main

import (
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"unsafe"

	"github.com/ebitengine/purego"
)

func main() {
	defaultCore := filepath.Join(".cache", "cores", "gambatte_libretro.dylib")

	switch runtime.GOOS {
	case "linux":
		if _, err := os.Stat("/mnt/sdcard"); err == nil {
			_ = os.Chdir("/mnt/sdcard")
		}

		defaultCore = filepath.Join(".cache", "cores", "gambatte_libretro.so")
		systemCore := "/usr/lib/libretro/gambatte_libretro.so"
		if _, err := os.Stat(systemCore); err == nil {
			defaultCore = systemCore
		}

		initMusl()
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

	audio, err := NewAudioService()
	if err != nil {
		fmt.Fprintf(os.Stderr, "failed to initialize audio service: %v\n", err)
		os.Exit(1)
	}

	// 2. Launch game session
	session, err := NewGameSession(SessionConfig{
		CorePath:  coreFlag,
		ROMPath:   romFlag,
		SystemDir: sysDirFlag,
		SaveDir:   saveDirFlag,
		Platform:  platform,
		Input:     input,
		Audio:     audio,
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

// initMusl fixes uninitialized process name pointers in musl libc.
// Purego/non-CGO Go binaries bypass musl's __libc_start_main, leaving __progname
// NULL. Mesa's drirc queries it during GBM startup and crashes if uninitialized.
func initMusl() {
	for _, libName := range []string{"libc.musl-aarch64.so.1", "libc.musl-armhf.so.1", "libc.musl-x86_64.so.1"} {
		libc, err := purego.Dlopen(libName, purego.RTLD_LAZY|purego.RTLD_GLOBAL)
		if err != nil {
			continue
		}
		nameBytes := []byte("minime\x00")
		namePtr := uintptr(unsafe.Pointer(&nameBytes[0]))
		for _, sym := range []string{"program_invocation_name", "program_invocation_short_name", "__progname", "__progname_full"} {
			addr, err := purego.Dlsym(libc, sym)
			if err == nil && addr != 0 {
				var p *uintptr
				*(*uintptr)(unsafe.Pointer(&p)) = addr
				*p = namePtr
			}
		}
		break
	}
}
