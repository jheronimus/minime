#define _POSIX_C_SOURCE 200809L

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <unistd.h>

#include "traits.h"
#include "fb.h"
#include "drm.h"
#include "png_enc.h"
#include "base64.h"
#include "uinput.h"
#include "rotate.h"

static void print_usage(const char *prog) {
    fprintf(stderr,
            "Minime Remote Diagnostics & Input Emulation Tool\n"
            "Usage:\n"
            "  %s screenshot [options]\n"
            "      --out <path>       Save PNG to file (default: write to stdout)\n"
            "      --base64           Output Base64-encoded PNG string\n"
            "      --backend <mode>   Capture backend: auto (default), drm, fb\n"
            "      --device <path>    Override device path (/dev/dri/card0 or /dev/fb0)\n"
            "\n"
            "  %s press <key> [--duration <ms>]\n"
            "      Simulate a single key press and release (default duration: 50ms)\n"
            "\n"
            "  %s down <key>\n"
            "      Hold key down\n"
            "\n"
            "  %s up <key>\n"
            "      Release key\n"
            "\n"
            "  %s combo <k1,k2,...> [--duration <ms>]\n"
            "      Simulate simultaneous key combo (e.g. MENU,X)\n"
            "\n"
            "  %s sequence <spec>\n"
            "      Execute timed sequence (e.g. 'UP:100,WAIT:200,A:50,WAIT:500,START:50')\n"
            "\n"
            "  %s info\n"
            "      Display active hardware traits (screen rotation, dimensions, keymap)\n"
            "\n"
            "Logical Button Names:\n"
            "  D-Pad:      UP, DOWN, LEFT, RIGHT\n"
            "  Face:       A, B, X, Y, C, Z\n"
            "  Shoulders:  L1, R1, L2, R2, L3, R3\n"
            "  System:     START, SELECT, MENU, POWER, VOL_UP, VOL_DOWN\n"
            "  Raw Codes:  Numeric keycodes (e.g. 304, 305, 103) are also supported\n",
            prog, prog, prog, prog, prog, prog, prog);
}

typedef enum {
    BACKEND_AUTO,
    BACKEND_DRM,
    BACKEND_FB
} capture_backend_t;

