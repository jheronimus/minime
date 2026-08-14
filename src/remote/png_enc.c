#include "png_enc.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "stb_image_write.h"

struct mem_buffer {
    uint8_t *data;
    size_t size;
    size_t capacity;
};

static void write_to_mem_cb(void *context, void *data, int size) {
    struct mem_buffer *buf = (struct mem_buffer *)context;
    if (size <= 0) return;
    if (buf->size + (size_t)size > buf->capacity) {
        size_t new_cap = (buf->capacity == 0) ? 65536 : buf->capacity * 2;
        while (new_cap < buf->size + (size_t)size) {
            new_cap *= 2;
        }
        uint8_t *new_data = realloc(buf->data, new_cap);
        if (!new_data) return;
        buf->data = new_data;
        buf->capacity = new_cap;
    }
    memcpy(buf->data + buf->size, data, (size_t)size);
    buf->size += (size_t)size;
}

static void write_to_file_cb(void *context, void *data, int size) {
    FILE *f = (FILE *)context;
    if (size > 0 && f) {
        fwrite(data, 1, (size_t)size, f);
    }
}

int png_encode_rgb_to_file(const char *path, const uint8_t *rgb, int w, int h) {
    if (!rgb || w <= 0 || h <= 0) return -1;

    if (!path || strcmp(path, "-") == 0) {
        // Write to stdout
        int ret = stbi_write_png_to_func(write_to_file_cb, stdout, w, h, 3, rgb, w * 3);
        fflush(stdout);
        return ret ? 0 : -1;
    }

    int ret = stbi_write_png(path, w, h, 3, rgb, w * 3);
    return ret ? 0 : -1;
}

int png_encode_rgb_to_mem(const uint8_t *rgb, int w, int h, uint8_t **out_data, size_t *out_size) {
    if (!rgb || w <= 0 || h <= 0 || !out_data || !out_size) return -1;

    struct mem_buffer buf = {0};
    int ret = stbi_write_png_to_func(write_to_mem_cb, &buf, w, h, 3, rgb, w * 3);
    if (!ret || !buf.data) {
        free(buf.data);
        *out_data = NULL;
        *out_size = 0;
        return -1;
    }

    *out_data = buf.data;
    *out_size = buf.size;
    return 0;
}
