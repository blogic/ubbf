/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

#include <ucode/module.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "util.h"

/**
 * Builds the path of one attribute file of an LED.
 *
 * @return false when the name could leave /sys/class/leds/ or the path
 *         does not fit
 */
static bool
led_path(char *out, size_t out_len, const char *name, const char *file)
{
	int n;

	if (!*name || strchr(name, '/') || !strcmp(name, ".") || !strcmp(name, ".."))
		return false;

	n = snprintf(out, out_len, "/sys/class/leds/%s/%s", name, file);

	return n > 0 && (size_t)n < out_len;
}

/**
 * Reads a sysfs integer attribute of an LED.
 *
 * @return false when the file is missing or does not hold an integer
 */
static bool
led_sysfs_int(const char *name, const char *file, int64_t *out)
{
	char path[256];
	char *content, *endp;
	bool ok;

	if (!led_path(path, sizeof(path), name, file))
		return false;

	content = sysfs_read_file(path);
	if (!content)
		return false;

	*out = strtoll(content, &endp, 10);
	ok = endp != content && *endp == '\0';
	free(content);

	return ok;
}

/**
 * Reports whether a kernel trigger drives the LED.
 *
 * The trigger file lists every trigger and brackets the active one, for
 * example `none [netdev] timer`.
 */
static bool
led_triggered(const char *name)
{
	char path[256];
	char *trigger, *open;
	bool active;

	if (!led_path(path, sizeof(path), name, "trigger"))
		return false;

	trigger = sysfs_read_file(path);
	if (!trigger)
		return false;

	open = strchr(trigger, '[');
	active = open && strncmp(open, "[none]", 6) != 0;
	free(trigger);

	return active;
}

/**
 * Builds the sysfs-derived fields of a TR-181 LED row from
 * `/sys/class/leds/<name>/`.
 *
 * `Status` is `Disabled` for an LED that is dark with no trigger, `InUse`
 * for one that is lit or that a trigger drives, and `Error` when its
 * brightness cannot be read. `Enable` is false for `Disabled` and
 * `Error`. The fields that come from the name (`Alias`, `Reason`, colour)
 * are left to the handler.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: LED name)
 * @return       TR-181 LED object, or null on a name that is not a
 *               plain directory name
 */
static uc_value_t *
uc_ubbf_led_read_info(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *name_val = uc_fn_arg(0);
	const char *name, *status;
	char path[256];
	int64_t brightness, max_brightness = 0;
	char buf[32];
	uc_value_t *obj;

	if (ucv_type(name_val) != UC_STRING)
		return NULL;

	name = ucv_string_get(name_val);
	if (!led_path(path, sizeof(path), name, "brightness"))
		return NULL;

	if (!led_sysfs_int(name, "brightness", &brightness))
		status = "Error";
	else if (brightness > 0 || led_triggered(name))
		status = "InUse";
	else
		status = "Disabled";

	led_sysfs_int(name, "max_brightness", &max_brightness);

	obj = ucv_object_new(vm);
	ucv_object_add(obj, "Enable",
		       ucv_string_new(strcmp(status, "InUse") ? "false" : "true"));
	ucv_object_add(obj, "Name", ucv_string_new(name));
	ucv_object_add(obj, "Status", ucv_string_new(status));
	ucv_object_add(obj, "CyclePeriodRepetitions", ucv_string_new("0"));
	ucv_object_add(obj, "Location", ucv_string_new(""));
	ucv_object_add(obj, "RelativeXPosition", ucv_string_new("0"));
	ucv_object_add(obj, "RelativeYPosition", ucv_string_new("0"));
	snprintf(buf, sizeof(buf), "%lld", (long long)max_brightness);
	ucv_object_add(obj, "MaxBrightness", ucv_string_new(buf));
	ucv_object_add(obj, "CycleElementNumberOfEntries", ucv_string_new("0"));

	return obj;
}

static const uc_function_list_t led_fns[] = {
	{ "read_info",          uc_ubbf_led_read_info },
};

void
uc_module_init(uc_vm_t *vm, uc_value_t *scope)
{
	uc_function_list_register(scope, led_fns);
}
