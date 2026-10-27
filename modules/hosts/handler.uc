'use strict';

// Out-of-tree module. `ubbf_module` is the scope datamodel.uc includes this
// file with, and it is visible only while the include runs, so anything the
// handlers below use later has to be bound here. See docs/ARCHITECTURE.md.

const ubbf = ubbf_module.ubbf;
const utils = ubbf_module.utils;
const model = ubbf_module.model;
const operations = ubbf_module.operations;
const members = ubbf_module.members;
const log_warn = utils.logging.log_warn;

const fs = require('fs');

const schema = ubbf_module.schema;
const schema_defaults = ubbf_module.schema_defaults;

const DHCP_OPT_HOST_NAME = 12;
const HOST_NAME_MAX = 64;

/**
 * Fetches per-host traffic data from nlbwmon (uncached), one row per MAC.
 *
 * @returns {object} Map of MAC address to traffic counters
 */
function nlbwmon_stats_fetch() {
	let result = {};

	let p = fs.popen('nlbw -c json -g mac 2>/dev/null', 'r');
	if (!p)
		return result;

	let output = p.read('all');
	p.close();

	let data;
	try {
		data = json(output ?? '');
	} catch (e) {
		return result;
	}

	let col = {};
	for (let i, name in data?.columns ?? [])
		col[name] = i;

	if (col.mac == null)
		return result;

	for (let row in data.data ?? []) {
		let mac = uc(row[col.mac] ?? '');
		if (mac == '')
			continue;

		result[mac] = {
			bytes_sent: int(row[col.tx_bytes]) ?? 0,
			bytes_received: int(row[col.rx_bytes]) ?? 0,
			packets_sent: int(row[col.tx_pkts]) ?? 0,
			packets_received: int(row[col.rx_pkts]) ?? 0
		};
	}

	return result;
}

/**
 * Gets per-host traffic data from nlbwmon (cached).
 *
 * @returns {object} Map of MAC address to traffic counters
 */
function nlbwmon_stats_get() {
	return utils.cache.call(nlbwmon_stats_fetch);
}

/**
 * Finds the Layer1Interface path and the InterfaceType of an active host:
 * Wi-Fi when the association list has it or its FDB port is an access
 * point, Ethernet when the port is a Device.Ethernet.Interface, else Other.
 *
 * @param {string} mac - MAC address
 * @param {object} lookup - Interface lookup data from hosts_build
 * @returns {object} { layer1, type }
 */
function host_interface_find(mac, lookup) {
	let wifi = lookup.wifi_assocs[mac];
	if (wifi)
		return { layer1: sprintf('Device.WiFi.SSID.%d', wifi.ssid_instance), type: 'Wi-Fi' };

	let port = lookup.fdb[mac];
	let ssid = port ? lookup.ap_ifnames[port] : null;
	if (ssid)
		return { layer1: sprintf('Device.WiFi.SSID.%d', ssid), type: 'Wi-Fi' };

	let ethernet = (port && lookup.config) ? utils.path.ethernet_interface_path(lookup.config, port) : '';
	if (ethernet != '')
		return { layer1: ethernet, type: 'Ethernet' };

	return { layer1: '', type: 'Other' };
}

/**
 * Gets the AssociatedDevice path for a WiFi client.
 *
 * hosts_build() resolves the AccessPoint of the station's SSID through
 * SSIDReference and numbers the station on that AccessPoint.
 *
 * @param {string} mac - MAC address
 * @param {object} wifi_assocs - WiFi associations map
 * @returns {string} AssociatedDevice path or empty string
 */
function associated_device_get(mac, wifi_assocs) {
	let wifi = wifi_assocs[mac];
	if (!wifi?.ap_instance || wifi.sta_number == null)
		return '';

	return sprintf('Device.WiFi.AccessPoint.%s.AssociatedDevice.%d',
		wifi.ap_instance, wifi.sta_number);
}

/**
 * Converts an IP address string to TR-181 address object.
 *
 * @param {string} addr - IP address string
 * @returns {object} Object with IPAddress property
 */
function address_to_object(addr) {
	return { IPAddress: addr };
}

/**
 * Builds WANStats object for a host.
 *
 * @param {string} mac - MAC address (uppercase)
 * @param {object} stats - nlbwmon stats map
 * @returns {object} WANStats object
 */
function wanstats_build(mac, stats) {
	let host_stats = stats[mac];
	return {
		BytesSent: sprintf('%d', host_stats?.bytes_sent ?? 0),
		BytesReceived: sprintf('%d', host_stats?.bytes_received ?? 0),
		PacketsSent: sprintf('%d', host_stats?.packets_sent ?? 0),
		PacketsReceived: sprintf('%d', host_stats?.packets_received ?? 0),
		ErrorsSent: '0',
		RetransCount: '0',
		DiscardPacketsSent: '0'
	};
}

/**
 * Returns the host name of a host: the name of its dnsmasq lease, else
 * the Host Name option (12) that udhcpsnoop saw in its DHCP request.
 *
 * @param {object} host - Merged host record
 * @param {object} lookup - Interface lookup data from hosts_build
 * @returns {string} Host name, at most 64 characters
 */
function host_name_get(host, lookup) {
	let name = host.hostname ?? '';

	if (name == '') {
		let snoop = lookup.snoop_by_mac?.[lc(host.mac)];
		name = utils.dhcp.hex_to_printable(
			utils.dhcp.dhcp_option_value(snoop?.options ?? [], DHCP_OPT_HOST_NAME));
	}

	return substr(name, 0, HOST_NAME_MAX);
}

