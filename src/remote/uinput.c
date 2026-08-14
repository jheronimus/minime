#include "uinput.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <time.h>
#include <ctype.h>
#include <sys/ioctl.h>
#include <linux/uinput.h>
#include <linux/input.h>

static void sleep_ms(int ms) {
    if (ms <= 0) return;
    struct timespec ts;
    ts.tv_sec = ms / 1000;
    ts.tv_nsec = (long)(ms % 1000) * 1000000L;
    nanosleep(&ts, NULL);
}

int uinput_open(void) {
    static const char *paths[] = {
        "/dev/uinput",
        "/dev/input/uinput",
        "/dev/misc/uinput"
    };

    int fd = -1;
    for (size_t i = 0; i < sizeof(paths)/sizeof(paths[0]); i++) {
        fd = open(paths[i], O_WRONLY | O_NONBLOCK);
        if (fd >= 0) break;
    }

    if (fd < 0) {
        perror("open /dev/uinput");
        return -1;
    }

    // Enable EV_KEY and EV_SYN
    if (ioctl(fd, UI_SET_EVBIT, EV_KEY) < 0 || ioctl(fd, UI_SET_EVBIT, EV_SYN) < 0) {
        perror("ioctl UI_SET_EVBIT");
        close(fd);
        return -1;
    }

    // Enable common gamepad and keyboard keys (0 to 512)
    for (int k = 1; k < 512; k++) {
        ioctl(fd, UI_SET_KEYBIT, k);
    }

    struct uinput_setup usetup;
    memset(&usetup, 0, sizeof(usetup));
    usetup.id.bustype = BUS_USB;
    usetup.id.vendor = 0x1234;
    usetup.id.product = 0x5678;
    usetup.id.version = 1;
    strncpy(usetup.name, "Minime Remote Controller", sizeof(usetup.name) - 1);

    if (ioctl(fd, UI_DEV_SETUP, &usetup) < 0) {
        // Fallback for older uinput kernel interface
        struct uinput_user_dev uidev;
        memset(&uidev, 0, sizeof(uidev));
        strncpy(uidev.name, "Minime Remote Controller", UINPUT_MAX_NAME_SIZE - 1);
        uidev.id.bustype = BUS_USB;
        uidev.id.vendor = 0x1234;
        uidev.id.product = 0x5678;
        uidev.id.version = 1;
        if (write(fd, &uidev, sizeof(uidev)) < 0) {
            perror("write uinput_user_dev");
            close(fd);
            return -1;
        }
    }

    if (ioctl(fd, UI_DEV_CREATE) < 0) {
        perror("ioctl UI_DEV_CREATE");
        close(fd);
        return -1;
    }

    // Small delay to allow Linux evdev subsystem to register device node
    sleep_ms(50);
    return fd;
}

void uinput_close(int fd) {
    if (fd >= 0) {
        ioctl(fd, UI_DEV_DESTROY);
        close(fd);
    }
}

static int str_case_eq(const char *a, const char *b) {
    while (*a && *b) {
        if (tolower((unsigned char)*a) != tolower((unsigned char)*b)) return 0;
        a++;
        b++;
    }
    return (*a == 0 && *b == 0);
}

