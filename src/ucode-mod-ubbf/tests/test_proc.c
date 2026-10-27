/* SPDX-License-Identifier: GPL-2.0-only */

/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

/*
 * proc.c: cpu_stats(), process_count(), process_info(), module_spawn()
 * and module_kill(). The parser cases bind-mount crafted files over the
 * files of /proc, which the mount namespace of run-isolated.sh permits.
 */

#include "harness.h"
#include "ubbf.h"

#include <dirent.h>
#include <fcntl.h>
#include <signal.h>
#include <spawn.h>
#include <unistd.h>
#include <sys/mount.h>
#include <sys/resource.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/wait.h>

extern char **environ;

static void
file_write(const char *path, const char *content, size_t len)
{
	int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0644);

	assert_true(fd >= 0);
	assert_int_equal(write(fd, content, len), (ssize_t)len);
	close(fd);
}

static void
file_put(const char *path, const char *content)
{
	file_write(path, content, strlen(content));
}

static bool
file_bind(const char *source, const char *target)
{
	return mount(source, target, "none", MS_BIND, NULL) == 0;
}

/*
 * posix_spawn() of glibc reports a failed exec as its error; under valgrind
 * the child is a plain fork that exits with 127 instead.
 */
static bool
spawn_reports_exec_failure(void)
{
	char *argv[] = { "/nonexistent/ubbf-test", NULL };
	pid_t pid;

	if (posix_spawn(&pid, argv[0], NULL, NULL, argv, environ) != 0)
		return true;

	waitpid(pid, NULL, 0);

	return false;
}

static pid_t
sleep_spawn(void)
{
	char *argv[] = { "/bin/sleep", "60", NULL };
	pid_t pid;

	assert_int_equal(posix_spawn(&pid, argv[0], NULL, NULL, argv, environ), 0);

	return pid;
}

static void
child_end(pid_t pid)
{
	kill(pid, SIGKILL);
	assert_int_equal(waitpid(pid, NULL, 0), pid);
}

static bool
process_gone(pid_t pid)
{
	for (int i = 0; i < 500; i++) {
		if (kill(pid, 0) != 0 && errno == ESRCH)
			return true;

		usleep(10000);
	}

	return false;
}

/*
 * Moves an open fd out of the way, for the cases that need the low fd
 * numbers free; the VM holds the read end of its signal pipe on fd 3.
 */
static int
fd_park(int fd)
{
	int saved = fcntl(fd, F_DUPFD_CLOEXEC, 100);

	if (saved >= 0)
		close(fd);

	return saved;
}

static void
fd_unpark(int saved, int fd)
{
	if (saved < 0)
		return;

	assert_int_equal(dup2(saved, fd), fd);
	assert_int_equal(fcntl(fd, F_SETFD, FD_CLOEXEC), 0);
	close(saved);
}

static int
fd_count(void)
{
	DIR *d = opendir("/proc/self/fd");
	struct dirent *ent;
	int count = 0;

	assert_non_null(d);
	while ((ent = readdir(d)))
		if (ent->d_name[0] != '.')
			count++;

	closedir(d);

	return count;
}

static char *
status_field(pid_t pid, const char *name, char *buf, size_t len)
{
	char path[64], line[256];
	size_t nlen = strlen(name);
	FILE *fp;

	snprintf(path, sizeof(path), "/proc/%d/status", (int)pid);
	fp = fopen(path, "r");
	assert_non_null(fp);

	buf[0] = '\0';
	while (fgets(line, sizeof(line), fp)) {
		if (strncmp(line, name, nlen) || line[nlen] != ':')
			continue;

		snprintf(buf, len, "%s", line + nlen + 1 + strspn(line + nlen + 1, " \t"));
		buf[strcspn(buf, "\n")] = '\0';
		break;
	}

	fclose(fp);

	return buf;
}

static unsigned long long
status_mask(pid_t pid, const char *name)
{
	char buf[64];

	return strtoull(status_field(pid, name, buf, sizeof(buf)), NULL, 16);
}

static bool
field_is(uc_value_t *obj, const char *name, const char *expected)
{
	uc_value_t *val = ucv_object_get(obj, name, NULL);

	return ucv_type(val) == UC_STRING && !strcmp(ucv_string_get(val), expected);
}

