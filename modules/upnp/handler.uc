'use strict';

// Out-of-tree module. `ubbf_module` is the scope datamodel.uc includes this
// file with, and it is visible only while the include runs, so anything the
// handlers below use later has to be bound here. See docs/ARCHITECTURE.md.

const ubbf = ubbf_module.ubbf;
const model = ubbf_module.model;
const utils = ubbf_module.utils;

const ubus = require('ubus');

const schema = ubbf_module.schema;
const schema_defaults = ubbf_module.schema_defaults;

const IP_INTERFACE_RE = regexp('^Device\\.IP\\.Interface\\.[0-9]+$');

// TR-181 has no size on the URL data type; TR-106 gives URL 2048.
const URL_MAX = 2048;

const clamp = utils.helpers.text_clamp;

/**
 * Fetches one discovery table from upnpd.
 *
 * @param {string} table - Table name of `upnpd discovery`
 * @returns {array} Rows, empty when upnpd is not running
 */
function discovery_table_fetch(table) {
	return ubus?.call('upnpd', 'discovery', { table })?.[table] ?? [];
}

/**
 * Returns one discovery table, cached for the request.
 *
 * @param {string} table - Table name of `upnpd discovery`
 * @returns {array} Rows
 */
function table_get(table) {
	return utils.cache.call(discovery_table_fetch, table);
}

/**
 * Fetches the row counts of the discovery tables from upnpd.
 *
 * @returns {object} Count per table name, empty when upnpd is not running
 */
function discovery_counts_fetch() {
	return ubus?.call('upnpd', 'discovery_counts', {}) ?? {};
}

/**
 * Returns the row count of one discovery table as a TR-181 value.
 *
 * @param {string} table - Table name
 * @returns {string} Count
 */
function table_count(table) {
	return sprintf('%d', utils.cache.call(discovery_counts_fetch)?.[table] ?? 0);
}

/**
 * Builds the enumerate result of a runtime table keyed by the daemon's row
 * id, so a row keeps its instance number while it exists.
 *
 * @param {array} rows - Daemon rows with an `id`
 * @param {function} convert - Row converter
 * @param {object} ctx - Handler context
 * @returns {object|null} One instance or all instances
 */
function rows_get(rows, convert, ctx) {
	if (ctx.instance) {
		for (let row in rows)
			if (row.id == ctx.instance)
				return convert(row);

		return null;
	}

	let result = {};

	for (let row in rows)
		result[sprintf('%d', row.id)] = convert(row);

	return result;
}

/**
 * Finds the Device.UPnP.Discovery.Device row of a UUID for parent paths.
 *
 * @param {string} uuid - Device UUID
 * @returns {string} Device.UPnP.Discovery.Device.{i} path or ''
 */
function discovery_device_path(uuid) {
	for (let row in table_get('devices'))
		if (row.uuid == uuid)
			return sprintf('Device.UPnP.Discovery.Device.%d', row.id);

	for (let row in table_get('root_devices'))
		if (row.uuid == uuid)
			return sprintf('Device.UPnP.Discovery.RootDevice.%d', row.id);

	return '';
}

/**
 * Finds the Device.UPnP.Discovery.Service row for a service type of a UUID.
 *
 * @param {string} uuid - Device UUID
 * @param {string} service_type - Service type URN
 * @returns {string} Device.UPnP.Discovery.Service.{i} path or ''
 */
function discovery_service_path(uuid, service_type) {
	for (let row in table_get('services'))
		if (row.uuid == uuid && row.type == service_type)
			return sprintf('Device.UPnP.Discovery.Service.%d', row.id);

	return '';
}

/**
 * Returns the Device.Hosts.Host path of the device that sent a row: by MAC
 * address when the ARP table knows it, else by IP address, which also
 * finds an IPv6 sender.
 *
 * @param {object} ctx - Handler context
 * @param {object} row - Daemon row or description with host_mac, host_ip
 * @returns {string} Host path or ''
 */
function host_ref(ctx, row) {
	let path = row.host_mac ? utils.hosts.host_path_by_mac(ctx.root, row.host_mac) : '';

	if (!path && row.host_ip)
		path = utils.hosts.host_path_by_ip(ctx.root, row.host_ip);

	return path ?? '';
}

