#include "traits.h"
#include "fb.h"
#include "rotate.h"
#include "png_enc.h"
#include "base64.h"
#include "uinput.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void print_usage(const char *prog) {
    fprintf(stderr, "Minime Remote Diagnostics & Input Emulation Tool\n");
    fprintf(stderr, "Usage:\n");
    fprintf(stderr, "  %s screenshot [options]\n", prog);
    fprintf(stderr, "      --out <path>       Save PNG to file (default: write to stdout)\n");
    fprintf(stderr, "      --base64           Output Base64-encoded PNG string\n");
    fprintf(stderr, "      --raw              Do not apply traits screen_rotation\n");
    fprintf(stderr, "      --device <path>    Override framebuffer device (default: from traits or /dev/fb0)\n");
    fprintf(stderr, "\n");
    fprintf(stderr, "  %s press <key> [--duration <ms>]\n", prog);
    fprintf(stderr, "      Simulate a single key press and release (default duration: 50ms)\n");
    fprintf(stderr, "\n");
    fprintf(stderr, "  %s down <key>\n", prog);
    fprintf(stderr, "      Hold key down\n");
    fprintf(stderr, "\n");
    fprintf(stderr, "  %s up <key>\n", prog);
    fprintf(stderr, "      Release key\n");
    fprintf(stderr, "\n");
    fprintf(stderr, "  %s combo <k1,k2,...> [--duration <ms>]\n", prog);
    fprintf(stderr, "      Simulate simultaneous key combo (e.g. MENU,X)\n");
    fprintf(stderr, "\n");
    fprintf(stderr, "  %s sequence <spec>\n", prog);
    fprintf(stderr, "      Execute timed sequence (e.g. 'UP:100,WAIT:200,A:50,WAIT:500,START:50')\n");
    fprintf(stderr, "\n");
    fprintf(stderr, "  %s info\n", prog);
    fprintf(stderr, "      Display active hardware traits (screen rotation, dimensions, keymap)\n");
    fprintf(stderr, "\n");
    fprintf(stderr, "Logical Button Names:\n");
    fprintf(stderr, "  D-Pad:      UP, DOWN, LEFT, RIGHT\n");
    fprintf(stderr, "  Face:       A, B, X, Y, C, Z\n");
    fprintf(stderr, "  Shoulders:  L1, R1, L2, R2, L3, R3\n");
    fprintf(stderr, "  System:     START, SELECT, MENU, POWER, VOL_UP, VOL_DOWN\n");
    fprintf(stderr, "  Raw Codes:  Numeric keycodes (e.g. 304, 305, 103) are also supported\n");
}