static void
field_expect(uc_value_t *obj, const char *name, const char *expected)
{
	uc_value_t *val = ucv_object_get(obj, name, NULL);

	assert_int_equal(ucv_type(val), UC_STRING);
	assert_string_equal(ucv_string_get(val), expected);
}

static long long
field_int(uc_value_t *obj, const char *name)
{
	uc_value_t *val = ucv_object_get(obj, name, NULL);
	const char *s;
	char *end;
	long long n;

	assert_int_equal(ucv_type(val), UC_STRING);
	s = ucv_string_get(val);
	n = strtoll(s, &end, 10);
	assert_true(*s && !*end);

	return n;
}

static void
cpu_check(uc_value_t *row)
{
	static const char *const names[] = {
		"UserModeUtilization", "SystemModeUtilization", "IdleModeUtilization", "CPUUtilization"
	};
	int64_t vals[4];

	assert_int_equal(ucv_type(row), UC_OBJECT);
	assert_int_equal(ucv_object_length(row), 4);

	for (size_t i = 0; i < ARRAY_SIZE(names); i++) {
		uc_value_t *val = ucv_object_get(row, names[i], NULL);
		const char *s;
		char *end;

		assert_int_equal(ucv_type(val), UC_STRING);
		s = ucv_string_get(val);
		vals[i] = strtoll(s, &end, 10);
		assert_true(*s && !*end);
		assert_in_range(vals[i], 0, 100);
	}

	assert_in_range(vals[2] + vals[3], 100, 101);
}

static void
test_cpu_stats_host(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *res = vm_call(vm, uc_ubbf_cpu_stats, 0);
	char key[32];
	long ncpu = sysconf(_SC_NPROCESSORS_ONLN);

	cpu_check(ucv_object_get(res, "cpu", NULL));
	assert_int_equal(ucv_object_length(res), ncpu + 1);

	ucv_object_foreach(res, k, row) {
		(void)k;
		cpu_check(row);
	}

	snprintf(key, sizeof(key), "cpu%ld", ncpu - 1);
	assert_non_null(ucv_object_get(res, key, NULL));

	ucv_put(res);
}

static void
test_cpu_stats(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *res;

	file_put("/tmp/fake-stat",
		"cpu  100 0 100 800 0 0 0 0 0 0\n"
		"cpu0 50 50 0 900 0 0 0\n"
		"cpu1 1 0 0 2 0 0 0\n"
		"cpu2 0 0 0 0 0 0 0\n"
		"cpu3 5 5 5\n"
		"cpu4 10 0 10 70 5 3 2 1 1 1\n"
		"cpu5 1 0 0 1\n"
		"cpu6 1 0 0 7\n"
		"cpuverylongname1234 1 0 0 1\n"
		"cpux\n"
		"intr 1 2 3\n"
		"ctxt 5\n"
		"softirq 1 2 3\n");
	if (!file_bind("/tmp/fake-stat", "/proc/stat"))
		skip();

	res = vm_call(vm, uc_ubbf_cpu_stats, 0);
	assert_json_equal(vm, res,
		"{ \"cpu\": { \"UserModeUtilization\": \"10\", \"SystemModeUtilization\": \"10\", "
		"\"IdleModeUtilization\": \"80\", \"CPUUtilization\": \"20\" }, "
		"\"cpu0\": { \"UserModeUtilization\": \"10\", \"SystemModeUtilization\": \"0\", "
		"\"IdleModeUtilization\": \"90\", \"CPUUtilization\": \"10\" }, "
		"\"cpu1\": { \"UserModeUtilization\": \"33\", \"SystemModeUtilization\": \"0\", "
		"\"IdleModeUtilization\": \"67\", \"CPUUtilization\": \"33\" }, "
		"\"cpu4\": { \"UserModeUtilization\": \"10\", \"SystemModeUtilization\": \"15\", "
		"\"IdleModeUtilization\": \"70\", \"CPUUtilization\": \"30\" }, "
		"\"cpu5\": { \"UserModeUtilization\": \"50\", \"SystemModeUtilization\": \"0\", "
		"\"IdleModeUtilization\": \"50\", \"CPUUtilization\": \"50\" }, "
		"\"cpu6\": { \"UserModeUtilization\": \"13\", \"SystemModeUtilization\": \"0\", "
		"\"IdleModeUtilization\": \"88\", \"CPUUtilization\": \"13\" }, "
		"\"cpuverylongname\": { \"UserModeUtilization\": \"50\", \"SystemModeUtilization\": \"0\", "
		"\"IdleModeUtilization\": \"50\", \"CPUUtilization\": \"50\" } }");
	ucv_put(res);

	file_put("/tmp/fake-stat", "");
	res = vm_call(vm, uc_ubbf_cpu_stats, 0);
	assert_json_equal(vm, res, "{ }");
	ucv_put(res);

	file_put("/tmp/fake-stat", "intr 1\nctxt 2\n");
	res = vm_call(vm, uc_ubbf_cpu_stats, 0);
	assert_json_equal(vm, res, "{ }");
	ucv_put(res);

	assert_int_equal(umount("/proc/stat"), 0);
}

