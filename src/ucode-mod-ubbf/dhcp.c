/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

#include "ubbf.h"
#include "bindings.h"

#include <arpa/inet.h>
#include <ctype.h>

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
 * @param vm  ucode VM context
 * @return    new array of lease objects, possibly empty
 */
uc_value_t *
leases_new(uc_vm_t *vm)
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
		uint32_t ip_n;
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

		str_to_upper(mac_s);

		o = ucv_object_new(vm);
		ucv_object_add(o, "expiry", ucv_int64_new(strtoll(expiry_s, NULL, 10)));
		ucv_object_add(o, "mac", ucv_string_new(mac_s));
		ucv_object_add(o, "ip", ucv_string_new(ip_s));
		ucv_object_add(o, "hostname", ucv_string_new(host_s));
		ucv_object_add(o, "client_id", ucv_string_new(cid_s ? cid_s : ""));
		ucv_object_add(o, "ip_int", ucv_int64_new(ipv4_parse(ip_s, &ip_n) ? ip_n : 0));

		ucv_array_push(arr, o);
	}

	free(buf);
	fclose(fp);
	return arr;
}

/**
 * ucode: `leases_parse()`, see leases_new().
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (none expected)
 * @return       array of lease objects, possibly empty
 */
uc_value_t *
uc_ubbf_leases_parse(uc_vm_t *vm, size_t nargs)
{
	return leases_new(vm);
}

/* `mac ? uc(mac) : mac_from_duid(duid)` of a lease. */
static uc_value_t *
lease_mac_new(uc_vm_t *vm, uc_value_t *lease, uc_value_t *duid)
{
	uc_value_t *mac = ucv_object_get(lease, "mac", NULL), *res;
	char buf[18], *text;

	if (ucv_is_truish(mac)) {
		text = ucv_to_string(vm, mac);
		str_to_upper(text);
		res = ucv_string_new(text);
		free(text);

		return res;
	}

	if (ucv_type(duid) != UC_STRING || !duid_mac_get(ucv_string_get(duid), ucv_string_length(duid), buf))
		return NULL;

	return ucv_string_new(buf);
}

/**
 * ucode: `ipv6_leases_by_mac(raw)`, the IPv6 addresses of the odhcpd
 * leases by client MAC; a lease without a MAC gives the MAC of its DUID.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: `dhcp ipv6leases` reply)
 * @return       object of MAC to array of addresses
 */
uc_value_t *
uc_ubbf_ipv6_leases_by_mac(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *devices = ucv_object_get(uc_fn_arg(0), "device", NULL);
	uc_value_t *result = ucv_object_new(vm), *leases, *lease, *mac, *list, *addrs, *addr;

	ucv_object_foreach(devices, name, dev) {
		(void)name;
		leases = ucv_object_get(dev, "leases", NULL);

		for (size_t i = 0; i < ucv_array_length(leases); i++) {
			lease = ucv_array_get(leases, i);
			mac = lease_mac_new(vm, lease, ucv_object_get(lease, "duid", NULL));
			if (!mac)
				continue;

			list = ucv_object_get(result, ucv_string_get(mac), NULL);
			if (!list) {
				list = ucv_array_new(vm);
				ucv_object_add(result, ucv_string_get(mac), list);
			}

			addrs = ucv_object_get(lease, "ipv6-addr", NULL);
			for (size_t j = 0; j < ucv_array_length(addrs); j++) {
				addr = ucv_object_get(ucv_array_get(addrs, j), "address", NULL);
				if (ucv_is_truish(addr))
					ucv_array_push(list, ucv_get(addr));
			}

			ucv_put(mac);
		}
	}

	return result;
}

static void
lease_entries_append(uc_value_t *list, uc_value_t *lease, const char *key)
{
	uc_value_t *entries = ucv_object_get(lease, key, NULL);

	for (size_t i = 0; i < ucv_array_length(entries); i++)
		ucv_array_push(list, ucv_get(ucv_array_get(entries, i)));
}

static uc_value_t *
pool_client_new(uc_vm_t *vm, uc_value_t *lease, uc_value_t *duid)
{
	uc_value_t *client = ucv_object_new(vm);

	ucv_object_add(client, "duid", ucv_get(duid));
	ucv_object_add(client, "mac", lease_mac_new(vm, lease, duid));
	ucv_object_add(client, "hostname", ucv_get(ucv_object_get(lease, "hostname", NULL)));
	ucv_object_add(client, "addresses", ucv_array_new(vm));
	ucv_object_add(client, "prefixes", ucv_array_new(vm));

	return client;
}