static int cmd_screenshot(int argc, char **argv, const RemoteTraits *traits) {
    const char *out_path = NULL;
    int use_base64 = 0;
    capture_backend_t backend = BACKEND_AUTO;
    const char *device_path = NULL;

    for (int i = 2; i < argc; i++) {
        if (strcmp(argv[i], "--out") == 0 && i + 1 < argc) {
            out_path = argv[++i];
        } else if (strcmp(argv[i], "--base64") == 0) {
            use_base64 = 1;
        } else if (strcmp(argv[i], "--backend") == 0 && i + 1 < argc) {
            const char *b = argv[++i];
            if (strcasecmp(b, "drm") == 0) {
                backend = BACKEND_DRM;
            } else if (strcasecmp(b, "fb") == 0) {
                backend = BACKEND_FB;
            } else if (strcasecmp(b, "auto") == 0) {
                backend = BACKEND_AUTO;
            } else {
                fprintf(stderr, "Unknown backend '%s' (valid: auto, drm, fb)\n", b);
                return 1;
            }
        } else if (strcmp(argv[i], "--device") == 0 && i + 1 < argc) {
            device_path = argv[++i];
        } else {
            fprintf(stderr, "Unknown screenshot option: %s\n", argv[i]);
            return 1;
        }
    }

    uint8_t *raw_rgb = NULL;
    int raw_w = 0, raw_h = 0;
    int captured = 0;

    if (backend == BACKEND_AUTO || backend == BACKEND_DRM) {
        const char *drm_dev = device_path ? device_path : "/dev/dri/card0";
        if (drm_capture_rgb(drm_dev, &raw_rgb, &raw_w, &raw_h) == 0) {
            captured = 1;
        } else if (backend == BACKEND_DRM) {
            fprintf(stderr, "DRM frame capture failed on %s\n", drm_dev);
            return 1;
        }
    }

    if (!captured && (backend == BACKEND_AUTO || backend == BACKEND_FB)) {
        const char *fb_dev = device_path;
        if (!fb_dev) {
            fb_dev = (traits->gpu_device[0] != '\0' && strcmp(traits->gpu_device, "na") != 0)
                         ? traits->gpu_device
                         : "/dev/fb0";
        }
        if (fb_capture(fb_dev, &raw_rgb, &raw_w, &raw_h) == 0) {
            captured = 1;
        } else {
            fprintf(stderr, "Framebuffer capture failed on %s\n", fb_dev);
            return 1;
        }
    }

    if (!captured || !raw_rgb) {
        fprintf(stderr, "Failed to capture display frame.\n");
        return 1;
    }

    uint8_t *final_rgb = raw_rgb;
    int final_w = raw_w;
    int final_h = raw_h;

    // Undo the panel rotation so the PNG matches what the player sees.
    // The fb/DRM buffer is stored rotated by screen_rotation degrees CW.
    // image_rotate_rgb(90) applies 90 CCW, which undoes 90 CW.
    int rot = (360 - (traits->screen_rotation % 360)) % 360;
    if (rot != 0) {
        uint8_t *rot_rgb = NULL;
        int rot_w = 0, rot_h = 0;
        if (image_rotate_rgb(raw_rgb, raw_w, raw_h, rot, &rot_rgb, &rot_w, &rot_h) == 0) {
            free(raw_rgb);
            final_rgb = rot_rgb;
            final_w = rot_w;
            final_h = rot_h;
        }
    }


    int ret = 0;
    if (use_base64) {
        uint8_t *png_buf = NULL;
        size_t png_size = 0;
        if (png_encode_rgb_to_mem(final_rgb, final_w, final_h, &png_buf, &png_size) != 0) {
            fprintf(stderr, "PNG memory encoding failed\n");
            free(final_rgb);
            return 1;
        }
        size_t b64_len = 0;
        char *b64_str = base64_encode(png_buf, png_size, &b64_len);
        free(png_buf);
        if (!b64_str) {
            fprintf(stderr, "Base64 encoding failed\n");
            free(final_rgb);
            return 1;
        }
        if (out_path) {
            FILE *f = fopen(out_path, "w");
            if (!f) {
                perror("fopen out_path");
                ret = 1;
            } else {
                fputs(b64_str, f);
                fputc('\n', f);
                fclose(f);
            }
        } else {
            fputs(b64_str, stdout);
            fputc('\n', stdout);
            fflush(stdout);
        }
        free(b64_str);
    } else {
        const char *target_file = out_path ? out_path : "-";
        if (png_encode_rgb_to_file(target_file, final_rgb, final_w, final_h) != 0) {
            fprintf(stderr, "Failed to write PNG output\n");
            ret = 1;
        }
    }

    free(final_rgb);
    return ret;
}

static int cmd_press(int argc, char **argv, const RemoteTraits *traits) {
    if (argc < 3) {
        fprintf(stderr, "Usage: remote press <key> [--duration <ms>]\n");
        return 1;
    }
    const char *key_name = argv[2];
    int duration_ms = 50;

    for (int i = 3; i < argc; i++) {
        if (strcmp(argv[i], "--duration") == 0 && i + 1 < argc) {
            duration_ms = atoi(argv[++i]);
        }
    }

    int keycode = resolve_keycode(key_name, traits);
    if (keycode < 0) {
        fprintf(stderr, "Unrecognized key name or keycode: %s\n", key_name);
        return 1;
    }

    int fd = uinput_open();
    if (fd < 0) {
        fprintf(stderr, "Failed to initialize /dev/uinput virtual device\n");
        return 1;
    }

    int ret = uinput_press(fd, keycode, duration_ms);
    uinput_close(fd);
    return ret;
}

static int cmd_down(int argc, char **argv, const RemoteTraits *traits) {
    if (argc < 3) {
        fprintf(stderr, "Usage: remote down <key>\n");
        return 1;
    }
    int keycode = resolve_keycode(argv[2], traits);
    if (keycode < 0) {
        fprintf(stderr, "Unrecognized key: %s\n", argv[2]);
        return 1;
    }
    int fd = uinput_open();
    if (fd < 0) return 1;
    int ret = uinput_emit(fd, keycode, 1);
    uinput_close(fd);
    return ret;
}

static int cmd_up(int argc, char **argv, const RemoteTraits *traits) {
    if (argc < 3) {
        fprintf(stderr, "Usage: remote up <key>\n");
        return 1;
    }
    int keycode = resolve_keycode(argv[2], traits);
    if (keycode < 0) {
        fprintf(stderr, "Unrecognized key: %s\n", argv[2]);
        return 1;
    }
    int fd = uinput_open();
    if (fd < 0) return 1;
    int ret = uinput_emit(fd, keycode, 0);
    uinput_close(fd);
    return ret;
}

