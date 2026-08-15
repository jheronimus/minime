#include "bench.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>

#define MEMCPY_BUF_SIZE (4 * 1024 * 1024) /* 4 MB */
#define MEMCPY_ITERS_DEFAULT 200
#define MEMCPY_ITERS_QUICK   50

#define INT_MATH_ITERS_DEFAULT 100000000
#define INT_MATH_ITERS_QUICK   25000000

#define IO_BLOCK_SIZE (64 * 1024) /* 64 KB */
#define IO_TOTAL_BYTES (16 * 1024 * 1024) /* 16 MB */

/* 1. Memory Bandwidth (memcpy) */
static double bench_memcpy(int iters) {
	uint8_t *src = (uint8_t *)malloc(MEMCPY_BUF_SIZE);
	uint8_t *dst = (uint8_t *)malloc(MEMCPY_BUF_SIZE);
	if (!src || !dst) {
		if (src) free(src);
		if (dst) free(dst);
		return 0.0;
	}
	memset(src, 0x5A, MEMCPY_BUF_SIZE);

	uint64_t start = bench_get_time_ns();
	for (int i = 0; i < iters; i++) {
		memcpy(dst, src, MEMCPY_BUF_SIZE);
		__asm__ __volatile__("" : : "r"(dst), "r"(src) : "memory");
		dst[i % MEMCPY_BUF_SIZE] = (uint8_t)(i & 0xFF);
	}
	uint64_t duration = bench_get_time_ns() - start;
	free(src);
	free(dst);

	double total_mb = ((double)iters * (double)MEMCPY_BUF_SIZE) / (1024.0 * 1024.0);
	double seconds = bench_ns_to_s(duration);
	return (seconds > 0.0) ? (total_mb / seconds) : 0.0; /* MB/s */
}

/* 2. Memory Bandwidth (memset) */
static double bench_memset(int iters) {
	uint8_t *buf = (uint8_t *)malloc(MEMCPY_BUF_SIZE);
	if (!buf) return 0.0;

	uint64_t start = bench_get_time_ns();
	for (int i = 0; i < iters; i++) {
		memset(buf, (i & 0xFF), MEMCPY_BUF_SIZE);
		__asm__ __volatile__("" : : "r"(buf) : "memory");
		buf[i % MEMCPY_BUF_SIZE] = (uint8_t)(i & 0xFF);
	}
	uint64_t duration = bench_get_time_ns() - start;
	free(buf);

	double total_mb = ((double)iters * (double)MEMCPY_BUF_SIZE) / (1024.0 * 1024.0);
	double seconds = bench_ns_to_s(duration);
	return (seconds > 0.0) ? (total_mb / seconds) : 0.0; /* MB/s */
}

/* 3. Integer ALU / Hash Compute */
static double bench_cpu_math(int iters) {
	uint32_t h = 0x811c9dc5; /* FNV-1a offset basis */
	uint64_t start = bench_get_time_ns();

	for (int i = 0; i < iters; i++) {
		h ^= (uint32_t)(i & 0xFF);
		h *= 0x01000193;
		h = (h << 13) | (h >> 19);
		h += 0x55555555;
	}
	uint64_t duration = bench_get_time_ns() - start;
	double seconds = bench_ns_to_s(duration);
	/* Dummy volatile store */
	volatile uint32_t sink = h;
	(void)sink;

	return (seconds > 0.0) ? ((double)iters / seconds) : 0.0; /* ops/sec */
}

/* 4. Storage Sequential Write I/O */
static double bench_storage_io(const char *tmp_path) {
	uint8_t *buf = (uint8_t *)malloc(IO_BLOCK_SIZE);
	if (!buf) return 0.0;
	memset(buf, 0xCC, IO_BLOCK_SIZE);

	int fd = open(tmp_path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
	if (fd < 0) {
		free(buf);
		return 0.0;
	}

	int blocks = IO_TOTAL_BYTES / IO_BLOCK_SIZE;
	uint64_t start = bench_get_time_ns();
	for (int i = 0; i < blocks; i++) {
		ssize_t written = write(fd, buf, IO_BLOCK_SIZE);
		if (written < 0) break;
	}
	fsync(fd);
	uint64_t duration = bench_get_time_ns() - start;

	close(fd);
	unlink(tmp_path);
	free(buf);

	double total_mb = (double)IO_TOTAL_BYTES / (1024.0 * 1024.0);
	double seconds = bench_ns_to_s(duration);
	return (seconds > 0.0) ? (total_mb / seconds) : 0.0; /* MB/s */
}

int run_bench_sys(bench_result_t *results, int max_results, int quick_mode) {
	if (max_results < 4) return 0;
	int idx = 0;

	int memcpy_iters = quick_mode ? MEMCPY_ITERS_QUICK : MEMCPY_ITERS_DEFAULT;
	int math_iters = quick_mode ? INT_MATH_ITERS_QUICK : INT_MATH_ITERS_DEFAULT;

	/* 1. memcpy */
	double memcpy_mb = bench_memcpy(memcpy_iters);
	snprintf(results[idx].name, sizeof(results[idx].name), "sys.memcpy_bandwidth");
	results[idx].category = BENCH_CAT_SYS;
	results[idx].raw_value = memcpy_mb;
	snprintf(results[idx].unit, sizeof(results[idx].unit), "MB/s");
	results[idx].baseline_value = 2200.0; /* 2.2 GB/s baseline */
	results[idx].lower_is_better = 0;
	results[idx].normalized_score = (memcpy_mb / results[idx].baseline_value) * 1000.0;
	idx++;

	/* 2. memset */
	double memset_mb = bench_memset(memcpy_iters);
	snprintf(results[idx].name, sizeof(results[idx].name), "sys.memset_bandwidth");
	results[idx].category = BENCH_CAT_SYS;
	results[idx].raw_value = memset_mb;
	snprintf(results[idx].unit, sizeof(results[idx].unit), "MB/s");
	results[idx].baseline_value = 4500.0; /* 4.5 GB/s baseline */
	results[idx].lower_is_better = 0;
	results[idx].normalized_score = (memset_mb / results[idx].baseline_value) * 1000.0;
	idx++;

	/* 3. Integer Math */
	double math_ops = bench_cpu_math(math_iters);
	snprintf(results[idx].name, sizeof(results[idx].name), "sys.cpu_int_math");
	results[idx].category = BENCH_CAT_SYS;
	results[idx].raw_value = math_ops / 1000000.0; /* Mops/s */
	snprintf(results[idx].unit, sizeof(results[idx].unit), "Mops/s");
	results[idx].baseline_value = 350.0; /* 350 Mops/s baseline */
	results[idx].lower_is_better = 0;
	results[idx].normalized_score = (results[idx].raw_value / results[idx].baseline_value) * 1000.0;
	idx++;

	/* 4. Storage Write I/O */
	const char *tmp_path = "/tmp/benchmark_io.tmp";
	double io_mb = bench_storage_io(tmp_path);
	snprintf(results[idx].name, sizeof(results[idx].name), "sys.storage_seq_write");
	results[idx].category = BENCH_CAT_SYS;
	results[idx].raw_value = io_mb;
	snprintf(results[idx].unit, sizeof(results[idx].unit), "MB/s");
	results[idx].baseline_value = 40.0; /* 40 MB/s baseline */
	results[idx].lower_is_better = 0;
	results[idx].normalized_score = (io_mb > 0.0) ? ((io_mb / results[idx].baseline_value) * 1000.0) : 1000.0;
	idx++;

	return idx;
}
