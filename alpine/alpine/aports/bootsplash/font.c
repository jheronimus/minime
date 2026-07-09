/* font.c - baked pixel font for the minimē wordmark
 *
 * Glyphs are rendered from "Public Pixel" by GGBotNet (CC0 1.0,
 * https://ggbot.itch.io/public-pixel-font) and baked into this source as
 * uint16_t row bitmaps, so no external font asset is needed at runtime.
 *
 * Two styles share the same Public Pixel letterforms:
 *   style 0 (DMG)    - upright
 *   style 1 (GBC/GBA) - forward-italic (shear baked into the bitmaps)
 * The macron in ē is the font's native U+0113 glyph (no manual macron).
 *
 * Each glyph is a 15-row cell; the letterform sits on a shared baseline at
 * row 10 so letters of different heights (i/ē vs m/n/e) align and the word
 * stays vertically centered.  Bit 15 of a row is the leftmost pixel column.
 */
#include "bootsplash.h"
#include <stdint.h>

int g_font_style = 0; /* 0 = upright (DMG), 1 = italic (GBC/GBA) */

/* ======================================================================== */
/* style 0 - upright (DMG)                                                   */
/* ======================================================================== */

static const uint16_t GLYPH_M_UP[15] = {
    0x0000, 0x0000, 0x0000,
    0x0000, 0x0000, 0x0000,
    0xFC00, 0xD600, 0xD600,
    0xD600, 0xD600, 0x0000,
    0x0000, 0x0000, 0x0000
};

static const uint16_t GLYPH_I_UP[15] = {
    0x0000, 0x0000, 0x0000,
    0x0000, 0x1800, 0x0000,
    0x7800, 0x1800, 0x1800,
    0x1800, 0xFE00, 0x0000,
    0x0000, 0x0000, 0x0000
};

static const uint16_t GLYPH_N_UP[15] = {
    0x0000, 0x0000, 0x0000,
    0x0000, 0x0000, 0x0000,
    0xFC00, 0xC600, 0xC600,
    0xC600, 0xC600, 0x0000,
    0x0000, 0x0000, 0x0000
};

static const uint16_t GLYPH_E_UP[15] = {
    0x0000, 0x0000, 0x0000,
    0x0000, 0x0000, 0x0000,
    0x7C00, 0xC600, 0xFE00,
    0xC000, 0x7C00, 0x0000,
    0x0000, 0x0000, 0x0000
};

static const uint16_t GLYPH_E_MACRON_UP[15] = {
    0x0000, 0x0000, 0x0000,
    0x0000, 0x7C00, 0x0000,
    0x7C00, 0xC600, 0xFE00,
    0xC000, 0x7C00, 0x0000,
    0x0000, 0x0000, 0x0000
};

/* ======================================================================== */
/* style 1 - forward italic (GBC/GBA); shear is baked into the bitmaps      */
/* ======================================================================== */

static const uint16_t GLYPH_M_IT[15] = {
    0x0000, 0x0000, 0x0000,
    0x0000, 0x0000, 0x0000,
    0x3F00, 0x6B00, 0x6B00,
    0xD600, 0xD600, 0x0000,
    0x0000, 0x0000, 0x0000
};

static const uint16_t GLYPH_I_IT[15] = {
    0x0000, 0x0000, 0x0000,
    0x0000, 0x0300, 0x0000,
    0x1E00, 0x0C00, 0x0C00,
    0x1800, 0xFE00, 0x0000,
    0x0000, 0x0000, 0x0000
};

static const uint16_t GLYPH_N_IT[15] = {
    0x0000, 0x0000, 0x0000,
    0x0000, 0x0000, 0x0000,
    0x3F00, 0x6300, 0x6300,
    0xC600, 0xC600, 0x0000,
    0x0000, 0x0000, 0x0000
};

static const uint16_t GLYPH_E_IT[15] = {
    0x0000, 0x0000, 0x0000,
    0x0000, 0x0000, 0x0000,
    0x1F00, 0x6300, 0x7F00,
    0xC000, 0x7C00, 0x0000,
    0x0000, 0x0000, 0x0000
};

static const uint16_t GLYPH_E_MACRON_IT[15] = {
    0x0000, 0x0000, 0x0000,
    0x0000, 0x0F80, 0x0000,
    0x1F00, 0x6300, 0x7F00,
    0xC000, 0x7C00, 0x0000,
    0x0000, 0x0000, 0x0000
};

