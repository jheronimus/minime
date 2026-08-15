#include "bench.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void print_usage(const char *prog) {
	printf("Minime Comprehensive Hardware Benchmark Suite v%s\n\n", BENCH_VERSION);
	printf("Usage: %s [options]\n\n", prog);
	printf("Options:\n");
	printf("  --all                 Run all benchmark categories (default)\n");
	printf("  --category <cat>      Run specific category: cpu, mem, gpu, storage, net\n");
	printf("  --quick               Run fast iteration with fewer loops\n");
	printf("  --json                Output results in JSON format\n");
	printf("  --markdown            Output results as a Markdown table\n");
	printf("  --save <file.json>    Save results to JSON file\n");
	printf("  --compare <base.json> Compare current run against baseline JSON\n");
	printf("  --help, -h            Show this help text\n");
}

int main(int argc, char **argv) {
	int run_all = 1;
	int run_cpu = 0, run_mem = 0, run_gpu = 0, run_storage = 0, run_net = 0;
	int quick_mode = 0;
	int json_out = 0;
	int md_out = 0;
	const char *save_path = NULL;
	const char *compare_path = NULL;

	for (int i = 1; i < argc; i++) {
		if (strcmp(argv[i], "--all") == 0) {
			run_all = 1;
		} else if (strcmp(argv[i], "--quick") == 0) {
			quick_mode = 1;
		} else if (strcmp(argv[i], "--json") == 0) {
			json_out = 1;
		} else if (strcmp(argv[i], "--markdown") == 0) {
			md_out = 1;
		} else if (strcmp(argv[i], "--save") == 0 && i + 1 < argc) {
			save_path = argv[++i];
		} else if (strcmp(argv[i], "--compare") == 0 && i + 1 < argc) {
			compare_path = argv[++i];
		} else if (strcmp(argv[i], "--category") == 0 && i + 1 < argc) {
			run_all = 0;
			i++;
			if (strcmp(argv[i], "cpu") == 0) run_cpu = 1;
			else if (strcmp(argv[i], "mem") == 0) run_mem = 1;
			else if (strcmp(argv[i], "gpu") == 0) run_gpu = 1;
			else if (strcmp(argv[i], "storage") == 0) run_storage = 1;
			else if (strcmp(argv[i], "net") == 0) run_net = 1;
			else {
				fprintf(stderr, "Unknown category '%s'. Available: cpu, mem, gpu, storage, net\n", argv[i]);
				return 1;
			}
		} else if (strcmp(argv[i], "--help") == 0 || strcmp(argv[i], "-h") == 0) {
			print_usage(argv[0]);
			return 0;
		} else {
			fprintf(stderr, "Unknown option '%s'. Use --help for usage.\n", argv[i]);
			return 1;
		}
	}

	if (run_all) {
		run_cpu = run_mem = run_gpu = run_storage = run_net = 1;
	}

	bench_result_t results[MAX_BENCH_RESULTS];
	int total_results = 0;

	if (!json_out && !md_out) {
		printf("Running Minime hardware benchmark suite (quick=%d)...\n", quick_mode);
	}

	if (run_cpu) {
		if (!json_out && !md_out) printf("  [1/5] Running CPU (single & multi-thread) benchmarks...\n");
		total_results += run_bench_cpu(&results[total_results], MAX_BENCH_RESULTS - total_results, quick_mode);
	}
	if (run_mem) {
		if (!json_out && !md_out) printf("  [2/5] Running Memory (bandwidth & latency) benchmarks...\n");
		total_results += run_bench_mem(&results[total_results], MAX_BENCH_RESULTS - total_results, quick_mode);
	}
	if (run_gpu) {
		if (!json_out && !md_out) printf("  [3/5] Running GPU (DRM, GLES, Vulkan) benchmarks...\n");
		total_results += run_bench_gpu(&results[total_results], MAX_BENCH_RESULTS - total_results, quick_mode);
	}
	if (run_storage) {
		if (!json_out && !md_out) printf("  [4/5] Running Storage (sequential & random I/O) benchmarks...\n");
		total_results += run_bench_storage(&results[total_results], MAX_BENCH_RESULTS - total_results, quick_mode);
	}
	if (run_net) {
		if (!json_out && !md_out) printf("  [5/5] Running Network (socket transfer) benchmarks...\n");
		total_results += run_bench_net(&results[total_results], MAX_BENCH_RESULTS - total_results, quick_mode);
	}

	double overall_index = bench_compute_overall_index(results, total_results);

	if (save_path) {
		if (bench_save_json(save_path, results, total_results, overall_index) == 0) {
			if (!json_out && !md_out) printf("Results saved to %s\n", save_path);
		} else {
			fprintf(stderr, "Failed to save results to %s\n", save_path);
		}
	}

	if (compare_path) {
		bench_compare_json(compare_path, results, total_results, overall_index);
	}

	if (json_out) {
		bench_save_json("/dev/stdout", results, total_results, overall_index);
	} else if (md_out) {
		bench_print_markdown(results, total_results, overall_index);
	} else {
		bench_print_table(results, total_results, overall_index);
	}

	return 0;
}
