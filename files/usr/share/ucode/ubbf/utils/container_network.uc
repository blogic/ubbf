'use strict';

import * as fs from 'fs';
import { log_info, log_err } from 'ubbf.utils.logging';
import * as ubbf from 'ubbf';

/**
 * Applies UCI batch commands via uci batch.
 *
 * @param {string} batch - UCI batch command string
 * @returns {boolean} True on success
 */
export function uci_batch_apply(batch) {
	if (!batch || batch == '')
		return true;

	log_info('uci_batch_apply: applying %d commands', length(split(batch, '\n')));

	let p = fs.popen('uci batch', 'w');
	if (!p) {
		log_err('uci_batch_apply: failed to open uci batch');
		return false;
	}

	p.write(batch + '\n');
	let rc = p.close();
	return (rc == 0);
};

/**
 * Generates veth device names for a container.
 *
 * @param {string} name - Container name
 * @param {number} idx - Interface index (0-based)
 * @returns {object} Object with host and container interface names
 */
export function veth_names_generate(name, idx) {
	let suffix = (idx > 0) ? sprintf('-%d', idx) : '';
	return {
		host: sprintf('vhost-%s%s', name, suffix),
		peer: sprintf('virt-%s%s', name, suffix),
		device: sprintf('veth_%s%s', name, suffix)
	};
};

/**
 * Ensures the shared br-virt bridge, DHCP, and firewall zone exist.
 * Creates them only if not already present. Must be called before
 * per-container veth setup.
 *
 * @returns {boolean} True if bridge was created or already existed
 */
export function bridge_ensure() {
	let p = fs.popen('uci -q get network.dev_virt 2>/dev/null', 'r');
	let existing;
	if (p) {
		existing = trim(p.read('all') ?? '');
		p.close();
	}

	if (existing == 'device')
		return true;

	let cmds = [];

	push(cmds, "set network.dev_virt='device'");
	push(cmds, "set network.dev_virt.type='bridge'");
	push(cmds, "set network.dev_virt.name='br-virt'");
	push(cmds, "set network.virt='interface'");
	push(cmds, "set network.virt.device='br-virt'");
	push(cmds, "set network.virt.proto='static'");
	push(cmds, "set network.virt.ipaddr='10.0.0.1'");
	push(cmds, "set network.virt.netmask='255.255.255.0'");
	push(cmds, 'commit network');

	push(cmds, "set dhcp.virt='dhcp'");
	push(cmds, "set dhcp.virt.interface='virt'");
	push(cmds, "set dhcp.virt.start='8'");
	push(cmds, "set dhcp.virt.limit='240'");
	push(cmds, "set dhcp.virt.leasetime='12h'");
	push(cmds, "set dhcp.virt.domain='virt'");
	push(cmds, "set dhcp.virt.dhcpv4='server'");
	push(cmds, 'commit dhcp');

	push(cmds, "set firewall.virt_zone='zone'");
	push(cmds, "set firewall.virt_zone.name='virt'");
	push(cmds, "set firewall.virt_zone.network='virt'");
	push(cmds, "set firewall.virt_zone.input='ACCEPT'");
	push(cmds, "set firewall.virt_zone.output='ACCEPT'");
	push(cmds, "set firewall.virt_zone.forward='ACCEPT'");
	push(cmds, "set firewall.virt_fwd_wan='forwarding'");
	push(cmds, "set firewall.virt_fwd_wan.src='virt'");
	push(cmds, "set firewall.virt_fwd_wan.dest='wan'");
	push(cmds, "set firewall.virt_fwd_lan='forwarding'");
	push(cmds, "set firewall.virt_fwd_lan.src='lan'");
	push(cmds, "set firewall.virt_fwd_lan.dest='virt'");
	push(cmds, 'commit firewall');

	log_info('bridge_ensure: creating br-virt bridge infrastructure');

	return uci_batch_apply(join('\n', cmds));
};

/**
 * Generates UCI batch commands to set up container networking.
 *
 * @param {string} name - Container name
 * @param {object} network_config - Network configuration from metadata
 * @returns {string} UCI batch commands
 */
