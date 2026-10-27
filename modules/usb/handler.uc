'use strict';

// Out-of-tree module. `ubbf_module` is the scope datamodel.uc includes this
// file with, and it is visible only while the include runs, so anything the
// handlers below use later has to be bound here. See docs/ARCHITECTURE.md.

const ubbf = ubbf_module.ubbf;
const utils = ubbf_module.utils;
const model = ubbf_module.model;
const operations = ubbf_module.operations;

const fs = require('fs');
const usb_lib = require('usb');

const schema = ubbf_module.schema;

const USB_DEVICE_DRIVER = '/sys/bus/usb/drivers/usb';

/**
 * Converts USB speed value to TR-181 Rate enumeration.
 *
 * @param {string} speed - USB speed in Mbps
 * @returns {string} Rate value (Low, Full, High, Super)
 */
function speed_to_rate(speed) {
	let s = +speed;
	if (s <= 1.5)
		return 'Low';
	if (s <= 12)
		return 'Full';
	if (s <= 480)
		return 'High';
	return 'Super';
}

/**
 * Parses USB host controller type from product string.
 *
 * @param {string} product - USB product string
 * @returns {string} Host type (xHCI, EHCI, OHCI, UHCI, or empty)
 */
function host_type_parse(product) {
	if (!product)
		return '';
	if (index(product, 'xHCI') >= 0)
		return 'xHCI';
	if (index(product, 'EHCI') >= 0)
		return 'EHCI';
	if (index(product, 'OHCI') >= 0)
		return 'OHCI';
	if (index(product, 'UHCI') >= 0)
		return 'UHCI';
	return '';
}


/**
 * Extracts bus number from USB host name.
 *
 * @param {string} host_name - USB host name (e.g., usb1)
 * @returns {number} Bus number
 */
function host_bus_get(host_name) {
	let m = match(host_name, /^usb([0-9]+)$/);
	return m ? int(m[1]) : 0;
}

/**
 * Extracts bus number from USB device name.
 *
 * @param {string} dev_name - USB device name (e.g., 1-2)
 * @returns {number} Bus number
 */
function device_bus_get(dev_name) {
	let m = match(dev_name, /^([0-9]+)-/);
	return m ? int(m[1]) : 0;
}

/**
 * Extracts port number from USB device name.
 *
 * @param {string} dev_name - USB device name (e.g., 1-2)
 * @returns {number} Port number
 */
function device_port_get(dev_name) {
	// devices behind a hub are named <bus>-<port>.<port>...; the port
	// is the position on the parent hub, i.e. the last segment
	let m = match(dev_name, /\.([0-9]+)$/);
	if (m)
		return int(m[1]);
	m = match(dev_name, /^[0-9]+-([0-9]+)$/);
	return m ? int(m[1]) : 0;
}

/**
 * Returns the parent device sysfs name for a USB device.
 *
 * For non-root devices (containing '.') returns the name with the
 * last '.<n>' segment stripped. For root devices ("<bus>-<port>" with
 * no dot) returns the root hub host name "usb<bus>". For host names
 * returns null.
 *
 * @param {string} dev - USB device or host name
 * @returns {string|null} Parent sysfs name or null
 */
function device_parent_name(dev) {
	if (match(dev, /^usb[0-9]+$/))
		return null;

	let dot = -1;
	for (let i = length(dev) - 1; i >= 0; i--) {
		if (substr(dev, i, 1) == '.') {
			dot = i;
			break;
		}
	}
	if (dot > 0)
		return substr(dev, 0, dot);

	let m = match(dev, /^([0-9]+)-/);
	return m ? sprintf('usb%s', m[1]) : null;
}

// Port, Host, Host.{i}.Device and Interface rows follow the devices present;
// the instance map keeps each one on its number while others come and go.
// A device's key carries its identity, so another device in the same port
// gets a new number.
const PORT_TABLE = 'Device.USB.Port';
const HOST_TABLE = 'Device.USB.USBHosts.Host';
const INTERFACE_TABLE = 'Device.USB.Interface';
const instance_map = utils['instance-map'];

