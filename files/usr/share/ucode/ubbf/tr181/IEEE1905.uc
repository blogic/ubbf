'use strict';

import * as schemas from 'ubbf.schemas.IEEE1905';
import * as ubus from 'ubus';
import * as ubbf from 'ubbf';
import { call as cache_call } from 'ubbf.utils.cache';

const MEDIA_TYPE_CODE_MAP = {
	[0x0000]: "IEEE 802.3u",
	[0x0001]: "IEEE 802.3ab",
	[0x0100]: "IEEE 802.11b",
	[0x0101]: "IEEE 802.11g",
	[0x0102]: "IEEE 802.11a",
	[0x0103]: "IEEE 802.11n 2.4",
	[0x0104]: "IEEE 802.11n 5.0",
	[0x0105]: "IEEE 802.11ac",
	[0x0106]: "IEEE 802.11ad",
	[0x0107]: "IEEE 802.11af",
	[0x0108]: "IEEE 802.11ax",
	[0x0109]: "IEEE 802.11be",
	[0x0200]: "IEEE 1901 Wavelet",
	[0x0201]: "IEEE 1901 FFT",
	[0x0300]: "MoCAv1.1",
	[0xFFFF]: "Generic PHY",
};

const ROLE_MAP = {
	"AP": "AP",
	"STA": "non-AP/non-PCP STA",
	"P2P_CLIENT": "non-AP/non-PCP STA",
	"P2P_GO": "AP",
};

/**
 * Fetches topology data from umapd via ubus.
 *
 * @returns {object|null} Topology data with devices and links
 */
function topology_fetch() {
	return ubus?.call('umap', 'get_topology', {})
		?? ubus?.call('umap-agent', 'get_topology', {});
}

/**
 * Gets cached topology data.
 *
 * @returns {object|null} Topology data
 */
function topology_get() {
	return cache_call(topology_fetch);
}

/**
 * Builds a lookup map of AL MAC to the 1-based IEEE1905Device index used in
 * Device.IEEE1905.AL.NetworkTopology.IEEE1905Device.{i}.
 *
 * @returns {object} Map of AL MAC -> 1-based index
 */
export function al_index_map() {
	let topo = topology_get();
	let devices = topo?.devices ?? [];
	let result = {};
	for (let i = 0; i < length(devices); i++) {
		let al_mac = devices[i].al_address;
		if (al_mac)
			result[al_mac] = i + 1;
	}
	return result;
};

/**
 * Builds a TR-181 reference path to an interface within a topology device.
 *
 * @param {number} dev_idx - 1-based device instance number
 * @param {array} ifaces - Array of interface objects for the device
 * @param {string} target_mac - MAC address to find
 * @returns {string} TR-181 reference path or empty string
 */
function interface_ref_build(dev_idx, ifaces, target_mac) {
	if (!target_mac || !ifaces)
		return "";

	for (let i = 0; i < length(ifaces); i++) {
		if (ifaces[i].local_if_mac_address == target_mac)
			return `Device.IEEE1905.AL.NetworkTopology.IEEE1905Device.${dev_idx}.Interface.${i + 1}.`;
	}

	return "";
}

/**
 * Resolves a remote interface MAC to the AL MAC that owns it.
 *
 * @param {array} devices - All devices in topology
 * @param {string} remote_mac - Remote interface MAC address
 * @returns {string} AL MAC address of the owning device or empty string
 */
function neighbor_al_resolve(devices, remote_mac) {
	if (!devices || !remote_mac)
		return "";

	for (let dev in devices)
		for (let iface in dev.interfaces)
			if (iface.local_if_mac_address == remote_mac)
				return dev.al_address ?? "";

	return "";
}

/**
 * Converts link metric data to TR-181 Metric object.
 *
 * @param {object} link - Link data from topology
 * @returns {object} TR-181 formatted Metric object
 */