/**
 * Converts a daemon SSDP row to a Discovery row.
 *
 * @param {object} row - Daemon row
 * @param {object} ctx - Handler context
 * @param {object} defaults - Schema defaults of the table
 * @returns {object} Discovery row
 */
function discovery_row_to_object(row, ctx, defaults) {
	return {
		...defaults,
		Status: row.status ?? defaults.Status,
		UUID: clamp(row.uuid, 36),
		USN: clamp(row.usn, 256),
		LeaseTime: sprintf('%d', row.max_age ?? 0),
		Location: clamp(row.location, URL_MAX),
		Server: clamp(row.server, 256),
		Host: host_ref(ctx, row),
		LastUpdate: utils.helpers.datetime_format(row.last_update)
	};
}

/**
 * Get handler for Device.UPnP.Device.
 *
 * @param {object} ctx - Handler context
 * @returns {object} Stored parameters over the defaults, with the row count
 */
function upnp_device_get(ctx) {
	return {
		...schema_defaults('UPnP_Device'),
		...(ctx.config ?? {}),
		X_UBBF_InterfaceNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config?.X_UBBF_Interface))
	};
}

/**
 * Returns the Status of a Device.UPnP.Device.X_UBBF_Interface row.
 *
 * @param {object} root - Data model root
 * @param {object} row - Stored row
 * @returns {string} Disabled, Error, Down or Up
 */
function interface_status(root, row) {
	if (!ubbf.to_bool(row.Enable))
		return 'Disabled';

	if (!match(row.Interface ?? '', IP_INTERFACE_RE) || !ubbf.interface_to_name(root, row.Interface))
		return 'Error';

	let dev = ubbf.get(root, 'Device.UPnP.Device');
	let iface = ubbf.get(root, row.Interface);

	if (!ubbf.to_bool(dev?.Enable) || !ubbf.to_bool(iface?.Enable))
		return 'Down';

	return 'Up';
}

/**
 * Get handler for Device.UPnP.Device.X_UBBF_Interface.{i}.
 *
 * @param {object} ctx - Handler context
 * @returns {object|null} Stored parameters with Status
 */
function interface_get(ctx) {
	if (!ctx.config)
		return null;

	return {
		...schema_defaults('UPnP_Device_Interface'),
		...ctx.config,
		Status: interface_status(ctx.root, ctx.config)
	};
}

/**
 * Set handler for Device.UPnP.Device.X_UBBF_Interface.{i}: Interface must
 * name a Device.IP.Interface row.
 *
 * @param {object} ctx - Set context with param and value
 * @returns {number} 0 to accept, -1 to refuse
 */
function interface_set(ctx) {
	if (ctx.param == 'Interface' && ctx.value != '' && !match(ctx.value, IP_INTERFACE_RE))
		return -1;

	return 0;
}

/**
 * Get handler for Device.UPnP.Device.Capabilities.
 *
 * @param {object} ctx - Handler context
 * @returns {object} Fixed capabilities
 */
function capabilities_get(ctx) {
	return { ...schema_defaults('UPnP_Device_Capabilities') };
}

/**
 * Get handler for Device.UPnP.Discovery: the row counts.
 *
 * @param {object} ctx - Handler context
 * @returns {object} NumberOfEntries values
 */
function discovery_counts_get(ctx) {
	return {
		RootDeviceNumberOfEntries: table_count('root_devices'),
		DeviceNumberOfEntries: table_count('devices'),
		ServiceNumberOfEntries: table_count('services')
	};
}

/**
 * Get handler for Device.UPnP.Discovery.RootDevice.{i}.
 *
 * @param {object} ctx - Handler context
 * @returns {object|null} One row or all rows
 */
function root_device_get(ctx) {
	return rows_get(table_get('root_devices'),
		row => discovery_row_to_object(row, ctx, schema_defaults('UPnP_Discovery_RootDevice')), ctx);
}

/**
 * Get handler for Device.UPnP.Discovery.Device.{i}.
 *
 * @param {object} ctx - Handler context
 * @returns {object|null} One row or all rows
 */
function device_get(ctx) {
	return rows_get(table_get('devices'),
		row => discovery_row_to_object(row, ctx, schema_defaults('UPnP_Discovery_Device')), ctx);
}

