package main

import (
	"github.com/hajimehoshi/ebiten/v2"
)

// FrameRenderer handles drawing video frames to the Ebitengine screen with aspect-fit integer scaling.
type FrameRenderer struct {
	cachedImage *ebiten.Image
}

// Draw scales and centers a frame onto the destination screen preserving aspect ratio.
func (r *FrameRenderer) Draw(screen *ebiten.Image, frame Frame) {
	if frame.Width > 0 && frame.Height > 0 && len(frame.RGBA) >= frame.Width*frame.Height*4 {
		if r.cachedImage == nil || r.cachedImage.Bounds().Dx() != frame.Width || r.cachedImage.Bounds().Dy() != frame.Height {
			r.cachedImage = ebiten.NewImage(frame.Width, frame.Height)
		}
		r.cachedImage.WritePixels(frame.RGBA)
	}

	if r.cachedImage == nil {
		return
	}

	sb := screen.Bounds()
	sw, sh := float64(sb.Dx()), float64(sb.Dy())
	cw, ch := float64(r.cachedImage.Bounds().Dx()), float64(r.cachedImage.Bounds().Dy())

	scale := min(sw/cw, sh/ch)
	scaledW, scaledH := cw*scale, ch*scale
	offsetX := (sw - scaledW) / 2
	offsetY := (sh - scaledH) / 2

	opts := &ebiten.DrawImageOptions{}
	opts.Filter = ebiten.FilterNearest
	opts.GeoM.Scale(scale, scale)
	opts.GeoM.Translate(offsetX, offsetY)

	screen.DrawImage(r.cachedImage, opts)
}
