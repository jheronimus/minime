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
#include <drm/drm_fourcc.h>

static uint32_t plane_fb_id_from_props(int fd, uint32_t plane_id) {
    struct drm_mode_obj_get_properties req = {0};
    req.obj_id = plane_id;
    req.obj_type = DRM_MODE_OBJECT_PLANE;

    if (ioctl(fd, DRM_IOCTL_MODE_OBJ_GETPROPERTIES, &req) < 0 || req.count_props == 0)
        return 0;

    uint32_t *prop_ids = calloc(req.count_props, sizeof(uint32_t));
    uint64_t *prop_vals = calloc(req.count_props, sizeof(uint64_t));
    if (!prop_ids || !prop_vals) {
        free(prop_ids);
        free(prop_vals);
        return 0;
    }

    req.props_ptr = (uint64_t)(uintptr_t)prop_ids;
    req.prop_values_ptr = (uint64_t)(uintptr_t)prop_vals;
    if (ioctl(fd, DRM_IOCTL_MODE_OBJ_GETPROPERTIES, &req) < 0) {
        free(prop_ids);
        free(prop_vals);
        return 0;
    }

    uint32_t fb_id = 0;
    for (uint32_t i = 0; i < req.count_props; i++) {
        struct drm_mode_get_property prop = {0};
        prop.prop_id = prop_ids[i];
        if (ioctl(fd, DRM_IOCTL_MODE_GETPROPERTY, &prop) == 0) {
            if (strcmp(prop.name, "FB_ID") == 0) {
                fb_id = (uint32_t)prop_vals[i];
                break;
            }
        }
    }

    free(prop_ids);
    free(prop_vals);
    return fb_id;
}

