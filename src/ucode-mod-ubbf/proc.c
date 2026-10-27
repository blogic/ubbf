/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

#include "ubbf.h"
#include "bindings.h"
#include <ctype.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <spawn.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <unistd.h>

extern char **environ;

extern char *sysfs_read_file(const char *path);

/**
 * Parses one CPU line from `/proc/stat` ("cpu", "cpu0", "cpu1", ...) and
 * appends the percentage breakdown to `out` under the key `key`.
 */
static void
cpu_stats_parse_line(const char *line, uc_value_t *out, const char *key,
		     uc_vm_t *vm)
{
	long long user = 0, nice = 0, system_t = 0, idle = 0;
	long long iowait = 0, irq = 0, softirq = 0, total;
	double um, sm, im, util;
	char buf[16];
	uc_value_t *o;

	/* Skip the leading label, expect 7 numeric columns. */
	while (*line && !isspace((unsigned char)*line))
		line++;
	if (sscanf(line, " %lld %lld %lld %lld %lld %lld %lld",
		   &user, &nice, &system_t, &idle, &iowait, &irq, &softirq) < 4)
		return;

	total = user + nice + system_t + idle + iowait + irq + softirq;
	if (total <= 0)
		return;

	um   = ((double)(user + nice) * 100.0) / total;
	sm   = ((double)(system_t + irq + softirq) * 100.0) / total;
	im   = ((double)idle * 100.0) / total;
	util = 100.0 - im;

	o = ucv_object_new(vm);
	snprintf(buf, sizeof(buf), "%d", (int)(um + 0.5));
	ucv_object_add(o, "UserModeUtilization", ucv_string_new(buf));
	snprintf(buf, sizeof(buf), "%d", (int)(sm + 0.5));
	ucv_object_add(o, "SystemModeUtilization", ucv_string_new(buf));
	snprintf(buf, sizeof(buf), "%d", (int)(im + 0.5));
	ucv_object_add(o, "IdleModeUtilization", ucv_string_new(buf));
	snprintf(buf, sizeof(buf), "%d", (int)(util + 0.5));
	ucv_object_add(o, "CPUUtilization", ucv_string_new(buf));

	ucv_object_add(out, key, o);
}

/**
 * Parses `/proc/stat` and returns a per-CPU utilisation breakdown.
 *
 * Output keys are the CPU labels from `/proc/stat`: `"cpu"` for the
 * aggregate row, then `"cpu0"`, `"cpu1"`, ... per core. Each value is an
 * object with `UserModeUtilization`, `SystemModeUtilization`,
 * `IdleModeUtilization`, and `CPUUtilization` (all percentages as
 * decimal strings, rounded to nearest integer).
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (none expected)
 * @return       object keyed by CPU label
 */
uc_value_t *
uc_ubbf_cpu_stats(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *out = ucv_object_new(vm);
	char *content = sysfs_read_file("/proc/stat");
	char *line, *save;

	if (!content)
		return out;

	for (line = strtok_r(content, "\n", &save); line;
	     line = strtok_r(NULL, "\n", &save)) {
		if (strncmp(line, "cpu", 3) != 0)
			continue;
		char key[16] = "cpu";
		const char *p = line + 3;
		size_t klen = 3;
		while (*p && !isspace((unsigned char)*p) && klen < sizeof(key) - 1)
			key[klen++] = *p++;
		key[klen] = '\0';
		cpu_stats_parse_line(line, out, key, vm);
	}

	free(content);
	return out;
}

/**
 * Counts numeric entries in `/proc`, i.e. the live PIDs.
 *
 * Replaces a `lsdir + regex` pass in ucode.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (none expected)
 * @return       integer count
 */
uc_value_t *
uc_ubbf_process_count(uc_vm_t *vm, size_t nargs)
{
	DIR *d = opendir("/proc");
	struct dirent *ent;
	int64_t count = 0;

	if (!d)
		return ucv_int64_new(0);

	while ((ent = readdir(d))) {
		const char *n = ent->d_name;
		if (!isdigit((unsigned char)*n))
			continue;
		while (*n && isdigit((unsigned char)*n))
			n++;
		if (*n == '\0')
			count++;
	}

	closedir(d);
	return ucv_int64_new(count);
}

