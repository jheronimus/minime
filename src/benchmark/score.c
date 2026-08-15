#include "bench.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

const char *bench_category_name(bench_category_t cat) {
	switch (cat) {
	case BENCH_CAT_EMU: return "Emulation";
	case BENCH_CAT_MEM: return "Memory & Allocator";
	case BENCH_CAT_UI:  return "Launcher UI";
	case BENCH_CAT_SYS: return "System & I/O";
	default:            return "Unknown";
	}
}

double bench_compute_category_score(const bench_result_t *results, int count, bench_category_t cat) {
	double sum_log = 0.0;
	int cat_count = 0;

	for (int i = 0; i < count; i++) {
		if (results[i].category == cat && results[i].normalized_score > 0.0) {
			sum_log += log(results[i].normalized_score);
			cat_count++;
		}
	}
	if (cat_count == 0) return 1000.0;
	return exp(sum_log / (double)cat_count);
}

double bench_compute_minime_index(const bench_result_t *results, int count) {
	double score_emu = bench_compute_category_score(results, count, BENCH_CAT_EMU);
	double score_mem = bench_compute_category_score(results, count, BENCH_CAT_MEM);
	double score_ui  = bench_compute_category_score(results, count, BENCH_CAT_UI);
	double score_sys = bench_compute_category_score(results, count, BENCH_CAT_SYS);

	double weighted_log =
		(WEIGHT_EMU * log(score_emu)) +
		(WEIGHT_MEM * log(score_mem)) +
		(WEIGHT_UI  * log(score_ui)) +
		(WEIGHT_SYS * log(score_sys));

	return exp(weighted_log);
}

void bench_print_table(const bench_result_t *results, int count, double index_score) {
	printf("\n================================================================================\n");
	printf("                   MINIME PERFORMANCE BENCHMARK REPORT                         \n");
	printf("================================================================================\n");
	printf("%-26s | %10s | %10s | %10s | %8s\n", "Benchmark Test", "Raw Result", "Baseline", "Score", "Category");
	printf("---------------------------+------------+------------+------------+---------\n");

	for (int i = 0; i < count; i++) {
		char raw_buf[32];
		char base_buf[32];
		snprintf(raw_buf, sizeof(raw_buf), "%.2f %s", results[i].raw_value, results[i].unit);
		snprintf(base_buf, sizeof(base_buf), "%.2f %s", results[i].baseline_value, results[i].unit);

		const char *cat_short = "SYS";
		if (results[i].category == BENCH_CAT_EMU) cat_short = "EMU";
		else if (results[i].category == BENCH_CAT_MEM) cat_short = "MEM";
		else if (results[i].category == BENCH_CAT_UI)  cat_short = "UI";

		printf("%-26s | %10s | %10s | %10.1f | %8s\n",
		       results[i].name, raw_buf, base_buf, results[i].normalized_score, cat_short);
	}

	printf("================================================================================\n");
	printf("CATEGORY SCORES:\n");
	for (int c = 0; c < BENCH_CAT_COUNT; c++) {
		double cat_score = bench_compute_category_score(results, count, (bench_category_t)c);
		printf("  • %-22s: %7.1f pts\n", bench_category_name((bench_category_t)c), cat_score);
	}
	printf("--------------------------------------------------------------------------------\n");
	printf("  ★ MINIME OVERALL INDEX: %7.1f pts (Higher is better, Baseline = 1000.0)\n", index_score);
	printf("================================================================================\n\n");
}

void bench_print_markdown(const bench_result_t *results, int count, double index_score) {
	printf("\n### Minime Performance Benchmark Results\n\n");
	printf("| Benchmark Test | Raw Result | Baseline | Score (pts) | Category |\n");
	printf("| :--- | :---: | :---: | :---: | :---: |\n");

	for (int i = 0; i < count; i++) {
		printf("| `%s` | %.2f %s | %.2f %s | %.1f | %s |\n",
		       results[i].name,
		       results[i].raw_value, results[i].unit,
		       results[i].baseline_value, results[i].unit,
		       results[i].normalized_score,
		       bench_category_name(results[i].category));
	}

	printf("\n**Category Breakdown:**\n");
	for (int c = 0; c < BENCH_CAT_COUNT; c++) {
		double cat_score = bench_compute_category_score(results, count, (bench_category_t)c);
		printf("- **%s**: %.1f pts\n", bench_category_name((bench_category_t)c), cat_score);
	}
	printf("\n**Overall Minime Index**: **`%.1f`** pts (Baseline = 1000.0)\n\n", index_score);
}

int bench_save_json(const char *path, const bench_result_t *results, int count, double index_score) {
	FILE *f = fopen(path, "w");
	if (!f) return -1;

	fprintf(f, "{\n");
	fprintf(f, "  \"version\": \"%s\",\n", BENCH_VERSION);
	fprintf(f, "  \"minime_index\": %.2f,\n", index_score);
	fprintf(f, "  \"categories\": {\n");
	for (int c = 0; c < BENCH_CAT_COUNT; c++) {
		double cat_score = bench_compute_category_score(results, count, (bench_category_t)c);
		fprintf(f, "    \"%s\": %.2f%s\n",
		        bench_category_name((bench_category_t)c),
		        cat_score,
		        (c < BENCH_CAT_COUNT - 1) ? "," : "");
	}
	fprintf(f, "  },\n");
	fprintf(f, "  \"results\": [\n");
	for (int i = 0; i < count; i++) {
		fprintf(f, "    {\n");
		fprintf(f, "      \"name\": \"%s\",\n", results[i].name);
		fprintf(f, "      \"category\": \"%s\",\n", bench_category_name(results[i].category));
		fprintf(f, "      \"raw_value\": %.4f,\n", results[i].raw_value);
		fprintf(f, "      \"unit\": \"%s\",\n", results[i].unit);
		fprintf(f, "      \"baseline\": %.4f,\n", results[i].baseline_value);
		fprintf(f, "      \"score\": %.2f\n", results[i].normalized_score);
		fprintf(f, "    }%s\n", (i < count - 1) ? "," : "");
	}
	fprintf(f, "  ]\n");
	fprintf(f, "}\n");
	fclose(f);
	return 0;
}

int bench_compare_json(const char *path, const bench_result_t *results, int count, double index_score) {
	FILE *f = fopen(path, "r");
	if (!f) {
		fprintf(stderr, "Error: cannot open baseline file %s\n", path);
		return -1;
	}

	char line[256];
	double base_index = 1000.0;

	/* Simple line-based JSON scanner */
	while (fgets(line, sizeof(line), f)) {
		if (strstr(line, "\"minime_index\":")) {
			sscanf(line, " \"minime_index\": %lf,", &base_index);
			break;
		}
	}
	fclose(f);

	double index_delta = ((index_score - base_index) / base_index) * 100.0;

	printf("\n================================================================================\n");
	printf("                    BENCHMARK A/B COMPARISON REPORT                             \n");
	printf("================================================================================\n");
	printf("Baseline File: %s\n", path);
	printf("Baseline Index: %7.1f pts\n", base_index);
	printf("Current  Index: %7.1f pts\n", index_score);
	printf("Overall Delta : %+6.2f%% (%s)\n",
	       index_delta, (index_delta >= 0.0) ? "SPEEDUP" : "REGRESSION");
	printf("================================================================================\n\n");

	bench_print_table(results, count, index_score);
	return 0;
}
