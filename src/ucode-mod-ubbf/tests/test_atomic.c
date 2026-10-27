/* SPDX-License-Identifier: GPL-2.0-only */

/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

/*
 * atomic.c: tmpfile_name(), write_file_atomic() and file_write_atomic().
 */

#include "harness.h"
#include "ubbf.h"

#include <fcntl.h>
#include <unistd.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/wait.h>

static char *
file_get(const char *path)
{
	static char buf[256];
	ssize_t n;
	int fd;

	fd = open(path, O_RDONLY);
	if (fd < 0)
		return NULL;

	n = read(fd, buf, sizeof(buf) - 1);
	close(fd);
	if (n < 0)
		return NULL;

	buf[n] = '\0';

	return buf;
}

static void
file_put(const char *path, const char *content, mode_t mode)
{
	int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, mode);

	assert_true(fd >= 0);
	assert_int_equal(write(fd, content, strlen(content)), (ssize_t)strlen(content));
	assert_int_equal(fchmod(fd, mode), 0);
	close(fd);
}

static mode_t
file_mode(const char *path)
{
	struct stat st;

	assert_int_equal(stat(path, &st), 0);

	return st.st_mode & 07777;
}

static bool
file_exists(const char *path)
{
	struct stat st;

	return lstat(path, &st) == 0;
}

static void
tmpfile_check(const char *path, const char *prefix, const char *ext)
{
	size_t plen = strlen(prefix), elen = strlen(ext), len = strlen(path);
	struct stat st;

	assert_int_equal(len, 5 + plen + 7 + elen);
	assert_memory_equal(path, "/tmp/", 5);
	assert_memory_equal(path + 5, prefix, plen);
	assert_int_equal(path[5 + plen], '-');
	assert_string_equal(path + len - elen, ext);
	assert_int_equal(stat(path, &st), 0);
	assert_true(S_ISREG(st.st_mode));
	assert_int_equal(st.st_size, 0);
	assert_int_equal(st.st_mode & 0777, 0600);
}

static void
test_tmpfile_name(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *a, *b, *res;
	char prefix[300];

	a = vm_call(vm, uc_ubbf_tmpfile_name, 1, ucv_string_new("ubbf-test"));
	tmpfile_check(ucv_string_get(a), "ubbf-test", "");

	b = vm_call(vm, uc_ubbf_tmpfile_name, 1, ucv_string_new("ubbf-test"));
	tmpfile_check(ucv_string_get(b), "ubbf-test", "");
	assert_string_not_equal(ucv_string_get(a), ucv_string_get(b));
	ucv_put(a);
	ucv_put(b);

	res = vm_call(vm, uc_ubbf_tmpfile_name, 2, ucv_string_new("cfg"), ucv_string_new(".json"));
	tmpfile_check(ucv_string_get(res), "cfg", ".json");
	ucv_put(res);

	res = vm_call(vm, uc_ubbf_tmpfile_name, 2, ucv_string_new("cfg"), ucv_int64_new(5));
	tmpfile_check(ucv_string_get(res), "cfg", "");
	ucv_put(res);

	memset(prefix, 'p', 243);
	prefix[243] = '\0';
	res = vm_call(vm, uc_ubbf_tmpfile_name, 1, ucv_string_new(prefix));
	tmpfile_check(ucv_string_get(res), prefix, "");
	ucv_put(res);

	prefix[243] = 'p';
	prefix[244] = '\0';
	assert_null(vm_call(vm, uc_ubbf_tmpfile_name, 1, ucv_string_new(prefix)));
	prefix[240] = '\0';
	assert_null(vm_call(vm, uc_ubbf_tmpfile_name, 2, ucv_string_new(prefix), ucv_string_new(".json")));

	assert_null(vm_call(vm, uc_ubbf_tmpfile_name, 1, ucv_string_new("missing-dir/x")));
	assert_null(vm_call(vm, uc_ubbf_tmpfile_name, 1, ucv_int64_new(1)));
	assert_null(vm_call(vm, uc_ubbf_tmpfile_name, 0));
}

static void
write_expect(uc_vm_t *vm, const char *path, uc_value_t *content, uc_value_t *mode, bool expected)
{
	uc_value_t *res = vm_call(vm, uc_ubbf_write_file_atomic, 3,
				  path ? ucv_string_new(path) : NULL, content, mode);

	assert_int_equal(ucv_type(res), UC_BOOLEAN);
	assert_int_equal(ucv_boolean_get(res), expected);
	ucv_put(res);
}

