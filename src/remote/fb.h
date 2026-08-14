#ifndef FB_H
#define FB_H

#include <stddef.h>
#include <stdint.h>

/*
 * Capture the current contents of the Linux framebuffer device (e.g. /dev/fb0).
 * *out_rgb will be allocated (w x h x 3 bytes, RGB888) and must be freed by caller.
 * *out_width and *out_height will be populated with actual screen dimensions.
 * Returns 0 on success, -1 on error.
 */
int fb_capture(const char *device_path, uint8_t **out_rgb, int *out_width, int *out_height);

#endif /* FB_H */
