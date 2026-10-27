'use strict';

// Out-of-tree module. `ubbf_module` is the scope datamodel.uc includes this
// file with, and it is visible only while the include runs, so anything the
// handlers below use later has to be bound here. See docs/ARCHITECTURE.md.

const ubbf = ubbf_module.ubbf;
const utils = ubbf_module.utils;
const model = ubbf_module.model;

const fs = require('fs');

const schema = ubbf_module.schema;

const LLDPD_SOCKET = '/var/run/lldpd.socket';

// The type strings of liblldpctl (chassis_id_subtype_map in
// src/lib/atoms/chassis.c, port_id_subtype_map in src/lib/atoms/port.c).
// lldpcli prints `unhandled` for chassis subtypes 1 and 3 and port subtypes
// 2 and 6, so those read 0.
const CHASSIS_ID_SUBTYPES = {
	'ifalias': 2,
	'mac': 4,
	'ip': 5,
	'ifname': 6,
	'local': 7
};

const PORT_ID_SUBTYPES = {
	'ifalias': 1,
	'mac': 3,
	'ip': 4,
	'ifname': 5,
	'local': 7
};

// Lengths from the TR-181 definitions of the parameters.
const ID_MAX = 255;
const MODEL_NAME_MAX = 31;
const INFORMATION_MAX = 248;

/**
 * Retrieves LLDP neighbor data from lldpcli (uncached).
 *
 * @returns {object|null} Parsed JSON output from lldpcli or null on failure
 */
function lldp_neighbors_fetch() {
	let result = fs.popen('lldpcli -f json show neighbors 2>/dev/null');
	if (!result)
		return null;

	let output = result.read('all');
	result.close();

	if (!output)
		return null;

	return json(output);
}

/**
 * Gets LLDP neighbor data (cached); every handler of one request reads it.
 *
 * @returns {object|null} Parsed JSON output from lldpcli or null on failure
 */
function lldp_neighbors_get() {
	return ubbf.cache_call(lldp_neighbors_fetch);
}

// lldpcli escapes control characters in its JSON and json() decodes them
// back, so the neighbour strings go through text_clamp().
const text_clamp = ubbf.text_clamp;

/**
 * Wraps a single lldpcli element in an array: the writer collapses an
 * array with one element into the element.
 *
 * @param {*} v - Collection node
 * @returns {array} The elements
 */
function as_array(v) {
	if (v == null)
		return [];

	return (type(v) == 'array') ? v : [ v ];
}

/**
 * Parses lldpcli age string to seconds.
 *
 * @param {string} age_str - Age string in format "N day(s), HH:MM:SS"
 * @returns {number|null} Age in seconds, or null when unknown
 */
function age_to_seconds(age_str) {
	let m = match(age_str ?? '', /(\d+) days?, (\d+):(\d+):(\d+)/);
	if (!m)
		return null;

	return int(m[1]) * 86400 + int(m[2]) * 3600 + int(m[3]) * 60 + int(m[4]);
}

/**
 * Parses vendor-specific TLVs from lldpcli unknown-tlvs data.
 *
 * @param {object} iface_data - Per-interface lldpcli data
 * @returns {array} Array of {org_code, info_type, information} objects
 */
function vendor_tlvs_parse(iface_data) {
	let result = [];

	for (let tlv in as_array(iface_data?.['unknown-tlvs']?.['unknown-tlv'])) {
		if (!tlv?.oui)
			continue;

		push(result, {
			org_code: ubbf.mac_normalise(tlv.oui, ','),
			info_type: int(tlv.subtype) ?? 0,
			information: substr(ubbf.mac_normalise(tlv.value ?? '', ','), 0, INFORMATION_MAX)
		});
	}

	return result;
}

/**
 * Converts vendor TLV data to TR-181 VendorSpecific object format.
 *
 * @param {object} tlv - Vendor TLV with org_code, info_type, information
 * @returns {object} TR-181 formatted VendorSpecific object
 */
function vendor_tlv_to_object(tlv) {
	return {
		OrganizationCode: tlv.org_code,
		InformationType: sprintf('%d', tlv.info_type),
		Information: tlv.information
	};
}

