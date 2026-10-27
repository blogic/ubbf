'use strict';

import * as fs from 'fs';
import * as ubus from 'ubus';
import * as ubbf from 'ubbf';
import {
	leases_parse,
	ipv6_leases_get,
	pool_leases_numbered,
	ipv6_pool_clients_numbered,
	dhcpsnoop_dump_get
} from 'ubbf.utils.dhcp';
import { call as cache_call } from 'ubbf.utils.cache';
import { wireless_status_get, assoclist_get, station_number } from 'ubbf.utils.wifi';
import { instance_numbers, instance_rows } from 'ubbf.utils.instance-map';

const HOSTS_TABLE = 'Device.Hosts.Host';
const HOSTS_STATE_PATH = '/tmp/ubbf/hosts-state.json';
const HOSTS_STATE_TTL = 7 * 24 * 3600;

/**
 * Indexes parsed DHCP leases by MAC address.
 *
 * @returns {object} Map of uppercase MAC to lease object (last wins on duplicate MAC)
 */
function leases_by_mac() {
	let leases = leases_parse();
	let result = {};

	for (let lease in leases)
		result[lease.mac] = lease;

	return result;
}

/**
 * Builds a map of associated station MACs to TR-181 SSID instance and station index.
 * Walks all radios and AP interfaces in network.wireless status, matching
 * iface.config.ubbf_ssid for the SSID instance number.
 *
 * @returns {object} Map of uppercase MAC to { ssid_instance }
 */
function wifi_associations_get() {
	let result = {};
	let status = wireless_status_get();
	if (!status)
		return result;

	for (let radio_name, radio in status) {
		if (!radio.interfaces)
			continue;

		for (let iface in radio.interfaces) {
			let ssid_inst = iface.config?.ubbf_ssid;
			let ifname = iface.ifname;
			if (!ssid_inst || !ifname)
				continue;

			let stations = assoclist_get(ifname);
			if (!stations)
				continue;

			for (let mac in stations)
				result[uc(mac)] = { ssid_instance: int(ssid_inst) };
		}
	}

	return result;
}

/**
 * Maps the network device of each access point to its TR-181 SSID
 * instance, so that a host whose FDB port is an AP is known as Wi-Fi even
 * when the association list does not show it, for example a station
 * behind a repeater.
 *
 * @returns {object} Map of ifname to SSID instance number
 */
function ap_ssid_by_ifname() {
	let result = {};

	for (let radio_name, radio in wireless_status_get() ?? {})
		for (let iface in radio.interfaces ?? [])
			if (iface.ifname && iface.config?.ubbf_ssid)
				result[iface.ifname] = int(iface.config.ubbf_ssid);

	return result;
}

/**
 * Merges two MAC -> IPv6 address-list maps, deduplicating addresses per MAC.
 *
 * @param {object} a - Primary map of MAC to address array
 * @param {object} b - Secondary map of MAC to address array (appended after a)
 * @returns {object} Combined map with unique addresses per MAC
 */
function ipv6_maps_merge(a, b) {
	let result = {};

	for (let mac, addrs in a)
		result[mac] = [...addrs];

	for (let mac, addrs in b) {
		if (!result[mac])
			result[mac] = [];
		for (let addr in addrs)
			if (index(result[mac], addr) < 0)
				push(result[mac], addr);
	}

	return result;
}

/**
 * Fetches network.interface dump from netifd via ubus (uncached).
 *
 * @returns {array} Array of { name, addresses, ipv6_addresses } per interface
 */
function netifd_interfaces_fetch() {
	let dump = ubus?.call('network.interface', 'dump');
	if (!dump || !dump.interface)
		return [];

	let result = [];
	for (let iface in dump.interface) {
		let name = iface.interface;
		let addresses = [];
		let ipv6_addresses = [];

		for (let addr in iface['ipv4-address'] ?? [])
			push(addresses, { ip: addr.address, mask: addr.mask });

		for (let addr in iface['ipv6-address'] ?? [])
			push(ipv6_addresses, { ip: addr.address, mask: addr.mask });

		push(result, { name, addresses, ipv6_addresses });
	}

	return result;
}

