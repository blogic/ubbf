'use strict';

import * as ubbf from 'ubbf';

/**
 * Converts a boolean value to UCI format ('1' or '0').
 *
 * @param {any} val - Value to convert
 * @returns {string} '1' for truthy, '0' for falsy
 */
export function b(val) {
	return val ? '1' : '0';
};

/**
 * Quotes a string for UCI batch syntax. Strips control characters
 * before single-quote escaping to prevent `uci batch` command
 * injection via embedded newlines in writable STRING parameters.
 *
 * @param {string} str - String to quote
 * @returns {string} Quoted string or empty string
 */
export function s(str) {
	if (str === null || str === '')
		return '';
	return sprintf("'%s'", replace(ubbf.uci_value_sanitise(str), /'/g, "'\\''"));
};

/**
 * Builds a UCI batch command string.
 *
 * @param {string} cmd_type - Command type ('set', 'add', 'add_list', etc.)
 * @param {string} path - UCI path
 * @param {any} value - Value to set
 * @param {function} formatter - Optional value formatter function
 * @returns {string} Formatted UCI command or empty string
 */
function uci_cmd(cmd_type, path, value, formatter) {
	if (cmd_type !== 'add' && value === null)
		return '';

	if (cmd_type === 'add')
		return sprintf('%s %s', cmd_type, path);
	else {
		let formatted_value = formatter ? formatter(value) : s(value);
		return sprintf('%s %s=%s', cmd_type, path, formatted_value);
	}
}

/**
 * Adds a string set command to output.
 *
 * @param {array} output - Output array to append to
 * @param {string} path - UCI path
 * @param {string} value - String value to set
 */
export function uci_set_string(output, path, value) {
	let cmd = uci_cmd('set', path, value, s);
	if (cmd)
		push(output, cmd);
};

/**
 * Adds a boolean set command to output.
 *
 * @param {array} output - Output array to append to
 * @param {string} path - UCI path
 * @param {boolean} value - Boolean value to set
 */
export function uci_set_boolean(output, path, value) {
	let cmd = uci_cmd('set', path, value, b);
	if (cmd)
		push(output, cmd);
};

/**
 * Adds a numeric set command to output.
 *
 * @param {array} output - Output array to append to
 * @param {string} path - UCI path
 * @param {number} value - Numeric value to set
 */
export function uci_set_number(output, path, value) {
	let cmd = uci_cmd('set', path, value, (v) => v);
	if (cmd)
		push(output, cmd);
};

/**
 * Adds a raw set command to output without escaping.
 *
 * @param {array} output - Output array to append to
 * @param {string} path - UCI path
 * @param {any} value - Raw value to set
 */
export function uci_set_raw(output, path, value) {
	let cmd = uci_cmd('set', path, value, (v) => v);
	if (cmd)
		push(output, cmd);
};

/**
 * Adds a delete command to output.
 *
 * @param {array} output - Output array to append to
 * @param {string} path - UCI path to delete
 */
export function uci_delete(output, path) {
	push(output, sprintf('delete %s', path));
};

/**
 * Adds a string list entry command to output.
 *
 * @param {array} output - Output array to append to
 * @param {string} path - UCI list path
 * @param {string} value - String value to add to list
 */
export function uci_list_string(output, path, value) {
	let cmd = uci_cmd('add_list', path, value, s);
	if (cmd)
		push(output, cmd);
};

/**
 * Adds a numeric list entry command to output.
 *
 * @param {array} output - Output array to append to
 * @param {string} path - UCI list path
 * @param {number} value - Numeric value to add to list
 */
export function uci_list_number(output, path, value) {
	let cmd = uci_cmd('add_list', path, value, (v) => v);
	if (cmd)
		push(output, cmd);
};

/**
 * Adds an anonymous section creation command to output.
 *
 * @param {array} output - Output array to append to
 * @param {string} path - UCI config and section type (e.g. 'firewall rule')
 */
export function uci_section(output, path) {
	let cmd = uci_cmd('add', path);
	if (cmd)
		push(output, cmd);
};

/**
 * Adds a named section creation command to output.
 *
 * @param {array} output - Output array to append to
 * @param {string} name - Full section name path
 * @param {string} type - Section type
 */
export function uci_named_section(output, name, type) {
	if (name === null)
		return;
	let cmd = sprintf('set %s=%s', name, type);
	push(output, cmd);
};

/**
 * Alias for uci_set_string.
 *
 * @param {array} output - Output array to append to
 * @param {string} path - UCI path
 * @param {string} value - Value to set
 */
export function uci_set(output, path, value) {
	uci_set_string(output, path, value);
};

/**
 * Alias for uci_list_string.
 *
 * @param {array} output - Output array to append to
 * @param {string} path - UCI list path
 * @param {string} value - Value to add to list
 */
export function uci_list(output, path, value) {
	uci_list_string(output, path, value);
};

/**
 * Joins output array into final UCI batch string.
 *
 * @param {array} output - Array of UCI commands
 * @returns {string} Newline-joined UCI batch output
 */
export function uci_output(output) {
	push(output, '');
	return join('\n', output);
};

/**
 * Adds a comment line to output. Strips control characters to
 * prevent `uci batch` command injection when user-controlled data
 * is interpolated into comments (no single-quote wrapping here).
 *
 * @param {array} output - Output array to append to
 * @param {string} comment - Comment text (should start with #)
 */
export function uci_comment(output, comment) {
	push(output, ubbf.uci_value_sanitise(comment));
};

/**
 * Converts IP version number to UCI family string.
 *
 * @param {number|string} ipver - IP version (4 or 6)
 * @returns {string|null} 'ipv4', 'ipv6', or null if invalid
 */
export function ipversion_to_family(ipver) {
	let ver = +ipver;
	if (ver == 4)
		return 'ipv4';
	if (ver == 6)
		return 'ipv6';
	return null;
};

/**
 * Formats an IP address with optional subnet mask.
 *
 * @param {string} ip - IP address
 * @param {string} mask - Subnet mask or CIDR notation
 * @returns {string|null} Formatted IP/mask string or null
 */
export function format_ip_with_mask(ip, mask) {
	if (!ip || ip == '')
		return null;
	if (!mask || mask == '')
		return ip;
	let slash = index(mask, '/');
	if (slash >= 0)
		return `${ip}/${substr(mask, slash + 1)}`;
	return `${ip}/${mask}`;
};

/**
 * Converts a firewall target to valid UCI value.
 *
 * @param {string} target - Target action (ACCEPT/DROP/REJECT)
 * @returns {string} Normalised UCI target, defaults to 'DROP'
 */
export function target_to_uci(target) {
	if (!target)
		return 'DROP';
	let t = uc(target);
	if (t == 'ACCEPT' || t == 'DROP' || t == 'REJECT')
		return t;
	return 'DROP';
};