/**
 * ucode: `ipv6_pool_clients_build(status, raw)`, the clients of a DHCPv6
 * server pool, one per DUID, in the order of the odhcpd leases of the
 * device of the pool interface.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (2 expected: netifd status of the pool
 *               interface, `dhcp ipv6leases` reply)
 * @return       array of `{ duid, mac, hostname, addresses, prefixes }`
 */
uc_value_t *
uc_ubbf_ipv6_pool_clients_build(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *status = uc_fn_arg(0), *dev, *device, *leases, *lease, *duid, *client;
	uc_value_t *clients, *result = ucv_array_new(vm);
	char *key;

	dev = ucv_object_get(status, "l3_device", NULL);
	if (!dev)
		dev = ucv_object_get(status, "device", NULL);

	if (!ucv_is_truish(dev))
		return result;

	device = ucv_key_get(vm, ucv_object_get(uc_fn_arg(1), "device", NULL), dev);
	leases = ucv_object_get(device, "leases", NULL);
	clients = ucv_object_new(vm);

	for (size_t i = 0; i < ucv_array_length(leases); i++) {
		lease = ucv_array_get(leases, i);
		duid = ucv_object_get(lease, "duid", NULL);
		if (!ucv_is_truish(duid))
			continue;

		key = ucv_to_string(vm, duid);
		client = ucv_object_get(clients, key, NULL);
		if (!client) {
			client = pool_client_new(vm, lease, duid);
			ucv_object_add(clients, key, client);
		}
		free(key);

		lease_entries_append(ucv_object_get(client, "addresses", NULL), lease, "ipv6-addr");
		lease_entries_append(ucv_object_get(client, "prefixes", NULL), lease, "ipv6-prefix");
	}

	ucv_object_foreach(clients, k, c) {
		(void)k;
		ucv_array_push(result, ucv_get(c));
	}

	ucv_put(clients);
	ucv_put(device);

	return result;
}

static int64_t
pool_address(uc_value_t *pool, const char *name)
{
	uc_value_t *addr = ucv_object_get(pool, name, NULL);
	uint32_t n;

	return (ucv_type(addr) == UC_STRING && ipv4_parse(ucv_string_get(addr), &n)) ? n : 0;
}

static int
lease_expiry_cmp(uc_value_t *a, uc_value_t *b, void *ud)
{
	int64_t diff = ucv_int64_get(ucv_object_get(b, "expiry", NULL)) -
		       ucv_int64_get(ucv_object_get(a, "expiry", NULL));

	(void)ud;

	return (diff > 0) - (diff < 0);
}

/* The leases inside the address range of a DHCPv4 pool, the latest expiry
 * first. */
static uc_value_t *
pool_leases_new(uc_vm_t *vm, uc_value_t *pool)
{
	int64_t min = pool_address(pool, "MinAddress"), max = pool_address(pool, "MaxAddress"), ip;
	uc_value_t *list = ucv_array_new(vm), *all, *lease;

	if (!min || !max)
		return list;

	all = leases_new(vm);
	for (size_t i = 0; i < ucv_array_length(all); i++) {
		lease = ucv_array_get(all, i);
		ip = ucv_int64_get(ucv_object_get(lease, "ip_int", NULL));
		if (ip >= min && ip <= max)
			ucv_array_push(list, ucv_get(lease));
	}
	ucv_put(all);

	ucv_array_sort_r(list, lease_expiry_cmp, NULL);

	return list;
}

static char *
lease_mac_lower(uc_vm_t *vm, uc_value_t *lease)
{
	char *mac = ucv_to_string(vm, ucv_object_get(lease, "mac", NULL));

	for (char *p = mac; *p; p++)
		*p = tolower((unsigned char)*p);

	return mac;
}

/**
 * ucode: `pool_leases_by_key(pool)`, the leases of a DHCPv4 server pool
 * by numbering key, the latest expiry first. Of several leases of one
 * MAC, the lowest address is known by the MAC, the others by MAC and
 * address, so a renewal that changes the expiry order does not move an
 * address to another number.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: Pool row with MinAddress
 *               and MaxAddress)
 * @return       object of key to lease
 */