function device_key(dev) {
	let info = usb_lib.device_info(dev);
	return sprintf('%s|%s:%s:%s', dev, info.idVendor ?? '', info.idProduct ?? '', info.serial ?? '');
}

function port_key(name) {
	return match(name, /^usb[0-9]+$/) ? name : device_key(name);
}

function port_keys(usb) {
	return map([ ...usb.hosts, ...usb.devices ], port_key);
}

function host_device_table(host) {
	return `${HOST_TABLE}.${host}.Device`;
}

function host_devices(host, usb) {
	let bus = host_bus_get(host);
	return filter(usb.devices, (dev) => device_bus_get(dev) == bus);
}

/**
 * Resolves a USB host or device name to its Device.USB.Port.{i} number.
 *
 * @param {string} name - Host or device sysfs name
 * @param {object} usb - usb_lib.enumerate() result
 * @returns {number|null} Port instance number or null
 */
function port_instance_for_name(name, usb) {
	return instance_map.instance_numbers(PORT_TABLE, port_keys(usb))[port_key(name)];
}

/**
 * Resolves a USB device name to its Device.{i} number within its host.
 *
 * @param {string} dev - Device sysfs name (e.g. "1-2.4")
 * @param {object} usb - usb_lib.enumerate() result
 * @returns {number|null} Device instance number within the host or null
 */
function host_device_instance_for_name(dev, usb) {
	let host = sprintf('usb%d', device_bus_get(dev));
	return instance_map.instance_numbers(host_device_table(host),
		map(host_devices(host, usb), device_key))[device_key(dev)];
}

/**
 * Resolves a host sysfs name (e.g. "usb1") to its USBHosts.Host.{i} number.
 *
 * @param {string} host - Host sysfs name
 * @param {object} usb - usb_lib.enumerate() result
 * @returns {number|null} Host instance number or null
 */
function host_instance_for_name(host, usb) {
	return instance_map.instance_numbers(HOST_TABLE, usb.hosts)[host];
}

/**
 * Enumerates USB network interfaces.
 *
 * @returns {array} Array of interface objects with device, ifname, path
 */
function usb_net_interfaces_enumerate() {
	return usb_lib.net_interfaces();
}

/**
 * Returns the USB network interfaces keyed by their Device.USB.Interface
 * instance number, each kept on its number by its sysfs path.
 *
 * @returns {object} Instance number to interface entry
 */
function usb_net_interfaces_numbered() {
	let ifaces = usb_net_interfaces_enumerate();
	let by_path = {};
	for (let iface in ifaces)
		by_path[iface.path] = iface;

	return instance_map.instance_rows(INTERFACE_TABLE, keys(by_path), (path) => by_path[path]);
}

function usb_net_interface_by_instance(instance) {
	return usb_net_interfaces_numbered()[sprintf('%d', ubbf.to_int(instance) ?? 0)];
}

/**
 * Builds configuration interface instances for a USB device.
 *
 * @param {string} dev - USB device name
 * @param {object} usb - USB enumeration data
 * @returns {object} Keyed interface instances
 */
function device_config_interfaces_build(dev, usb) {
	let config_ifaces = {};
	let instance = 1;

	for (let iface in usb.interfaces) {
		if (index(iface, dev + ':') != 0)
			continue;

		let info = usb_lib.interface_info(iface);
		config_ifaces[sprintf('%d', instance++)] = {
			InterfaceNumber: sprintf('%d', info.bInterfaceNumber ?? 0),
			InterfaceClass: sprintf('%d', info.bInterfaceClass ?? 0),
			InterfaceSubClass: sprintf('%d', info.bInterfaceSubClass ?? 0),
			InterfaceProtocol: sprintf('%d', info.bInterfaceProtocol ?? 0)
		};
	}

	return config_ifaces;
}

