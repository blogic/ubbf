'use strict';

import * as schemas from 'ubbf.schemas.GatewayInfo';
import { client_snoop_entry } from 'ubbf.utils.dhcp';
import * as ubbf from 'ubbf';

const VSI_ENTERPRISE_BBF = 3561;

/**
 * Parses a DHCP option 125 (V-I Vendor-Specific Information, RFC 3925)
 * payload and extracts the TR-069 Annex F device-gateway association
 * sub-options for the Broadband Forum enterprise number: 4 = OUI,
 * 5 = SerialNumber, 6 = ProductClass.
 *
 * @param {string} hexval - Hex-encoded option payload from udhcpsnoop
 * @returns {object|null} { oui, serial, class } or null when absent
 */
function vsi_gateway_parse(hexval) {
	let raw = hexdec(hexval ?? '');
	if (!raw)
		return null;

	let out = {};
	let pos = 0;
	while (pos + 5 <= length(raw)) {
		let ent = (ord(raw, pos) << 24) | (ord(raw, pos + 1) << 16) |
		          (ord(raw, pos + 2) << 8) | ord(raw, pos + 3);
		let dpos = pos + 5;
		let dend = dpos + ord(raw, pos + 4);
		if (dend > length(raw))
			break;

		if (ent != VSI_ENTERPRISE_BBF) {
			pos = dend;
			continue;
		}

		while (dpos + 2 <= dend) {
			let code = ord(raw, dpos);
			let slen = ord(raw, dpos + 1);
			let sval = substr(raw, dpos + 2, slen);
			if (code == 4)
				out.oui = sval;
			else if (code == 5)
				out.serial = sval;
			else if (code == 6)
				out.class = sval;
			dpos += 2 + slen;
		}
		pos = dend;
	}

	return length(keys(out)) ? out : null;
}

/**
 * Finds the gateway association advertised over DHCP option 125 on any
 * enabled DHCPv4 client interface.
 *
 * @param {object} root - Root data model object
 * @returns {object|null} Parsed association or null
 */
function gateway_association_find(root) {
	for (let k, client in (root?.Device?.DHCPv4?.Client ?? {})) {
		if (!ubbf.is_instance_key(k) || !ubbf.to_bool(client?.Enable))
			continue;

		let snoop = client_snoop_entry(root, client.Interface);
		for (let so in (snoop?.server_options ?? [])) {
			if (so?.tag != 125)
				continue;
			let info = vsi_gateway_parse(so.value);
			if (info)
				return info;
		}
	}

	return null;
}

/**
 * Get handler for Device.GatewayInfo.
 *
 * Populated from the TR-069 Annex F device-gateway association (DHCP
 * option 125, enterprise 3561) when an upstream gateway advertises one;
 * empty otherwise, which is the specified value when this device is
 * itself the gateway.
 *
 * @param {object} ctx - Context with root data model
 * @returns {object} Gateway identification properties
 */
function gatewayinfo_get(ctx) {
	let info = gateway_association_find(ctx.root);

	return {
		ManufacturerOUI: info?.oui ?? '',
		ProductClass: info?.class ?? '',
		SerialNumber: info?.serial ?? ''
	};
}

export const model = {
	'Device.GatewayInfo': {
		schema: schemas.GatewayInfo,
		get: gatewayinfo_get,
		protocol: 'cwmp'
	}
};
