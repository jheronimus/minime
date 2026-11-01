package main

import "unsafe"

// Pixel formats negotiated via retro_set_environment(envSetPixelFormat).
const (
	pixelFormat0RGB1555 = iota // 15-bit (1-bit unused, 5-R, 5-G, 5-B)
	pixelFormatXRGB8888        // 32-bit (8-unused, 8-R, 8-G, 8-B)
	pixelFormatRGB565          // 16-bit (5-R, 6-G, 5-B)
)

// Libretro joypad button IDs (RETRO_DEVICE_ID_JOYPAD_*).
const (
	retroJoypadB = iota
	retroJoypadY
	retroJoypadSelect
	retroJoypadStart
	retroJoypadUp
	retroJoypadDown
	retroJoypadLeft
	retroJoypadRight
	retroJoypadA
	retroJoypadX
	retroJoypadL
	retroJoypadR
	retroJoypadL2
	retroJoypadR2
	retroJoypadL3
	retroJoypadR3
)

// Active libretro environment commands handled by runner.
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
	baseWidth   uint32
	baseHeight  uint32
	maxWidth    uint32
	maxHeight   uint32
	aspectRatio float32
	padding     uint32
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
	meta *byte
}