/**
 * Builds configuration instances for a USB device.
 *
 * @param {string} dev - USB device name
 * @param {object} usb - USB enumeration data
 * @returns {object} Keyed configuration instances
 */
function device_configurations_build(dev, usb, info) {
	let config_ifaces = device_config_interfaces_build(dev, usb);

	return {
		'1': {
			ConfigurationNumber: sprintf('%d', info.bConfigurationValue ?? 0),
			InterfaceNumberOfEntries: sprintf('%d', length(keys(config_ifaces))),
			Interface: config_ifaces
		}
	};
}

/**
 * Maps a device to the visible device states of USB 2.0 table 9-1. sysfs
 * shows a device that has an address: Suspended while runtime PM suspends
 * it, Configured once it has a configuration, else Address (for example a
 * device the authorization holds back).
 *
 * @param {object} info - Result of usb_lib.device_info()
 * @returns {string} DeviceState value
 */
function device_state_get(info) {
	if (info.power_runtime_status == 'suspended')
		return 'Suspended';

	return (info.bConfigurationValue > 0) ? 'Configured' : 'Address';
}

/**
 * Builds device instances for a USB host.
 *
 * @param {string} host - USB host name
 * @param {object} usb - USB enumeration data
 * @returns {object} Keyed device instances
 */
function host_devices_build(host, usb) {
	let devs = host_devices(host, usb);
	let numbers = instance_map.instance_numbers(host_device_table(host), map(devs, device_key));
	let devices_data = {};

	for (let dev in devs) {
		let info = usb_lib.device_info(dev);
		let configurations = device_configurations_build(dev, usb, info);

		let parent_name = device_parent_name(dev);
		let usb_port_idx = parent_name ? port_instance_for_name(parent_name, usb) : null;
		let usb_port_ref = usb_port_idx ? sprintf('Device.USB.Port.%d', usb_port_idx) : '';

		let parent_ref = '';
		if (parent_name && !match(parent_name, /^usb[0-9]+$/)) {
			let parent_host_inst = host_instance_for_name(sprintf('usb%d', device_bus_get(dev)), usb);
			let parent_dev_inst = host_device_instance_for_name(parent_name, usb);
			if (parent_host_inst && parent_dev_inst)
				parent_ref = sprintf('Device.USB.USBHosts.Host.%d.Device.%d',
				                     parent_host_inst, parent_dev_inst);
		}

		devices_data[sprintf('%d', numbers[device_key(dev)])] = {
			'.name': dev,
			DeviceNumber: sprintf('%d', info.devnum ?? 0),
			USBVersion: info.version,
			DeviceClass: sprintf('%d', info.bDeviceClass ?? 0),
			DeviceSubClass: sprintf('%d', info.bDeviceSubClass ?? 0),
			DeviceVersion: sprintf('%d', info.bcdDevice ?? 0),
			DeviceProtocol: sprintf('%d', info.bDeviceProtocol ?? 0),
			ProductID: sprintf('%d', info.idProduct),
			VendorID: sprintf('%d', info.idVendor),
			Manufacturer: info.manufacturer,
			ProductClass: info.product,
			SerialNumber: info.serial,
			Port: sprintf('%d', device_port_get(dev) ?? 0),
			USBPort: usb_port_ref,
			Rate: speed_to_rate(info.speed),
			Parent: parent_ref,
			MaxChildren: sprintf('%d', info.maxchild),
			IsSuspended: (info.power_runtime_status != 'active') ? 'true' : 'false',
			IsSelfPowered: 'false',
			ConfigurationNumberOfEntries: sprintf('%d', length(keys(configurations))),
			DeviceState: device_state_get(info),
			IsAllowed: (trim(fs.readfile(`/sys/bus/usb/devices/${dev}/authorized`) ?? '1') == '0') ? 'false' : 'true',
			Configuration: configurations
		};
	}

	return devices_data;
}

/**
 * Get handler for Device.USB.
 *
 * @param {object} ctx - Context with config
 * @returns {object} USB root properties with entry counts
 */
