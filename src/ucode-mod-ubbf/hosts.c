/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

/*
 * Device.Hosts: the maps that the host scan merges, the DHCP client paths,
 * the ActiveLastChange state of /tmp/ubbf/hosts-state.json with the hosts
 * that left the LAN, and the lookup of a host by address. utils/hosts.uc
 * makes the ubus and iwinfo reads, keeps the caches and numbers the rows.
 */

#include "ubbf.h"
#include "bindings.h"

#include <arpa/inet.h>
#include <math.h>
#include <sys/stat.h>

#define HOSTS_STATE_DIR		"/tmp/ubbf"
#define HOSTS_STATE_PATH	HOSTS_STATE_DIR "/hosts-state.json"
#define HOSTS_STATE_TTL		(7 * 24 * 3600)

/* A write per minute keeps `seen` exact enough for a TTL of days; the
 * state lives in /tmp. */
#define HOSTS_SEEN_STEP		60

/**
 * ucode: `hosts_leases_by_mac()`, the DHCP leases by upper-case MAC; of two
 * leases of one MAC the later line wins.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (none expected)
 * @return       object of MAC to lease
 */
uc_value_t *
uc_ubbf_hosts_leases_by_mac(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *leases = leases_new(vm), *result = ucv_object_new(vm), *lease, *mac;

	for (size_t i = 0; i < ucv_array_length(leases); i++) {
		lease = ucv_array_get(leases, i);
		mac = ucv_object_get(lease, "mac", NULL);
		ucv_object_add(result, ucv_string_get(mac), ucv_get(lease));
	}

	ucv_put(leases);

	return result;
}

/**
 * ucode: `hosts_ap_ssids(status)`, the TR-181 SSID instance of the network
 * device of each access point, so that a host whose FDB port is an AP is
 * known as Wi-Fi even when the association list does not show it, for
 * example a station behind a repeater.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: network.wireless status)
 * @return       object of ifname to SSID instance number
 */
uc_value_t *
uc_ubbf_hosts_ap_ssids(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *result = ucv_object_new(vm), *ifaces, *iface, *ifname, *ssid;
	int64_t n;
	char *key;

	ucv_object_foreach(uc_fn_arg(0), radio_name, radio) {
		(void)radio_name;
		ifaces = ucv_object_get(radio, "interfaces", NULL);

		for (size_t i = 0; i < ucv_array_length(ifaces); i++) {
			iface = ucv_array_get(ifaces, i);
			ifname = ucv_object_get(iface, "ifname", NULL);
			ssid = ucv_object_get(ucv_object_get(iface, "config", NULL), "ubbf_ssid", NULL);
			if (!ucv_is_truish(ifname) || !ucv_is_truish(ssid))
				continue;

			key = ucv_to_string(vm, ifname);
			ucv_object_add(result, key, value_int_cut(ssid, &n) ? ucv_int64_new(n) : ucv_double_new(NAN));
			free(key);
		}
	}

	return result;
}

static bool
value_listed(uc_value_t *list, uc_value_t *val)
{
	uc_value_t *item;

	for (size_t i = 0; i < ucv_array_length(list); i++) {
		item = ucv_array_get(list, i);
		if (ucv_type(item) == ucv_type(val) && loose_equal(item, val))
			return true;
	}

	return false;
}

/**
 * ucode: `ipv6_maps_merge(a, b)`, two maps of MAC to IPv6 addresses in
 * one, the addresses of `b` after those of `a` and without repeats.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (2 expected: maps of MAC to array)
 * @return       new map
 */
uc_value_t *
uc_ubbf_ipv6_maps_merge(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *result = ucv_object_new(vm), *list, *addr;

	ucv_object_foreach(uc_fn_arg(0), mac, addrs) {
		list = ucv_array_new(vm);
		for (size_t i = 0; i < ucv_array_length(addrs); i++)
			ucv_array_push(list, ucv_get(ucv_array_get(addrs, i)));
		ucv_object_add(result, mac, list);
	}

	ucv_object_foreach(uc_fn_arg(1), mac2, addrs2) {
		list = ucv_object_get(result, mac2, NULL);
		if (!list) {
			list = ucv_array_new(vm);
			ucv_object_add(result, mac2, list);
		}

		for (size_t i = 0; i < ucv_array_length(addrs2); i++) {
			addr = ucv_array_get(addrs2, i);
			if (!value_listed(list, addr))
				ucv_array_push(list, ucv_get(addr));
		}
	}

	return result;
}

