#ifndef TRAITS_H
#define TRAITS_H

#include <stddef.h>

typedef struct {
    int screen_rotation;
    int screen_width;
    int screen_height;
    char gpu_device[128];

    int key_up;
    int key_down;
    int key_left;
    int key_right;

    int key_a;
    int key_b;
    int key_c;
    int key_x;
    int key_y;
    int key_z;

    int key_l1;
    int key_r1;
    int key_l2;
    int key_r2;
    int key_l3;
    int key_r3;

    int key_start;
    int key_select;
    int key_menu;
    int key_power;

    int key_vol_up;
    int key_vol_down;
} RemoteTraits;

/*
 * Load traits from /mnt/sdcard/.minime/traits, /etc/minime/traits, or /usr/share/minime/traits/platform.ini.
 * Falls back to standard defaults if files are absent or unreadable.
 */
int traits_load(RemoteTraits *t);

#endif /* TRAITS_H */