/**
 * Gets netifd interface dump (cached per request cycle).
 *
 * @returns {array} Array of { name, addresses, ipv6_addresses } per interface
 */
function netifd_interfaces_get() {
	return cache_call(netifd_interfaces_fetch);
}

/**
 * Adds the path of the lowest-numbered pool client of each MAC to a lookup.
 *
 * @param {object} result - Map of upper-case MAC to client path, filled in
 * @param {string} base - Path of the pool, e.g. Device.DHCPv4.Server.Pool.1
 * @param {object} clients - Instance number to pool client, each with `mac`
 */
function pool_clients_index(result, base, clients) {
	for (let n in sort(keys(clients), (a, b) => +a - +b)) {
		let mac = clients[n].mac;
		if (mac && !result[mac])
			result[mac] = sprintf('%s.Client.%s', base, n);
	}
}

/**
 * Builds the Hosts.Host.{i}.DHCPClient value of each MAC: the DHCPv4 and
 * the DHCPv6 pool client that own its leases, in the same numbering as
 * pool_client_get() of tr181/DHCPv4.uc and tr181/DHCPv6.uc. Reads the
 * config directly to avoid mutating pool objects (ubbf.instances adds
 * .instance/.path fields).
 *
 * @param {object} root - TR-181 config root
 * @returns {object} Map of upper-case MAC to a list of up to two paths
 */
function pool_client_by_mac(root) {
	let v4 = {}, v6 = {}, result = {};

	for (let inst, pool in root?.Device?.DHCPv4?.Server?.Pool ?? {}) {
		let base = `Device.DHCPv4.Server.Pool.${inst}`;
		pool_clients_index(v4, base, pool_leases_numbered(base, pool));
	}

	for (let inst, pool in root?.Device?.DHCPv6?.Server?.Pool ?? {}) {
		let base = `Device.DHCPv6.Server.Pool.${inst}`;
		pool_clients_index(v6, base, ipv6_pool_clients_numbered(base, root, pool));
	}

	for (let mac in uniq([...keys(v4), ...keys(v6)]))
		result[mac] = join(',', filter([v4[mac], v6[mac]], (p) => p != null));

	return result;
}

/**
 * Maps each TR-181 SSID instance to the AccessPoint instance whose
 * SSIDReference points at it. Reads the config directly to avoid mutating
 * AccessPoint objects (ubbf.instances adds .instance/.path fields).
 *
 * @param {object} root - TR-181 config root
 * @returns {object} Map of SSID instance string to AccessPoint instance string
 */
function ap_by_ssid_instance(root) {
	let result = {};
	let aps = root?.Device?.WiFi?.AccessPoint;
	if (type(aps) != 'object')
		return result;

	for (let ap_inst, ap in aps) {
		let m = match(ap?.SSIDReference ?? '', /Device\.WiFi\.SSID\.(\d+)/);
		if (!m || result[m[1]])
			continue;
		result[m[1]] = ap_inst;
	}

	return result;
}

// Module-level bridge so hosts_build() can pass the config root through
// to hosts_build_internal() via the cache_call() wrapper, which only
// accepts a no-arg callback.
let _root;

/**
 * Builds the merged host inventory by combining ARP, DHCP leases, IPv6
 * neighbours, IPv6 leases, bridge FDB, WiFi associations and netifd
 * interface state. Reads the config root from the module-level _root.
 *
 * @returns {object} { hosts, wifi_assocs, ap_ifnames, fdb, config,
 *                     netifd_ifaces, leases_by_mac, snoop_by_mac,
 *                     pool_client_paths }
 */
