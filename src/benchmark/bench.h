#ifndef BENCH_H
#define BENCH_H

#include <stddef.h>
#include <stdint.h>
#include <time.h>

#define BENCH_VERSION "1.0.0"

typedef enum {
	BENCH_CAT_EMU = 0,
	BENCH_CAT_MEM = 1,
	BENCH_CAT_UI = 2,
	BENCH_CAT_SYS = 3,
	BENCH_CAT_COUNT = 4
} bench_category_t;

typedef struct {
	char name[64];
	bench_category_t category;
	double raw_value;
	char unit[16];
	double baseline_value;
	double normalized_score;
	int lower_is_better;
} bench_result_t;

#define MAX_BENCH_RESULTS 64

/* Category weights summing to 1.0 */
#define WEIGHT_EMU 0.40
#define WEIGHT_MEM 0.25
#define WEIGHT_UI  0.20
#define WEIGHT_SYS 0.15

/* High resolution timer helper (monotonic nanoseconds) */
static inline uint64_t bench_get_time_ns(void) {
	struct timespec ts;
	clock_gettime(CLOCK_MONOTONIC, &ts);
	return (uint64_t)ts.tv_sec * 1000000000ULL + (uint64_t)ts.tv_nsec;
}

static inline double bench_ns_to_ms(uint64_t ns) {
	return (double)ns / 1000000.0;
}

static inline double bench_ns_to_s(uint64_t ns) {
	return (double)ns / 1000000000.0;
}

/* Category runner prototypes */
int run_bench_mem(bench_result_t *results, int max_results, int quick_mode);
int run_bench_sys(bench_result_t *results, int max_results, int quick_mode);
int run_bench_emu(bench_result_t *results, int max_results, int quick_mode);
int run_bench_ui(bench_result_t *results, int max_results, int quick_mode);

/* Scoring and reporting */
const char *bench_category_name(bench_category_t cat);
double bench_compute_category_score(const bench_result_t *results, int count, bench_category_t cat);
double bench_compute_minime_index(const bench_result_t *results, int count);

void bench_print_table(const bench_result_t *results, int count, double index_score);
void bench_print_markdown(const bench_result_t *results, int count, double index_score);
int bench_save_json(const char *path, const bench_result_t *results, int count, double index_score);
int bench_compare_json(const char *path, const bench_result_t *results, int count, double index_score);

#endif /* BENCH_H */
