'use strict';

import * as ubbf from 'ubbf';
import * as ubus from 'ubus';
import { deviceinfo_get } from 'ubbf';
import * as iwinfo from 'iwinfo';
import * as nl80211 from 'nl80211';
import { find_phy } from 'wifi.utils';
import { cache_call } from 'ubbf';
import { iwinfo_update, capability_radios_get } from 'ubbf.utils.wifi';
import { band_to_index } from 'ubbf';
import {
	phy_radio_restrict, radio_capability_find, wiphy_radios_get, radio_address_key, radio_addresses_assign
} from 'ubbf.utils.wifi_radio';

/**
 * Fetches wireless status from network.wireless ubus (uncached).
 *
 * @returns {object|null} Wireless status keyed by radio name
 */
function wireless_status_fetch() {
	return ubus?.call('network.wireless', 'status');
}

/**
 * Gets wireless status from network.wireless ubus (cached).
 *
 * @returns {object|null} Wireless status keyed by radio name
 */
export function wireless_status_get() {
	return cache_call(wireless_status_fetch);
};

/**
 * Gets the first interface name for a radio.
 *
 * @param {string} radio_name - Radio name (e.g., radio0)
 * @returns {string|null} Interface name or null if not found
 */
export function radio_ifname_get(radio_name) {
	let status = wireless_status_get();
	let radio = status?.[radio_name];
	if (!radio?.interfaces || length(radio.interfaces) == 0)
		return null;
	return radio.interfaces[0].ifname;
};

/**
 * Fetches local radio survey data from iwinfo (uncached), see
 * radio_survey_build() in wifi_dataelements.c of ubbf.so.
 *
 * @param {string} ifname - Interface name
 * @returns {object} Survey data with noise, utilization, transmit and receive stats
 */
function local_radio_survey_fetch(ifname) {
	return ubbf.radio_survey_build(ifname ? iwinfo.ifaces?.[ifname] : null);
}

/**
 * Gets local radio survey data from iwinfo (cached).
 *
 * @param {string} ifname - Interface name
 * @returns {object} Survey data with noise, utilization, transmit and receive stats
 */
export function local_radio_survey_get(ifname) {
	return cache_call(local_radio_survey_fetch, ifname);
};

/**
 * Fetches local radio capability data from iwinfo (uncached), see
 * radio_capability_build() in wifi_dataelements.c of ubbf.so.
 *
 * @param {string} phy_name - PHY name (e.g., phy0)
 * @param {number} band_idx - Band index (0=2.4GHz, 1=5GHz, 3=6GHz)
 * @param {object} radio - Capability radio; its frequency ranges limit the channels
 * @returns {object} Radio capabilities including operating classes and HE capabilities
 */
function local_radio_capability_fetch(phy_name, band_idx, radio) {
	let phys = map(iwinfo.phys ?? [], (p) => (p?.wiphy_name == phy_name) ? phy_radio_restrict(p, band_idx, radio) : p);

	return ubbf.radio_capability_build(phys, phy_name, band_idx);
}

/**
 * Gets local radio capability data from iwinfo (cached).
 *
 * @param {string} phy_name - PHY name (e.g., phy0)
 * @param {number} band_idx - Band index (0=2.4GHz, 1=5GHz, 3=6GHz)
 * @param {object} radio - Capability radio; its frequency ranges limit the channels
 * @returns {object} Radio capabilities including operating classes and HE capabilities
 */
export function local_radio_capability_get(phy_name, band_idx, radio) {
	return cache_call(local_radio_capability_fetch, phy_name, band_idx, radio);
};

/**
 * Gets associated client data for a BSS in the umap topology shape, see
 * local_sta_data_build() in wifi_dataelements.c of ubbf.so. HE
 * capabilities are embedded per client so client_capabilities_get() in
 * device_to_object() picks them up like EasyMesh topology entries.
 *
 * @param {string} ifname - Interface name
 * @returns {array} Array of associated client objects
 */
export function local_sta_data_get(ifname) {
	let assoclist = iwinfo.assoclist(ifname);
	if (!assoclist)
		return [];

	let nl_stations = null;
	try {
		nl_stations = nl80211.request(
			nl80211.const.NL80211_CMD_GET_STATION,
			nl80211.const.NLM_F_DUMP,
			{ dev: ifname }
		);
	} catch (e) {
		nl_stations = null;
	}

	return ubbf.local_sta_data_build(assoclist, nl_stations);
};

