#ifndef DRM_H
#define DRM_H

#include <stddef.h>
#include <stdint.h>

/*
 * Capture the active DRM/KMS primary CRTC/plane framebuffer as RGB24 (8-bit per channel).
 * If device_path is NULL, defaults to /dev/dri/card0.
 * Returns 0 on success, -1 on failure (e.g. no DRM device or no active CRTC/FB).
 */
int drm_capture_rgb(const char *device_path, uint8_t **out_rgb, int *out_w, int *out_h);

#endif /* DRM_H */