uc_value_t *
uc_ubbf_pool_leases_by_key(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *leases = pool_leases_new(vm, uc_fn_arg(0)), *lowest = ucv_object_new(vm);
	uc_value_t *by_key = ucv_object_new(vm), *lease, *low, *ip;
	char *mac, *key;

	for (size_t i = 0; i < ucv_array_length(leases); i++) {
		lease = ucv_array_get(leases, i);
		mac = lease_mac_lower(vm, lease);
		low = ucv_object_get(lowest, mac, NULL);

		if (!low || ucv_int64_get(ucv_object_get(lease, "ip_int", NULL)) <
			    ucv_int64_get(ucv_object_get(low, "ip_int", NULL)))
			ucv_object_add(lowest, mac, ucv_get(lease));

		free(mac);
	}

	for (size_t i = 0; i < ucv_array_length(leases); i++) {
		lease = ucv_array_get(leases, i);
		mac = lease_mac_lower(vm, lease);

		ip = ucv_object_get(lease, "ip", NULL);

		if (ucv_object_get(lowest, mac, NULL) == lease)
			key = xstrdup(mac);
		else
			xasprintf(&key, "%s/%s", mac, ucv_string_get(ip));

		ucv_object_add(by_key, key, ucv_get(lease));
		free(key);
		free(mac);
	}

	ucv_put(lowest);
	ucv_put(leases);

	return by_key;
}

static bool
chaddr_valid(const char *s)
{
	for (int i = 0; i < 6; i++) {
		if (i && *s++ != ':')
			return false;
		if (!isxdigit((unsigned char)s[0]) || !isxdigit((unsigned char)s[1]))
			return false;
		s += 2;
	}

	return !*s;
}

/* Whether a StaticAddress row fits its pool: Chaddr is a MAC address and
 * Yiaddr is a host address of the pool subnet. */
static bool
static_address_valid(uc_value_t *pool, uc_value_t *row)
{
	uc_value_t *chaddr = ucv_object_get(row, "Chaddr", NULL), *yiaddr = ucv_object_get(row, "Yiaddr", NULL);
	int64_t mask, base, net, bcast;
	struct in_addr a;
	uint32_t addr;

	if (ucv_type(chaddr) != UC_STRING || !chaddr_valid(ucv_string_get(chaddr)))
		return false;

	if (ucv_type(yiaddr) != UC_STRING || inet_pton(AF_INET, ucv_string_get(yiaddr), &a) != 1)
		return false;

	mask = pool_address(pool, "SubnetMask");
	base = pool_address(pool, "MinAddress");
	if (!mask || !base)
		return true;

	addr = ntohl(a.s_addr);
	net = base & mask;
	bcast = net | (~mask & 0xffffffff);

	return (addr & mask) == net && addr != net && addr != bcast;
}

static void
static_group_add(uc_vm_t *vm, uc_value_t *groups, const char *key, const char *pool_key, const char *row_key)
{
	uc_value_t *group = ucv_object_get(groups, key, NULL), *ref = ucv_array_new(vm);

	if (!group) {
		group = ucv_array_new(vm);
		ucv_object_add(groups, key, group);
	}

	ucv_array_push(ref, ucv_string_new(pool_key));
	ucv_array_push(ref, ucv_string_new(row_key));
	ucv_array_push(group, ref);
}

static void
static_duplicates_mark(uc_value_t *states, uc_value_t *groups)
{
	uc_value_t *ref, *pool_key, *row_key;

	ucv_object_foreach(groups, key, group) {
		(void)key;
		if (ucv_array_length(group) < 2)
			continue;

		for (size_t i = 0; i < ucv_array_length(group); i++) {
			ref = ucv_array_get(group, i);
			pool_key = ucv_array_get(ref, 0);
			row_key = ucv_array_get(ref, 1);
			ucv_object_add(ucv_object_get(states, ucv_string_get(pool_key), NULL),
				       ucv_string_get(row_key), ucv_string_new("Error_DuplicateAddress"));
		}
	}
}