static void
test_write_file_atomic(void **state)
{
	const char *path = "/tmp/atomic/file";
	uc_vm_t *vm = *state;
	mode_t old_umask;
	struct stat st;
	ino_t ino;

	assert_int_equal(mkdir("/tmp/atomic", 0755), 0);
	old_umask = umask(077);

	write_expect(vm, path, ucv_string_new("hello\n"), NULL, true);
	assert_string_equal(file_get(path), "hello\n");
	assert_int_equal(file_mode(path), 0644);
	assert_false(file_exists("/tmp/atomic/file.tmp"));
	assert_int_equal(stat(path, &st), 0);
	ino = st.st_ino;

	write_expect(vm, path, ucv_string_new("secret"), ucv_int64_new(0600), true);
	assert_string_equal(file_get(path), "secret");
	assert_int_equal(file_mode(path), 0600);
	assert_int_equal(stat(path, &st), 0);
	assert_int_not_equal(st.st_ino, ino);

	write_expect(vm, path, ucv_string_new("masked"), ucv_int64_new(010640), true);
	assert_int_equal(file_mode(path), 0640);

	write_expect(vm, path, ucv_string_new("default"), ucv_string_new("0600"), true);
	assert_int_equal(file_mode(path), 0644);

	file_put("/tmp/atomic/file.tmp", "stale leftover", 0666);
	write_expect(vm, path, ucv_string_new("fresh"), ucv_int64_new(0600), true);
	assert_string_equal(file_get(path), "fresh");
	assert_int_equal(file_mode(path), 0600);
	assert_false(file_exists("/tmp/atomic/file.tmp"));

	/* content that is neither a string nor null is refused, the file stays */
	write_expect(vm, path, ucv_int64_new(5), NULL, false);
	write_expect(vm, path, vm_json(vm, "{ }"), NULL, false);
	assert_string_equal(file_get(path), "fresh");

	write_expect(vm, path, NULL, NULL, true);
	assert_false(file_exists(path));
	write_expect(vm, path, NULL, NULL, true);

	file_put(path, "x", 0644);
	write_expect(vm, path, ucv_string_new(""), NULL, true);
	assert_false(file_exists(path));

	write_expect(vm, "/tmp/atomic/missing/file", ucv_string_new("x"), NULL, false);
	assert_false(file_exists("/tmp/atomic/missing"));
	write_expect(vm, "/tmp/atomic/missing/file", NULL, NULL, true);

	assert_int_equal(mkdir("/tmp/atomic/dir", 0755), 0);
	assert_int_equal(mkdir("/tmp/atomic/dir/sub", 0755), 0);
	write_expect(vm, "/tmp/atomic/dir", ucv_string_new("x"), NULL, false);
	assert_false(file_exists("/tmp/atomic/dir.tmp"));
	write_expect(vm, "/tmp/atomic/dir", NULL, NULL, false);
	assert_true(file_exists("/tmp/atomic/dir/sub"));

	write_expect(vm, NULL, ucv_string_new("x"), NULL, false);
	write_expect(vm, NULL, NULL, NULL, false);

	umask(old_umask);
}

static void
test_file_write_atomic(void **state)
{
	char long_path[600];
	int cwd;

	(void)state;

	assert_true(file_write_atomic("/tmp/atomic-nul", "a\0b", 3, 0600));
	assert_int_equal(memcmp(file_get("/tmp/atomic-nul"), "a\0b", 4), 0);
	assert_int_equal(file_mode("/tmp/atomic-nul"), 0600);

	assert_true(file_write_atomic("/tmp/atomic-nul", "ignored", 0, 0600));
	assert_false(file_exists("/tmp/atomic-nul"));

	cwd = open(".", O_RDONLY | O_DIRECTORY);
	assert_true(cwd >= 0);
	assert_int_equal(chdir("/tmp"), 0);
	assert_true(file_write_atomic("atomic-rel", "rel", 3, 0644));
	assert_int_equal(fchdir(cwd), 0);
	close(cwd);
	assert_string_equal(file_get("/tmp/atomic-rel"), "rel");

	snprintf(long_path, sizeof(long_path), "/tmp/%0503d", 0);
	assert_int_equal(strlen(long_path), 508);
	assert_false(file_write_atomic(long_path, "x", 1, 0644));
}

static void
test_file_write_atomic_full(void **state)
{
	static char big[65536];

	(void)state;

	assert_int_equal(mkdir("/tmp/atomic-small", 0755), 0);
	if (mount("none", "/tmp/atomic-small", "tmpfs", 0, "size=4k") != 0)
		skip();

	memset(big, 'x', sizeof(big));
	assert_false(file_write_atomic("/tmp/atomic-small/f", big, sizeof(big), 0644));
	assert_false(file_exists("/tmp/atomic-small/f.tmp"));
	assert_false(file_exists("/tmp/atomic-small/f"));

	assert_int_equal(umount("/tmp/atomic-small"), 0);
}

int
main(void)
{
	const struct CMUnitTest tests[] = {
		cmocka_unit_test(test_tmpfile_name),
		cmocka_unit_test(test_write_file_atomic),
		cmocka_unit_test(test_file_write_atomic),
		cmocka_unit_test(test_file_write_atomic_full),
	};

	return cmocka_run_group_tests(tests, vm_setup, vm_teardown);
}
