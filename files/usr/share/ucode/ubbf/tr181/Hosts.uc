'use strict';

import * as schemas from 'ubbf.schemas.Hosts';
import * as ubbf from 'ubbf';
import { stats_get as nlbwmon_stats_get } from 'ubbf.utils.nlbwmon';
import {
	hosts_build,
	hosts_downstream_get,
	hosts_state_get,
	host_active_track,
	hosts_state_flush
} from 'ubbf.utils.hosts';
import { dhcp_option_value, hex_to_printable } from 'ubbf.utils.dhcp';

const DHCP_OPT_VENDOR_CLASS = 60;
const DHCP_OPT_CLIENT_ID = 61;
const DHCP_OPT_USER_CLASS = 77;

/**
 * Finds the Layer1Interface path for a host.
 *
 * @param {object} config - Full ubbf config
 * @param {string} mac - MAC address
 * @param {object} wifi_assocs - WiFi associations map
 * @param {object} fdb - Bridge FDB map
 * @returns {string} Layer1Interface path or empty string
 */
function layer1_interface_find(config, mac, wifi_assocs, fdb) {
	if (!config)
		return '';

	let wifi = wifi_assocs[mac];
	if (wifi)
		return sprintf('Device.WiFi.SSID.%d', wifi.ssid_instance);

	let port = fdb[mac];
	if (!port)
		return '';

	// iterate directly: ubbf.instances() would annotate the live tree
	// with .instance/.path keys that leak into later responses
	let eth_interfaces = config.Device?.Ethernet?.Interface ?? {};
	for (let key, iface in eth_interfaces) {
		if (!ubbf.is_instance_key(key) || type(iface) != 'object')
			continue;
		if (iface.Name != port)
			continue;
		return sprintf('Device.Ethernet.Interface.%s', key);
	}

	return '';
}

/**
 * Determines the interface type for a host.
 *
 * @param {string} mac - MAC address
 * @param {object} wifi_assocs - WiFi associations map
 * @param {object} fdb - Bridge FDB map
 * @returns {string} InterfaceType: Ethernet, WiFi, or Other
 */
function interface_type_get(mac, wifi_assocs, fdb) {
	if (wifi_assocs[mac])
		return 'WiFi';

	if (fdb[mac])
		return 'Ethernet';

	return 'Other';
}

/**
 * Gets the AssociatedDevice path for a WiFi client.
 *
 * The SSID instance from ubbf_ssid cannot be used as the AccessPoint
 * instance directly; the two only coincide while SSIDs and APs are created
 * in lockstep. Resolve the AP through the SSIDReference-derived map.
 *
 * @param {string} mac - MAC address
 * @param {object} wifi_assocs - WiFi associations map
 * @param {object} ap_by_ssid - Map of SSID instance to AccessPoint instance
 * @returns {string} AssociatedDevice path or empty string
 */
function associated_device_get(mac, wifi_assocs, ap_by_ssid) {
	let wifi = wifi_assocs[mac];
	if (!wifi)
		return '';

	let ap_inst = ap_by_ssid[sprintf('%d', wifi.ssid_instance)];
	if (!ap_inst)
		return '';

	return sprintf('Device.WiFi.AccessPoint.%s.AssociatedDevice.%d',
		ap_inst, wifi.sta_index);
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
 * Computes LeaseTimeRemaining in seconds per TR-181 Device.Hosts.Host.{i}.
 *
 * @param {object} lease - Lease object from leases_by_mac, or null
 * @param {number} now - Current UNIX epoch
 * @returns {number} Seconds remaining, 0 when there is no future lease
 */
function lease_remaining_get(lease, now) {
	if (!lease || lease.expiry == null)
		return 0;
	if (lease.expiry <= now)
		return 0;
	return lease.expiry - now;
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
		let primary_ip = ubbf.host_primary_ip(host);
		let now = state.now;

		let lease = lookup.leases_by_mac?.[mac];
		let lease_remaining = lease_remaining_get(lease, now);

		let snoop_entry = lookup.snoop_by_mac?.[lc(mac)];
		let snoop_opts = snoop_entry?.options ?? [];

		let vendor_class = hex_to_printable(
			dhcp_option_value(snoop_opts, DHCP_OPT_VENDOR_CLASS));
		let client_id = dhcp_option_value(snoop_opts, DHCP_OPT_CLIENT_ID);
		let user_class = dhcp_option_value(snoop_opts, DHCP_OPT_USER_CLASS);

		let dhcp_client = lookup.pool_client_paths?.[mac] ?? '';

		let associated_device = associated_device_get(mac, lookup.wifi_assocs,
			lookup.ap_by_ssid);
		let layer1 = layer1_interface_find(lookup.config, mac,
			lookup.wifi_assocs, lookup.fdb);
		let layer3 = ubbf.layer3_interface_find(lookup.config, primary_ip,
			lookup.netifd_ifaces);
		let iface_type = interface_type_get(mac, lookup.wifi_assocs, lookup.fdb);

		let active = host.active ? true : false;
		let active_last_change = host_active_track(state, mac, active);

		let result = {
			...schemas.Host.defaults,
			Alias: ubbf.alias_from_mac(mac),
			PhysAddress: mac,
			IPAddress: primary_ip,
			AddressSource: host.address_source,
			DHCPClient: dhcp_client,
			LeaseTimeRemaining: sprintf('%d', lease_remaining),
			HostName: host.hostname,
			Active: active ? 'true' : 'false',
			ActiveLastChange: active_last_change,
			AssociatedDevice: associated_device,
			Layer1Interface: layer1,
			Layer3Interface: layer3.path,
			InterfaceType: iface_type,
			VendorClassID: vendor_class,
			ClientID: client_id,
			UserClassID: user_class,
			IPv4AddressNumberOfEntries: sprintf('%d', length(host.ipv4_addresses)),
			IPv6AddressNumberOfEntries: sprintf('%d', length(host.ipv6_addresses)),
			IPv4Address: ubbf.enumerate_instances(host.ipv4_addresses, address_to_object),
			IPv6Address: ubbf.enumerate_instances(host.ipv6_addresses, address_to_object)
		};

		if (nlbwmon_stats[mac])
			result.WANStats = wanstats_build(mac, nlbwmon_stats);

		return result;
	};
}