function link_metric_to_object(link) {
	return {
		IEEE802dot1Bridge: link.is_bridge ? "true" : "false",
		PacketErrors: sprintf('%d', link.tx_errors ?? 0),
		PacketErrorsReceived: sprintf('%d', link.rx_errors ?? 0),
		TransmittedPackets: sprintf('%d', link.tx_packets ?? 0),
		PacketsReceived: sprintf('%d', link.rx_packets ?? 0),
		MACThroughputCapacity: sprintf('%d', link.throughput ?? 0),
		LinkAvailability: sprintf('%d', link.availability ?? 0),
		PHYRate: sprintf('%d', link.speed ?? 0),
		RSSI: sprintf('%d', link.rssi ?? 0),
	};
}

/**
 * Converts a link entry to TR-181 Link object.
 *
 * @param {string} remote_mac - Remote interface MAC address
 * @param {object} link - Link data
 * @param {array} devices - All topology devices
 * @returns {object} TR-181 formatted Link object
 */
function link_to_object(remote_mac, link, devices) {
	return {
		InterfaceId: remote_mac,
		IEEE1905Id: neighbor_al_resolve(devices, remote_mac),
		MediaType: MEDIA_TYPE_CODE_MAP[link.media_type] ?? "",
		GenericPhyOUI: "",
		GenericPhyURL: "",
		Metric: link_metric_to_object(link),
	};
}

/**
 * Converts a local device interface to TR-181 AL.Interface object.
 *
 * @param {object} iface - Interface data from topology
 * @param {array} devices - All topology devices
 * @returns {object} TR-181 formatted Interface object
 */
function al_interface_to_object(iface, devices) {
	let links = {};
	let link_count = 0;

	for (let remote_mac, link_data in iface.links) {
		links[sprintf('%d', ++link_count)] = link_to_object(remote_mac, link_data, devices);
	}

	return {
		InterfaceId: iface.local_if_mac_address ?? "",
		Status: "Up",
		LastChange: "0",
		LowerLayers: "",
		InterfaceStackReference: "",
		MediaType: MEDIA_TYPE_CODE_MAP[iface.media_type] ?? "",
		GenericPhyOUI: "",
		GenericPhyURL: "",
		PowerState: "On",
		VendorPropertiesNumberOfEntries: "0",
		LinkNumberOfEntries: sprintf('%d', link_count),
		Link: links,
	};
}

/**
 * Converts a topology IPv4 address entry to TR-181 object.
 *
 * @param {string} if_mac - Interface MAC address
 * @param {object} entry - IPv4 address entry
 * @returns {object} TR-181 formatted IPv4Address object
 */
function topo_ipv4_to_object(if_mac, entry) {
	return {
		MACAddress: if_mac,
		IPv4Address: entry.address ?? "",
		IPv4AddressType: entry.ipv4addr_type_name ?? "",
		DHCPServer: entry.dhcp_server ?? "",
	};
}

/**
 * Converts a topology IPv6 address entry to TR-181 object.
 *
 * @param {string} if_mac - Interface MAC address
 * @param {object} entry - IPv6 address entry
 * @param {string} addr_type - Address type string
 * @returns {object} TR-181 formatted IPv6Address object
 */
function topo_ipv6_to_object(if_mac, entry, addr_type) {
	return {
		MACAddress: if_mac,
		IPv6Address: entry.address ?? "",
		IPv6AddressType: addr_type ?? "",
		IPv6AddressOrigin: entry.origin ?? "",
	};
}

/**
 * Converts a topology device interface to TR-181 IEEE1905Device.Interface object.
 *
 * @param {object} iface - Interface data from topology
 * @returns {object} TR-181 formatted Interface object
 */
function topo_interface_to_object(iface) {
	let obj = {
		InterfaceId: iface.local_if_mac_address ?? "",
		MediaType: MEDIA_TYPE_CODE_MAP[iface.media_type] ?? "",
		PowerState: "On",
		GenericPhyOUI: "",
		GenericPhyURL: "",
	};

	let msi = iface.media_specific_information;
	if (msi) {
		obj.NetworkMembership = msi.bssid ?? "";
		obj.Role = ROLE_MAP[msi.role_name] ?? msi.role_name ?? "";
		obj.APChannelBand = sprintf('%02x', msi.bandwidth ?? 0);
		obj.FrequencyIndex1 = sprintf('%02x', msi.channel1 ?? 0);
		obj.FrequencyIndex2 = sprintf('%02x', msi.channel2 ?? 0);
	}

	return obj;
}