function hosts_build_internal() {
	let arp_entries = ubbf.arp_parse();
	let dhcp_leases = leases_by_mac();
	let ipv6_leases = ipv6_maps_merge(ipv6_leases_get(), ubbf.ipv6_neigh_parse());
	let wifi_assocs = wifi_associations_get();
	let ap_ifnames = ap_ssid_by_ifname();
	let ap_by_ssid = ap_by_ssid_instance(_root);
	for (let mac, wifi in wifi_assocs) {
		wifi.ap_instance = ap_by_ssid[sprintf('%d', wifi.ssid_instance)];
		if (wifi.ap_instance)
			wifi.sta_number = station_number(wifi.ap_instance, mac);
	}
	let fdb = cache_call(ubbf.bridge_fdb_parse);
	let netifd_ifaces = netifd_interfaces_get();
	let snoop = dhcpsnoop_dump_get();
	let pool_paths = pool_client_by_mac(_root);

	let hosts = ubbf.hosts_merge(arp_entries, dhcp_leases, ipv6_leases, fdb);

	return {
		hosts,
		wifi_assocs,
		ap_ifnames,
		fdb,
		config: _root,
		netifd_ifaces,
		leases_by_mac: dhcp_leases,
		snoop_by_mac: snoop,
		pool_client_paths: pool_paths
	};
}

/**
 * Builds and caches the merged host inventory for the given config root.
 *
 * @param {object} root - TR-181 config root (Device.*)
 * @returns {object} Cached host inventory from hosts_build_internal
 */
export function hosts_build(root) {
	_root = root;
	return cache_call(hosts_build_internal);
};

/**
 * Decides whether a host belongs to an upstream (WAN-side) interface.
 * Uses the host's primary IP to find the matching layer-3 interface.
 *
 * @param {object} host - Merged host record
 * @param {object} lookup - hosts_build_internal result with config and netifd_ifaces
 * @returns {boolean} true if the host is on an upstream interface
 */
function host_is_upstream(host, lookup) {
	let primary_ip = ubbf.host_primary_ip(host);
	let layer3 = ubbf.layer3_interface_find(lookup.config, primary_ip, lookup.netifd_ifaces);
	return layer3.upstream;
}

/**
 * Reads the ActiveLastChange state cache from disk.
 *
 * @returns {object} { entries: { MAC: { active, last_change, changed, seen, host } },
 *                     dirty: false, now: int }
 */
function hosts_state_load() {
	let state = { entries: {}, dirty: false, now: time() };

	let raw = fs.readfile(HOSTS_STATE_PATH);
	if (!raw)
		return state;

	try {
		let parsed = json(raw);
		if (type(parsed) == 'object' && type(parsed.entries) == 'object')
			state.entries = parsed.entries;
	} catch (e) {
	}

	return state;
}

/**
 * Returns the per-request cached hosts state object.
 *
 * @returns {object} State object shared for the current request cycle
 */
export function hosts_state_get() {
	return cache_call(hosts_state_load);
};

/**
 * Records the current Active state for a MAC and returns the timestamp of the
 * last observed transition. First sighting anchors last_change to "now".
 * While the host is active, the state keeps the last time it was seen and
 * a snapshot of its row, which hosts_downstream_get() lists after the host
 * left, with Active false, until HOSTS_STATE_TTL.
 *
 * @param {object} state - State from hosts_state_get()
 * @param {string} mac - Upper-case MAC
 * @param {boolean} active - Currently-observed active flag
 * @param {object} snapshot - What to show while the host is away
 * @returns {string} ISO 8601 timestamp of the last Active transition
 */
export function host_active_track(state, mac, active, snapshot) {
	let entry = state.entries[mac];
	if (!entry || entry.active != active) {
		entry = {
			...(entry ?? {}),
			active: active,
			last_change: ubbf.iso8601_format(state.now),
			changed: state.now
		};
		state.entries[mac] = entry;
		state.dirty = true;
	}

	if (!active)
		return entry.last_change;

	// The state lives in /tmp; a write per minute keeps seen exact enough
	// for a TTL of days.
	if (state.now - (entry.seen ?? 0) >= 60) {
		entry.seen = state.now;
		state.dirty = true;
	}

	if (snapshot && sprintf('%J', snapshot) != sprintf('%J', entry.host)) {
		entry.host = snapshot;
		state.dirty = true;
	}

	return entry.last_change;
};