/**
 * Maps the single-character process state from `stat[2]` to its TR-181
 * label.
 */
static const char *
state_label(char c)
{
	switch (c) {
	case 'R': return "Running";
	case 'S': return "Sleeping";
	case 'D': return "Uninterruptible";
	case 'Z': return "Zombie";
	case 'T': return "Stopped";
	case 't': return "Tracing";
	case 'X': case 'x': return "Dead";
	case 'K': return "Wakekill";
	case 'W': return "Waking";
	case 'P': return "Parked";
	case 'I': return "Idle";
	}
	return "Unknown";
}

/**
 * Reads `/proc/<pid>/cmdline`, drops empty NUL-separated tokens, and
 * joins the remainder with a single space when there is more than one
 * non-trivial argument; otherwise concatenates without a separator.
 *
 * Returns 0 when no command is available; the caller falls back to the
 * `comm` field surrounded by parentheses.
 */
static int
cmdline_read(int pid, char *out, size_t out_len)
{
	char path[64];
	char buf[4096];
	int fd;
	ssize_t n, off, write_off;
	bool need_space = false, has_long = false;
	int parts_seen = 0;

	snprintf(path, sizeof(path), "/proc/%d/cmdline", pid);
	fd = open(path, O_RDONLY);
	if (fd < 0)
		return 0;
	n = read(fd, buf, sizeof(buf) - 1);
	close(fd);
	if (n <= 0)
		return 0;
	buf[n] = '\0';

	/* First pass: detect whether any argument is longer than one byte. */
	for (off = 0; off < n; ) {
		size_t len = strlen(buf + off);
		if (len > 0) {
			parts_seen++;
			if (len > 1) {
				has_long = true;
				break;
			}
		}
		off += len + 1;
	}
	if (parts_seen == 0)
		return 0;

	/* Second pass: emit. Use space as separator when we saw a long token,
	 * matching the original ucode `cmdline_format` heuristic. */
	write_off = 0;
	for (off = 0; off < n && write_off < (ssize_t)out_len - 1; ) {
		size_t len = strlen(buf + off);
		if (len > 0) {
			if (need_space && has_long && write_off < (ssize_t)out_len - 1)
				out[write_off++] = ' ';
			size_t copy = len;
			if (write_off + copy >= out_len)
				copy = out_len - 1 - write_off;
			memcpy(out + write_off, buf + off, copy);
			write_off += copy;
			need_space = true;
		}
		off += len + 1;
	}
	out[write_off] = '\0';
	return 1;
}

/**
 * Builds a TR-181 Process row from `/proc/<pid>/{stat,cmdline,statm}`.
 *
 * Mirrors the `parse_process_info` path that used to live in
 * `tr181/DeviceInfo/ProcessStatus.uc`: parses `stat` after the closing
 * paren of the `comm` field, derives the CPU time in milliseconds from
 * utime+stime clock ticks, the size from the first `statm` field (pages
 * of 4 KiB), and falls back to `(<comm>)` when the cmdline is empty.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: pid integer)
 * @return       TR-181 process object, or null when the PID is gone
 */