/**
 * ucode: `static_address_states(root)`, the configured state of every
 * Device.DHCPv4.Server.Pool.{i}.StaticAddress.{i} row. A row of a disabled
 * pool is Disabled. Enabled rows that share a Chaddr or a Yiaddr, across all
 * enabled pools, are Error_DuplicateAddress, because dnsmasq cannot serve
 * both.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: root)
 * @return       object of pool key to object of row key to Status
 */
uc_value_t *
uc_ubbf_static_address_states(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *pools = navigate_by_path(vm, uc_fn_arg(0), "Device.DHCPv4.Server.Pool");
	uc_value_t *states = ucv_object_new(vm), *by_mac = ucv_object_new(vm), *by_ip = ucv_object_new(vm);
	uc_value_t *pool_states, *chaddr, *yiaddr;
	char ip[INET_ADDRSTRLEN], *mac;
	const char *status;
	struct in_addr a;
	bool enabled;

	ucv_object_foreach(pools, pool_key, pool) {
		if (ucv_type(pool) != UC_OBJECT)
			continue;

		pool_states = ucv_object_new(vm);
		ucv_object_add(states, pool_key, pool_states);
		enabled = value_to_bool(ucv_object_get(pool, "Enable", NULL));

		ucv_object_foreach(ucv_object_get(pool, "StaticAddress", NULL), row_key, row) {
			if (ucv_type(row) != UC_OBJECT)
				continue;

			if (!enabled || !value_to_bool(ucv_object_get(row, "Enable", NULL)))
				status = "Disabled";
			else if (!static_address_valid(pool, row))
				status = "Error_Misconfigured";
			else
				status = "Active";

			ucv_object_add(pool_states, row_key, ucv_string_new(status));
			if (strcmp(status, "Active"))
				continue;

			chaddr = ucv_object_get(row, "Chaddr", NULL);
			mac = xstrdup(ucv_string_get(chaddr));
			for (char *p = mac; *p; p++)
				*p = tolower((unsigned char)*p);
			static_group_add(vm, by_mac, mac, pool_key, row_key);
			free(mac);

			yiaddr = ucv_object_get(row, "Yiaddr", NULL);
			inet_pton(AF_INET, ucv_string_get(yiaddr), &a);
			inet_ntop(AF_INET, &a, ip, sizeof(ip));
			static_group_add(vm, by_ip, ip, pool_key, row_key);
		}
	}

	static_duplicates_mark(states, by_mac);
	static_duplicates_mark(states, by_ip);

	ucv_put(by_mac);
	ucv_put(by_ip);

	return states;
}

/**
 * ucode: `dhcp_option_value(options, tag)`, the hex value of a snooped
 * DHCP option.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (2 expected: array of `{ tag, value }`,
 *               option tag)
 * @return       hex value, '' when the option is missing
 */
uc_value_t *
uc_ubbf_dhcp_option_value(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *options = uc_fn_arg(0), *opt, *value;

	for (size_t i = 0; i < ucv_array_length(options); i++) {
		opt = ucv_array_get(options, i);
		if (!loose_equal(ucv_object_get(opt, "tag", NULL), uc_fn_arg(1)))
			continue;

		value = ucv_object_get(opt, "value", NULL);

		return value ? ucv_get(value) : ucv_string_new("");
	}

	return ucv_string_new("");
}

/**
 * ucode: `hex_to_printable(hex)`, the text of a hex string when every byte
 * is printable ASCII, so that parameters like VendorClassID never carry
 * garbled text.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: hex string of even length)
 * @return       decoded text, or '' for any other input
 */
uc_value_t *
uc_ubbf_hex_to_printable(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *hex = uc_fn_arg(0), *res;
	size_t len = ucv_string_length(hex);
	const char *s;
	char *out;
	int byte;

	if (ucv_type(hex) != UC_STRING || !len || (len % 2))
		return ucv_string_new("");

	s = ucv_string_get(hex);
	out = xalloc(len / 2 + 1);

	for (size_t i = 0; i < len; i += 2) {
		byte = (hex_nibble(s[i]) << 4) | hex_nibble(s[i + 1]);
		if (hex_nibble(s[i]) < 0 || hex_nibble(s[i + 1]) < 0 || byte < 32 || byte > 126) {
			free(out);
			return ucv_string_new("");
		}
		out[i / 2] = byte;
	}

	res = ucv_string_new(out);
	free(out);

	return res;
}