/**
 * Get handler for Device.UPnP.Discovery.Service.{i}.
 *
 * @param {object} ctx - Handler context
 * @returns {object|null} One row or all rows
 */
function service_get(ctx) {
	return rows_get(table_get('services'), function(row) {
		let obj = discovery_row_to_object(row, ctx, schema_defaults('UPnP_Discovery_Service'));

		delete obj.UUID;
		obj.ParentDevice = discovery_device_path(row.uuid);

		return obj;
	}, ctx);
}

/**
 * Get handler for Device.UPnP.Description: the row counts.
 *
 * @param {object} ctx - Handler context
 * @returns {object} NumberOfEntries values
 */
function description_counts_get(ctx) {
	return {
		DeviceDescriptionNumberOfEntries: table_count('descriptions'),
		DeviceInstanceNumberOfEntries: table_count('device_instances'),
		ServiceInstanceNumberOfEntries: table_count('service_instances')
	};
}

/**
 * Get handler for Device.UPnP.Description.DeviceDescription.{i}.
 *
 * @param {object} ctx - Handler context
 * @returns {object|null} One row or all rows
 */
function device_description_get(ctx) {
	return rows_get(table_get('descriptions'), function(desc) {
		return {
			...schema_defaults('UPnP_Description_DeviceDescription'),
			URLBase: clamp(desc.urlbase, URL_MAX),
			SpecVersion: clamp(desc.spec_version, 256),
			Host: host_ref(ctx, desc)
		};
	}, ctx);
}

/**
 * Returns the Device.UPnP.Description.DeviceInstance.{i} path of a UDN.
 *
 * @param {string} udn - Device UDN without the uuid: prefix
 * @returns {string} Path or ''
 */
function device_instance_path(udn) {
	for (let dev in table_get('device_instances'))
		if (dev.udn == udn)
			return sprintf('Device.UPnP.Description.DeviceInstance.%d', dev.id);

	return '';
}

/**
 * Get handler for Device.UPnP.Description.DeviceInstance.{i}.
 *
 * @param {object} ctx - Handler context
 * @returns {object|null} One row or all rows
 */
function device_instance_get(ctx) {
	return rows_get(table_get('device_instances'), function(dev) {
		return {
			...schema_defaults('UPnP_Description_DeviceInstance'),
			UDN: clamp(dev.udn, 36),
			ParentDevice: dev.parent_udn ? device_instance_path(dev.parent_udn) : '',
			DiscoveryDevice: discovery_device_path(dev.udn),
			DeviceType: clamp(dev.device_type, 256),
			FriendlyName: clamp(dev.friendly_name, 128),
			Manufacturer: clamp(dev.manufacturer, 128),
			ManufacturerURL: clamp(dev.manufacturer_url, URL_MAX),
			ModelDescription: clamp(dev.model_description, 256),
			ModelName: clamp(dev.model_name, 64),
			ModelNumber: clamp(dev.model_number, 64),
			ModelURL: clamp(dev.model_url, URL_MAX),
			SerialNumber: clamp(dev.serial_number, 128),
			UPC: clamp(dev.upc, 12),
			PresentationURL: clamp(dev.presentation_url, URL_MAX)
		};
	}, ctx);
}

/**
 * Get handler for Device.UPnP.Description.ServiceInstance.{i}.
 *
 * @param {object} ctx - Handler context
 * @returns {object|null} One row or all rows
 */
function service_instance_get(ctx) {
	return rows_get(table_get('service_instances'), function(svc) {
		return {
			...schema_defaults('UPnP_Description_ServiceInstance'),
			ParentDevice: device_instance_path(svc.udn),
			ServiceId: clamp(svc.service_id, 256),
			ServiceDiscovery: discovery_service_path(svc.udn, svc.service_type),
			ServiceType: clamp(svc.service_type, 256),
			SCPDURL: clamp(svc.scpd_url, URL_MAX),
			ControlURL: clamp(svc.control_url, URL_MAX),
			EventSubURL: clamp(svc.event_sub_url, URL_MAX)
		};
	}, ctx);
}

/**
 * Del hook of the discovery and description tables: the rows mirror what
 * the LAN announces, so a controller cannot delete them.
 *
 * @param {object} ctx - { path, instance }
 * @returns {number} -USP_ERR_OBJECT_NOT_DELETABLE
 */