/**
 * Builds IEEE1905Neighbor metric instances from device metrics data.
 *
 * @param {object} dev - Device data
 * @param {string} local_if_mac - Local interface MAC
 * @param {string} neighbor_al_mac - Neighbour AL MAC
 * @returns {object} Enumerated Metric instances
 */
function topo_neighbor_metrics_build(dev, local_if_mac, neighbor_al_mac) {
	let metrics = {};
	let idx = 0;

	let tx_metrics = {};
	for (let tx_entry in dev.metrics?.tx) {
		if (tx_entry.neighbor_al_mac_address != neighbor_al_mac)
			continue;

		for (let lm in tx_entry.link_metrics) {
			if (lm.local_if_mac_address == local_if_mac)
				tx_metrics[lm.remote_if_mac_address] = lm;
		}
	}

	let rx_metrics = {};
	for (let rx_entry in dev.metrics?.rx) {
		if (rx_entry.neighbor_al_mac_address != neighbor_al_mac)
			continue;

		for (let lm in rx_entry.link_metrics) {
			if (lm.local_if_mac_address == local_if_mac)
				rx_metrics[lm.remote_if_mac_address] = lm;
		}
	}

	for (let remote_mac, tx in tx_metrics) {
		let rx = rx_metrics[remote_mac];
		metrics[sprintf('%d', ++idx)] = {
			NeighborMACAddress: remote_mac,
			IEEE802dot1Bridge: tx.bridges_present ? "true" : "false",
			PacketErrors: sprintf('%d', tx.packet_errors ?? 0),
			PacketErrorsReceived: sprintf('%d', rx?.packet_errors ?? 0),
			TransmittedPackets: sprintf('%d', tx.transmitted_packets ?? 0),
			PacketsReceived: sprintf('%d', rx?.received_packets ?? 0),
			MACThroughputCapacity: sprintf('%d', tx.mac_throughput_capacity ?? 0),
			LinkAvailability: sprintf('%d', tx.link_availability ?? 0),
			PHYRate: sprintf('%d', tx.phy_rate ?? 0),
			RSSI: sprintf('%d', rx?.rssi ?? 0),
		};
	}

	for (let remote_mac, rx in rx_metrics) {
		if (remote_mac in tx_metrics)
			continue;

		metrics[sprintf('%d', ++idx)] = {
			NeighborMACAddress: remote_mac,
			IEEE802dot1Bridge: "false",
			PacketErrors: "0",
			PacketErrorsReceived: sprintf('%d', rx.packet_errors ?? 0),
			TransmittedPackets: "0",
			PacketsReceived: sprintf('%d', rx.received_packets ?? 0),
			MACThroughputCapacity: "0",
			LinkAvailability: "0",
			PHYRate: "0",
			RSSI: sprintf('%d', rx.rssi ?? 0),
		};
	}

	return metrics;
}

/**
 * Converts a topology device to TR-181 IEEE1905Device object.
 *
 * @param {object} dev - Device data from topology
 * @param {number} dev_idx - 1-based device index
 * @returns {object} TR-181 formatted IEEE1905Device object
 */
