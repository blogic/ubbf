'use strict';

import * as ubbf from 'ubbf';

/**
 * Parses an IPv6 prefix in the form address/length.
 *
 * @param {string} value - Prefix string
 * @returns {object|null} { addr: byte array, len } or null when invalid
 */
export function prefix6_parse(value) {
	let m = match(value ?? '', /^([0-9A-Fa-f:.]+)\/([0-9]+)$/);
	if (!m)
		return null;

	let addr = iptoarr(m[1]);
	let len = +m[2];
	if (length(addr) != 16 || len > 128)
		return null;

	return { addr, len };
};

/**
 * Reports whether the prefix `inner` lies inside the prefix `outer`.
 *
 * @param {object} outer - Parsed prefix
 * @param {object} inner - Parsed prefix
 * @returns {boolean} True when every address of inner is in outer
 */
export function prefix6_contains(outer, inner) {
	if (inner.len < outer.len)
		return false;

	for (let i = 0, bits = outer.len; bits > 0; i++, bits -= 8) {
		let mask = (bits >= 8) ? 0xff : (0xff << (8 - bits)) & 0xff;
		if ((outer.addr[i] & mask) != (inner.addr[i] & mask))
			return false;
	}

	return true;
};

/**
 * Checks the configuration of one Device.NAT.NPTv6.InterfaceSetting.{i}
 * row. A row is inoperable when Interface does not resolve, when a prefix
 * is missing or invalid, or when the prefixes differ in length (RFC 6296
 * maps prefixes of one length).
 *
 * @param {object} root - Root data model object
 * @param {object} row - InterfaceSetting row
 * @returns {object} { status, network, internal, external }; status is
 *   Disabled, Error_Misconfigured or Enabled
 */
export function nptv6_setting_check(root, row) {
	if (!ubbf.to_bool(row?.Enable))
		return { status: 'Disabled' };

	let network = row.Interface ? ubbf.interface_to_name(root, row.Interface) : null;
	let internal = prefix6_parse(row.InternalPrefix);
	let external = prefix6_parse(row.ExternalPrefix);

	if (!network || !internal || !external || internal.len != external.len)
		return { status: 'Error_Misconfigured' };

	return {
		status: 'Enabled',
		network,
		internal: row.InternalPrefix,
		external: row.ExternalPrefix
	};
};