/**
 * Finds the rank of a configured radio within its band, as umapd does: the
 * nl80211 radio the wifi-device's radio option names, else the first radio
 * of the band.
 *
 * @param {object} phy - Entry of the nl80211 wiphy dump
 * @param {object} config - The wifi-device configuration
 * @returns {number} Rank of the radio in its band
 */
function radio_rank_get(phy, config) {
	if (config.radio == null)
		return 0;

	let entry = filter(wiphy_radios_get(phy), (e) => e.band == config.band && e.index == int(config.radio))[0];
	return entry?.rank ?? 0;
}

/**
 * Fetches list of local radios with their BSS information (uncached).
 * Each AP BSS node carries its associated_clients inline, mirroring the
 * shape of umap topology devices.
 *
 * @returns {array} Array of radio objects with radio_unique_identifier and bss list
 */
function local_radios_fetch() {
	let status = wireless_status_get();
	if (!status)
		return [];

	iwinfo_update();

	let wiphys = map(filter(iwinfo.phys ?? [], (p) => p?.mac), (p) => ({ mac: p.mac, radios: wiphy_radios_get(p) }));
	let ruids = radio_addresses_assign(wiphys);

	let result = [];
	for (let radio_name, radio_status in status) {
		if (type(radio_status) != 'object')
			continue;

		let config = radio_status.config ?? {};
		let phy_name = find_phy(config, false);
		let phy = filter(iwinfo.phys ?? [], (p) => p?.wiphy_name == phy_name)[0];
		let ruid = phy?.mac ? ruids[radio_address_key(phy.mac, config.band, radio_rank_get(phy, config))] : null;
		if (!ruid)
			continue;

		let bss_list = [];
		for (let iface in radio_status.interfaces ?? []) {
			if (iface.config?.mode != 'ap')
				continue;
			// the runtime BSSID is the netdev MAC; the UCI config rarely
			// pins macaddr, so fall back to sysfs rather than the ifname
			let bss_mac = iface.config?.macaddr;
			if (!bss_mac && iface.ifname)
				bss_mac = ubbf.readfile_trim(`/sys/class/net/${iface.ifname}/address`);
			push(bss_list, {
				mac_address: bss_mac ?? "",
				ssid: iface.config?.ssid ?? "",
				associated_clients: local_sta_data_get(iface.ifname),
				_ifname: iface.ifname
			});
		}

		push(result, {
			radio_unique_identifier: ruid,
			bss: bss_list,
			_radio_name: radio_name,
			_phy_name: phy_name,
			_band_idx: band_to_index(config.band),
			_cap: radio_capability_find(capability_radios_get(), config.band, radio_name)
		});
	}
	return result;
}

/**
 * Gets list of local radios with their BSS information (cached).
 *
 * @returns {array} Array of radio objects with radio_unique_identifier and bss list
 */
export function local_radios_get() {
	return cache_call(local_radios_fetch);
};

/**
 * Fetches local device information for non-EasyMesh mode (uncached).
 *
 * @returns {object} Device object with identification and AP operational BSS
 */
function local_device_fetch() {
	let deviceinfo = deviceinfo_get();
	let radios = local_radios_get();

	return {
		al_address: deviceinfo.ManufacturerOUI ?? "",
		identification: {
			manufacturer_name: deviceinfo.Manufacturer ?? "",
			serial_number: deviceinfo.SerialNumber ?? "",
			manufacturer_model: deviceinfo.ModelName ?? "",
			software_version: deviceinfo.SoftwareVersion ?? ""
		},
		map: {
			ap_operational_bss: radios
		}
	};
}

/**
 * Gets local device information for non-EasyMesh mode (cached).
 *
 * @returns {object} Device object with identification and AP operational BSS
 */
export function local_device_get() {
	return cache_call(local_device_fetch);
};

/**
 * Fetches local API data (capabilities, survey) for non-EasyMesh mode (uncached).
 *
 * @returns {object} API data structure with capability and survey information
 */
