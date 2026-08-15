CC ?= cc
CFLAGS ?= -O2 -Wall -Wextra -std=c99
CFLAGS += -D_POSIX_C_SOURCE=200809L -D_DEFAULT_SOURCE
LDFLAGS ?=
LDLIBS ?= -pthread -lm -ldl

TARGET = benchmark
SRCS = main.c bench_cpu.c bench_mem.c bench_gpu.c bench_storage.c bench_net.c score.c
OBJS = $(SRCS:.c=.o)

all: $(TARGET)

$(TARGET): $(OBJS)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $(OBJS) $(LDLIBS)

%.o: %.c bench.h
	$(CC) $(CFLAGS) -c $< -o $@

clean:
	rm -f $(OBJS) $(TARGET) benchmark_aarch64

.PHONY: all clean
