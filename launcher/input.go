package main

import (
	"github.com/hajimehoshi/ebiten/v2"
)

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
	var mask uint16

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