function local_api_data_fetch() {
	let radios = local_radios_get();
	if (length(radios) == 0)
		return {};

	let survey_radios = {};
	let capability_radios = {};
	let inventory_radios = {};

	for (let radio in radios) {
		let ruid = radio.radio_unique_identifier;
		if (!ruid)
			continue;

		survey_radios[ruid] = local_radio_survey_get(radio_ifname_get(radio._radio_name));
		capability_radios[ruid] = local_radio_capability_get(radio._phy_name, radio._band_idx, radio._cap);
		inventory_radios[ruid] = { chipset_vendor: ubbf.chipset_vendor_get(radio._phy_name) };
	}

	return {
		policy: {},
		backhaul: {},
		capability: {
			radios: capability_radios,
			device_inventory: { radios: inventory_radios }
		},
		survey: { radios: survey_radios },
		traffic_sep: {},
		channel_pref: {},
		scan_results: {},
		cac_status: {},
		service_prio: {},
		security_1905: {},
		ap_mld: {},
		bsta_mld: {}
	};
}

/**
 * Gets local API data (capabilities, survey) for non-EasyMesh mode (cached).
 *
 * @returns {object} API data structure with capability and survey information
 */
export function local_api_data_get() {
	return cache_call(local_api_data_fetch);
};

/**
 * Fetches the raw topology blob from a umap ubus object (uncached).
 *
 * @param {string} obj - ubus object name ('umap' or 'umap-agent')
 * @returns {object|null} Raw get_topology result
 */
function raw_topology_fetch(obj) {
	return ubus.call(obj, 'get_topology', {});
}

/**
 * Gets the raw topology blob from a umap ubus object (cached).
 *
 * Both topology consumers (ubus_topology_get and topology_devices_get) share
 * this single cached fetch, so one Get resolves the whole DataElements subtree
 * from one topology snapshot per umap object instead of one get_topology call
 * (and one ~14 KB blob parse) per resolved parameter.
 *
 * @param {string} obj - ubus object name ('umap' or 'umap-agent')
 * @returns {object|null} Raw get_topology result
 */
function raw_topology_get(obj) {
	return cache_call(raw_topology_fetch, obj);
}

/**
 * Fetches per-client capability data from a umap ubus object (uncached).
 *
 * @param {string} obj - ubus object name ('umap' or 'umap-agent')
 * @param {string} sta_mac - Client MAC address
 * @returns {object|null} get_client result keyed by BSSID
 */
function client_query_fetch(obj, sta_mac) {
	return ubus.call(obj, 'get_client', { address: sta_mac });
}

/**
 * Gets per-client capability data from a umap ubus object (cached).
 *
 * @param {string} obj - ubus object name ('umap' or 'umap-agent')
 * @param {string} sta_mac - Client MAC address
 * @returns {object|null} get_client result keyed by BSSID
 */
export function client_query_get(obj, sta_mac) {
	return cache_call(client_query_fetch, obj, sta_mac);
};

/**
 * Fetches topology information from umap controller and agent (uncached).
 *
 * @returns {object} Object with controller_id and colocated_agent_id
 */
function ubus_topology_fetch() {
	let controller_id = "";
	let colocated_agent_id = "";

	let ctrl_result = raw_topology_get('umap');
	if (ctrl_result?.devices?.[0]?.al_address)
		controller_id = ctrl_result.devices[0].al_address;

	let agent_result = raw_topology_get('umap-agent');
	if (agent_result?.devices?.[0]?.al_address)
		colocated_agent_id = agent_result.devices[0].al_address;

	return { controller_id, colocated_agent_id };
}

/**
 * Gets topology information from umap controller and agent (cached).
 *
 * @returns {object} Object with controller_id and colocated_agent_id
 */
export function ubus_topology_get() {
	return cache_call(ubus_topology_fetch);
};

/**
 * Fetches device API data from umap for a specific device (uncached), see
 * device_api_data_build() in wifi_dataelements.c of ubbf.so.
 *
 * @param {string} al_mac - AL MAC address of the device
 * @param {boolean} controller_enabled - Whether the EasyMesh controller is enabled
 * @returns {object} API data structure with policy, backhaul, capability, etc.
 */
function device_api_data_fetch(al_mac, controller_enabled) {
	let obj = controller_enabled ? 'umap' : 'umap-agent';
	let replies = {
		agent: controller_enabled ? ubus.call('umap', 'get_agent', { address: al_mac }) : null,
		local: ubus.call('umap-agent', 'get_agent', {}),
		policy: controller_enabled ? ubus.call('umap', 'get_policy_config', { al_mac }) : null,
		scan: ubus.call(obj, 'get_scan_results', { al_mac })
	};

	return ubbf.device_api_data_build(al_mac, controller_enabled, replies);
}

