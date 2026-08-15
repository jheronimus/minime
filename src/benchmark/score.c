#include "bench.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

const char *bench_category_name(bench_category_t cat) {
	switch (cat) {
	case BENCH_CAT_CPU:     return "CPU (Compute)";
	case BENCH_CAT_MEM:     return "Memory (Bandwidth/Alloc)";
	case BENCH_CAT_GPU:     return "GPU (DRM/GLES/Vulkan)";
	case BENCH_CAT_STORAGE: return "Storage (I/O)";
	case BENCH_CAT_NET:     return "Network (Transfer)";
	default:                return "UNKNOWN";
	}
}

static const char *bench_category_tag(bench_category_t cat) {
	switch (cat) {
	case BENCH_CAT_CPU:     return "CPU";
	case BENCH_CAT_MEM:     return "MEM";
	case BENCH_CAT_GPU:     return "GPU";
	case BENCH_CAT_STORAGE: return "STR";
	case BENCH_CAT_NET:     return "NET";
	default:                return "UNK";
	}
}

/* Category score = geometric mean of non-skipped tests in category */
double bench_compute_category_score(const bench_result_t *results, int count, bench_category_t cat) {
	double log_sum = 0.0;
	int active = 0;

	for (int i = 0; i < count; i++) {
		if (results[i].category == cat && !results[i].skipped && results[i].normalized_score > 0.0) {
			log_sum += log(results[i].normalized_score);
			active++;
		}
	}
	if (active == 0) return 0.0;
	return exp(log_sum / (double)active);
}

/* Overall composite index = weighted geometric mean of category scores */
double bench_compute_overall_index(const bench_result_t *results, int count) {
	double weights[BENCH_CAT_COUNT] = {
		WEIGHT_CPU, WEIGHT_MEM, WEIGHT_GPU, WEIGHT_STORAGE, WEIGHT_NET
	};
	double cat_scores[BENCH_CAT_COUNT];
	double log_sum = 0.0;
	double total_weight = 0.0;

	for (int c = 0; c < BENCH_CAT_COUNT; c++) {
		cat_scores[c] = bench_compute_category_score(results, count, (bench_category_t)c);
		if (cat_scores[c] > 0.0) {
			log_sum += weights[c] * log(cat_scores[c]);
			total_weight += weights[c];
		}
	}

	if (total_weight <= 0.0) return 0.0;
	return exp(log_sum / total_weight);
}

static void format_metric(char *buf, size_t sz, double val, const char *unit) {
	if (strcmp(unit, "ops/s") == 0) {
		if (val >= 1000000.0) {
			snprintf(buf, sz, "%.2f Mops/s", val / 1000000.0);
			return;
		} else if (val >= 1000.0) {
			snprintf(buf, sz, "%.1f kops/s", val / 1000.0);
			return;
		}
	} else if (strcmp(unit, "IOPS") == 0) {
		if (val >= 1000.0) {
			snprintf(buf, sz, "%.1f kIOPS", val / 1000.0);
			return;
		}
	}
	if (val >= 1000.0) {
		snprintf(buf, sz, "%.1f %s", val, unit);
	} else {
		snprintf(buf, sz, "%.2f %s", val, unit);
	}
}

void bench_print_table(const bench_result_t *results, int count, double index_score) {
	printf("\n");
	printf("================================================================================\n");
	printf("                   MINIME PERFORMANCE BENCHMARK REPORT                         \n");
	printf("================================================================================\n");
	printf("%-26s | %15s | %14s | %9s | %s\n", "Benchmark Test", "Raw Result", "Baseline", "Score", "Cat");
	printf("---------------------------+-----------------+----------------+-----------+-----\n");

	for (int i = 0; i < count; i++) {
		if (results[i].skipped) {
			printf("%-26s | %15s | %14s | %9s | %-3s\n",
				results[i].name, "SKIPPED", "N/A", "N/A", bench_category_tag(results[i].category));
		} else {
			char raw_str[32], base_str[32];
			format_metric(raw_str, sizeof(raw_str), results[i].raw_value, results[i].unit);
			format_metric(base_str, sizeof(base_str), results[i].baseline_value, results[i].unit);

			printf("%-26s | %15s | %14s | %9.1f | %-3s\n",
				results[i].name, raw_str, base_str, results[i].normalized_score, bench_category_tag(results[i].category));
		}
	}

	printf("================================================================================\n");
	printf("CATEGORY SCORES:\n");
	for (int c = 0; c < BENCH_CAT_COUNT; c++) {
		double s = bench_compute_category_score(results, count, (bench_category_t)c);
		printf("  • %-26s : %7.1f pts\n", bench_category_name((bench_category_t)c), s);
	}
	printf("--------------------------------------------------------------------------------\n");
	printf("  ★ MINIME OVERALL INDEX     : %7.1f pts (Higher is better, Baseline = 1000.0)\n", index_score);
	printf("================================================================================\n\n");
}

