'use strict';

import { cursor } from 'uci';
import { popen } from 'fs';
import { netifd_status_get } from 'ubbf.utils.netifd';

/**
 * Extracts the host of a URL, without the brackets of an IPv6 literal.
 *
 * @param {string} url - ACS URL
 * @returns {string|null} host, or null when the URL has none
 */
function url_host(url) {
	let m = match(url ?? '', /^[A-Za-z][A-Za-z0-9+.-]*:\/\/(\[([0-9A-Fa-f:.]+)\]|([^\/:?#]+))/);
	if (!m)
		return null;
	return m[2] ?? m[3];
}

/**
 * MVP-2008: reports whether the ACS is reached over IPv6, that is its host
 * is an IPv6 literal or a name that resolves to an IPv6 address.
 *
 * @param {string} url - ACS URL
 * @returns {boolean}
 */
function acs_on_ipv6(url) {
	let host = url_host(url);
	if (!host || match(host, /^[0-9.]+$/))
		return false;
	if (index(host, ':') >= 0)
		return true;
	if (!match(host, /^[A-Za-z0-9.-]+$/))
		return false;

	let p = popen(`resolveip -6 -t 2 ${host} 2>/dev/null`, 'r');
	if (!p)
		return false;
	let out = p.read('all');
	p.close();

	return index(out ?? '', ':') >= 0;
}

function first_address(iface, key) {
	return netifd_status_get(iface)?.[key]?.[0]?.address;
}

/**
 * Composes the Connection Request URL from the WAN addresses and the cpe
 * options in /etc/config/cwmp. The family follows the ACS: IPv6 when the
 * ACS is reached over IPv6 or the WAN has no IPv4 address, IPv4 otherwise.
 * netifd keeps the DHCPv6 address on the "<iface>6" interface.
 *
 * @returns {string} Connection Request URL, or '' while the WAN has no
 *                   usable address
 */
export function cr_url_compose() {
	let c = cursor();
	let iface = c.get('cwmp', 'cpe', 'default_wan_interface') ?? 'wan';
	let port = c.get('cwmp', 'cpe', 'port') ?? '7547';
	let path = c.get('cwmp', 'cpe', 'path') ?? 'connreq';

	let v4 = first_address(iface, 'ipv4-address');
	let v6 = first_address(`${iface}6`, 'ipv6-address') ?? first_address(iface, 'ipv6-address');

	// RFC 3986 requires an IPv6 literal in a URL to be bracketed.
	if (v6 && (!v4 || acs_on_ipv6(c.get('cwmp', 'acs', 'url'))))
		return sprintf('http://[%s]:%s/%s', v6, port, path);
	if (v4)
		return sprintf('http://%s:%s/%s', v4, port, path);
	return '';
};
