'use strict';

import * as ubbf from 'ubbf';
import { uci_set_boolean, uci_set_string } from 'ubbf.render.uci_helpers';

/**
 * Appends fw4 reflection options to the most recently emitted
 * firewall.@redirect[-1] section. fw4 defaults to reflection=1 with
 * reflection_src=internal, so without this the SNAT source on a
 * hairpinned packet is the gateway LAN IP. MVP-2113 requires the
 * external WAN IP/port as source ("packets displaying external source
 * IP address and port"); Device.NAT.X_UBBF_Hairpinning.Enable=true
 * flips reflection_src to external, false hard-disables reflection.
 *
 * @param {object} config - UBBF config root
 * @param {string[]} output - UCI batch line accumulator
 */
export function redirect_emit_reflection(config, output) {
	let hairpin = ubbf.get(config, 'Device.NAT.X_UBBF_Hairpinning');
	let enabled = ubbf.to_bool(hairpin?.Enable ?? "false");

	if (enabled) {
		uci_set_boolean(output, 'firewall.@redirect[-1].reflection', true);
		uci_set_string(output, 'firewall.@redirect[-1].reflection_src', 'external');
		return;
	}

	uci_set_boolean(output, 'firewall.@redirect[-1].reflection', false);
};