void bench_print_markdown(const bench_result_t *results, int count, double index_score) {
	printf("\n## Minime Performance Benchmark Results\n\n");
	printf("| Benchmark Test | Raw Result | Baseline | Score | Category |\n");
	printf("| :--- | :---: | :---: | :---: | :---: |\n");

	for (int i = 0; i < count; i++) {
		if (results[i].skipped) {
			printf("| `%s` | *SKIPPED* | *N/A* | *N/A* | `%s` |\n",
				results[i].name, bench_category_tag(results[i].category));
		} else {
			printf("| `%s` | %.2f %s | %.2f %s | **%.1f** | `%s` |\n",
				results[i].name, results[i].raw_value, results[i].unit,
				results[i].baseline_value, results[i].unit,
				results[i].normalized_score, bench_category_tag(results[i].category));
		}
	}

	printf("\n### Category Scores\n\n");
	for (int c = 0; c < BENCH_CAT_COUNT; c++) {
		double s = bench_compute_category_score(results, count, (bench_category_t)c);
		printf("- **%s**: `%.1f pts`\n", bench_category_name((bench_category_t)c), s);
	}
	printf("\n**Overall Minime Index: `%.1f pts`** (Baseline = 1000.0)\n\n", index_score);
}

int bench_save_json(const char *path, const bench_result_t *results, int count, double index_score) {
	FILE *fp = fopen(path, "w");
	if (!fp) return -1;

	fprintf(fp, "{\n");
	fprintf(fp, "  \"version\": \"%s\",\n", BENCH_VERSION);
	fprintf(fp, "  \"index_score\": %.2f,\n", index_score);
	fprintf(fp, "  \"categories\": {\n");
	for (int c = 0; c < BENCH_CAT_COUNT; c++) {
		double s = bench_compute_category_score(results, count, (bench_category_t)c);
		fprintf(fp, "    \"%s\": %.2f%s\n",
			bench_category_tag((bench_category_t)c), s, (c == BENCH_CAT_COUNT - 1) ? "" : ",");
	}
	fprintf(fp, "  },\n");
	fprintf(fp, "  \"tests\": [\n");
	for (int i = 0; i < count; i++) {
		fprintf(fp, "    {\n");
		fprintf(fp, "      \"name\": \"%s\",\n", results[i].name);
		fprintf(fp, "      \"category\": \"%s\",\n", bench_category_tag(results[i].category));
		fprintf(fp, "      \"raw_value\": %.2f,\n", results[i].raw_value);
		fprintf(fp, "      \"unit\": \"%s\",\n", results[i].unit);
		fprintf(fp, "      \"baseline\": %.2f,\n", results[i].baseline_value);
		fprintf(fp, "      \"score\": %.2f,\n", results[i].normalized_score);
		fprintf(fp, "      \"skipped\": %d\n", results[i].skipped);
		fprintf(fp, "    }%s\n", (i == count - 1) ? "" : ",");
	}
	fprintf(fp, "  ]\n");
	fprintf(fp, "}\n");

	fclose(fp);
	return 0;
}

int bench_compare_json(const char *path, const bench_result_t *results, int count, double index_score) {
	(void)results;
	(void)count;
	FILE *fp = fopen(path, "r");
	if (!fp) {
		fprintf(stderr, "Error: cannot open baseline JSON file '%s'\n", path);
		return -1;
	}

	char line[256];
	double baseline_index = 0.0;
	while (fgets(line, sizeof(line), fp)) {
		if (strstr(line, "\"index_score\":")) {
			char *colon = strchr(line, ':');
			if (colon) {
				baseline_index = atof(colon + 1);
				break;
			}
		}
	}
	fclose(fp);

	if (baseline_index <= 0.0) {
		fprintf(stderr, "Error: failed to parse valid index_score from '%s'\n", path);
		return -1;
	}

	double delta_pct = ((index_score - baseline_index) / baseline_index) * 100.0;

	printf("\n");
	printf("================================================================================\n");
	printf("                    BENCHMARK A/B COMPARISON REPORT                             \n");
	printf("================================================================================\n");
	printf("Baseline File: %s\n", path);
	printf("Baseline Index: %7.1f pts\n", baseline_index);
	printf("Current  Index: %7.1f pts\n", index_score);
	printf("Overall Delta : %+6.2f%% (%s)\n", delta_pct, (delta_pct >= 0.0) ? "SPEEDUP" : "REGRESSION");
	printf("================================================================================\n\n");

	return 0;
}
