/* common.c - utilities, audio callback, and config parsing */
#include "bootsplash.h"
#include <math.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>

Config g_cfg;
Voice g_voices[MAX_VOICES];
int g_voice_count;
volatile double g_audio_time;
double g_master_amp = 1.0;

double now_sec(void)
{
    return (double)SDL_GetTicks() / 1000.0;
}

double clampd(double x, double lo, double hi)
{
    if (x < lo)
        return lo;
    if (x > hi)
        return hi;
    return x;
}

double lerp_d(double a, double b, double t)
{
    return a + (b - a) * clampd(t, 0.0, 1.0);
}

int lerp_i(int a, int b, double t)
{
    return (int)lerp_d((double)a, (double)b, clampd(t, 0.0, 1.0));
}

void clear(SDL_Renderer *r, uint8_t rr, uint8_t gg, uint8_t bb)
{
    SDL_SetRenderDrawColor(r, rr, gg, bb, 255);
    SDL_RenderClear(r);
}

void set_color(SDL_Renderer *r, uint8_t rr, uint8_t gg, uint8_t bb)
{
    SDL_SetRenderDrawColor(r, rr, gg, bb, 255);
}

void draw_rect(SDL_Renderer *r, int x, int y, int w, int h)
{
    SDL_Rect rect = { x, y, w, h };
    SDL_RenderFillRect(r, &rect);
}

void draw_line(SDL_Renderer *r, int x1, int y1, int x2, int y2)
{
    SDL_RenderDrawLine(r, x1, y1, x2, y2);
}

void hsl_to_rgb(float h, float s, float l, uint8_t *rr, uint8_t *gg, uint8_t *bb)
{
    float c = (1.0f - fabsf(2.0f * l - 1.0f)) * s;
    float x = c * (1.0f - fabsf(fmodf(h / 60.0f, 2.0f) - 1.0f));
    float m = l - c / 2.0f;
    float rp = 0.0f, gp = 0.0f, bp = 0.0f;

    if (h < 60.0f) {
        rp = c; gp = x;
    } else if (h < 120.0f) {
        rp = x; gp = c;
    } else if (h < 180.0f) {
        gp = c; bp = x;
    } else if (h < 240.0f) {
        gp = x; bp = c;
    } else if (h < 300.0f) {
        rp = x; bp = c;
    } else {
        rp = c; bp = x;
    }

    *rr = (uint8_t)clampd((rp + m) * 255.0, 0.0, 255.0);
    *gg = (uint8_t)clampd((gp + m) * 255.0, 0.0, 255.0);
    *bb = (uint8_t)clampd((bp + m) * 255.0, 0.0, 255.0);
}

void voices_clear(void)
{
    g_voice_count = 0;
}

void voice_add(double start, double dur, double freq, Wave wave, double amp, double decay)
{
    if (g_voice_count >= MAX_VOICES)
        return;
    Voice *v = &g_voices[g_voice_count++];
    v->start = start;
    v->end = start + dur;
    v->freq = freq;
    v->wave = wave;
    v->amp = amp;
    v->decay = decay;
}

double wave_sample(Wave w, double phase)
{
    phase = fmod(phase, 1.0);
    if (phase < 0.0)
        phase += 1.0;

    switch (w) {
    case WAVE_SINE:
        return sin(phase * 2.0 * M_PI);
    case WAVE_SQUARE:
        return phase < 0.5 ? 1.0 : -1.0;
    case WAVE_TRIANGLE:
        if (phase < 0.5)
            return 4.0 * phase - 1.0;
        return 3.0 - 4.0 * phase;
    case WAVE_NOISE:
        return ((double)rand() / (double)RAND_MAX) * 2.0 - 1.0;
    }
    return 0.0;
}

double env_decay(double t, double decay)
{
    return exp(-decay * t);
}

void audio_callback(void *userdata, Uint8 *stream, int len)
{
    (void)userdata;
    int frames = len / (2 * (int)sizeof(Sint16));
    Sint16 *out = (Sint16 *)stream;

    for (int i = 0; i < frames; i++) {
        double t = g_audio_time;
        double sample = 0.0;

        for (int vi = 0; vi < g_voice_count; vi++) {
            const Voice *v = &g_voices[vi];
            if (t < v->start || t >= v->end)
                continue;
            double local = t - v->start;
            double phase = local * v->freq;
            double s = wave_sample(v->wave, phase);
            sample += s * v->amp * env_decay(local, v->decay);
        }

        sample *= g_master_amp;
        sample = clampd(sample, -1.0, 1.0);
        Sint16 val = (Sint16)(sample * 32767.0);
        *out++ = val;
        *out++ = val;
        g_audio_time += 1.0 / (double)SAMPLE_RATE;
    }
}

