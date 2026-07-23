/* gbc.c - Game Boy Color boot homage */
#include "bootsplash.h"
#include <math.h>

#define SCR_W 640
#define SCR_H 480
#define FINAL_R 68
#define FINAL_G 121
#define FINAL_B 224

static const char WORD[] = "minim\x01";

void audio_gbc(void)
{
    /* Authentic Game Boy Color startup beep: ~1046.50 Hz then ~2093.00 Hz (C6 and C7 square waves) */
    double t0 = 1.00;
    voice_add(t0,        0.12, 1046.50, WAVE_SQUARE, 0.25, 12.0);
    voice_add(t0 + 0.08, 0.35, 2093.00, WAVE_SQUARE, 0.25, 8.0);
}

void draw_gbc(SDL_Renderer *r, double t)
{
    clear(r, 255, 255, 255);
    g_font_style = 1;

    int scale = 6;
    int spacing = 3;
    int text_w = string_width(WORD, scale, spacing);
    int text_h = 15 * scale;
    int final_x = (SCR_W - text_w) / 2;
    int final_y = (SCR_H - text_h) / 2;
    double base = 0.10;
    double per_letter = 0.12;
    double settle = 0.25;

    for (int i = 0; WORD[i]; i++) {
        double appear = base + i * per_letter;
        if (t < appear)
            continue;

        double u = clampd((t - appear) / settle, 0.0, 1.0);
        uint8_t r1, g1, b1;
        hsl_to_rgb((float)(i * 60), 1.0f, 0.5f, &r1, &g1, &b1);

        uint8_t rr = (uint8_t)lerp_i((int)r1, FINAL_R, u);
        uint8_t gg = (uint8_t)lerp_i((int)g1, FINAL_G, u);
        uint8_t bb = (uint8_t)lerp_i((int)b1, FINAL_B, u);

        int yoff = (int)(lerp_d(-15.0, 0.0, u));
        int char_x = final_x + string_char_x(WORD, i, scale, spacing);
        int char_y = final_y + yoff;

        /* black 3D drop shadow like the GBC "GAME BOY" logo */
        draw_char_shadow(r, WORD[i], char_x, char_y, scale, 0x00, 0x00, 0x00);
        draw_char(r, WORD[i], char_x, char_y, scale, rr, gg, bb);
    }
}
