#define _GNU_SOURCE
#include <time.h>
#include <dlfcn.h>

int clock_gettime(clockid_t clk_id, struct timespec *tp) {
    static int (*real_clock_gettime)(clockid_t, struct timespec *) = NULL;
    if (!real_clock_gettime) {
        real_clock_gettime = dlsym(RTLD_NEXT, "clock_gettime");
    }
    
    // Redirect CLOCK_MONOTONIC_RAW (4) to CLOCK_MONOTONIC (1)
    if (clk_id == 4) {
        clk_id = 1;
    }
    
    return real_clock_gettime(clk_id, tp);
}
