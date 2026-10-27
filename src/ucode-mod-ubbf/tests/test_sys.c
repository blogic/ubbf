/* SPDX-License-Identifier: GPL-2.0-only */

/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

/*
 * sys.c: arch_get(), apk_version() and statvfs_info().
 */

#include "harness.h"
#include "ubbf.h"

#include <ctype.h>
#include <fcntl.h>
#include <limits.h>
#include <unistd.h>
#include <sys/mount.h>
#include <sys/stat.h>

#define APK_DB	"/lib/apk/db/installed"

static void
file_fill(const char *path, size_t len)
{
	char buf[4096];
	int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0644);

	assert_true(fd >= 0);
	memset(buf, 'x', sizeof(buf));

	while (len > 0) {
		size_t n = len < sizeof(buf) ? len : sizeof(buf);

		assert_int_equal(write(fd, buf, n), (ssize_t)n);
		len -= n;
	}

	close(fd);
}

static void
test_arch_get(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *res = vm_call(vm, uc_ubbf_arch_get, 1, ucv_string_new("ignored"));
	const char *arch;

	assert_int_equal(ucv_type(res), UC_STRING);
	arch = ucv_string_get(res);
	assert_true(*arch);

	for (const char *p = arch; *p; p++)
		assert_false(isspace((unsigned char)*p));

	ucv_put(res);
}

static void
apk_expect(uc_vm_t *vm, uc_value_t *name, const char *expected)
{
	uc_value_t *res = vm_call(vm, uc_ubbf_apk_version, 1, name);

	if (expected)
		assert_string_equal(ucv_string_get(res), expected);
	else
		assert_null(res);

	ucv_put(res);
}

static void
test_apk_version_no_db(void **state)
{
	uc_vm_t *vm = *state;
	struct stat st;

	apk_expect(vm, ucv_int64_new(1), NULL);
	apk_expect(vm, NULL, NULL);
	apk_expect(vm, ucv_string_new(""), NULL);

	if (stat(APK_DB, &st) == 0)
		skip();

	apk_expect(vm, ucv_string_new("busybox"), NULL);
}

static const char apk_db[] =
	"C:Q1abc=\n"
	"P:busybox\n"
	"V:1.36.1-r2\n"
	"A:x86_64\n"
	"\n"
	"V:0.1-r0\n"
	"P:late\n"
	"A:x86_64\n"
	"\n"
	"P:ucode\n"
	"A:x86_64\n"
	"T:the interpreter\n"
	"V:2026.10.18-r1\n"
	"\n"
	"P:noversion\n"
	"A:x86_64\n"
	"\n"
	"P:other\n"
	"V:2.0-r0\n"
	"\n"
	"P:last\n"
	"V:9.9-r0";

/*
 * /lib/apk does not exist on a host other than OpenWrt and the tree below
 * it is not writable, so an overlay on the directory /lib resolves to adds
 * the database in this mount namespace only.
 */
static bool
apk_db_mount(void)
{
	char lib[PATH_MAX], opts[PATH_MAX * 2 + 64];
	FILE *fp;

	if (!realpath("/lib", lib))
		return false;

	if (mkdir("/tmp/apk-upper", 0755) || mkdir("/tmp/apk-work", 0755))
		return false;

	snprintf(opts, sizeof(opts), "lowerdir=%s,upperdir=/tmp/apk-upper,workdir=/tmp/apk-work", lib);
	if (mount("overlay", lib, "overlay", 0, opts) != 0)
		return false;

	mkdir("/lib/apk", 0755);
	mkdir("/lib/apk/db", 0755);
	fp = fopen(APK_DB, "w");
	if (!fp) {
		umount(lib);
		return false;
	}

	fputs(apk_db, fp);
	fclose(fp);

	return true;
}

static void
test_apk_version(void **state)
{
	uc_vm_t *vm = *state;
	char name[600], lib[PATH_MAX];

	if (!apk_db_mount())
		skip();

	apk_expect(vm, ucv_string_new("busybox"), "1.36.1-r2");
	apk_expect(vm, ucv_string_new("ucode"), "2026.10.18-r1");
	apk_expect(vm, ucv_string_new("other"), "2.0-r0");
	apk_expect(vm, ucv_string_new("last"), "9.9-r0");
	apk_expect(vm, ucv_string_new("late"), NULL);
	apk_expect(vm, ucv_string_new("noversion"), NULL);
	apk_expect(vm, ucv_string_new("busy"), NULL);
	apk_expect(vm, ucv_string_new("busybox2"), NULL);
	apk_expect(vm, ucv_string_new("x86_64"), NULL);
	apk_expect(vm, ucv_string_new("missing"), NULL);
	apk_expect(vm, ucv_string_new(""), NULL);

	memset(name, 'n', sizeof(name) - 1);
	name[sizeof(name) - 1] = '\0';
	apk_expect(vm, ucv_string_new(name), NULL);

	assert_non_null(realpath("/lib", lib));
	assert_int_equal(umount(lib), 0);
}

static void
statvfs_expect(uc_vm_t *vm, const char *path, int64_t total, int64_t free_kib)
{
	uc_value_t *res = vm_call(vm, uc_ubbf_statvfs_info, 1, ucv_string_new(path));
	char buf[128];

	snprintf(buf, sizeof(buf),
		 "{ \"total_kib\": %lld, \"free_kib\": %lld, \"avail_kib\": %lld }",
		 (long long)total, (long long)free_kib, (long long)free_kib);
	assert_json_equal(vm, res, buf);
	ucv_put(res);
}

static void
test_statvfs_info(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *res;

	res = vm_call(vm, uc_ubbf_statvfs_info, 1, ucv_string_new("/"));
	assert_int_equal(ucv_type(res), UC_OBJECT);
	assert_int_equal(ucv_type(ucv_object_get(res, "total_kib", NULL)), UC_INTEGER);
	assert_int_equal(ucv_type(ucv_object_get(res, "free_kib", NULL)), UC_INTEGER);
	assert_int_equal(ucv_type(ucv_object_get(res, "avail_kib", NULL)), UC_INTEGER);
	ucv_put(res);

	assert_null(vm_call(vm, uc_ubbf_statvfs_info, 1, ucv_string_new("/tmp/statvfs-missing")));
	assert_null(vm_call(vm, uc_ubbf_statvfs_info, 1, ucv_int64_new(1)));
	assert_null(vm_call(vm, uc_ubbf_statvfs_info, 0));

	assert_int_equal(mkdir("/tmp/statvfs", 0755), 0);
	if (mount("none", "/tmp/statvfs", "tmpfs", 0, "size=1m") != 0)
		skip();

	statvfs_expect(vm, "/tmp/statvfs", 1024, 1024);
	file_fill("/tmp/statvfs/data", 100 * 1024);
	statvfs_expect(vm, "/tmp/statvfs/data", 1024, 924);

	assert_int_equal(umount("/tmp/statvfs"), 0);
}

int
main(void)
{
	const struct CMUnitTest tests[] = {
		cmocka_unit_test(test_arch_get),
		cmocka_unit_test(test_apk_version_no_db),
		cmocka_unit_test(test_apk_version),
		cmocka_unit_test(test_statvfs_info),
	};

	return cmocka_run_group_tests(tests, vm_setup, vm_teardown);
}
