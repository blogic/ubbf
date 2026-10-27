/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

/*
 * The dynamic IPv6 prefixes of an IP.Interface: delegated prefixes from
 * netifd and prefixes learned from Router Advertisements. utils/ipv6.uc
 * makes the netifd ubus call.
 */

#include "ubbf.h"
#include "bindings.h"

#include <arpa/inet.h>
#include <syslog.h>

#define RA_PREFIX_STATE "/tmp/ubbf/ra-prefix.%s"

/* A prefix length in [0,128] on a nibble boundary; the value is read as
 * ucode `+len` reads it. */
static bool
nibble_length_ok(uc_value_t *len)
{
	uc_value_t *num;
	int64_t n = -1;

	if (!len || value_loose_is(len, ""))
		return false;

	num = ucv_to_number(len);
	if (ucv_type(num) == UC_INTEGER)
		n = ucv_int64_get(num);
	ucv_put(num);

	return n >= 0 && n <= 128 && !(n % 4);
}

/**
 * ucode: `prefix_length_nibble_check(len)`, whether a prefix length is an
 * integer in [0,128] and a multiple of 4.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: string or number)
 * @return       boolean
 */
uc_value_t *
uc_ubbf_prefix_length_nibble_check(uc_vm_t *vm, size_t nargs)
{
	return ucv_boolean_new(nibble_length_ok(uc_fn_arg(0)));
}

/* ubbf to_int() of a text, or `def` when it is no integer. */
static int64_t
text_int(const char *text, int64_t def)
{
	uc_value_t *str = ucv_string_new(text);
	int64_t n;

	if (!value_to_int(str, &n))
		n = def;
	ucv_put(str);

	return n;
}

/* One line of the state file: `addr/len,preferred,valid[,...]`. The address
 * is the formed SLAAC address, so the host bits are masked off. */
static bool
ra_line_parse(char *line, char *prefix, int64_t *mask, int64_t *preferred, int64_t *valid)
{
	char *fields[3], *slash, *p = line;
	struct in6_addr addr;

	for (int i = 0; i < 3; i++) {
		fields[i] = p;
		p = strchr(p, ',');
		if (!p && i < 2)
			return false;
		if (p)
			*p++ = '\0';
	}

	slash = strchr(fields[0], '/');
	if (!slash || strchr(slash + 1, '/'))
		return false;
	*slash = '\0';

	*mask = text_int(slash + 1, 64);
	if (*mask < 0 || *mask > 128 || inet_pton(AF_INET6, fields[0], &addr) != 1)
		return false;

	for (int i = 0; i < 16; i++) {
		if (i * 8 >= *mask)
			addr.s6_addr[i] = 0;
		else if (i * 8 + 8 > *mask)
			addr.s6_addr[i] &= 0xff << (8 - (*mask - i * 8));
	}

	inet_ntop(AF_INET6, &addr, prefix, INET6_ADDRSTRLEN);
	*preferred = text_int(fields[1], 0);
	*valid = text_int(fields[2], 0);

	return true;
}

static bool
ra_prefix_seen(uc_value_t *list, const char *prefix, int64_t mask)
{
	uc_value_t *row, *addr;

	for (size_t i = 0; i < ucv_array_length(list); i++) {
		row = ucv_array_get(list, i);
		addr = ucv_object_get(row, "address", NULL);
		if (ucv_int64_get(ucv_object_get(row, "mask", NULL)) == mask && !strcmp(ucv_string_get(addr), prefix))
			return true;
	}

	return false;
}

/* The RA prefixes that /etc/odhcp6c.user.d/10-ubbf-ra-prefix stores for a
 * netifd interface, without repeats. */
static uc_value_t *
ra_prefixes_hook_read(uc_vm_t *vm, const char *iface)
{
	uc_value_t *list = ucv_array_new(vm), *row;
	int64_t mask, preferred, valid;
	char prefix[INET6_ADDRSTRLEN], *path, *line = NULL, *entry, *end;
	size_t cap = 0;
	FILE *fp;

	xasprintf(&path, RA_PREFIX_STATE, iface);
	fp = fopen(path, "r");
	free(path);

	if (!fp)
		return list;

	while (getline(&line, &cap, fp) >= 0) {
		entry = line + strspn(line, " \t\r\n");
		for (end = entry + strlen(entry); end > entry && strchr(" \t\r\n", end[-1]); end--)
			;
		*end = '\0';

		if (!*entry || !ra_line_parse(entry, prefix, &mask, &preferred, &valid) ||
		    ra_prefix_seen(list, prefix, mask))
			continue;

		row = ucv_object_new(vm);
		ucv_object_add(row, "address", ucv_string_new(prefix));
		ucv_object_add(row, "mask", ucv_int64_new(mask));
		ucv_object_add(row, "preferred", ucv_int64_new(preferred));
		ucv_object_add(row, "valid", ucv_int64_new(valid));
		ucv_array_push(list, row);
	}

	free(line);
	fclose(fp);

	return list;
}

