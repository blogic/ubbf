/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

#include <ucode/module.h>

#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <arpa/inet.h>
#include <net/if.h>

#define MR_VIFS_MAX 32

/**
 * Reads the netdev names of the multicast routing vifs.
 *
 * `/proc/net/ip_mr_vif` and `/proc/net/ip6_mr_vif` list one vif per line
 * as `<index> <name> ...`.
 *
 * @param path   proc file of the family
 * @param names  table indexed by vif number, filled with the names
 */
static void
mr_vifs_read(const char *path, char names[MR_VIFS_MAX][IFNAMSIZ])
{
	char line[256], name[IFNAMSIZ];
	FILE *fp;
	int vif;

	fp = fopen(path, "r");
	if (!fp)
		return;

	while (fgets(line, sizeof(line), fp)) {
		if (sscanf(line, "%d %15s", &vif, name) != 2)
			continue;
		if (vif < 0 || vif >= MR_VIFS_MAX)
			continue;
		snprintf(names[vif], IFNAMSIZ, "%s", name);
	}

	fclose(fp);
}

/**
 * Converts an address from an ipmr proc file.
 *
 * The IPv4 file prints the network-order address as a host-order
 * integer, so storing the parsed integer gives back the original bytes
 * on either byte order. The IPv6 file prints the address in full colon
 * form.
 *
 * @param family  AF_INET or AF_INET6
 * @param text    address field of the line
 * @param out     buffer for the address in text form
 * @return        true when `text` is a valid address
 */
static bool
mr_addr_parse(int family, const char *text, char out[INET6_ADDRSTRLEN])
{
	struct in6_addr a6;
	uint32_t a4;
	char *end;

	if (family == AF_INET6)
		return inet_pton(AF_INET6, text, &a6) == 1 &&
		       inet_ntop(AF_INET6, &a6, out, INET6_ADDRSTRLEN) != NULL;

	a4 = (uint32_t)strtoul(text, &end, 16);
	if (*end != '\0' || end - text != 8)
		return false;

	return inet_ntop(AF_INET, &a4, out, INET6_ADDRSTRLEN) != NULL;
}

/**
 * Appends the entries of one multicast forwarding cache to an array.
 *
 * Lines read `Group Origin Iif Pkts Bytes Wrong vif:ttl...`; the vif
 * numbers are resolved through the vif file of the family. An
 * unresolved entry has no output interfaces.
 *
 * @param vm        ucode VM context
 * @param arr       array to append to
 * @param family    AF_INET or AF_INET6
 * @param cache     proc file of the forwarding cache
 * @param vifs      proc file of the vifs
 */
static void
mr_cache_read(uc_vm_t *vm, uc_value_t *arr, int family,
	      const char *cache, const char *vifs)
{
	char names[MR_VIFS_MAX][IFNAMSIZ] = { 0 };
	char line[1024], group_text[48], origin_text[48];
	char group[INET6_ADDRSTRLEN], origin[INET6_ADDRSTRLEN];
	unsigned long pkts, bytes, wrong;
	uc_value_t *entry, *oifs;
	int iif, used, vif, ttl;
	const char *p;
	FILE *fp;

	fp = fopen(cache, "r");
	if (!fp)
		return;

	mr_vifs_read(vifs, names);

	while (fgets(line, sizeof(line), fp)) {
		if (sscanf(line, "%47s %47s %d %lu %lu %lu%n", group_text, origin_text,
			   &iif, &pkts, &bytes, &wrong, &used) != 6)
			continue;
		if (!mr_addr_parse(family, group_text, group) ||
		    !mr_addr_parse(family, origin_text, origin))
			continue;

		oifs = ucv_array_new(vm);
		for (p = line + used; sscanf(p, " %d:%d%n", &vif, &ttl, &used) == 2; p += used)
			if (vif >= 0 && vif < MR_VIFS_MAX && names[vif][0])
				ucv_array_push(oifs, ucv_string_new(names[vif]));

		entry = ucv_object_new(vm);
		ucv_object_add(entry, "group", ucv_string_new(group));
		ucv_object_add(entry, "origin", ucv_string_new(origin));
		ucv_object_add(entry, "iif", (iif >= 0 && iif < MR_VIFS_MAX && names[iif][0])
			? ucv_string_new(names[iif]) : NULL);
		ucv_object_add(entry, "oifs", oifs);
		ucv_object_add(entry, "packets", ucv_uint64_new(pkts));
		ucv_object_add(entry, "bytes", ucv_uint64_new(bytes));
		ucv_array_push(arr, entry);
	}

	fclose(fp);
}

/**
 * Parses the IPv4 and IPv6 multicast forwarding caches.
 *
 * Reads `/proc/net/ip_mr_cache` and `/proc/net/ip6_mr_cache` with their
 * vif files.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (none expected)
 * @return       array of `{ group, origin, iif, oifs, packets, bytes }`,
 *               IPv4 entries first, possibly empty
 */
static uc_value_t *
uc_ubbf_mr_cache_parse(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *arr = ucv_array_new(vm);

	mr_cache_read(vm, arr, AF_INET, "/proc/net/ip_mr_cache", "/proc/net/ip_mr_vif");
	mr_cache_read(vm, arr, AF_INET6, "/proc/net/ip6_mr_cache", "/proc/net/ip6_mr_vif");

	return arr;
}

static const uc_function_list_t multicast_fns[] = {
	{ "mr_cache_parse",     uc_ubbf_mr_cache_parse },
};

void
uc_module_init(uc_vm_t *vm, uc_value_t *scope)
{
	uc_function_list_register(scope, multicast_fns);
}
