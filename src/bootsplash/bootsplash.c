/*
 * bootsplash: lightweight framebuffer bootsplash for Minime
 *
 * Renders the lowercase 'minimē' ASCII wordmark and a looping left-to-right
 * gradient progress bar. Listens to evdev volume keys to toggle between
 * bootsplash (KD_GRAPHICS) and console log (KD_TEXT). Watches OpenRC UI
 * lifecycle to perform smooth handoff or reveal errors on failure.
 */

#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <signal.h>
#include <poll.h>
#include <time.h>
#include <dirent.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <linux/fb.h>
#include <linux/input.h>
#include <linux/kd.h>
#include <linux/vt.h>

#define LOGO_ROWS 4
#define LOGO_COLS 30
#define MAX_INPUTS 16
#define TIMEOUT_SECS 60

static const char *logo_lines[LOGO_ROWS] = {
	"       ▀        ▀         ▀▀▀▀",
	"█▀█▀█  █  █▀▀█  █  █▀█▀█  █▀▀█",
	"█ █ █  █  █  █  █  █ █ █  █▄▄█",
	"█ █ █  █  █  █  █  █ █ █  █▄▄▄"
};

enum glyph_type {
	GLYPH_SPACE = 0,
	GLYPH_FULL,
	GLYPH_UPPER,
	GLYPH_LOWER
};

static enum glyph_type logo_grid[LOGO_ROWS][LOGO_COLS];

struct fb_ctx {
	int fd;
	uint8_t *mem;
	size_t mem_size;
	uint32_t xres;
	uint32_t yres;
	uint32_t bpp;
	uint32_t line_length;
	struct fb_bitfield red;
	struct fb_bitfield green;
	struct fb_bitfield blue;
};

static volatile sig_atomic_t g_running = 1;

static void sig_handler(int sig)
{
	(void)sig;
	g_running = 0;
}

static void parse_logo_grid(void)
{
	memset(logo_grid, 0, sizeof(logo_grid));
	for (int r = 0; r < LOGO_ROWS; r++) {
		const unsigned char *p = (const unsigned char *)logo_lines[r];
		int c = 0;
		while (*p && c < LOGO_COLS) {
			if (*p == ' ') {
				logo_grid[r][c++] = GLYPH_SPACE;
				p++;
			} else if (p[0] == 0xe2 && p[1] == 0x96) {
				if (p[2] == 0x88) {
					logo_grid[r][c++] = GLYPH_FULL;
				} else if (p[2] == 0x80) {
					logo_grid[r][c++] = GLYPH_UPPER;
				} else if (p[2] == 0x84) {
					logo_grid[r][c++] = GLYPH_LOWER;
				} else {
					logo_grid[r][c++] = GLYPH_SPACE;
				}
				p += 3;
			} else {
				p++;
			}
		}
	}
}

static uint32_t pack_pixel(const struct fb_ctx *fb, uint8_t r, uint8_t g, uint8_t b)
{
	if (fb->bpp == 16) {
		uint16_t r5 = (r >> 3) & 0x1f;
		uint16_t g6 = (g >> 2) & 0x3f;
		uint16_t b5 = (b >> 3) & 0x1f;
		return (r5 << fb->red.offset) | (g6 << fb->green.offset) | (b5 << fb->blue.offset);
	}
	return ((uint32_t)r << fb->red.offset) |
	       ((uint32_t)g << fb->green.offset) |
	       ((uint32_t)b << fb->blue.offset);
}

static void fill_rect(const struct fb_ctx *fb, uint32_t x0, uint32_t y0,
		      uint32_t w, uint32_t h, uint32_t color)
{
	if (x0 >= fb->xres || y0 >= fb->yres)
		return;
	if (x0 + w > fb->xres)
		w = fb->xres - x0;
	if (y0 + h > fb->yres)
		h = fb->yres - y0;

	for (uint32_t y = y0; y < y0 + h; y++) {
		uint8_t *dst = fb->mem + (y * fb->line_length);
		if (fb->bpp == 16) {
			uint16_t *line = (uint16_t *)(dst + (x0 * 2));
			for (uint32_t x = 0; x < w; x++)
				line[x] = (uint16_t)color;
		} else if (fb->bpp == 32) {
			uint32_t *line = (uint32_t *)(dst + (x0 * 4));
			for (uint32_t x = 0; x < w; x++)
				line[x] = color;
		}
	}
}