static int cmd_screenshot(int argc, char **argv, const RemoteTraits *traits) {
    const char *out_path = "-";
    const char *fb_dev = traits->gpu_device[0] ? traits->gpu_device : "/dev/fb0";
    int raw = 0;
    int base64_mode = 0;

    for (int i = 0; i < argc; i++) {
        if (strcmp(argv[i], "--raw") == 0) {
            raw = 1;
        } else if (strcmp(argv[i], "--base64") == 0) {
            base64_mode = 1;
        } else if (strcmp(argv[i], "--out") == 0 && i + 1 < argc) {
            out_path = argv[++i];
        } else if (strcmp(argv[i], "--device") == 0 && i + 1 < argc) {
            fb_dev = argv[++i];
        }
    }

    uint8_t *raw_rgb = NULL;
    int src_w = 0, src_h = 0;
    if (fb_capture(fb_dev, &raw_rgb, &src_w, &src_h) != 0) {
        fprintf(stderr, "Error: Failed to capture framebuffer '%s'\n", fb_dev);
        return 1;
    }

    uint8_t *final_rgb = NULL;
    int final_w = 0, final_h = 0;

    int rot = raw ? 0 : traits->screen_rotation;
    if (image_rotate_rgb(raw_rgb, src_w, src_h, rot, &final_rgb, &final_w, &final_h) != 0) {
        fprintf(stderr, "Error: Failed to process image orientation\n");
        free(raw_rgb);
        return 1;
    }
    free(raw_rgb);

    int ret = 0;
    if (base64_mode) {
        uint8_t *png_data = NULL;
        size_t png_size = 0;
        if (png_encode_rgb_to_mem(final_rgb, final_w, final_h, &png_data, &png_size) != 0) {
            fprintf(stderr, "Error: Failed to encode PNG\n");
            free(final_rgb);
            return 1;
        }
        size_t b64_len = 0;
        char *b64_str = base64_encode(png_data, png_size, &b64_len);
        free(png_data);

        if (!b64_str) {
            fprintf(stderr, "Error: Base64 encoding failed\n");
            free(final_rgb);
            return 1;
        }

        if (strcmp(out_path, "-") == 0) {
            printf("%s\n", b64_str);
            fflush(stdout);
        } else {
            FILE *f = fopen(out_path, "w");
            if (f) {
                fprintf(f, "%s\n", b64_str);
                fclose(f);
            } else {
                perror("fopen output file");
                ret = 1;
            }
        }
        free(b64_str);
    } else {
        if (png_encode_rgb_to_file(out_path, final_rgb, final_w, final_h) != 0) {
            fprintf(stderr, "Error: Failed to encode/write PNG\n");
            ret = 1;
        }
    }

    free(final_rgb);
    return ret;
}

static int cmd_press(int argc, char **argv, const RemoteTraits *traits) {
    if (argc < 1) {
        fprintf(stderr, "Error: Missing key name\n");
        return 1;
    }
    const char *key_name = argv[0];
    int duration = 50;

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--duration") == 0 && i + 1 < argc) {
            duration = atoi(argv[++i]);
        }
    }

    int code = resolve_keycode(key_name, traits);
    if (code <= 0) {
        fprintf(stderr, "Error: Unknown key '%s'\n", key_name);
        return 1;
    }

    int fd = uinput_open();
    if (fd < 0) return 1;

    int ret = uinput_press(fd, code, duration);
    uinput_close(fd);
    return (ret == 0) ? 0 : 1;
}

static int cmd_down(int argc, char **argv, const RemoteTraits *traits) {
    if (argc < 1) {
        fprintf(stderr, "Error: Missing key name\n");
        return 1;
    }
    int code = resolve_keycode(argv[0], traits);
    if (code <= 0) {
        fprintf(stderr, "Error: Unknown key '%s'\n", argv[0]);
        return 1;
    }
    int fd = uinput_open();
    if (fd < 0) return 1;
    int ret = uinput_emit(fd, code, 1);
    uinput_close(fd);
    return (ret == 0) ? 0 : 1;
}

static int cmd_up(int argc, char **argv, const RemoteTraits *traits) {
    if (argc < 1) {
        fprintf(stderr, "Error: Missing key name\n");
        return 1;
    }
    int code = resolve_keycode(argv[0], traits);
    if (code <= 0) {
        fprintf(stderr, "Error: Unknown key '%s'\n", argv[0]);
        return 1;
    }
    int fd = uinput_open();
    if (fd < 0) return 1;
    int ret = uinput_emit(fd, code, 0);
    uinput_close(fd);
    return (ret == 0) ? 0 : 1;
}