export function network_uci_setup(name, network_config) {
	if (network_config.share_parent_network)
		return '';

	bridge_ensure();

	let cmds = [];
	let veth = veth_names_generate(name, 0);

	push(cmds, sprintf('set network.%s=device', veth.device));
	push(cmds, sprintf('set network.%s.type=veth', veth.device));
	push(cmds, sprintf('set network.%s.name=%s', veth.device, veth.host));
	push(cmds, sprintf('set network.%s.peer_name=%s', veth.device, veth.peer));

	push(cmds, sprintf("add_list network.dev_virt.ports='%s'", veth.host));

	let iface_name = sprintf('ct_%s', name);
	push(cmds, sprintf('set network.%s=interface', iface_name));
	push(cmds, sprintf('set network.%s.proto=none', iface_name));
	push(cmds, sprintf('set network.%s.device=%s', iface_name, veth.peer));
	push(cmds, sprintf('set network.%s.jail=%s', iface_name, name));
	push(cmds, sprintf('set network.%s.jail_ifname=eth0', iface_name));

	let zone_name = sprintf('ct_%s', name);
	push(cmds, sprintf('set firewall.%s=zone', zone_name));
	push(cmds, sprintf('set firewall.%s.name=%s', zone_name, zone_name));
	push(cmds, sprintf('set firewall.%s.input=REJECT', zone_name));
	push(cmds, sprintf('set firewall.%s.output=ACCEPT', zone_name));
	push(cmds, sprintf('set firewall.%s.forward=REJECT', zone_name));
	push(cmds, sprintf("add_list firewall.%s.network='%s'", zone_name, iface_name));

	let fwd_name = sprintf('ct_%s_fwd', name);
	push(cmds, sprintf('set firewall.%s=forwarding', fwd_name));
	push(cmds, sprintf('set firewall.%s.src=%s', fwd_name, zone_name));
	push(cmds, sprintf('set firewall.%s.dest=wan', fwd_name));

	for (let i = 0; i < length(network_config.port_forwarding ?? []); i++) {
		let pf = network_config.port_forwarding[i];
		let rule_name = sprintf('ct_%s_pf_%d', name, i);

		push(cmds, sprintf('set firewall.%s=redirect', rule_name));
		push(cmds, sprintf('set firewall.%s.src=wan', rule_name));
		push(cmds, sprintf('set firewall.%s.dest=%s', rule_name, zone_name));
		push(cmds, sprintf('set firewall.%s.proto=%s', rule_name, pf.protocol ?? 'tcp'));
		push(cmds, sprintf('set firewall.%s.src_dport=%s', rule_name, pf.external_port));
		push(cmds, sprintf('set firewall.%s.dest_port=%s', rule_name, pf.internal_port ?? pf.external_port));
	}

	push(cmds, 'commit network');
	push(cmds, 'commit firewall');

	return join('\n', cmds);
};

/**
 * Generates UCI batch commands to remove container networking.
 *
 * @param {string} name - Container name
 * @returns {string} UCI batch commands
 */
export function network_uci_cleanup(name) {
	let cmds = [];
	let veth = veth_names_generate(name, 0);

	push(cmds, sprintf("del_list network.dev_virt.ports='%s'", veth.host));
	push(cmds, sprintf('delete network.%s', veth.device));
	push(cmds, sprintf('delete network.ct_%s', name));

	push(cmds, sprintf('delete firewall.ct_%s', name));
	push(cmds, sprintf('delete firewall.ct_%s_fwd', name));

	let pattern = sprintf('ct_%s_pf_[0-9]+', name);
	let redirects = fs.popen('uci show firewall 2>/dev/null | grep -oE ' + ubbf.shell_escape(pattern) + ' | sort -u', 'r');
	if (redirects) {
		let line;
		while ((line = redirects.read('line')) != null) {
			let rule = trim(line);
			if (rule != '')
				push(cmds, sprintf('delete firewall.%s', rule));
		}
		redirects.close();
	}

	push(cmds, 'commit network');
	push(cmds, 'commit firewall');

	return join('\n', cmds);
};