static int map_and_convert_fb(int fd, uint32_t fb_id,
                              uint8_t **out_rgb, int *out_w, int *out_h) {
    uint32_t width = 0, height = 0, pitch = 0, handle = 0, format = 0;
    int bpp = 32;

    /* Try GETFB2 first (standard modern DRM interface for cross-process handles) */
    struct drm_mode_fb_cmd2 fb2 = {0};
    fb2.fb_id = fb_id;
    if (ioctl(fd, DRM_IOCTL_MODE_GETFB2, &fb2) == 0 && fb2.width && fb2.height && fb2.handles[0]) {
        width = fb2.width;
        height = fb2.height;
        pitch = fb2.pitches[0];
        handle = fb2.handles[0];
        format = fb2.pixel_format;
        if (format == DRM_FORMAT_RGB565 || format == DRM_FORMAT_BGR565) {
            bpp = 16;
        } else if (format == DRM_FORMAT_RGB888 || format == DRM_FORMAT_BGR888) {
            bpp = 24;
        } else {
            bpp = 32;
        }
    } else {
        /* Fallback to legacy GETFB */
        struct drm_mode_fb_cmd fb = {0};
        fb.fb_id = fb_id;
        if (ioctl(fd, DRM_IOCTL_MODE_GETFB, &fb) < 0 || fb.width == 0 || fb.height == 0 || fb.pitch == 0)
            return -1;
        width = fb.width;
        height = fb.height;
        pitch = fb.pitch;
        handle = fb.handle;
        bpp = (int)fb.bpp;
    }

    size_t map_size = (size_t)pitch * height;
    void *map = MAP_FAILED;

    /* 1. Try PRIME DMA-BUF export */
    struct drm_prime_handle prime = {0};
    prime.handle = handle;
    prime.flags = DRM_CLOEXEC | DRM_RDWR;
    if (ioctl(fd, DRM_IOCTL_PRIME_HANDLE_TO_FD, &prime) == 0) {
        map = mmap(NULL, map_size, PROT_READ, MAP_SHARED, prime.fd, 0);
        close(prime.fd);
    }

    /* 2. Fallback to dumb buffer mapping */
    if (map == MAP_FAILED || map == NULL) {
        struct drm_mode_map_dumb mreq = {0};
        mreq.handle = handle;
        if (ioctl(fd, DRM_IOCTL_MODE_MAP_DUMB, &mreq) == 0) {
            map = mmap(NULL, map_size, PROT_READ, MAP_SHARED, fd, mreq.offset);
        }
    }

    if (map == MAP_FAILED || map == NULL) {
        struct drm_gem_close cl = { .handle = handle };
        ioctl(fd, DRM_IOCTL_GEM_CLOSE, &cl);
        return -1;
    }

    size_t rgb_size = (size_t)width * height * 3;
    uint8_t *rgb = malloc(rgb_size);
    if (!rgb) {
        munmap(map, map_size);
        struct drm_gem_close cl = { .handle = handle };
        ioctl(fd, DRM_IOCTL_GEM_CLOSE, &cl);
        return -1;
    }

    const uint8_t *src = (const uint8_t *)map;
    int w = (int)width;
    int h = (int)height;
    int p = (int)pitch;

    for (int y = 0; y < h; y++) {
        const uint8_t *row = src + (size_t)y * p;
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
    struct drm_gem_close cl = { .handle = handle };
    ioctl(fd, DRM_IOCTL_GEM_CLOSE, &cl);

    *out_rgb = rgb;
    *out_w = w;
    *out_h = h;
    return 0;
}

int drm_capture_rgb(const char *device_path, uint8_t **out_rgb, int *out_w, int *out_h) {
    if (!out_rgb || !out_w || !out_h) return -1;
    *out_rgb = NULL;
    *out_w = 0;
    *out_h = 0;

    const char *path = device_path ? device_path : "/dev/dri/card0";
    int fd = open(path, O_RDWR | O_CLOEXEC);
    if (fd < 0) return -1;

    /* Enable universal planes and atomic properties so primary planes and FB_IDs are exposed */
    struct drm_set_client_cap cap_univ = { .capability = DRM_CLIENT_CAP_UNIVERSAL_PLANES, .value = 1 };
    ioctl(fd, DRM_IOCTL_SET_CLIENT_CAP, &cap_univ);

    struct drm_set_client_cap cap_atomic = { .capability = DRM_CLIENT_CAP_ATOMIC, .value = 1 };
    ioctl(fd, DRM_IOCTL_SET_CLIENT_CAP, &cap_atomic);

    uint32_t active_fb = 0;

    /* 1. Walk planes for active FB_ID */
    struct drm_mode_get_plane_res pres = {0};
    ioctl(fd, DRM_IOCTL_MODE_GETPLANERESOURCES, &pres);
    if (pres.count_planes > 0) {
        uint32_t *plane_ids = calloc(pres.count_planes, sizeof(uint32_t));
        pres.plane_id_ptr = (uint64_t)(uintptr_t)plane_ids;
        if (ioctl(fd, DRM_IOCTL_MODE_GETPLANERESOURCES, &pres) == 0) {
            for (uint32_t i = 0; i < pres.count_planes && !active_fb; i++) {
                struct drm_mode_get_plane plane = {0};
                plane.plane_id = plane_ids[i];
                if (ioctl(fd, DRM_IOCTL_MODE_GETPLANE, &plane) == 0 && plane.fb_id) {
                    active_fb = plane.fb_id;
                } else {
                    active_fb = plane_fb_id_from_props(fd, plane_ids[i]);
                }
            }
        }
        free(plane_ids);
    }

    /* 2. If plane walk found nothing, check CRTCs */
    if (!active_fb) {
        struct drm_mode_card_res res = {0};
        if (ioctl(fd, DRM_IOCTL_MODE_GETRESOURCES, &res) == 0 && res.count_crtcs > 0) {
            uint32_t *crtc_ids = calloc(res.count_crtcs, sizeof(uint32_t));
            uint32_t *conn_ids = calloc(res.count_connectors, sizeof(uint32_t));
            uint32_t *enc_ids = calloc(res.count_encoders, sizeof(uint32_t));
            uint32_t *fb_ids = calloc(res.count_fbs, sizeof(uint32_t));
            if (crtc_ids && conn_ids && enc_ids && fb_ids) {
                res.crtc_id_ptr = (uint64_t)(uintptr_t)crtc_ids;
                res.connector_id_ptr = (uint64_t)(uintptr_t)conn_ids;
                res.encoder_id_ptr = (uint64_t)(uintptr_t)enc_ids;
                res.fb_id_ptr = (uint64_t)(uintptr_t)fb_ids;
                if (ioctl(fd, DRM_IOCTL_MODE_GETRESOURCES, &res) == 0) {
                    for (uint32_t i = 0; i < res.count_crtcs && !active_fb; i++) {
                        struct drm_mode_crtc crtc = {0};
                        crtc.crtc_id = crtc_ids[i];
                        if (ioctl(fd, DRM_IOCTL_MODE_GETCRTC, &crtc) == 0 &&
                            crtc.mode_valid && crtc.fb_id)
                            active_fb = crtc.fb_id;
                    }
                }
            }
            free(crtc_ids);
            free(conn_ids);
            free(enc_ids);
            free(fb_ids);
        }
    }

    if (!active_fb) {
        close(fd);
        return -1;
    }

    int ret = map_and_convert_fb(fd, active_fb, out_rgb, out_w, out_h);
    close(fd);
    return ret;
}
