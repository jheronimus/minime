#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

#define FIFO_PATH "/run/bt-audio.fifo"
#define TARGET_PATH "/run/bt-audio-target"
#define BUFFER_SIZE 16384

static pid_t player_pid;
static int player_in = -1;

static void stop_player(void)
{
	if (player_pid > 0) {
		kill(player_pid, SIGTERM);
		close(player_in);
		waitpid(player_pid, NULL, 0);
	}
	player_pid = 0;
	player_in = -1;
}

static int read_target(char *target, size_t size)
{
	int fd;
	ssize_t length;

	target[0] = '\0';
	fd = open(TARGET_PATH, O_RDONLY | O_CLOEXEC);
	if (fd < 0)
		return -1;
	length = read(fd, target, size - 1);
	close(fd);
	if (length <= 0)
		return 0;
	target[length] = '\0';
	while (length > 0 && (target[length - 1] == '\n' || target[length - 1] == '\r'))
		target[--length] = '\0';
	return 0;
}

static int start_player(const char *target)
{
	int pipefd[2];
	pid_t pid;

	if (pipe(pipefd) < 0)
		return -1;
	pid = fork();
	if (pid < 0) {
		close(pipefd[0]);
		close(pipefd[1]);
		return -1;
	}
	if (pid == 0) {
		char device[64];
		int length;

		close(pipefd[1]);
		if (dup2(pipefd[0], STDIN_FILENO) < 0)
			_exit(126);
		close(pipefd[0]);
		length = snprintf(device, sizeof(device), "bluealsa:DEV=%s,PROFILE=a2dp", target);
		if (length < 0 || (size_t)length >= sizeof(device))
			_exit(126);
		execlp("aplay", "aplay", "-q", "-t", "raw", "-f", "S16_LE", "-c", "2",
		       "-r", "48000", "-D", "bt_output", "-", (char *)NULL);
		_exit(127);
	}
	close(pipefd[0]);
	player_pid = pid;
	player_in = pipefd[1];
	return 0;
}

int main(void)
{
	char target[64];
	char active[64] = "";
	char buffer[BUFFER_SIZE];
	ssize_t count;
	int fifo;

	signal(SIGPIPE, SIG_IGN);
	umask(0);
	if (mkfifo(FIFO_PATH, 0666) < 0 && errno != EEXIST)
		return 1;
	fifo = open(FIFO_PATH, O_RDONLY);
	if (fifo < 0)
		return 1;
	for (;;) {
		read_target(target, sizeof(target));
		if (strcmp(target, active) != 0) {
			stop_player();
			strncpy(active, target, sizeof(active) - 1);
			active[sizeof(active) - 1] = '\0';
			if (active[0] != '\0')
				start_player(active);
		}
		count = read(fifo, buffer, sizeof(buffer));
		if (count == 0)
			continue;
		if (count < 0)
			continue;
		if (player_in >= 0 && write(player_in, buffer, (size_t)count) < 0)
			stop_player();
	}
}
