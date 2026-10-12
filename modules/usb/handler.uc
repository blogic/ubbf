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

const USB_DEVICES = '/sys/bus/usb/devices';
const USB_DEVICE_DRIVER = '/sys/bus/usb/drivers/usb';

/**
 * Converts USB speed value to TR-181 Rate enumeration.
 *
 * @param {string} speed - USB speed in Mbps
 * @returns {string|null} Rate value (Low, Full, High, Super), or null
 *          when the speed is not a positive number
 */
function speed_to_rate(speed) {
	let s = +speed;
	if (!(s > 0))
		return null;
	if (s <= 1.5)
		return 'Low';
	if (s <= 12)
		return 'Full';
	if (s <= 480)
		return 'High';
	return 'Super';
}

/**
 * Returns the TR-181 Port.{i}.Rate of a port. The enum has no Unknown, so
 * a port without a speed takes the top rate of its USB version.
 *
 * @param {object} info - Result of usb_lib.device_info()
 * @returns {string} Low, Full, High or Super
 */
function port_rate_get(info) {
	let rate = speed_to_rate(info.speed);
	if (rate)
		return rate;

	let version = +trim(info.version ?? '');
	if (version >= 3)
		return 'Super';
	if (version >= 2)
		return 'High';
	return (version >= 1) ? 'Full' : 'Low';
}

/**
 * Parses USB host controller type from product string.
 *
 * @param {string} product - USB product string
 * @returns {string} Host type (xHCI, EHCI, OHCI, UHCI, or Unknown)
 */