static uc_value_t *
iface_addresses_new(uc_vm_t *vm, uc_value_t *addrs)
{
	uc_value_t *list = ucv_array_new(vm), *addr, *entry;

	for (size_t i = 0; i < ucv_array_length(addrs); i++) {
		addr = ucv_array_get(addrs, i);
		entry = ucv_object_new(vm);
		ucv_object_add(entry, "ip", ucv_get(ucv_object_get(addr, "address", NULL)));
		ucv_object_add(entry, "mask", ucv_get(ucv_object_get(addr, "mask", NULL)));
		ucv_array_push(list, entry);
	}

	return list;
}

/**
 * ucode: `netifd_interfaces_build(dump)`, the addresses of the netifd
 * interfaces from a `network.interface dump` reply.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: the reply)
 * @return       array of `{ name, addresses, ipv6_addresses }`
 */
uc_value_t *
uc_ubbf_netifd_interfaces_build(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *ifaces = ucv_object_get(uc_fn_arg(0), "interface", NULL);
	uc_value_t *result = ucv_array_new(vm), *iface, *entry;

	for (size_t i = 0; i < ucv_array_length(ifaces); i++) {
		iface = ucv_array_get(ifaces, i);
		entry = ucv_object_new(vm);
		ucv_object_add(entry, "name", ucv_get(ucv_object_get(iface, "interface", NULL)));
		ucv_object_add(entry, "addresses", iface_addresses_new(vm, ucv_object_get(iface, "ipv4-address", NULL)));
		ucv_object_add(entry, "ipv6_addresses", iface_addresses_new(vm, ucv_object_get(iface, "ipv6-address", NULL)));
		ucv_array_push(result, entry);
	}

	return result;
}

/* The first `Device.WiFi.SSID.<n>` in a reference, as ucode match() finds
 * it; NULL without one. */
static char *
ssid_ref_instance(const char *ref)
{
	static const char prefix[] = "Device.WiFi.SSID.";
	const char *p = ref, *digits;
	size_t n;

	while ((p = strstr(p, prefix)) != NULL) {
		digits = p + strlen(prefix);
		n = strspn(digits, "0123456789");
		if (n)
			return strndup(digits, n);
		p++;
	}

	return NULL;
}

/**
 * ucode: `ap_by_ssid_instance(root)`, the AccessPoint instance whose
 * SSIDReference names each SSID instance; the first AccessPoint wins.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: root)
 * @return       object of SSID instance to AccessPoint instance
 */
uc_value_t *
uc_ubbf_ap_by_ssid_instance(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *aps = navigate_by_path(vm, uc_fn_arg(0), "Device.WiFi.AccessPoint");
	uc_value_t *result = ucv_object_new(vm), *ref;
	char *ssid;

	ucv_object_foreach(aps, ap_inst, ap) {
		ref = ucv_object_get(ap, "SSIDReference", NULL);
		ssid = (ucv_type(ref) == UC_STRING) ? ssid_ref_instance(ucv_string_get(ref)) : NULL;

		if (ssid && !ucv_object_get(result, ssid, NULL))
			ucv_object_add(result, ssid, ucv_string_new(ap_inst));

		free(ssid);
	}

	return result;
}

static int
instance_key_cmp(uc_value_t *a, uc_value_t *b, void *ud)
{
	double d = ucv_to_double(a) - ucv_to_double(b);

	(void)ud;

	return (d > 0) - (d < 0);
}

/* The path of the lowest-numbered client of each MAC in the numbered pool
 * clients of each pool. */
