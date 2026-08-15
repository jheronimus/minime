#include "bench.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include <unistd.h>

#define CHURN_ITERS_DEFAULT 500000
#define CHURN_ITERS_QUICK   100000
#define MT_THREADS          4
#define MT_ITERS_DEFAULT    200000
#define MT_ITERS_QUICK      50000
#define QUEUE_SIZE          1024

/* Simple LCG pseudo-random for deterministic allocations */
static inline uint32_t lcg_rand(uint32_t *state) {
	*state = *state * 1664525 + 1013904223;
	return *state;
}

/* 1. Single-threaded Small Allocation Churn */
static double bench_small_churn(int iters) {
	void *ptrs[1024];
	memset(ptrs, 0, sizeof(ptrs));
	uint32_t rng = 12345;

	uint64_t start = bench_get_time_ns();
	for (int i = 0; i < iters; i++) {
		int idx = (int)(lcg_rand(&rng) % 1024);
		if (ptrs[idx]) {
			free(ptrs[idx]);
			ptrs[idx] = NULL;
		} else {
			size_t sz = 64 + (size_t)(lcg_rand(&rng) % 3968); /* 64B to 4032B */
			ptrs[idx] = malloc(sz);
			if (ptrs[idx]) {
				/* Touch memory to prevent dead-store elimination */
				*(volatile uint8_t *)ptrs[idx] = (uint8_t)(sz & 0xFF);
			}
		}
	}
	for (int i = 0; i < 1024; i++) {
		if (ptrs[i]) {
			free(ptrs[i]);
			ptrs[i] = NULL;
		}
	}
	uint64_t duration = bench_get_time_ns() - start;
	double seconds = bench_ns_to_s(duration);
	return (double)iters / seconds; /* ops/sec */
}

/* 2. Multi-threaded Allocation Contention */
typedef struct {
	int iters;
	uint32_t seed;
} mt_worker_arg_t;

static void *mt_worker(void *arg) {
	mt_worker_arg_t *w = (mt_worker_arg_t *)arg;
	void *ptrs[512];
	memset(ptrs, 0, sizeof(ptrs));
	uint32_t rng = w->seed;

	for (int i = 0; i < w->iters; i++) {
		int idx = (int)(lcg_rand(&rng) % 512);
		if (ptrs[idx]) {
			free(ptrs[idx]);
			ptrs[idx] = NULL;
		} else {
			size_t sz = 32 + (size_t)(lcg_rand(&rng) % 2016);
			ptrs[idx] = malloc(sz);
			if (ptrs[idx]) {
				*(volatile uint8_t *)ptrs[idx] = 1;
			}
		}
	}
	for (int i = 0; i < 512; i++) {
		if (ptrs[i]) free(ptrs[i]);
	}
	return NULL;
}

static double bench_multithread(int iters) {
	pthread_t threads[MT_THREADS];
	mt_worker_arg_t args[MT_THREADS];

	uint64_t start = bench_get_time_ns();
	for (int i = 0; i < MT_THREADS; i++) {
		args[i].iters = iters;
		args[i].seed = 42 + i * 1000;
		pthread_create(&threads[i], NULL, mt_worker, &args[i]);
	}
	for (int i = 0; i < MT_THREADS; i++) {
		pthread_join(threads[i], NULL);
	}
	uint64_t duration = bench_get_time_ns() - start;
	double seconds = bench_ns_to_s(duration);
	return (double)(iters * MT_THREADS) / seconds; /* total ops/sec */
}

/* 3. Cross-thread Allocate/Free (Producer-Consumer) */
typedef struct {
	void *slots[QUEUE_SIZE];
	int head;
	int tail;
	int count;
	int done;
	pthread_mutex_t lock;
	pthread_cond_t not_empty;
	pthread_cond_t not_full;
	int total_items;
} cross_queue_t;

static void *cross_producer(void *arg) {
	cross_queue_t *q = (cross_queue_t *)arg;
	uint32_t rng = 9999;
	for (int i = 0; i < q->total_items; i++) {
		size_t sz = 64 + (size_t)(lcg_rand(&rng) % 1024);
		void *p = malloc(sz);
		if (p) *(volatile uint8_t *)p = 0xAA;

		pthread_mutex_lock(&q->lock);
		while (q->count == QUEUE_SIZE) {
			pthread_cond_wait(&q->not_full, &q->lock);
		}
		q->slots[q->head] = p;
		q->head = (q->head + 1) % QUEUE_SIZE;
		q->count++;
		pthread_cond_signal(&q->not_empty);
		pthread_mutex_unlock(&q->lock);
	}
	pthread_mutex_lock(&q->lock);
	q->done = 1;
	pthread_cond_signal(&q->not_empty);
	pthread_mutex_unlock(&q->lock);
	return NULL;
}

