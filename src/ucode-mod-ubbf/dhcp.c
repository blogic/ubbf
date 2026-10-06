/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

#include "ubbf.h"
#include <ctype.h>

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
	char *buf = NULL, *line;
	size_t size = 0;
	FILE *fp;

	/* Streamed line by line, so that a pool of any size is read in full;
	 * getline() because a client id can be hundreds of bytes. */
	fp = fopen("/tmp/dhcp.leases", "r");
	if (!fp)
		return arr;

	while (getline(&buf, &size, fp) > 0) {
		char *expiry_s, *mac_s, *ip_s, *host_s, *cid_s;
		char *p, *fsave;
		uc_value_t *o;

		line = buf;
		while (*line == ' ' || *line == '\t')
			line++;
		if (!*line || *line == '\n')
			continue;

		p = strtok_r(line, " \t\n", &fsave);
		if (!p) continue;
		expiry_s = p;
		mac_s = strtok_r(NULL, " \t\n", &fsave);
		ip_s = strtok_r(NULL, " \t\n", &fsave);
		host_s = strtok_r(NULL, " \t\n", &fsave);
		cid_s = strtok_r(NULL, " \t\n", &fsave);

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

	free(buf);
	fclose(fp);
	return arr;
}
