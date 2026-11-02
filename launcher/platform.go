package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"sync"
	"time"
)

// BatteryState reports current battery capacity and charging status.
type BatteryState struct {
	Percent  int  // 0-100, or -1 if unavailable
	Charging bool // true if on AC mains or USB power
}

// SystemState holds a snapshot of detected hardware capabilities.
type SystemState struct {
	Battery       BatteryState
	HDMIConnected bool
	DisplayWidth  int
	DisplayHeight int
	Brightness    int
	MaxBrightness int
	Volume        int // 0-100
}

// PlatformService manages device hardware discovery and power controls.
type PlatformService struct {
	mu            sync.RWMutex
	state         SystemState
	backlightPath string
	mixerControl  string
	stopCh        chan struct{}
}

// NewPlatformService initializes hardware trait discovery and background monitoring.
func NewPlatformService() *PlatformService {
	ps := &PlatformService{
		stopCh: make(chan struct{}),
		state: SystemState{
			Battery: BatteryState{
				Percent:  100,
				Charging: true,
			},
			DisplayWidth:  640,
			DisplayHeight: 480,
			Brightness:    10,
			MaxBrightness: 10,
			Volume:        100,
		},
	}

	if runtime.GOOS != "linux" {
		return ps
	}

	ps.state.Battery.Percent = -1
	ps.probeDisplay()
	ps.probeBacklight()
	ps.probeBattery()
	ps.probeAudioMixer()

	go ps.pollSysfsLoop()

	return ps
}

// State returns a consistent snapshot of the current hardware status.
func (ps *PlatformService) State() SystemState {
	ps.mu.RLock()
	defer ps.mu.RUnlock()
	return ps.state
}

// Close terminates background sysfs polling.
func (ps *PlatformService) Close() error {
	close(ps.stopCh)
	return nil
}

// Volume returns the audio volume percentage (0-100).
func (ps *PlatformService) Volume() int {
	ps.mu.RLock()
	defer ps.mu.RUnlock()
	return ps.state.Volume
}

// SetVolume updates the audio volume (0-100) and synchronizes with the ALSA mixer.
func (ps *PlatformService) SetVolume(val int) {
	val = max(0, min(100, val))

	ps.mu.Lock()
	ps.state.Volume = val
	ctrl := ps.mixerControl
	ps.mu.Unlock()

	if runtime.GOOS != "linux" || ctrl == "" {
		return
	}

	go func(v int, control string) {
		if v > 0 {
			_ = exec.Command("amixer", "-q", "sset", control, fmt.Sprintf("%d%%", v), "unmute").Run()
			_ = exec.Command("amixer", "-q", "sset", "DAC", "unmute").Run()
			_ = exec.Command("amixer", "-q", "sset", "Speaker", "unmute").Run()
		} else {
			_ = exec.Command("amixer", "-q", "sset", control, "mute").Run()
		}
	}(val, ctrl)
}

// AdjustVolume steps the audio volume up or down by 5%.
func (ps *PlatformService) AdjustVolume(increase bool) {
	step := 5
	if !increase {
		step = -5
	}
	ps.SetVolume(ps.Volume() + step)
}

// Brightness returns the current backlight level.
func (ps *PlatformService) Brightness() int {
	ps.mu.RLock()
	defer ps.mu.RUnlock()
	return ps.state.Brightness
}

// SetBrightness sets the display backlight level.
func (ps *PlatformService) SetBrightness(val int) error {
	ps.mu.Lock()
	maxB := ps.state.MaxBrightness
	if maxB > 0 && val > maxB {
		val = maxB
	}
	if val < 1 {
		val = 1
	}
	ps.state.Brightness = val
	path := ps.backlightPath
	ps.mu.Unlock()

	if runtime.GOOS != "linux" || path == "" {
		return nil
	}

	return os.WriteFile(path, []byte(strconv.Itoa(val)+"\n"), 0644)
}

// AdjustBrightness steps the display backlight by 10%.
func (ps *PlatformService) AdjustBrightness(increase bool) {
	ps.mu.RLock()
	cur := ps.state.Brightness
	maxB := ps.state.MaxBrightness
	ps.mu.RUnlock()

	step := max(1, maxB/10)
	target := cur + step
	if !increase {
		target = cur - step
	}
	_ = ps.SetBrightness(target)
}

// Suspend triggers kernel suspend-to-RAM or suspend-to-idle.
func (ps *PlatformService) Suspend() error {
	if runtime.GOOS != "linux" {
		return nil
	}
	if err := os.WriteFile("/sys/power/state", []byte("mem\n"), 0644); err == nil {
		return nil
	}
	return os.WriteFile("/sys/power/state", []byte("freeze\n"), 0644)
}

// Sysfs probing and monitoring

