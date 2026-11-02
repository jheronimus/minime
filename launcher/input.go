package main

import (
	"encoding/binary"
	"errors"
	"io"
	"os"
	"path/filepath"
	"runtime"
	"sync"
	"sync/atomic"

	"github.com/hajimehoshi/ebiten/v2"
)

// Standard RetroPad virtual controller buttons (RETRO_DEVICE_ID_JOYPAD_*).
const (
	ButtonB = iota
	ButtonY
	ButtonSelect
	ButtonStart
	ButtonUp
	ButtonDown
	ButtonLeft
	ButtonRight
	ButtonA
	ButtonX
	ButtonL
	ButtonR
	ButtonL2
	ButtonR2
	ButtonL3
	ButtonR3
	ButtonMenu // Virtual hotkey button
)

// HotkeyEvent represents an intercepted action combination (e.g. Menu + Volume).
type HotkeyEvent int

const (
	HotkeyNone HotkeyEvent = iota
	HotkeyMenu
	HotkeyVolumeUp
	HotkeyVolumeDown
	HotkeyBrightnessUp
	HotkeyBrightnessDown
	HotkeyPowerSuspend
)

// Linux evdev constants.
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

// InputService manages input from both Linux evdev devices and desktop keyboard/gamepad.
type InputService struct {
	mu           sync.RWMutex
	hardwareMask uint32
	menuHeld     bool
	events       chan HotkeyEvent
	stopCh       chan struct{}
}

// NewInputService initializes device input listeners.
func NewInputService() *InputService {
	svc := &InputService{
		events: make(chan HotkeyEvent, 16),
		stopCh: make(chan struct{}),
	}

	if runtime.GOOS == "linux" {
		svc.watchEvdevDevices()
	}

	return svc
}

// Events returns the receive-only channel for hotkey notifications.
func (is *InputService) Events() <-chan HotkeyEvent {
	return is.events
}

// Close terminates background evdev listeners.
func (is *InputService) Close() error {
	close(is.stopCh)
	return nil
}

// State returns the current RetroPad button bitmask (16-bit).
func (is *InputService) State() uint16 {
	mask := uint16(atomic.LoadUint32(&is.hardwareMask))

	// Desktop Keyboard bindings
	for _, m := range keyboardMappings {
		if ebiten.IsKeyPressed(m.key) {
			mask |= 1 << m.button
		}
	}

	// Desktop Gamepad bindings
	for _, id := range ebiten.AppendGamepadIDs(nil) {
		for _, m := range gamepadMappings {
			if ebiten.IsStandardGamepadButtonPressed(id, m.padButton) {
				mask |= 1 << m.retroButton
			}
		}
	}

	return mask
}

// IsPressed reports whether a specific RetroPad button is currently down.
func (is *InputService) IsPressed(btn int) bool {
	return (is.State() & (1 << btn)) != 0
}

func (is *InputService) emit(ev HotkeyEvent) {
	select {
	case is.events <- ev:
	default:
	}
}

// Linux evdev listener loops

func (is *InputService) watchEvdevDevices() {
	eventFiles, err := filepath.Glob("/dev/input/event*")
	if err != nil {
		return
	}

	for _, path := range eventFiles {
		go is.listenDevice(path)
	}
}

func (is *InputService) listenDevice(path string) {
	file, err := os.Open(path)
	if err != nil {
		return
	}
	defer func() {
		_ = file.Close()
	}()

	go func() {
		<-is.stopCh
		_ = file.Close()
	}()

	var ev linuxInputEvent
	for {
		if err := binary.Read(file, binary.LittleEndian, &ev); err != nil {
			if errors.Is(err, io.EOF) || errors.Is(err, os.ErrClosed) {
				return
			}
			return
		}

		if ev.Type == evSw && ev.Code == swLid && ev.Value == 1 {
			is.emit(HotkeyPowerSuspend)
			continue
		}

		if ev.Type != evKey {
			continue
		}

		// Handle power button
		if ev.Code == keyPower && ev.Value == 1 {
			is.emit(HotkeyPowerSuspend)
			continue
		}

		// Handle Menu button
		if ev.Code == keyMenu || ev.Code == keyMenuAlt {
			is.mu.Lock()
			is.menuHeld = (ev.Value != 0)
			is.mu.Unlock()

			if ev.Value == 1 {
				is.emit(HotkeyMenu)
			}
			continue
		}

		// Handle Volume buttons and Menu + Volume combos
		if (ev.Code == keyVolumeUp || ev.Code == keyVolumeDown) && (ev.Value == 1 || ev.Value == 2) {
			is.mu.RLock()
			menu := is.menuHeld
			is.mu.RUnlock()

			if menu {
				if ev.Code == keyVolumeUp {
					is.emit(HotkeyBrightnessUp)
				} else {
					is.emit(HotkeyBrightnessDown)
				}
			} else {
				if ev.Code == keyVolumeUp {
					is.emit(HotkeyVolumeUp)
				} else {
					is.emit(HotkeyVolumeDown)
				}
			}
			continue
		}

		// Joypad buttons (ignore repeat events ev.Value == 2)
		if ev.Value <= 1 {
			is.handleJoypadCode(ev.Code, ev.Value == 1)
		}
	}
}