int resolve_keycode(const char *name, const RemoteTraits *traits) {
    if (!name || !*name) return -1;

    // Check if numeric string
    char *end = NULL;
    long val = strtol(name, &end, 10);
    if (end && *end == '\0' && val > 0 && val < 65536) {
        return (int)val;
    }

    // Match logical names
    if (str_case_eq(name, "up") || str_case_eq(name, "dpad_up") || str_case_eq(name, "key_up"))
        return traits->key_up;
    if (str_case_eq(name, "down") || str_case_eq(name, "dpad_down") || str_case_eq(name, "key_down"))
        return traits->key_down;
    if (str_case_eq(name, "left") || str_case_eq(name, "dpad_left") || str_case_eq(name, "key_left"))
        return traits->key_left;
    if (str_case_eq(name, "right") || str_case_eq(name, "dpad_right") || str_case_eq(name, "key_right"))
        return traits->key_right;

    if (str_case_eq(name, "a") || str_case_eq(name, "east") || str_case_eq(name, "key_a"))
        return traits->key_a;
    if (str_case_eq(name, "b") || str_case_eq(name, "south") || str_case_eq(name, "key_b"))
        return traits->key_b;
    if (str_case_eq(name, "c") || str_case_eq(name, "key_c"))
        return traits->key_c ? traits->key_c : BTN_C;
    if (str_case_eq(name, "x") || str_case_eq(name, "north") || str_case_eq(name, "key_x"))
        return traits->key_x;
    if (str_case_eq(name, "y") || str_case_eq(name, "west") || str_case_eq(name, "key_y"))
        return traits->key_y;
    if (str_case_eq(name, "z") || str_case_eq(name, "key_z"))
        return traits->key_z ? traits->key_z : BTN_Z;

    if (str_case_eq(name, "l1") || str_case_eq(name, "l") || str_case_eq(name, "tl") || str_case_eq(name, "key_l1"))
        return traits->key_l1;
    if (str_case_eq(name, "r1") || str_case_eq(name, "r") || str_case_eq(name, "tr") || str_case_eq(name, "key_r1"))
        return traits->key_r1;
    if (str_case_eq(name, "l2") || str_case_eq(name, "tl2") || str_case_eq(name, "key_l2"))
        return traits->key_l2;
    if (str_case_eq(name, "r2") || str_case_eq(name, "tr2") || str_case_eq(name, "key_r2"))
        return traits->key_r2;
    if (str_case_eq(name, "l3") || str_case_eq(name, "thumbl") || str_case_eq(name, "key_l3"))
        return traits->key_l3 ? traits->key_l3 : BTN_THUMBL;
    if (str_case_eq(name, "r3") || str_case_eq(name, "thumbr") || str_case_eq(name, "key_r3"))
        return traits->key_r3 ? traits->key_r3 : BTN_THUMBR;

    if (str_case_eq(name, "start") || str_case_eq(name, "key_start"))
        return traits->key_start;
    if (str_case_eq(name, "select") || str_case_eq(name, "key_select"))
        return traits->key_select;
    if (str_case_eq(name, "menu") || str_case_eq(name, "mode") || str_case_eq(name, "hotkey") || str_case_eq(name, "key_menu"))
        return traits->key_menu;
    if (str_case_eq(name, "power") || str_case_eq(name, "key_power"))
        return traits->key_power;

    if (str_case_eq(name, "vol_up") || str_case_eq(name, "volume_up") || str_case_eq(name, "volup") || str_case_eq(name, "plus") || str_case_eq(name, "key_vol_up"))
        return traits->key_vol_up;
    if (str_case_eq(name, "vol_down") || str_case_eq(name, "volume_down") || str_case_eq(name, "voldown") || str_case_eq(name, "minus") || str_case_eq(name, "key_vol_down"))
        return traits->key_vol_down;

    // Standard Linux keycodes
    if (str_case_eq(name, "enter") || str_case_eq(name, "key_enter")) return KEY_ENTER;
    if (str_case_eq(name, "esc") || str_case_eq(name, "escape") || str_case_eq(name, "key_esc")) return KEY_ESC;
    if (str_case_eq(name, "space") || str_case_eq(name, "key_space")) return KEY_SPACE;
    if (str_case_eq(name, "backspace") || str_case_eq(name, "key_backspace")) return KEY_BACKSPACE;
    if (str_case_eq(name, "tab") || str_case_eq(name, "key_tab")) return KEY_TAB;

    return -1;
}

