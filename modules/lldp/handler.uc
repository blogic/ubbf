'use strict';

// Out-of-tree module. `ubbf_module` is the scope datamodel.uc includes this
// file with, and it is visible only while the include runs, so anything the
// handlers below use later has to be bound here. See docs/ARCHITECTURE.md.

const ubbf = ubbf_module.ubbf;
const utils = ubbf_module.utils;
const model = ubbf_module.model;

const fs = require('fs');

let schemas = {};
include('schema.uc', { schemas });

const CHASSIS_ID_SUBTYPES = {
	'reserved': 0,
	'chassis component': 1,
	'ifAlias': 2,
	'port component': 3,
	'mac': 4,
	'ip': 5,
	'ifname': 6,
	'local': 7
};

const PORT_ID_SUBTYPES = {
	'reserved': 0,
	'ifAlias': 1,
	'port component': 2,
	'mac': 3,
	'ip': 4,
	'ifname': 5,
	'agent circuit id': 6,
	'local': 7
};

/**
 * Retrieves LLDP neighbor data from lldpcli.
 *
 * @returns {object|null} Parsed JSON output from lldpcli or null on failure
 */
function lldp_neighbors_get() {
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
 * Parses lldpcli age string to seconds.
 *
 * @param {string} age_str - Age string in format "N day(s), HH:MM:SS"
 * @returns {number} Age in seconds
 */
function age_to_seconds(age_str) {
	if (!age_str)
		return 0;

	let m = match(age_str, /(\d+) days?, (\d+):(\d+):(\d+)/);
	if (!m)
		return 0;

	return int(m[1]) * 86400 + int(m[2]) * 3600 + int(m[3]) * 60 + int(m[4]);
}

/**
 * Parses vendor-specific TLVs from lldpcli unknown-tlvs data.
 *
 * @param {object} iface_data - Per-interface lldpcli data
 * @returns {array} Array of {org_code, info_type, information} objects
 */
function vendor_tlvs_parse(iface_data) {
	let unknown = iface_data?.['unknown-tlvs']?.['unknown-tlv'];
	if (!unknown)
		return [];

	if (type(unknown) != 'array')
		unknown = [unknown];

	let result = [];
	for (let tlv in unknown) {
		if (!tlv.oui)
			continue;

		push(result, {
			org_code: ubbf.mac_normalise(tlv.oui, ','),
			info_type: int(tlv.subtype) ?? 0,
			information: ubbf.mac_normalise(tlv.value ?? '', ',')
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
 * Builds device entry from chassis and port data.
 *
 * @param {string} iface_name - Interface name
 * @param {string} chassis_name - Chassis name (used as model name)
 * @param {object} chassis_data - Chassis identification data
 * @param {object} port_data - Port identification data
 * @param {string} age - Age string from lldpcli
 * @param {object} iface_data - Full interface data from lldpcli
 * @returns {object} Device entry with chassis, port, and device info
 */
function device_entry_build(iface_name, chassis_name, chassis_data, port_data, age, iface_data) {
	let chassis_id = chassis_data.id?.value ?? '';
	let chassis_id_type = lc(chassis_data.id?.type ?? '');
	let chassis_subtype = CHASSIS_ID_SUBTYPES[chassis_id_type] ?? 0;

	let oui = '';
	if (chassis_id_type == 'mac' && chassis_id)
		oui = ubbf.mac_normalise(substr(chassis_id, 0, 8), ':');

	let caps = [];
	if (type(chassis_data.capability) == 'array')
		for (let cap in chassis_data.capability)
			if (cap.enabled)
				push(caps, cap.type);

	let port_id = port_data.id?.value ?? '';
	let port_id_type = lc(port_data.id?.type ?? '');
	let port_subtype = PORT_ID_SUBTYPES[port_id_type] ?? 0;
	let port_descr = port_data.descr ?? '';
	let ttl = int(port_data.ttl) ?? 0;

	let mac_address = '';
	if (port_id_type == 'mac' && port_id)
		mac_address = port_id;

	let device_mac = '';
	if (mac_address)
		device_mac = uc(mac_address);
	else if (chassis_id_type == 'mac' && chassis_id)
		device_mac = uc(chassis_id);

	let age_seconds = age_to_seconds(age);
	let last_update = age_seconds ? ubbf.iso8601_format(time() - age_seconds) : '';

	return {
		interface: iface_name,
		mac: device_mac,
		chassis_id: chassis_id,
		chassis_subtype: chassis_subtype,
		vendor_tlvs: vendor_tlvs_parse(iface_data),
		device_info: {
			category: join(',', caps),
			oui: oui,
			model_name: chassis_name,
			model_number: ''
		},
		// lldpcli reports one port per chassis per receive interface,
		// so each device entry maps to a single TR-181 Port instance.
		ports: [{
			port_id: port_id,
			port_subtype: port_subtype,
			port_descr: port_descr,
			ttl: ttl,
			mac_address: mac_address,
			last_update: last_update
		}]
	};
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

	if (type(data) == 'array') {
		for (let item in data)
			for (let name, val in item)
				push(entries, { name, data: val });
	} else if (type(data) == 'object') {
		for (let name, val in data)
			push(entries, { name, data: val });
	}

	return entries;
}

/**
 * Builds structured LLDP device data from neighbour information.
 *
 * @returns {array} Array of device objects with chassis, port, and device info
 */
function lldp_data_build() {
	let lldp_data = lldp_neighbors_get();
	if (!lldp_data?.lldp?.interface)
		return [];

	let devices = [];

	for (let iface in lldp_collection_entries(lldp_data.lldp.interface)) {
		let iface_data = iface.data;
		if (!iface_data?.chassis)
			continue;

		let port_data = iface_data.port ?? {};

		for (let chassis in lldp_collection_entries(iface_data.chassis))
			push(devices, device_entry_build(iface.name, chassis.name, chassis.data, port_data, iface_data.age, iface_data));
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
 * @param {object} dev - Device data with chassis info, ports, and device_info
 * @returns {object} TR-181 formatted Discovery_Device object
 */
function device_to_object(root, dev) {
	return {
		Interface: dev.interface,
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
 * dispatch_subtree's ancestor block descends through `VendorSpecific.<inst>`
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
 * @param {object} ctx - Context with config
 * @returns {object} LLDP root with Discovery sub-object
 */
function lldp_get(ctx) {
	return {
		...ubbf.ctx_config(ctx),
		Discovery: discovery_get(ctx)
	};
}

model['Device.LLDP'] = {
	schema: schemas.LLDP,
	get: lldp_get,
	enable_status_derive: true
};

model['Device.LLDP.Discovery'] = {
	schema: schemas.Discovery,
	get: discovery_get
};

model['Device.LLDP.Discovery.Device'] = {
};

model['Device.LLDP.Discovery.Device.{i}'] = {
	schema: schemas.Discovery_Device,
	get: device_get
};

model['Device.LLDP.Discovery.Device.{i}.Port.{i}'] = {
	schema: schemas.Device_Port
};

model['Device.LLDP.Discovery.Device.{i}.Port.{i}.LinkInformation'] = {
	schema: schemas.Port_LinkInformation
};

model['Device.LLDP.Discovery.Device.{i}.DeviceInformation'] = {
	schema: schemas.Device_DeviceInformation,
	get: device_information_get
};

model['Device.LLDP.Discovery.Device.{i}.DeviceInformation.VendorSpecific.{i}'] = {
	schema: schemas.DeviceInformation_VendorSpecific
};
