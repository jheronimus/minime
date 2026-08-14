#include "traits.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <linux/input.h>

static void set_defaults(RemoteTraits *t) {
    memset(t, 0, sizeof(*t));
    t->screen_rotation = 0;
    t->screen_width = 640;
    t->screen_height = 480;
    strncpy(t->gpu_device, "/dev/fb0", sizeof(t->gpu_device) - 1);

    t->key_up = KEY_UP;         // 103
    t->key_down = KEY_DOWN;     // 108
    t->key_left = KEY_LEFT;     // 105
    t->key_right = KEY_RIGHT;   // 106

    t->key_a = BTN_EAST;        // 305
    t->key_b = BTN_SOUTH;       // 304
    t->key_c = BTN_C;           // 306
    t->key_x = BTN_NORTH;       // 307
    t->key_y = BTN_WEST;        // 308
    t->key_z = BTN_Z;           // 309

    t->key_l1 = BTN_TL;         // 310
    t->key_r1 = BTN_TR;         // 311
    t->key_l2 = BTN_TL2;        // 312
    t->key_r2 = BTN_TR2;        // 313
    t->key_l3 = BTN_THUMBL;     // 317
    t->key_r3 = BTN_THUMBR;     // 318

    t->key_start = BTN_START;   // 315
    t->key_select = BTN_SELECT; // 314
    t->key_menu = BTN_MODE;     // 316
    t->key_power = KEY_POWER;   // 116

    t->key_vol_up = KEY_VOLUMEUP;     // 115
    t->key_vol_down = KEY_VOLUMEDOWN; // 114
}

static char *trim(char *s) {
    while (isspace((unsigned char)*s)) s++;
    if (*s == 0) return s;
    char *end = s + strlen(s) - 1;
    while (end > s && isspace((unsigned char)*end)) end--;
    end[1] = '\0';
    return s;
}

static int parse_file(const char *path, RemoteTraits *t) {
    FILE *f = fopen(path, "r");
    if (!f) return -1;

    char line[256];
    while (fgets(line, sizeof(line), f)) {
        char *p = trim(line);
        if (*p == '\0' || *p == '#' || *p == ';' || *p == '[') continue;

        char *eq = strchr(p, '=');
        if (!eq) continue;
        *eq = '\0';
        char *key = trim(p);
        char *val = trim(eq + 1);

        if (strcmp(key, "screen_rotation") == 0) t->screen_rotation = atoi(val);
        else if (strcmp(key, "screen_width") == 0) t->screen_width = atoi(val);
        else if (strcmp(key, "screen_height") == 0) t->screen_height = atoi(val);
        else if (strcmp(key, "gpu_device") == 0) strncpy(t->gpu_device, val, sizeof(t->gpu_device) - 1);
        else if (strcmp(key, "key_up") == 0) t->key_up = atoi(val);
        else if (strcmp(key, "key_down") == 0) t->key_down = atoi(val);
        else if (strcmp(key, "key_left") == 0) t->key_left = atoi(val);
        else if (strcmp(key, "key_right") == 0) t->key_right = atoi(val);
        else if (strcmp(key, "key_a") == 0) t->key_a = atoi(val);
        else if (strcmp(key, "key_b") == 0) t->key_b = atoi(val);
        else if (strcmp(key, "key_c") == 0) t->key_c = atoi(val);
        else if (strcmp(key, "key_x") == 0) t->key_x = atoi(val);
        else if (strcmp(key, "key_y") == 0) t->key_y = atoi(val);
        else if (strcmp(key, "key_z") == 0) t->key_z = atoi(val);
        else if (strcmp(key, "key_l1") == 0) t->key_l1 = atoi(val);
        else if (strcmp(key, "key_r1") == 0) t->key_r1 = atoi(val);
        else if (strcmp(key, "key_l2") == 0) t->key_l2 = atoi(val);
        else if (strcmp(key, "key_r2") == 0) t->key_r2 = atoi(val);
        else if (strcmp(key, "key_l3") == 0) t->key_l3 = atoi(val);
        else if (strcmp(key, "key_r3") == 0) t->key_r3 = atoi(val);
        else if (strcmp(key, "key_start") == 0) t->key_start = atoi(val);
        else if (strcmp(key, "key_select") == 0) t->key_select = atoi(val);
        else if (strcmp(key, "key_menu") == 0) t->key_menu = atoi(val);
        else if (strcmp(key, "key_power") == 0) t->key_power = atoi(val);
        else if (strcmp(key, "key_vol_up") == 0) t->key_vol_up = atoi(val);
        else if (strcmp(key, "key_vol_down") == 0) t->key_vol_down = atoi(val);
    }
    fclose(f);
    return 0;
}

int traits_load(RemoteTraits *t) {
    set_defaults(t);

    static const char *paths[] = {
        "/mnt/sdcard/.minime/traits",
        "/usr/share/minime/traits/platform.ini",
        "/etc/minime/traits"
    };

    for (size_t i = 0; i < sizeof(paths)/sizeof(paths[0]); i++) {
        if (parse_file(paths[i], t) == 0) {
            return 0;
        }
    }
    return 0; // default values applied
}
