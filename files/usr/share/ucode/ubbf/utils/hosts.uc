'use strict';

import * as fs from 'fs';
import * as ubus from 'ubus';
import * as ubbf from 'ubbf';
import {
	leases_parse,
	ipv6_leases_get,
	leases_for_pool,
	dhcpsnoop_dump_get
} from 'ubbf.utils.dhcp';
import { call as cache_call } from 'ubbf.utils.cache';
import { wireless_status_get, assoclist_get } from 'ubbf.utils.wifi';

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
 * @returns {object} Map of uppercase MAC to { ssid_instance, sta_index }
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

			let sta_idx = 1;
			for (let mac, sta in stations) {
				result[uc(mac)] = {
					ssid_instance: int(ssid_inst),
					sta_index: sta_idx
				};
				sta_idx++;
			}
		}
	}

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
 * Builds a lookup from upper-case MAC to the path of the DHCPv4 pool client
 * entry that owns the lease. Walks every configured Device.DHCPv4.Server.Pool
 * and reuses leases_for_pool(), so the resulting client index matches the
 * enumeration order used by pool_client_get(). Reads the config directly to
 * avoid mutating pool objects (ubbf.instances adds .instance/.path fields).
 *
 * @param {object} root - TR-181 config root
 * @returns {object} Map of upper-case MAC to TR-181 pool client path
 */
function pool_client_by_mac(root) {
	let result = {};
	let pools = root?.Device?.DHCPv4?.Server?.Pool;
	if (type(pools) != 'object')
		return result;

	for (let pool_inst, pool in pools) {
		let leases = leases_for_pool(pool);
		for (let i = 0; i < length(leases); i++) {
			let mac = leases[i].mac;
			if (result[mac])
				continue;
			result[mac] = sprintf('Device.DHCPv4.Server.Pool.%s.Client.%d',
				pool_inst, i + 1);
		}
	}

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
 * @returns {object} { hosts, wifi_assocs, ap_by_ssid, fdb, config,
 *                     netifd_ifaces, leases_by_mac, snoop_by_mac,
 *                     pool_client_paths }
 */
function hosts_build_internal() {
	let arp_entries = ubbf.arp_parse();
	let dhcp_leases = leases_by_mac();
	let ipv6_leases = ipv6_maps_merge(ipv6_leases_get(), ubbf.ipv6_neigh_parse());
	let wifi_assocs = wifi_associations_get();
	let ap_by_ssid = ap_by_ssid_instance(_root);
	let fdb = cache_call(ubbf.bridge_fdb_parse);
	let netifd_ifaces = netifd_interfaces_get();
	let snoop = dhcpsnoop_dump_get();
	let pool_paths = pool_client_by_mac(_root);

	let hosts = ubbf.hosts_merge(arp_entries, dhcp_leases, ipv6_leases, fdb);

	return {
		hosts,
		wifi_assocs,
		ap_by_ssid,
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
 * Returns hosts attached to downstream (LAN-side) interfaces only.
 *
 * @param {object} root - TR-181 config root (Device.*)
 * @returns {array} Filtered host records excluding upstream hosts
 */
export function hosts_downstream_get(root) {
	let data = hosts_build(root);
	return filter(data.hosts, (host) => !host_is_upstream(host, data));
};

/**
 * Reads the ActiveLastChange state cache from disk.
 *
 * @returns {object} { entries: { MAC: { active, last_change } }, dirty: false,
 *                     now: int }
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
 *
 * @param {object} state - State from hosts_state_get()
 * @param {string} mac - Upper-case MAC
 * @param {boolean} active - Currently-observed active flag
 * @returns {string} ISO 8601 timestamp of the last Active transition
 */
export function host_active_track(state, mac, active) {
	let entry = state.entries[mac];
	if (!entry || entry.active != active) {
		entry = {
			active: active,
			last_change: ubbf.iso8601_format(state.now)
		};
		state.entries[mac] = entry;
		state.dirty = true;
	}
	entry.seen = state.now;
	return entry.last_change;
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
	let downstream = hosts_downstream_get(root);

	for (let i = 0; i < length(downstream); i++) {
		if (downstream[i].mac == mac)
			return sprintf('Device.Hosts.Host.%d', i + 1);
	}

	return '';
};
