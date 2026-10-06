// Device.USB.USBHosts.AllowAllDevices and AllowedDevice.{i} become the UCI
// package ubbf_usb; the procd service ubbf-usb-allow reloads on a change and
// sets the kernel USB authorization.
function render_config() {
	const RULE_FIELDS = {
		vendor: 'VendorID',
		product: 'ProductID',
		class: 'DeviceClass',
		subclass: 'DeviceSubClass',
		protocol: 'DeviceProtocol'
	};

	let usbhosts = ubbf_get(config, 'Device.USB.USBHosts') ?? {};

	// Below TR-181 2.20 the parameters do not exist: every device stays
	// allowed, as before.
	let allow_all = true;
	if (dm_visible('2.20', null))
		allow_all = ubbf_to_bool(usbhosts.AllowAllDevices ?? 'true');

	uci_named_section(output, 'ubbf_usb.global', 'usb');
	uci_set_boolean(output, 'ubbf_usb.global.allow_all', allow_all);

	if (!allow_all) {
		for (let row in ubbf_instances(config, 'Device.USB.USBHosts.AllowedDevice')) {
			if (!ubbf_to_bool(row.Enable))
				continue;

			uci_section(output, 'ubbf_usb allow');
			for (let option, param in RULE_FIELDS)
				if (row[param])
					uci_set_string(output, `ubbf_usb.@allow[-1].${option}`, row[param]);
			for (let item in csv_to_list(row.Interfaces ?? ''))
				uci_list_string(output, 'ubbf_usb.@allow[-1].interface', item);
		}
	}

	services.set_enabled('ubbf-usb-allow', true);
}
render_config();