function topo_device_to_object(dev, dev_idx) {
	let ifaces = dev.interfaces ?? [];
	let ipv4_list = {};
	let ipv4_idx = 0;

	for (let ip_if in dev.ipv4) {
		let if_mac = ip_if.if_mac_address;
		for (let addr in ip_if.addresses)
			ipv4_list[sprintf('%d', ++ipv4_idx)] = topo_ipv4_to_object(if_mac, addr);
	}

	let ipv6_list = {};
	let ipv6_idx = 0;

	for (let ip_if in dev.ipv6) {
		let if_mac = ip_if.if_mac_address;

		if (ip_if.linklocal_address)
			ipv6_list[sprintf('%d', ++ipv6_idx)] = topo_ipv6_to_object(
				if_mac, { address: ip_if.linklocal_address }, "LinkLocal");

		for (let addr in ip_if.other_addresses)
			ipv6_list[sprintf('%d', ++ipv6_idx)] = topo_ipv6_to_object(
				if_mac, addr, addr.ipv6addr_type_name ?? "");
	}

	let iface_list = {};
	for (let i = 0; i < length(ifaces); i++)
		iface_list[sprintf('%d', i + 1)] = topo_interface_to_object(ifaces[i]);

	let ieee1905_neighbors = {};
	let neigh_idx = 0;

	for (let neigh_entry in dev.neighbors?.ieee1905) {
		let local_if_mac = neigh_entry.local_if_mac_address;
		for (let neigh in neigh_entry.ieee1905_neighbors) {
			let neighbor_al_mac = neigh.neighbor_al_mac_address;
			let metrics = topo_neighbor_metrics_build(dev, local_if_mac, neighbor_al_mac);
			ieee1905_neighbors[sprintf('%d', ++neigh_idx)] = {
				LocalInterface: interface_ref_build(dev_idx, ifaces, local_if_mac),
				NeighborDeviceId: neighbor_al_mac ?? "",
				MetricNumberOfEntries: sprintf('%d', length(metrics)),
				Metric: metrics,
			};
		}
	}

	let non_ieee1905 = {};
	let non_idx = 0;

	for (let iface_mac, neighbor_macs in dev.neighbors?.others) {
		for (let neigh_mac in neighbor_macs) {
			non_ieee1905[sprintf('%d', ++non_idx)] = {
				LocalInterface: interface_ref_build(dev_idx, ifaces, iface_mac),
				NeighborInterfaceId: neigh_mac,
			};
		}
	}

	let l2_list = {};
	let l2_idx = 0;

	for (let l2_iface in dev.l2) {
		for (let l2_neigh in l2_iface.neighbors) {
			l2_list[sprintf('%d', ++l2_idx)] = {
				LocalInterface: interface_ref_build(dev_idx, ifaces, l2_iface.if_mac_address),
				NeighborInterfaceId: l2_neigh.neighbor_mac_address ?? "",
				BehindInterfaceIds: join(',', l2_neigh.behind_mac_addresses ?? []),
			};
		}
	}

	let bridging_list = {};
	for (let i = 0; i < length(dev.bridging_tuples ?? []); i++) {
		let macs = dev.bridging_tuples[i];
		let ref_paths = [];
		for (let mac in macs)
			push(ref_paths, interface_ref_build(dev_idx, ifaces, mac));
		bridging_list[sprintf('%d', i + 1)] = {
			InterfaceList: join(',', ref_paths),
		};
	}

	let vendor_list = {};
	for (let i = 0; i < length(dev.vendor_properties ?? []); i++) {
		let vp = dev.vendor_properties[i];
		vendor_list[sprintf('%d', i + 1)] = {
			OUI: vp.oui ?? "",
			Information: vp.information ?? "",
		};
	}

	return {
		IEEE1905Id: dev.al_address ?? "",
		Version: "1905.1a",
		RegistrarFreqBand: "",
		FriendlyName: dev.identification?.friendly_name ?? "",
		ManufacturerName: dev.identification?.manufacturer_name ?? "",
		ManufacturerModel: dev.identification?.manufacturer_model ?? "",
		ControlURL: "",
		AssocWiFiNetworkDeviceRef: "",
		VendorPropertiesNumberOfEntries: sprintf('%d', length(vendor_list)),
		IPv4AddressNumberOfEntries: sprintf('%d', ipv4_idx),
		IPv6AddressNumberOfEntries: sprintf('%d', ipv6_idx),
		InterfaceNumberOfEntries: sprintf('%d', length(ifaces)),
		NonIEEE1905NeighborNumberOfEntries: sprintf('%d', non_idx),
		IEEE1905NeighborNumberOfEntries: sprintf('%d', neigh_idx),
		L2NeighborNumberOfEntries: sprintf('%d', l2_idx),
		BridgingTupleNumberOfEntries: sprintf('%d', length(bridging_list)),
		IPv4Address: ipv4_list,
		IPv6Address: ipv6_list,
		Interface: iface_list,
		IEEE1905Neighbor: ieee1905_neighbors,
		NonIEEE1905Neighbor: non_ieee1905,
		L2Neighbor: l2_list,
		BridgingTuple: bridging_list,
		VendorProperties: vendor_list,
	};
}