static void
test_process_count(void **state)
{
	static const char *const entries[] = { "1", "23", "007", "4096", "12a", "abc", "a1", "self" };
	uc_vm_t *vm = *state;
	uc_value_t *res;
	char path[64];

	res = vm_call(vm, uc_ubbf_process_count, 1, ucv_string_new("ignored"));
	assert_int_equal(ucv_type(res), UC_INTEGER);
	assert_true(ucv_int64_get(res) >= 2);
	ucv_put(res);

	assert_int_equal(mkdir("/tmp/fake-proc", 0755), 0);
	for (size_t i = 0; i < ARRAY_SIZE(entries); i++) {
		snprintf(path, sizeof(path), "/tmp/fake-proc/%s", entries[i]);
		assert_int_equal(mkdir(path, 0755), 0);
	}
	file_put("/tmp/fake-proc/99", "a file counts as well");

	if (!file_bind("/tmp/fake-proc", "/proc"))
		skip();

	res = vm_call(vm, uc_ubbf_process_count, 0);
	assert_int_equal(umount("/proc"), 0);
	assert_int_equal(ucv_int64_get(res), 5);
	ucv_put(res);

	assert_int_equal(mkdir("/tmp/empty-proc", 0755), 0);
	assert_true(file_bind("/tmp/empty-proc", "/proc"));
	res = vm_call(vm, uc_ubbf_process_count, 0);
	assert_int_equal(umount("/proc"), 0);
	assert_int_equal(ucv_int64_get(res), 0);
	ucv_put(res);
}

static uc_value_t *
info_wait(uc_vm_t *vm, pid_t pid, const char *state)
{
	uc_value_t *res;

	for (int i = 0; i < 200; i++) {
		res = vm_call(vm, uc_ubbf_process_info, 1, ucv_int64_new(pid));
		if (field_is(res, "State", state))
			return res;

		ucv_put(res);
		usleep(10000);
	}

	fail_msg("process %d never reached %s", (int)pid, state);

	return NULL;
}

static void
test_process_info_host(void **state)
{
	uc_vm_t *vm = *state;
	pid_t pid = sleep_spawn(), zombie;
	char buf[64], comm[64], expected[80];
	uc_value_t *res;
	FILE *fp;

	res = info_wait(vm, pid, "Sleeping");
	snprintf(buf, sizeof(buf), "%d", (int)pid);
	field_expect(res, "PID", buf);
	field_expect(res, "Command", "/bin/sleep 60");
	assert_true(field_int(res, "Size") > 0);
	field_int(res, "Priority");
	assert_true(field_int(res, "CPUTime") >= 0);
	assert_int_equal(ucv_object_length(res), 6);
	ucv_put(res);
	child_end(pid);

	zombie = fork();
	assert_true(zombie >= 0);
	if (zombie == 0)
		_exit(0);

	res = info_wait(vm, zombie, "Zombie");
	snprintf(buf, sizeof(buf), "/proc/%d/comm", (int)zombie);
	fp = fopen(buf, "r");
	assert_non_null(fp);
	assert_non_null(fgets(comm, sizeof(comm), fp));
	fclose(fp);
	comm[strcspn(comm, "\n")] = '\0';
	snprintf(expected, sizeof(expected), "(%s)", comm);
	field_expect(res, "Command", expected);
	ucv_put(res);
	assert_int_equal(waitpid(zombie, NULL, 0), zombie);

	assert_null(vm_call(vm, uc_ubbf_process_info, 1, ucv_int64_new(0)));
	assert_null(vm_call(vm, uc_ubbf_process_info, 1, ucv_int64_new(-1)));
	assert_null(vm_call(vm, uc_ubbf_process_info, 1, ucv_int64_new(999999999)));
	assert_null(vm_call(vm, uc_ubbf_process_info, 1, ucv_string_new("1")));
	assert_null(vm_call(vm, uc_ubbf_process_info, 1, ucv_double_new(1.0)));
	assert_null(vm_call(vm, uc_ubbf_process_info, 0));
}

