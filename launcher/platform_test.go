package main

import (
	"testing"
)

func TestPlatformState(t *testing.T) {
	ps := NewPlatformService()
	defer func() {
		_ = ps.Close()
	}()

	st := ps.State()
	if st.DisplayWidth <= 0 || st.DisplayHeight <= 0 {
		t.Errorf("expected positive display dimensions, got %dx%d", st.DisplayWidth, st.DisplayHeight)
	}

	if err := ps.SetBrightness(8); err != nil {
		t.Logf("SetBrightness returned: %v", err)
	}

	ps.SetVolume(80)
	if ps.Volume() != 80 {
		t.Errorf("expected volume 80, got %d", ps.Volume())
	}

	ps.AdjustVolume(true)
	if ps.Volume() != 85 {
		t.Errorf("expected volume 85 after adjust, got %d", ps.Volume())
	}

	if err := ps.Suspend(); err != nil {
		t.Logf("Suspend returned: %v", err)
	}
}

func TestInputServiceHotkeys(t *testing.T) {
	input := NewInputService()
	defer func() {
		_ = input.Close()
	}()

	input.emit(HotkeyMenu)
	input.emit(HotkeyVolumeUp)

	select {
	case ev := <-input.Events():
		if ev != HotkeyMenu {
			t.Errorf("expected HotkeyMenu, got %v", ev)
		}
	default:
		t.Errorf("expected event on channel")
	}

	select {
	case ev := <-input.Events():
		if ev != HotkeyVolumeUp {
			t.Errorf("expected HotkeyVolumeUp, got %v", ev)
		}
	default:
		t.Errorf("expected event on channel")
	}
}
