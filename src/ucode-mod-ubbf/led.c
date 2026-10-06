/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

#include "ubbf.h"

extern char *sysfs_read_file(const char *path);

/**
 * Extracts the colour component from a Linux LED name.
 *
 * The Linux LED naming convention is `<device>:<color>:<function>`. The
 * colour is therefore the second-to-last colon-separated segment.
 * Returns an empty string when the name has fewer than two segments.
 */
static const char *
led_color_from_name(const char *name, char *out, size_t out_len)
{
	const char *last = strrchr(name, ':');
	const char *prev;

	if (!last)
		return "";

	prev = last - 1;
	while (prev > name && *prev != ':')
		prev--;

	if (*prev == ':')
		prev++;

	size_t n = last - prev;
	if (n >= out_len)
		n = out_len - 1;
	memcpy(out, prev, n);
	out[n] = '\0';
	return out;
}

/**
 * Reads a sysfs integer value, returning the supplied default on failure.
 */
static int64_t
led_sysfs_int(const char *path, int64_t def)
{
	char *content = sysfs_read_file(path);
	int64_t v = def;
	if (content) {
		char *endp;
		long long parsed = strtoll(content, &endp, 10);
		if (*endp == '\0')
			v = parsed;
		free(content);
	}
	return v;
}

/**
 * Builds a TR-181 LED row from `/sys/class/leds/<name>/`.
 *
 * Reads `brightness`, `max_brightness`, and `trigger` in one call,
 * derives the colour from the LED name, and emits the standard TR-181
 * fields. Replaces the three separate `ubbf.readfile_*` calls plus the
 * regex/split that used to live in `tr181/LEDs.uc:led_to_object`.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: LED name)
 * @return       TR-181 LED object, or null on bad input
 */
uc_value_t *
uc_ubbf_led_read_info(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *name_val = uc_fn_arg(0);
	const char *name;
	char path[256];
	int64_t brightness, max_brightness;
	char *trigger;
	char reason[64] = "none";
	char color[32];
	char buf[32];
	uc_value_t *obj;

	if (ucv_type(name_val) != UC_STRING)
		return NULL;

	name = ucv_string_get(name_val);

	snprintf(path, sizeof(path), "/sys/class/leds/%s/brightness", name);
	brightness = led_sysfs_int(path, 0);

	snprintf(path, sizeof(path), "/sys/class/leds/%s/max_brightness", name);
	max_brightness = led_sysfs_int(path, 255);

	snprintf(path, sizeof(path), "/sys/class/leds/%s/trigger", name);
	trigger = sysfs_read_file(path);
	if (trigger) {
		char *open = strchr(trigger, '[');
		char *close = open ? strchr(open + 1, ']') : NULL;
		if (open && close) {
			size_t n = close - open - 1;
			if (n >= sizeof(reason)) n = sizeof(reason) - 1;
			memcpy(reason, open + 1, n);
			reason[n] = '\0';
		}
		free(trigger);
	}

	led_color_from_name(name, color, sizeof(color));

	obj = ucv_object_new(vm);
	ucv_object_add(obj, "Enable", ucv_string_new("true"));
	ucv_object_add(obj, "Name", ucv_string_new(name));
	ucv_object_add(obj, "Status",
		       ucv_string_new(brightness > 0 ? "On" : "Off"));
	ucv_object_add(obj, "Reason", ucv_string_new(reason));
	ucv_object_add(obj, "CyclePeriodRepetitions", ucv_string_new("0"));
	ucv_object_add(obj, "Location", ucv_string_new(""));
	ucv_object_add(obj, "RelativeXPosition", ucv_string_new("0"));
	ucv_object_add(obj, "RelativeYPosition", ucv_string_new("0"));
	snprintf(buf, sizeof(buf), "%lld", (long long)max_brightness);
	ucv_object_add(obj, "MaxBrightness", ucv_string_new(buf));
	ucv_object_add(obj, "CurrentColor", ucv_string_new(color));
	ucv_object_add(obj, "CycleElementNumberOfEntries", ucv_string_new("0"));

	return obj;
}