static void clear_screen(const struct fb_ctx *fb)
{
	if (!fb->mem)
		return;
	memset(fb->mem, 0, fb->mem_size);
}

static void draw_wordmark(const struct fb_ctx *fb, uint32_t start_x, uint32_t start_y,
			  uint32_t cell_w, uint32_t cell_h, uint32_t fg_color)
{
	for (int r = 0; r < LOGO_ROWS; r++) {
		for (int c = 0; c < LOGO_COLS; c++) {
			enum glyph_type g = logo_grid[r][c];
			if (g == GLYPH_SPACE)
				continue;

			uint32_t px = start_x + (c * cell_w);
			uint32_t py = start_y + (r * cell_h);
			uint32_t half_h = cell_h / 2;

			switch (g) {
			case GLYPH_FULL:
				fill_rect(fb, px, py, cell_w, cell_h, fg_color);
				break;
			case GLYPH_UPPER:
				fill_rect(fb, px, py, cell_w, half_h, fg_color);
				break;
			case GLYPH_LOWER:
				fill_rect(fb, px, py + half_h, cell_w, cell_h - half_h, fg_color);
				break;
			default:
				break;
			}
		}
	}
}

static void draw_gradient_bar(const struct fb_ctx *fb, uint32_t track_x, uint32_t track_y,
			      uint32_t track_w, uint32_t bar_h, int32_t beam_pos,
			      uint32_t beam_w, uint32_t *scratch_buf)
{
	if (track_w > 4096)
		track_w = 4096;

	for (uint32_t x = 0; x < track_w; x++) {
		int32_t dist = (int32_t)x - beam_pos;
		if (dist >= 0 && (uint32_t)dist < beam_w) {
			/* Inside beam: 0.0 (tail) -> 1.0 (head) */
			float t = 1.0f - ((float)dist / (float)beam_w);
			uint8_t r, g, b;
			if (t < 0.5f) {
				float f = t * 2.0f;
				r = 0;
				g = (uint8_t)(30.0f + f * (150.0f - 30.0f));
				b = (uint8_t)(100.0f + f * (255.0f - 100.0f));
			} else {
				float f = (t - 0.5f) * 2.0f;
				r = (uint8_t)(f * 100.0f);
				g = (uint8_t)(150.0f + f * (255.0f - 150.0f));
				b = 255;
			}
			scratch_buf[x] = pack_pixel(fb, r, g, b);
		} else {
			scratch_buf[x] = 0;
		}
	}

	for (uint32_t y = 0; y < bar_h; y++) {
		if (track_y + y >= fb->yres)
			break;
		uint8_t *dst = fb->mem + ((track_y + y) * fb->line_length);
		if (fb->bpp == 16) {
			uint16_t *line = (uint16_t *)(dst + (track_x * 2));
			for (uint32_t x = 0; x < track_w; x++)
				line[x] = (uint16_t)scratch_buf[x];
		} else if (fb->bpp == 32) {
			uint32_t *line = (uint32_t *)(dst + (track_x * 4));
			memcpy(line, scratch_buf, track_w * sizeof(uint32_t));
		}
	}
}

static int open_tty(void)
{
	static const char *tty_paths[] = {
		"/dev/tty0",
		"/dev/tty1",
		"/dev/console",
		NULL
	};

	for (int i = 0; tty_paths[i]; i++) {
		int fd = open(tty_paths[i], O_RDWR | O_NOCTTY | O_CLOEXEC);
		if (fd >= 0)
			return fd;
	}
	return -1;
}

static void read_trait_keys(int *key_up, int *key_down)
{
	static const char *trait_files[] = {
		"/mnt/sdcard/.minime/traits",
		"/mnt/card/.minime/traits",
		"/etc/traits",
		NULL
	};

	*key_up = KEY_VOLUMEUP;
	*key_down = KEY_VOLUMEDOWN;

	for (int i = 0; trait_files[i]; i++) {
		FILE *f = fopen(trait_files[i], "r");
		if (!f)
			continue;

		char line[128];
		while (fgets(line, sizeof(line), f)) {
			int val = 0;
			if (sscanf(line, "key_vol_up=%d", &val) == 1 && val > 0)
				*key_up = val;
			else if (sscanf(line, "key_vol_down=%d", &val) == 1 && val > 0)
				*key_down = val;
		}
		fclose(f);
		break;
	}
}