static int cmd_combo(int argc, char **argv, const RemoteTraits *traits) {
    if (argc < 1) {
        fprintf(stderr, "Error: Missing combo keys\n");
        return 1;
    }
    char *combo_spec = strdup(argv[0]);
    int duration = 50;

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--duration") == 0 && i + 1 < argc) {
            duration = atoi(argv[++i]);
        }
    }

    int keys[16];
    int count = 0;
    char *saveptr = NULL;
    char *token = strtok_r(combo_spec, ",+", &saveptr);
    while (token && count < 16) {
        while (*token == ' ') token++;
        int code = resolve_keycode(token, traits);
        if (code > 0) {
            keys[count++] = code;
        } else {
            fprintf(stderr, "Error: Unknown key in combo: '%s'\n", token);
            free(combo_spec);
            return 1;
        }
        token = strtok_r(NULL, ",+", &saveptr);
    }
    free(combo_spec);

    if (count == 0) {
        fprintf(stderr, "Error: No valid keys in combo\n");
        return 1;
    }

    int fd = uinput_open();
    if (fd < 0) return 1;
    int ret = uinput_combo(fd, keys, count, duration);
    uinput_close(fd);
    return (ret == 0) ? 0 : 1;
}

static int cmd_sequence(int argc, char **argv, const RemoteTraits *traits) {
    if (argc < 1) {
        fprintf(stderr, "Error: Missing sequence specification\n");
        return 1;
    }
    int fd = uinput_open();
    if (fd < 0) return 1;
    int ret = uinput_sequence(fd, argv[0], traits);
    uinput_close(fd);
    return (ret == 0) ? 0 : 1;
}

static int cmd_info(const RemoteTraits *t) {
    printf("Minime Remote Hardware Info\n");
    printf("  Screen Rotation: %d deg\n", t->screen_rotation);
    printf("  Screen Width:    %d px\n", t->screen_width);
    printf("  Screen Height:   %d px\n", t->screen_height);
    printf("  GPU Device:      %s\n", t->gpu_device);
    printf("Resolved Keycodes:\n");
    printf("  UP: %-4d  DOWN: %-4d  LEFT: %-4d  RIGHT: %-4d\n", t->key_up, t->key_down, t->key_left, t->key_right);
    printf("  A:  %-4d  B:    %-4d  X:    %-4d  Y:     %-4d\n", t->key_a, t->key_b, t->key_x, t->key_y);
    printf("  L1: %-4d  R1:   %-4d  L2:   %-4d  R2:    %-4d\n", t->key_l1, t->key_r1, t->key_l2, t->key_r2);
    printf("  START: %-4d  SELECT: %-4d  MENU: %-4d  POWER: %-4d\n", t->key_start, t->key_select, t->key_menu, t->key_power);
    printf("  VOL_UP: %-4d  VOL_DOWN: %-4d\n", t->key_vol_up, t->key_vol_down);
    return 0;
}

int main(int argc, char **argv) {
    if (argc < 2 || strcmp(argv[1], "--help") == 0 || strcmp(argv[1], "-h") == 0) {
        print_usage(argv[0]);
        return (argc < 2) ? 1 : 0;
    }

    RemoteTraits traits;
    traits_load(&traits);

    const char *cmd = argv[1];
    if (strcmp(cmd, "screenshot") == 0 || strcmp(cmd, "snap") == 0) {
        return cmd_screenshot(argc - 2, argv + 2, &traits);
    } else if (strcmp(cmd, "press") == 0) {
        return cmd_press(argc - 2, argv + 2, &traits);
    } else if (strcmp(cmd, "down") == 0) {
        return cmd_down(argc - 2, argv + 2, &traits);
    } else if (strcmp(cmd, "up") == 0) {
        return cmd_up(argc - 2, argv + 2, &traits);
    } else if (strcmp(cmd, "combo") == 0) {
        return cmd_combo(argc - 2, argv + 2, &traits);
    } else if (strcmp(cmd, "sequence") == 0 || strcmp(cmd, "seq") == 0) {
        return cmd_sequence(argc - 2, argv + 2, &traits);
    } else if (strcmp(cmd, "info") == 0 || strcmp(cmd, "status") == 0) {
        return cmd_info(&traits);
    } else {
        fprintf(stderr, "Error: Unknown command '%s'\n\n", cmd);
        print_usage(argv[0]);
        return 1;
    }
}