uc_value_t *
uc_ubbf_process_info(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *pid_val = uc_fn_arg(0);
	int64_t pid;
	char path[64];
	char *stat;
	char *close_paren, *open_paren;
	char comm[64];
	char cmdline[2048] = "";
	char buf[64];
	uc_value_t *obj;
	int field;
	char *p, *save;
	const char *state = "Unknown";
	long long utime = 0, stime = 0;
	long long size_pages = 0;
	int priority = 0;

	if (ucv_type(pid_val) != UC_INTEGER)
		return NULL;
	pid = ucv_int64_get(pid_val);

	snprintf(path, sizeof(path), "/proc/%lld/stat", (long long)pid);
	stat = sysfs_read_file(path);
	if (!stat)
		return NULL;

	close_paren = strrchr(stat, ')');
	open_paren = strchr(stat, '(');
	if (!close_paren || !open_paren || open_paren > close_paren) {
		free(stat);
		return NULL;
	}

	{
		size_t clen = close_paren - open_paren - 1;
		if (clen >= sizeof(comm))
			clen = sizeof(comm) - 1;
		memcpy(comm, open_paren + 1, clen);
		comm[clen] = '\0';
	}

	/* Walk the post-comm fields. Field index 0 is the state char,
	 * field 11/12 are utime/stime, field 15 is priority. */
	field = 0;
	for (p = strtok_r(close_paren + 1, " \t\n", &save); p;
	     p = strtok_r(NULL, " \t\n", &save), field++) {
		switch (field) {
		case 0:  state = state_label(p[0]); break;
		case 11: utime = strtoll(p, NULL, 10); break;
		case 12: stime = strtoll(p, NULL, 10); break;
		case 15: priority = (int)strtol(p, NULL, 10); break;
		}
		if (field >= 15)
			break;
	}
	free(stat);

	/* Memory in KiB; statm reports in pages */
	snprintf(path, sizeof(path), "/proc/%lld/statm", (long long)pid);
	char *statm = sysfs_read_file(path);
	if (statm) {
		size_pages = strtoll(statm, NULL, 10);
		free(statm);
	}

	if (!cmdline_read((int)pid, cmdline, sizeof(cmdline)))
		snprintf(cmdline, sizeof(cmdline), "(%s)", comm);

	obj = ucv_object_new(vm);
	snprintf(buf, sizeof(buf), "%lld", (long long)pid);
	ucv_object_add(obj, "PID", ucv_string_new(buf));
	ucv_object_add(obj, "Command", ucv_string_new(cmdline));
	snprintf(buf, sizeof(buf), "%lld", size_pages * (sysconf(_SC_PAGESIZE) / 1024));
	ucv_object_add(obj, "Size", ucv_string_new(buf));
	snprintf(buf, sizeof(buf), "%d", priority);
	ucv_object_add(obj, "Priority", ucv_string_new(buf));
	/* utime+stime are in clock ticks; TR-181 CPUTime is milliseconds */
	long clk_tck = sysconf(_SC_CLK_TCK);
	if (clk_tck <= 0)
		clk_tck = 100;
	snprintf(buf, sizeof(buf), "%lld", (utime + stime) * 1000 / clk_tck);
	ucv_object_add(obj, "CPUTime", ucv_string_new(buf));
	ucv_object_add(obj, "State", ucv_string_new(state));

	return obj;
}

/* The fd on which dm-host expects its ubus channel. */
#define DM_HOST_FD	3

/**
 * Runs a program with posix_spawn(), with an empty signal mask and the
 * default action for all signals: the caller may block or ignore signals
 * that the program expects.
 *
 * @param pid   receives the process id
 * @param argv  NULL-terminated argument list; argv[0] is the program path,
 *              or a name that the PATH lookup of posix_spawnp() resolves
 * @param fa    the file actions of the child
 * @return      0, or the error number of posix_spawn()
 */
static int
process_spawn(pid_t *pid, char *const argv[], const posix_spawn_file_actions_t *fa)
{
	posix_spawnattr_t attr;
	sigset_t none, all;
	int rv;

	sigemptyset(&none);
	sigfillset(&all);
	posix_spawnattr_init(&attr);
	posix_spawnattr_setflags(&attr, POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF);
	posix_spawnattr_setsigmask(&attr, &none);
	posix_spawnattr_setsigdefault(&attr, &all);

	rv = posix_spawnp(pid, argv[0], fa, &attr, argv, environ);

	posix_spawnattr_destroy(&attr);

	return rv;
}

/**
 * Starts a native data model module: dm-host with the module path as its
 * argument and one end of a socket pair as fd 3. obuspa runs several
 * threads, so the child must not run anything but exec after the fork;
 * posix_spawn() does exactly that.
 *
 * ubbf.module_spawn(host, module) -> { pid, fd } or null
 */
