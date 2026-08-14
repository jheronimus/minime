#include "rotate.h"
#include <stdlib.h>
#include <string.h>

int image_rotate_rgb(const uint8_t *src, int src_w, int src_h, int rotation,
                     uint8_t **dst, int *dst_w, int *dst_h) {
    if (!src || src_w <= 0 || src_h <= 0 || !dst || !dst_w || !dst_h) {
        return -1;
    }

    int rot = ((rotation % 360) + 360) % 360;

    if (rot == 0) {
        *dst_w = src_w;
        *dst_h = src_h;
        size_t size = (size_t)src_w * src_h * 3;
        *dst = malloc(size);
        if (*dst == NULL) return -1;
        memcpy(*dst, src, size);
        return 0;
    }

    if (rot == 90) {
        *dst_w = src_h;
        *dst_h = src_w;
        size_t size = (size_t)(*dst_w) * (*dst_h) * 3;
        *dst = malloc(size);
        if (*dst == NULL) return -1;

        uint8_t *d = *dst;
        int dw = *dst_w;
        int dh = *dst_h;

        for (int dy = 0; dy < dh; dy++) {
            for (int dx = 0; dx < dw; dx++) {
                int sx = dy;
                int sy = src_h - 1 - dx;
                size_t s_idx = ((size_t)sy * src_w + sx) * 3;
                size_t d_idx = ((size_t)dy * dw + dx) * 3;
                d[d_idx + 0] = src[s_idx + 0];
                d[d_idx + 1] = src[s_idx + 1];
                d[d_idx + 2] = src[s_idx + 2];
            }
        }
        return 0;
    }

    if (rot == 180) {
        *dst_w = src_w;
        *dst_h = src_h;
        size_t size = (size_t)src_w * src_h * 3;
        *dst = malloc(size);
        if (*dst == NULL) return -1;

        uint8_t *d = *dst;
        int dw = *dst_w;
        int dh = *dst_h;

        for (int dy = 0; dy < dh; dy++) {
            for (int dx = 0; dx < dw; dx++) {
                int sx = src_w - 1 - dx;
                int sy = src_h - 1 - dy;
                size_t s_idx = ((size_t)sy * src_w + sx) * 3;
                size_t d_idx = ((size_t)dy * dw + dx) * 3;
                d[d_idx + 0] = src[s_idx + 0];
                d[d_idx + 1] = src[s_idx + 1];
                d[d_idx + 2] = src[s_idx + 2];
            }
        }
        return 0;
    }

    if (rot == 270) {
        *dst_w = src_h;
        *dst_h = src_w;
        size_t size = (size_t)(*dst_w) * (*dst_h) * 3;
        *dst = malloc(size);
        if (*dst == NULL) return -1;

        uint8_t *d = *dst;
        int dw = *dst_w;
        int dh = *dst_h;

        for (int dy = 0; dy < dh; dy++) {
            for (int dx = 0; dx < dw; dx++) {
                int sx = src_w - 1 - dy;
                int sy = dx;
                size_t s_idx = ((size_t)sy * src_w + sx) * 3;
                size_t d_idx = ((size_t)dy * dw + dx) * 3;
                d[d_idx + 0] = src[s_idx + 0];
                d[d_idx + 1] = src[s_idx + 1];
                d[d_idx + 2] = src[s_idx + 2];
            }
        }
        return 0;
    }

    return -1;
}
