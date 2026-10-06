/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

#include "ubbf.h"
#include <ctype.h>
#include <dirent.h>
#include <unistd.h>

#define USB_SYSFS "/sys/bus/usb/devices"

extern char *sysfs_read_file(const char *path);

/**
 * Comparator: lexical order, but with `usb<N>` always coming before
 * non-host entries so the enumerate result keeps the order callers
 * historically expect.
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
uc_value_t *
uc_ubbf_usb_enumerate(uc_vm_t *vm, size_t nargs)
{
	DIR *d;
	struct dirent *ent;
	uc_value_t *out = ucv_object_new(vm);
	uc_value_t *hosts = ucv_array_new(vm);
	uc_value_t *devices = ucv_array_new(vm);
	uc_value_t *interfaces = ucv_array_new(vm);
	const char **host_names = NULL, **dev_names = NULL, **iface_names = NULL;
	size_t hn = 0, dn = 0, in_ = 0;
	size_t hcap = 0, dcap = 0, icap = 0;

	ucv_object_add(out, "hosts", hosts);
	ucv_object_add(out, "devices", devices);
	ucv_object_add(out, "interfaces", interfaces);

	d = opendir(USB_SYSFS);
	if (!d)
		return out;

	while ((ent = readdir(d))) {
		const char *name = ent->d_name;
		if (name[0] == '.')
			continue;

		const char ***target;
		size_t *cnt, *cap;

		if (is_host_name(name))      { target = &host_names; cnt = &hn; cap = &hcap; }
		else if (is_interface_name(name)) { target = &iface_names; cnt = &in_; cap = &icap; }
		else if (is_device_name(name))    { target = &dev_names; cnt = &dn; cap = &dcap; }
		else continue;

		if (*cnt == *cap) {
			*cap = *cap ? *cap * 2 : 16;
			*target = realloc(*target, *cap * sizeof(**target));
		}
		(*target)[(*cnt)++] = strdup(name);
	}
	closedir(d);

	if (host_names) qsort(host_names, hn, sizeof(*host_names), str_cmp);
	if (dev_names)  qsort(dev_names,  dn, sizeof(*dev_names),  str_cmp);
	if (iface_names) qsort(iface_names, in_, sizeof(*iface_names), str_cmp);

	for (size_t i = 0; i < hn; i++) {
		ucv_array_push(hosts, ucv_string_new(host_names[i]));
		free((void *)host_names[i]);
	}
	for (size_t i = 0; i < dn; i++) {
		ucv_array_push(devices, ucv_string_new(dev_names[i]));
		free((void *)dev_names[i]);
	}
	for (size_t i = 0; i < in_; i++) {
		ucv_array_push(interfaces, ucv_string_new(iface_names[i]));
		free((void *)iface_names[i]);
	}
	free(host_names);
	free(dev_names);
	free(iface_names);

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
 * ucode `host_devices_build` did per device. Returns null when the
 * device path is missing.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: device sysfs name)
 * @return       descriptor object, or null
 */
uc_value_t *
uc_ubbf_usb_device_info(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *name_val = uc_fn_arg(0);
	const char *name;
	char base[256];
	uc_value_t *o;

	if (ucv_type(name_val) != UC_STRING)
		return NULL;

	name = ucv_string_get(name_val);
	snprintf(base, sizeof(base), "%s/%s", USB_SYSFS, name);

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
 * fields are hex-decoded.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: interface sysfs name)
 * @return       descriptor object, or null
 */
uc_value_t *
uc_ubbf_usb_interface_info(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *name_val = uc_fn_arg(0);
	const char *name;
	char base[256];
	uc_value_t *o;

	if (ucv_type(name_val) != UC_STRING)
		return NULL;

	name = ucv_string_get(name_val);
	snprintf(base, sizeof(base), "%s/%s", USB_SYSFS, name);

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
 * reference.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (none expected)
 * @return       array of interface objects, possibly empty
 */
uc_value_t *
uc_ubbf_usb_net_interfaces(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *out = ucv_array_new(vm);
	DIR *d;
	struct dirent *ent;

	d = opendir(USB_SYSFS);
	if (!d)
		return out;

	while ((ent = readdir(d))) {
		const char *name = ent->d_name;
		if (name[0] == '.' || !is_interface_name(name))
			continue;

		char netdir[256];
		snprintf(netdir, sizeof(netdir), "%s/%s/net", USB_SYSFS, name);
		DIR *nd = opendir(netdir);
		if (!nd)
			continue;

		/* is_interface_name() guarantees a ':' within the first 63 bytes */
		char devname[64];
		size_t dl = strchr(name, ':') - name;
		memcpy(devname, name, dl);
		devname[dl] = '\0';

		struct dirent *nent;
		while ((nent = readdir(nd))) {
			const char *ifn = nent->d_name;
			if (ifn[0] == '.')
				continue;
			char path[256];
			snprintf(path, sizeof(path), "/sys/class/net/%s", ifn);

			uc_value_t *o = ucv_object_new(vm);
			ucv_object_add(o, "device", ucv_string_new(devname));
			ucv_object_add(o, "ifname", ucv_string_new(ifn));
			ucv_object_add(o, "path", ucv_string_new(path));
			ucv_array_push(out, o);
		}
		closedir(nd);
	}
	closedir(d);

	return out;
}
