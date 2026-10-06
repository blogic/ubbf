/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

#include "ubbf.h"

/**
 * Converts a dotted-quad IPv4 address string to a 32-bit integer.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected)
 * @return       integer in network-byte-order layout, or 0 on parse failure
 */
uc_value_t *
uc_ubbf_ip_to_int(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *ip_val = uc_fn_arg(0);
	const char *ip;
	unsigned int a, b, c, d;

	if (ucv_type(ip_val) != UC_STRING)
		return ucv_int64_new(0);

	ip = ucv_string_get(ip_val);
	if (sscanf(ip, "%u.%u.%u.%u", &a, &b, &c, &d) != 4)
		return ucv_int64_new(0);

	return ucv_int64_new((int64_t)((a << 24) | (b << 16) | (c << 8) | d));
}

/**
 * Converts a 32-bit integer to its dotted-quad IPv4 string representation.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected)
 * @return       string in `a.b.c.d` form, or null when the input is not integer
 */
uc_value_t *
uc_ubbf_int_to_ip(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *n_val = uc_fn_arg(0);
	char buf[16];
	uint32_t n;

	if (ucv_type(n_val) != UC_INTEGER)
		return NULL;

	n = (uint32_t)ucv_int64_get(n_val);
	snprintf(buf, sizeof(buf), "%u.%u.%u.%u",
		 (n >> 24) & 0xff, (n >> 16) & 0xff,
		 (n >> 8) & 0xff, n & 0xff);

	return ucv_string_new(buf);
}

/**
 * Converts a CIDR prefix length to a dotted-quad netmask string.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected, 0-32)
 * @return       netmask string, or empty string for out-of-range input
 */
uc_value_t *
uc_ubbf_cidr_to_netmask(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *cidr_val = uc_fn_arg(0);
	int64_t cidr;
	uint32_t mask;
	char buf[16];

	if (ucv_type(cidr_val) != UC_INTEGER)
		return ucv_string_new("");

	cidr = ucv_int64_get(cidr_val);
	if (cidr < 0 || cidr > 32)
		return ucv_string_new("");

	if (cidr == 0)
		return ucv_string_new("0.0.0.0");

	mask = (uint32_t)(0xFFFFFFFFUL << (32 - cidr));
	snprintf(buf, sizeof(buf), "%u.%u.%u.%u",
		 (mask >> 24) & 0xFF, (mask >> 16) & 0xFF,
		 (mask >> 8) & 0xFF, mask & 0xFF);

	return ucv_string_new(buf);
}

/**
 * Converts a dotted-quad netmask string to a CIDR prefix length.
 *
 * Counts leading 1-bits without verifying that the remainder is all-zero, so
 * non-contiguous masks return the count of the leading run.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected)
 * @return       prefix length 0-32, or 0 on parse failure
 */
uc_value_t *
uc_ubbf_netmask_to_cidr(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *mask_val = uc_fn_arg(0);
	const char *mask;
	unsigned int a, b, c, d;
	uint32_t n;
	int cidr = 0;

	if (ucv_type(mask_val) != UC_STRING)
		return ucv_int64_new(0);

	mask = ucv_string_get(mask_val);
	if (sscanf(mask, "%u.%u.%u.%u", &a, &b, &c, &d) != 4)
		return ucv_int64_new(0);

	n = (a << 24) | (b << 16) | (c << 8) | d;
	while (n & 0x80000000U) {
		cidr++;
		n <<= 1;
	}

	return ucv_int64_new(cidr);
}

/**
 * Expands an IPv6 address into 32 lowercase hex characters.
 *
 * Resolves any `::` zero-run and writes the canonical full form into
 * `result`. The output buffer must be at least 33 bytes (32 hex characters
 * plus the trailing NUL). Empty or null input yields an all-zero address.
 *
 * @param addr   input address string (may contain `::`), or NULL
 * @param result destination buffer of at least 33 bytes
 */