/**
 * Get handler for Device.IEEE1905.
 *
 * @param {object} ctx - Handler context
 * @returns {object} IEEE1905 root object
 */
function ieee1905_get(ctx) {
	return {
		...ubbf.ctx_config(ctx),
		Version: "1905.1a",
	};
}

/**
 * Get handler for Device.IEEE1905.AL.
 *
 * @param {object} ctx - Handler context
 * @returns {object} AL object with local device info
 */
function al_get(ctx) {
	let topo = topology_get();
	let local = topo?.devices?.[0];
	let ifaces = local?.interfaces ?? [];

	let iface_list = {};
	for (let i = 0; i < length(ifaces); i++)
		iface_list[sprintf('%d', i + 1)] = al_interface_to_object(ifaces[i], topo?.devices);

	return {
		...ubbf.ctx_config(ctx),
		IEEE1905Id: local?.al_address ?? "",
		Status: topo ? "Up" : "Disabled",
		LastChange: "0",
		LowerLayers: "",
		RegistrarFreqBand: "",
		InterfaceNumberOfEntries: sprintf('%d', length(ifaces)),
		Interface: iface_list,
	};
}

/**
 * Get handler for Device.IEEE1905.AL.Interface.{i}.
 *
 * @param {object} ctx - Handler context
 * @returns {object|null} Interface object
 */
function al_interface_get(ctx) {
	let topo = topology_get();
	let local = topo?.devices?.[0];
	let ifaces = local?.interfaces ?? [];
	let devices = topo?.devices;

	if (ctx.instance == null)
		return ubbf.enumerate_instances(ifaces,
			(iface) => al_interface_to_object(iface, devices));

	let iface = ubbf.get_by_instance(ifaces, ctx.instance);
	if (!iface)
		return null;

	return al_interface_to_object(iface, devices);
}

/**
 * Get handler for Device.IEEE1905.AL.NetworkTopology.
 *
 * @param {object} ctx - Handler context
 * @returns {object} NetworkTopology object
 */
function network_topology_get(ctx) {
	let topo = topology_get();
	let devices = topo?.devices ?? [];
	let enabled = ubbf.to_bool(ctx.config?.Enable);

	let device_list = {};
	for (let i = 0; i < length(devices); i++)
		device_list[sprintf('%d', i + 1)] = topo_device_to_object(devices[i], i + 1);

	return {
		...ubbf.ctx_config(ctx),
		Status: (enabled && topo) ? "Available" : "Disabled",
		IEEE1905DeviceNumberOfEntries: sprintf('%d', length(devices)),
		ChangeLogNumberOfEntries: "0",
		IEEE1905Device: device_list,
	};
}

/**
 * Get handler for Device.IEEE1905.AL.NetworkTopology.IEEE1905Device.{i}.
 *
 * @param {object} ctx - Handler context
 * @returns {object|null} IEEE1905Device object
 */
function network_topology_device_get(ctx) {
	let topo = topology_get();
	let devices = topo?.devices ?? [];

	if (ctx.instance == null) {
		let device_list = {};
		for (let i = 0; i < length(devices); i++)
			device_list[sprintf('%d', i + 1)] = topo_device_to_object(devices[i], i + 1);
		return device_list;
	}

	let dev = ubbf.get_by_instance(devices, ctx.instance);
	if (!dev)
		return null;

	return topo_device_to_object(dev, ctx.instance);
}

