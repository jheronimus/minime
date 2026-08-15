#include "bench.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void print_usage(const char *prog) {
	printf("Minime Performance Benchmark Tool v%s\n\n", BENCH_VERSION);
	printf("Usage: %s [options]\n\n", prog);
	printf("Options:\n");
	printf("  --all                 Run complete benchmark suite (default)\n");
	printf("  --category <cat>      Run specific category: emu, mem, ui, sys\n");
	printf("  --quick               Run fast smoke test with reduced iterations\n");
	printf("  --json                Output machine-readable JSON to stdout\n");
	printf("  --markdown            Output Markdown table to stdout\n");
	printf("  --save <file.json>    Save run metrics to JSON file\n");
	printf("  --compare <base.json> Compare current run against saved baseline JSON\n");
	printf("  --help, -h            Show this help message\n\n");
}

int main(int argc, char **argv) {
	int run_all = 1;
	int run_emu = 0;
	int run_mem = 0;
	int run_ui  = 0;
	int run_sys = 0;
	int quick_mode = 0;
	int output_json = 0;
	int output_markdown = 0;
	const char *save_path = NULL;
	const char *compare_path = NULL;

	for (int i = 1; i < argc; i++) {
		if (strcmp(argv[i], "--all") == 0) {
			run_all = 1;
		} else if (strcmp(argv[i], "--quick") == 0) {
			quick_mode = 1;
		} else if (strcmp(argv[i], "--json") == 0) {
			output_json = 1;
		} else if (strcmp(argv[i], "--markdown") == 0) {
			output_markdown = 1;
		} else if (strcmp(argv[i], "--category") == 0 && i + 1 < argc) {
			run_all = 0;
			i++;
			if (strcmp(argv[i], "emu") == 0) run_emu = 1;
			else if (strcmp(argv[i], "mem") == 0) run_mem = 1;
			else if (strcmp(argv[i], "ui") == 0)  run_ui = 1;
			else if (strcmp(argv[i], "sys") == 0) run_sys = 1;
			else {
				fprintf(stderr, "Unknown category '%s'. Valid: emu, mem, ui, sys\n", argv[i]);
				return 1;
			}
		} else if (strcmp(argv[i], "--save") == 0 && i + 1 < argc) {
			save_path = argv[++i];
		} else if (strcmp(argv[i], "--compare") == 0 && i + 1 < argc) {
			compare_path = argv[++i];
		} else if (strcmp(argv[i], "--help") == 0 || strcmp(argv[i], "-h") == 0) {
			print_usage(argv[0]);
			return 0;
		} else {
			fprintf(stderr, "Unknown option '%s'\n", argv[i]);
			print_usage(argv[0]);
			return 1;
		}
	}

	if (run_all) {
		run_emu = 1;
		run_mem = 1;
		run_ui  = 1;
		run_sys = 1;
	}

	bench_result_t results[MAX_BENCH_RESULTS];
	int count = 0;

	if (!output_json && !output_markdown) {
		printf("Running Minime performance benchmark suite (quick=%d)...\n", quick_mode);
	}

	if (run_mem) {
		if (!output_json && !output_markdown) printf("  [1/4] Running memory & allocator benchmarks...\n");
		count += run_bench_mem(&results[count], MAX_BENCH_RESULTS - count, quick_mode);
	}
	if (run_sys) {
		if (!output_json && !output_markdown) printf("  [2/4] Running system compute and I/O benchmarks...\n");
		count += run_bench_sys(&results[count], MAX_BENCH_RESULTS - count, quick_mode);
	}
	if (run_emu) {
		if (!output_json && !output_markdown) printf("  [3/4] Running emulator core benchmarks...\n");
		count += run_bench_emu(&results[count], MAX_BENCH_RESULTS - count, quick_mode);
	}
	if (run_ui) {
		if (!output_json && !output_markdown) printf("  [4/4] Running launcher UI benchmarks...\n");
		count += run_bench_ui(&results[count], MAX_BENCH_RESULTS - count, quick_mode);
	}

	double index_score = bench_compute_minime_index(results, count);

	if (save_path) {
		if (bench_save_json(save_path, results, count, index_score) == 0) {
			if (!output_json) printf("Results saved to %s\n", save_path);
		} else {
			fprintf(stderr, "Failed to save results to %s\n", save_path);
		}
	}

	if (compare_path) {
		bench_compare_json(compare_path, results, count, index_score);
	} else if (output_json) {
		/* Dump to stdout */
		bench_save_json("/dev/stdout", results, count, index_score);
	} else if (output_markdown) {
		bench_print_markdown(results, count, index_score);
	} else {
		bench_print_table(results, count, index_score);
	}

	return 0;
}
