#include "bench.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define MEM_BUF_SIZE (8 * 1024 * 1024) /* 8 MB */
#define MEM_ITERS_DEFAULT 100
#define MEM_ITERS_QUICK   25

#define CHURN_ITERS_DEFAULT 200000
#define CHURN_ITERS_QUICK   50000

#define LATENCY_BUF_SIZE (4 * 1024 * 1024) /* 4 MB */
#define LATENCY_ITERS    5000000

static inline uint32_t lcg_rand(uint32_t *state) {
	*state = *state * 1664525 + 1013904223;
	return *state;
}

/* 1. Memory Bandwidth (memcpy) */
static double bench_tinymem_memcpy(int iters) {
	uint8_t *src = (uint8_t *)malloc(MEM_BUF_SIZE);
	uint8_t *dst = (uint8_t *)malloc(MEM_BUF_SIZE);
	if (!src || !dst) {
		if (src) free(src);
		if (dst) free(dst);
		return 0.0;
	}
	memset(src, 0x5A, MEM_BUF_SIZE);

	uint64_t start = bench_get_time_ns();
	for (int i = 0; i < iters; i++) {
		memcpy(dst, src, MEM_BUF_SIZE);
		__asm__ __volatile__("" : : "r"(dst), "r"(src) : "memory");
		dst[i % MEM_BUF_SIZE] = (uint8_t)(i & 0xFF);
	}
	uint64_t duration = bench_get_time_ns() - start;
	free(src);
	free(dst);

	double total_mb = ((double)iters * (double)MEM_BUF_SIZE) / (1024.0 * 1024.0);
	double seconds = bench_ns_to_s(duration);
	return (seconds > 0.0) ? (total_mb / seconds) : 0.0; /* MB/s */
}

/* 2. Memory Bandwidth (memset) */
static double bench_tinymem_memset(int iters) {
	uint8_t *buf = (uint8_t *)malloc(MEM_BUF_SIZE);
	if (!buf) return 0.0;

	uint64_t start = bench_get_time_ns();
	for (int i = 0; i < iters; i++) {
		memset(buf, (i & 0xFF), MEM_BUF_SIZE);
		__asm__ __volatile__("" : : "r"(buf) : "memory");
		buf[i % MEM_BUF_SIZE] = (uint8_t)(i & 0xFF);
	}
	uint64_t duration = bench_get_time_ns() - start;
	free(buf);

	double total_mb = ((double)iters * (double)MEM_BUF_SIZE) / (1024.0 * 1024.0);
	double seconds = bench_ns_to_s(duration);
	return (seconds > 0.0) ? (total_mb / seconds) : 0.0; /* MB/s */
}

/* 3. Memory Allocation Churn */
static double bench_alloc_churn(int iters) {
	void *ptrs[512];
	memset(ptrs, 0, sizeof(ptrs));
	uint32_t rng = 12345;

	uint64_t start = bench_get_time_ns();
	for (int i = 0; i < iters; i++) {
		int idx = (int)(lcg_rand(&rng) % 512);
		if (ptrs[idx]) {
			free(ptrs[idx]);
			ptrs[idx] = NULL;
		} else {
			size_t sz = 64 + (size_t)(lcg_rand(&rng) % 2048);
			ptrs[idx] = malloc(sz);
			if (ptrs[idx]) {
				*(volatile uint8_t *)ptrs[idx] = 1;
			}
		}
	}
	for (int i = 0; i < 512; i++) {
		if (ptrs[i]) free(ptrs[i]);
	}
	uint64_t duration = bench_get_time_ns() - start;
	double seconds = bench_ns_to_s(duration);
	return (seconds > 0.0) ? ((double)iters / seconds) : 0.0; /* ops/s */
}

/* 4. Pointer Chasing Random Access Latency */
static double bench_pointer_chase_latency(void) {
	size_t count = LATENCY_BUF_SIZE / sizeof(uint32_t);
	uint32_t *indices = (uint32_t *)malloc(LATENCY_BUF_SIZE);
	if (!indices) return 0.0;

	/* Setup simple pseudo-random permutation ring */
	for (size_t i = 0; i < count; i++) {
		indices[i] = (uint32_t)((i * 10007 + 13) % count);
	}

	uint32_t pos = 0;
	uint64_t start = bench_get_time_ns();
	for (int i = 0; i < LATENCY_ITERS; i++) {
		pos = indices[pos];
	}
	uint64_t duration = bench_get_time_ns() - start;
	volatile uint32_t sink = pos;
	(void)sink;
	free(indices);

	return (double)duration / (double)LATENCY_ITERS; /* Nanoseconds per access */
}

int run_bench_mem(bench_result_t *results, int max_results, int quick_mode) {
	if (max_results < 4) return 0;
	int idx = 0;

	int iters = quick_mode ? MEM_ITERS_QUICK : MEM_ITERS_DEFAULT;
	int churn_iters = quick_mode ? CHURN_ITERS_QUICK : CHURN_ITERS_DEFAULT;

	/* 1. memcpy Bandwidth */
	double memcpy_mb = bench_tinymem_memcpy(iters);
	snprintf(results[idx].name, sizeof(results[idx].name), "mem.bandwidth_memcpy");
	results[idx].category = BENCH_CAT_MEM;
	results[idx].raw_value = memcpy_mb;
	snprintf(results[idx].unit, sizeof(results[idx].unit), "MB/s");
	results[idx].baseline_value = 1450.0; /* 1.45 GB/s RK3566 DDR baseline */
	results[idx].lower_is_better = 0;
	results[idx].skipped = 0;
	results[idx].normalized_score = (memcpy_mb / results[idx].baseline_value) * 1000.0;
	idx++;

	/* 2. memset Bandwidth */
	double memset_mb = bench_tinymem_memset(iters);
	snprintf(results[idx].name, sizeof(results[idx].name), "mem.bandwidth_memset");
	results[idx].category = BENCH_CAT_MEM;
	results[idx].raw_value = memset_mb;
	snprintf(results[idx].unit, sizeof(results[idx].unit), "MB/s");
	results[idx].baseline_value = 3000.0; /* 3.0 GB/s RK3566 baseline */
	results[idx].lower_is_better = 0;
	results[idx].skipped = 0;
	results[idx].normalized_score = (memset_mb / results[idx].baseline_value) * 1000.0;
	idx++;

	/* 3. Allocator Churn */
	double churn_ops = bench_alloc_churn(churn_iters);
	snprintf(results[idx].name, sizeof(results[idx].name), "mem.alloc_churn");
	results[idx].category = BENCH_CAT_MEM;
	results[idx].raw_value = churn_ops;
	snprintf(results[idx].unit, sizeof(results[idx].unit), "ops/s");
	results[idx].baseline_value = 1000000.0; /* 1M ops/s baseline */
	results[idx].lower_is_better = 0;
	results[idx].skipped = 0;
	results[idx].normalized_score = (churn_ops / results[idx].baseline_value) * 1000.0;
	idx++;

	/* 4. Random Access Latency */
	double latency_ns = bench_pointer_chase_latency();
	snprintf(results[idx].name, sizeof(results[idx].name), "mem.random_access_latency");
	results[idx].category = BENCH_CAT_MEM;
	results[idx].raw_value = latency_ns;
	snprintf(results[idx].unit, sizeof(results[idx].unit), "ns");
	results[idx].baseline_value = 85.0; /* 85 ns DDR random latency */
	results[idx].lower_is_better = 1;
	results[idx].skipped = 0;
	results[idx].normalized_score = (results[idx].baseline_value / latency_ns) * 1000.0;
	idx++;

	return idx;
}
