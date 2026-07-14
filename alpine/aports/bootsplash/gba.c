/* gba.c - Game Boy Advance boot homage */
#include "bootsplash.h"
#include <math.h>

#define SCR_W 640
#define SCR_H 480

static const char WORD[] = "minim\x01";

void audio_gba(void)
{
    /* Warm Bb3 and F3 drone underneath */
    voice_add(0.05, 1.80, 174.61, WAVE_SINE, 0.12, 1.0);
    voice_add(0.05, 1.80, 233.08, WAVE_SINE, 0.10, 1.0);

    /* Ascending Fmaj9 arpeggio (triangle waves) */
    double base = 0.05;
    double per = 0.07;
    double freqs[6] = { 349.23, 440.00, 523.25, 659.25, 783.99, 1046.50 };

    for (int i = 0; i < 6; i++) {
        voice_add(base + i * per, 0.30, freqs[i], WAVE_TRIANGLE, 0.16, 4.0);
    }

    /* Bright high-pitched F6/A6/C7 chime at the end of the arpeggio */
    double chime = base + 6.0 * per + 0.12;
    voice_add(chime, 0.80, 1396.91, WAVE_SINE, 0.18, 3.0);
    voice_add(chime, 0.80, 1760.00, WAVE_SINE, 0.15, 3.0);
    voice_add(chime, 0.80, 2093.00, WAVE_SINE, 0.12, 3.0);
}

void draw_gba(SDL_Renderer *r, double t)
{
    clear(r, 255, 255, 255);
    g_font_style = 1;

    int scale = 6;
    int spacing = 3;
    int text_w = string_width(WORD, scale, spacing);
    int text_h = 15 * scale;
    int final_x = (SCR_W - text_w) / 2 - 1 * scale;
    int final_y = (SCR_H - text_h) / 2;
    double base = 0.10;
    double per = 0.12;
    double settle = 0.30;

    /* Scattered starting positions for each letter (converging entry) */
    static const int start_dx[6] = { -220, -100, 150, 220, -180, 250 };
    static const int start_dy[6] = { -150,  200, -200, 180, -100, 150 };

    double all_landed = base + 5.0 * per + settle;

    for (int i = 0; WORD[i]; i++) {
        double appear = base + i * per;
        if (t < appear)
            continue;

        double u = clampd((t - appear) / settle, 0.0, 1.0);
        int final_char_x = final_x + string_char_x(WORD, i, scale, spacing);
        int x0 = final_char_x + start_dx[i];
        int y0 = final_y + start_dy[i];
        int x = lerp_i(x0, final_char_x, u);
        int y = lerp_i(y0, final_y, u);

        /* Blue-to-magenta horizontal gradient across the word mark */
        float factor = (float)i / 5.0f;
        uint8_t final_r = (uint8_t)lerp_i(0, 220, factor);
        uint8_t final_g = (uint8_t)lerp_i(80, 20, factor);
        uint8_t final_b = (uint8_t)lerp_i(220, 150, factor);

        /* Rainbow cycling color during flight */
        uint8_t rain_r, rain_g, rain_b;
        float hue = (float)(i * 60.0f + t * 400.0f);
        while (hue >= 360.0f)
            hue -= 360.0f;
        hsl_to_rgb(hue, 1.0f, 0.5f, &rain_r, &rain_g, &rain_b);

        /* Interpolate from rainbow to final gradient color based on settle progress */
        uint8_t rr = (uint8_t)lerp_i((int)rain_r, (int)final_r, u);
        uint8_t gg = (uint8_t)lerp_i((int)rain_g, (int)final_g, u);
        uint8_t bb = (uint8_t)lerp_i((int)rain_b, (int)final_b, u);

        /* Semi-transparent during flight, solid when settled */
        uint8_t alpha = (u < 1.0) ? (uint8_t)lerp_i(100, 255, u) : 255;

        /* Hue-shifting sheen sweep passing over letters after they all land */
        if (t > all_landed) {
            double st = t - all_landed;
            double dur = 0.80;
            if (st < dur) {
                double st_ratio = st / dur;
                int sx = final_x - 30 + (int)((text_w + 60) * st_ratio);
                int char_cx = final_char_x + (glyph_width(WORD[i]) * scale) / 2;
                double dist = fabs((double)(char_cx - sx));
                double sweep_w = 60.0;
                if (dist < sweep_w) {
                    double f = 1.0 - (dist / sweep_w);
                    f = f * f; /* sharper peak */
                    rr = (uint8_t)lerp_i(rr, 255, f);
                    gg = (uint8_t)lerp_i(gg, 255, f);
                    bb = (uint8_t)lerp_i(bb, 200, f); /* warm gold/white shine */
                }
            }
        }

        /* purple-ish 3D drop shadow like the GBA "GAME BOY" logo */
        uint8_t sr = (uint8_t)lerp_i(0, (int)final_r, 0.35);
        uint8_t sg = (uint8_t)lerp_i(0, (int)final_g, 0.35);
        uint8_t sb = (uint8_t)lerp_i(0, (int)final_b, 0.35);
        draw_char_shadow(r, WORD[i], x, y, scale, sr, sg, sb);

        if (alpha < 255) {
            SDL_SetRenderDrawBlendMode(r, SDL_BLENDMODE_BLEND);
            draw_char_alpha(r, WORD[i], x, y, scale, rr, gg, bb, alpha);
            SDL_SetRenderDrawBlendMode(r, SDL_BLENDMODE_NONE);
        } else {
            draw_char(r, WORD[i], x, y, scale, rr, gg, bb);
        }
    }
}
