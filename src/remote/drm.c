#include "drm.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <drm/drm.h>
#include <drm/drm_mode.h>

int drm_capture_rgb(const char *device_path, uint8_t **out_rgb, int *out_w, int *out_h) {
    if (!out_rgb || !out_w || !out_h) return -1;
    *out_rgb = NULL;
    *out_w = 0;
    *out_h = 0;

    const char *path = device_path ? device_path : "/dev/dri/card0";
    int fd = open(path, O_RDWR | O_CLOEXEC);
    if (fd < 0) {
        return -1;
    }

    struct drm_mode_card_res res = {0};
    if (ioctl(fd, DRM_IOCTL_MODE_GETRESOURCES, &res) < 0) {
        close(fd);
        return -1;
    }

    uint32_t *crtc_ids = NULL;
    uint32_t *fb_ids = NULL;
    if (res.count_crtcs > 0) {
        crtc_ids = calloc(res.count_crtcs, sizeof(uint32_t));
        res.crtc_id_ptr = (uint64_t)(uintptr_t)crtc_ids;
    }
    if (res.count_fbs > 0) {
        fb_ids = calloc(res.count_fbs, sizeof(uint32_t));
        res.fb_id_ptr = (uint64_t)(uintptr_t)fb_ids;
    }

    if (ioctl(fd, DRM_IOCTL_MODE_GETRESOURCES, &res) < 0) {
        free(crtc_ids);
        free(fb_ids);
        close(fd);
        return -1;
    }

    uint32_t active_fb = 0;
    for (uint32_t i = 0; i < res.count_crtcs; i++) {
        struct drm_mode_crtc crtc = {0};
        crtc.crtc_id = crtc_ids[i];
        if (ioctl(fd, DRM_IOCTL_MODE_GETCRTC, &crtc) == 0) {
            if (crtc.mode_valid && crtc.fb_id) {
                active_fb = crtc.fb_id;
                break;
            }
        }
    }

    if (!active_fb) {
        struct drm_mode_get_plane_res pres = {0};
        if (ioctl(fd, DRM_IOCTL_MODE_GETPLANERESOURCES, &pres) == 0 && pres.count_planes > 0) {
            uint32_t *plane_ids = calloc(pres.count_planes, sizeof(uint32_t));
            pres.plane_id_ptr = (uint64_t)(uintptr_t)plane_ids;
            if (ioctl(fd, DRM_IOCTL_MODE_GETPLANERESOURCES, &pres) == 0) {
                for (uint32_t i = 0; i < pres.count_planes; i++) {
                    struct drm_mode_get_plane plane = {0};
                    plane.plane_id = plane_ids[i];
                    if (ioctl(fd, DRM_IOCTL_MODE_GETPLANE, &plane) == 0) {
                        if (plane.fb_id) {
                            active_fb = plane.fb_id;
                            break;
                        }
                    }
                }
            }
            free(plane_ids);
        }
    }

    free(crtc_ids);
    free(fb_ids);

    if (!active_fb) {
        close(fd);
        return -1;
    }

    struct drm_mode_fb_cmd fb = {0};
    fb.fb_id = active_fb;
    if (ioctl(fd, DRM_IOCTL_MODE_GETFB, &fb) < 0 || fb.width == 0 || fb.height == 0 || fb.pitch == 0) {
        close(fd);
        return -1;
    }

    size_t map_size = (size_t)fb.pitch * fb.height;
    void *map = MAP_FAILED;

    struct drm_mode_map_dumb mreq = {0};
    mreq.handle = fb.handle;
    if (ioctl(fd, DRM_IOCTL_MODE_MAP_DUMB, &mreq) == 0) {
        map = mmap(NULL, map_size, PROT_READ, MAP_SHARED, fd, mreq.offset);
    }

    if (map == MAP_FAILED || map == NULL) {
        struct drm_prime_handle prime = {0};
        prime.handle = fb.handle;
        prime.flags = DRM_CLOEXEC | DRM_RDWR;
        if (ioctl(fd, DRM_IOCTL_PRIME_HANDLE_TO_FD, &prime) == 0) {
            map = mmap(NULL, map_size, PROT_READ, MAP_SHARED, prime.fd, 0);
            close(prime.fd);
        }
    }

    if (map == MAP_FAILED || map == NULL) {
        close(fd);
        return -1;
    }

    size_t rgb_size = (size_t)fb.width * fb.height * 3;
    uint8_t *rgb = malloc(rgb_size);
    if (!rgb) {
        munmap(map, map_size);
        close(fd);
        return -1;
    }

    const uint8_t *src_bytes = (const uint8_t *)map;
    int bpp = (int)fb.bpp;
    int w = (int)fb.width;
    int h = (int)fb.height;
    int pitch = (int)fb.pitch;

    for (int y = 0; y < h; y++) {
        const uint8_t *row = src_bytes + (size_t)y * pitch;
        uint8_t *dst_row = rgb + (size_t)y * w * 3;

        if (bpp == 32) {
            for (int x = 0; x < w; x++) {
                uint32_t px = *(const uint32_t *)(row + x * 4);
                dst_row[x * 3 + 0] = (uint8_t)((px >> 16) & 0xFF);
                dst_row[x * 3 + 1] = (uint8_t)((px >> 8) & 0xFF);
                dst_row[x * 3 + 2] = (uint8_t)(px & 0xFF);
            }
        } else if (bpp == 16) {
            for (int x = 0; x < w; x++) {
                uint16_t px = *(const uint16_t *)(row + x * 2);
                uint8_t r = (uint8_t)((px >> 11) & 0x1F);
                uint8_t g = (uint8_t)((px >> 5) & 0x3F);
                uint8_t b = (uint8_t)(px & 0x1F);
                dst_row[x * 3 + 0] = (uint8_t)((r << 3) | (r >> 2));
                dst_row[x * 3 + 1] = (uint8_t)((g << 2) | (g >> 4));
                dst_row[x * 3 + 2] = (uint8_t)((b << 3) | (b >> 2));
            }
        } else if (bpp == 24) {
            for (int x = 0; x < w; x++) {
                dst_row[x * 3 + 0] = row[x * 3 + 2];
                dst_row[x * 3 + 1] = row[x * 3 + 1];
                dst_row[x * 3 + 2] = row[x * 3 + 0];
            }
        } else {
            for (int x = 0; x < w; x++) {
                dst_row[x * 3 + 0] = row[x];
                dst_row[x * 3 + 1] = row[x];
                dst_row[x * 3 + 2] = row[x];
            }
        }
    }

    munmap(map, map_size);
    close(fd);

    *out_rgb = rgb;
    *out_w = w;
    *out_h = h;
    return 0;
}