/**
 * Lists the chassis of one lldpcli interface element.
 *
 * lldpcli keys a chassis by its System Name, and only when the neighbour
 * sent one: without a System Name TLV the chassis object holds the
 * chassis fields (`id`, `descr`, ...) directly.
 *
 * @param {object|array} chassis - Chassis node of an interface element
 * @returns {array} `{ name, data }` per chassis
 */
function chassis_entries(chassis) {
	if (type(chassis) == 'object' && type(chassis.id) == 'object')
		return [ { name: '', data: chassis } ];

	let entries = [];

	for (let item in as_array(chassis)) {
		for (let name, data in item) {
			if (type(data) == 'object')
				push(entries, { name, data });
		}
	}

	return entries;
}

/**
 * Normalises an lldpcli JSON collection. The default (non-json0) writer
 * emits a single element as an object keyed by name, but two or more
 * elements as an array of single-key objects.
 *
 * @param {object|array} data - lldpcli collection node
 * @returns {array} Array of { name, data } pairs
 */
function lldp_collection_entries(data) {
	let entries = [];

	for (let item in as_array(data)) {
		for (let name, val in item)
			push(entries, { name, data: val });
	}

	return entries;
}

/**
 * Returns the OUI of a MAC chassis ID, or '' for a locally administered
 * address, which has no manufacturer.
 *
 * @param {string} mac - Chassis ID of subtype MAC
 * @returns {string} OUI as six upper-case hex digits, or ''
 */
function mac_oui(mac) {
	let oui = ubbf.mac_normalise(substr(mac, 0, 8), ':');
	if (length(oui) != 6 || (hex(substr(oui, 0, 2)) & 0x02))
		return '';

	return oui;
}

/**
 * Builds the port entry of one lldpcli interface element.
 *
 * @param {object} port_data - Port node of the element
 * @param {string} age - Age string of the element
 * @returns {object} Port entry
 */
function port_entry_build(port_data, age) {
	let port_id = text_clamp(port_data.id?.value, ID_MAX);
	let port_id_type = lc(port_data.id?.type ?? '');
	let age_seconds = age_to_seconds(age);

	return {
		port_id,
		port_subtype: PORT_ID_SUBTYPES[port_id_type] ?? 0,
		port_descr: text_clamp(port_data.descr, ID_MAX),
		ttl: int(port_data.ttl) ?? 0,
		mac_address: (port_id_type == 'mac') ? port_id : '',
		// lldpd reports the age since the port data last changed, not
		// since the last frame; liblldpctl exposes nothing else.
		last_update: ubbf.datetime_format(
			(age_seconds != null) ? time() - age_seconds : null)
	};
}

/**
 * Builds a device entry from the chassis of one lldpcli interface element.
 *
 * @param {string} iface_name - Receive interface
 * @param {object} chassis - `{ name, data }` from chassis_entries()
 * @returns {object} Device entry without ports
 */
function device_entry_build(iface_name, chassis) {
	let chassis_data = chassis.data;
	let chassis_id = text_clamp(chassis_data.id?.value, ID_MAX);
	let chassis_id_type = lc(chassis_data.id?.type ?? '');

	let caps = [];
	for (let cap in as_array(chassis_data.capability)) {
		if (cap?.enabled)
			push(caps, cap.type);
	}

	return {
		interface: iface_name,
		mac: (chassis_id_type == 'mac') ? uc(chassis_id) : '',
		chassis_id,
		chassis_subtype: CHASSIS_ID_SUBTYPES[chassis_id_type] ?? 0,
		vendor_tlvs: [],
		device_info: {
			category: join(',', caps),
			oui: (chassis_id_type == 'mac') ? mac_oui(chassis_id) : '',
			model_name: text_clamp(chassis.name, MODEL_NAME_MAX),
			model_number: ''
		},
		ports: []
	};
}

/**
 * Adds the vendor TLVs of one port to a device, each (OrganizationCode,
 * InformationType) once, the unique key of the VendorSpecific table.
 *
 * @param {object} dev - Device entry
 * @param {array} tlvs - TLVs from vendor_tlvs_parse()
 */
