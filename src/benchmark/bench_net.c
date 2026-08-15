#include "bench.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <pthread.h>
#include <sys/socket.h>
#include <sys/types.h>

#define NET_BUF_SIZE (64 * 1024) /* 64 KB */
#define NET_TRANSFER_MB_DEFAULT 32
#define NET_TRANSFER_MB_QUICK   8

/* 1. Full-Duplex Socket Stream Throughput Benchmark */
typedef struct {
	int fd;
	int total_bytes;
} net_worker_arg_t;

static void *socket_receiver_thread(void *arg) {
	net_worker_arg_t *a = (net_worker_arg_t *)arg;
	uint8_t *buf = (uint8_t *)malloc(NET_BUF_SIZE);
	if (!buf) return NULL;

	int received = 0;
	while (received < a->total_bytes) {
		ssize_t n = recv(a->fd, buf, NET_BUF_SIZE, 0);
		if (n <= 0) break;
		received += (int)n;
	}
	free(buf);
	return NULL;
}

static double bench_socket_stream(int total_mb) {
	int fds[2];
	if (socketpair(AF_UNIX, SOCK_STREAM, 0, fds) < 0) {
		return 0.0;
	}

	int total_bytes = total_mb * 1024 * 1024;
	net_worker_arg_t arg;
	arg.fd = fds[0];
	arg.total_bytes = total_bytes;

	pthread_t rx_thread;
	if (pthread_create(&rx_thread, NULL, socket_receiver_thread, &arg) != 0) {
		close(fds[0]);
		close(fds[1]);
		return 0.0;
	}

	uint8_t *send_buf = (uint8_t *)malloc(NET_BUF_SIZE);
	if (!send_buf) {
		close(fds[0]);
		close(fds[1]);
		pthread_join(rx_thread, NULL);
		return 0.0;
	}
	memset(send_buf, 0x3C, NET_BUF_SIZE);

	uint64_t start = bench_get_time_ns();
	int sent = 0;
	while (sent < total_bytes) {
		int chunk = total_bytes - sent;
		if (chunk > NET_BUF_SIZE) chunk = NET_BUF_SIZE;
		ssize_t n = send(fds[1], send_buf, chunk, 0);
		if (n <= 0) break;
		sent += (int)n;
	}
	pthread_join(rx_thread, NULL);
	uint64_t duration = bench_get_time_ns() - start;

	close(fds[0]);
	close(fds[1]);
	free(send_buf);

	double seconds = bench_ns_to_s(duration);
	return (seconds > 0.0) ? ((double)total_mb / seconds) : 0.0; /* MB/s */
}

int run_bench_net(bench_result_t *results, int max_results, int quick_mode) {
	if (max_results < 2) return 0;
	int idx = 0;
	int total_mb = quick_mode ? NET_TRANSFER_MB_QUICK : NET_TRANSFER_MB_DEFAULT;

	/* 1. Socket Stream Bandwidth */
	double stream_mb = bench_socket_stream(total_mb);
	snprintf(results[idx].name, sizeof(results[idx].name), "net.socket_stream_bw");
	results[idx].category = BENCH_CAT_NET;
	results[idx].raw_value = stream_mb;
	snprintf(results[idx].unit, sizeof(results[idx].unit), "MB/s");
	results[idx].baseline_value = 650.0; /* 650 MB/s RK3566 socket stream baseline */
	results[idx].lower_is_better = 0;
	results[idx].skipped = (stream_mb <= 0.0) ? 1 : 0;
	results[idx].normalized_score = (stream_mb > 0.0) ? ((stream_mb / results[idx].baseline_value) * 1000.0) : 0.0;
	idx++;

	/* 2. Network Stack Throughput */
	double stack_mb = bench_socket_stream(total_mb / 2);
	snprintf(results[idx].name, sizeof(results[idx].name), "net.stack_throughput");
	results[idx].category = BENCH_CAT_NET;
	results[idx].raw_value = stack_mb;
	snprintf(results[idx].unit, sizeof(results[idx].unit), "MB/s");
	results[idx].baseline_value = 650.0;
	results[idx].lower_is_better = 0;
	results[idx].skipped = (stack_mb <= 0.0) ? 1 : 0;
	results[idx].normalized_score = (stack_mb > 0.0) ? ((stack_mb / results[idx].baseline_value) * 1000.0) : 0.0;
	idx++;

	return idx;
}
