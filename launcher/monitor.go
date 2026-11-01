package main

import (
	"encoding/binary"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"sync"
	"time"
)

// Linux evdev constants
const (
	evKey         = 0x01
	evSw          = 0x05
	keyPower      = 116
	keyVolumeUp   = 115
	keyVolumeDown = 114
	keyMenu       = 316
	keyMenuAlt    = 139
	swLid         = 0x00
)

type linuxInputEvent struct {
	Sec   int64
	Usec  int64
	Type  uint16
	Code  uint16
	Value int32
}

// EventType identifies the kind of system hardware event.
type EventType string

const (
	EventPowerSuspend      EventType = "suspend"
	EventPowerResume       EventType = "resume"
	EventBatteryChanged    EventType = "battery_changed"
	EventHDMIHotplug       EventType = "hdmi_hotplug"
	EventVolumeChanged     EventType = "volume_changed"
	EventBrightnessChanged EventType = "brightness_changed"
	EventMenuPressed       EventType = "menu_pressed"
)

// Event represents an asynchronous notification from hardware monitoring.
type Event struct {
	Type EventType
	Data any
}

// SystemState holds a snapshot of detected system and hardware traits.
type SystemState struct {
	BatteryPercent     int  // 0-100, or -1 if unavailable
	BatteryCharging    bool // true if external power / charging
	HDMIConnected      bool
	LidClosed          bool
	DisplayWidth       int
	DisplayHeight      int
	DisplayOrientation int // 0, 90, 180, 270 degrees
	Brightness         int
	MaxBrightness      int
	Volume             int // 0-100
}

// Monitor coordinates hardware discovery and dynamic event monitoring.
type Monitor struct {
	mutex         sync.RWMutex
	state         SystemState
	events        chan Event
	stopChannel   chan struct{}
	backlightPath string
	menuHeld      bool
}

// NewMonitor initializes hardware discovery and background monitoring.
// On non-Linux platforms (e.g. macOS simulator), it returns default dimensions and no-ops.
func NewMonitor() (*Monitor, error) {
	m := &Monitor{
		events:      make(chan Event, 16),
		stopChannel: make(chan struct{}),
		state: SystemState{
			BatteryPercent:     100,
			BatteryCharging:    true,
			HDMIConnected:      false,
			LidClosed:          false,
			DisplayWidth:       640,
			DisplayHeight:      480,
			DisplayOrientation: 0,
			Brightness:         10,
			MaxBrightness:      10,
			Volume:             100,
		},
	}

	if runtime.GOOS != "linux" {
		return m, nil
	}

	m.state.BatteryPercent = -1
	m.probeDisplay()
	m.probeBacklight()
	m.probeBattery()
	m.probeAudio()

	go m.pollSysfsLoop()
	go m.watchInputEvents()

	return m, nil
}

// State returns a consistent snapshot of the current hardware status.
func (m *Monitor) State() SystemState {
	m.mutex.RLock()
	defer m.mutex.RUnlock()
	return m.state
}

// Events returns the receive-only channel for hardware event notifications.
func (m *Monitor) Events() <-chan Event {
	return m.events
}

func (m *Monitor) updateState(updateFn func(s *SystemState)) {
	m.mutex.Lock()
	defer m.mutex.Unlock()
	updateFn(&m.state)
}

func (m *Monitor) emit(event Event) {
	select {
	case m.events <- event:
	default:
		// Prevent blocking if the event channel buffer is full
	}
}

func readTrimmed(path string) (string, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(string(data)), nil
}

func (m *Monitor) probeDisplay() {
	drmDirs, err := filepath.Glob("/sys/class/drm/card*-*")
	if err != nil || len(drmDirs) == 0 {
		return
	}

	for _, dir := range drmDirs {
		baseName := filepath.Base(dir)
		status, _ := readTrimmed(filepath.Join(dir, "status"))

		if strings.Contains(baseName, "HDMI") {
			m.updateState(func(s *SystemState) {
				s.HDMIConnected = (status == "connected")
			})
			continue
		}

		if status != "connected" {
			continue
		}

		// Read preferred mode (e.g. "640x480\n")
		if modeStr, err := readTrimmed(filepath.Join(dir, "modes")); err == nil && modeStr != "" {
			firstMode := strings.Split(modeStr, "\n")[0]
			parts := strings.Split(firstMode, "x")
			if len(parts) == 2 {
				w, _ := strconv.Atoi(parts[0])
				h, _ := strconv.Atoi(parts[1])
				if w > 0 && h > 0 {
					m.updateState(func(s *SystemState) {
						s.DisplayWidth = w
						s.DisplayHeight = h
					})
				}
			}
		}

		// Read panel orientation if exposed by the DRM driver
		if orientStr, err := readTrimmed(filepath.Join(dir, "panel_orientation")); err == nil {
			var rotation int
			switch orientStr {
			case "Upside Down":
				rotation = 180
			case "Left Side Up":
				rotation = 90
			case "Right Side Up":
				rotation = 270
			default:
				rotation = 0
			}
			m.updateState(func(s *SystemState) {
				s.DisplayOrientation = rotation
			})
		}
	}
}

