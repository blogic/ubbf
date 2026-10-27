'use strict';

import * as ubus from 'ubus';
import * as ubbf from 'ubbf';
import {
	ipv6_leases_get,
	pool_leases_numbered,
	ipv6_pool_clients_numbered,
	dhcpsnoop_dump_get
} from 'ubbf.utils.dhcp';
import { cache_call } from 'ubbf';
import { wireless_status_get, assoclist_get, station_number } from 'ubbf.utils.wifi';
import { instance_numbers, instance_rows } from 'ubbf';

const HOSTS_TABLE = 'Device.Hosts.Host';

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
 * Fetches network.interface dump from netifd via ubus (uncached).
 *
 * @returns {array} Array of { name, addresses, ipv6_addresses } per interface
 */
function netifd_interfaces_fetch() {
	return ubbf.netifd_interfaces_build(ubus?.call('network.interface', 'dump'));
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
 * Builds the Hosts.Host.{i}.DHCPClient value of each MAC: the DHCPv4 and
 * the DHCPv6 pool client that own its leases, in the same numbering as
 * pool_client_get() of tr181/DHCPv4.uc and tr181/DHCPv6.uc.
 *
 * @param {object} root - TR-181 config root
 * @returns {object} Map of upper-case MAC to a list of up to two paths
 */
function pool_client_by_mac(root) {
	let v4 = {}, v6 = {};

	for (let inst, pool in root?.Device?.DHCPv4?.Server?.Pool ?? {}) {
		let base = `Device.DHCPv4.Server.Pool.${inst}`;
		v4[base] = pool_leases_numbered(base, pool);
	}

	for (let inst, pool in root?.Device?.DHCPv6?.Server?.Pool ?? {}) {
		let base = `Device.DHCPv6.Server.Pool.${inst}`;
		v6[base] = ipv6_pool_clients_numbered(base, root, pool);
	}

	return ubbf.pool_client_paths(v4, v6);
}

/**
 * Reads the host sources of the system: ARP, DHCP leases, IPv6
 * neighbours and leases, bridge FDB, WiFi associations, netifd
 * interfaces and the DHCP snoop. None of it depends on the config root.
 *
 * @returns {object} { hosts, wifi_assocs, ap_ifnames, fdb, netifd_ifaces,
 *                     leases_by_mac, snoop_by_mac }
 */
function hosts_scan() {
	let arp_entries = ubbf.arp_parse();
	let dhcp_leases = ubbf.hosts_leases_by_mac();
	let ipv6_leases = ubbf.ipv6_maps_merge(ipv6_leases_get(), ubbf.ipv6_neigh_parse());
	let fdb = cache_call(ubbf.bridge_fdb_parse);

	return {
		hosts: ubbf.hosts_merge(arp_entries, dhcp_leases, ipv6_leases, fdb),
		wifi_assocs: wifi_associations_get(),
		ap_ifnames: ubbf.hosts_ap_ssids(wireless_status_get() ?? {}),
		fdb,
		netifd_ifaces: netifd_interfaces_get(),
		leases_by_mac: dhcp_leases,
		snoop_by_mac: dhcpsnoop_dump_get()
	};
}

// The inventory of the last hosts_build() call, valid while the cached
// scan and the config root are the same objects. A cache_call() key
// would serialise the whole root on each call.
let built = { scan: null, root: null, data: null };

/**
 * Builds the merged host inventory for a config root: the cached scan of
 * the system plus the AccessPoint of each WiFi association and the
 * DHCP client paths, which depend on the root.
 *
 * @param {object} root - TR-181 config root (Device.*)
 * @returns {object} { hosts, wifi_assocs, ap_ifnames, fdb, config,
 *                     netifd_ifaces, leases_by_mac, snoop_by_mac,
 *                     pool_client_paths }
 */
export function hosts_build(root) {
	let scan = cache_call(hosts_scan);
	if (built.scan === scan && built.root === root)
		return built.data;

	let ap_by_ssid = ubbf.ap_by_ssid_instance(root);
	let wifi_assocs = {};
	for (let mac, wifi in scan.wifi_assocs) {
		let ap_instance = ap_by_ssid[sprintf('%d', wifi.ssid_instance)];
		wifi_assocs[mac] = { ...wifi, ap_instance };
		if (ap_instance)
			wifi_assocs[mac].sta_number = station_number(ap_instance, mac);
	}

	let data = {
		...scan,
		wifi_assocs,
		config: root,
		pool_client_paths: pool_client_by_mac(root)
	};

	built = { scan, root, data };
	return data;
};

/**
 * Decides whether a host belongs to an upstream (WAN-side) interface.
 * Uses the host's primary IP to find the matching layer-3 interface.
 *
 * @param {object} host - Merged host record
 * @param {object} lookup - hosts_build() result with config and netifd_ifaces
 * @returns {boolean} true if the host is on an upstream interface
 */
function host_is_upstream(host, lookup) {
	let primary_ip = ubbf.host_primary_ip(host);
	let layer3 = ubbf.layer3_interface_find(lookup.config, primary_ip, lookup.netifd_ifaces);
	return layer3.upstream;
}

/**
 * Returns the per-request cached hosts state object, see
 * hosts_state_load() in hosts.c of ubbf.so.
 *
 * @returns {object} State object shared for the current request cycle
 */
export function hosts_state_get() {
	return cache_call(ubbf.hosts_state_load);
};

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
 * by MAC address: the hosts on the LAN now, and the hosts that left with
 * Active false, see hosts_downstream_build() in hosts.c of ubbf.so. The
 * position is the Device.Hosts.Host instance number; the merge order
 * follows the ARP table, which the kernel hashes with a seed chosen at boot.
 *
 * @param {object} root - TR-181 config root (Device.*)
 * @returns {array} Filtered host records excluding upstream hosts
 */
export function hosts_downstream_get(root) {
	return ubbf.hosts_downstream_build(hosts_state_get(), hosts_present_get(root),
		root?.Device?.Hosts?.CleanupHostsThreshold);
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
	let removed = ubbf.hosts_inactive_drop(state, hosts_present_get(root), min_time);

	ubbf.hosts_state_flush(state);

	return removed;
};

/**
 * Resolves an IPv4 or IPv6 address to its TR-181 Device.Hosts.Host.{i}
 * path, see host_path_by_ip_find() in hosts.c of ubbf.so.
 *
 * @param {object} root - TR-181 config root (Device.*)
 * @param {string} ip - IP address
 * @returns {string} TR-181 host instance path, or empty string if not found
 */
export function host_path_by_ip(root, ip) {
	return ubbf.host_path_by_ip_find(hosts_numbered(root), ip);
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