void
ipv6_expand_to_buf(const char *addr, char *result)
{
	uint16_t groups[8] = { 0 };
	const char *dcolon;
	int left_cnt = 0, right_cnt = 0;
	int i;

	if (!addr || !*addr) {
		memcpy(result, "00000000000000000000000000000000", 33);
		return;
	}

	dcolon = strstr(addr, "::");

	if (dcolon) {
		char left_buf[64] = "", right_buf[64] = "";
		size_t left_len = dcolon - addr;

		if (left_len > 0 && left_len < sizeof(left_buf)) {
			memcpy(left_buf, addr, left_len);
			left_buf[left_len] = '\0';

			char *tmp = xstrdup(left_buf);
			for (char *tok = strtok(tmp, ":"); tok && left_cnt < 8; tok = strtok(NULL, ":"))
				groups[left_cnt++] = (uint16_t)strtoul(tok, NULL, 16);
			free(tmp);
		}

		const char *right_start = dcolon + 2;
		if (*right_start) {
			strncpy(right_buf, right_start, sizeof(right_buf) - 1);

			uint16_t right_groups[8] = { 0 };
			char *tmp = xstrdup(right_buf);
			for (char *tok = strtok(tmp, ":"); tok && right_cnt < 8; tok = strtok(NULL, ":"))
				right_groups[right_cnt++] = (uint16_t)strtoul(tok, NULL, 16);
			free(tmp);

			for (i = 0; i < right_cnt; i++)
				groups[8 - right_cnt + i] = right_groups[i];
		}
	} else {
		char *tmp = xstrdup(addr);
		for (char *tok = strtok(tmp, ":"); tok && left_cnt < 8; tok = strtok(NULL, ":"))
			groups[left_cnt++] = (uint16_t)strtoul(tok, NULL, 16);
		free(tmp);
	}

	snprintf(result, 33, "%04x%04x%04x%04x%04x%04x%04x%04x",
		 groups[0], groups[1], groups[2], groups[3],
		 groups[4], groups[5], groups[6], groups[7]);
}

#define LIFETIME_INFINITE INT64_MAX

/**
 * Reads a lifetime in seconds from a netifd, odhcp6c or kernel row.
 *
 * netifd leaves the key out for an infinite lifetime and reports the
 * seconds left as a u32, which wraps once a valid lifetime has run out.
 * 0xffffffff is the infinite lifetime of RFC 4861.
 *
 * @return  seconds left, 0 when expired, or LIFETIME_INFINITE
 */
static int64_t
lifetime_get(uc_value_t *obj, const char *key)
{
	uc_value_t *v = ucv_object_get(obj, key, NULL);
	int64_t n;

	if (ucv_type(v) != UC_INTEGER)
		return LIFETIME_INFINITE;

	n = ucv_int64_get(v);
	if (n == UINT32_MAX)
		return LIFETIME_INFINITE;
	if (n < 0 || n > INT32_MAX)
		return 0;
	return n;
}

/**
 * Helper: classify the IPv6 lifetime status from preferred/valid lifetimes.
 */
static const char *
ipv6_lifetime_str(int64_t preferred, int64_t valid)
{
	if (valid <= 0) return "Invalid";
	if (preferred <= 0) return "Deprecated";
	return "Preferred";
}

/**
 * Derives a TR-181 IPv6 lifetime status from preferred/valid lifetimes.
 *
 * Returns `"Invalid"` when `valid` has run out, `"Deprecated"` when
 * `preferred` has, otherwise `"Preferred"`. The two values are read from
 * the passed object under keys `preferred` and `valid` with
 * lifetime_get(); a missing key is an infinite lifetime.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: object)
 * @return       status string
 */
uc_value_t *
uc_ubbf_ipv6_lifetime_status(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *data = uc_fn_arg(0);

	if (ucv_type(data) != UC_OBJECT)
		return ucv_string_new("Invalid");

	return ucv_string_new(ipv6_lifetime_str(lifetime_get(data, "preferred"),
						lifetime_get(data, "valid")));
}

/**
 * Helper: read a string field from `obj`, return default when missing.
 */
static uc_value_t *
obj_str_or(uc_value_t *obj, const char *key, const char *def)
{
	uc_value_t *v = ucv_object_get(obj, key, NULL);

	if (ucv_type(v) == UC_STRING && ucv_string_length(v) > 0)
		return ucv_get(v);
	return ucv_string_new(def);
}

/**
 * Helper: read an integer field from `obj`, return default when missing.
 */
static int64_t
obj_int_or(uc_value_t *obj, const char *key, int64_t def)
{
	uc_value_t *v = ucv_object_get(obj, key, NULL);
	return (ucv_type(v) == UC_INTEGER) ? ucv_int64_get(v) : def;
}

/**
 * Builds a TR-181 IPv4Address object from a netifd-shaped address row.
 *
 * Reads `address` and `mask` (CIDR length) from the input object, derives
 * the dotted-quad SubnetMask, and emits the seven TR-181 fields with
 * sensible defaults. The optional second argument overrides the
 * `AddressingType` field (default `"DHCP"`).
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1-2 expected: addr object, optional addressing type)
 * @return       TR-181 object
 */