static void *cross_consumer(void *arg) {
	cross_queue_t *q = (cross_queue_t *)arg;
	while (1) {
		pthread_mutex_lock(&q->lock);
		while (q->count == 0 && !q->done) {
			pthread_cond_wait(&q->not_empty, &q->lock);
		}
		if (q->count == 0 && q->done) {
			pthread_mutex_unlock(&q->lock);
			break;
		}
		void *p = q->slots[q->tail];
		q->tail = (q->tail + 1) % QUEUE_SIZE;
		q->count--;
		pthread_cond_signal(&q->not_full);
		pthread_mutex_unlock(&q->lock);

		if (p) free(p);
	}
	return NULL;
}

static double bench_cross_thread(int items) {
	cross_queue_t q;
	memset(&q, 0, sizeof(q));
	q.total_items = items;
	pthread_mutex_init(&q.lock, NULL);
	pthread_cond_init(&q.not_empty, NULL);
	pthread_cond_init(&q.not_full, NULL);

	pthread_t prod, cons;
	uint64_t start = bench_get_time_ns();
	pthread_create(&prod, NULL, cross_producer, &q);
	pthread_create(&cons, NULL, cross_consumer, &q);

	pthread_join(prod, NULL);
	pthread_join(cons, NULL);

	uint64_t duration = bench_get_time_ns() - start;
	pthread_mutex_destroy(&q.lock);
	pthread_cond_destroy(&q.not_empty);
	pthread_cond_destroy(&q.not_full);

	double seconds = bench_ns_to_s(duration);
	return (double)items / seconds; /* ops/sec */
}

/* 4. Reallocation Latency */
static double bench_realloc_latency(int iters) {
	uint32_t rng = 777;
	uint64_t total_ns = 0;
	void *p = malloc(128);

	for (int i = 0; i < iters; i++) {
		size_t next_sz = 128 + (size_t)(lcg_rand(&rng) % 65536);
		uint64_t t0 = bench_get_time_ns();
		void *np = realloc(p, next_sz);
		uint64_t t1 = bench_get_time_ns();
		total_ns += (t1 - t0);
		if (np) {
			p = np;
			*(volatile uint8_t *)p = 0x55;
		}
	}
	free(p);
	return bench_ns_to_ms(total_ns) / (double)iters; /* avg ms per realloc */
}

int run_bench_mem(bench_result_t *results, int max_results, int quick_mode) {
	if (max_results < 4) return 0;
	int idx = 0;

	int churn_iters = quick_mode ? CHURN_ITERS_QUICK : CHURN_ITERS_DEFAULT;
	int mt_iters = quick_mode ? MT_ITERS_QUICK : MT_ITERS_DEFAULT;
	int cross_items = quick_mode ? 25000 : 100000;
	int realloc_iters = quick_mode ? 10000 : 50000;

	/* 1. Small Churn */
	double churn_ops = bench_small_churn(churn_iters);
	snprintf(results[idx].name, sizeof(results[idx].name), "mem.alloc_churn_single");
	results[idx].category = BENCH_CAT_MEM;
	results[idx].raw_value = churn_ops;
	snprintf(results[idx].unit, sizeof(results[idx].unit), "ops/s");
	results[idx].baseline_value = 1500000.0; /* 1.5M ops/s baseline */
	results[idx].lower_is_better = 0;
	results[idx].normalized_score = (churn_ops / results[idx].baseline_value) * 1000.0;
	idx++;

	/* 2. Multi-threaded Contention */
	double mt_ops = bench_multithread(mt_iters);
	snprintf(results[idx].name, sizeof(results[idx].name), "mem.multithread_4t");
	results[idx].category = BENCH_CAT_MEM;
	results[idx].raw_value = mt_ops;
	snprintf(results[idx].unit, sizeof(results[idx].unit), "ops/s");
	results[idx].baseline_value = 2500000.0; /* 2.5M ops/s baseline */
	results[idx].lower_is_better = 0;
	results[idx].normalized_score = (mt_ops / results[idx].baseline_value) * 1000.0;
	idx++;

	/* 3. Cross-thread Free */
	double cross_ops = bench_cross_thread(cross_items);
	snprintf(results[idx].name, sizeof(results[idx].name), "mem.cross_thread_queue");
	results[idx].category = BENCH_CAT_MEM;
	results[idx].raw_value = cross_ops;
	snprintf(results[idx].unit, sizeof(results[idx].unit), "ops/s");
	results[idx].baseline_value = 400000.0; /* 400k ops/s baseline */
	results[idx].lower_is_better = 0;
	results[idx].normalized_score = (cross_ops / results[idx].baseline_value) * 1000.0;
	idx++;

	/* 4. Reallocation Latency */
	double realloc_ms = bench_realloc_latency(realloc_iters);
	snprintf(results[idx].name, sizeof(results[idx].name), "mem.realloc_latency");
	results[idx].category = BENCH_CAT_MEM;
	results[idx].raw_value = realloc_ms * 1000.0; /* microseconds */
	snprintf(results[idx].unit, sizeof(results[idx].unit), "us");
	results[idx].baseline_value = 0.50; /* 0.50 us baseline */
	results[idx].lower_is_better = 1;
	results[idx].normalized_score = (results[idx].baseline_value / results[idx].raw_value) * 1000.0;
	idx++;

	return idx;
}