function host_type_parse(product) {
	for (let type in [ 'xHCI', 'EHCI', 'OHCI', 'UHCI' ])
		if (index(product ?? '', type) >= 0)
			return type;
	return 'Unknown';
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

// Port, Host, Host.{i}.Device and Interface rows follow the ports and
// devices present; the instance map keeps each one on its number while
// others come and go. A device's key carries its identity, so another
// device in the same port gets a new number.
const PORT_TABLE = 'Device.USB.Port';
const HOST_TABLE = 'Device.USB.USBHosts.Host';
const INTERFACE_TABLE = 'Device.USB.Interface';

function link_name(path) {
	let target = fs.readlink(path);
	return target ? fs.basename(target) : null;
}

/**
 * Lists the ports of the root hubs and hub devices, the physical ports
 * of TR-181 Device.USB.Port. The USB 2 and USB 3 halves of one port are
 * peers in sysfs and make one port, named after the lower of the two.
 *
 * @param {array} hubs - Names of the root hubs and hub devices
 * @returns {object} { ports: port name to { hubs, devices }, port_of: sysfs
 *          port name to port name }
 */
function hub_ports_read(hubs) {
	let ports = {};
	let port_of = {};

	for (let hub in hubs) {
		let root = match(hub, /^usb([0-9]+)$/);
		let dir = `${USB_DEVICES}/${root ? root[1] + '-0' : hub}:1.0`;

		for (let entry in sort(fs.lsdir(dir) ?? [])) {
			if (!match(entry, /-port[0-9]+$/))
				continue;

			let peer = link_name(`${dir}/${entry}/peer`);
			let name = (peer && peer < entry) ? peer : entry;
			let device = link_name(`${dir}/${entry}/device`);

			ports[name] ??= { hubs: [], devices: [] };
			push(ports[name].hubs, hub);
			if (device)
				push(ports[name].devices, device);
			port_of[entry] = name;
		}
	}

	return { ports, port_of };
}

/**
 * Reads the USB tree once: the names of usb_lib.enumerate(), the
 * device_info() of each host and device and the hub ports. A node that is
 * gone by the time of its read is left out, so all rows of one request
 * agree.
 *
 * @returns {object} { hosts, devices, interfaces, info: name to
 *          device_info(), ports, port_of: see hub_ports_read() }
 */
function usb_snapshot_fetch() {
	let usb = usb_lib.enumerate();
	let info = {};
	for (let name in [ ...usb.hosts, ...usb.devices ])
		info[name] = usb_lib.device_info(name);

	let present = (name) => info[name] != null;
	let hosts = filter(usb.hosts, present);
	let devices = filter(usb.devices, present);
	let hubs = [ ...hosts, ...filter(devices, (dev) => info[dev].bDeviceClass_str == '09') ];

	return {
		hosts,
		devices,
		interfaces: usb.interfaces,
		info,
		...hub_ports_read(hubs)
	};
}

function usb_snapshot() {
	return ubbf.cache_call(usb_snapshot_fetch);
}

function device_key(dev, usb) {
	let info = usb.info[dev] ?? {};
	return sprintf('%s|%s:%s:%s', dev, info.idVendor ?? '', info.idProduct ?? '', info.serial ?? '');
}

function port_keys(usb) {
	return sort(keys(usb.ports));
}

function host_device_table(host) {
	return `${HOST_TABLE}.${host}.Device`;
}

function host_devices(host, usb) {
	let bus = host_bus_get(host);
	return filter(usb.devices, (dev) => device_bus_get(dev) == bus);
}

/**
 * Resolves a USB device to the Device.USB.Port.{i} number of the hub port
 * it is plugged into: port <p> of its parent hub, named
 * `<parent>-port<p>` in sysfs.
 *
 * @param {string} dev - Device sysfs name
 * @param {object} usb - usb_snapshot() result
 * @returns {number|null} Port instance number or null
 */
function port_instance_for_device(dev, usb) {
	let port = usb.port_of[sprintf('%s-port%d', device_parent_name(dev), device_port_get(dev))];
	return port ? ubbf.instance_numbers(PORT_TABLE, port_keys(usb))[port] : null;
}

/**
 * Resolves a USB device name to its Device.{i} number within its host.
 *
 * @param {string} dev - Device sysfs name (e.g. "1-2.4")
 * @param {object} usb - usb_snapshot() result
 * @returns {number|null} Device instance number within the host or null
 */
function host_device_instance_for_name(dev, usb) {
	let host = sprintf('usb%d', device_bus_get(dev));
	return ubbf.instance_numbers(host_device_table(host),
		map(host_devices(host, usb), (d) => device_key(d, usb)))[device_key(dev, usb)];
}

/**
 * Resolves a host sysfs name (e.g. "usb1") to its USBHosts.Host.{i} number.
 *
 * @param {string} host - Host sysfs name
 * @param {object} usb - usb_snapshot() result
 * @returns {number|null} Host instance number or null
 */
function host_instance_for_name(host, usb) {
	return ubbf.instance_numbers(HOST_TABLE, usb.hosts)[host];
}

/**
 * Returns the USB network interfaces keyed by their Device.USB.Interface
 * instance number, each kept on its number by its sysfs path.
 *
 * @returns {object} Instance number to interface entry
 */
function usb_net_interfaces_numbered() {
	let ifaces = ubbf.cache_call(usb_lib.net_interfaces);
	let by_path = {};
	for (let iface in ifaces)
		by_path[iface.path] = iface;

	return ubbf.instance_rows(INTERFACE_TABLE, keys(by_path), (path) => by_path[path]);
}

function usb_net_interface_by_instance(instance) {
	return usb_net_interfaces_numbered()[sprintf('%d', ubbf.to_int(instance) ?? 0)];
}

/**
 * Counts the rows of Device.USB.Interface: the USB netdevs and the stored
 * rows whose netdev is gone.
 *
 * @param {object|null} stored - Stored rows of the table
 * @returns {number} Number of rows
 */
function interface_count(stored) {
	let rows = { ...(stored ?? {}) };

	for (let n in keys(usb_net_interfaces_numbered()))
		rows[n] = true;
	return length(filter(keys(rows), ubbf.is_instance_key));
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
		if (!info)
			continue;

		config_ifaces[sprintf('%d', instance++)] = {
			InterfaceNumber: sprintf('%d', info.bInterfaceNumber ?? 0),
			InterfaceClass: sprintf('%02x', info.bInterfaceClass ?? 0),
			InterfaceSubClass: sprintf('%02x', info.bInterfaceSubClass ?? 0),
			InterfaceProtocol: sprintf('%02x', info.bInterfaceProtocol ?? 0)
		};
	}

	return config_ifaces;
}