export const model = {
	'Device.IEEE1905': {
		schema: schemas.IEEE1905,
		get: ieee1905_get,
	},

	'Device.IEEE1905.AL': {
		schema: schemas.AL,
		get: al_get,
	},

	'Device.IEEE1905.AL.Security': {
		schema: schemas.AL_Security,
	},

	'Device.IEEE1905.AL.NetworkingRegistrar': {
		schema: schemas.AL_NetworkingRegistrar,
	},

	'Device.IEEE1905.AL.Interface': {
	},

	'Device.IEEE1905.AL.Interface.{i}': {
		schema: schemas.AL_Interface,
		get: al_interface_get,
	},

	'Device.IEEE1905.AL.Interface.{i}.VendorProperties.{i}': {
		schema: schemas.Interface_VendorProperties,
	},

	'Device.IEEE1905.AL.Interface.{i}.Link': {
	},

	'Device.IEEE1905.AL.Interface.{i}.Link.{i}': {
		schema: schemas.Interface_Link,
	},

	'Device.IEEE1905.AL.Interface.{i}.Link.{i}.Metric': {
		schema: schemas.Link_Metric,
	},

	'Device.IEEE1905.AL.ForwardingTable': {
		schema: schemas.AL_ForwardingTable,
	},

	'Device.IEEE1905.AL.ForwardingTable.ForwardingRule': {
	},

	'Device.IEEE1905.AL.ForwardingTable.ForwardingRule.{i}': {
		schema: schemas.ForwardingTable_ForwardingRule,
	},

	'Device.IEEE1905.AL.NetworkTopology': {
		schema: schemas.AL_NetworkTopology,
		get: network_topology_get,
	},

	'Device.IEEE1905.AL.NetworkTopology.ChangeLog.{i}': {
		schema: schemas.NetworkTopology_ChangeLog,
	},

	'Device.IEEE1905.AL.NetworkTopology.IEEE1905Device': {
	},

	'Device.IEEE1905.AL.NetworkTopology.IEEE1905Device.{i}': {
		schema: schemas.NetworkTopology_IEEE1905Device,
		get: network_topology_device_get,
	},

	'Device.IEEE1905.AL.NetworkTopology.IEEE1905Device.{i}.IPv4Address.{i}': {
		schema: schemas.IEEE1905Device_IPv4Address,
	},

	'Device.IEEE1905.AL.NetworkTopology.IEEE1905Device.{i}.IPv6Address.{i}': {
		schema: schemas.IEEE1905Device_IPv6Address,
	},

	'Device.IEEE1905.AL.NetworkTopology.IEEE1905Device.{i}.Interface.{i}': {
		schema: schemas.IEEE1905Device_Interface,
	},

	'Device.IEEE1905.AL.NetworkTopology.IEEE1905Device.{i}.IEEE1905Neighbor': {
	},

	'Device.IEEE1905.AL.NetworkTopology.IEEE1905Device.{i}.IEEE1905Neighbor.{i}': {
		schema: schemas.IEEE1905Device_IEEE1905Neighbor,
	},

	'Device.IEEE1905.AL.NetworkTopology.IEEE1905Device.{i}.IEEE1905Neighbor.{i}.Metric.{i}': {
		schema: schemas.IEEE1905Neighbor_Metric,
	},

	'Device.IEEE1905.AL.NetworkTopology.IEEE1905Device.{i}.NonIEEE1905Neighbor.{i}': {
		schema: schemas.IEEE1905Device_NonIEEE1905Neighbor,
	},

	'Device.IEEE1905.AL.NetworkTopology.IEEE1905Device.{i}.L2Neighbor.{i}': {
		schema: schemas.IEEE1905Device_L2Neighbor,
	},

	'Device.IEEE1905.AL.NetworkTopology.IEEE1905Device.{i}.BridgingTuple.{i}': {
		schema: schemas.IEEE1905Device_BridgingTuple,
	},

	'Device.IEEE1905.AL.NetworkTopology.IEEE1905Device.{i}.VendorProperties.{i}': {
		schema: schemas.IEEE1905Device_VendorProperties,
	},
};
