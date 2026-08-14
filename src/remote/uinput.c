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

#define MAX_EV_FDS 16
static int g_ev_fds[MAX_EV_FDS];
static int g_ev_count = 0;

static void sleep_ms(int ms) {
    if (ms <= 0) return;
    struct timespec ts;
    ts.tv_sec = ms / 1000;
    ts.tv_nsec = (long)(ms % 1000) * 1000000L;
    nanosleep(&ts, NULL);
}

static void open_existing_evdev_nodes(void) {
    g_ev_count = 0;
    char path[32];
    for (int i = 0; i < 16 && g_ev_count < MAX_EV_FDS; i++) {
        snprintf(path, sizeof(path), "/dev/input/event%d", i);
        int fd = open(path, O_RDWR | O_NONBLOCK);
        if (fd < 0) {
            fd = open(path, O_WRONLY | O_NONBLOCK);
        }
        if (fd >= 0) {
            g_ev_fds[g_ev_count++] = fd;
        }
    }
}

int uinput_open(void) {
    // 1. Open all existing physical evdev nodes for direct injection
    open_existing_evdev_nodes();

    // 2. Also create virtual uinput device for processes listening to uinput
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
        // If uinput is unavailable, return synthetic fd 0 if we opened evdev nodes
        if (g_ev_count > 0) return 999;
        perror("open /dev/uinput");
        return -1;
    }

    if (ioctl(fd, UI_SET_EVBIT, EV_KEY) < 0 || ioctl(fd, UI_SET_EVBIT, EV_SYN) < 0) {
        if (g_ev_count > 0) {
            close(fd);
            return 999;
        }
        perror("ioctl UI_SET_EVBIT");
        close(fd);
        return -1;
    }

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
        struct uinput_user_dev uidev;
        memset(&uidev, 0, sizeof(uidev));
        strncpy(uidev.name, "Minime Remote Controller", UINPUT_MAX_NAME_SIZE - 1);
        uidev.id.bustype = BUS_USB;
        uidev.id.vendor = 0x1234;
        uidev.id.product = 0x5678;
        uidev.id.version = 1;
        if (write(fd, &uidev, sizeof(uidev)) < 0) {
            if (g_ev_count > 0) {
                close(fd);
                return 999;
            }
            perror("write uinput_user_dev");
            close(fd);
            return -1;
        }
    }

    if (ioctl(fd, UI_DEV_CREATE) < 0) {
        if (g_ev_count > 0) {
            close(fd);
            return 999;
        }
        perror("ioctl UI_DEV_CREATE");
        close(fd);
        return -1;
    }

    sleep_ms(20);
    return fd;
}

