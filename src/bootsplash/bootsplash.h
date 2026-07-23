/* bootsplash.h - shared declarations for the minime bootsplash */
#ifndef BOOTSPLASH_H
#define BOOTSPLASH_H

#include <SDL.h>
#include <stdint.h>

#define SAMPLE_RATE 44100
#define MAX_VOICES 64

typedef enum { WAVE_SINE, WAVE_SQUARE, WAVE_TRIANGLE, WAVE_NOISE } Wave;

typedef struct {
    double start;
    double end;
    double freq;
    double amp;
    double decay;
    Wave wave;
} Voice;

typedef struct {
    int enabled;
    int mode;
    int modes_mask;
    int allow_skip;
    int volume;
    int debug;
} Config;

typedef struct {
    const char *name;
    double duration;
    void (*draw)(SDL_Renderer *r, double t);
    void (*audio)(void);
} Mode;

extern Config g_cfg;
extern Voice g_voices[MAX_VOICES];
extern int g_voice_count;
extern volatile double g_audio_time;
extern double g_master_amp;

extern const Mode g_modes[];
extern const int g_mode_count;

/* time and math */
double now_sec(void);
double clampd(double x, double lo, double hi);
double lerp_d(double a, double b, double t);
int lerp_i(int a, int b, double t);

/* drawing */
void clear(SDL_Renderer *r, uint8_t rr, uint8_t gg, uint8_t bb);
void set_color(SDL_Renderer *r, uint8_t rr, uint8_t gg, uint8_t bb);
void draw_rect(SDL_Renderer *r, int x, int y, int w, int h);
void draw_line(SDL_Renderer *r, int x1, int y1, int x2, int y2);
void hsl_to_rgb(float h, float s, float l, uint8_t *rr, uint8_t *gg, uint8_t *bb);

/* audio */
void voices_clear(void);
void voice_add(double start, double dur, double freq, Wave wave, double amp, double decay);
double wave_sample(Wave w, double phase);
double env_decay(double t, double decay);
void audio_callback(void *userdata, Uint8 *stream, int len);

/* font */
extern int g_font_style;
int glyph_width(char c);
int string_width(const char *s, int scale, int spacing);
int string_char_x(const char *s, int idx, int scale, int spacing);
void draw_string(SDL_Renderer *r, const char *s, int x, int y, int scale,
                 int spacing, uint8_t rr, uint8_t gg, uint8_t bb);
void draw_char(SDL_Renderer *r, char c, int x, int y, int scale,
               uint8_t rr, uint8_t gg, uint8_t bb);
void draw_char_alpha(SDL_Renderer *r, char c, int x, int y, int scale,
                     uint8_t rr, uint8_t gg, uint8_t bb, uint8_t alpha);
void draw_char_shadow(SDL_Renderer *r, char c, int x, int y, int scale,
                      uint8_t rr, uint8_t gg, uint8_t bb);

/* platform modules */
void draw_dmg(SDL_Renderer *r, double t);
void audio_dmg(void);
void draw_gbc(SDL_Renderer *r, double t);
void audio_gbc(void);
void draw_gba(SDL_Renderer *r, double t);
void audio_gba(void);

/* config */
void config_load(const char *path, Config *cfg);
int config_cycle_next(int count, const char *state_path);

#endif /* BOOTSPLASH_H */
