#include "bench.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <dirent.h>
#include <sys/stat.h>

#define UI_SCAN_ITERS_DEFAULT 5000
#define UI_SCAN_ITERS_QUICK   1000

#define BLIT_ITERS_DEFAULT    2000
#define BLIT_ITERS_QUICK      500

/* 1. Launcher Directory Scanning & Metadata Parsing */
static double bench_ui_dir_scan(int iters) {
	uint64_t start = bench_get_time_ns();
	const char *scan_dirs[] = { "/roms", "/mnt/sdcard/roms", "/etc", "/usr/bin" };
	int total_entries = 0;

	for (int it = 0; it < iters; it++) {
		const char *target = scan_dirs[it % 4];
		DIR *d = opendir(target);
		if (d) {
			struct dirent *de;
			while ((de = readdir(d)) != NULL) {
				if (de->d_name[0] == '.') continue;
				total_entries += (int)strlen(de->d_name);
			}
			closedir(d);
		}
	}
	uint64_t duration = bench_get_time_ns() - start;
	volatile int sink = total_entries;
	(void)sink;

	double seconds = bench_ns_to_s(duration);
	return (seconds > 0.0) ? ((double)iters / seconds) : 0.0; /* scans/sec */
}

/* 2. UI Frame Surface Blitting & Glyphs Simulation */
static double bench_ui_blitting(int iters) {
	/* 640x480 RGB565 / ARGB8888 surface simulation */
	const int W = 640;
	const int H = 480;
	uint32_t *framebuffer = (uint32_t *)malloc(W * H * sizeof(uint32_t));
	uint32_t *tile = (uint32_t *)malloc(64 * 64 * sizeof(uint32_t));
	if (!framebuffer || !tile) {
		if (framebuffer) free(framebuffer);
		if (tile) free(tile);
		return 0.0;
	}
	memset(tile, 0x55, 64 * 64 * sizeof(uint32_t));

	uint64_t start = bench_get_time_ns();
	for (int it = 0; it < iters; it++) {
		int dst_x = (it * 17) % (W - 64);
		int dst_y = (it * 23) % (H - 64);

		for (int y = 0; y < 64; y++) {
			uint32_t *dst_row = &framebuffer[(dst_y + y) * W + dst_x];
			uint32_t *src_row = &tile[y * 64];
			for (int x = 0; x < 64; x++) {
				/* Alpha blend simulation */
				uint32_t d = dst_row[x];
				uint32_t s = src_row[x];
				dst_row[x] = (d & 0xFEFEFEFE) >> 1 | (s & 0xFEFEFEFE) >> 1;
			}
		}
	}
	uint64_t duration = bench_get_time_ns() - start;
	volatile uint32_t sink = framebuffer[0];
	(void)sink;

	free(framebuffer);
	free(tile);

	double seconds = bench_ns_to_s(duration);
	return (seconds > 0.0) ? ((double)iters / seconds) : 0.0; /* blits/sec */
}

/* 3. Traits & Configuration Parser Benchmark */
static double bench_traits_parser(int iters) {
	const char dummy_traits[] =
		"device=RG353V\n"
		"soc=rk3566\n"
		"arch=arm64\n"
		"screen_width=640\n"
		"screen_height=480\n"
		"screen_rotation=0\n"
		"key_a=305\n"
		"key_b=304\n"
		"key_x=307\n"
		"key_y=308\n"
		"key_menu=316\n";

	uint64_t start = bench_get_time_ns();
	int parsed_keys = 0;

	for (int it = 0; it < iters; it++) {
		char buf[512];
		strncpy(buf, dummy_traits, sizeof(buf) - 1);
		buf[sizeof(buf) - 1] = '\0';

		char *line = strtok(buf, "\n");
		while (line) {
			char *eq = strchr(line, '=');
			if (eq) {
				*eq = '\0';
				parsed_keys += (int)(eq - line);
			}
			line = strtok(NULL, "\n");
		}
	}
	uint64_t duration = bench_get_time_ns() - start;
	volatile int sink = parsed_keys;
	(void)sink;

	double seconds = bench_ns_to_s(duration);
	return (seconds > 0.0) ? ((double)iters / seconds) : 0.0; /* parse ops/sec */
}

int run_bench_ui(bench_result_t *results, int max_results, int quick_mode) {
	if (max_results < 3) return 0;
	int idx = 0;

	int scan_iters = quick_mode ? UI_SCAN_ITERS_QUICK : UI_SCAN_ITERS_DEFAULT;
	int blit_iters = quick_mode ? BLIT_ITERS_QUICK : BLIT_ITERS_DEFAULT;
	int trait_iters = quick_mode ? 25000 : 100000;

	/* 1. Directory Scanning */
	double scan_ops = bench_ui_dir_scan(scan_iters);
	snprintf(results[idx].name, sizeof(results[idx].name), "ui.dir_scan_throughput");
	results[idx].category = BENCH_CAT_UI;
	results[idx].raw_value = scan_ops;
	snprintf(results[idx].unit, sizeof(results[idx].unit), "scans/s");
	results[idx].baseline_value = 8000.0; /* 8k scans/sec baseline */
	results[idx].lower_is_better = 0;
	results[idx].normalized_score = (scan_ops / results[idx].baseline_value) * 1000.0;
	idx++;

	/* 2. UI Surface Blitting */
	double blit_ops = bench_ui_blitting(blit_iters);
	snprintf(results[idx].name, sizeof(results[idx].name), "ui.surface_blitting");
	results[idx].category = BENCH_CAT_UI;
	results[idx].raw_value = blit_ops;
	snprintf(results[idx].unit, sizeof(results[idx].unit), "blits/s");
	results[idx].baseline_value = 150000.0; /* 150k blits/sec baseline */
	results[idx].lower_is_better = 0;
	results[idx].normalized_score = (blit_ops / results[idx].baseline_value) * 1000.0;
	idx++;

	/* 3. Traits Parsing */
	double trait_ops = bench_traits_parser(trait_iters);
	snprintf(results[idx].name, sizeof(results[idx].name), "ui.traits_parsing");
	results[idx].category = BENCH_CAT_UI;
	results[idx].raw_value = trait_ops / 1000.0; /* kops/s */
	snprintf(results[idx].unit, sizeof(results[idx].unit), "kops/s");
	results[idx].baseline_value = 450.0; /* 450 kops/s baseline */
	results[idx].lower_is_better = 0;
	results[idx].normalized_score = (results[idx].raw_value / results[idx].baseline_value) * 1000.0;
	idx++;

	return idx;
}
