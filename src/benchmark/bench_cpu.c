#include "bench.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include <unistd.h>

#define CPU_ITERS_DEFAULT 50000000
#define CPU_ITERS_QUICK   10000000
#define NUM_THREADS       4

/* Deterministic integer ALU & hashing compression simulation */
static uint32_t cpu_worker_loop(int iters, uint32_t seed) {
	uint32_t a = seed;
	uint32_t b = seed ^ 0x55555555;
	uint32_t c = seed ^ 0xAAAAAAAA;
	uint32_t d = seed ^ 0x33333333;

	for (int i = 0; i < iters; i++) {
		a = (a + b) ^ (c >> 3);
		b = (b << 5) ^ (d + i);
		c = (c + 0x9e3779b9) ^ (a << 7);
		d = (d ^ (b >> 11)) + (c ^ 0x12345678);

		/* Fast bit-tree context model simulation */
		uint32_t idx = (a ^ b) & 0xFF;
		a += (idx * 0x01000193);
	}
	return a ^ b ^ c ^ d;
}

/* 1. Single-threaded Benchmark */
static double bench_cpu_single(int iters) {
	uint64_t start = bench_get_time_ns();
	volatile uint32_t res = cpu_worker_loop(iters, 0x12345678);
	(void)res;
	uint64_t duration = bench_get_time_ns() - start;

	double seconds = bench_ns_to_s(duration);
	return (seconds > 0.0) ? (((double)iters / 1000000.0) / seconds) : 0.0; /* MIPS (Mops/s) */
}

/* 2. Multi-threaded Benchmark */
typedef struct {
	int iters;
	uint32_t seed;
	uint32_t result;
} cpu_thread_arg_t;

static void *cpu_thread_fn(void *arg) {
	cpu_thread_arg_t *t = (cpu_thread_arg_t *)arg;
	t->result = cpu_worker_loop(t->iters, t->seed);
	return NULL;
}

static double bench_cpu_multi(int iters, int num_threads) {
	pthread_t threads[NUM_THREADS];
	cpu_thread_arg_t args[NUM_THREADS];

	if (num_threads > NUM_THREADS) num_threads = NUM_THREADS;

	uint64_t start = bench_get_time_ns();
	for (int i = 0; i < num_threads; i++) {
		args[i].iters = iters;
		args[i].seed = 0x12345678 + i * 0x1000;
		pthread_create(&threads[i], NULL, cpu_thread_fn, &args[i]);
	}
	for (int i = 0; i < num_threads; i++) {
		pthread_join(threads[i], NULL);
	}
	uint64_t duration = bench_get_time_ns() - start;

	double total_ops = (double)iters * (double)num_threads;
	double seconds = bench_ns_to_s(duration);
	return (seconds > 0.0) ? ((total_ops / 1000000.0) / seconds) : 0.0; /* Total MIPS */
}

int run_bench_cpu(bench_result_t *results, int max_results, int quick_mode) {
	if (max_results < 2) return 0;
	int idx = 0;
	int iters = quick_mode ? CPU_ITERS_QUICK : CPU_ITERS_DEFAULT;

	/* 1. Single Thread */
	double mips_1t = bench_cpu_single(iters);
	snprintf(results[idx].name, sizeof(results[idx].name), "cpu.single_thread");
	results[idx].category = BENCH_CAT_CPU;
	results[idx].raw_value = mips_1t;
	snprintf(results[idx].unit, sizeof(results[idx].unit), "MIPS");
	results[idx].baseline_value = 85.0; /* 85 MIPS RK3566 1.8GHz baseline */
	results[idx].lower_is_better = 0;
	results[idx].skipped = 0;
	results[idx].normalized_score = (mips_1t / results[idx].baseline_value) * 1000.0;
	idx++;

	/* 2. Multi Thread (4 Cores) */
	long nprocs = sysconf(_SC_NPROCESSORS_ONLN);
	if (nprocs < 1) nprocs = 4;
	if (nprocs > NUM_THREADS) nprocs = NUM_THREADS;

	double mips_mt = bench_cpu_multi(iters, (int)nprocs);
	snprintf(results[idx].name, sizeof(results[idx].name), "cpu.multi_thread_4t");
	results[idx].category = BENCH_CAT_CPU;
	results[idx].raw_value = mips_mt;
	snprintf(results[idx].unit, sizeof(results[idx].unit), "MIPS");
	results[idx].baseline_value = 330.0; /* 330 MIPS 4-core RK3566 baseline */
	results[idx].lower_is_better = 0;
	results[idx].skipped = 0;
	results[idx].normalized_score = (mips_mt / results[idx].baseline_value) * 1000.0;
	idx++;

	return idx;
}
