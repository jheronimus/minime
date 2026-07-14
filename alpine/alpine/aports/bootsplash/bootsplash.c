/* bootsplash.c - main loop and SDL setup */
#include "bootsplash.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

const Mode g_modes[] = {
    { "dmg", 2.20, draw_dmg, audio_dmg },
    { "gbc", 2.20, draw_gbc, audio_gbc },
    { "gba", 2.50, draw_gba, audio_gba },
};
const int g_mode_count = sizeof(g_modes) / sizeof(g_modes[0]);

static const char *default_config = "/mnt/sdcard/.minime/config/bootsplash.cfg";

static void state_path_from_config(const char *config, char *out, size_t outsz)
{
    const char *needle = "/config/";
    const char *p = strstr(config, needle);
    if (p) {
        size_t base_len = p - config;
        snprintf(out, outsz, "%.*s/state/bootsplash.idx", (int)base_len, config);
        return;
    }
    const char *slash = strrchr(config, '/');
    if (slash) {
        snprintf(out, outsz, "%.*s/bootsplash.idx", (int)(slash - config), config);
    } else {
        snprintf(out, outsz, "bootsplash.idx");
    }
}

#define TRAITS_PATH "/mnt/sdcard/.minime/traits"
#define SPLASH_W 640
#define SPLASH_H 480

/* Read the panel orientation from the Minime traits file written by S09detect-traits.
 * Falls back to 640x480 / 0deg when the file is absent (e.g. macOS test runs). */
static void read_traits(int *w, int *h, int *rot)
{
    *w = SPLASH_W;
    *h = SPLASH_H;
    *rot = 0;
    FILE *f = fopen(TRAITS_PATH, "r");
    if (!f)
        return;
    char line[256];
    while (fgets(line, sizeof(line), f)) {
        char *p = line;
        while (*p == ' ' || *p == '\t')
            p++;
        if (*p == '#' || *p == '[' || *p == '\0' || *p == '\n')
            continue;
        char *eq = strchr(p, '=');
        if (!eq)
            continue;
        *eq = '\0';
        char *ke = p + strlen(p) - 1;
        while (ke >= p && (*ke == ' ' || *ke == '\t'))
            *ke-- = '\0';
        char *val = eq + 1;
        char *e = val + strlen(val) - 1;
        while (e >= val && (*e == '\n' || *e == '\r' || *e == ' ' || *e == '\t'))
            *e-- = '\0';
        if (!strcmp(p, "screen_width"))
            *w = atoi(val);
        else if (!strcmp(p, "screen_height"))
            *h = atoi(val);
        else if (!strcmp(p, "screen_rotation"))
            *rot = atoi(val);
    }
    fclose(f);
}

static int resolve_mode(const Config *cfg, const char *state_path)
{
    int enabled[8];
    int n = 0;
    for (int i = 0; i < g_mode_count; i++) {
        if (cfg->modes_mask & (1 << i))
            enabled[n++] = i;
    }
    if (n == 0)
        return 0;

    if (cfg->mode >= 0 && (cfg->modes_mask & (1 << cfg->mode)))
        return cfg->mode;

    if (cfg->mode == -2) {
        int idx = config_cycle_next(n, state_path);
        if (idx < 0)
            idx = 0;
        return enabled[idx];
    }

    srand((unsigned)time(NULL));
    return enabled[rand() % n];
}

static void usage(const char *prog)
{
    fprintf(stderr, "Usage: %s [--config PATH] [--mode dmg|gbc|gba] [--rotation 0|90|180|270] [--fullscreen] [--windowed] [--verbose]\n", prog);
}

static int parse_mode(const char *name, int *out)
{
    for (int j = 0; j < g_mode_count; j++) {
        if (strcmp(name, g_modes[j].name) == 0) {
            *out = j;
            return 0;
        }
    }
    if (strcmp(name, "random") == 0) {
        *out = -1;
        return 0;
    }
    if (strcmp(name, "cycle") == 0) {
        *out = -2;
        return 0;
    }
    return -1;
}

static int parse_args(int argc, char **argv, int *cli_mode, int *cli_fullscreen,
                      int *cli_debug, int *cli_rotation)
{
    *cli_mode = -3;
    *cli_fullscreen = -1;
    *cli_debug = 0;
    *cli_rotation = -1;

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--config") == 0 && i + 1 < argc) {
            default_config = argv[++i];
        } else if (strcmp(argv[i], "--mode") == 0 && i + 1 < argc) {
            int m;
            if (parse_mode(argv[i + 1], &m) == 0)
                *cli_mode = m;
            i++;
        } else if (strcmp(argv[i], "--rotation") == 0 && i + 1 < argc) {
            *cli_rotation = atoi(argv[++i]);
        } else if (strcmp(argv[i], "--fullscreen") == 0) {
            *cli_fullscreen = 1;
        } else if (strcmp(argv[i], "--windowed") == 0) {
            *cli_fullscreen = 0;
        } else if (strcmp(argv[i], "--verbose") == 0) {
            *cli_debug = 1;
        } else {
            usage(argv[0]);
            return 1;
        }
    }
    return 0;
}