func (ps *PlatformService) probeDisplay() {
	drmDirs, err := filepath.Glob("/sys/class/drm/card*-*")
	if err != nil || len(drmDirs) == 0 {
		return
	}

	for _, dir := range drmDirs {
		status, _ := readTrimmed(filepath.Join(dir, "status"))
		if status != "connected" {
			continue
		}

		if modeStr, err := readTrimmed(filepath.Join(dir, "modes")); err == nil && modeStr != "" {
			firstMode := strings.Split(modeStr, "\n")[0]
			parts := strings.Split(firstMode, "x")
			if len(parts) == 2 {
				w, _ := strconv.Atoi(parts[0])
				h, _ := strconv.Atoi(parts[1])
				if w > 0 && h > 0 {
					ps.mu.Lock()
					ps.state.DisplayWidth = w
					ps.state.DisplayHeight = h
					ps.mu.Unlock()
				}
			}
		}
		break
	}
}

func (ps *PlatformService) probeBacklight() {
	entries, err := filepath.Glob("/sys/class/backlight/*")
	if err != nil || len(entries) == 0 {
		return
	}

	dir := entries[0]
	ps.backlightPath = filepath.Join(dir, "brightness")

	if maxStr, err := readTrimmed(filepath.Join(dir, "max_brightness")); err == nil {
		if val, err := strconv.Atoi(maxStr); err == nil && val > 0 {
			ps.mu.Lock()
			ps.state.MaxBrightness = val
			ps.mu.Unlock()
		}
	}

	if curStr, err := readTrimmed(ps.backlightPath); err == nil {
		if val, err := strconv.Atoi(curStr); err == nil && val > 0 {
			ps.mu.Lock()
			ps.state.Brightness = val
			ps.mu.Unlock()
		}
	}
}

func (ps *PlatformService) probeBattery() {
	supplies, err := filepath.Glob("/sys/class/power_supply/*")
	if err != nil || len(supplies) == 0 {
		return
	}

	capacity := -1
	charging := false

	for _, supply := range supplies {
		typ, _ := readTrimmed(filepath.Join(supply, "type"))
		if typ == "Battery" {
			if capStr, err := readTrimmed(filepath.Join(supply, "capacity")); err == nil {
				if val, err := strconv.Atoi(capStr); err == nil {
					capacity = val
				}
			}
			if status, err := readTrimmed(filepath.Join(supply, "status")); err == nil {
				if status == "Charging" || status == "Full" {
					charging = true
				}
			}
		}
		if typ == "Mains" || typ == "USB" {
			if online, err := readTrimmed(filepath.Join(supply, "online")); err == nil && online == "1" {
				charging = true
			}
		}
	}

	ps.mu.Lock()
	ps.state.Battery.Percent = capacity
	ps.state.Battery.Charging = charging
	ps.mu.Unlock()
}

func (ps *PlatformService) probeAudioMixer() {
	// 1. Try reading traits configuration
	for _, traitPath := range []string{"/usr/share/minime/traits/platform.ini", "/mnt/sdcard/.minime/traits/platform.ini"} {
		if data, err := os.ReadFile(traitPath); err == nil {
			for _, line := range strings.Split(string(data), "\n") {
				line = strings.TrimSpace(line)
				if strings.HasPrefix(line, "audio_mixer=") {
					ps.mixerControl = strings.TrimPrefix(line, "audio_mixer=")
					break
				}
			}
		}
		if ps.mixerControl != "" {
			break
		}
	}

	// 2. Discover available mixer controls dynamically via amixer
	if ps.mixerControl == "" {
		if out, err := exec.Command("amixer", "scontrols").Output(); err == nil {
			str := string(out)
			for _, candidate := range []string{"Line Out", "Master", "Playback", "Speaker"} {
				if strings.Contains(str, "'"+candidate+"'") {
					ps.mixerControl = candidate
					break
				}
			}
		}
	}

	// 3. Query initial volume percentage
	if ps.mixerControl != "" {
		if out, err := exec.Command("amixer", "sget", ps.mixerControl).Output(); err == nil {
			str := string(out)
			if idx := strings.Index(str, "["); idx != -1 {
				if end := strings.Index(str[idx:], "%]"); end != -1 {
					if val, err := strconv.Atoi(str[idx+1 : idx+end]); err == nil {
						ps.mu.Lock()
						ps.state.Volume = val
						ps.mu.Unlock()
					}
				}
			}
		}
	}
}

func (ps *PlatformService) pollSysfsLoop() {
	ticker := time.NewTicker(3 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-ps.stopCh:
			return
		case <-ticker.C:
			ps.probeBattery()

			hdmiDirs, _ := filepath.Glob("/sys/class/drm/card*-HDMI-*/status")
			for _, p := range hdmiDirs {
				status, _ := readTrimmed(p)
				ps.mu.Lock()
				ps.state.HDMIConnected = (status == "connected")
				ps.mu.Unlock()
			}
		}
	}
}

func readTrimmed(path string) (string, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(string(data)), nil
}
