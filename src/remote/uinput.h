#ifndef UINPUT_H
#define UINPUT_H

#include "traits.h"
#include <stddef.h>
#include <stdint.h>

/*
 * Initialize a virtual uinput device for gamepad and keypress emulation.
 * Returns file descriptor >= 0 on success, -1 on error.
 */
int uinput_open(void);

/*
 * Close the virtual uinput device.
 */
void uinput_close(int fd);

/*
 * Resolve a key identifier (logical name, trait name, or numeric code) to Linux evdev keycode.
 * Returns keycode > 0 on success, -1 if unknown.
 */
int resolve_keycode(const char *name, const RemoteTraits *traits);

/*
 * Emit key event (value: 1 = pressed, 0 = released).
 */
int uinput_emit(int fd, int keycode, int value);

/*
 * Emulate single keypress with duration in milliseconds.
 */
int uinput_press(int fd, int keycode, int duration_ms);

/*
 * Emulate multi-key simultaneous press (combo) with duration in milliseconds.
 */
int uinput_combo(int fd, const int *keycodes, int count, int duration_ms);

/*
 * Execute a timed sequence string (e.g. "UP:100,WAIT:200,A:50,WAIT:500,MENU+X:50").
 */
int uinput_sequence(int fd, const char *seq, const RemoteTraits *traits);

#endif /* UINPUT_H */