static int cmd_combo(int argc, char **argv, const RemoteTraits *traits) {
    if (argc < 3) {
        fprintf(stderr, "Usage: remote combo <k1,k2,...> [--duration <ms>]\n");
        return 1;
    }
    const char *combo_spec = argv[2];
    int duration_ms = 50;

    for (int i = 3; i < argc; i++) {
        if (strcmp(argv[i], "--duration") == 0 && i + 1 < argc) {
            duration_ms = atoi(argv[++i]);
        }
    }

    int keycodes[16];
    int key_count = 0;

    char buf[256];
    strncpy(buf, combo_spec, sizeof(buf) - 1);
    buf[sizeof(buf) - 1] = '\0';

    char *saveptr = NULL;
    char *token = strtok_r(buf, ",", &saveptr);
    while (token && key_count < 16) {
        while (*token == ' ') token++;
        int code = resolve_keycode(token, traits);
        if (code >= 0) {
            keycodes[key_count++] = code;
        } else {
            fprintf(stderr, "Warning: unknown combo key '%s', skipping\n", token);
        }
        token = strtok_r(NULL, ",", &saveptr);
    }

    if (key_count == 0) {
        fprintf(stderr, "No valid keys in combo: %s\n", combo_spec);
        return 1;
    }

    int fd = uinput_open();
    if (fd < 0) return 1;

    int ret = uinput_combo(fd, keycodes, key_count, duration_ms);
    uinput_close(fd);
    return ret;
}

static int cmd_sequence(int argc, char **argv, const RemoteTraits *traits) {
    if (argc < 3) {
        fprintf(stderr, "Usage: remote sequence <spec>\n");
        return 1;
    }
    int fd = uinput_open();
    if (fd < 0) return 1;

    int ret = uinput_sequence(fd, argv[2], traits);
    uinput_close(fd);
    return ret;
}

static int cmd_info(const RemoteTraits *traits) {
    printf("Minime Remote Hardware Info\n");
    printf("  Screen Rotation: %d deg\n", traits->screen_rotation);
    printf("  Screen Width:    %d px\n", traits->screen_width);
    printf("  Screen Height:   %d px\n", traits->screen_height);
    printf("  GPU Device:      %s\n", traits->gpu_device[0] ? traits->gpu_device : "/dev/fb0");
    printf("Resolved Keycodes:\n");
    printf("  UP: %d   DOWN: %d   LEFT: %d   RIGHT: %d\n",
           traits->key_up, traits->key_down, traits->key_left, traits->key_right);
    printf("  A:  %d   B:    %d   X:    %d   Y:     %d\n",
           traits->key_a, traits->key_b, traits->key_x, traits->key_y);
    printf("  L1: %d   R1:   %d   L2:   %d   R2:    %d\n",
           traits->key_l1, traits->key_r1, traits->key_l2, traits->key_r2);
    printf("  START: %d   SELECT: %d   MENU: %d   POWER: %d\n",
           traits->key_start, traits->key_select, traits->key_menu, traits->key_power);
    printf("  VOL_UP: %d   VOL_DOWN: %d\n",
           traits->key_vol_up, traits->key_vol_down);
    return 0;
}

int main(int argc, char **argv) {
    if (argc < 2) {
        print_usage(argv[0]);
        return 1;
    }

    const char *cmd = argv[1];

    if (strcmp(cmd, "-h") == 0 || strcmp(cmd, "--help") == 0 || strcmp(cmd, "help") == 0) {
        print_usage(argv[0]);
        return 0;
    }

    RemoteTraits traits;
    memset(&traits, 0, sizeof(traits));
    traits_load(&traits);

    if (strcmp(cmd, "screenshot") == 0) {
        return cmd_screenshot(argc, argv, &traits);
    } else if (strcmp(cmd, "press") == 0) {
        return cmd_press(argc, argv, &traits);
    } else if (strcmp(cmd, "down") == 0) {
        return cmd_down(argc, argv, &traits);
    } else if (strcmp(cmd, "up") == 0) {
        return cmd_up(argc, argv, &traits);
    } else if (strcmp(cmd, "combo") == 0) {
        return cmd_combo(argc, argv, &traits);
    } else if (strcmp(cmd, "sequence") == 0) {
        return cmd_sequence(argc, argv, &traits);
    } else if (strcmp(cmd, "info") == 0) {
        return cmd_info(&traits);
    } else {
        fprintf(stderr, "Unknown command: %s\n", cmd);
        print_usage(argv[0]);
        return 1;
    }
}
