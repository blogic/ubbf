'use strict';

// Out-of-tree module. `ubbf_module` is the scope datamodel.uc includes this
// file with, and it is visible only while the include runs, so anything the
// handlers below use later has to be bound here. See docs/ARCHITECTURE.md.

const ubbf = ubbf_module.ubbf;
const lower_layer_resolve_vlan = ubbf_module.utils.ubbf_helpers.lower_layer_resolve_vlan;
const log_warn = ubbf_module.ubbf.log_warn;
const model = ubbf_module.model;
const operations = ubbf_module.operations;

const wol_lib = require('wol');

const schema = ubbf_module.schema;

/**
 * Lists the LAN devices for a Wake-on-LAN magic packet.
 *
 * Resolves each enabled IP interface that is not Upstream to its device,
 * and lists each device once. Falls back to br-lan when none resolves.
 *
 * @param {object} root - Root configuration object
 * @returns {array} LAN device names
 */
function wol_lan_devices(root) {
	let devices = [];

	for (let inst, iface in root?.Device?.IP?.Interface ?? {}) {
		if (ubbf.to_bool(iface.Upstream) || !ubbf.to_bool(iface.Enable))
			continue;

		let dev = lower_layer_resolve_vlan(root, iface.LowerLayers);
		if (dev && index(devices, dev) < 0)
			push(devices, dev);
	}

	return length(devices) ? devices : ['br-lan'];
}

/**
 * Handles Device.Ethernet.WoL.SendMagicPacket() operation.
 *
 * Sends the magic packet on every LAN device. The container-scope
 * dispatcher passes the root configuration as the third argument (no
 * instance list) because WoL has no per-instance context.
 *
 * @param {object} input - Operation input with MACAddress and optional Password
 * @param {string} command_key - Command key (unused)
 * @param {object} root - Root configuration object
 * @returns {object|number} Empty result when one device sent the packet,
 *                          else a negative USP error code
 */
function wol_send_magic_packet(input, command_key, root) {
	let mac = input.MACAddress;
	if (!ubbf.mac_is_valid(mac)) {
		log_warn('wol: invalid MACAddress %s', mac);
		return -USP_ERR_INVALID_COMMAND_ARGS;
	}

	let devices = wol_lan_devices(root);
	let failed = [];

	for (let dev in devices) {
		let sent = wol_lib.send(dev, mac, input.Password);
		if (sent == null) {
			log_warn('wol: invalid Password');
			return -USP_ERR_INVALID_COMMAND_ARGS;
		}
		if (!sent)
			push(failed, dev);
	}

	if (length(failed))
		log_warn('wol: magic packet for %s not sent on %s', mac, join(', ', failed));

	return (length(failed) < length(devices)) ? {} : -USP_ERR_COMMAND_FAILURE;
}

model['Device.Ethernet.WoL'] = {
	schema: schema('WoL')
};

operations['Device.Ethernet.WoL.SendMagicPacket()'] = {
	type: 'sync',
	handler: wol_send_magic_packet
};
