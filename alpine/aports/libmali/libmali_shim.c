#define _GNU_SOURCE
#include <fcntl.h>
#include <stdlib.h>
#include <stdarg.h>
#include <pthread.h>

// fcntl64 symbol for glibc compatibility
int fcntl64(int fd, int cmd, ...) {
    va_list ap;
    void *arg;
    va_start(ap, cmd);
    arg = va_arg(ap, void *);
    va_end(ap);
    return fcntl(fd, cmd, arg);
}

// __register_atfork symbol for glibc compatibility
extern int pthread_atfork(void (*prepare)(void), void (*parent)(void), void (*child)(void));
int __register_atfork(void (*prepare)(void), void (*parent)(void), void (*child)(void), void *dso_handle) {
    return pthread_atfork(prepare, parent, child);
}

// struct mallinfo and mallinfo symbol for glibc compatibility
struct mallinfo {
  int arena;
  int ordblks;
  int smblks;
  int hblks;
  int hblkhd;
  int usmblks;
  int fsmblks;
  int uordblks;
  int fordblks;
  int keepcost;
};

struct mallinfo mallinfo(void) {
    struct mallinfo mi = {0};
    return mi;
}

// strtol_l and strtoul_l symbols for glibc compatibility
long strtol_l(const char *nptr, char **endptr, int base, locale_t loc) {
    return strtol(nptr, endptr, base);
}

unsigned long strtoul_l(const char *nptr, char **endptr, int base, locale_t loc) {
    return strtoul(nptr, endptr, base);
}
