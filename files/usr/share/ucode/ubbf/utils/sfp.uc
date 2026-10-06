'use strict';

// SFP type and allow list of Device.SFPs (TR-181 2.21), shared by the get
// handler of modules/usfpd and the device/sfp-allow subsystem of ubbf-device,
// so that SFPCage.{i}.IsAllowed and the blocking agree.

import * as ubbf from 'ubbf';

// ubbf has no XPON and no MoCA stack, so only Ethernet SFPs are usable.
export const SUPPORTED_SFP_TYPES = [ 'Optical Ethernet', 'Electrical Ethernet' ];

/**
 * Lists the rows of a table of the configuration in instance order.
 *
 * @param {object|null} table - Table keyed by instance
 * @returns {array} Rows
 */
function rows_ordered(table) {
	let instances = sort(filter(keys(table ?? {}), (k) => match(k, /^[0-9]+$/)), (a, b) => +a - +b);

	return map(instances, (k) => table[k]);
}

/**
 * Matches a vendor part number against a pattern in which `*` stands for
 * any run of characters; '' and '*' match every part number.
 *
 * @param {string} pattern - VendorPN criterion
 * @param {string} value - VendorPN of the SFP
 * @returns {boolean} True on a match
 */
function pn_matches(pattern, value) {
	if (pattern == '' || pattern == '*')
		return true;

	let parts = split(pattern, '*');
	if (length(parts) == 1)
		return value == pattern;

	let first = parts[0], last = parts[-1];
	let pos = length(first), end = length(value) - length(last);

	if (end < pos || substr(value, 0, pos) != first || substr(value, end) != last)
		return false;

	for (let i = 1; i < length(parts) - 1; i++) {
		let at = index(substr(value, pos, end - pos), parts[i]);
		if (at < 0)
			return false;

		pos += at + length(parts[i]);
	}

	return true;
}

/**
 * Tests the vendor criteria of a row against an SFP; an empty criterion
 * does not classify.
 *
 * @param {object} row - AllowedSFP.{i} or SFPProperties.SFP.{i} row
 * @param {object} ident - VendorName, VendorOUI and VendorPN of the SFP
 * @returns {boolean} True when every set criterion matches
 */
function vendor_matches(row, ident) {
	let name = row.VendorName ?? '';
	let oui = lc(row.VendorOUI ?? '');

	if (name != '' && name != (ident.VendorName ?? ''))
		return false;

	if (oui != '' && oui != lc(ident.VendorOUI ?? ''))
		return false;

	return pn_matches(row.VendorPN ?? '', ident.VendorPN ?? '');
}

/**
 * Returns the type of an SFP: the type of the first enabled
 * SFPProperties.SFP.{i} row that matches its vendor fields, else the type
 * usfpd reads from the EEPROM.
 *
 * @param {object|null} sfps - Device.SFPs of the configuration
 * @param {object} ident - VendorName, VendorOUI and VendorPN of the SFP
 * @param {string} eeprom_type - SFPType from usfpd
 * @returns {string} SFP type
 */
export function sfp_type_resolve(sfps, ident, eeprom_type) {
	for (let row in rows_ordered(sfps?.SFPProperties?.SFP)) {
		if (!ubbf.to_bool(row.Enable ?? 'true') || !row.SFPType)
			continue;

		if (vendor_matches(row, ident))
			return row.SFPType;
	}

	return eeprom_type;
};

/**
 * Tells whether the allow list admits an SFP: AllowAllSFPs true, or an
 * enabled AllowedSFP.{i} row whose set criteria all match.
 *
 * @param {object|null} sfps - Device.SFPs of the configuration
 * @param {object} ident - VendorName, VendorOUI and VendorPN of the SFP
 * @param {string} type - Result of sfp_type_resolve()
 * @returns {boolean} True when the SFP is allowed
 */
export function sfp_allowed(sfps, ident, type) {
	let allowed = sfps?.AllowedSFPs;

	if (ubbf.to_bool(allowed?.AllowAllSFPs ?? 'true'))
		return true;

	for (let row in rows_ordered(allowed?.AllowedSFP)) {
		if (!ubbf.to_bool(row.Enable ?? 'false'))
			continue;

		if ((row.SFPType ?? '') != '' && row.SFPType != type)
			continue;

		if (vendor_matches(row, ident))
			return true;
	}

	return false;
};
