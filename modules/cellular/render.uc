function render_config() {
	// Nothing in TR-181 models an interface metric. Next to another WAN the
	// cellular default route sits behind it, since netifd installs default
	// routes with replace semantics and metric 0 would take the wired WAN's
	// place; as the only WAN it takes the plain default and the operator's
	// resolvers.
	const CELLULAR_METRIC = 100;

	// ModemManager fills the dump's signal block only while a refresh rate
	// is armed; without it RSSI, RSRP and RSRQ read 0 for ever.
	const SIGNAL_RATE = 30;

	/**
	 * Converts an IP version number to UCI format.
	 *
	 * @param {number|string} ipv - IP version (4, 6, or other)
	 * @returns {string} UCI IP type string
	 */
	function ipversion_to_uci(ipv) {
		let v = int(ipv);
		if (v == 4)
			return 'ipv4';
		if (v == 6)
			return 'ipv6';
		return 'ipv4v6';
	}

	/**
	 * Finds the IP.Interface stacked on a Cellular.Interface.
	 *
	 * @param {string} ref - Device.Cellular.Interface.{i} path
	 * @returns {object|null} IP.Interface instance whose LowerLayers names it
	 */
	function interface_by_lowerlayers(ref) {
		for (let iface in ubbf_instances(config, 'Device.IP.Interface')) {
			let lowers = csv_to_list(iface.LowerLayers ?? '');
			if (length(lowers) && lowers[0] == ref)
				return iface;
		}
		return null;
	}

	/**
	 * Whether an enabled upstream IP.Interface other than the one stacked on
	 * this modem exists.
	 *
	 * @param {string} ref - Device.Cellular.Interface.{i} path
	 * @returns {boolean} true when the modem is a secondary WAN
	 */
	function other_upstream_exists(ref) {
		for (let iface in ubbf_instances(config, 'Device.IP.Interface')) {
			if (!ubbf_to_bool(iface.Enable) || !ubbf_to_bool(iface.Upstream))
				continue;
			let lowers = csv_to_list(iface.LowerLayers ?? '');
			if (length(lowers) && lowers[0] == ref)
				continue;
			return true;
		}
		return false;
	}

	/**
	 * Finds the IP.Interface carrying the access point's Alias as its Name,
	 * the pairing older configurations used before LowerLayers stacking.
	 *
	 * @param {string} alias - AccessPoint Alias
	 * @returns {object|null} IP.Interface instance with that Name
	 */
	function interface_by_name(alias) {
		if (!alias)
			return null;
		for (let iface in ubbf_instances(config, 'Device.IP.Interface')) {
			if (iface.Name == alias)
				return iface;
		}
		return null;
	}

	/**
	 * The modem's sysfs device path for a Cellular.Interface reference.
	 *
	 * The stored path is what the handler recorded when the controller
	 * bound the row; the live dump covers a render before that happened.
	 *
	 * @param {string} ref - Device.Cellular.Interface.{i} path
	 * @returns {string|null} sysfs path, null when neither source has it
	 */
	function device_for(ref) {
		let stored = ubbf_get(config, ref)?.X_UBBF_Device;
		if (stored)
			return stored;

		let m = match(ref, /^Device\.Cellular\.Interface\.(\d+)$/);
		if (!m)
			return null;

		let modems = ubus.call('modemmanager', 'dump', {})?.modem ?? [];
		return modems[int(m[1]) - 1]?.generic?.device ?? null;
	}

	/**
	 * Turns one access point into the modemmanager proto on the netifd
	 * interface stacked on its modem. ip.uc has already emitted that section
	 * with proto none; the lines here come later in the batch and win.
	 *
	 * @param {object} ap - Cellular.AccessPoint instance
	 */
	function generate_accesspoint(ap) {
		if (!ubbf_to_bool(ap.Enable))
			return;

		let ref = ap.Interface ?? '';
		if (!match(ref, /^Device\.Cellular\.Interface\.\d+$/)) {
			warn('cellular: AccessPoint %s is bound to no Cellular.Interface', ap['.instance']);
			return;
		}

		let iface = interface_by_lowerlayers(ref) ?? interface_by_name(ap.Alias);
		if (!iface?.Name) {
			warn('cellular: no IP.Interface is stacked on %s', ref);
			return;
		}

		let device = device_for(ref);
		if (!device) {
			warn('cellular: no device path known for %s, AccessPoint %s not rendered', ref, ap['.instance']);
			return;
		}

		let name = iface.Name;

		// ip.uc bound the section to the modem's netdev through ifname; the
		// proto owns the netdev itself and takes the modem's sysfs path in
		// device instead.
		uci_delete(output, `network.${name}.ifname`);
		uci_set_string(output, `network.${name}.proto`, 'modemmanager');
		uci_set_string(output, `network.${name}.device`, device);

		if (ap.APN && ap.APN != '')
			uci_set_string(output, `network.${name}.apn`, ap.APN);

		// ModemManager defaults to no authentication; with credentials the
		// network picks the scheme, and one that refuses PAP still takes CHAP.
		if (ap.Username && ap.Username != '') {
			uci_set_string(output, `network.${name}.username`, ap.Username);
			uci_list_string(output, `network.${name}.allowedauth`, 'pap');
			uci_list_string(output, `network.${name}.allowedauth`, 'chap');
		}

		if (ap.Password && ap.Password != '')
			uci_set_string(output, `network.${name}.password`, ap.Password);

		let pin = ubbf_get(config, ref)?.USIM?.PIN;
		if (pin && pin != '')
			uci_set_string(output, `network.${name}.pincode`, pin);

		uci_set_string(output, `network.${name}.iptype`, ipversion_to_uci(ap.IPVersion));
		if (other_upstream_exists(ref)) {
			uci_set_number(output, `network.${name}.metric`, CELLULAR_METRIC);
			uci_set_boolean(output, `network.${name}.peerdns`, false);
		}
		uci_set_number(output, `network.${name}.signalrate`, SIGNAL_RATE);
	}

	services.set_enabled('modemmanager', true);

	let accesspoints = ubbf_instances(config, 'Device.Cellular.AccessPoint');
	for (let ap in accesspoints)
		generate_accesspoint(ap);
}
uci_comment(output, '# generated by cellular/render.uc');
render_config();
