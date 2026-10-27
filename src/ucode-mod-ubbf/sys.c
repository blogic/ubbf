/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

#include "ubbf.h"
#include "bindings.h"
#include <sys/utsname.h>
#include <sys/statvfs.h>
#include <fcntl.h>
#include <unistd.h>
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
 * Looks a package up in the APK database.
 *
 * Scans `/lib/apk/db/installed`, a concatenation of package records
 * separated by blank lines. Each record starts with `P:<package-name>`
 * and carries the version in a `V:<version>` line. This avoids the
 * fork+exec of `apk info`.
 *
 * @param name     package name
 * @param version  buffer for the version, or NULL
 * @param size     size of `version`
 * @return         true when the package is installed
 */
static bool
apk_package_find(const char *name, char *version, size_t size)
{
	size_t nlen = strlen(name);
	bool found = false;
	char line[512];
	FILE *fp;

	if (nlen == 0 || nlen > sizeof(line) - 4)
		return false;

	fp = fopen("/lib/apk/db/installed", "r");
	if (!fp)
		return false;

	while (fgets(line, sizeof(line), fp)) {
		line[strcspn(line, "\n")] = '\0';

		if (found && line[0] == '\0')
			break;

		if (found && version && line[0] == 'V' && line[1] == ':') {
			snprintf(version, size, "%s", line + 2);
			break;
		}

		if (!found && line[0] == 'P' && line[1] == ':' &&
		    strcmp(line + 2, name) == 0)
			found = true;
	}

	fclose(fp);
	return found;
}

/**
 * Returns the version of an installed APK package.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: package name)
 * @return       version string such as `8.2.0-r1`, or null when the
 *               package is not installed or its record has no version
 */
uc_value_t *
uc_ubbf_apk_version(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *name_val = uc_fn_arg(0);
	char version[128] = "";

	if (ucv_type(name_val) != UC_STRING)
		return NULL;

	if (!apk_package_find(ucv_string_get(name_val), version, sizeof(version)) ||
	    version[0] == '\0')
		return NULL;

	return ucv_string_new(version);
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

#define DEVICEINFO_PATH	"/etc/usp/deviceinfo.json"
#define DEVICEINFO_REG	"ubbf.deviceinfo"

/**
 * Returns the device identity of /etc/usp/deviceinfo.json
 * (ManufacturerOUI, SerialNumber and others). The file is read once per
 * VM; a missing or invalid file gives an empty object.
 *
 * @param vm  ucode VM context
 * @return    the device info object (borrowed), shared by all callers
 */
uc_value_t *
deviceinfo_value(uc_vm_t *vm)
{
	uc_value_t *info = uc_vm_registry_get(vm, DEVICEINFO_REG);

	if (!info) {
		info = json_file_load(vm, DEVICEINFO_PATH);
		if (ucv_type(info) != UC_OBJECT) {
			ucv_put(info);
			info = ucv_object_new(vm);
		}

		uc_vm_registry_set(vm, DEVICEINFO_REG, info);
	}

	return info;
}

/**
 * ucode: `deviceinfo_get()`, see deviceinfo_value().
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (none expected)
 * @return       device info object
 */
uc_value_t *
uc_ubbf_deviceinfo_get(uc_vm_t *vm, size_t nargs)
{
	return ucv_get(deviceinfo_value(vm));
}
