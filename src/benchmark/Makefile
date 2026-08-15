CC ?= gcc
CFLAGS ?= -O2 -Wall -Wextra -std=c99 -D_POSIX_C_SOURCE=200809L -D_DEFAULT_SOURCE
LDFLAGS ?=
LDLIBS ?= -pthread -lm
PREFIX ?= /usr
DESTDIR ?=

TARGET = benchmark
SRCS = main.c bench_mem.c bench_sys.c bench_emu.c bench_ui.c score.c
OBJS = $(SRCS:.c=.o)

all: $(TARGET)

$(TARGET): $(OBJS)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $(OBJS) $(LDLIBS)

%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

install: $(TARGET)
	install -D -m 0755 $(TARGET) $(DESTDIR)$(PREFIX)/bin/$(TARGET)

clean:
	rm -f $(OBJS) $(TARGET)

.PHONY: all install clean
