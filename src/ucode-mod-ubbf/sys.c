/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

#include "ubbf.h"
#include <sys/utsname.h>
#include <sys/statvfs.h>
#include <fcntl.h>
#include <unistd.h>
#include <ftw.h>
#include <stdint.h>

/**
 * Returns the kernel machine identifier (`uname -m`).
 *
 * Replaces the historical `popen("uname -m")` path in Processor.uc.
 * Uses `uname(2)` directly; returns `"Unknown"` on syscall failure.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (none expected)
 * @return       architecture string
 */
uc_value_t *
uc_ubbf_arch_get(uc_vm_t *vm, size_t nargs)
{
	struct utsname u;

	if (uname(&u) != 0)
		return ucv_string_new("Unknown");

	return ucv_string_new(u.machine[0] ? u.machine : "Unknown");
}

/**
 * Tests whether a named APK package is installed.
 *
 * Scans `/lib/apk/db/installed` for a matching `P:<name>\n` line. That
 * file is a concatenation of package records separated by blank lines,
 * with each record starting with `P:<package-name>`. This avoids the
 * fork+exec of `apk info -e <name>`.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: package name)
 * @return       boolean indicating installation state
 */
uc_value_t *
uc_ubbf_apk_installed(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *name_val = uc_fn_arg(0);
	const char *name;
	size_t nlen;
	FILE *fp;
	char line[512];

	if (ucv_type(name_val) != UC_STRING)
		return ucv_boolean_new(false);

	name = ucv_string_get(name_val);
	nlen = strlen(name);
	if (nlen == 0 || nlen > sizeof(line) - 4)
		return ucv_boolean_new(false);

	fp = fopen("/lib/apk/db/installed", "r");
	if (!fp)
		return ucv_boolean_new(false);

	while (fgets(line, sizeof(line), fp)) {
		if (line[0] != 'P' || line[1] != ':')
			continue;
		if (strncmp(line + 2, name, nlen) == 0 &&
		    (line[2 + nlen] == '\n' || line[2 + nlen] == '\0')) {
			fclose(fp);
			return ucv_boolean_new(true);
		}
	}

	fclose(fp);
	return ucv_boolean_new(false);
}

/**
 * Returns a snapshot of the filesystem hosting `path`.
 *
 * Calls `statvfs(2)` and returns an object with `total_kib`, `free_kib`,
 * and `avail_kib` (blocks scaled to KiB). `free_kib` counts all free
 * blocks; `avail_kib` counts those available to non-privileged processes.
 * Returns null on syscall failure or bad input.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: path)
 * @return       object, or null
 */
uc_value_t *
uc_ubbf_statvfs_info(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *path_val = uc_fn_arg(0);
	struct statvfs st;
	uc_value_t *obj;
	uint64_t blk;

	if (ucv_type(path_val) != UC_STRING)
		return NULL;

	if (statvfs(ucv_string_get(path_val), &st) != 0)
		return NULL;

	blk = st.f_frsize ? st.f_frsize : st.f_bsize;

	obj = ucv_object_new(vm);
	ucv_object_add(obj, "total_kib",
		       ucv_int64_new((int64_t)(st.f_blocks * blk / 1024)));
	ucv_object_add(obj, "free_kib",
		       ucv_int64_new((int64_t)(st.f_bfree * blk / 1024)));
	ucv_object_add(obj, "avail_kib",
		       ucv_int64_new((int64_t)(st.f_bavail * blk / 1024)));

	return obj;
}

static uint64_t du_total_bytes;

static int
du_walk_cb(const char *fpath, const struct stat *sb, int typeflag, struct FTW *ftwbuf)
{
	(void)fpath;
	(void)ftwbuf;

	if (typeflag == FTW_F || typeflag == FTW_D)
		du_total_bytes += (uint64_t)sb->st_blocks * 512;

	return 0;
}

/**
 * Returns the total disk usage of a path tree, in KiB.
 *
 * Uses `nftw(3)` with `FTW_PHYS` so symlinks are not followed; sums
 * `stat.st_blocks * 512` per entry, matching the semantics of
 * `du -sk`. Returns -1 on error.
 *
 * The walker uses a process-global accumulator so this helper is not
 * re-entrant or thread-safe. That is acceptable for ucode, which runs
 * single-threaded.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: path)
 * @return       integer KiB, or -1 on error
 */
uc_value_t *
uc_ubbf_du_kib(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *path_val = uc_fn_arg(0);

	if (ucv_type(path_val) != UC_STRING)
		return ucv_int64_new(-1);

	du_total_bytes = 0;
	if (nftw(ucv_string_get(path_val), du_walk_cb, 16, FTW_PHYS) != 0)
		return ucv_int64_new(-1);

	return ucv_int64_new((int64_t)(du_total_bytes / 1024));
}