function device_tlvs_merge(dev, tlvs) {
	for (let tlv in tlvs) {
		let dup = filter(dev.vendor_tlvs, (t) => t.org_code == tlv.org_code && t.info_type == tlv.info_type);
		if (!length(dup))
			push(dev.vendor_tlvs, tlv);
	}
}

/**
 * Builds structured LLDP device data from neighbour information.
 *
 * lldpd reports one element per receive interface and neighbour port. The
 * elements of one chassis, the unique key (ChassisIDSubtype, ChassisID),
 * become one device with one Port row each; Interface and Host come from
 * the first element.
 *
 * @returns {array} Array of device objects with chassis, port, and device info
 */
function lldp_data_build() {
	let lldp_data = lldp_neighbors_get();
	let by_key = {};
	let devices = [];

	for (let iface in lldp_collection_entries(lldp_data?.lldp?.interface)) {
		let iface_data = iface.data;
		if (type(iface_data) != 'object' || !iface_data.chassis)
			continue;

		for (let chassis in chassis_entries(iface_data.chassis)) {
			let entry = device_entry_build(iface.name, chassis);
			let key = sprintf('%d/%s', entry.chassis_subtype, entry.chassis_id);
			let dev = by_key[key];
			let port = port_entry_build(iface_data.port ?? {}, iface_data.age);

			if (!dev) {
				// A host that runs lldpd often takes the chassis ID from
				// another of its interfaces; the MAC Port ID is the
				// address the Hosts table knows.
				if (port.mac_address)
					entry.mac = uc(port.mac_address);
				dev = by_key[key] = entry;
				push(devices, dev);
			}

			push(dev.ports, port);
			device_tlvs_merge(dev, vendor_tlvs_parse(iface_data));
		}
	}

	return devices;
}

/**
 * Converts LLDP port data to TR-181 Port object format.
 *
 * @param {object} port - Port data with port_id, port_subtype, ttl, port_descr
 * @returns {object} TR-181 formatted Device_Port object
 */
function port_to_object(port) {
	return {
		PortIDSubtype: sprintf('%d', port.port_subtype),
		PortID: port.port_id,
		TTL: sprintf('%d', port.ttl),
		PortDescription: port.port_descr,
		LastUpdate: port.last_update,
		MACAddressList: port.mac_address,
		LinkInformation: {
			InterfaceType: '0',
			MACForwardingTable: ''
		}
	};
}

/**
 * Converts LLDP device data to TR-181 Discovery_Device object format.
 *
 * @param {object} root - Root data model object
 * @param {object} dev - Device data with chassis info, ports, and device_info
 * @returns {object} TR-181 formatted Discovery_Device object
 */
function device_to_object(root, dev) {
	return {
		Interface: ubbf.ethernet_interface_path(root, dev.interface),
		ChassisIDSubtype: sprintf('%d', dev.chassis_subtype),
		ChassisID: dev.chassis_id,
		Host: utils.hosts.host_path_by_mac(root, dev.mac),
		PortNumberOfEntries: sprintf('%d', length(dev.ports)),
		Port: ubbf.enumerate_instances(dev.ports, port_to_object),
		DeviceInformation: {
			DeviceCategory: dev.device_info.category,
			ManufacturerOUI: dev.device_info.oui,
			ModelName: dev.device_info.model_name,
			ModelNumber: dev.device_info.model_number,
			VendorSpecificNumberOfEntries: sprintf('%d', length(dev.vendor_tlvs)),
			VendorSpecific: ubbf.enumerate_instances(dev.vendor_tlvs, vendor_tlv_to_object)
		}
	};
}

/**
 * Get handler for Device.LLDP.Discovery.Device.{i}.
 *
 * @param {object} ctx - Context with optional instance number
 * @returns {object|null} Single device or enumerated devices
 */
function device_get(ctx) {
	let devices = lldp_data_build();
	let to_object = (dev) => device_to_object(ctx.root, dev);

	if (ctx.instance == null)
		return ubbf.enumerate_instances(devices, to_object);

	let dev = ubbf.get_by_instance(devices, ctx.instance);
	if (!dev)
		return null;

	return to_object(dev);
}

