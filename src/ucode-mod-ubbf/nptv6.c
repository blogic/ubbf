/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

/*
 * IPv6-to-IPv6 network prefix translation (RFC 6296),
 * Device.NAT.NPTv6.InterfaceSetting.{i}: the prefixes of a row and its
 * state. ucode sees a parsed prefix as `{ addr: [ 16 bytes ], len }`.
 */

#include "ubbf.h"
#include "bindings.h"

#include <arpa/inet.h>

/* Reads `address/length` of an IPv6 prefix. */
static bool
prefix6_parse(uc_value_t *val, struct in6_addr *addr, int *len)
{
	const char *s, *slash;
	unsigned long n;
	char *text;
	bool ok;

	if (ucv_type(val) != UC_STRING)
		return false;

	s = ucv_string_get(val);
	slash = strchr(s, '/');
	if (!slash || slash == s || strspn(s, "0123456789abcdefABCDEF:.") != (size_t)(slash - s) ||
	    !slash[1] || strspn(slash + 1, "0123456789") != strlen(slash + 1))
		return false;

	errno = 0;
	n = strtoul(slash + 1, NULL, 10);
	if (errno == ERANGE || n > 128)
		return false;

	text = strndup(s, slash - s);
	ok = inet_pton(AF_INET6, text, addr) == 1;
	free(text);

	*len = n;

	return ok;
}

/* Whether every address of the prefix `inner` lies inside `outer`. */
static bool
prefix6_contains(const struct in6_addr *outer, int outer_len,
		 const struct in6_addr *inner, int inner_len)
{
	uint8_t mask;

	if (inner_len < outer_len)
		return false;

	for (int i = 0, bits = outer_len; bits > 0; i++, bits -= 8) {
		mask = (bits >= 8) ? 0xff : (uint8_t)(0xff << (8 - bits));
		if ((outer->s6_addr[i] & mask) != (inner->s6_addr[i] & mask))
			return false;
	}

	return true;
}

/* A parsed prefix from its ucode form. */
static bool
prefix6_value(uc_value_t *val, struct in6_addr *addr, int *len)
{
	uc_value_t *bytes = ucv_object_get(val, "addr", NULL);

	if (ucv_array_length(bytes) != 16)
		return false;

	for (size_t i = 0; i < 16; i++)
		addr->s6_addr[i] = ucv_to_integer(ucv_array_get(bytes, i));

	*len = ucv_to_integer(ucv_object_get(val, "len", NULL));

	return true;
}

/**
 * ucode: `prefix6_parse(value)`, an IPv6 prefix in the form
 * address/length.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: prefix string)
 * @return       `{ addr, len }`, or null when invalid
 */
uc_value_t *
uc_ubbf_prefix6_parse(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *out, *bytes;
	struct in6_addr addr;
	int len;

	if (!prefix6_parse(uc_fn_arg(0), &addr, &len))
		return NULL;

	bytes = ucv_array_new(vm);
	for (size_t i = 0; i < 16; i++)
		ucv_array_push(bytes, ucv_int64_new(addr.s6_addr[i]));

	out = ucv_object_new(vm);
	ucv_object_add(out, "addr", bytes);
	ucv_object_add(out, "len", ucv_int64_new(len));

	return out;
}

/**
 * ucode: `prefix6_contains(outer, inner)`, whether every address of the
 * prefix `inner` lies inside `outer`.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (2 expected: prefix6_parse() results)
 * @return       boolean
 */
uc_value_t *
uc_ubbf_prefix6_contains(uc_vm_t *vm, size_t nargs)
{
	struct in6_addr outer, inner;
	int outer_len, inner_len;

	if (!prefix6_value(uc_fn_arg(0), &outer, &outer_len) ||
	    !prefix6_value(uc_fn_arg(1), &inner, &inner_len))
		return ucv_boolean_new(false);

	return ucv_boolean_new(prefix6_contains(&outer, outer_len, &inner, inner_len));
}

static uc_value_t *
state_new(uc_vm_t *vm, const char *status)
{
	uc_value_t *state = ucv_object_new(vm);

	ucv_object_add(state, "status", ucv_string_new(status));

	return state;
}

/**
 * ucode: `nptv6_setting_check(root, row)`, the state of one
 * Device.NAT.NPTv6.InterfaceSetting.{i} row. A row is inoperable when
 * Interface does not resolve, when a prefix is missing or invalid, or when
 * the prefixes differ in length (RFC 6296 maps prefixes of one length).
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (2 expected: root, InterfaceSetting row)
 * @return       `{ status, network, internal, external }`; status is
 *               Disabled, Error_Misconfigured or Enabled
 */
uc_value_t *
uc_ubbf_nptv6_setting_check(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *root = uc_fn_arg(0), *row = uc_fn_arg(1), *network = NULL, *state;
	uc_value_t *internal = ucv_object_get(row, "InternalPrefix", NULL);
	uc_value_t *external = ucv_object_get(row, "ExternalPrefix", NULL);
	uc_value_t *iface = ucv_object_get(row, "Interface", NULL);
	struct in6_addr a;
	int ilen, elen;

	if (!value_to_bool(ucv_object_get(row, "Enable", NULL)))
		return state_new(vm, "Disabled");

	if (ucv_is_truish(iface))
		network = interface_name_get(vm, root, iface);

	if (!ucv_is_truish(network) || !prefix6_parse(internal, &a, &ilen) ||
	    !prefix6_parse(external, &a, &elen) || ilen != elen)
		return state_new(vm, "Error_Misconfigured");

	state = state_new(vm, "Enabled");
	ucv_object_add(state, "network", ucv_get(network));
	ucv_object_add(state, "internal", ucv_get(internal));
	ucv_object_add(state, "external", ucv_get(external));

	return state;
}
