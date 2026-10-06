'use strict';

import * as fs from 'fs';
import * as schemas from 'ubbf.schemas.USB';
import * as ubbf from 'ubbf';
import { ifstats_get, ifstats_reset } from 'ubbf.utils.ifstats';

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

/**
 * Resolves a USB host or device name to its Device.USB.Port.{i} index.
 *
 * Mirrors port_container_get ordering: hosts first then devices, in
 * ubbf.usb_enumerate() sorted order.
 *
 * @param {string} name - Host or device sysfs name
 * @param {object} usb - ubbf.usb_enumerate() result
 * @returns {number|null} Port instance number (1-based) or null
 */
function port_instance_for_name(name, usb) {
	let idx = 1;
	for (let h in usb.hosts) {
		if (h == name)
			return idx;
		idx++;
	}
	for (let d in usb.devices) {
		if (d == name)
			return idx;
		idx++;
	}
	return null;
}

/**
 * Resolves a USB device name to its Device.{i} index within its host.
 *
 * Mirrors host_devices_build ordering: per-bus filtered, sorted.
 *
 * @param {string} dev - Device sysfs name (e.g. "1-2.4")
 * @param {object} usb - ubbf.usb_enumerate() result
 * @returns {number|null} Device instance number within the host or null
 */
function host_device_instance_for_name(dev, usb) {
	let bus = device_bus_get(dev);
	let idx = 1;
	for (let d in usb.devices) {
		if (device_bus_get(d) != bus)
			continue;
		if (d == dev)
			return idx;
		idx++;
	}
	return null;
}

/**
 * Resolves a host sysfs name (e.g. "usb1") to its USBHosts.Host.{i} index.
 *
 * @param {string} host - Host sysfs name
 * @param {object} usb - ubbf.usb_enumerate() result
 * @returns {number|null} Host instance number (1-based) or null
 */
function host_instance_for_name(host, usb) {
	let idx = 1;
	for (let h in usb.hosts) {
		if (h == host)
			return idx;
		idx++;
	}
	return null;
}

/**
 * Enumerates USB network interfaces.
 *
 * @returns {array} Array of interface objects with device, ifname, path
 */
function usb_net_interfaces_enumerate() {
	return ubbf.usb_net_interfaces();
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

		let info = ubbf.usb_interface_info(iface);
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
 * Builds device instances for a USB host.
 *
 * @param {string} host - USB host name
 * @param {object} usb - USB enumeration data
 * @returns {object} Keyed device instances
 */
function host_devices_build(host, usb) {
	let bus = host_bus_get(host);
	let devices_data = {};
	let instance = 1;

	for (let dev in usb.devices) {
		if (device_bus_get(dev) != bus)
			continue;

		let info = ubbf.usb_device_info(dev);
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

		devices_data[sprintf('%d', instance++)] = {
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
			ConfigurationNumberOfEntries: sprintf('%d', info.bNumConfigurations ?? 0),
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
	let usb = ubbf.usb_enumerate();
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
	let info = ubbf.usb_device_info(host);
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
	let usb = ubbf.usb_enumerate();
	let to_object = (host) => host_to_object(host, usb);

	return {
		HostNumberOfEntries: sprintf('%d', length(usb.hosts)),
		Host: ubbf.enumerate_instances(usb.hosts, to_object)
	};
}

/**
 * Get handler for Device.USB.USBHosts.Host.{i}.
 *
 * @param {object} ctx - Context with instance
 * @returns {object|null} Host properties or enumerated list
 */
function host_get(ctx) {
	let usb = ubbf.usb_enumerate();
	let to_object = (host) => host_to_object(host, usb);

	if (ctx.instance == null)
		return ubbf.enumerate_instances(usb.hosts, to_object);

	let host = ubbf.get_by_instance(usb.hosts, ctx.instance);
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
	let usb = ubbf.usb_enumerate();
	let port_instances = {};
	let instance = 1;

	for (let host in usb.hosts) {
		let info = ubbf.usb_device_info(host);
		port_instances[sprintf('%d', instance++)] = {
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
		let info = ubbf.usb_device_info(dev);
		let port_type = (info.bDeviceClass_str == '09') ? 'Hub' : 'Device';
		port_instances[sprintf('%d', instance++)] = {
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
	let usb = ubbf.usb_enumerate();
	let all = [...usb.hosts, ...usb.devices];

	return ubbf.get_by_instance(all, instance);
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

	let info = ubbf.usb_device_info(name);
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
	let net_ifaces = usb_net_interfaces_enumerate();
	return ubbf.enumerate_instances(net_ifaces, net_iface_to_object);
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
	if (ctx.instance == null)
		return ubbf.enumerate_instances(usb_net_interfaces_enumerate(), interface_row);

	let iface = ubbf.get_by_instance(usb_net_interfaces_enumerate(), ctx.instance);
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
	let iface = ubbf.get_by_instance(usb_net_interfaces_enumerate(), instance);
	if (!iface?.ifname)
		return null;

	return ifstats_get(iface.ifname);
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

	let net_ifaces = usb_net_interfaces_enumerate();
	let iface = ubbf.get_by_instance(net_ifaces, idx);
	if (!iface?.ifname)
		return null;

	if (!ifstats_reset(iface.ifname))
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

	let usb = ubbf.usb_enumerate();
	let host = ubbf.get_by_instance(usb.hosts, idx);
	if (!host)
		return null;

	if (fs.writefile(sprintf('%s/unbind', USB_DEVICE_DRIVER), host) == null)
		return null;
	if (fs.writefile(sprintf('%s/bind', USB_DEVICE_DRIVER), host) == null)
		return null;

	return {};
}

export const model = {
	'Device.USB': {
		schema: schemas.USB,
		get: usb_get
	},

	'Device.USB.Interface': {
		get: interface_container_get
	},

	'Device.USB.Interface.{i}': {
		schema: schemas.Interface,
		get: interface_get
	},

	'Device.USB.Interface.{i}.Stats': {
		schema: schemas.Interface_Stats,
		get: usb_interface_stats_get
	},

	'Device.USB.Port': {
		get: port_container_get
	},

	'Device.USB.Port.{i}': {
		schema: schemas.Port,
		get: port_get
	},

	'Device.USB.USBHosts': {
		schema: schemas.USBHosts,
		get: usbhosts_get
	},

	'Device.USB.USBHosts.Host': {
	},

	'Device.USB.USBHosts.Host.{i}': {
		schema: schemas.Host,
		get: host_get
	},

	'Device.USB.USBHosts.Host.{i}.Device': {
	},

	'Device.USB.USBHosts.Host.{i}.Device.{i}': {
		schema: schemas.Host_Device
	},

	'Device.USB.USBHosts.Host.{i}.Device.{i}.Configuration': {
	},

	'Device.USB.USBHosts.Host.{i}.Device.{i}.Configuration.{i}': {
		schema: schemas.Device_Configuration
	},

	'Device.USB.USBHosts.Host.{i}.Device.{i}.Configuration.{i}.Interface': {
	},

	'Device.USB.USBHosts.Host.{i}.Device.{i}.Configuration.{i}.Interface.{i}': {
		schema: schemas.Configuration_Interface
	}
};

export const operations = {
	'Device.USB.USBHosts.Host.{i}.Reset()': {
		type: 'sync',
		handler: host_reset
	},

	'Device.USB.Interface.{i}.Stats.Reset()': {
		type: 'sync',
		handler: usb_interface_stats_reset
	}
};