static void parse_modes_mask(const char *val, Config *cfg)
{
    cfg->modes_mask = 0;
    char buf[128];
    strncpy(buf, val, sizeof(buf) - 1);
    buf[sizeof(buf) - 1] = '\0';

    char *save = NULL;
    for (char *tok = strtok_r(buf, " \t,", &save); tok; tok = strtok_r(NULL, " \t,", &save)) {
        for (int i = 0; i < g_mode_count; i++) {
            if (strcmp(tok, g_modes[i].name) == 0)
                cfg->modes_mask |= (1 << i);
        }
    }
    if (cfg->modes_mask == 0)
        cfg->modes_mask = (1 << g_mode_count) - 1;
}

static int mode_by_name(const char *name)
{
    for (int i = 0; i < g_mode_count; i++) {
        if (strcmp(name, g_modes[i].name) == 0)
            return i;
    }
    return -1;
}

static void config_defaults(Config *cfg)
{
    cfg->enabled = 1;
    cfg->mode = 2; /* gba default */
    cfg->modes_mask = (1 << g_mode_count) - 1;
    cfg->allow_skip = 1;
    cfg->volume = 100;
    cfg->debug = 0;
}

void config_load(const char *path, Config *cfg)
{
    FILE *f = fopen(path, "r");
    if (!f) {
        config_defaults(cfg);
        return;
    }

    config_defaults(cfg);
    char line[256];
    while (fgets(line, sizeof(line), f)) {
        char *p = strchr(line, '#');
        if (p)
            *p = '\0';
        char *eq = strchr(line, '=');
        if (!eq)
            continue;
        *eq = '\0';
        char *key = line;
        char *val = eq + 1;

        while (*key == ' ' || *key == '\t')
            key++;
        char *end = key + strlen(key) - 1;
        while (end > key && (*end == ' ' || *end == '\t' || *end == '\r' || *end == '\n'))
            *end-- = '\0';
        while (*val == ' ' || *val == '\t')
            val++;
        end = val + strlen(val) - 1;
        while (end >= val && (*end == ' ' || *end == '\t' || *end == '\r' || *end == '\n'))
            *end-- = '\0';

        if (strcmp(key, "enabled") == 0) {
            cfg->enabled = atoi(val);
        } else if (strcmp(key, "mode") == 0) {
            int m = mode_by_name(val);
            if (m >= 0)
                cfg->mode = m;
            else if (strcmp(val, "random") == 0)
                cfg->mode = -1;
            else if (strcmp(val, "cycle") == 0)
                cfg->mode = -2;
        } else if (strcmp(key, "modes") == 0) {
            parse_modes_mask(val, cfg);
        } else if (strcmp(key, "skip") == 0) {
            cfg->allow_skip = atoi(val);
        } else if (strcmp(key, "volume") == 0) {
            cfg->volume = atoi(val);
            if (cfg->volume < 0)
                cfg->volume = 0;
            if (cfg->volume > 100)
                cfg->volume = 100;
        } else if (strcmp(key, "debug") == 0) {
            cfg->debug = atoi(val);
        }
    }
    fclose(f);
}

static int mkdir_p(const char *path)
{
    char tmp[256];
    strncpy(tmp, path, sizeof(tmp) - 1);
    tmp[sizeof(tmp) - 1] = '\0';

    for (char *p = tmp + 1; *p; p++) {
        if (*p == '/') {
            *p = '\0';
            if (mkdir(tmp, 0755) != 0 && errno != EEXIST)
                return -1;
            *p = '/';
        }
    }
    return 0;
}

int config_cycle_next(int count, const char *state_path)
{
    int idx = 0;
    FILE *f = fopen(state_path, "r");
    if (f) {
        if (fscanf(f, "%d", &idx) != 1)
            idx = 0;
        fclose(f);
    }
    idx = (idx + 1) % count;

    mkdir_p(state_path);
    f = fopen(state_path, "w");
    if (f) {
        fprintf(f, "%d\n", idx);
        fclose(f);
    }
    return idx;
}