uc_value_t *
uc_ubbf_ipv4_addr_to_object(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *addr = uc_fn_arg(0);
	uc_value_t *atype = uc_fn_arg(1);
	uc_value_t *obj;
	int64_t cidr;
	uint32_t mask;
	char mbuf[16];
	const char *type_str;

	obj = ucv_object_new(vm);

	if (ucv_type(addr) != UC_OBJECT)
		return obj;

	cidr = obj_int_or(addr, "mask", 0);
	if (cidr < 0 || cidr > 32) {
		mbuf[0] = '\0';
	} else if (cidr == 0) {
		strcpy(mbuf, "0.0.0.0");
	} else {
		mask = (uint32_t)(0xFFFFFFFFUL << (32 - cidr));
		snprintf(mbuf, sizeof(mbuf), "%u.%u.%u.%u",
			 (mask >> 24) & 0xff, (mask >> 16) & 0xff,
			 (mask >> 8) & 0xff, mask & 0xff);
	}

	type_str = (ucv_type(atype) == UC_STRING) ? ucv_string_get(atype) : "DHCP";

	ucv_object_add(obj, "Enable", ucv_string_new("true"));
	ucv_object_add(obj, "Status", ucv_string_new("Enabled"));
	ucv_object_add(obj, "IPAddress", obj_str_or(addr, "address", ""));
	ucv_object_add(obj, "SubnetMask", ucv_string_new(mbuf));
	ucv_object_add(obj, "AddressingType", ucv_string_new(type_str));

	return obj;
}

/* TR-181 dateTime sentinel meaning "no expiry" / permanent. */
#define TR181_DATETIME_FOREVER "9999-12-31T23:59:59Z"

/**
 * Formats a remaining lifetime (seconds from now, from lifetime_get()) as
 * a TR-181 dateTime expiry string: LIFETIME_INFINITE yields the "no
 * expiry" sentinel, 0 the current time. Writes into `buf` (>= 32 bytes).
 */
static void
lifetime_datetime(int64_t seconds, char *buf, size_t buflen)
{
	struct tm tm;
	time_t t;

	if (seconds == LIFETIME_INFINITE) {
		snprintf(buf, buflen, "%s", TR181_DATETIME_FOREVER);
		return;
	}

	t = time(NULL) + (time_t)seconds;
	if (!gmtime_r(&t, &tm)) {
		snprintf(buf, buflen, "%s", TR181_DATETIME_FOREVER);
		return;
	}

	strftime(buf, buflen, "%Y-%m-%dT%H:%M:%SZ", &tm);
}

/**
 * Builds a TR-181 IPv6Address object from a netifd-shaped address row.
 *
 * Reads `address`, `preferred`, and `valid` from the input. Derives
 * IPAddressStatus from the lifetimes (matching `ubbf.ipv6_lifetime_status`).
 * The optional second argument overrides the `Origin` field (default
 * `"DHCPv6"`). A third truthy argument marks the address as permanent
 * (kernel-assigned link-local, static): IPAddressStatus becomes
 * `"Preferred"` and the lifetime fields emit the TR-181 dateTime sentinel
 * `"9999-12-31T23:59:59Z"` instead of a seconds count.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1-3 expected: addr object, optional
 *               origin, optional forever flag)
 * @return       TR-181 object
 */
uc_value_t *
uc_ubbf_ipv6_addr_to_object(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *addr = uc_fn_arg(0);
	uc_value_t *origin = uc_fn_arg(1);
	uc_value_t *forever_val = uc_fn_arg(2);
	uc_value_t *obj;
	int64_t preferred, valid;
	char buf[32];
	const char *origin_str;
	bool forever;

	obj = ucv_object_new(vm);
	if (ucv_type(addr) != UC_OBJECT)
		return obj;

	preferred = lifetime_get(addr, "preferred");
	valid = lifetime_get(addr, "valid");
	origin_str = (ucv_type(origin) == UC_STRING) ? ucv_string_get(origin) : "DHCPv6";
	forever = (ucv_type(forever_val) == UC_BOOLEAN) && ucv_boolean_get(forever_val);

	ucv_object_add(obj, "Enable", ucv_string_new("true"));
	ucv_object_add(obj, "Status", ucv_string_new("Enabled"));
	ucv_object_add(obj, "IPAddressStatus",
		       ucv_string_new(forever ? "Preferred"
					      : ipv6_lifetime_str(preferred, valid)));
	ucv_object_add(obj, "Alias", ucv_string_new(""));
	ucv_object_add(obj, "IPAddress", obj_str_or(addr, "address", ""));
	ucv_object_add(obj, "Origin", ucv_string_new(origin_str));
	if (forever) {
		ucv_object_add(obj, "PreferredLifetime",
			       ucv_string_new(TR181_DATETIME_FOREVER));
		ucv_object_add(obj, "ValidLifetime",
			       ucv_string_new(TR181_DATETIME_FOREVER));
	} else {
		lifetime_datetime(preferred, buf, sizeof(buf));
		ucv_object_add(obj, "PreferredLifetime", ucv_string_new(buf));
		lifetime_datetime(valid, buf, sizeof(buf));
		ucv_object_add(obj, "ValidLifetime", ucv_string_new(buf));
	}
	ucv_object_add(obj, "Anycast", ucv_string_new("false"));

	return obj;
}