func (m *Monitor) probeBacklight() {
	entries, err := filepath.Glob("/sys/class/backlight/*")
	if err != nil || len(entries) == 0 {
		return
	}

	backlightDir := entries[0]
	m.backlightPath = filepath.Join(backlightDir, "brightness")

	if maxStr, err := readTrimmed(filepath.Join(backlightDir, "max_brightness")); err == nil {
		if maxVal, err := strconv.Atoi(maxStr); err == nil && maxVal > 0 {
			m.updateState(func(s *SystemState) {
				s.MaxBrightness = maxVal
			})
		}
	}
	if curStr, err := readTrimmed(m.backlightPath); err == nil {
		if curVal, err := strconv.Atoi(curStr); err == nil {
			m.updateState(func(s *SystemState) {
				s.Brightness = curVal
			})
		}
	}
}

func (m *Monitor) probeBattery() {
	supplies, err := filepath.Glob("/sys/class/power_supply/*")
	if err != nil || len(supplies) == 0 {
		return
	}

	var (
		batteryCapacity = -1
		isCharging      = false
	)

	for _, ps := range supplies {
		psType, _ := readTrimmed(filepath.Join(ps, "type"))

		if psType == "Battery" {
			if capStr, err := readTrimmed(filepath.Join(ps, "capacity")); err == nil {
				if capVal, err := strconv.Atoi(capStr); err == nil {
					batteryCapacity = capVal
				}
			}
			if status, err := readTrimmed(filepath.Join(ps, "status")); err == nil {
				if status == "Charging" || status == "Full" {
					isCharging = true
				}
			}
		}

		if psType == "Mains" || psType == "USB" {
			if onlineStr, err := readTrimmed(filepath.Join(ps, "online")); err == nil {
				if onlineStr == "1" {
					isCharging = true
				}
			}
		}
	}

	prev := m.State()
	m.updateState(func(s *SystemState) {
		s.BatteryPercent = batteryCapacity
		s.BatteryCharging = isCharging
	})

	if prev.BatteryPercent != batteryCapacity || prev.BatteryCharging != isCharging {
		m.emit(Event{
			Type: EventBatteryChanged,
			Data: m.State(),
		})
	}
}

func (m *Monitor) probeAudio() {
	if runtime.GOOS != "linux" {
		return
	}

	// Try reading mixer volume from traits or common ALSA controls
	mixerControls := []string{"Line Out", "Master", "Playback", "Speaker"}
	for _, ctrl := range mixerControls {
		out, err := exec.Command("amixer", "sget", ctrl).Output()
		if err != nil {
			continue
		}
		// Look for [XX%] pattern in amixer output
		str := string(out)
		idx := strings.Index(str, "[")
		if idx != -1 {
			end := strings.Index(str[idx:], "%]")
			if end != -1 {
				valStr := str[idx+1 : idx+end]
				if val, err := strconv.Atoi(valStr); err == nil && val >= 0 && val <= 100 {
					m.updateState(func(s *SystemState) {
						s.Volume = val
					})
					return
				}
			}
		}
	}
}

func (m *Monitor) pollSysfsLoop() {
	ticker := time.NewTicker(2 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-m.stopChannel:
			return
		case <-ticker.C:
			m.probeBattery()

			hdmiDirs, _ := filepath.Glob("/sys/class/drm/card*-HDMI-*/status")
			for _, statusPath := range hdmiDirs {
				status, _ := readTrimmed(statusPath)
				connected := (status == "connected")
				if m.State().HDMIConnected != connected {
					m.updateState(func(s *SystemState) {
						s.HDMIConnected = connected
					})
					m.emit(Event{Type: EventHDMIHotplug, Data: connected})
				}
			}
		}
	}
}

func (m *Monitor) watchInputEvents() {
	eventFiles, err := filepath.Glob("/dev/input/event*")
	if err != nil {
		return
	}

	for _, eventFile := range eventFiles {
		go m.listenEventDevice(eventFile)
	}
}