static int scan_input_devices(int *fds, int max_fds)
{
	int count = 0;
	DIR *dir = opendir("/dev/input");
	if (!dir)
		return 0;

	struct dirent *de;
	while ((de = readdir(dir)) != NULL && count < max_fds) {
		if (strncmp(de->d_name, "event", 5) != 0)
			continue;

		char path[512];
		snprintf(path, sizeof(path), "/dev/input/%s", de->d_name);

		int fd = open(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC);
		if (fd >= 0) {
			fds[count++] = fd;
		}
	}
	closedir(dir);
	return count;
}

static void close_input_devices(int *fds, int count)
{
	for (int i = 0; i < count; i++) {
		if (fds[i] >= 0) {
			close(fds[i]);
			fds[i] = -1;
		}
	}
}

static bool check_file_exists(const char *path)
{
	return access(path, F_OK) == 0;
}

int main(int argc, char **argv)
{
	(void)argc;
	(void)argv;

	struct sigaction sa;
	memset(&sa, 0, sizeof(sa));
	sa.sa_handler = sig_handler;
	sigaction(SIGTERM, &sa, NULL);
	sigaction(SIGINT, &sa, NULL);
	sigaction(SIGHUP, &sa, NULL);

	parse_logo_grid();

	int tty_fd = open_tty();
	if (tty_fd >= 0) {
		ioctl(tty_fd, KDSETMODE, KD_GRAPHICS);
	}

	struct fb_ctx fb;
	memset(&fb, 0, sizeof(fb));
	fb.fd = open("/dev/fb0", O_RDWR | O_CLOEXEC);
	if (fb.fd < 0) {
		if (tty_fd >= 0) {
			ioctl(tty_fd, KDSETMODE, KD_TEXT);
			close(tty_fd);
		}
		return 1;
	}

	struct fb_var_screeninfo vinfo;
	struct fb_fix_screeninfo finfo;
	if (ioctl(fb.fd, FBIOGET_VSCREENINFO, &vinfo) < 0 ||
	    ioctl(fb.fd, FBIOGET_FSCREENINFO, &finfo) < 0) {
		close(fb.fd);
		if (tty_fd >= 0) {
			ioctl(tty_fd, KDSETMODE, KD_TEXT);
			close(tty_fd);
		}
		return 1;
	}

	fb.xres = vinfo.xres;
	fb.yres = vinfo.yres;
	fb.bpp = vinfo.bits_per_pixel;
	fb.line_length = finfo.line_length ? finfo.line_length : (fb.xres * (fb.bpp / 8));
	fb.red = vinfo.red;
	fb.green = vinfo.green;
	fb.blue = vinfo.blue;
	fb.mem_size = finfo.smem_len ? finfo.smem_len : (fb.line_length * fb.yres);

	fb.mem = mmap(NULL, fb.mem_size, PROT_READ | PROT_WRITE, MAP_SHARED, fb.fd, 0);
	if (fb.mem == MAP_FAILED) {
		close(fb.fd);
		if (tty_fd >= 0) {
			ioctl(tty_fd, KDSETMODE, KD_TEXT);
			close(tty_fd);
		}
		return 1;
	}

	/* Compute layout geometry */
	uint32_t cell_w = fb.xres / 40;
	if (cell_w < 4)
		cell_w = 4;
	if (cell_w > 18)
		cell_w = 18;
	uint32_t cell_h = cell_w;

	uint32_t word_w = LOGO_COLS * cell_w;
	uint32_t word_h = LOGO_ROWS * cell_h;
	uint32_t gap_h = (cell_h * 3) / 2;
	uint32_t bar_h = cell_h / 3;
	if (bar_h < 3)
		bar_h = 3;
	if (bar_h > 8)
		bar_h = 8;
	uint32_t total_h = word_h + gap_h + bar_h;

	uint32_t start_x = (fb.xres > word_w) ? (fb.xres - word_w) / 2 : 0;
	uint32_t start_y = (fb.yres > total_h) ? (fb.yres - total_h) / 2 : 0;

	uint32_t track_x = start_x;
	uint32_t track_y = start_y + word_h + gap_h;
	uint32_t track_w = word_w;

	uint32_t beam_w = track_w / 3;
	if (beam_w < 20)
		beam_w = 20;

	uint32_t fg_color = pack_pixel(&fb, 240, 240, 240);

	uint32_t scratch_buf[4096];
	if (track_w > 4096)
		track_w = 4096;

	clear_screen(&fb);
	draw_wordmark(&fb, start_x, start_y, cell_w, cell_h, fg_color);

	int key_vol_up = KEY_VOLUMEUP;
	int key_vol_down = KEY_VOLUMEDOWN;
	read_trait_keys(&key_vol_up, &key_vol_down);

	int input_fds[MAX_INPUTS];
	int input_count = scan_input_devices(input_fds, MAX_INPUTS);

	bool in_graphics_mode = true;
	int32_t beam_pos = -(int32_t)beam_w;
	int step = (track_w / 30);
	if (step < 2)
		step = 2;

	time_t start_time = time(NULL);
	int scan_ticks = 0;

	while (g_running) {
		/* OpenRC lifecycle handoff */
		if (check_file_exists("/run/openrc/started/ui")) {
			/* UI started -> exit smoothly leaving KD_GRAPHICS */
			break;
		}
		if (check_file_exists("/run/openrc/failed/ui")) {
			/* UI failed -> reveal console and exit */
			if (tty_fd >= 0)
				ioctl(tty_fd, KDSETMODE, KD_TEXT);
			break;
		}

		/* 60-second safety timeout */
		if (time(NULL) - start_time > TIMEOUT_SECS) {
			if (tty_fd >= 0)
				ioctl(tty_fd, KDSETMODE, KD_TEXT);
			break;
		}

		/* Re-scan input devices periodically or if none opened */
		if (++scan_ticks >= 15 || input_count == 0) {
			scan_ticks = 0;
			read_trait_keys(&key_vol_up, &key_vol_down);
			close_input_devices(input_fds, input_count);
			input_count = scan_input_devices(input_fds, MAX_INPUTS);
		}

		/* Poll input devices */
		struct pollfd pfds[MAX_INPUTS];
		for (int i = 0; i < input_count; i++) {
			pfds[i].fd = input_fds[i];
			pfds[i].events = POLLIN;
			pfds[i].revents = 0;
		}

		int poll_ret = poll(pfds, input_count, 33);
		if (poll_ret > 0) {
			for (int i = 0; i < input_count; i++) {
				if (!(pfds[i].revents & POLLIN))
					continue;

				struct input_event ev;
				while (read(pfds[i].fd, &ev, sizeof(ev)) == (ssize_t)sizeof(ev)) {
					if (ev.type != EV_KEY || ev.value != 1)
						continue;

					if (ev.code == key_vol_up) {
						if (in_graphics_mode) {
							if (tty_fd >= 0)
								ioctl(tty_fd, KDSETMODE, KD_TEXT);
							in_graphics_mode = false;
						}
					} else if (ev.code == key_vol_down) {
						if (!in_graphics_mode) {
							if (tty_fd >= 0)
								ioctl(tty_fd, KDSETMODE, KD_GRAPHICS);
							in_graphics_mode = true;
							clear_screen(&fb);
							draw_wordmark(&fb, start_x, start_y, cell_w, cell_h, fg_color);
						}
					}
				}
			}
		}

		/* Animate progress bar left-to-right only in KD_GRAPHICS mode */
		if (in_graphics_mode) {
			draw_gradient_bar(&fb, track_x, track_y, track_w, bar_h,
					  beam_pos, beam_w, scratch_buf);

			beam_pos += step;
			if (beam_pos > (int32_t)track_w) {
				beam_pos = -(int32_t)beam_w;
			}
		}
	}

	close_input_devices(input_fds, input_count);
	munmap(fb.mem, fb.mem_size);
	close(fb.fd);
	if (tty_fd >= 0)
		close(tty_fd);

	return 0;
}
