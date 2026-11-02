package main

import (
	"unsafe"
)

// Frame contains a 32-bit RGBA pixel buffer ready for screen presentation.
type Frame struct {
	Width  int
	Height int
	RGBA   []byte
}

// VideoConverter converts raw Libretro framebuffers into RGBA frames.
type VideoConverter struct {
	rgba []byte
}

// Convert converts raw core framebuffer data into standard 32-bit RGBA format.
func (vc *VideoConverter) Convert(frameData unsafe.Pointer, width, height, pitch int, pixelFormat uint32) Frame {
	if frameData == nil || width <= 0 || height <= 0 || pitch <= 0 {
		return Frame{}
	}

	neededBytes := width * height * 4
	if len(vc.rgba) < neededBytes {
		vc.rgba = make([]byte, neededBytes)
	}

	sourceBytes := unsafe.Slice((*byte)(frameData), height*pitch)
	dest := vc.rgba[:neededBytes]
	destIdx := 0

	switch pixelFormat {
	case pixelFormatRGB565:
		for y := 0; y < height; y++ {
			row := sourceBytes[y*pitch:]
			for x := 0; x < width; x++ {
				offset := x * 2
				val := uint16(row[offset]) | (uint16(row[offset+1]) << 8)
				r := uint8((val >> 11) & 0x1F)
				g := uint8((val >> 5) & 0x3F)
				b := uint8(val & 0x1F)
				dest[destIdx+0] = (r << 3) | (r >> 2)
				dest[destIdx+1] = (g << 2) | (g >> 4)
				dest[destIdx+2] = (b << 3) | (b >> 2)
				dest[destIdx+3] = 255
				destIdx += 4
			}
		}

	case pixelFormatXRGB8888:
		for y := 0; y < height; y++ {
			row := sourceBytes[y*pitch:]
			for x := 0; x < width; x++ {
				offset := x * 4
				dest[destIdx+0] = row[offset+2] // R
				dest[destIdx+1] = row[offset+1] // G
				dest[destIdx+2] = row[offset+0] // B
				dest[destIdx+3] = 255
				destIdx += 4
			}
		}

	case pixelFormat0RGB1555:
		for y := 0; y < height; y++ {
			row := sourceBytes[y*pitch:]
			for x := 0; x < width; x++ {
				offset := x * 2
				val := uint16(row[offset]) | (uint16(row[offset+1]) << 8)
				r := uint8((val >> 10) & 0x1F)
				g := uint8((val >> 5) & 0x1F)
				b := uint8(val & 0x1F)
				dest[destIdx+0] = (r << 3) | (r >> 2)
				dest[destIdx+1] = (g << 3) | (g >> 2)
				dest[destIdx+2] = (b << 3) | (b >> 2)
				dest[destIdx+3] = 255
				destIdx += 4
			}
		}
	}

	return Frame{
		Width:  width,
		Height: height,
		RGBA:   dest,
	}
}