static int sdl_init_video(SDL_Window **win, SDL_Renderer **rend, int fullscreen,
                          int w, int h)
{
    if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_JOYSTICK | SDL_INIT_EVENTS) != 0) {
        fprintf(stderr, "bootsplash: SDL init failed: %s\n", SDL_GetError());
        return 1;
    }

    Uint32 flags = SDL_WINDOW_SHOWN;
    if (fullscreen)
        flags |= SDL_WINDOW_FULLSCREEN_DESKTOP;

    *win = SDL_CreateWindow("minime bootsplash", SDL_WINDOWPOS_CENTERED,
                            SDL_WINDOWPOS_CENTERED, w, h, flags);
    if (!*win) {
        fprintf(stderr, "bootsplash: window failed: %s\n", SDL_GetError());
        return 1;
    }

    *rend = SDL_CreateRenderer(*win, -1,
                               SDL_RENDERER_ACCELERATED |
                               SDL_RENDERER_PRESENTVSYNC);
    if (!*rend)
        *rend = SDL_CreateRenderer(*win, -1, SDL_RENDERER_SOFTWARE);
    if (!*rend) {
        fprintf(stderr, "bootsplash: renderer failed: %s\n", SDL_GetError());
        return 1;
    }
    return 0;
}

static int sdl_init_audio(void)
{
    SDL_AudioSpec want = { 0 };
    want.freq = SAMPLE_RATE;
    want.format = AUDIO_S16SYS;
    want.channels = 2;
    want.samples = 512;
    want.callback = audio_callback;

    SDL_AudioSpec have;
    if (SDL_OpenAudio(&want, &have) != 0) {
        fprintf(stderr, "bootsplash: audio open failed: %s\n", SDL_GetError());
        return 0;
    }
    SDL_PauseAudio(0);
    return 1;
}

typedef enum {
    ACT_NONE, ACT_SKIP, ACT_MODE0, ACT_MODE1, ACT_MODE2, ACT_FULL, ACT_VERBOSE
} Action;

static Action key_action(SDL_Keycode key)
{
    switch (key) {
    case SDLK_ESCAPE:
    case SDLK_q:
        return ACT_SKIP;
    case SDLK_d:
        return ACT_MODE0;
    case SDLK_c:
        return ACT_MODE1;
    case SDLK_b:
        return ACT_MODE2;
    case SDLK_f:
        return ACT_FULL;
    case SDLK_v:
        return ACT_VERBOSE;
    default:
        return ACT_NONE;
    }
}

static Action poll_events(void)
{
    SDL_Event e;
    Action act = ACT_NONE;
    while (SDL_PollEvent(&e)) {
        if (e.type == SDL_QUIT) {
            return ACT_SKIP;
        } else if (e.type == SDL_JOYBUTTONDOWN) {
            return ACT_SKIP;
        } else if (e.type == SDL_KEYDOWN) {
            Action a = key_action(e.key.keysym.sym);
            if (a == ACT_NONE)
                a = ACT_SKIP;
            if (a != ACT_NONE && act == ACT_NONE)
                act = a;
        }
    }
    return act;
}