function usb_get(ctx) {
	let usb = usb_lib.enumerate();
	let net_ifaces = usb_net_interfaces_enumerate();
	return {
		InterfaceNumberOfEntries: sprintf('%d', length(net_ifaces)),
		PortNumberOfEntries: sprintf('%d', length(usb.hosts) + length(usb.devices))
	};
}

/**
 * Converts a USB host to TR-181 Host object format.
 *
 * @param {string} host - USB host name (e.g., usb1)
 * @param {object} usb - USB enumeration data
 * @returns {object} TR-181 Host object with devices
 */
function host_to_object(host, usb) {
	let info = usb_lib.device_info(host);
	let devices = host_devices_build(host, usb);

	return {
		'.name': host,
		Alias: ubbf.alias_from_name(host),
		Enable: 'true',
		Name: host,
		Type: host_type_parse(info.product),
		PowerManagementEnable: (info.power_control == 'auto') ? 'true' : 'false',
		USBVersion: info.version,
		DeviceNumberOfEntries: sprintf('%d', length(keys(devices))),
		Device: devices
	};
}

/**
 * Get handler for Device.USB.USBHosts.
 *
 * @param {object} ctx - Context
 * @returns {object} USBHosts properties with enumerated hosts
 */
function usbhosts_get(ctx) {
	let usb = usb_lib.enumerate();
	let to_object = (host) => host_to_object(host, usb);

	return {
		...ubbf.ctx_config(ctx),
		AllowAllDevices: ctx.config?.AllowAllDevices ?? 'true',
		AllowedDeviceNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config?.AllowedDevice)),
		HostNumberOfEntries: sprintf('%d', length(usb.hosts)),
		Host: instance_map.instance_rows(HOST_TABLE, usb.hosts, to_object)
	};
}

/**
 * Get handler for Device.USB.USBHosts.Host.{i}.
 *
 * @param {object} ctx - Context with instance
 * @returns {object|null} Host properties or enumerated list
 */
function host_get(ctx) {
	let usb = usb_lib.enumerate();
	let to_object = (host) => host_to_object(host, usb);

	if (ctx.instance == null)
		return instance_map.instance_rows(HOST_TABLE, usb.hosts, to_object);

	let host = instance_map.instance_key(HOST_TABLE, usb.hosts, ctx.instance);
	if (!host)
		return null;

	return to_object(host);
}

/**
 * Builds port instances for Device.USB.Port container.
 *
 * @param {object} ctx - Context
 * @returns {object} Keyed port instances
 */
function port_power_get(port_type, info) {
	// TR-181: Power only applies to Device ports; self/bus comes from
	// the config descriptor bmAttributes self-powered bit
	if (port_type != 'Device')
		return 'Unknown';
	return (info.bmAttributes & 0x40) ? 'Self' : 'Bus';
}

function port_container_get(ctx) {
	let usb = usb_lib.enumerate();
	let numbers = instance_map.instance_numbers(PORT_TABLE, port_keys(usb));
	let port_instances = {};

	for (let host in usb.hosts) {
		let info = usb_lib.device_info(host);
		port_instances[sprintf('%d', numbers[port_key(host)])] = {
			'.name': host,
			Alias: ubbf.alias_from_name(host),
			Name: host,
			Standard: info.version,
			Type: 'Host',
			Receptacle: 'Standard-A',
			Rate: speed_to_rate(info.speed),
			Power: port_power_get('Host', info)
		};
	}

	for (let dev in usb.devices) {
		let info = usb_lib.device_info(dev);
		let port_type = (info.bDeviceClass_str == '09') ? 'Hub' : 'Device';
		port_instances[sprintf('%d', numbers[port_key(dev)])] = {
			'.name': dev,
			Alias: ubbf.alias_from_name(dev),
			Name: dev,
			Standard: info.version,
			Type: port_type,
			Receptacle: '',
			Rate: speed_to_rate(info.speed),
			Power: port_power_get(port_type, info)
		};
	}

	return port_instances;
}