/**
 * Returns the hosts that are in the state of the last HOSTS_STATE_TTL
 * seconds but not on the LAN now, built from their snapshot.
 *
 * @param {object} state - State from hosts_state_get()
 * @param {array} present - Hosts that are on the LAN now
 * @returns {array} Host records with active false
 */
function hosts_away_get(state, present) {
	let seen = {};
	let away = [];

	for (let host in present)
		seen[host.mac] = true;

	for (let mac, entry in state.entries) {
		if (seen[mac] || !entry.host || state.now - (entry.seen ?? 0) >= HOSTS_STATE_TTL)
			continue;

		push(away, { ...entry.host, mac, active: false });
	}

	return away;
}

/**
 * Returns the time from which a host of the state counts as inactive: its
 * last transition, or now while the state still has it active (a host that
 * left since the last read of the table).
 *
 * @param {object} state - State from hosts_state_get()
 * @param {string} mac - Upper-case MAC
 * @returns {number} UNIX time
 */
function host_inactive_since(state, mac) {
	let entry = state.entries[mac];
	return entry.active ? state.now : entry.changed;
}

/**
 * Removes the away hosts that are inactive longest from the state until
 * at most `keep` of them are left (Device.Hosts.CleanupHostsThreshold).
 *
 * @param {object} state - State from hosts_state_get()
 * @param {array} away - Hosts from hosts_away_get()
 * @param {number} keep - Number of away hosts to keep
 * @returns {array} The away hosts that are kept
 */
function hosts_away_trim(state, away, keep) {
	if (length(away) <= keep)
		return away;

	let by_age = sort([...away], (a, b) =>
		host_inactive_since(state, a.mac) - host_inactive_since(state, b.mac));
	let drop = length(away) - keep;

	for (let i = 0; i < drop; i++)
		delete state.entries[by_age[i].mac];
	state.dirty = true;

	return slice(by_age, drop);
}

/**
 * Returns the hosts on downstream (LAN-side) interfaces now.
 *
 * @param {object} root - TR-181 config root (Device.*)
 * @returns {array} Host records excluding upstream hosts
 */
function hosts_present_get(root) {
	let data = hosts_build(root);
	return filter(data.hosts, (host) => !host_is_upstream(host, data));
}

/**
 * Returns hosts attached to downstream (LAN-side) interfaces only, sorted
 * by MAC address: the hosts on the LAN now, and the hosts that left within
 * HOSTS_STATE_TTL with Active false. If the table has more rows than
 * Device.Hosts.CleanupHostsThreshold, the hosts that left first go. The
 * position is the Device.Hosts.Host instance number; the merge order
 * follows the ARP table, which the kernel hashes with a seed chosen at boot.
 *
 * @param {object} root - TR-181 config root (Device.*)
 * @returns {array} Filtered host records excluding upstream hosts
 */
export function hosts_downstream_get(root) {
	let present = hosts_present_get(root);
	let state = hosts_state_get();
	let away = hosts_away_get(state, present);
	let threshold = ubbf.to_int(root?.Device?.Hosts?.CleanupHostsThreshold) ?? -1;

	if (threshold >= 0)
		away = hosts_away_trim(state, away, max(threshold - length(present), 0));

	let hosts = [...present, ...away];

	return sort(hosts, (a, b) => (a.mac < b.mac) ? -1 : ((a.mac > b.mac) ? 1 : 0));
};

/**
 * Returns the downstream hosts keyed by their Device.Hosts.Host instance
 * number. A host keeps its number while others come and go (TR-369
 * R-ARC.8); the map lives in /tmp, since a reboot clears the table.
 *
 * @param {object} root - TR-181 config root (Device.*)
 * @returns {object} Instance number to host record
 */
