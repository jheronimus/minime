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
    fprintf(stderr, "Usage: %s [--config PATH] [--mode dmg|gbc|gba] [--fullscreen] [--windowed] [--verbose]\n", prog);
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
                      int *cli_debug)
{
    *cli_mode = -3;
    *cli_fullscreen = -1;
    *cli_debug = 0;

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--config") == 0 && i + 1 < argc) {
            default_config = argv[++i];
        } else if (strcmp(argv[i], "--mode") == 0 && i + 1 < argc) {
            int m;
            if (parse_mode(argv[i + 1], &m) == 0)
                *cli_mode = m;
            i++;
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

static int sdl_init_video(SDL_Window **win, SDL_Renderer **rend, int fullscreen)
{
    if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_JOYSTICK | SDL_INIT_EVENTS) != 0) {
        fprintf(stderr, "bootsplash: SDL init failed: %s\n", SDL_GetError());
        return 1;
    }

    int w = 640;
    int h = 480;
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

    SDL_RenderSetLogicalSize(*rend, 640, 480);
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
    int cli_mode, cli_fullscreen, cli_debug;
    int fullscreen = 0;

    if (getenv("BOOTSPLASH_FULLSCREEN"))
        fullscreen = 1;

    if (parse_args(argc, argv, &cli_mode, &cli_fullscreen, &cli_debug) != 0)
        return 1;

    config_load(default_config, &cfg);

    if (cli_mode >= -2)
        cfg.mode = cli_mode;
    if (cli_fullscreen >= 0)
        fullscreen = cli_fullscreen;
    if (cli_debug)
        cfg.debug = 1;

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
        fprintf(stderr, "bootsplash: mode=%s duration=%.2f vol=%d\n",
                g_modes[mode].name, g_modes[mode].duration, cfg.volume);
    }

    SDL_Window *win = NULL;
    SDL_Renderer *rend = NULL;
    if (sdl_init_video(&win, &rend, fullscreen) != 0)
        return 1;

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

        g_modes[mode].draw(rend, t);
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
    SDL_DestroyRenderer(rend);
    SDL_DestroyWindow(win);
    SDL_Quit();

    return 0;
}
