package main

import (
	"testing"
)

func TestMonitorState(t *testing.T) {
	mon, err := NewMonitor()
	if err != nil {
		t.Fatalf("failed to create monitor: %v", err)
	}
	defer func() {
		_ = mon.Close()
	}()

	state := mon.State()
	if state.DisplayWidth <= 0 || state.DisplayHeight <= 0 {
		t.Errorf("expected positive display dimensions, got %dx%d", state.DisplayWidth, state.DisplayHeight)
	}

	if err := mon.SetBrightness(8); err != nil {
		t.Logf("SetBrightness returned: %v", err)
	}

	mon.SetVolume(80)
	if mon.Volume() != 80 {
		t.Errorf("expected volume 80, got %d", mon.Volume())
	}

	if err := mon.Suspend(); err != nil {
		t.Logf("Suspend returned: %v", err)
	}
}

func TestMonitorEvents(t *testing.T) {
	mon, err := NewMonitor()
	if err != nil {
		t.Fatalf("failed to create monitor: %v", err)
	}
	defer func() {
		_ = mon.Close()
	}()

	mon.emit(Event{Type: EventPowerSuspend, Data: "test"})

	select {
	case ev := <-mon.Events():
		if ev.Type != EventPowerSuspend {
			t.Errorf("expected EventPowerSuspend, got %v", ev.Type)
		}
	default:
		t.Errorf("expected event on channel")
	}
}