/**
 * Gets device API data from umap for a specific device (cached).
 *
 * @param {string} al_mac - AL MAC address of the device
 * @param {boolean} controller_enabled - Whether the EasyMesh controller is enabled
 * @returns {object} API data structure with policy, backhaul, capability, etc.
 */
export function device_api_data_get(al_mac, controller_enabled) {
	return cache_call(device_api_data_fetch, al_mac, controller_enabled);
};

/**
 * @param {number} opclass - Global operating class
 * @returns {number} Band priority: 2.4 GHz (0), 5 GHz (1), 6 GHz (2), unknown (3)
 */
function opclass_band_priority(opclass) {
	if (opclass >= 81 && opclass <= 84)
		return 0;
	if (opclass >= 115 && opclass <= 130)
		return 1;
	if (opclass >= 131 && opclass <= 137)
		return 2;
	return 3;
}

/**
 * Returns the sort key of a radio: the band of its first known operating
 * class, then its lowest operating class of that band, which puts the
 * lower channels of a band first.
 *
 * @param {object} radio_bss - Radio entry from ap_operational_bss
 * @param {object} capability - Capability data keyed by RUID
 * @returns {object} { band, opclass }, lower values first
 */
function radio_sort_key(radio_bss, capability) {
	let ruid = radio_bss.radio_unique_identifier ?? "";
	let raw = capability?.radios?.[ruid] ?? {};
	let opclasses = map(raw.operating_classes
		?? raw.basic_capabilities?.opclasses_supported
		?? [], (oc) => oc.class ?? oc.opclass ?? 0);

	let band = 3;
	for (let cl in opclasses) {
		band = opclass_band_priority(cl);
		if (band < 3)
			break;
	}

	let in_band = filter(opclasses, (cl) => band < 3 && opclass_band_priority(cl) == band);
	return { band, opclass: length(in_band) ? min(...in_band) : 0 };
}

/**
 * Sorts the radios of a device into DataElements instance order: by band,
 * then by lowest operating class, then by RUID, so that two radios of one
 * band keep their order between reads.
 *
 * @param {array} radios - Radio entries from ap_operational_bss
 * @param {object} capability - Capability data keyed by RUID
 * @returns {array} Sorted copy of the radios
 */
export function radios_bss_sort(radios, capability) {
	let entries = map(radios ?? [], (radio) => ({
		radio,
		key: radio_sort_key(radio, capability),
		ruid: radio.radio_unique_identifier ?? ""
	}));

	sort(entries, (a, b) => (a.key.band - b.key.band) || (a.key.opclass - b.key.opclass) ||
		((a.ruid < b.ruid) ? -1 : ((a.ruid > b.ruid) ? 1 : 0)));

	return map(entries, (entry) => entry.radio);
};

/**
 * Fetches network-wide steering statistics from umap controller (uncached).
 *
 * @returns {object} Steering stats with network, bss, and sta sub-objects
 */
function steering_stats_fetch() {
	return ubus.call('umap', 'get_steering_stats', {}) ?? {};
}

/**
 * Gets network-wide steering statistics from umap controller (cached).
 *
 * @returns {object} Steering stats with network, bss, and sta sub-objects
 */
export function steering_stats_get() {
	return cache_call(steering_stats_fetch);
};

/**
 * Fetches steering history for all STAs from umap controller (uncached).
 *
 * @returns {object} Steering history keyed by STA MAC
 */
function steering_history_fetch() {
	return ubus.call('umap', 'get_steering_history', {}) ?? {};
}

/**
 * Gets steering history for all STAs from umap controller (cached).
 *
 * @returns {object} Steering history keyed by STA MAC
 */
export function steering_history_get() {
	return cache_call(steering_history_fetch);
};

/**
 * Enumerates EasyMesh agent devices from topology, deduplicating by AL MAC.
 * Queries umap controller first, then umap-agent, keeping only agent devices.
 *
 * @returns {array} Array of device objects with agent role
 */
function topology_devices_fetch() {
	return ubbf.topology_devices_build(raw_topology_get('umap'), raw_topology_get('umap-agent'));
}

/**
 * Gets EasyMesh agent devices from topology (cached).
 *
 * @returns {array} Array of device objects with agent role
 */
export function topology_devices_get() {
	return cache_call(topology_devices_fetch);
};
