package main

import (
	"unsafe"
)

// refreshVideo is the libretro video_refresh callback.
// The core invokes this during retro_run() whenever a new frame is ready.
// It converts raw core framebuffer data into 32-bit RGBA for presentation.
func refreshVideo(frameData unsafe.Pointer, width, height, pitch uintptr) uintptr {
	if activeCore == nil || frameData == nil || width == 0 || height == 0 {
		return 0
	}

	frameWidth := int(width)
	frameHeight := int(height)
	framePitch := int(pitch)
	neededBytes := frameWidth * frameHeight * 4

	if len(activeCore.frameRGBA) < neededBytes {
		activeCore.frameRGBA = make([]byte, neededBytes)
	}
	activeCore.frameWidth = frameWidth
	activeCore.frameHeight = frameHeight

	sourceBytes := unsafe.Slice((*byte)(frameData), frameHeight*framePitch)
	destination := activeCore.frameRGBA
	destIndex := 0

	switch activeCore.pixelFormat {
	case pixelFormatRGB565:
		for y := 0; y < frameHeight; y++ {
			row := sourceBytes[y*framePitch:]
			for x := 0; x < frameWidth; x++ {
				pixelOffset := x * 2
				pixelValue := uint16(row[pixelOffset]) | (uint16(row[pixelOffset+1]) << 8)
				red := uint8((pixelValue >> 11) & 0x1F)
				green := uint8((pixelValue >> 5) & 0x3F)
				blue := uint8(pixelValue & 0x1F)
				destination[destIndex+0] = (red << 3) | (red >> 2)
				destination[destIndex+1] = (green << 2) | (green >> 4)
				destination[destIndex+2] = (blue << 3) | (blue >> 2)
				destination[destIndex+3] = 255
				destIndex += 4
			}
		}
	case pixelFormatXRGB8888:
		for y := 0; y < frameHeight; y++ {
			row := sourceBytes[y*framePitch:]
			for x := 0; x < frameWidth; x++ {
				pixelOffset := x * 4
				destination[destIndex+0] = row[pixelOffset+2] // Red
				destination[destIndex+1] = row[pixelOffset+1] // Green
				destination[destIndex+2] = row[pixelOffset+0] // Blue
				destination[destIndex+3] = 255
				destIndex += 4
			}
		}
	case pixelFormat0RGB1555:
		for y := 0; y < frameHeight; y++ {
			row := sourceBytes[y*framePitch:]
			for x := 0; x < frameWidth; x++ {
				pixelOffset := x * 2
				pixelValue := uint16(row[pixelOffset]) | (uint16(row[pixelOffset+1]) << 8)
				red := uint8((pixelValue >> 10) & 0x1F)
				green := uint8((pixelValue >> 5) & 0x1F)
				blue := uint8(pixelValue & 0x1F)
				destination[destIndex+0] = (red << 3) | (red >> 2)
				destination[destIndex+1] = (green << 3) | (green >> 2)
				destination[destIndex+2] = (blue << 3) | (blue >> 2)
				destination[destIndex+3] = 255
				destIndex += 4
			}
		}
	}

	activeCore.frameReady = true
	return 0
}
