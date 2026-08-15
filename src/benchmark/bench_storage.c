#include "bench.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>

#define STORAGE_BUF_SIZE (1 * 1024 * 1024) /* 1 MB */
#define STORAGE_TOTAL_MB_DEFAULT 16
#define STORAGE_TOTAL_MB_QUICK   4

#define RAND_4K_ITERS_DEFAULT 500
#define RAND_4K_ITERS_QUICK   100

static const char *get_storage_path(void) {
	struct stat st;
	if (stat("/mnt/sdcard", &st) == 0 && S_ISDIR(st.st_mode)) {
		return "/mnt/sdcard/.benchmark_io.tmp";
	}
	return "/tmp/.benchmark_io.tmp";
}

/* 1. Sequential Write Throughput */
static double bench_storage_seq_write(int total_mb) {
	const char *path = get_storage_path();
	int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
	if (fd < 0) return 0.0;

	uint8_t *buf = (uint8_t *)malloc(STORAGE_BUF_SIZE);
	if (!buf) {
		close(fd);
		return 0.0;
	}
	memset(buf, 0xA5, STORAGE_BUF_SIZE);

	uint64_t start = bench_get_time_ns();
	for (int i = 0; i < total_mb; i++) {
		ssize_t written = write(fd, buf, STORAGE_BUF_SIZE);
		if (written < 0) break;
	}
	fsync(fd);
	uint64_t duration = bench_get_time_ns() - start;

	close(fd);
	free(buf);

	double seconds = bench_ns_to_s(duration);
	return (seconds > 0.0) ? ((double)total_mb / seconds) : 0.0; /* MB/s */
}

/* 2. Sequential Read Throughput */
static double bench_storage_seq_read(int total_mb) {
	const char *path = get_storage_path();
	int fd = open(path, O_RDONLY);
	if (fd < 0) return 0.0;

	uint8_t *buf = (uint8_t *)malloc(STORAGE_BUF_SIZE);
	if (!buf) {
		close(fd);
		return 0.0;
	}

	uint64_t start = bench_get_time_ns();
	for (int i = 0; i < total_mb; i++) {
		ssize_t rd = read(fd, buf, STORAGE_BUF_SIZE);
		if (rd <= 0) break;
	}
	uint64_t duration = bench_get_time_ns() - start;

	close(fd);
	free(buf);

	double seconds = bench_ns_to_s(duration);
	return (seconds > 0.0) ? ((double)total_mb / seconds) : 0.0; /* MB/s */
}

/* 3. Random 4KB IOPS */
static double bench_storage_rand_4k(int iters) {
	const char *path = get_storage_path();
	int fd = open(path, O_RDWR);
	if (fd < 0) return 0.0;

	uint8_t block[4096];
	memset(block, 0x55, sizeof(block));

	uint64_t start = bench_get_time_ns();
	for (int i = 0; i < iters; i++) {
		off_t offset = (off_t)((i * 4096) % (4 * 1024 * 1024));
		pwrite(fd, block, sizeof(block), offset);
		pread(fd, block, sizeof(block), offset);
	}
	uint64_t duration = bench_get_time_ns() - start;

	close(fd);
	unlink(path);

	double seconds = bench_ns_to_s(duration);
	return (seconds > 0.0) ? ((double)(iters * 2) / seconds) : 0.0; /* IOPS */
}

int run_bench_storage(bench_result_t *results, int max_results, int quick_mode) {
	if (max_results < 3) return 0;
	int idx = 0;

	int total_mb = quick_mode ? STORAGE_TOTAL_MB_QUICK : STORAGE_TOTAL_MB_DEFAULT;
	int rand_iters = quick_mode ? RAND_4K_ITERS_QUICK : RAND_4K_ITERS_DEFAULT;

	/* 1. Sequential Write */
	double write_mb = bench_storage_seq_write(total_mb);
	snprintf(results[idx].name, sizeof(results[idx].name), "storage.seq_write");
	results[idx].category = BENCH_CAT_STORAGE;
	results[idx].raw_value = write_mb;
	snprintf(results[idx].unit, sizeof(results[idx].unit), "MB/s");
	results[idx].baseline_value = 22.0; /* 22 MB/s SD card write baseline */
	results[idx].lower_is_better = 0;
	results[idx].skipped = (write_mb <= 0.0) ? 1 : 0;
	results[idx].normalized_score = (write_mb > 0.0) ? ((write_mb / results[idx].baseline_value) * 1000.0) : 0.0;
	idx++;

	/* 2. Sequential Read */
	double read_mb = bench_storage_seq_read(total_mb);
	snprintf(results[idx].name, sizeof(results[idx].name), "storage.seq_read");
	results[idx].category = BENCH_CAT_STORAGE;
	results[idx].raw_value = read_mb;
	snprintf(results[idx].unit, sizeof(results[idx].unit), "MB/s");
	results[idx].baseline_value = 500.0; /* 500 MB/s cache/direct read baseline */
	results[idx].lower_is_better = 0;
	results[idx].skipped = (read_mb <= 0.0) ? 1 : 0;
	results[idx].normalized_score = (read_mb > 0.0) ? ((read_mb / results[idx].baseline_value) * 1000.0) : 0.0;
	idx++;

	/* 3. Random 4K IOPS */
	double iops = bench_storage_rand_4k(rand_iters);
	snprintf(results[idx].name, sizeof(results[idx].name), "storage.rand_4k_iops");
	results[idx].category = BENCH_CAT_STORAGE;
	results[idx].raw_value = iops;
	snprintf(results[idx].unit, sizeof(results[idx].unit), "IOPS");
	results[idx].baseline_value = 65000.0; /* 65k IOPS baseline */
	results[idx].lower_is_better = 0;
	results[idx].skipped = (iops <= 0.0) ? 1 : 0;
	results[idx].normalized_score = (iops > 0.0) ? ((iops / results[idx].baseline_value) * 1000.0) : 0.0;
	idx++;

	return idx;
}
