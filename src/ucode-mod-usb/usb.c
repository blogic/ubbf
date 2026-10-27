/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

#include <ucode/module.h>

#include <ctype.h>
#include <dirent.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "util.h"

#define USB_SYSFS "/sys/bus/usb/devices"

/**
 * Comparator for qsort() over an array of strings: lexical order.
 */
static int
str_cmp(const void *a, const void *b)
{
	return strcmp(*(const char **)a, *(const char **)b);
}

/**
 * Tests whether `s` matches `usb<digits>$`.
 */
static int
is_host_name(const char *s)
{
	if (s[0] != 'u' || s[1] != 's' || s[2] != 'b' || !s[3])
		return 0;
	for (s += 3; *s; s++)
		if (!isdigit((unsigned char)*s))
			return 0;
	return 1;
}

/**
 * Tests whether `s` matches `<digits>-<digits>(\.<digits>)*$`.
 */
static int
is_device_name(const char *s)
{
	if (!isdigit((unsigned char)*s))
		return 0;
	while (isdigit((unsigned char)*s)) s++;
	if (*s != '-')
		return 0;
	s++;
	if (!isdigit((unsigned char)*s))
		return 0;
	while (*s) {
		if (isdigit((unsigned char)*s)) {
			s++;
			continue;
		}
		if (*s == '.') {
			s++;
			if (!isdigit((unsigned char)*s))
				return 0;
			continue;
		}
		return 0;
	}
	return 1;
}

/**
 * Tests whether `s` matches `<dev>:<conf>.<iface>$`.
 */
static int
is_interface_name(const char *s)
{
	const char *colon = strchr(s, ':');
	if (!colon)
		return 0;

	char head[64];
	size_t hl = colon - s;
	if (hl >= sizeof(head))
		return 0;
	memcpy(head, s, hl);
	head[hl] = '\0';
	if (!is_device_name(head))
		return 0;

	const char *p = colon + 1;
	if (!isdigit((unsigned char)*p))
		return 0;
	while (isdigit((unsigned char)*p)) p++;
	if (*p != '.')
		return 0;
	p++;
	if (!isdigit((unsigned char)*p))
		return 0;
	while (*p) {
		if (!isdigit((unsigned char)*p))
			return 0;
		p++;
	}
	return 1;
}

static int
is_usb_name(const char *s)
{
	return is_host_name(s) || is_device_name(s) || is_interface_name(s);
}

static int
is_any_name(const char *s)
{
	return 1;
}

/**
 * Lists the names in a directory that pass `keep`, sorted lexically, so
 * that the enumerations built from them are stable. Returns NULL with a
 * count of 0 when the directory cannot be read; free the list with
 * names_free().
 */
static char **
dir_names_sorted(const char *path, int (*keep)(const char *), size_t *count)
{
	DIR *d = opendir(path);
	struct dirent *ent;
	char **names = NULL;
	size_t cap = 0;

	*count = 0;
	if (!d)
		return NULL;

	while ((ent = readdir(d))) {
		if (ent->d_name[0] == '.' || !keep(ent->d_name))
			continue;

		if (*count == cap) {
			cap = cap ? cap * 2 : 16;
			names = xrealloc(names, cap * sizeof(*names));
		}
		names[(*count)++] = xstrdup(ent->d_name);
	}
	closedir(d);

	if (names)
		qsort(names, *count, sizeof(*names), str_cmp);

	return names;
}

static void
names_free(char **names, size_t count)
{
	for (size_t i = 0; i < count; i++)
		free(names[i]);
	free(names);
}

/**
 * Lists `/sys/bus/usb/devices` and bins entries into hosts, devices,
 * and interface aliases.
 *
 * Returns `{ hosts: [], devices: [], interfaces: [] }`, each sorted
 * lexically so downstream enumerations are stable.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (none expected)
 * @return       enumeration object
 */
static uc_value_t *
uc_ubbf_usb_enumerate(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *out = ucv_object_new(vm);
	uc_value_t *hosts = ucv_array_new(vm);
	uc_value_t *devices = ucv_array_new(vm);
	uc_value_t *interfaces = ucv_array_new(vm);
	size_t count;
	char **names = dir_names_sorted(USB_SYSFS, is_usb_name, &count);

	ucv_object_add(out, "hosts", hosts);
	ucv_object_add(out, "devices", devices);
	ucv_object_add(out, "interfaces", interfaces);

	for (size_t i = 0; i < count; i++) {
		uc_value_t *target = devices;

		if (is_host_name(names[i]))
			target = hosts;
		else if (is_interface_name(names[i]))
			target = interfaces;

		ucv_array_push(target, ucv_string_new(names[i]));
	}
	names_free(names, count);

	return out;
}

