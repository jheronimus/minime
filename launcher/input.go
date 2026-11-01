package main

import (
	"sync/atomic"

	"github.com/hajimehoshi/ebiten/v2"
)

var hardwareInputMask uint32

func handleEvdevKey(code uint16, pressed bool) {
	var button = -1
	switch code {
	case 103, 544: // KEY_UP, BTN_DPAD_UP
		button = retroJoypadUp
	case 108, 545: // KEY_DOWN, BTN_DPAD_DOWN
		button = retroJoypadDown
	case 105, 546: // KEY_LEFT, BTN_DPAD_LEFT
		button = retroJoypadLeft
	case 106, 547: // KEY_RIGHT, BTN_DPAD_RIGHT
		button = retroJoypadRight
	case 305, 45: // BTN_EAST, KEY_X
		button = retroJoypadA
	case 304, 44: // BTN_SOUTH, KEY_Z
		button = retroJoypadB
	case 307, 31: // BTN_NORTH, KEY_S
		button = retroJoypadX
	case 308, 30: // BTN_WEST, KEY_A
		button = retroJoypadY
	case 315, 28: // BTN_START, KEY_ENTER
		button = retroJoypadStart
	case 314, 14, 54: // BTN_SELECT, KEY_BACKSPACE, KEY_RIGHTSHIFT
		button = retroJoypadSelect
	case 310, 16: // BTN_TL, KEY_Q
		button = retroJoypadL
	case 311, 18: // BTN_TR, KEY_E
		button = retroJoypadR
	case 312: // BTN_TL2
		button = retroJoypadL2
	case 313: // BTN_TR2
		button = retroJoypadR2
	}

	if button >= 0 {
		if pressed {
			atomic.OrUint32(&hardwareInputMask, 1<<button)
		} else {
			atomic.AndUint32(&hardwareInputMask, ^(1 << button))
		}
	}
}

type keyMapping struct {
	key         ebiten.Key
	retroButton int
}

type gamepadMapping struct {
	button      ebiten.StandardGamepadButton
	retroButton int
}

var keyboardMappings = []keyMapping{
	{ebiten.KeyArrowUp, retroJoypadUp},
	{ebiten.KeyArrowDown, retroJoypadDown},
	{ebiten.KeyArrowLeft, retroJoypadLeft},
	{ebiten.KeyArrowRight, retroJoypadRight},
	{ebiten.KeyX, retroJoypadA},
	{ebiten.KeyZ, retroJoypadB},
	{ebiten.KeyS, retroJoypadX},
	{ebiten.KeyA, retroJoypadY},
	{ebiten.KeyEnter, retroJoypadStart},
	{ebiten.KeyShiftRight, retroJoypadSelect},
	{ebiten.KeyBackspace, retroJoypadSelect},
	{ebiten.KeyQ, retroJoypadL},
	{ebiten.KeyE, retroJoypadR},
}

var gamepadMappings = []gamepadMapping{
	{ebiten.StandardGamepadButtonLeftTop, retroJoypadUp},
	{ebiten.StandardGamepadButtonLeftBottom, retroJoypadDown},
	{ebiten.StandardGamepadButtonLeftLeft, retroJoypadLeft},
	{ebiten.StandardGamepadButtonLeftRight, retroJoypadRight},
	{ebiten.StandardGamepadButtonRightRight, retroJoypadA},
	{ebiten.StandardGamepadButtonRightBottom, retroJoypadB},
	{ebiten.StandardGamepadButtonRightTop, retroJoypadX},
	{ebiten.StandardGamepadButtonRightLeft, retroJoypadY},
	{ebiten.StandardGamepadButtonCenterRight, retroJoypadStart},
	{ebiten.StandardGamepadButtonCenterLeft, retroJoypadSelect},
	{ebiten.StandardGamepadButtonFrontTopLeft, retroJoypadL},
	{ebiten.StandardGamepadButtonFrontTopRight, retroJoypadR},
	{ebiten.StandardGamepadButtonFrontBottomLeft, retroJoypadL2},
	{ebiten.StandardGamepadButtonFrontBottomRight, retroJoypadR2},
	{ebiten.StandardGamepadButtonLeftStick, retroJoypadL3},
	{ebiten.StandardGamepadButtonRightStick, retroJoypadR3},
}

func pollInputMask() uint16 {
	mask := uint16(atomic.LoadUint32(&hardwareInputMask))

	for _, mapping := range keyboardMappings {
		if ebiten.IsKeyPressed(mapping.key) {
			mask |= 1 << mapping.retroButton
		}
	}

	for _, gamepadID := range ebiten.AppendGamepadIDs(nil) {
		for _, mapping := range gamepadMappings {
			if ebiten.IsStandardGamepadButtonPressed(gamepadID, mapping.button) {
				mask |= 1 << mapping.retroButton
			}
		}
	}

	return mask
}

// onInputState is the libretro input_state callback, querying joypad button states.
func onInputState(port, device, index, id uintptr) uintptr {
	if activeCore == nil || port != 0 || device != deviceJoypad || id > 15 {
		return 0
	}
	if (activeCore.inputMask & (1 << id)) != 0 {
		return 1
	}
	return 0
}