static const uint16_t GLYPH_SPACE[15] = { 0 };

/* ======================================================================== */
/* metrics & drawing                                                         */
/* ======================================================================== */

int glyph_width(char c)
{
    /* italic glyphs are wider because the shear is baked in */
    int it = (g_font_style == 1);
    switch (c) {
    case 'm':
    case 'M':
        return it ? 10 : 8;
    case 'i':
    case 'I':
        return it ? 11 : 8;
    case 'n':
    case 'N':
        return it ? 10 : 8;
    case 'e':
    case 'E':
        return it ? 10 : 8;
    case 0x01: /* ē */
        return it ? 11 : 8;
    default:
        return 0;
    }
}

static const uint16_t *glyph_for(char c)
{
    int it = (g_font_style == 1);
    switch (c) {
    case 'm':
    case 'M':
        return it ? GLYPH_M_IT : GLYPH_M_UP;
    case 'i':
    case 'I':
        return it ? GLYPH_I_IT : GLYPH_I_UP;
    case 'n':
    case 'N':
        return it ? GLYPH_N_IT : GLYPH_N_UP;
    case 'e':
    case 'E':
        return it ? GLYPH_E_IT : GLYPH_E_UP;
    case 0x01: /* ē */
        return it ? GLYPH_E_MACRON_IT : GLYPH_E_MACRON_UP;
    default:
        return GLYPH_SPACE;
    }
}

int string_width(const char *s, int scale, int spacing)
{
    int w = 0;
    int len = 0;
    for (int i = 0; s[i]; i++) {
        w += glyph_width(s[i]) * scale;
        len++;
    }
    if (len > 0)
        w += (len - 1) * spacing;
    return w;
}

int string_char_x(const char *s, int idx, int scale, int spacing)
{
    int x = 0;
    for (int i = 0; i < idx; i++) {
        x += glyph_width(s[i]) * scale + spacing;
    }
    return x;
}

void draw_char(SDL_Renderer *r, char c, int x, int y, int scale,
               uint8_t rr, uint8_t gg, uint8_t bb)
{
    const uint16_t *g = glyph_for(c);
    int w = glyph_width(c);

    set_color(r, rr, gg, bb);
    for (int row = 0; row < 15; row++) {
        uint16_t bits = g[row];
        for (int col = 0; col < w; col++) {
            if (bits & (1 << (15 - col)))
                draw_rect(r, x + col * scale, y + row * scale, scale, scale);
        }
    }
}

void draw_char_alpha(SDL_Renderer *r, char c, int x, int y, int scale,
                     uint8_t rr, uint8_t gg, uint8_t bb, uint8_t alpha)
{
    const uint16_t *g = glyph_for(c);
    int w = glyph_width(c);

    SDL_SetRenderDrawColor(r, rr, gg, bb, alpha);
    for (int row = 0; row < 15; row++) {
        uint16_t bits = g[row];
        for (int col = 0; col < w; col++) {
            if (bits & (1 << (15 - col)))
                draw_rect(r, x + col * scale, y + row * scale, scale, scale);
        }
    }
}

void draw_char_shadow(SDL_Renderer *r, char c, int x, int y, int scale,
                      uint8_t rr, uint8_t gg, uint8_t bb)
{
    const uint16_t *g = glyph_for(c);
    int w = glyph_width(c);

    SDL_SetRenderDrawColor(r, rr, gg, bb, 255);
    for (int row = 0; row < 15; row++) {
        uint16_t bits = g[row];
        /* shadow drops down-right by one scaled pixel */
        for (int col = 0; col < w; col++) {
            if (bits & (1 << (15 - col))) {
                draw_rect(r, x + col * scale + scale,
                          y + row * scale + scale, scale, scale);
            }
        }
    }
}

void draw_string(SDL_Renderer *r, const char *s, int x, int y, int scale,
                 int spacing, uint8_t rr, uint8_t gg, uint8_t bb)
{
    int cur_x = x;
    for (int i = 0; s[i]; i++) {
        draw_char(r, s[i], cur_x, y, scale, rr, gg, bb);
        cur_x += glyph_width(s[i]) * scale + spacing;
    }
}