/**
 * Builds configuration instances for a USB device. sysfs shows the active
 * configuration only, so a device has one row, or none while it is not
 * configured.
 *
 * @param {string} dev - USB device name
 * @param {object} usb - USB enumeration data
 * @param {object} info - Result of usb_lib.device_info()
 * @returns {object} Keyed configuration instances
 */
function device_configurations_build(dev, usb, info) {
	if (!(info.bConfigurationValue > 0))
		return {};

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
 * Returns the TR-181 Port.{i}.Power of a port.
 *
 * @param {string} port_type - Port Type (Host, Hub or Device)
 * @param {object} info - Result of usb_lib.device_info()
 * @returns {string} Self, Bus or Unknown
 */
function port_power_get(port_type, info) {
	// TR-181: Power only applies to Device ports; self/bus comes from
	// the config descriptor bmAttributes self-powered bit
	if (port_type != 'Device')
		return 'Unknown';
	return (info.bmAttributes & 0x40) ? 'Self' : 'Bus';
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
	let numbers = ubbf.instance_numbers(host_device_table(host), map(devs, (d) => device_key(d, usb)));
	let devices_data = {};

	for (let dev in devs) {
		let info = usb.info[dev];
		let configurations = device_configurations_build(dev, usb, info);

		let parent_name = device_parent_name(dev);
		let usb_port_idx = port_instance_for_device(dev, usb);
		let usb_port_ref = usb_port_idx ? sprintf('Device.USB.Port.%d', usb_port_idx) : '';

		let parent_ref = '';
		if (parent_name && !match(parent_name, /^usb[0-9]+$/)) {
			let parent_host_inst = host_instance_for_name(sprintf('usb%d', device_bus_get(dev)), usb);
			let parent_dev_inst = host_device_instance_for_name(parent_name, usb);
			if (parent_host_inst && parent_dev_inst)
				parent_ref = sprintf('Device.USB.USBHosts.Host.%d.Device.%d',
				                     parent_host_inst, parent_dev_inst);
		}

		devices_data[sprintf('%d', numbers[device_key(dev, usb)])] = {
			DeviceNumber: sprintf('%d', info.devnum ?? 0),
			USBVersion: info.version,
			DeviceClass: sprintf('%02x', info.bDeviceClass ?? 0),
			DeviceSubClass: sprintf('%02x', info.bDeviceSubClass ?? 0),
			DeviceVersion: sprintf('%d', info.bcdDevice ?? 0),
			DeviceProtocol: sprintf('%02x', info.bDeviceProtocol ?? 0),
			ProductID: sprintf('%d', info.idProduct),
			VendorID: sprintf('%d', info.idVendor),
			Manufacturer: info.manufacturer,
			ProductClass: info.product,
			SerialNumber: info.serial,
			Port: sprintf('%d', device_port_get(dev) ?? 0),
			USBPort: usb_port_ref,
			Rate: speed_to_rate(info.speed) ?? 'Unknown',
			Parent: parent_ref,
			MaxChildren: sprintf('%d', info.maxchild),
			IsSuspended: (info.power_runtime_status == 'suspended') ? 'true' : 'false',
			IsSelfPowered: (port_power_get('Device', info) == 'Self') ? 'true' : 'false',
			ConfigurationNumberOfEntries: sprintf('%d', length(keys(configurations))),
			DeviceState: device_state_get(info),
			IsAllowed: (trim(fs.readfile(`${USB_DEVICES}/${dev}/authorized`) ?? '1') == '0') ? 'false' : 'true',
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
	let usb = usb_snapshot();
	return {
		InterfaceNumberOfEntries: sprintf('%d', interface_count(ctx.config?.Interface)),
		PortNumberOfEntries: sprintf('%d', length(usb.ports))
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
	let info = usb.info[host];
	let devices = host_devices_build(host, usb);

	return {
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
	let usb = usb_snapshot();
	let to_object = (host) => host_to_object(host, usb);

	return {
		...ubbf.ctx_config(ctx),
		AllowAllDevices: ctx.config?.AllowAllDevices ?? 'true',
		AllowedDeviceNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config?.AllowedDevice)),
		HostNumberOfEntries: sprintf('%d', length(usb.hosts)),
		Host: ubbf.instance_rows(HOST_TABLE, usb.hosts, to_object)
	};
}

/**
 * Get handler for Device.USB.USBHosts.Host.{i}.
 *
 * @param {object} ctx - Context with instance
 * @returns {object|null} Host properties or enumerated list
 */
function host_get(ctx) {
	let usb = usb_snapshot();
	let to_object = (host) => host_to_object(host, usb);

	if (ctx.instance == null)
		return ubbf.instance_rows(HOST_TABLE, usb.hosts, to_object);

	let host = ubbf.instance_key(HOST_TABLE, usb.hosts, ctx.instance);
	if (!host)
		return null;

	return to_object(host);
}

/**
 * Builds the Device.USB.Port.{i} row of a hub port. The port takes the
 * highest USB version of its hubs, and the rate of the device plugged into
 * it, else the top rate of that version.
 *
 * @param {string} name - Port name from hub_ports_read()
 * @param {object} usb - usb_snapshot() result
 * @returns {object} TR-181 Port row
 */
function port_to_object(name, usb) {
	let port = usb.ports[name];
	let hub;
	for (let h in port.hubs)
		if (!hub || +trim(usb.info[h].version ?? '') > +trim(hub.version ?? ''))
			hub = usb.info[h];

	let attached = usb.info[port.devices[0]];
	let is_host = match(port.hubs[0], /^usb[0-9]+$/);
	let port_type = is_host ? 'Host' : 'Hub';

	return {
		Alias: ubbf.alias_from_name(name),
		Name: name,
		Standard: hub.version,
		Type: port_type,
		Receptacle: is_host ? 'Standard-A' : '',
		Rate: port_rate_get(attached ?? hub),
		Power: port_power_get(port_type, hub)
	};
}

/**
 * Builds port instances for Device.USB.Port container.
 *
 * @param {object} ctx - Context
 * @returns {object} Keyed port instances
 */
function port_container_get(ctx) {
	let usb = usb_snapshot();
	let numbers = ubbf.instance_numbers(PORT_TABLE, port_keys(usb));
	let port_instances = {};

	for (let name in port_keys(usb))
		port_instances[sprintf('%d', numbers[name])] = port_to_object(name, usb);

	return port_instances;
}

/**
 * Get handler for Device.USB.Port.{i}.
 *
 * @param {object} ctx - Context with instance
 * @returns {object|null} Port properties
 */
function port_get(ctx) {
	let usb = usb_snapshot();
	let key = ubbf.instance_key(PORT_TABLE, port_keys(usb), ctx.instance);
	if (key == null)
		return null;

	return port_to_object(key, usb);
}

/**
 * Builds a TR-181 USB.Interface row from a usb_net_interfaces entry.
 *
 * @param {object} iface - Entry with device, ifname, path
 * @param {object|null} config - Stored row, for the values a controller
 *                               wrote
 * @returns {object} TR-181 Interface row
 */
function interface_row(iface, config) {
	let carrier = ubbf.readfile_trim(sprintf('%s/carrier', iface.path));

	return {
		Enable: 'true',
		Status: (carrier == '1') ? 'Up' : 'Down',
		Alias: ubbf.alias_from_name(iface.ifname),
		Name: iface.ifname,
		Description: config?.Description ?? '',
		LastChange: '0',
		LowerLayers: '',
		Upstream: 'false',
		MaxBitRate: '0',
		MACAddress: ubbf.readfile_trim(sprintf('%s/address', iface.path), ''),
		Port: ''
	};
}

/**
 * Get handler for Device.USB.Interface.{i}.
 *
 * The table holds the USB netdevs (runtime_instances); a write of
 * Description stores its row (writable_rows). A stored row whose netdev
 * is gone stays visible as NotPresent, so its Description can still be
 * read and changed. Enumerate mode leaves out the stored rows, which the
 * dispatcher reads one by one.
 *
 * @param {object} ctx - Context with instance and stored config
 * @returns {object|null} Rows by instance, one row, or null
 */
function interface_get(ctx) {
	if (ctx.instance == null) {
		let stored = ctx.root?.Device?.USB?.Interface ?? {};
		let rows = {};

		for (let n, iface in usb_net_interfaces_numbered())
			if (!stored[n])
				rows[n] = interface_row(iface, null);
		return rows;
	}

	let iface = usb_net_interface_by_instance(ctx.instance);
	if (!ctx.config)
		return iface?.ifname ? interface_row(iface, null) : null;

	if (!iface?.ifname)
		return { ...ubbf.ctx_config(ctx), Status: 'NotPresent' };

	return interface_row(iface, ctx.config);
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
 * @param {object} root - Data model root (unused)
 * @returns {object|number} Empty object on success, a negative USP error
 *          code on failure
 */
function usb_interface_stats_reset(input, command_key, instances, root) {
	let iface = usb_net_interface_by_instance(instances[0]);
	if (!iface?.ifname)
		return -USP_ERR_OBJECT_DOES_NOT_EXIST;

	if (!utils.ifstats.ifstats_reset(iface.ifname)) {
		ubbf.log_err('usb: Stats.Reset() of %s failed', iface.ifname);
		return -USP_ERR_COMMAND_FAILURE;
	}
	return {};
}

/**
 * Writes a USB host name to the bind or unbind file of the USB-core
 * device driver.
 *
 * @param {string} op - bind or unbind
 * @param {string} host - Host sysfs name
 * @returns {boolean} True when the write succeeded
 */
function host_driver_write(op, host) {
	if (fs.writefile(sprintf('%s/%s', USB_DEVICE_DRIVER, op), host) != null)
		return true;

	ubbf.log_err('usb: %s of %s failed: %s', op, host, fs.error());
	return false;
}

/**
 * Tells whether the USB-core device driver holds a host: its sysfs
 * directory then has a link with the name of the host.
 *
 * @param {string} host - Host sysfs name (e.g. usb1)
 * @returns {boolean} true if the host is bound to the driver
 */
function host_bound(host) {
	return fs.lstat(sprintf('%s/%s', USB_DEVICE_DRIVER, host)) != null;
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
 * A failed bind after the unbind leaves the bus without a driver, so the
 * bind gets a second try.
 *
 * @param {object} input - Operation input (unused)
 * @param {string} command_key - Command key (unused)
 * @param {array} instances - Instance numbers from path match
 * @param {object} root - Data model root (unused)
 * @returns {object|number} Empty object on success, a negative USP error
 *          code on failure
 */
function host_reset(input, command_key, instances, root) {
	let host = ubbf.instance_key(HOST_TABLE, usb_snapshot().hosts, instances[0]);
	if (!host)
		return -USP_ERR_OBJECT_DOES_NOT_EXIST;

	// The kernel rejects the unbind of a host the driver does not hold; the
	// bind below is then the whole reset.
	if (!host_driver_write('unbind', host) && host_bound(host))
		return -USP_ERR_COMMAND_FAILURE;

	let bound = host_driver_write('bind', host) || host_driver_write('bind', host);
	ubbf.cache_invalidate(usb_snapshot_fetch);
	ubbf.cache_invalidate(usb_lib.net_interfaces);

	return bound ? {} : -USP_ERR_COMMAND_FAILURE;
}

model['Device.USB'] = {
	schema: schema('USB'),
	get: usb_get
};

model['Device.USB.Interface'] = {};

model['Device.USB.Interface.{i}'] = {
	schema: schema('Interface'),
	get: interface_get,
	runtime_instances: true,
	writable_rows: true
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