func (m *Monitor) listenEventDevice(path string) {
	file, err := os.Open(path)
	if err != nil {
		return
	}
	defer func() {
		_ = file.Close()
	}()

	go func() {
		<-m.stopChannel
		_ = file.Close()
	}()

	var ev linuxInputEvent
	for {
		err := binary.Read(file, binary.LittleEndian, &ev)
		if err != nil {
			if errorsIs(err, io.EOF) || errorsIs(err, os.ErrClosed) {
				return
			}
			return
		}

		if ev.Type == evSw && ev.Code == swLid {
			lidClosed := (ev.Value == 1)
			m.updateState(func(s *SystemState) {
				s.LidClosed = lidClosed
			})
			if lidClosed {
				m.emit(Event{Type: EventPowerSuspend, Data: "lid"})
			} else {
				m.emit(Event{Type: EventPowerResume, Data: "lid"})
			}
		}

		if ev.Type == evKey {
			if ev.Code == keyPower && ev.Value == 1 {
				m.emit(Event{Type: EventPowerSuspend, Data: "power_key"})
			} else if ev.Code == keyMenu || ev.Code == keyMenuAlt {
				m.mutex.Lock()
				m.menuHeld = (ev.Value != 0)
				m.mutex.Unlock()
				if ev.Value == 1 {
					m.emit(Event{Type: EventMenuPressed, Data: "menu_key"})
				}
			} else if (ev.Code == keyVolumeUp || ev.Code == keyVolumeDown) && (ev.Value == 1 || ev.Value == 2) {
				m.mutex.RLock()
				menuHeld := m.menuHeld
				m.mutex.RUnlock()

				if menuHeld {
					m.AdjustBrightness(ev.Code == keyVolumeUp)
				} else {
					step := 5
					if ev.Code == keyVolumeDown {
						step = -5
					}
					cur := m.Volume()
					m.SetVolume(cur + step)
				}
			} else if ev.Value <= 1 {
				handleEvdevKey(ev.Code, ev.Value != 0)
			}
		}
	}
}

func errorsIs(err, target error) bool {
	return strings.Contains(err.Error(), target.Error())
}

// Volume returns the current audio volume percentage (0-100).
func (m *Monitor) Volume() int {
	m.mutex.RLock()
	defer m.mutex.RUnlock()
	return m.state.Volume
}

// SetVolume sets the audio volume percentage (0-100) and syncs to ALSA mixer.
func (m *Monitor) SetVolume(value int) {
	if value < 0 {
		value = 0
	}
	if value > 100 {
		value = 100
	}
	m.updateState(func(s *SystemState) {
		s.Volume = value
	})
	m.emit(Event{Type: EventVolumeChanged, Data: value})

	if runtime.GOOS == "linux" {
		go func(v int) {
			if v > 0 {
				_ = exec.Command("amixer", "-q", "sset", "DAC", "unmute").Run()
				_ = exec.Command("amixer", "-q", "sset", "Speaker", "unmute").Run()
				_ = exec.Command("amixer", "-q", "sset", "Master", fmt.Sprintf("%d%%", v), "unmute").Run()
				_ = exec.Command("amixer", "-q", "sset", "Line Out", fmt.Sprintf("%d%%", v), "unmute").Run()
			} else {
				_ = exec.Command("amixer", "-q", "sset", "Speaker", "mute").Run()
				_ = exec.Command("amixer", "-q", "sset", "Master", "mute").Run()
				_ = exec.Command("amixer", "-q", "sset", "Line Out", "mute").Run()
			}
		}(value)
	}
}

// AdjustBrightness changes the display backlight by one step (or ~10% of max).
func (m *Monitor) AdjustBrightness(increase bool) {
	m.mutex.RLock()
	cur := m.state.Brightness
	maxB := m.state.MaxBrightness
	m.mutex.RUnlock()

	step := 1
	if maxB > 10 {
		step = maxB / 10
		if step < 1 {
			step = 1
		}
	}

	target := cur + step
	if !increase {
		target = cur - step
	}
	if target < 1 {
		target = 1 // Don't turn screen completely black
	}
	if maxB > 0 && target > maxB {
		target = maxB
	}

	_ = m.SetBrightness(target)
}

// SetBrightness adjusts the display backlight.
func (m *Monitor) SetBrightness(value int) error {
	m.updateState(func(s *SystemState) {
		s.Brightness = value
	})
	m.emit(Event{Type: EventBrightnessChanged, Data: value})
	if runtime.GOOS != "linux" || m.backlightPath == "" {
		return nil
	}
	data := []byte(fmt.Sprintf("%d\n", value))
	return os.WriteFile(m.backlightPath, data, 0644)
}

// Suspend triggers Linux kernel suspend-to-RAM or suspend-to-idle.
func (m *Monitor) Suspend() error {
	if runtime.GOOS != "linux" {
		return nil
	}
	if err := os.WriteFile("/sys/power/state", []byte("mem\n"), 0644); err == nil {
		return nil
	}
	return os.WriteFile("/sys/power/state", []byte("freeze\n"), 0644)
}

// Close stops background monitoring goroutines.
func (m *Monitor) Close() error {
	close(m.stopChannel)
	return nil
}