func (is *InputService) handleJoypadCode(code uint16, pressed bool) {
	btn := -1
	switch code {
	case 103, 544: // KEY_UP, BTN_DPAD_UP
		btn = ButtonUp
	case 108, 545: // KEY_DOWN, BTN_DPAD_DOWN
		btn = ButtonDown
	case 105, 546: // KEY_LEFT, BTN_DPAD_LEFT
		btn = ButtonLeft
	case 106, 547: // KEY_RIGHT, BTN_DPAD_RIGHT
		btn = ButtonRight
	case 305, 45: // BTN_EAST, KEY_X
		btn = ButtonA
	case 304, 44: // BTN_SOUTH, KEY_Z
		btn = ButtonB
	case 307, 31: // BTN_NORTH, KEY_S
		btn = ButtonX
	case 308, 30: // BTN_WEST, KEY_A
		btn = ButtonY
	case 315, 28: // BTN_START, KEY_ENTER
		btn = ButtonStart
	case 314, 14, 54: // BTN_SELECT, KEY_BACKSPACE, KEY_RIGHTSHIFT
		btn = ButtonSelect
	case 310, 16: // BTN_TL, KEY_Q
		btn = ButtonL
	case 311, 18: // BTN_TR, KEY_E
		btn = ButtonR
	case 312: // BTN_TL2
		btn = ButtonL2
	case 313: // BTN_TR2
		btn = ButtonR2
	}

	if btn >= 0 {
		if pressed {
			atomic.OrUint32(&is.hardwareMask, 1<<btn)
		} else {
			atomic.AndUint32(&is.hardwareMask, ^(1 << btn))
		}
	}
}

// Desktop Mappings

type keyMapping struct {
	key    ebiten.Key
	button int
}

type gamepadMapping struct {
	padButton   ebiten.StandardGamepadButton
	retroButton int
}

var keyboardMappings = []keyMapping{
	{ebiten.KeyArrowUp, ButtonUp},
	{ebiten.KeyArrowDown, ButtonDown},
	{ebiten.KeyArrowLeft, ButtonLeft},
	{ebiten.KeyArrowRight, ButtonRight},
	{ebiten.KeyX, ButtonA},
	{ebiten.KeyZ, ButtonB},
	{ebiten.KeyS, ButtonX},
	{ebiten.KeyA, ButtonY},
	{ebiten.KeyEnter, ButtonStart},
	{ebiten.KeyShiftRight, ButtonSelect},
	{ebiten.KeyBackspace, ButtonSelect},
	{ebiten.KeyQ, ButtonL},
	{ebiten.KeyE, ButtonR},
}

var gamepadMappings = []gamepadMapping{
	{ebiten.StandardGamepadButtonLeftTop, ButtonUp},
	{ebiten.StandardGamepadButtonLeftBottom, ButtonDown},
	{ebiten.StandardGamepadButtonLeftLeft, ButtonLeft},
	{ebiten.StandardGamepadButtonLeftRight, ButtonRight},
	{ebiten.StandardGamepadButtonRightRight, ButtonA},
	{ebiten.StandardGamepadButtonRightBottom, ButtonB},
	{ebiten.StandardGamepadButtonRightTop, ButtonX},
	{ebiten.StandardGamepadButtonRightLeft, ButtonY},
	{ebiten.StandardGamepadButtonCenterRight, ButtonStart},
	{ebiten.StandardGamepadButtonCenterLeft, ButtonSelect},
	{ebiten.StandardGamepadButtonFrontTopLeft, ButtonL},
	{ebiten.StandardGamepadButtonFrontTopRight, ButtonR},
	{ebiten.StandardGamepadButtonFrontBottomLeft, ButtonL2},
	{ebiten.StandardGamepadButtonFrontBottomRight, ButtonR2},
	{ebiten.StandardGamepadButtonLeftStick, ButtonL3},
	{ebiten.StandardGamepadButtonRightStick, ButtonR3},
}