uc_value_t *
uc_ubbf_module_spawn(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *host = uc_fn_arg(0), *module = uc_fn_arg(1), *obj;
	posix_spawn_file_actions_t fa;
	char *argv[3];
	int sv[2], rv;
	pid_t pid;

	if (ucv_type(host) != UC_STRING || ucv_type(module) != UC_STRING)
		return NULL;

	if (socketpair(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0, sv))
		return NULL;

	/* dup2() onto the same fd would keep close-on-exec set. */
	if (sv[1] == DM_HOST_FD) {
		int moved = fcntl(sv[1], F_DUPFD_CLOEXEC, DM_HOST_FD + 1);

		close(sv[1]);
		sv[1] = moved;
	}

	posix_spawn_file_actions_init(&fa);
	posix_spawn_file_actions_adddup2(&fa, sv[1], DM_HOST_FD);

	argv[0] = (char *)ucv_string_get(host);
	argv[1] = (char *)ucv_string_get(module);
	argv[2] = NULL;

	rv = (sv[1] < 0) ? -1 : process_spawn(&pid, argv, &fa);

	posix_spawn_file_actions_destroy(&fa);
	if (sv[1] >= 0)
		close(sv[1]);

	if (rv) {
		close(sv[0]);
		return NULL;
	}

	obj = ucv_object_new(vm);
	ucv_object_add(obj, "pid", ucv_int64_new(pid));
	ucv_object_add(obj, "fd", ucv_int64_new(sv[0]));

	return obj;
}

/**
 * Ends a module process and reaps it. uloop may reap it first; then
 * waitpid() fails with ECHILD, which is fine.
 *
 * ubbf.module_kill(pid) -> true
 */
uc_value_t *
uc_ubbf_module_kill(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *pid = uc_fn_arg(0);

	if (ucv_type(pid) != UC_INTEGER || ucv_int64_get(pid) <= 0)
		return NULL;

	kill((pid_t)ucv_int64_get(pid), SIGKILL);
	while (waitpid((pid_t)ucv_int64_get(pid), NULL, 0) < 0 && errno == EINTR)
		;

	return ucv_boolean_new(true);
}

/**
 * Runs a program from an argument list, without a shell, and collects its
 * output, stdout and stderr together as `cmd 2>&1` gives them. See
 * process_spawn() for the signal setup of the child.
 *
 * @param argv    NULL-terminated argument list; argv[0] is the program path
 *                or a name to look up in PATH
 * @param status  receives the exit code, or -1 when the program did not run
 *                or ended by a signal
 * @return        the output, freed by the caller, or NULL when the program
 *                did not run
 */
char *
spawn_output(char *const argv[], int *status)
{
	posix_spawn_file_actions_t fa;
	size_t len = 0, size = 4096;
	int fds[2], rv, ws;
	char *buf;
	ssize_t n;
	pid_t pid;

	*status = -1;

	if (pipe2(fds, O_CLOEXEC))
		return NULL;

	posix_spawn_file_actions_init(&fa);
	posix_spawn_file_actions_adddup2(&fa, fds[1], STDOUT_FILENO);
	posix_spawn_file_actions_adddup2(&fa, fds[1], STDERR_FILENO);

	rv = process_spawn(&pid, argv, &fa);

	posix_spawn_file_actions_destroy(&fa);
	close(fds[1]);

	if (rv) {
		close(fds[0]);
		return NULL;
	}

	buf = xalloc(size);
	for (;;) {
		n = read(fds[0], buf + len, size - len - 1);
		if (n < 0 && errno == EINTR)
			continue;
		if (n <= 0)
			break;

		len += n;
		if (size - len - 1 == 0) {
			size *= 2;
			buf = xrealloc(buf, size);
		}
	}
	buf[len] = '\0';
	close(fds[0]);

	while ((rv = waitpid(pid, &ws, 0)) < 0 && errno == EINTR)
		;

	if (rv == pid && WIFEXITED(ws))
		*status = WEXITSTATUS(ws);

	return buf;
}