/**
 * Derives TR-181 IPv6Prefix OnLink / Autonomous / StaticType defaults from
 * Origin. RA and Child prefixes are on-link and autonomous; delegated and
 * static prefixes are neither. StaticType follows the Static Origin.
 */
static void
ipv6_prefix_flags_from_origin(const char *origin,
			      const char **onlink,
			      const char **autonomous,
			      const char **static_type)
{
	if (!strcmp(origin, "RouterAdvertisement") ||
	    !strcmp(origin, "Child")) {
		*onlink = "true";
		*autonomous = "true";
		*static_type = "Inapplicable";
		return;
	}

	if (!strcmp(origin, "Static")) {
		*onlink = "false";
		*autonomous = "false";
		*static_type = "Static";
		return;
	}

	*onlink = "false";
	*autonomous = "false";
	*static_type = "Inapplicable";
}

/**
 * Builds a TR-181 IPv6Prefix object from a netifd-shaped prefix row.
 *
 * Reads `address`, `mask`, `preferred`, and `valid`. The optional second
 * argument overrides the `Origin` field (default `"PrefixDelegation"`).
 * OnLink, Autonomous, and StaticType default to values derived from Origin
 * (RA/Child: on-link+autonomous; Static: StaticType=Static; otherwise all
 * off with StaticType=Inapplicable).
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1-2 expected: prefix object, optional origin)
 * @return       TR-181 object
 */
uc_value_t *
uc_ubbf_ipv6_prefix_to_object(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *pfx = uc_fn_arg(0);
	uc_value_t *origin = uc_fn_arg(1);
	uc_value_t *obj;
	int64_t preferred, valid, mask;
	char buf[80];
	uc_value_t *addr;
	const char *origin_str;
	const char *onlink_str;
	const char *autonomous_str;
	const char *static_type_str;

	obj = ucv_object_new(vm);
	if (ucv_type(pfx) != UC_OBJECT)
		return obj;

	preferred = lifetime_get(pfx, "preferred");
	valid = lifetime_get(pfx, "valid");
	mask = obj_int_or(pfx, "mask", 0);
	addr = obj_str_or(pfx, "address", "");
	origin_str = (ucv_type(origin) == UC_STRING)
		? ucv_string_get(origin) : "PrefixDelegation";

	ipv6_prefix_flags_from_origin(origin_str,
				      &onlink_str,
				      &autonomous_str,
				      &static_type_str);

	ucv_object_add(obj, "Enable", ucv_string_new("true"));
	ucv_object_add(obj, "Status", ucv_string_new("Enabled"));
	ucv_object_add(obj, "PrefixStatus",
		       ucv_string_new(ipv6_lifetime_str(preferred, valid)));
	ucv_object_add(obj, "Alias", ucv_string_new(""));
	snprintf(buf, sizeof(buf), "%s/%lld", ucv_string_get(addr), (long long)mask);
	ucv_put(addr);
	ucv_object_add(obj, "Prefix", ucv_string_new(buf));
	ucv_object_add(obj, "Origin", ucv_string_new(origin_str));
	ucv_object_add(obj, "StaticType", ucv_string_new(static_type_str));
	ucv_object_add(obj, "OnLink", ucv_string_new(onlink_str));
	ucv_object_add(obj, "Autonomous", ucv_string_new(autonomous_str));
	lifetime_datetime(preferred, buf, sizeof(buf));
	ucv_object_add(obj, "PreferredLifetime", ucv_string_new(buf));
	lifetime_datetime(valid, buf, sizeof(buf));
	ucv_object_add(obj, "ValidLifetime", ucv_string_new(buf));

	return obj;
}