struct fake_proc {
	pid_t pid;
	char stat[64], statm[64], cmdline[64];
};

static bool
fake_proc_mount(struct fake_proc *fp)
{
	char path[64];

	fp->pid = sleep_spawn();
	snprintf(fp->stat, sizeof(fp->stat), "/proc/%d/stat", (int)fp->pid);
	snprintf(fp->statm, sizeof(fp->statm), "/proc/%d/statm", (int)fp->pid);
	snprintf(fp->cmdline, sizeof(fp->cmdline), "/proc/%d/cmdline", (int)fp->pid);

	file_put("/tmp/fake-pid-stat", "1 (x) S 1");
	file_put("/tmp/fake-pid-statm", "0");
	file_put("/tmp/fake-pid-cmdline", "");

	snprintf(path, sizeof(path), "%s", fp->stat);
	if (!file_bind("/tmp/fake-pid-stat", path)) {
		child_end(fp->pid);
		return false;
	}

	assert_true(file_bind("/tmp/fake-pid-statm", fp->statm));
	assert_true(file_bind("/tmp/fake-pid-cmdline", fp->cmdline));

	return true;
}

static void
fake_proc_umount(struct fake_proc *fp)
{
	assert_int_equal(umount(fp->stat), 0);
	assert_int_equal(umount(fp->statm), 0);
	assert_int_equal(umount(fp->cmdline), 0);
	child_end(fp->pid);
}

static void
info_expect(uc_vm_t *vm, struct fake_proc *fp, const char *expected)
{
	uc_value_t *res = vm_call(vm, uc_ubbf_process_info, 1, ucv_int64_new(fp->pid));
	char buf[512];

	if (!expected) {
		assert_null(res);
		return;
	}

	snprintf(buf, sizeof(buf), expected, (int)fp->pid);
	assert_json_equal(vm, res, buf);
	ucv_put(res);
}

static void
state_expect(uc_vm_t *vm, struct fake_proc *fp, char c, const char *label)
{
	uc_value_t *res;
	char buf[128];

	snprintf(buf, sizeof(buf), "1 (x) %c 1 2 3", c);
	file_put("/tmp/fake-pid-stat", buf);

	res = vm_call(vm, uc_ubbf_process_info, 1, ucv_int64_new(fp->pid));
	field_expect(res, "State", label);
	ucv_put(res);
}

static void
command_expect(uc_vm_t *vm, struct fake_proc *fp, const char *command)
{
	uc_value_t *res = vm_call(vm, uc_ubbf_process_info, 1, ucv_int64_new(fp->pid));

	field_expect(res, "Command", command);
	ucv_put(res);
}

