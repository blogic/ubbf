function render_config() {

/**
 * Emits the firewall rules that let multicast traffic cross from each
 * proxy's upstream zone into its downstream zones. fw4 evaluates `rule`
 * sections before the zone forwardings, so appending them here, after the
 * in-tree firewall template has run, changes nothing about their effect.
 */
function generate_multicast_rules() {
	let proxies = ubbf_instances(config, 'Device.X_UBBF.MulticastProxy.Proxy');

	for (let proxy in proxies) {
		if (!ubbf_to_bool(proxy.Enable))
			continue;

		let upstream_name = interface_to_name(config, proxy.UpstreamInterface);
		if (!upstream_name)
			continue;

		let ifaces = ubbf_instances(config,
			`Device.X_UBBF.MulticastProxy.Proxy.${proxy['.instance']}.Interface`);

		for (let iface in ifaces) {
			if (!ubbf_to_bool(iface.Enable))
				continue;

			let ds_name = interface_to_name(config, iface.Interface);
			if (!ds_name)
				continue;

			uci_section(output, 'firewall rule');
			uci_set_string(output, 'firewall.@rule[-1].name', `Allow-Mcast-${upstream_name}-${ds_name}`);
			uci_set_string(output, 'firewall.@rule[-1].src', upstream_name);
			uci_set_string(output, 'firewall.@rule[-1].dest', ds_name);
			uci_set_string(output, 'firewall.@rule[-1].proto', 'udp');
			uci_set_string(output, 'firewall.@rule[-1].dest_ip', '224.0.0.0/4');
			uci_set_string(output, 'firewall.@rule[-1].family', 'ipv4');
			uci_set_string(output, 'firewall.@rule[-1].target', 'ACCEPT');
		}
	}
}

/**
 * Converts TR-181 scope value to omcproxy scope.
 *
 * @param {string} scope - TR-181 scope value
 * @returns {string} omcproxy scope value
 */
function scope_to_uci(scope) {
	let map = {
		'Global': 'global',
		'Organisation': 'organization',
		'Site': 'site',
		'Admin': 'admin',
		'Realm': 'realm'
	};
	return map[scope] ?? 'global';
}

/**
 * Converts TR-181 version string to UCI integer.
 *
 * @param {string} version - TR-181 version (V1, V2, V3)
 * @returns {string} UCI version number
 */
function version_to_uci(version) {
	if (!version)
		return null;
	let m = match(version, /^V(\d+)$/);
	return m ? m[1] : null;
}

/**
 * Resolves interface reference to netifd network name.
 *
 * @param {string} iface_ref - TR-181 interface reference path
 * @returns {string|null} netifd network name (e.g. 'wan', 'lan')
 */
function resolve_interface(iface_ref) {
	if (!iface_ref)
		return null;

	return interface_to_name(config, iface_ref);
}

/**
 * Resolves bridge reference to bridge name.
 *
 * @param {string} bridge_ref - TR-181 bridge reference path
 * @returns {string|null} Bridge interface name (e.g., 'br-lan')
 */
function resolve_bridge(bridge_ref) {
	if (!bridge_ref)
		return null;

	let bridge_data = ubbf_get(config, bridge_ref);
	return bridge_data?.Name;
}

let mcast_config = ubbf_get(config, 'Device.X_UBBF.MulticastProxy');
let mcast_enable = ubbf_to_bool(mcast_config?.Enable);
let backend = mcast_config?.Backend ?? 'igmpproxy';

if (!mcast_enable) {
	services.set_enabled('igmpproxy', false);
	services.set_enabled('omcproxy', false);
	return;
}

uci_comment(output, '');

let proxies = ubbf_instances(config, 'Device.X_UBBF.MulticastProxy.Proxy');
let has_valid_proxy = false;

let has_quickleave = false;
let snooping_instances = ubbf_instances(config, 'Device.X_UBBF.MulticastProxy.Snooping');
for (let snoop in snooping_instances) {
	if (ubbf_to_bool(snoop.ImmediateLeave)) {
		has_quickleave = true;
		break;
	}
}

for (let proxy in proxies) {
	if (!ubbf_to_bool(proxy.Enable))
		continue;

	let upstream_name = resolve_interface(proxy.UpstreamInterface);
	if (!upstream_name)
		continue;

	let downstream_names = [];
	let ifaces = ubbf_instances(config, `Device.X_UBBF.MulticastProxy.Proxy.${proxy['.instance']}.Interface`);
	for (let iface in ifaces) {
		if (!ubbf_to_bool(iface.Enable))
			continue;
		let if_name = resolve_interface(iface.Interface);
		if (if_name)
			push(downstream_names, if_name);
	}

	if (length(downstream_names) == 0)
		continue;

	has_valid_proxy = true;
	let alias = ubbf.name_sanitise(proxy.Alias || `proxy_${proxy['.instance']}`);

	if (backend == 'igmpproxy') {
		uci_comment(output, `## igmpproxy instance ${alias}`);

		uci_section(output, 'igmpproxy igmpproxy');
		uci_set_boolean(output, 'igmpproxy.@igmpproxy[-1].quickleave', has_quickleave);
		uci_comment(output, '');

		uci_section(output, 'igmpproxy phyint');
		uci_set_string(output, 'igmpproxy.@phyint[-1].network', upstream_name);
		uci_set_string(output, 'igmpproxy.@phyint[-1].direction', 'upstream');
		uci_set_string(output, 'igmpproxy.@phyint[-1].zone', upstream_name);

		let altnet = proxy.AltNet ?? '0.0.0.0/0';
		let altnets = csv_to_list(altnet);
		for (let net in altnets)
			uci_list_string(output, 'igmpproxy.@phyint[-1].altnet', net);

		uci_comment(output, '');

		for (let ds_name in downstream_names) {
			uci_section(output, 'igmpproxy phyint');
			uci_set_string(output, 'igmpproxy.@phyint[-1].network', ds_name);
			uci_set_string(output, 'igmpproxy.@phyint[-1].direction', 'downstream');
			uci_set_string(output, 'igmpproxy.@phyint[-1].zone', ds_name);
			uci_comment(output, '');
		}
	} else {
		let scope = scope_to_uci(proxy.Scope);

		uci_comment(output, `## omcproxy instance ${alias}`);
		uci_named_section(output, `omcproxy.${alias}`, 'proxy');
		uci_set_boolean(output, `omcproxy.${alias}.enabled`, true);
		uci_set_string(output, `omcproxy.${alias}.scope`, scope);
		uci_set_string(output, `omcproxy.${alias}.uplink`, upstream_name);

		for (let dl_name in downstream_names)
			uci_list_string(output, `omcproxy.${alias}.downlink`, dl_name);

		uci_comment(output, '');
	}

}

for (let snoop in snooping_instances) {
	if (!ubbf_to_bool(snoop.Enable))
		continue;

	let bridge_name = resolve_bridge(snoop.Interface);
	if (!bridge_name)
		continue;

	let mode = snoop.Mode ?? 'Standard';
	if (mode == 'Disabled')
		continue;

	let bridge_section = replace(bridge_name, /^br-/, '');

	uci_comment(output, `## Snooping on ${bridge_name}`);

	uci_set_boolean(output, `network.${bridge_section}.igmp_snooping`, true);
	uci_set_boolean(output, `network.${bridge_section}.multicast_querier`, true);

	let igmp_ver = version_to_uci(snoop.IGMPVersion);
	if (igmp_ver)
		uci_set_number(output, `network.${bridge_section}.igmp_version`, int(igmp_ver));

	let mld_ver = version_to_uci(snoop.MLDVersion);
	if (mld_ver)
		uci_set_number(output, `network.${bridge_section}.mld_version`, int(mld_ver));

	let robustness = ubbf_to_int(snoop.Robustness);
	if (robustness)
		uci_set_number(output, `network.${bridge_section}.robustness`, robustness);

	let query_interval = ubbf_to_int(snoop.QueryInterval);
	if (query_interval)
		uci_set_number(output, `network.${bridge_section}.query_interval`, query_interval * 100);

	let query_response = ubbf_to_int(snoop.QueryResponseInterval);
	if (query_response)
		uci_set_number(output, `network.${bridge_section}.query_response_interval`, query_response * 10);

	let last_member = ubbf_to_int(snoop.LastMemberQueryInterval);
	if (last_member)
		uci_set_number(output, `network.${bridge_section}.last_member_interval`, last_member * 10);

	uci_comment(output, '');
}

generate_multicast_rules();

services.set_enabled('igmpproxy', has_valid_proxy && backend == 'igmpproxy');
services.set_enabled('omcproxy', has_valid_proxy && backend != 'igmpproxy');
}
uci_comment(output, '# generated by multicast/render.uc');
render_config();