/**
 * Get handler for Device.LLDP.Discovery.Device.{i}.DeviceInformation.
 *
 * The intermediate registration is required so the dm engine has a deepest
 * matching handler when callers ask for paths under DeviceInformation;
 * without it deep gets like `....DeviceInformation.VendorSpecific.1.OrganizationCode`
 * resolve to null even though device_get's full tree carries the value.
 *
 * Returning the full DeviceInformation slice (including VendorSpecific.{i})
 * also makes a leaf-level get handler on VendorSpecific.{i} unnecessary:
 * subtree_dispatch's ancestor block descends through `VendorSpecific.<inst>`
 * to reach the per-TLV leaves. Registering a get handler at VendorSpecific.{i}
 * would force the existing-instances runtime-discovery branch to fire, and
 * because LLDP discovery is never persisted to the runtime tree the
 * resulting refresh_instances call would return [] and obuspa would reject
 * deep VendorSpecific paths with err 7026.
 *
 * @param {object} ctx - Context with device instance and root
 * @returns {object|null} DeviceInformation slice including VendorSpecific
 */
function device_information_get(ctx) {
	let devices = lldp_data_build();
	let dev = ubbf.get_by_instance(devices, ctx.instance);
	if (!dev)
		return null;
	return device_to_object(ctx.root, dev).DeviceInformation;
}

/**
 * Get handler for Device.LLDP.Discovery.
 *
 * @param {object} ctx - Context object
 * @returns {object} Discovery container with enumerated Device entries
 */
function discovery_get(ctx) {
	let devices = lldp_data_build();
	let to_object = (dev) => device_to_object(ctx.root, dev);

	return {
		Device: ubbf.enumerate_instances(devices, to_object),
		DeviceNumberOfEntries: sprintf('%d', length(devices))
	};
}

/**
 * Get handler for Device.LLDP.
 *
 * X_UBBF_Enable falls back to `Enable`, the name before the X_UBBF_
 * prefix, while a stored configuration has only that key. The stored
 * object is read from ctx.root because ctx.config already carries the
 * schema default of X_UBBF_Enable. X_UBBF_Status follows the daemon: its
 * socket exists only while lldpd runs.
 *
 * @param {object} ctx - Context with root
 * @returns {object} LLDP root with Discovery sub-object
 */
function lldp_get(ctx) {
	let stored = ctx.root?.Device?.LLDP;
	let enable = ubbf.to_bool(stored?.X_UBBF_Enable ?? stored?.Enable);
	let status = 'Disabled';

	if (enable)
		status = fs.access(LLDPD_SOCKET) ? 'Enabled' : 'Error';

	return {
		X_UBBF_Enable: enable ? 'true' : 'false',
		X_UBBF_Status: status,
		Discovery: discovery_get(ctx)
	};
}

model['Device.LLDP'] = {
	schema: schema('LLDP'),
	get: lldp_get
};

model['Device.LLDP.Discovery'] = {
	schema: schema('Discovery'),
	get: discovery_get
};

model['Device.LLDP.Discovery.Device'] = {
};

// The rows come from lldpd; a stored row would hide them.
model['Device.LLDP.Discovery.Device.{i}'] = {
	schema: schema('Discovery_Device'),
	get: device_get,
	maxInstances: 0
};

model['Device.LLDP.Discovery.Device.{i}.Port.{i}'] = {
	schema: schema('Device_Port'),
	maxInstances: 0
};

model['Device.LLDP.Discovery.Device.{i}.Port.{i}.LinkInformation'] = {
	schema: schema('Port_LinkInformation')
};

model['Device.LLDP.Discovery.Device.{i}.DeviceInformation'] = {
	schema: schema('Device_DeviceInformation'),
	get: device_information_get
};

model['Device.LLDP.Discovery.Device.{i}.DeviceInformation.VendorSpecific.{i}'] = {
	schema: schema('DeviceInformation_VendorSpecific'),
	maxInstances: 0
};