void uinput_close(int fd) {
    if (fd >= 0 && fd != 999) {
        ioctl(fd, UI_DEV_DESTROY);
        close(fd);
    }
    for (int i = 0; i < g_ev_count; i++) {
        if (g_ev_fds[i] >= 0) {
            close(g_ev_fds[i]);
            g_ev_fds[i] = -1;
        }
    }
    g_ev_count = 0;
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

    // Direct numeric code
    char *endptr = NULL;
    long num = strtol(name, &endptr, 10);
    if (endptr && *endptr == '\0' && num > 0 && num < 65535) {
        return (int)num;
    }

    // Trait-aware aliases (using resolved traits keycodes)
    if (traits) {
        if (str_case_eq(name, "up")) return traits->key_up ? traits->key_up : KEY_UP;
        if (str_case_eq(name, "down")) return traits->key_down ? traits->key_down : KEY_DOWN;
        if (str_case_eq(name, "left")) return traits->key_left ? traits->key_left : KEY_LEFT;
        if (str_case_eq(name, "right")) return traits->key_right ? traits->key_right : KEY_RIGHT;
        if (str_case_eq(name, "a")) return traits->key_a ? traits->key_a : BTN_EAST;
        if (str_case_eq(name, "b")) return traits->key_b ? traits->key_b : BTN_SOUTH;
        if (str_case_eq(name, "x")) return traits->key_x ? traits->key_x : BTN_NORTH;
        if (str_case_eq(name, "y")) return traits->key_y ? traits->key_y : BTN_WEST;
        if (str_case_eq(name, "l1") || str_case_eq(name, "l")) return traits->key_l1 ? traits->key_l1 : BTN_TL;
        if (str_case_eq(name, "r1") || str_case_eq(name, "r")) return traits->key_r1 ? traits->key_r1 : BTN_TR;
        if (str_case_eq(name, "l2")) return traits->key_l2 ? traits->key_l2 : BTN_TL2;
        if (str_case_eq(name, "r2")) return traits->key_r2 ? traits->key_r2 : BTN_TR2;
        if (str_case_eq(name, "menu")) return traits->key_menu ? traits->key_menu : BTN_MODE;
        if (str_case_eq(name, "start")) return traits->key_start ? traits->key_start : BTN_START;
        if (str_case_eq(name, "select")) return traits->key_select ? traits->key_select : BTN_SELECT;
        if (str_case_eq(name, "power")) return traits->key_power ? traits->key_power : KEY_POWER;
        if (str_case_eq(name, "vol_up") || str_case_eq(name, "volume_up") || str_case_eq(name, "volup"))
            return traits->key_vol_up ? traits->key_vol_up : KEY_VOLUMEUP;
        if (str_case_eq(name, "vol_down") || str_case_eq(name, "volume_down") || str_case_eq(name, "voldown"))
            return traits->key_vol_down ? traits->key_vol_down : KEY_VOLUMEDOWN;
    }

    // Standard Linux evdev fallback names
    if (str_case_eq(name, "up")) return KEY_UP;
    if (str_case_eq(name, "down")) return KEY_DOWN;
    if (str_case_eq(name, "left")) return KEY_LEFT;
    if (str_case_eq(name, "right")) return KEY_RIGHT;
    if (str_case_eq(name, "a")) return BTN_EAST;
    if (str_case_eq(name, "b")) return BTN_SOUTH;
    if (str_case_eq(name, "x")) return BTN_NORTH;
    if (str_case_eq(name, "y")) return BTN_WEST;
    if (str_case_eq(name, "l1") || str_case_eq(name, "l")) return BTN_TL;
    if (str_case_eq(name, "r1") || str_case_eq(name, "r")) return BTN_TR;
    if (str_case_eq(name, "l2")) return BTN_TL2;
    if (str_case_eq(name, "r2")) return BTN_TR2;
    if (str_case_eq(name, "menu")) return BTN_MODE;
    if (str_case_eq(name, "start")) return BTN_START;
    if (str_case_eq(name, "select")) return BTN_SELECT;
    if (str_case_eq(name, "power")) return KEY_POWER;
    if (str_case_eq(name, "vol_up") || str_case_eq(name, "volume_up") || str_case_eq(name, "volup")) return KEY_VOLUMEUP;
    if (str_case_eq(name, "vol_down") || str_case_eq(name, "volume_down") || str_case_eq(name, "voldown")) return KEY_VOLUMEDOWN;

    return -1;
}

static void broadcast_event(int uinput_fd, uint16_t type, uint16_t code, int32_t value) {
    struct input_event ev;
    memset(&ev, 0, sizeof(ev));
    ev.type = type;
    ev.code = code;
    ev.value = value;

    if (uinput_fd >= 0 && uinput_fd != 999) {
        write(uinput_fd, &ev, sizeof(ev));
    }
    for (int i = 0; i < g_ev_count; i++) {
        if (g_ev_fds[i] >= 0) {
            write(g_ev_fds[i], &ev, sizeof(ev));
        }
    }
}

int uinput_emit(int fd, int keycode, int value) {
    if (fd < 0 || keycode <= 0) return -1;

    broadcast_event(fd, EV_KEY, (uint16_t)keycode, value);
    broadcast_event(fd, EV_SYN, SYN_REPORT, 0);
    return 0;
}

int uinput_press(int fd, int keycode, int duration_ms) {
    if (fd < 0 || keycode <= 0) return -1;
    if (duration_ms <= 0) duration_ms = 50;

    uinput_emit(fd, keycode, 1);
    sleep_ms(duration_ms);
    uinput_emit(fd, keycode, 0);
    return 0;
}

int uinput_combo(int fd, const int *keycodes, int count, int duration_ms) {
    if (fd < 0 || !keycodes || count <= 0) return -1;
    if (duration_ms <= 0) duration_ms = 50;

    // Press all keys in order
    for (int i = 0; i < count; i++) {
        broadcast_event(fd, EV_KEY, (uint16_t)keycodes[i], 1);
    }
    broadcast_event(fd, EV_SYN, SYN_REPORT, 0);

    sleep_ms(duration_ms);

    // Release all keys in reverse order
    for (int i = count - 1; i >= 0; i--) {
        broadcast_event(fd, EV_KEY, (uint16_t)keycodes[i], 0);
    }
    broadcast_event(fd, EV_SYN, SYN_REPORT, 0);

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
