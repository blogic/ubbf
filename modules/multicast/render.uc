function render_config() {

/**
 * Converts TR-181 version string to UCI integer.
 *
 * @param {string} version - Version from the schema enumeration (V1 to V3)
 * @returns {string|null} UCI version number
 */
function version_to_uci(version) {
	if (!version)
		return null;
	let m = match(version, /^V(\d+)$/);
	return m ? m[1] : null;
}

/**
 * Resolves bridge reference to bridge name.
 *
 * @param {string} bridge_ref - TR-181 bridge reference path
 * @returns {string|null} Bridge interface name (e.g., 'br-lan')
 */
function resolve_bridge(bridge_ref) {
	if (!bridge_ref || !match(bridge_ref, /^Device\.Bridging\.Bridge\.\d+$/))
		return null;

	return ubbf_get(config, bridge_ref)?.Name;
}

/**
 * Returns the netifd names of the enabled downstream interfaces of a proxy.
 *
 * @param {object} proxy - Proxy row
 * @returns {array} Network names
 */
function proxy_downstreams(proxy) {
	let names = [];
	let ifaces = ubbf_instances(config, `Device.X_UBBF.MulticastProxy.Proxy.${proxy['.instance']}.Interface`);

	for (let iface in ifaces) {
		if (!ubbf_to_bool(iface.Enable))
			continue;
		let name = interface_to_name(config, iface.Interface);
		if (name && index(names, name) < 0)
			push(names, name);
	}

	return names;
}

/**
 * Collects the enabled proxy rows that can be rendered. A network serves
 * one proxy only: the first row that names it decides its direction.
 *
 * @returns {array} `{ proxy, upstream, downstreams }` per row
 */
function proxy_rows_collect() {
	let rows = [];
	let used = {};

	for (let proxy in ubbf_instances(config, 'Device.X_UBBF.MulticastProxy.Proxy')) {
		if (!ubbf_to_bool(proxy.Enable))
			continue;

		let upstream = interface_to_name(config, proxy.UpstreamInterface);
		if (!upstream || used[upstream])
			continue;

		let downstreams = filter(proxy_downstreams(proxy), (n) => n != upstream && !used[n]);
		if (!length(downstreams))
			continue;

		used[upstream] = true;
		for (let n in downstreams)
			used[n] = true;

		push(rows, { proxy, upstream, downstreams });
	}

	return rows;
}

/**
 * Writes the omcproxy configuration, one proxy section per row. omcproxy
 * proxies IGMP and MLD on the device of each network and is the querier
 * of the downlinks. The init script gives procd the firewall rules of
 * the zones of each network.
 *
 * @param {array} rows - Rows from proxy_rows_collect()
 */
function omcproxy_write(rows) {
	let scopes = {
		Global: 'global',
		Organisation: 'organization',
		Site: 'site',
		Admin: 'admin',
		Realm: 'realm'
	};
	let timers = {
		Robustness: 'robustness',
		QueryInterval: 'query_interval',
		QueryResponseInterval: 'query_response_interval',
		LastMemberQueryInterval: 'last_member_query_interval'
	};

	for (let row in rows) {
		let name = sprintf('proxy_%s', row.proxy['.instance']);

		uci_named_section(output, `omcproxy.${name}`, 'proxy');
		uci_set_string(output, `omcproxy.${name}.uplink`, row.upstream);
		uci_set_string(output, `omcproxy.${name}.scope`, scopes[row.proxy.Scope] ?? 'global');
		uci_set_boolean(output, `omcproxy.${name}.fastleave`, ubbf_to_bool(row.proxy.ImmediateLeave));

		for (let param, option in timers) {
			let value = ubbf_to_int(row.proxy[param]);
			if (value)
				uci_set_string(output, `omcproxy.${name}.${option}`, sprintf('%d', value));
		}

		for (let ds in row.downstreams)
			uci_list_string(output, `omcproxy.${name}.downlink`, ds);
		for (let net in csv_to_list(row.proxy.AltNet ?? ''))
			uci_list_string(output, `omcproxy.${name}.altnet`, net);
	}
}

/**
 * Applies the Snooping rows to their bridges. The core turns snooping and
 * the querier on for every bridge; a disabled row turns both off.
 * ImmediateLeave sets fast leave on each port of the bridge.
 */
function snooping_render() {
	for (let snoop in ubbf_instances(config, 'Device.X_UBBF.MulticastProxy.Snooping')) {
		let bridge_name = resolve_bridge(snoop.Interface);
		if (!bridge_name)
			continue;

		if (!ubbf_to_bool(snoop.Enable) || snoop.Mode == 'Disabled') {
			device_state_set(render_state, bridge_name, 'igmp_snooping', '0');
			device_state_set(render_state, bridge_name, 'multicast_querier', '0');
			continue;
		}

		device_state_set(render_state, bridge_name, 'igmp_snooping', '1');

		let igmp_ver = version_to_uci(snoop.IGMPVersion);
		if (igmp_ver)
			device_state_set(render_state, bridge_name, 'igmp_version', igmp_ver);

		let mld_ver = version_to_uci(snoop.MLDVersion);
		if (mld_ver)
			device_state_set(render_state, bridge_name, 'mld_version', mld_ver);

		let robustness = ubbf_to_int(snoop.Robustness);
		if (robustness)
			device_state_set(render_state, bridge_name, 'robustness', sprintf('%d', robustness));

		// The schema keeps seconds and tenths of a second; netifd takes
		// centiseconds.
		let query_interval = ubbf_to_int(snoop.QueryInterval);
		if (query_interval)
			device_state_set(render_state, bridge_name, 'query_interval', sprintf('%d', query_interval * 100));

		let query_response = ubbf_to_int(snoop.QueryResponseInterval);
		if (query_response)
			device_state_set(render_state, bridge_name, 'query_response_interval', sprintf('%d', query_response * 10));

		let last_member = ubbf_to_int(snoop.LastMemberQueryInterval);
		if (last_member)
			device_state_set(render_state, bridge_name, 'last_member_interval', sprintf('%d', last_member * 10));

		if (!ubbf_to_bool(snoop.ImmediateLeave))
			continue;

		for (let port in render_state.bridge_ports?.[bridge_name] ?? [])
			device_state_set(render_state, port, 'multicast_fast_leave', '1');
	}
}

snooping_render();

let mcast_config = ubbf_get(config, 'Device.X_UBBF.MulticastProxy');
let rows = ubbf_to_bool(mcast_config?.Enable) ? proxy_rows_collect() : [];

omcproxy_write(rows);
services.set_enabled('omcproxy', length(rows) > 0);
}
uci_comment(output, '# generated by multicast/render.uc');
render_config();
