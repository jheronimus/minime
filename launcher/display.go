package main

import (
	"errors"
	"fmt"

	"github.com/hajimehoshi/ebiten/v2"
)

// Display provides hardware-synchronized presentation of emulator and UI frames.
type Display interface {
	Width() int
	Height() int
	Present(frame Frame) error
	Close() error
}

// nativeDisplayFactory is registered by display_drm.go on Linux.
var nativeDisplayFactory func() (Display, error)

// NewDisplay returns a hardware display if available (DRM/KMS on Linux), or nil for desktop Ebitengine.
func NewDisplay() (Display, error) {
	if nativeDisplayFactory != nil {
		return nativeDisplayFactory()
	}
	return nil, nil
}

// EbitenDisplay is the primary desktop presentation engine using Ebitengine.
// When Ebitengine v2.11 adds native GBM support, this will become the universal display across all platforms.
type EbitenDisplay struct {
	width        int
	height       int
	latestFrame  Frame
	desktopImage *ebiten.Image
	onUpdate     func() error
}

// NewEbitenDisplay creates a desktop window presenter.
func NewEbitenDisplay(w, h int, fps float64, onUpdate func() error) *EbitenDisplay {
	if w <= 0 || h <= 0 {
		w, h = 640, 480
	}

	ebiten.SetWindowTitle("Minime")
	ebiten.SetWindowSize(w, h)
	ebiten.SetWindowResizingMode(ebiten.WindowResizingModeEnabled)
	ebiten.SetTPS(int(fps + 0.5))

	return &EbitenDisplay{
		width:    w,
		height:   h,
		onUpdate: onUpdate,
	}
}

// Run starts the Ebitengine application loop.
func (ed *EbitenDisplay) Run() error {
	if err := ebiten.RunGame(ed); err != nil && !errors.Is(err, ebiten.Termination) {
		return fmt.Errorf("ebiten run game: %w", err)
	}
	return nil
}

// Update implements ebiten.Game.
func (ed *EbitenDisplay) Update() error {
	if ebiten.IsKeyPressed(ebiten.KeyEscape) {
		return ebiten.Termination
	}
	if ed.onUpdate != nil {
		return ed.onUpdate()
	}
	return nil
}

// Present updates the frame to be rendered on the next display refresh.
func (ed *EbitenDisplay) Present(frame Frame) error {
	ed.latestFrame = frame
	return nil
}

// Draw implements ebiten.Game, scaling and rendering the latest frame.
func (ed *EbitenDisplay) Draw(screen *ebiten.Image) {
	f := ed.latestFrame
	if f.Width > 0 && f.Height > 0 && len(f.RGBA) >= f.Width*f.Height*4 {
		if ed.desktopImage == nil || ed.desktopImage.Bounds().Dx() != f.Width || ed.desktopImage.Bounds().Dy() != f.Height {
			ed.desktopImage = ebiten.NewImage(f.Width, f.Height)
		}
		ed.desktopImage.WritePixels(f.RGBA)
	}

	if ed.desktopImage == nil {
		return
	}

	sb := screen.Bounds()
	sw, sh := float64(sb.Dx()), float64(sb.Dy())
	cw, ch := float64(ed.desktopImage.Bounds().Dx()), float64(ed.desktopImage.Bounds().Dy())
	if cw <= 0 || ch <= 0 {
		return
	}

	scale := min(sw/cw, sh/ch)
	scaledW, scaledH := cw*scale, ch*scale
	offsetX := (sw - scaledW) / 2
	offsetY := (sh - scaledH) / 2

	opts := &ebiten.DrawImageOptions{}
	opts.Filter = ebiten.FilterNearest
	opts.GeoM.Scale(scale, scale)
	opts.GeoM.Translate(offsetX, offsetY)

	screen.DrawImage(ed.desktopImage, opts)
}

// Layout implements ebiten.Game.
func (ed *EbitenDisplay) Layout(w, h int) (int, int) {
	if w <= 0 || h <= 0 {
		return ed.width, ed.height
	}
	return w, h
}

// Width returns current display width.
func (ed *EbitenDisplay) Width() int {
	return ed.width
}

// Height returns current display height.
func (ed *EbitenDisplay) Height() int {
	return ed.height
}

// Close cleans up desktop display resources.
func (ed *EbitenDisplay) Close() error {
	return nil
}
