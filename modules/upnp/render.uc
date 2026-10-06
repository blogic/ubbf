const IP_INTERFACE_RE = regexp('^Device\\.IP\\.Interface\\.[0-9]+$');

/**
 * Returns the netifd names of the interfaces UPnP serves: the enabled rows
 * of Device.UPnP.Device.X_UBBF_Interface whose IP interface is enabled.
 * A network that no row names, a guest network for example, gets no UPnP.
 *
 * @param {object} dev - Device.UPnP.Device config
 * @returns {array} Interface entries `{ path, name }`
 */
function served_interfaces(dev) {
	let served = [];

	for (let key, row in dev?.X_UBBF_Interface ?? {}) {
		if (type(row) != 'object' || !ubbf_to_bool(row.Enable))
			continue;
		if (!match(row.Interface ?? '', IP_INTERFACE_RE))
			continue;
		if (!ubbf_to_bool(ubbf_get(config, row.Interface)?.Enable))
			continue;

		let name = interface_to_name(config, row.Interface);
		if (name && !length(filter(served, (s) => s.name == name)))
			push(served, { path: row.Interface, name });
	}

	return served;
}

/**
 * Returns the TR-064 WANAccessType of an IP interface from the layers
 * below it.
 *
 * @param {string} path - Device.IP.Interface path
 * @returns {string} DSL, Cable or Ethernet
 */
function wan_access_type(path) {
	let todo = [ path ];

	for (let depth = 0; depth < 8 && length(todo); depth++) {
		let next = [];

		for (let p in todo) {
			if (match(p, /^Device\.DSL\./))
				return 'DSL';
			if (match(p, /^Device\.DOCSIS\./))
				return 'Cable';

			for (let lower in ubbf.csv_to_list(ubbf_get(config, p)?.LowerLayers ?? ''))
				push(next, lower);
		}

		todo = next;
	}

	return 'Ethernet';
}

/**
 * Returns the URL of the local web UI on an interface, from its first
 * enabled LocalAccess HTTPAccess row and its first static IPv4 address.
 *
 * @param {string} path - Device.IP.Interface path
 * @returns {string|null} URL, or null when there is none
 */
function presentation_url(path) {
	let ip;

	for (let addr in ubbf_instances(config, path + '.IPv4Address')) {
		if (ubbf_to_bool(addr.Enable) && addr.IPAddress) {
			ip = addr.IPAddress;
			break;
		}
	}

	if (!ip)
		return null;

	for (let row in ubbf_instances(config, 'Device.UserInterface.HTTPAccess')) {
		if (!ubbf_to_bool(row.Enable) || row.Interface != path || (row.AccessType ?? 'LocalAccess') != 'LocalAccess')
			continue;

		let scheme = (row.Protocol == 'HTTPS') ? 'https' : 'http';
		let port = row.Port ?? '';
		let default_port = (scheme == 'https') ? '443' : '80';

		return (port == '' || port == default_port)
			? sprintf('%s://%s/', scheme, ip)
			: sprintf('%s://%s:%s/', scheme, ip, port);
	}

	return null;
}

function render_config() {
	let dev = ubbf_get(config, 'Device.UPnP.Device');
	let igd = ubbf_to_bool(dev?.UPnPIGD ?? 'true');

	// Without a served interface upnpd does not run: its own default for
	// an empty downstream list is 'lan'.
	let served = ubbf_to_bool(dev?.Enable) ? served_interfaces(dev) : [];
	let enabled = length(served) > 0;

	services.set_enabled('upnpd', enabled);

	if (!enabled)
		return;

	let upstream_path = upstream_interface_ref(config);
	let upstream = upstream_path ? interface_to_name(config, upstream_path) : null;
	let hairpin = ubbf_get(config, 'Device.NAT.X_UBBF_Hairpinning');
	let info = { ...deviceinfo_get(), ...(ubbf_get(config, 'Device.DeviceInfo') ?? {}) };

	uci_named_section(output, 'upnpd.config', 'upnpd');
	uci_set_boolean(output, 'upnpd.config.enabled', true);
	uci_set_boolean(output, 'upnpd.config.igd', igd);
	uci_set_string(output, 'upnpd.config.upstream_interface', upstream ?? 'wan');

	for (let s in served)
		uci_list_string(output, 'upnpd.config.downstream_interface', s.name);

	uci_set_boolean(output, 'upnpd.config.hairpin', ubbf_to_bool(hairpin?.Enable ?? 'false'));

	// Written, not left to the daemon defaults, so that a change of those
	// defaults does not change the policy of a deployed device.
	uci_set_boolean(output, 'upnpd.config.secure_mode', true);

	// Device.UPnP.Device.IGD exists from TR-181 2.20; before, the IGD keeps
	// the policy it always had.
	let igd_cfg = dm_visible('2.20', null) ? (ubbf_get(config, 'Device.UPnP.Device.IGD') ?? {}) : null;
	let ipv6 = igd_cfg ? ubbf_to_bool(igd_cfg.EnableIPv6 ?? 'false') : true;

	uci_set_number(output, 'upnpd.config.max_lease', igd_cfg ? (ubbf_to_int(igd_cfg.MaxLeaseLifetime) ?? 86400) : 604800);
	uci_set_number(output, 'upnpd.config.cleanup_interval', igd_cfg ? (ubbf_to_int(igd_cfg.CleanupInterval) ?? 0) : 0);
	uci_set_boolean(output, 'upnpd.config.allow_reserved', igd_cfg ? ubbf_to_bool(igd_cfg.AllowReservedAddress ?? 'false') : true);
	uci_set_boolean(output, 'upnpd.config.ipv6', ipv6);
	uci_set_boolean(output, 'upnpd.config.ipv6_pinholes', ipv6);

	uci_set_string(output, 'upnpd.config.friendly_name', info.FriendlyName || info.ModelName || 'Router');

	for (let opt, key in { model_name: 'ModelName', manufacturer: 'Manufacturer', serial: 'SerialNumber',
	                       model_description: 'Description', model_number: 'HardwareVersion' })
		if (info[key])
			uci_set_string(output, `upnpd.config.${opt}`, info[key]);

	if (upstream_path)
		uci_set_string(output, 'upnpd.config.wan_access_type', wan_access_type(upstream_path));

	let url = length(served) ? presentation_url(served[0].path) : null;
	if (url)
		uci_set_string(output, 'upnpd.config.presentation_url', url);

	// The policy of a ubbf device: LAN clients may map unprivileged ports
	// to unprivileged ports, and nothing else. TR-181 has no parameter for
	// it, and the overlay is rewritten on every apply.
	uci_section(output, 'upnpd perm_rule');
	uci_set_string(output, 'upnpd.@perm_rule[-1].action', 'allow');
	uci_set_string(output, 'upnpd.@perm_rule[-1].ext_ports', '1024-65535');
	uci_set_string(output, 'upnpd.@perm_rule[-1].int_addr', '0.0.0.0/0');
	uci_set_string(output, 'upnpd.@perm_rule[-1].int_ports', '1024-65535');

	uci_section(output, 'upnpd perm_rule');
	uci_set_string(output, 'upnpd.@perm_rule[-1].action', 'deny');
	uci_set_string(output, 'upnpd.@perm_rule[-1].ext_ports', '0-65535');
	uci_set_string(output, 'upnpd.@perm_rule[-1].int_addr', '0.0.0.0/0');
	uci_set_string(output, 'upnpd.@perm_rule[-1].int_ports', '0-65535');
}
uci_comment(output, '# generated by upnp/render.uc');
render_config();