int uinput_emit(int fd, int keycode, int value) {
    if (fd < 0 || keycode <= 0) return -1;

    struct input_event ev;
    memset(&ev, 0, sizeof(ev));
    ev.type = EV_KEY;
    ev.code = (uint16_t)keycode;
    ev.value = value;
    if (write(fd, &ev, sizeof(ev)) < 0) {
        perror("write EV_KEY");
        return -1;
    }

    memset(&ev, 0, sizeof(ev));
    ev.type = EV_SYN;
    ev.code = SYN_REPORT;
    ev.value = 0;
    if (write(fd, &ev, sizeof(ev)) < 0) {
        perror("write EV_SYN");
        return -1;
    }

    return 0;
}

int uinput_press(int fd, int keycode, int duration_ms) {
    if (fd < 0 || keycode <= 0) return -1;
    if (duration_ms <= 0) duration_ms = 50;

    if (uinput_emit(fd, keycode, 1) < 0) return -1;
    sleep_ms(duration_ms);
    if (uinput_emit(fd, keycode, 0) < 0) return -1;
    return 0;
}

int uinput_combo(int fd, const int *keycodes, int count, int duration_ms) {
    if (fd < 0 || !keycodes || count <= 0) return -1;
    if (duration_ms <= 0) duration_ms = 50;

    // Press all keys
    for (int i = 0; i < count; i++) {
        struct input_event ev;
        memset(&ev, 0, sizeof(ev));
        ev.type = EV_KEY;
        ev.code = (uint16_t)keycodes[i];
        ev.value = 1;
        write(fd, &ev, sizeof(ev));
    }
    struct input_event syn;
    memset(&syn, 0, sizeof(syn));
    syn.type = EV_SYN;
    syn.code = SYN_REPORT;
    write(fd, &syn, sizeof(syn));

    sleep_ms(duration_ms);

    // Release all keys in reverse
    for (int i = count - 1; i >= 0; i--) {
        struct input_event ev;
        memset(&ev, 0, sizeof(ev));
        ev.type = EV_KEY;
        ev.code = (uint16_t)keycodes[i];
        ev.value = 0;
        write(fd, &ev, sizeof(ev));
    }
    write(fd, &syn, sizeof(syn));

    return 0;
}

int uinput_sequence(int fd, const char *seq, const RemoteTraits *traits) {
    if (fd < 0 || !seq || !*seq) return -1;

    char *buf = strdup(seq);
    if (!buf) return -1;

    char *saveptr = NULL;
    char *token = strtok_r(buf, ",\n\r", &saveptr);

    while (token) {
        while (isspace((unsigned char)*token)) token++;
        if (*token != '\0') {
            char *colon = strchr(token, ':');
            int duration = 50;
            if (colon) {
                *colon = '\0';
                duration = atoi(colon + 1);
                if (duration <= 0) duration = 50;
            }

            if (str_case_eq(token, "wait") || str_case_eq(token, "sleep") || str_case_eq(token, "delay")) {
                sleep_ms(duration);
            } else if (strchr(token, '+')) {
                // Combo step like MENU+X
                int keys[16];
                int kcount = 0;
                char *comboptr = NULL;
                char *kname = strtok_r(token, "+", &comboptr);
                while (kname && kcount < 16) {
                    while (isspace((unsigned char)*kname)) kname++;
                    int code = resolve_keycode(kname, traits);
                    if (code > 0) {
                        keys[kcount++] = code;
                    } else {
                        fprintf(stderr, "Unknown combo key: '%s'\n", kname);
                    }
                    kname = strtok_r(NULL, "+", &comboptr);
                }
                if (kcount > 0) {
                    uinput_combo(fd, keys, kcount, duration);
                }
            } else {
                int code = resolve_keycode(token, traits);
                if (code > 0) {
                    uinput_press(fd, code, duration);
                } else {
                    fprintf(stderr, "Unknown sequence key: '%s'\n", token);
                }
            }
        }
        token = strtok_r(NULL, ",\n\r", &saveptr);
    }

    free(buf);
    return 0;
}