int main(int argc, char **argv)
{
    Config cfg;
    int cli_mode, cli_fullscreen, cli_debug, cli_rotation;
    int fullscreen = 0;

    if (getenv("BOOTSPLASH_FULLSCREEN"))
        fullscreen = 1;

    if (parse_args(argc, argv, &cli_mode, &cli_fullscreen, &cli_debug,
                   &cli_rotation) != 0)
        return 1;

    config_load(default_config, &cfg);

    if (cli_mode >= -2)
        cfg.mode = cli_mode;
    if (cli_fullscreen >= 0)
        fullscreen = cli_fullscreen;
    if (cli_debug)
        cfg.debug = 1;

    int scr_w, scr_h, scr_rot;
    read_traits(&scr_w, &scr_h, &scr_rot);
    if (cli_rotation >= 0)
        scr_rot = cli_rotation;

    if (!cfg.enabled) {
        if (cfg.debug)
            fprintf(stderr, "bootsplash: disabled in config\n");
        return 0;
    }

    g_master_amp = cfg.volume / 100.0;
    char state_file[256];
    state_path_from_config(default_config, state_file, sizeof(state_file));
    int mode = resolve_mode(&cfg, state_file);
    if (mode < 0 || mode >= g_mode_count)
        mode = 0;

    if (cfg.debug) {
        fprintf(stderr, "bootsplash: mode=%s duration=%.2f vol=%d rot=%d\n",
                g_modes[mode].name, g_modes[mode].duration, cfg.volume, scr_rot);
    }

    SDL_Window *win = NULL;
    SDL_Renderer *rend = NULL;
    if (sdl_init_video(&win, &rend, fullscreen, scr_w, scr_h) != 0)
        return 1;

    /* Render the animation to an offscreen 640x480 target, then rotate it onto
     * the panel using the same pivot-(0,0) trick as the Minime UI so the splash
     * matches the device orientation.  Falls back to direct draw if the target
     * texture cannot be created. */
    SDL_Texture *off = SDL_CreateTexture(rend, SDL_PIXELFORMAT_ARGB8888,
                                         SDL_TEXTUREACCESS_TARGET,
                                         SPLASH_W, SPLASH_H);
    int use_off = (off != NULL);

    SDL_Joystick *joy = NULL;
    if (SDL_NumJoysticks() > 0)
        joy = SDL_JoystickOpen(0);

    voices_clear();
    g_modes[mode].audio();
    int audio_ok = sdl_init_audio();
    if (!audio_ok && cfg.debug)
        fprintf(stderr, "bootsplash: running without audio\n");

    double start = now_sec();
    double dur = g_modes[mode].duration;
    int running = 1;
    Uint32 win_flags = SDL_GetWindowFlags(win);

    while (running) {
        double t = now_sec() - start;
        if (t >= dur) {
            running = 0;
            break;
        }

        if (use_off) {
            SDL_SetRenderTarget(rend, off);
            g_modes[mode].draw(rend, t);
            SDL_SetRenderTarget(rend, NULL);

            int ow, oh;
            SDL_GetRendererOutputSize(rend, &ow, &oh);
            SDL_SetRenderDrawColor(rend, 0, 0, 0, 255);
            SDL_RenderClear(rend);
            if (scr_rot == 0) {
                SDL_RenderCopy(rend, off, NULL, &(SDL_Rect){0, 0, ow, oh});
            } else {
                int r = scr_rot / 90;
                int dx = 0, dy = 0;
                if (r == 1) { dx = oh; dy = 0; }
                else if (r == 2) { dx = ow; dy = oh; }
                else if (r == 3) { dx = 0; dy = ow; }
                SDL_RenderCopyEx(rend, off, NULL,
                                 &(SDL_Rect){dx, dy, ow, oh}, scr_rot,
                                 &(SDL_Point){0, 0}, SDL_FLIP_NONE);
            }
        } else {
            g_modes[mode].draw(rend, t);
        }
        SDL_RenderPresent(rend);

        Action act = poll_events();
        if (act == ACT_SKIP && cfg.allow_skip) {
            running = 0;
            break;
        }
        if (act == ACT_FULL) {
            if (win_flags & SDL_WINDOW_FULLSCREEN_DESKTOP) {
                SDL_SetWindowFullscreen(win, 0);
                win_flags &= ~SDL_WINDOW_FULLSCREEN_DESKTOP;
            } else {
                SDL_SetWindowFullscreen(win, SDL_WINDOW_FULLSCREEN_DESKTOP);
                win_flags |= SDL_WINDOW_FULLSCREEN_DESKTOP;
            }
        }
        if (act == ACT_VERBOSE) {
            cfg.debug = !cfg.debug;
            if (cfg.debug)
                fprintf(stderr, "bootsplash: verbose on\n");
        }
        if (act >= ACT_MODE0 && act <= ACT_MODE2) {
            int m = act - ACT_MODE0;
            if (m < g_mode_count) {
                mode = m;
                start = now_sec();
                dur = g_modes[mode].duration;
                voices_clear();
                SDL_LockAudio();
                g_audio_time = 0.0;
                SDL_UnlockAudio();
                g_modes[mode].audio();
                if (cfg.debug)
                    fprintf(stderr, "bootsplash: switched to %s\n", g_modes[mode].name);
            }
        }

        SDL_Delay(8);
    }

    if (audio_ok)
        SDL_CloseAudio();
    if (joy)
        SDL_JoystickClose(joy);
    if (off)
        SDL_DestroyTexture(off);
    SDL_DestroyRenderer(rend);
    SDL_DestroyWindow(win);
    SDL_Quit();

    return 0;
}