static uc_value_t *
pool_clients_index(uc_vm_t *vm, uc_value_t *pools)
{
	uc_value_t *index = ucv_object_new(vm), *nums, *num, *mac;
	char *key, *path;

	ucv_object_foreach(pools, base, clients) {
		nums = ucv_array_new(vm);
		ucv_object_foreach(clients, n, client) {
			(void)client;
			ucv_array_push(nums, ucv_string_new(n));
		}
		ucv_array_sort_r(nums, instance_key_cmp, NULL);

		for (size_t i = 0; i < ucv_array_length(nums); i++) {
			num = ucv_array_get(nums, i);
			mac = ucv_object_get(ucv_object_get(clients, ucv_string_get(num), NULL), "mac", NULL);
			if (!ucv_is_truish(mac))
				continue;

			key = ucv_to_string(vm, mac);
			if (!ucv_is_truish(ucv_object_get(index, key, NULL))) {
				xasprintf(&path, "%s.Client.%s", base, ucv_string_get(num));
				ucv_object_add(index, key, ucv_string_new(path));
				free(path);
			}
			free(key);
		}

		ucv_put(nums);
	}

	return index;
}

static void
pool_client_paths_add(uc_value_t *result, const char *mac, uc_value_t *v4, uc_value_t *v6)
{
	uc_value_t *p4 = ucv_object_get(v4, mac, NULL), *p6 = ucv_object_get(v6, mac, NULL);
	char *joined;

	if (ucv_object_get(result, mac, NULL))
		return;

	if (p4 && p6)
		xasprintf(&joined, "%s,%s", ucv_string_get(p4), ucv_string_get(p6));
	else
		joined = xstrdup(p4 ? ucv_string_get(p4) : p6 ? ucv_string_get(p6) : "");

	ucv_object_add(result, mac, ucv_string_new(joined));
	free(joined);
}

/**
 * ucode: `pool_client_paths(v4, v6)`, the Hosts.Host.{i}.DHCPClient value
 * of each MAC: the DHCPv4 and the DHCPv6 pool client that own its leases.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (2 expected: objects of pool path to
 *               the numbered clients of the pool, for DHCPv4 and DHCPv6)
 * @return       object of MAC to a list of up to two paths
 */
uc_value_t *
uc_ubbf_pool_client_paths(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *v4 = pool_clients_index(vm, uc_fn_arg(0)), *v6 = pool_clients_index(vm, uc_fn_arg(1));
	uc_value_t *result = ucv_object_new(vm);

	ucv_object_foreach(v4, mac, path) {
		(void)path;
		pool_client_paths_add(result, mac, v4, v6);
	}

	ucv_object_foreach(v6, mac6, path6) {
		(void)path6;
		pool_client_paths_add(result, mac6, v4, v6);
	}

	ucv_put(v4);
	ucv_put(v6);

	return result;
}

/**
 * ucode: `hosts_state_load()`, the ActiveLastChange state from disk:
 * `{ entries: { MAC: { active, last_change, changed, seen, host } },
 * dirty: false, now }`.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (none expected)
 * @return       state object
 */
uc_value_t *
uc_ubbf_hosts_state_load(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *state = ucv_object_new(vm), *saved = json_file_load(vm, HOSTS_STATE_PATH);
	uc_value_t *entries = ucv_object_get(saved, "entries", NULL);

	ucv_object_add(state, "entries", (ucv_type(entries) == UC_OBJECT) ? ucv_get(entries) : ucv_object_new(vm));
	ucv_object_add(state, "dirty", ucv_boolean_new(false));
	ucv_object_add(state, "now", ucv_int64_new(time(NULL)));
	ucv_put(saved);

	return state;
}

static void
state_dirty_set(uc_value_t *state, bool dirty)
{
	ucv_object_add(state, "dirty", ucv_boolean_new(dirty));
}

static double
state_now(uc_value_t *state)
{
	return ucv_to_double(ucv_object_get(state, "now", NULL));
}

static double
entry_number(uc_value_t *entry, const char *name, double def)
{
	uc_value_t *val = ucv_object_get(entry, name, NULL);

	return val ? ucv_to_double(val) : def;
}

static uc_value_t *
entry_changed_new(uc_vm_t *vm, uc_value_t *entry, uc_value_t *state, uc_value_t *active)
{
	uc_value_t *now = ucv_object_get(state, "now", NULL), *changed = ucv_object_new(vm);
	char buf[48];

	ucv_object_foreach(entry, key, val)
		ucv_object_add(changed, key, ucv_get(val));

	ucv_object_add(changed, "active", ucv_get(active));
	if (ucv_type(now) == UC_INTEGER) {
		ucv_object_add(changed, "last_change", unix_to_datetime_new(now));
	} else {
		datetime_utc_format(time(NULL), -1, buf, sizeof(buf));
		ucv_object_add(changed, "last_change", ucv_string_new(buf));
	}
	ucv_object_add(changed, "changed", ucv_get(now));

	return changed;
}