function discovery_row_del(ctx) {
	return -USP_ERR_OBJECT_NOT_DELETABLE;
}

/**
 * Firewall hook for Device.UPnP.Device: on every interface of an enabled
 * X_UBBF_Interface row, SSDP while UPnP is on and the control port while
 * the IGD is on too. Discovery without the IGD needs SSDP alone.
 *
 * @param {object} inst - UPnP.Device config object
 * @param {object} root - Root config data
 * @param {string} path - Instance path
 * @returns {array|null} Service descriptors
 */
function upnp_firewall(inst, root, path) {
	let cfg = { ...schema_defaults('UPnP_Device'), ...(inst ?? {}) };

	if (!ubbf.to_bool(cfg.Enable))
		return null;

	let igd = ubbf.to_bool(cfg.UPnPIGD);
	let descriptors = [];

	for (let key, row in cfg.X_UBBF_Interface ?? {}) {
		if (type(row) != 'object' || interface_status(root, row) != 'Up')
			continue;

		let name = ubbf.interface_to_name(root, row.Interface);

		push(descriptors, {
			type: 'Service',
			alias: sprintf('cpe-upnp-ssdp-%s', name),
			Interface: row.Interface,
			Protocol: '17',
			DestPort: '1900',
			Action: 'Accept'
		});

		if (igd)
			push(descriptors, {
				type: 'Service',
				alias: sprintf('cpe-upnp-http-%s', name),
				Interface: row.Interface,
				Protocol: '6',
				DestPort: '5000',
				Action: 'Accept'
			});
	}

	return length(descriptors) > 0 ? descriptors : null;
}

model['Device.UPnP'] = {
	schema: schema('UPnP')
};

model['Device.UPnP.Device'] = {
	schema: schema('UPnP_Device'),
	get: upnp_device_get,
	firewall: upnp_firewall
};

model['Device.UPnP.Device.X_UBBF_Interface'] = {
};

model['Device.UPnP.Device.X_UBBF_Interface.{i}'] = {
	schema: schema('UPnP_Device_Interface'),
	get: interface_get,
	set: interface_set
};

model['Device.UPnP.Device.IGD'] = {
	schema: schema('UPnP_Device_IGD'),
	since: '2.20'
};

model['Device.UPnP.Device.Capabilities'] = {
	schema: schema('UPnP_Device_Capabilities'),
	get: capabilities_get
};

model['Device.UPnP.Discovery'] = {
	schema: schema('UPnP_Discovery'),
	get: discovery_counts_get
};

model['Device.UPnP.Discovery.RootDevice'] = {
};

model['Device.UPnP.Discovery.RootDevice.{i}'] = {
	schema: schema('UPnP_Discovery_RootDevice'),
	get: root_device_get,
	del: discovery_row_del,
	addable: false
};

model['Device.UPnP.Discovery.Device'] = {
};

model['Device.UPnP.Discovery.Device.{i}'] = {
	schema: schema('UPnP_Discovery_Device'),
	get: device_get,
	del: discovery_row_del,
	addable: false
};

model['Device.UPnP.Discovery.Service'] = {
};

model['Device.UPnP.Discovery.Service.{i}'] = {
	schema: schema('UPnP_Discovery_Service'),
	get: service_get,
	del: discovery_row_del,
	addable: false
};

model['Device.UPnP.Description'] = {
	schema: schema('UPnP_Description'),
	get: description_counts_get
};

model['Device.UPnP.Description.DeviceDescription'] = {
};

model['Device.UPnP.Description.DeviceDescription.{i}'] = {
	schema: schema('UPnP_Description_DeviceDescription'),
	get: device_description_get,
	del: discovery_row_del,
	addable: false
};

model['Device.UPnP.Description.DeviceInstance'] = {
};

model['Device.UPnP.Description.DeviceInstance.{i}'] = {
	schema: schema('UPnP_Description_DeviceInstance'),
	get: device_instance_get,
	del: discovery_row_del,
	addable: false
};

model['Device.UPnP.Description.ServiceInstance'] = {
};

model['Device.UPnP.Description.ServiceInstance.{i}'] = {
	schema: schema('UPnP_Description_ServiceInstance'),
	get: service_instance_get,
	del: discovery_row_del,
	addable: false
};