/**
 * Get handler for Device.Hosts.AccessControl.{i}.
 *
 * @param {object} ctx - Context with instance number
 * @returns {object} AccessControl entry with computed ScheduleNumberOfEntries
 */
function access_control_get(ctx) {
	return {
		...ubbf.ctx_config(ctx),
		ScheduleNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config?.Schedule))
	};
}

/**
 * Get handler for Device.Hosts.
 *
 * @param {object} ctx - Context object
 * @returns {object} Hosts container with enumerated Host entries
 */
function hosts_get(ctx) {
	let data = hosts_build(ctx.root);
	let filtered_hosts = hosts_downstream_get(ctx.root);
	let state = hosts_state_get();
	let converter = host_converter_create(data, state);

	let result = {
		Host: ubbf.enumerate_instances(filtered_hosts, converter),
		HostNumberOfEntries: sprintf('%d', length(filtered_hosts)),
		AccessControlNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config?.AccessControl))
	};

	hosts_state_flush(state);
	return result;
}

/**
 * Get handler for Device.Hosts.Host.{i}.
 *
 * @param {object} ctx - Context with optional instance number
 * @returns {object|null} Single host or enumerated hosts
 */
function host_get(ctx) {
	let data = hosts_build(ctx.root);
	let filtered_hosts = hosts_downstream_get(ctx.root);
	let state = hosts_state_get();
	let converter = host_converter_create(data, state);

	let result;
	if (ctx.instance == null) {
		result = ubbf.enumerate_instances(filtered_hosts, converter);
	}
	else {
		let host = ubbf.get_by_instance(filtered_hosts, ctx.instance);
		if (!host)
			return null;
		result = converter(host);
	}

	hosts_state_flush(state);
	return result;
}

/**
 * Get handler for Device.Hosts.Host.{i}.WANStats.
 *
 * @param {object} ctx - Context with instance number
 * @returns {object|null} WANStats object or null if host not found
 */
function wanstats_get(ctx) {
	let filtered_hosts = hosts_downstream_get(ctx.root);
	let host = ubbf.get_by_instance(filtered_hosts, ctx.instance);
	if (!host)
		return null;

	return wanstats_build(host.mac, nlbwmon_stats_get());
}

export const model = {
	'Device.Hosts': {
		schema: schemas.Hosts,
		get: hosts_get
	},

	'Device.Hosts.Host': {
	},

	'Device.Hosts.Host.{i}': {
		schema: schemas.Host,
		get: host_get
	},

	'Device.Hosts.Host.{i}.IPv4Address': {
	},

	'Device.Hosts.Host.{i}.IPv4Address.{i}': {
		schema: schemas.Host_IPv4Address
	},

	'Device.Hosts.Host.{i}.IPv6Address': {
	},

	'Device.Hosts.Host.{i}.IPv6Address.{i}': {
		schema: schemas.Host_IPv6Address
	},

	'Device.Hosts.Host.{i}.WANStats': {
		schema: schemas.Host_WANStats,
		get: wanstats_get
	},

	'Device.Hosts.AccessControl': {
	},

	'Device.Hosts.AccessControl.{i}': {
		schema: schemas.AccessControl,
		get: access_control_get
	},

	'Device.Hosts.AccessControl.{i}.Schedule': {
	},

	'Device.Hosts.AccessControl.{i}.Schedule.{i}': {
		schema: schemas.AccessControl_Schedule
	}
};