/**
 * ucode: `host_active_track(state, mac, active, snapshot)`, records the
 * Active state of a host and returns the time of its last transition; a
 * first sighting counts as a transition now. While the host is active, the
 * state keeps the last time it was seen and a snapshot of its row, which
 * hosts_downstream_build() lists after the host left, with Active false,
 * for HOSTS_STATE_TTL.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (4 expected: state, upper-case MAC,
 *               active flag, row to show while the host is away)
 * @return       ISO 8601 time of the last Active transition
 */
uc_value_t *
uc_ubbf_host_active_track(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *state = uc_fn_arg(0), *active = uc_fn_arg(2), *snapshot = uc_fn_arg(3);
	uc_value_t *entries = ucv_object_get(state, "entries", NULL), *entry;
	char *mac = ucv_to_string(vm, uc_fn_arg(1)), *a, *b;
	bool differ;

	entry = ucv_object_get(entries, mac, NULL);
	if (!ucv_is_truish(entry) || !loose_equal(ucv_object_get(entry, "active", NULL), active)) {
		entry = entry_changed_new(vm, entry, state, active);
		ucv_object_add(entries, mac, entry);
		state_dirty_set(state, true);
	}

	free(mac);

	if (!ucv_is_truish(active))
		return ucv_get(ucv_object_get(entry, "last_change", NULL));

	if (state_now(state) - entry_number(entry, "seen", 0) >= HOSTS_SEEN_STEP) {
		ucv_object_add(entry, "seen", ucv_get(ucv_object_get(state, "now", NULL)));
		state_dirty_set(state, true);
	}

	if (ucv_is_truish(snapshot)) {
		a = ucv_to_jsonstring(vm, snapshot);
		b = ucv_to_jsonstring(vm, ucv_object_get(entry, "host", NULL));
		differ = strcmp(a, b);
		free(a);
		free(b);

		if (differ) {
			ucv_object_add(entry, "host", ucv_get(snapshot));
			state_dirty_set(state, true);
		}
	}

	return ucv_get(ucv_object_get(entry, "last_change", NULL));
}

/* The hosts of the state of the last HOSTS_STATE_TTL seconds that are not
 * on the LAN now, from their snapshot, with Active false. */
static uc_value_t *
hosts_away_new(uc_vm_t *vm, uc_value_t *state, uc_value_t *present)
{
	uc_value_t *seen = ucv_object_new(vm), *away = ucv_array_new(vm), *host, *row;
	double now = state_now(state);
	char *mac;

	for (size_t i = 0; i < ucv_array_length(present); i++) {
		mac = ucv_to_string(vm, ucv_object_get(ucv_array_get(present, i), "mac", NULL));
		ucv_object_add(seen, mac, ucv_boolean_new(true));
		free(mac);
	}

	ucv_object_foreach(ucv_object_get(state, "entries", NULL), key, entry) {
		host = ucv_object_get(entry, "host", NULL);
		if (ucv_object_get(seen, key, NULL) || !ucv_is_truish(host) ||
		    now - entry_number(entry, "seen", 0) >= HOSTS_STATE_TTL)
			continue;

		row = ucv_object_new(vm);
		ucv_object_foreach(host, hk, hv)
			ucv_object_add(row, hk, ucv_get(hv));
		ucv_object_add(row, "mac", ucv_string_new(key));
		ucv_object_add(row, "active", ucv_boolean_new(false));
		ucv_array_push(away, row);
	}

	ucv_put(seen);

	return away;
}

/* The time from which a host of the state counts as inactive: its last
 * transition, or now while the state still has it active (a host that left
 * since the last read of the table). */
