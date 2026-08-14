#ifndef PNG_ENC_H
#define PNG_ENC_H

#include <stddef.h>
#include <stdint.h>

/*
 * Encode a 24-bit RGB pixel buffer (w x h x 3 bytes) into PNG format.
 * path: file path to write, or "-" for stdout.
 * Returns 0 on success, -1 on failure.
 */
int png_encode_rgb_to_file(const char *path, const uint8_t *rgb, int w, int h);

/*
 * Encode a 24-bit RGB pixel buffer into an in-memory PNG buffer.
 * *out_data must be freed by caller using free().
 * Returns 0 on success, -1 on failure.
 */
int png_encode_rgb_to_mem(const uint8_t *rgb, int w, int h, uint8_t **out_data, size_t *out_size);

#endif /* PNG_ENC_H */