/**
 * Resolves the sysfs name for a USB port by instance number.
 *
 * @param {number} instance - TR-181 instance number
 * @returns {string|null} sysfs device name
 */
function port_name_resolve(instance) {
	let key = instance_map.instance_key(PORT_TABLE, port_keys(usb_lib.enumerate()), instance);

	return (key == null) ? null : split(key, '|')[0];
}

/**
 * Get handler for Device.USB.Port.{i}.
 *
 * @param {object} ctx - Context with config
 * @returns {object|null} Port properties
 */
function port_get(ctx) {
	let name = ctx.config?.['.name'];
	if (!name)
		name = port_name_resolve(ctx.instance);
	if (!name)
		return null;

	let info = usb_lib.device_info(name);
	let is_host = match(name, /^usb[0-9]+$/);

	let port_type;
	if (is_host)
		port_type = 'Host';
	else if (info.bDeviceClass_str == '09')
		port_type = 'Hub';
	else
		port_type = 'Device';

	return {
		Alias: ubbf.alias_from_name(name),
		Name: name,
		Standard: info.version,
		Type: port_type,
		Receptacle: is_host ? 'Standard-A' : '',
		Rate: speed_to_rate(info.speed),
		Power: port_power_get(port_type, info)
	};
}

/**
 * Converts a USB network interface to TR-181 object format.
 *
 * @param {object} iface - Interface with ifname and path
 * @returns {object} TR-181 Interface object
 */
function net_iface_to_object(iface) {
	return {
		'.name': iface.ifname,
		'.path': iface.path,
		Alias: ubbf.alias_from_name(iface.ifname),
		Name: iface.ifname
	};
}

/**
 * Gets all USB network interfaces as enumerated instances.
 *
 * @param {object} ctx - Context
 * @returns {object} Enumerated interface instances
 */
function interface_container_get(ctx) {
	let rows = {};
	for (let n, iface in usb_net_interfaces_numbered())
		rows[n] = net_iface_to_object(iface);
	return rows;
}

/**
 * Builds a TR-181 USB.Interface row from a usb_net_interfaces entry.
 *
 * @param {object} iface - Entry with device, ifname, path
 * @returns {object} TR-181 Interface row
 */
function interface_row(iface) {
	let carrier = ubbf.readfile_trim(sprintf('%s/carrier', iface.path));

	return {
		Enable: 'true',
		Status: (carrier == '1') ? 'Up' : 'Down',
		Alias: ubbf.alias_from_name(iface.ifname),
		Name: iface.ifname,
		LastChange: '0',
		LowerLayers: '',
		Upstream: 'false',
		MaxBitRate: '0',
		MACAddress: ubbf.readfile_trim(sprintf('%s/address', iface.path)) || '',
		Port: ''
	};
}

/**
 * Get handler for Device.USB.Interface.{i}.
 *
 * USB interfaces are fully dynamic: no stored config exists, so both
 * enumerate mode and per-instance reads resolve from the live
 * usb_net_interfaces list.
 *
 * @param {object} ctx - Context with instance
 * @returns {object|null} Enumerated rows, single row, or null
 */
function interface_get(ctx) {
	if (ctx.instance == null) {
		let rows = {};
		for (let n, iface in usb_net_interfaces_numbered())
			rows[n] = interface_row(iface);
		return rows;
	}

	let iface = usb_net_interface_by_instance(ctx.instance);
	if (!iface?.ifname)
		return null;
	return interface_row(iface);
}

/**
 * Get handler for Device.USB.Interface.{i}.Stats.
 *
 * @param {object} ctx - Context with parent
 * @returns {object|null} Interface statistics
 */
function usb_interface_stats_get(ctx) {
	let instance = ctx.parent?.['.instance'] ?? ctx.instance;
	let iface = usb_net_interface_by_instance(instance);
	if (!iface?.ifname)
		return null;

	return utils.ifstats.ifstats_get(iface.ifname);
}