/**
 * ucode: `ra_prefixes_hook_read(iface)`, the RA prefixes of a netifd
 * interface from the state file of the odhcp6c hook. The kernel FIB has
 * no on-link PIO routes there: accept_ra is 0 on the l3 device, because
 * odhcp6c consumes the RAs.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: netifd interface, e.g. 'wan6')
 * @return       array of `{ address, mask, preferred, valid }`
 */
uc_value_t *
uc_ubbf_ra_prefixes_hook_read(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *iface = uc_fn_arg(0);
	uc_value_t *list;
	char *name;

	if (!ucv_is_truish(iface))
		return ucv_array_new(vm);

	name = ucv_to_string(vm, iface);
	list = ra_prefixes_hook_read(vm, name);
	free(name);

	return list;
}

static uc_value_t *
prefix_row_new(uc_vm_t *vm, uc_value_t *data, const char *origin)
{
	uc_value_t *row = ucv_object_new(vm);

	ucv_object_add(row, "data", ucv_get(data));
	ucv_object_add(row, "origin", ucv_string_new(origin));

	return row;
}

static void
pd_prefix_drop_log(uc_vm_t *vm, uc_value_t *name, uc_value_t *prefix)
{
	uc_value_t *addr = ucv_object_get(prefix, "address", NULL);
	uc_value_t *mask = ucv_object_get(prefix, "mask", NULL);
	char *n = ucv_to_string(vm, name);
	char *a = addr ? ucv_to_string(vm, addr) : xstrdup("?");
	char *m = mask ? ucv_to_string(vm, mask) : xstrdup("?");

	ubbf_log(LOG_ERR, "IP.Interface %s: dropping non-nibble PD prefix %s/%s", n, a, m);

	free(n);
	free(a);
	free(m);
}

/**
 * ucode: `ipv6_prefix_rows_build(name, upstream, netifd6, l2_dev)`, the
 * dynamic IPv6 prefix rows of an interface in the order of the tree read:
 * the delegated prefixes of netifd on a nibble boundary first, then on an
 * upstream interface the RA prefixes from the odhcp6c hook, or from the
 * kernel without a hook state. The tree read and the reads of one row
 * index this list, so the two views agree.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (4 expected: IP.Interface Name,
 *               Upstream flag, netifd status of the IPv6 interface, device
 *               for the kernel RA prefixes)
 * @return       array of `{ data, origin }`
 */
uc_value_t *
uc_ubbf_ipv6_prefix_rows_build(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *name = uc_fn_arg(0), *pd = ucv_object_get(uc_fn_arg(2), "ipv6-prefix", NULL);
	uc_value_t *rows = ucv_array_new(vm), *prefix, *ra;
	char *iface;

	for (size_t i = 0; i < ucv_array_length(pd); i++) {
		prefix = ucv_array_get(pd, i);
		if (nibble_length_ok(ucv_object_get(prefix, "mask", NULL)))
			ucv_array_push(rows, prefix_row_new(vm, prefix, "PrefixDelegation"));
		else
			pd_prefix_drop_log(vm, name, prefix);
	}

	if (!ucv_is_truish(uc_fn_arg(1)))
		return rows;

	iface = ucv_to_string(vm, name);
	iface = xrealloc(iface, strlen(iface) + 2);
	strcat(iface, "6");
	ra = ra_prefixes_hook_read(vm, iface);
	free(iface);

	if (!ucv_array_length(ra)) {
		ucv_put(ra);
		ra = ra_prefixes_new(vm, uc_fn_arg(3));
	}

	for (size_t i = 0; i < ucv_array_length(ra); i++)
		ucv_array_push(rows, prefix_row_new(vm, ucv_array_get(ra, i), "RouterAdvertisement"));

	ucv_put(ra);

	return rows;
}