static void
test_process_info(void **state)
{
	static const char stat_full[] =
		"4242 (my (odd) name) S 1 2 3 4 5 6 7 8 9 10 250 150 0 0 25 0 1 0 77 88\n";
	uc_vm_t *vm = *state;
	struct fake_proc fp;
	long tck = sysconf(_SC_CLK_TCK);
	char comm[128], expected[512];

	if (!fake_proc_mount(&fp))
		skip();

	file_put("/tmp/fake-pid-stat", stat_full);
	file_put("/tmp/fake-pid-statm", "1000 200 100 1 0 50 0\n");
	file_write("/tmp/fake-pid-cmdline", "/usr/bin/app\0--flag\0\0value\0", 27);
	snprintf(expected, sizeof(expected),
		 "{ \"PID\": \"%%d\", \"Command\": \"/usr/bin/app --flag value\", \"Size\": \"4000\", "
		 "\"Priority\": \"25\", \"CPUTime\": \"%lld\", \"State\": \"Sleeping\" }",
		 400LL * 1000 / (tck > 0 ? tck : 100));
	info_expect(vm, &fp, expected);

	file_write("/tmp/fake-pid-cmdline", "a\0b\0\0c\0", 7);
	command_expect(vm, &fp, "abc");

	file_write("/tmp/fake-pid-cmdline", "ab\0c\0", 5);
	command_expect(vm, &fp, "ab c");

	file_write("/tmp/fake-pid-cmdline", "\0\0\0", 3);
	file_put("/tmp/fake-pid-statm", "");
	file_put("/tmp/fake-pid-stat", "7 (short) R 1 2");
	info_expect(vm, &fp,
		"{ \"PID\": \"%d\", \"Command\": \"(short)\", \"Size\": \"0\", \"Priority\": \"0\", "
		"\"CPUTime\": \"0\", \"State\": \"Running\" }");

	file_put("/tmp/fake-pid-cmdline", "");
	memset(comm, 'c', 100);
	comm[100] = '\0';
	snprintf(expected, sizeof(expected), "1 (%s) S 1", comm);
	file_put("/tmp/fake-pid-stat", expected);
	comm[63] = '\0';
	snprintf(expected, sizeof(expected),
		 "{ \"PID\": \"%%d\", \"Command\": \"(%s)\", \"Size\": \"0\", \"Priority\": \"0\", "
		 "\"CPUTime\": \"0\", \"State\": \"Sleeping\" }", comm);
	info_expect(vm, &fp, expected);

	state_expect(vm, &fp, 'R', "Running");
	state_expect(vm, &fp, 'S', "Sleeping");
	state_expect(vm, &fp, 'D', "Uninterruptible");
	state_expect(vm, &fp, 'Z', "Zombie");
	state_expect(vm, &fp, 'T', "Stopped");
	state_expect(vm, &fp, 't', "Tracing");
	state_expect(vm, &fp, 'X', "Dead");
	state_expect(vm, &fp, 'x', "Dead");
	state_expect(vm, &fp, 'K', "Wakekill");
	state_expect(vm, &fp, 'W', "Waking");
	state_expect(vm, &fp, 'P', "Parked");
	state_expect(vm, &fp, 'I', "Idle");
	state_expect(vm, &fp, 'Q', "Unknown");

	file_put("/tmp/fake-pid-stat", "1 x S 1 2 3");
	info_expect(vm, &fp, NULL);
	file_put("/tmp/fake-pid-stat", "1 (x S 1 2 3");
	info_expect(vm, &fp, NULL);
	file_put("/tmp/fake-pid-stat", "1 x) S 1 2 3");
	info_expect(vm, &fp, NULL);
	file_put("/tmp/fake-pid-stat", "1 )x( S 1 2 3");
	info_expect(vm, &fp, NULL);
	file_put("/tmp/fake-pid-stat", "");
	info_expect(vm, &fp, NULL);

	/* a line that ends at the comm has no fields after it */
	file_put("/tmp/fake-pid-stat", "1 (x)");
	info_expect(vm, &fp,
		"{ \"PID\": \"%d\", \"Command\": \"(x)\", \"Size\": \"0\", \"Priority\": \"0\", "
		"\"CPUTime\": \"0\", \"State\": \"Unknown\" }");

	fake_proc_umount(&fp);
}

static uc_value_t *
spawn_call(uc_vm_t *vm, const char *host, const char *module, pid_t *pid, int *fd)
{
	uc_value_t *res = vm_call(vm, uc_ubbf_module_spawn, 2, ucv_string_new(host), ucv_string_new(module));

	assert_int_equal(ucv_type(res), UC_OBJECT);
	assert_int_equal(ucv_object_length(res), 2);
	*pid = ucv_int64_get(ucv_object_get(res, "pid", NULL));
	*fd = ucv_int64_get(ucv_object_get(res, "fd", NULL));
	assert_true(*pid > 0);
	assert_true(*fd >= 0);

	return res;
}

static void
kill_expect(uc_vm_t *vm, pid_t pid)
{
	uc_value_t *res = vm_call(vm, uc_ubbf_module_kill, 1, ucv_int64_new(pid));

	assert_int_equal(ucv_type(res), UC_BOOLEAN);
	assert_true(ucv_boolean_get(res));
	ucv_put(res);
}

