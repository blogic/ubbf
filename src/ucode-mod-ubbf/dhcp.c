/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

#include "ubbf.h"
#include <ctype.h>

extern char *sysfs_read_file(const char *path);

/**
 * Uppercase an ASCII string in place.
 */
static void
str_upper_inplace(char *s)
{
	for (; *s; s++)
		if (*s >= 'a' && *s <= 'z')
			*s -= 32;
}

/**
 * Parses an IPv4 dotted-quad to a 32-bit integer; returns 0 on failure.
 */
static int64_t
ipv4_to_int_str(const char *s)
{
	unsigned int a, b, c, d;
	if (sscanf(s, "%u.%u.%u.%u", &a, &b, &c, &d) != 4)
		return 0;
	return (int64_t)((a << 24) | (b << 16) | (c << 8) | d);
}

/**
 * Parses dnsmasq's `/tmp/dhcp.leases` file into an array of lease objects.
 *
 * The lease format is one entry per line with whitespace-separated fields
 * `expiry mac ip hostname [client_id]`. Hostname `*` is normalised to an
 * empty string. Each entry carries the parsed `ip_int` for downstream
 * range comparisons (matching the helper that ucode used to compute via
 * `ubbf.ip_to_int(lease.ip)`).
 *
 * Lines with fewer than four fields are skipped, so a partially-written
 * file yields the leases that are intact at parse time.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (none expected)
 * @return       array of lease objects, possibly empty
 */
uc_value_t *
uc_ubbf_leases_parse(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *arr = ucv_array_new(vm);
	char *content;
	char *line, *save;

	content = sysfs_read_file("/tmp/dhcp.leases");
	if (!content)
		return arr;

	/* sysfs_read_file uses an 8 KiB buffer; with ~50 bytes per lease that
	 * is roughly 160 leases. Beyond that the file is silently truncated;
	 * acceptable for the use case (TR-181 enumeration of active leases). */

	for (line = strtok_r(content, "\n", &save); line;
	     line = strtok_r(NULL, "\n", &save)) {
		char *expiry_s, *mac_s, *ip_s, *host_s, *cid_s;
		char *p, *fsave;
		uc_value_t *o;

		while (*line == ' ' || *line == '\t')
			line++;
		if (!*line)
			continue;

		p = strtok_r(line, " \t", &fsave);
		if (!p) continue;
		expiry_s = p;
		mac_s = strtok_r(NULL, " \t", &fsave);
		ip_s = strtok_r(NULL, " \t", &fsave);
		host_s = strtok_r(NULL, " \t", &fsave);
		cid_s = strtok_r(NULL, " \t", &fsave);

		if (!mac_s || !ip_s || !host_s)
			continue;

		if (host_s[0] == '*' && host_s[1] == '\0')
			host_s = "";

		/* Uppercase MAC in place; safe because the buffer slice is owned. */
		str_upper_inplace(mac_s);

		o = ucv_object_new(vm);
		ucv_object_add(o, "expiry", ucv_int64_new(strtoll(expiry_s, NULL, 10)));
		ucv_object_add(o, "mac", ucv_string_new(mac_s));
		ucv_object_add(o, "ip", ucv_string_new(ip_s));
		ucv_object_add(o, "hostname", ucv_string_new(host_s));
		ucv_object_add(o, "client_id", ucv_string_new(cid_s ? cid_s : ""));
		ucv_object_add(o, "ip_int", ucv_int64_new(ipv4_to_int_str(ip_s)));

		ucv_array_push(arr, o);
	}

	free(content);
	return arr;
}