/**
 * Sync operation handler for USB.Interface.{i}.Stats.Reset().
 *
 * @param {object} input - Operation input (unused)
 * @param {string} command_key - Command key (unused)
 * @param {array} instances - Instance numbers from path match
 * @returns {object|null} Empty object on success, null on failure
 */
function usb_interface_stats_reset(input, command_key, instances) {
	let idx = instances[0];
	if (idx == null)
		return null;

	let iface = usb_net_interface_by_instance(idx);
	if (!iface?.ifname)
		return null;

	if (!utils.ifstats.ifstats_reset(iface.ifname))
		return null;
	return {};
}

/**
 * Sync operation handler for USB.USBHosts.Host.{i}.Reset().
 *
 * Unbinds and rebinds the root hub from the USB-core device driver.
 * This drops every device on the bus via usb_disconnect(), then
 * re-enumerates them via usb_probe_device() -> hub_port_init(), which
 * issues SetPortFeature(PORT_RESET) on each occupied downstream port.
 *
 * Does not toggle the host controller's HCRST bit (would require
 * walking up to the platform/PCI parent), but achieves the
 * user-visible effect of "reset signaling on all downstream ports"
 * portably across controller types.
 *
 * @param {object} input - Operation input (unused)
 * @param {string} command_key - Command key (unused)
 * @param {array} instances - Instance numbers from path match
 * @returns {object|null} Empty object on success, null on failure
 */
function host_reset(input, command_key, instances) {
	let idx = instances[0];
	if (idx == null)
		return null;

	let host = instance_map.instance_key(HOST_TABLE, usb_lib.enumerate().hosts, idx);
	if (!host)
		return null;

	if (fs.writefile(sprintf('%s/unbind', USB_DEVICE_DRIVER), host) == null)
		return null;
	if (fs.writefile(sprintf('%s/bind', USB_DEVICE_DRIVER), host) == null)
		return null;

	return {};
}

model['Device.USB'] = {
	schema: schema('USB'),
	get: usb_get
};

model['Device.USB.Interface'] = {
	get: interface_container_get
};

model['Device.USB.Interface.{i}'] = {
	schema: schema('Interface'),
	get: interface_get
};

model['Device.USB.Interface.{i}.Stats'] = {
	schema: schema('Interface_Stats'),
	get: usb_interface_stats_get
};

model['Device.USB.Port'] = {
	get: port_container_get
};

model['Device.USB.Port.{i}'] = {
	schema: schema('Port'),
	get: port_get
};

model['Device.USB.USBHosts'] = {
	schema: schema('USBHosts'),
	get: usbhosts_get
};

model['Device.USB.USBHosts.AllowedDevice'] = {
	since: '2.20'
};

model['Device.USB.USBHosts.AllowedDevice.{i}'] = {
	schema: schema('AllowedDevice'),
	get: ubbf.ctx_config,
	since: '2.20'
};

model['Device.USB.USBHosts.Host'] = {};

model['Device.USB.USBHosts.Host.{i}'] = {
	schema: schema('Host'),
	get: host_get,
	addable: false
};

model['Device.USB.USBHosts.Host.{i}.Device'] = {};

model['Device.USB.USBHosts.Host.{i}.Device.{i}'] = {
	schema: schema('Host_Device')
};

model['Device.USB.USBHosts.Host.{i}.Device.{i}.Configuration'] = {};

model['Device.USB.USBHosts.Host.{i}.Device.{i}.Configuration.{i}'] = {
	schema: schema('Device_Configuration')
};

model['Device.USB.USBHosts.Host.{i}.Device.{i}.Configuration.{i}.Interface'] = {};

model['Device.USB.USBHosts.Host.{i}.Device.{i}.Configuration.{i}.Interface.{i}'] = {
	schema: schema('Configuration_Interface')
};

operations['Device.USB.USBHosts.Host.{i}.Reset()'] = {
	type: 'sync',
	handler: host_reset
};

operations['Device.USB.Interface.{i}.Stats.Reset()'] = {
	type: 'sync',
	handler: usb_interface_stats_reset
};