static void
test_module_spawn(void **state)
{
	uc_vm_t *vm = *state;
	struct sigaction ign = { .sa_handler = SIG_IGN }, old_act;
	sigset_t block, old_mask;
	char path[64], link[64];
	struct stat st;
	uc_value_t *res;
	ssize_t n;
	pid_t pid;
	int fd;

	sigemptyset(&block);
	sigaddset(&block, SIGUSR1);
	assert_int_equal(sigprocmask(SIG_BLOCK, &block, &old_mask), 0);
	assert_int_equal(sigaction(SIGUSR2, &ign, &old_act), 0);

	res = spawn_call(vm, "/bin/sleep", "60", &pid, &fd);

	assert_int_equal(sigaction(SIGUSR2, &old_act, NULL), 0);
	assert_int_equal(sigprocmask(SIG_SETMASK, &old_mask, NULL), 0);

	assert_int_equal(fstat(fd, &st), 0);
	assert_true(S_ISSOCK(st.st_mode));
	assert_true(fcntl(fd, F_GETFD) & FD_CLOEXEC);

	snprintf(path, sizeof(path), "/proc/%d/fd/3", (int)pid);
	n = readlink(path, link, sizeof(link) - 1);
	assert_true(n > 0);
	link[n] = '\0';
	assert_memory_equal(link, "socket:[", 8);

	/* Only the standard signals: under valgrind the child of the emulated
	 * vfork keeps the internal signals 32 and 33 of glibc blocked. */
	assert_int_equal(status_mask(pid, "SigBlk") & 0x7fffffffULL, 0);
	assert_int_equal(status_mask(pid, "SigIgn") & 0x7fffffffULL, 0);

	kill_expect(vm, pid);
	assert_int_equal(kill(pid, 0), -1);
	assert_int_equal(errno, ESRCH);
	close(fd);
	ucv_put(res);
}

static void
socket_echo_expect(int fd)
{
	char buf[128];
	size_t off = 0;
	ssize_t n;

	assert_int_equal(write(fd, "ping\n", 5), 5);

	while (off < sizeof(buf) - 1) {
		n = read(fd, buf + off, sizeof(buf) - 1 - off);
		if (n <= 0)
			break;

		off += n;
	}

	buf[off] = '\0';
	assert_string_equal(buf, "/tmp/echo.sh got ping\n");
}

static void
test_module_spawn_channel(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *res;
	int fd, saved, parked;
	pid_t pid;

	file_put("/tmp/echo.sh", "read line <&3\necho \"$0 got $line\" >&3\n");

	res = spawn_call(vm, "/bin/sh", "/tmp/echo.sh", &pid, &fd);
	socket_echo_expect(fd);
	kill_expect(vm, pid);
	close(fd);
	ucv_put(res);

	/* With fd 0 free, socketpair() hands out fds 0 and 3, so the child end
	 * sits on the fd that dm-host expects and has to move first. */
	parked = fd_park(3);
	saved = fcntl(0, F_DUPFD_CLOEXEC, 100);
	assert_true(saved >= 100);
	close(0);

	res = spawn_call(vm, "/bin/sh", "/tmp/echo.sh", &pid, &fd);
	assert_int_equal(fd, 0);
	assert_int_equal(fcntl(3, F_GETFD), -1);
	socket_echo_expect(fd);
	kill_expect(vm, pid);
	ucv_put(res);

	assert_int_equal(dup2(saved, 0), 0);
	close(saved);
	fd_unpark(parked, 3);
}

