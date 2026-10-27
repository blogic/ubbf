// Stand-in for the native usb module: one root hub usb1 and the devices
// of global.usb_devices, a sysfs name to { vid, pid, serial } map; each
// device has one network interface.
return {
	enumerate: () => ({
		hosts: [ 'usb1' ],
		devices: sort(keys(global.usb_devices ?? {})),
		interfaces: []
	}),
	device_info: (name) => {
		let d = global.usb_devices?.[name] ?? {};
		return { idVendor: d.vid ?? 0, idProduct: d.pid ?? 0, serial: d.serial ?? '', version: '2.00',
			 bNumConfigurations: 2, bConfigurationValue: 1 };
	},
	interface_info: () => ({}),
	net_interfaces: () => map(sort(keys(global.usb_devices ?? {})), (name) => ({
		device: name, ifname: `usb-${name}`, path: `/sys/bus/usb/devices/${name}/net/usb-${name}`
	}))
};