export function hosts_numbered(root) {
	let hosts = hosts_downstream_get(root);
	let by_mac = {};
	for (let h in hosts)
		by_mac[h.mac] = h;

	return instance_rows(HOSTS_TABLE, map(hosts, (h) => h.mac), (mac) => by_mac[mac]);
};

/**
 * Returns the downstream host with an instance number.
 *
 * @param {object} root - TR-181 config root (Device.*)
 * @param {*} instance - Instance number
 * @returns {object|null} Host record
 */
export function host_by_instance(root, instance) {
	return hosts_numbered(root)[sprintf('%d', ubbf.to_int(instance) ?? 0)];
};

/**
 * Flushes the hosts state cache to disk if dirty, pruning entries that have
 * not been seen for HOSTS_STATE_TTL seconds. Callers pass the state object
 * they mutated so the flush is independent of the request-scope cache.
 *
 * @param {object} state - State from hosts_state_get()
 */
export function hosts_state_flush(state) {
	if (!state)
		return;

	let cutoff = state.now - HOSTS_STATE_TTL;
	let pruned = {};

	for (let mac, entry in state.entries) {
		if ((entry.seen ?? state.now) < cutoff) {
			state.dirty = true;
			continue;
		}
		pruned[mac] = entry;
	}

	if (!state.dirty)
		return;

	state.entries = pruned;
	fs.mkdir('/tmp/ubbf');
	fs.writefile(HOSTS_STATE_PATH, sprintf('%J', { entries: pruned }));
	state.dirty = false;
};

/**
 * Removes the hosts that left the LAN from the state, all of them or only
 * those inactive for longer than `min_time` (Device.Hosts.RemoveInactiveHosts()).
 * These are the rows with Active false; a host that hosts_merge() finds
 * on the LAN is active.
 *
 * @param {object} root - TR-181 config root (Device.*)
 * @param {number|null} min_time - Seconds of inactivity, or null for all
 * @returns {number} Number of hosts removed
 */
export function hosts_inactive_remove(root, min_time) {
	let state = hosts_state_get();
	let removed = 0;

	for (let host in hosts_away_get(state, hosts_present_get(root))) {
		if (min_time != null && state.now - host_inactive_since(state, host.mac) <= min_time)
			continue;

		delete state.entries[host.mac];
		removed++;
	}

	if (removed)
		state.dirty = true;
	hosts_state_flush(state);

	return removed;
};

/**
 * Resolves an IPv4 or IPv6 address to its TR-181 Device.Hosts.Host.{i}
 * path. The addresses compare in canonical form; a zone after '%' is
 * ignored.
 *
 * @param {object} root - TR-181 config root (Device.*)
 * @param {string} ip - IP address
 * @returns {string} TR-181 host instance path, or empty string if not found
 */
export function host_path_by_ip(root, ip) {
	let want = iptoarr(split(ip ?? '', '%')[0]);
	if (!want)
		return '';

	want = arrtoip(want);

	for (let n, h in hosts_numbered(root)) {
		for (let addr in [ ...(h.ipv4_addresses ?? []), ...(h.ipv6_addresses ?? []) ]) {
			let a = iptoarr(split(addr ?? '', '%')[0]);
			if (a && arrtoip(a) == want)
				return `Device.Hosts.Host.${n}`;
		}
	}

	return '';
};

/**
 * Resolves a MAC address to its TR-181 Device.Hosts.Host.{i} path.
 *
 * @param {object} root - TR-181 config root (Device.*)
 * @param {string} mac - MAC address (any case)
 * @returns {string} TR-181 host instance path, or empty string if not found
 */
export function host_path_by_mac(root, mac) {
	if (!mac)
		return '';

	mac = uc(mac);
	let n = instance_numbers(HOSTS_TABLE, map(hosts_downstream_get(root), (h) => h.mac))[mac];

	return (n != null) ? `Device.Hosts.Host.${n}` : '';
};