static double
host_inactive_since(uc_value_t *state, uc_value_t *host)
{
	uc_value_t *mac = ucv_object_get(host, "mac", NULL);
	uc_value_t *entry = ucv_object_get(ucv_object_get(state, "entries", NULL), ucv_string_get(mac), NULL);

	if (ucv_is_truish(ucv_object_get(entry, "active", NULL)))
		return state_now(state);

	return entry_number(entry, "changed", 0);
}

static int
inactive_since_cmp(uc_value_t *a, uc_value_t *b, void *ud)
{
	double d = host_inactive_since(ud, a) - host_inactive_since(ud, b);

	return (d > 0) - (d < 0);
}

/* Removes the away hosts that are inactive longest from the state until at
 * most `keep` of them are left (Device.Hosts.CleanupHostsThreshold). */
static uc_value_t *
hosts_away_trim(uc_vm_t *vm, uc_value_t *state, uc_value_t *away, size_t keep)
{
	uc_value_t *entries = ucv_object_get(state, "entries", NULL), *kept, *mac;
	size_t drop;

	if (ucv_array_length(away) <= keep)
		return away;

	ucv_array_sort_r(away, inactive_since_cmp, state);
	drop = ucv_array_length(away) - keep;

	for (size_t i = 0; i < drop; i++) {
		mac = ucv_object_get(ucv_array_get(away, i), "mac", NULL);
		ucv_object_delete(entries, ucv_string_get(mac));
	}
	state_dirty_set(state, true);

	kept = ucv_array_new(vm);
	for (size_t i = drop; i < ucv_array_length(away); i++)
		ucv_array_push(kept, ucv_get(ucv_array_get(away, i)));
	ucv_put(away);

	return kept;
}

static int
host_mac_cmp(uc_value_t *a, uc_value_t *b, void *ud)
{
	uc_value_t *ma = ucv_object_get(a, "mac", NULL), *mb = ucv_object_get(b, "mac", NULL);
	size_t la = ucv_string_length(ma), lb = ucv_string_length(mb);
	int delta;

	(void)ud;

	if (ucv_type(ma) != UC_STRING || ucv_type(mb) != UC_STRING)
		return 0;

	delta = memcmp(ucv_string_get(ma), ucv_string_get(mb), (la < lb) ? la : lb);
	if (!delta)
		delta = (la > lb) - (la < lb);

	return (delta > 0) - (delta < 0);
}

/**
 * ucode: `hosts_downstream_build(state, present, threshold)`, the hosts on
 * the LAN now and the hosts that left within HOSTS_STATE_TTL, with Active
 * false, sorted by MAC. If the table has more rows than the threshold
 * (Device.Hosts.CleanupHostsThreshold, -1 for none), the hosts that left
 * first go from the state.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (3 expected: state, hosts on the LAN,
 *               threshold value)
 * @return       array of host records
 */
uc_value_t *
uc_ubbf_hosts_downstream_build(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *state = uc_fn_arg(0), *present = uc_fn_arg(1), *away, *hosts;
	int64_t threshold, keep;

	away = hosts_away_new(vm, state, present);

	if (!value_to_int(uc_fn_arg(2), &threshold))
		threshold = -1;

	if (threshold >= 0) {
		keep = threshold - (int64_t)ucv_array_length(present);
		away = hosts_away_trim(vm, state, away, (keep > 0) ? keep : 0);
	}

	hosts = ucv_array_new(vm);
	for (size_t i = 0; i < ucv_array_length(present); i++)
		ucv_array_push(hosts, ucv_get(ucv_array_get(present, i)));
	for (size_t i = 0; i < ucv_array_length(away); i++)
		ucv_array_push(hosts, ucv_get(ucv_array_get(away, i)));
	ucv_put(away);

	ucv_array_sort_r(hosts, host_mac_cmp, NULL);

	return hosts;
}

/**
 * ucode: `hosts_inactive_drop(state, present, min_time)`, removes the hosts
 * that left the LAN from the state, all of them or only those inactive for
 * longer than `min_time` (Device.Hosts.RemoveInactiveHosts()).
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (3 expected: state, hosts on the LAN,
 *               seconds of inactivity or null for all)
 * @return       number of hosts removed
 */
