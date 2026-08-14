#include "fb.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <linux/fb.h>

int fb_capture(const char *device_path, uint8_t **out_rgb, int *out_width, int *out_height) {
    if (!device_path || !out_rgb || !out_width || !out_height) {
        return -1;
    }

    int fd = open(device_path, O_RDONLY);
    if (fd < 0) {
        perror("open framebuffer");
        return -1;
    }

    struct fb_var_screeninfo vinfo;
    struct fb_fix_screeninfo finfo;

    if (ioctl(fd, FBIOGET_VSCREENINFO, &vinfo) < 0) {
        perror("ioctl FBIOGET_VSCREENINFO");
        close(fd);
        return -1;
    }

    if (ioctl(fd, FBIOGET_FSCREENINFO, &finfo) < 0) {
        perror("ioctl FBIOGET_FSCREENINFO");
        close(fd);
        return -1;
    }

    int width = vinfo.xres;
    int height = vinfo.yres;
    int bpp = vinfo.bits_per_pixel;
    size_t line_length = finfo.line_length;
    if (line_length == 0) {
        line_length = width * (bpp / 8);
    }

    size_t screensize = finfo.smem_len;
    if (screensize == 0) {
        screensize = line_length * height;
    }

    uint8_t *fbp = (uint8_t *)mmap(NULL, screensize, PROT_READ, MAP_SHARED, fd, 0);
    if (fbp == MAP_FAILED) {
        perror("mmap framebuffer");
        close(fd);
        return -1;
    }

    size_t rgb_size = (size_t)width * height * 3;
    uint8_t *rgb = malloc(rgb_size);
    if (!rgb) {
        perror("malloc rgb buffer");
        munmap(fbp, screensize);
        close(fd);
        return -1;
    }

    // Offset into framebuffer memory if yoffset is non-zero (double buffering)
    size_t start_offset = vinfo.yoffset * line_length + vinfo.xoffset * (bpp / 8);
    if (start_offset + line_length * height > screensize) {
        start_offset = 0; // Fallback to start if offset extends beyond smem_len
    }

    if (bpp == 16) {
        // Standard RGB565 or BGR565
        int r_shift = vinfo.red.offset;
        int g_shift = vinfo.green.offset;
        int b_shift = vinfo.blue.offset;
        int r_len = vinfo.red.length ? vinfo.red.length : 5;
        int g_len = vinfo.green.length ? vinfo.green.length : 6;
        int b_len = vinfo.blue.length ? vinfo.blue.length : 5;

        for (int y = 0; y < height; y++) {
            const uint16_t *row = (const uint16_t *)(fbp + start_offset + y * line_length);
            for (int x = 0; x < width; x++) {
                uint16_t pixel = row[x];
                uint8_t r = ((pixel >> r_shift) & ((1 << r_len) - 1)) * 255 / ((1 << r_len) - 1);
                uint8_t g = ((pixel >> g_shift) & ((1 << g_len) - 1)) * 255 / ((1 << g_len) - 1);
                uint8_t b = ((pixel >> b_shift) & ((1 << b_len) - 1)) * 255 / ((1 << b_len) - 1);

                size_t idx = ((size_t)y * width + x) * 3;
                rgb[idx + 0] = r;
                rgb[idx + 1] = g;
                rgb[idx + 2] = b;
            }
        }
    } else if (bpp == 32) {
        int r_shift = vinfo.red.offset;
        int g_shift = vinfo.green.offset;
        int b_shift = vinfo.blue.offset;

        for (int y = 0; y < height; y++) {
            const uint32_t *row = (const uint32_t *)(fbp + start_offset + y * line_length);
            for (int x = 0; x < width; x++) {
                uint32_t pixel = row[x];
                uint8_t r = (pixel >> r_shift) & 0xFF;
                uint8_t g = (pixel >> g_shift) & 0xFF;
                uint8_t b = (pixel >> b_shift) & 0xFF;

                size_t idx = ((size_t)y * width + x) * 3;
                rgb[idx + 0] = r;
                rgb[idx + 1] = g;
                rgb[idx + 2] = b;
            }
        }
    } else if (bpp == 24) {
        for (int y = 0; y < height; y++) {
            const uint8_t *row = fbp + start_offset + y * line_length;
            for (int x = 0; x < width; x++) {
                size_t s_idx = x * 3;
                size_t d_idx = ((size_t)y * width + x) * 3;
                // Check if red is byte 0 or byte 2
                if (vinfo.red.offset == 0) {
                    rgb[d_idx + 0] = row[s_idx + 0];
                    rgb[d_idx + 1] = row[s_idx + 1];
                    rgb[d_idx + 2] = row[s_idx + 2];
                } else {
                    rgb[d_idx + 0] = row[s_idx + 2];
                    rgb[d_idx + 1] = row[s_idx + 1];
                    rgb[d_idx + 2] = row[s_idx + 0];
                }
            }
        }
    } else {
        fprintf(stderr, "Unsupported framebuffer bit depth: %d bpp\n", bpp);
        free(rgb);
        munmap(fbp, screensize);
        close(fd);
        return -1;
    }

    munmap(fbp, screensize);
    close(fd);

    *out_rgb = rgb;
    *out_width = width;
    *out_height = height;
    return 0;
}