/**
 * Creates a converter function for host objects with interface lookup data.
 *
 * @param {object} lookup - Interface lookup data from hosts_build
 * @param {object} state - Hosts state from hosts_state_get()
 * @returns {function} Converter function for enumerate_instances
 */
function host_converter_create(lookup, state) {
	let nlbwmon_stats = nlbwmon_stats_get();

	return function(host) {
		let mac = host.mac;
		let active = host.active ? true : false;
		let primary_ip = ubbf.host_primary_ip(host);
		let iface = active ? host_interface_find(mac, lookup)
		                   : { layer1: host.layer1 ?? '', type: host.iface_type ?? 'Other' };
		let host_name = active ? host_name_get(host, lookup) : (host.hostname ?? '');
		let layer3 = ubbf.layer3_interface_find(lookup.config, primary_ip,
			lookup.netifd_ifaces);

		let active_last_change = utils.hosts.host_active_track(state, mac, active, {
			ipv4_addresses: host.ipv4_addresses,
			ipv6_addresses: host.ipv6_addresses,
			hostname: host_name,
			layer1: iface.layer1,
			iface_type: iface.type
		});

		return {
			...schema_defaults('Host'),
			PhysAddress: mac,
			IPAddress: primary_ip,
			DHCPClient: lookup.pool_client_paths?.[mac] ?? '',
			HostName: host_name,
			Active: active ? 'true' : 'false',
			ActiveLastChange: active_last_change,
			AssociatedDevice: active ? associated_device_get(mac, lookup.wifi_assocs) : '',
			Layer1Interface: iface.layer1,
			Layer3Interface: layer3.path,
			InterfaceType: iface.type,
			IPv4AddressNumberOfEntries: sprintf('%d', length(host.ipv4_addresses)),
			IPv6AddressNumberOfEntries: sprintf('%d', length(host.ipv6_addresses)),
			IPv4Address: ubbf.enumerate_instances(host.ipv4_addresses, address_to_object),
			IPv6Address: ubbf.enumerate_instances(host.ipv6_addresses, address_to_object),
			WANStats: wanstats_build(mac, nlbwmon_stats)
		};
	};
}

/**
 * Get handler for Device.Hosts.Host.{i}.
 *
 * @param {object} ctx - Context with optional instance number
 * @returns {object|null} Single host or enumerated hosts
 */
function host_get(ctx) {
	let data = utils.hosts.hosts_build(ctx.root);
	let numbered = utils.hosts.hosts_numbered(ctx.root);
	let state = utils.hosts.hosts_state_get();
	let converter = host_converter_create(data, state);

	let result;
	if (ctx.instance == null) {
		result = {};
		for (let n, host in numbered)
			result[n] = converter(host);
	}
	else {
		let host = numbered[sprintf('%d', ctx.instance)];
		if (!host)
			return null;
		result = converter(host);
	}

	utils.hosts.hosts_state_flush(state);
	return result;
}

/**
 * Get handler for Device.Hosts.Host.{i}.WANStats.
 *
 * @param {object} ctx - Context with instance number
 * @returns {object|null} WANStats object or null if host not found
 */
function wanstats_get(ctx) {
	let host = utils.hosts.host_by_instance(ctx.root, ctx.instance);
	if (!host)
		return null;

	return wanstats_build(host.mac, nlbwmon_stats_get());
}

/**
 * Sync operation handler for Device.Hosts.RemoveInactiveHosts().
 *
 * @param {object} input - Optional MinimumInactiveTime in seconds
 * @param {string} command_key - USP command key
 * @param {object} root - Runtime tree
 * @returns {object|number} NumberOfRemovedHosts, or a negative USP error code
 */
function remove_inactive_hosts(input, command_key, root) {
	let raw = input?.MinimumInactiveTime;
	let given = raw != null && raw !== '';
	let min_time = given ? ubbf.to_int(raw) : null;

	if (given && (min_time == null || min_time < 0)) {
		log_warn('Hosts.RemoveInactiveHosts(): invalid MinimumInactiveTime %s', raw);
		return -USP_ERR_INVALID_COMMAND_ARGS;
	}

	return { NumberOfRemovedHosts: sprintf('%d', utils.hosts.hosts_inactive_remove(root, min_time)) };
}

model['Device.Hosts.Host'] = {};

// The table lists what the device sees; an added row would hide the live
// rows (docs/ARCHITECTURE.md, "Tables under a core parent").
model['Device.Hosts.Host.{i}'] = {
	schema: schema('Host'),
	get: host_get,
	maxInstances: 0
};

model['Device.Hosts.Host.{i}.IPv4Address'] = {};

model['Device.Hosts.Host.{i}.IPv4Address.{i}'] = {
	schema: schema('Host_IPv4Address')
};

model['Device.Hosts.Host.{i}.IPv6Address'] = {};

model['Device.Hosts.Host.{i}.IPv6Address.{i}'] = {
	schema: schema('Host_IPv6Address')
};

model['Device.Hosts.Host.{i}.WANStats'] = {
	schema: schema('Host_WANStats'),
	get: wanstats_get
};

members['Device.Hosts'] = schema('Hosts_Commands');

operations['Device.Hosts.RemoveInactiveHosts()'] = {
	type: 'sync',
	handler: remove_inactive_hosts
};