uc_value_t *
uc_ubbf_hosts_inactive_drop(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *state = uc_fn_arg(0), *min_time = uc_fn_arg(2), *host, *mac;
	uc_value_t *away = hosts_away_new(vm, state, uc_fn_arg(1));
	int64_t removed = 0;

	for (size_t i = 0; i < ucv_array_length(away); i++) {
		host = ucv_array_get(away, i);
		if (min_time && state_now(state) - host_inactive_since(state, host) <= ucv_to_double(min_time))
			continue;

		mac = ucv_object_get(host, "mac", NULL);
		ucv_object_delete(ucv_object_get(state, "entries", NULL), ucv_string_get(mac));
		removed++;
	}

	if (removed)
		state_dirty_set(state, true);

	ucv_put(away);

	return ucv_int64_new(removed);
}

/**
 * ucode: `hosts_state_flush(state)`, writes the state to disk when it
 * changed, without the entries not seen for HOSTS_STATE_TTL. The write is
 * atomic: another process can read the file at any time, and a partial
 * read would make it start over with an empty state.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: state)
 * @return       null
 */
uc_value_t *
uc_ubbf_hosts_state_flush(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *state = uc_fn_arg(0), *pruned, *file;
	double cutoff = state_now(state) - HOSTS_STATE_TTL;
	char *text;

	if (!ucv_is_truish(state))
		return NULL;

	pruned = ucv_object_new(vm);
	ucv_object_foreach(ucv_object_get(state, "entries", NULL), mac, entry) {
		if (entry_number(entry, "seen", state_now(state)) < cutoff) {
			state_dirty_set(state, true);
			continue;
		}
		ucv_object_add(pruned, mac, ucv_get(entry));
	}

	if (!ucv_is_truish(ucv_object_get(state, "dirty", NULL))) {
		ucv_put(pruned);
		return NULL;
	}

	ucv_object_add(state, "entries", pruned);

	file = ucv_object_new(vm);
	ucv_object_add(file, "entries", ucv_get(pruned));
	text = ucv_to_jsonstring(vm, file);
	ucv_put(file);

	mkdir(HOSTS_STATE_DIR, 0777);
	file_write_atomic(HOSTS_STATE_PATH, text, strlen(text), 0644);
	free(text);

	state_dirty_set(state, false);

	return NULL;
}

/* An address in canonical form, as ucode iptoarr() reads it; a zone after
 * '%' is ignored. */
static bool
host_addr_parse(uc_value_t *val, uint8_t out[17])
{
	char *text;
	bool ok = true;

	if (ucv_type(val) != UC_STRING)
		return false;

	text = strndup(ucv_string_get(val), strcspn(ucv_string_get(val), "%"));
	memset(out, 0, 17);

	if (inet_pton(AF_INET6, text, out + 1) == 1)
		out[0] = 6;
	else if (inet_pton(AF_INET, text, out + 1) == 1)
		out[0] = 4;
	else
		ok = false;

	free(text);

	return ok;
}

static bool
host_has_addr(uc_value_t *host, const uint8_t want[17])
{
	static const char *const lists[] = { "ipv4_addresses", "ipv6_addresses" };
	uc_value_t *addrs;
	uint8_t a[17];

	for (size_t l = 0; l < ARRAY_SIZE(lists); l++) {
		addrs = ucv_object_get(host, lists[l], NULL);
		for (size_t i = 0; i < ucv_array_length(addrs); i++)
			if (host_addr_parse(ucv_array_get(addrs, i), a) && !memcmp(a, want, sizeof(a)))
				return true;
	}

	return false;
}

/**
 * ucode: `host_path_by_ip_find(numbered, ip)`, the Device.Hosts.Host.{i}
 * path of the host with an IPv4 or IPv6 address. The addresses compare in
 * canonical form.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (2 expected: instance number to host
 *               record, address)
 * @return       path, or '' when no host has the address
 */
uc_value_t *
uc_ubbf_host_path_by_ip_find(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *res;
	uint8_t want[17];
	char *path;

	if (!host_addr_parse(uc_fn_arg(1), want))
		return ucv_string_new("");

	ucv_object_foreach(uc_fn_arg(0), n, host) {
		if (!host_has_addr(host, want))
			continue;

		xasprintf(&path, "Device.Hosts.Host.%s", n);
		res = ucv_string_new(path);
		free(path);

		return res;
	}

	return ucv_string_new("");
}