static void
test_module_spawn_fail(void **state)
{
	uc_vm_t *vm = *state;
	struct rlimit old_lim, lim;
	int before = fd_count(), saved, parked, probe[2];

	if (spawn_reports_exec_failure()) {
		assert_null(vm_call(vm, uc_ubbf_module_spawn, 2, ucv_string_new("/nonexistent/dm-host"),
				    ucv_string_new("/tmp/mod.so")));
		assert_int_equal(fd_count(), before);
	}

	assert_null(vm_call(vm, uc_ubbf_module_spawn, 2, ucv_string_new("/bin/sleep"), NULL));
	assert_null(vm_call(vm, uc_ubbf_module_spawn, 2, NULL, ucv_string_new("60")));
	assert_null(vm_call(vm, uc_ubbf_module_spawn, 2, ucv_string_new("/bin/sleep"), ucv_int64_new(60)));
	assert_null(vm_call(vm, uc_ubbf_module_spawn, 0));

	assert_int_equal(getrlimit(RLIMIT_NOFILE, &old_lim), 0);
	parked = fd_park(3);
	saved = fcntl(0, F_DUPFD_CLOEXEC, 100);
	assert_true(saved >= 100);

	/* A limit of four fds leaves no room for the socket pair once 0 to 2
	 * are open, and none for the move of the child end off fd 3 once fd 0
	 * is free. */
	lim = old_lim;
	lim.rlim_cur = 4;
	assert_int_equal(setrlimit(RLIMIT_NOFILE, &lim), 0);

	/* valgrind does not apply the limit to socketpair() */
	if (socketpair(AF_UNIX, SOCK_STREAM, 0, probe) == 0) {
		close(probe[0]);
		close(probe[1]);
		assert_int_equal(setrlimit(RLIMIT_NOFILE, &old_lim), 0);
		close(saved);
		fd_unpark(parked, 3);
		skip();
	}

	assert_null(vm_call(vm, uc_ubbf_module_spawn, 2, ucv_string_new("/bin/sleep"), ucv_string_new("60")));
	assert_int_equal(fcntl(3, F_GETFD), -1);

	close(0);
	assert_null(vm_call(vm, uc_ubbf_module_spawn, 2, ucv_string_new("/bin/sleep"), ucv_string_new("60")));
	assert_int_equal(fcntl(0, F_GETFD), -1);
	assert_int_equal(fcntl(3, F_GETFD), -1);

	assert_int_equal(setrlimit(RLIMIT_NOFILE, &old_lim), 0);
	assert_int_equal(dup2(saved, 0), 0);
	close(saved);
	fd_unpark(parked, 3);
}

static void
test_module_kill(void **state)
{
	uc_vm_t *vm = *state;
	char buf[64];
	uc_value_t *res;
	pid_t pid, orphan;
	FILE *fp;
	int fd;

	file_put("/tmp/stubborn.sh", "trap '' TERM INT HUP\nread line <&3\n");
	res = spawn_call(vm, "/bin/sh", "/tmp/stubborn.sh", &pid, &fd);
	usleep(100000);
	kill_expect(vm, pid);
	assert_int_equal(kill(pid, 0), -1);
	assert_int_equal(errno, ESRCH);
	assert_int_equal(waitpid(pid, NULL, WNOHANG), -1);
	assert_int_equal(errno, ECHILD);
	close(fd);
	ucv_put(res);

	pid = fork();
	assert_true(pid >= 0);
	if (pid == 0)
		_exit(3);

	usleep(100000);
	kill_expect(vm, pid);
	assert_int_equal(waitpid(pid, NULL, WNOHANG), -1);
	assert_int_equal(errno, ECHILD);

	fp = popen("/bin/sleep 60 >/dev/null 2>&1 & echo $!", "r");
	assert_non_null(fp);
	assert_non_null(fgets(buf, sizeof(buf), fp));
	assert_int_equal(pclose(fp), 0);
	orphan = (pid_t)strtol(buf, NULL, 10);
	assert_true(orphan > 0);
	assert_int_equal(kill(orphan, 0), 0);
	kill_expect(vm, orphan);
	assert_true(process_gone(orphan));

	assert_null(vm_call(vm, uc_ubbf_module_kill, 1, ucv_int64_new(0)));
	assert_null(vm_call(vm, uc_ubbf_module_kill, 1, ucv_int64_new(-1)));
	assert_null(vm_call(vm, uc_ubbf_module_kill, 1, ucv_string_new("1")));
	assert_null(vm_call(vm, uc_ubbf_module_kill, 1, ucv_double_new(2.0)));
	assert_null(vm_call(vm, uc_ubbf_module_kill, 0));
}

int
main(void)
{
	const struct CMUnitTest tests[] = {
		cmocka_unit_test(test_cpu_stats_host),
		cmocka_unit_test(test_cpu_stats),
		cmocka_unit_test(test_process_count),
		cmocka_unit_test(test_process_info_host),
		cmocka_unit_test(test_process_info),
		cmocka_unit_test(test_module_spawn),
		cmocka_unit_test(test_module_spawn_channel),
		cmocka_unit_test(test_module_spawn_fail),
		cmocka_unit_test(test_module_kill),
	};

	return cmocka_run_group_tests(tests, vm_setup, vm_teardown);
}