/**
 * Reads a sysfs file under `<base>/<rel>` and returns a trimmed copy.
 * Returns NULL on read failure; caller must free.
 */
static char *
read_under(const char *base, const char *rel)
{
	char path[512];
	snprintf(path, sizeof(path), "%s/%s", base, rel);
	return sysfs_read_file(path);
}

/**
 * Reads a sysfs file as a base-10 integer, returning the supplied
 * default on read or parse failure.
 */
static long long
read_int(const char *base, const char *rel, long long def)
{
	char *content = read_under(base, rel);
	long long v = def;
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
 * Reads a sysfs file as a base-16 integer, returning the supplied
 * default on read or parse failure.
 */
static long long
read_hex(const char *base, const char *rel, long long def)
{
	char *content = read_under(base, rel);
	long long v = def;
	if (content) {
		char *endp;
		long long parsed = strtoll(content, &endp, 16);
		if (*endp == '\0')
			v = parsed;
		free(content);
	}
	return v;
}

/**
 * Adds a string field; replaces a NULL with the empty string and
 * always free()s the input buffer.
 */
static void
add_str_take(uc_value_t *o, const char *key, char *val)
{
	ucv_object_add(o, key, ucv_string_new(val ? val : ""));
	free(val);
}

/**
 * Reads the per-device USB descriptor sysfs files for `<USB_SYSFS>/<dev>`.
 *
 * Returns a single object containing the raw values:
 *   - integers: bConfigurationValue, devnum, bcdDevice, maxchild,
 *               bNumConfigurations
 *   - hex integers: bDeviceClass, bDeviceSubClass, bDeviceProtocol,
 *                   idVendor, idProduct
 *   - strings: version, manufacturer, product, serial, speed,
 *              power_runtime_status, power_control, bDeviceClass_str
 *
 * One call replaces ~15 separate `readfile_*` round-trips that the
 * ucode `host_devices_build` did per device. Returns null for a name
 * that is not a host or device name, and when the device path is
 * missing, for example after an unplug.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: device sysfs name)
 * @return       descriptor object, or null
 */
static uc_value_t *
uc_ubbf_usb_device_info(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *name_val = uc_fn_arg(0);
	const char *name;
	char base[256];
	uc_value_t *o;

	if (ucv_type(name_val) != UC_STRING)
		return NULL;

	name = ucv_string_get(name_val);
	if (!is_host_name(name) && !is_device_name(name))
		return NULL;

	snprintf(base, sizeof(base), "%s/%s", USB_SYSFS, name);
	if (access(base, F_OK) != 0)
		return NULL;

	o = ucv_object_new(vm);

	ucv_object_add(o, "bConfigurationValue", ucv_int64_new(read_int(base, "bConfigurationValue", 0)));
	ucv_object_add(o, "devnum",              ucv_int64_new(read_int(base, "devnum", 0)));
	ucv_object_add(o, "bcdDevice",           ucv_int64_new(read_hex(base, "bcdDevice", 0)));
	ucv_object_add(o, "maxchild",            ucv_int64_new(read_int(base, "maxchild", 0)));
	ucv_object_add(o, "bNumConfigurations",  ucv_int64_new(read_int(base, "bNumConfigurations", 0)));

	ucv_object_add(o, "bmAttributes",        ucv_int64_new(read_hex(base, "bmAttributes", 0)));
	ucv_object_add(o, "bDeviceClass",        ucv_int64_new(read_hex(base, "bDeviceClass", 0)));
	ucv_object_add(o, "bDeviceSubClass",     ucv_int64_new(read_hex(base, "bDeviceSubClass", 0)));
	ucv_object_add(o, "bDeviceProtocol",     ucv_int64_new(read_hex(base, "bDeviceProtocol", 0)));
	ucv_object_add(o, "idVendor",            ucv_int64_new(read_hex(base, "idVendor", 0)));
	ucv_object_add(o, "idProduct",           ucv_int64_new(read_hex(base, "idProduct", 0)));

	add_str_take(o, "version",      read_under(base, "version"));
	add_str_take(o, "manufacturer", read_under(base, "manufacturer"));
	add_str_take(o, "product",      read_under(base, "product"));
	add_str_take(o, "serial",       read_under(base, "serial"));
	add_str_take(o, "speed",        read_under(base, "speed"));
	add_str_take(o, "power_runtime_status", read_under(base, "power/runtime_status"));
	add_str_take(o, "power_control",        read_under(base, "power/control"));
	add_str_take(o, "bDeviceClass_str",     read_under(base, "bDeviceClass"));

	return o;
}

/**
 * Reads the per-interface USB descriptor sysfs files for an interface
 * alias such as `1-2:1.0`. Returns `{ bInterfaceNumber, bInterfaceClass,
 * bInterfaceSubClass, bInterfaceProtocol }` (all integers). The class
 * fields are hex-decoded. Returns null for a name that is not an
 * interface name, and when the interface path is missing.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: interface sysfs name)
 * @return       descriptor object, or null
 */
static uc_value_t *
uc_ubbf_usb_interface_info(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *name_val = uc_fn_arg(0);
	const char *name;
	char base[256];
	uc_value_t *o;

	if (ucv_type(name_val) != UC_STRING)
		return NULL;

	name = ucv_string_get(name_val);
	if (!is_interface_name(name))
		return NULL;

	snprintf(base, sizeof(base), "%s/%s", USB_SYSFS, name);
	if (access(base, F_OK) != 0)
		return NULL;

	o = ucv_object_new(vm);
	ucv_object_add(o, "bInterfaceNumber",
		       ucv_int64_new(read_int(base, "bInterfaceNumber", 0)));
	ucv_object_add(o, "bInterfaceClass",
		       ucv_int64_new(read_hex(base, "bInterfaceClass", 0)));
	ucv_object_add(o, "bInterfaceSubClass",
		       ucv_int64_new(read_hex(base, "bInterfaceSubClass", 0)));
	ucv_object_add(o, "bInterfaceProtocol",
		       ucv_int64_new(read_hex(base, "bInterfaceProtocol", 0)));

	return o;
}

/**
 * Walks every USB interface alias and lists the netdev names exposed
 * under its `net/` directory. The kernel parents USB netdevs to the
 * interface (`1-2:1.0/net/eth0`), never to the device dir.
 *
 * Returns an array of `{ device, ifname, path }` objects, where
 * `device` is the sysfs name of the parent USB device, `ifname` is the
 * netdev name, and `path` is the standard `/sys/class/net/<ifname>`
 * reference. The entries are sorted by interface alias, then by netdev
 * name.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (none expected)
 * @return       array of interface objects, possibly empty
 */
static uc_value_t *
uc_ubbf_usb_net_interfaces(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *out = ucv_array_new(vm);
	size_t alias_count;
	char **aliases = dir_names_sorted(USB_SYSFS, is_interface_name, &alias_count);

	for (size_t i = 0; i < alias_count; i++) {
		const char *name = aliases[i];
		char netdir[512], devname[64], path[512];
		size_t netdev_count;
		char **netdevs;

		snprintf(netdir, sizeof(netdir), "%s/%s/net", USB_SYSFS, name);
		netdevs = dir_names_sorted(netdir, is_any_name, &netdev_count);

		/* is_interface_name() guarantees a ':' within the first 63 bytes */
		size_t dl = strchr(name, ':') - name;
		memcpy(devname, name, dl);
		devname[dl] = '\0';

		for (size_t j = 0; j < netdev_count; j++) {
			uc_value_t *o = ucv_object_new(vm);

			snprintf(path, sizeof(path), "/sys/class/net/%s", netdevs[j]);
			ucv_object_add(o, "device", ucv_string_new(devname));
			ucv_object_add(o, "ifname", ucv_string_new(netdevs[j]));
			ucv_object_add(o, "path", ucv_string_new(path));
			ucv_array_push(out, o);
		}
		names_free(netdevs, netdev_count);
	}
	names_free(aliases, alias_count);

	return out;
}

static const uc_function_list_t usb_fns[] = {
	{ "enumerate",          uc_ubbf_usb_enumerate },
	{ "device_info",        uc_ubbf_usb_device_info },
	{ "interface_info",     uc_ubbf_usb_interface_info },
	{ "net_interfaces",     uc_ubbf_usb_net_interfaces },
};

void
uc_module_init(uc_vm_t *vm, uc_value_t *scope)
{
	uc_function_list_register(scope, usb_fns);
}
