#ifndef ROTATE_H
#define ROTATE_H

#include <stddef.h>
#include <stdint.h>

int image_rotate_rgb(const uint8_t *src, int src_w, int src_h, int rotation,
                     uint8_t **dst, int *dst_w, int *dst_h);

#endif /* ROTATE_H */
