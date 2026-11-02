package main

import (
	"github.com/hajimehoshi/ebiten/v2"
)

// Display outputs frames directly to hardware screen scanout (e.g. Linux DRM KMS).
type Display interface {
	Show(frame Frame) error
	Close() error
}

// nativeDisplayFactory is registered by display_drm.go on Linux.
var nativeDisplayFactory func() (Display, error)

// NewDisplay returns the native hardware display on Linux, or nil for desktop Ebitengine.
func NewDisplay() (Display, error) {
	if nativeDisplayFactory != nil {
		return nativeDisplayFactory()
	}
	return nil, nil
}

// cachedImage reuses the texture across frames to avoid runtime allocations.
var cachedImage *ebiten.Image

// DrawFrame scales and centers a frame onto the destination screen with aspect-fit integer scaling.
func DrawFrame(screen *ebiten.Image, frame Frame) {
	if frame.Width <= 0 || frame.Height <= 0 || len(frame.RGBA) < frame.Width*frame.Height*4 {
		return
	}

	if cachedImage == nil || cachedImage.Bounds().Dx() != frame.Width || cachedImage.Bounds().Dy() != frame.Height {
		cachedImage = ebiten.NewImage(frame.Width, frame.Height)
	}
	cachedImage.WritePixels(frame.RGBA)

	sb := screen.Bounds()
	sw, sh := float64(sb.Dx()), float64(sb.Dy())
	cw, ch := float64(frame.Width), float64(frame.Height)

	scale := min(sw/cw, sh/ch)
	scaledW, scaledH := cw*scale, ch*scale
	offsetX := (sw - scaledW) / 2
	offsetY := (sh - scaledH) / 2

	opts := &ebiten.DrawImageOptions{}
	opts.Filter = ebiten.FilterNearest
	opts.GeoM.Scale(scale, scale)
	opts.GeoM.Translate(offsetX, offsetY)

	screen.DrawImage(cachedImage, opts)
}
