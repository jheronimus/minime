/* dmg.c - original Game Boy boot homage */
#include "bootsplash.h"
#include <math.h>

#define SCR_W 640
#define SCR_H 480

static const char WORD[] = "minim\x01";

void audio_dmg(void)
{
    /* Authentic Game Boy startup beep: ~1046.50 Hz then ~2093.00 Hz (C6 and C7 square waves) */
    double t0 = 0.92;
    voice_add(t0,        0.12, 1046.50, WAVE_SQUARE, 0.25, 12.0);
    voice_add(t0 + 0.08, 0.35, 2093.00, WAVE_SQUARE, 0.25, 8.0);
}

void draw_dmg(SDL_Renderer *r, double t)
{
    /* Game Boy LCD olive-brown */
    clear(r, 0x9E, 0x9E, 0x4A);
    g_font_style = 0;

    int scale = 5;
    int spacing = 2;
    int text_w = string_width(WORD, scale, spacing);
    int text_h = 15 * scale;
    int final_x = (SCR_W - text_w) / 2;
    int final_y = (SCR_H - text_h) / 2;
    int start_y = -text_h - 20;
    double land = 0.90;

    double y = final_y;
    if (t < land) {
        double p = t / land;
        p = 1.0 - (1.0 - p) * (1.0 - p);
        y = lerp_d((double)start_y, (double)final_y, p);
    }

    draw_string(r, WORD, final_x, (int)y, scale, spacing, 0x1f, 0x1f, 0x1f);
}
