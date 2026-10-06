'use strict';

import { readfile } from 'fs';

// The image build writes the TR-181 version it targets. The file is in /etc
// so that a developer can switch the version on a device and reboot. This
// lives apart from datamodel.uc because ubbf-device needs the answer
// without building the data model.
const VERSION_PATH = '/etc/ubbf/tr181-version';

export const DM_VERSIONS = [ '2.19.1', '2.20.0', '2.20.1', '2.21.0' ];

/**
 * Returns the minor number of a version tag such as '2.20'.
 *
 * Tags carry major.minor only: the spec gives no item a patch version, and
 * the full XMLs of a patch release equal those of its .0 release.
 *
 * @param {string} tag - Version tag
 * @returns {number|null} Minor number, or null for a malformed tag
 */
export function tag_minor(tag) {
	// A number would match as text: 2.20 reads as "2.2".
	if (type(tag) != 'string')
		return null;

	let m = match(tag, /^2\.([0-9]+)$/);

	return m ? +m[1] : null;
};

/**
 * Reports whether an item tagged `since` and `until` exists in a version.
 *
 * `until` names the first version that deleted the item; deprecated and
 * obsoleted items stay. A malformed tag counts as absent, so a typo cannot
 * hide an item; the callers report it.
 *
 * @param {number} minor - Minor number of the version
 * @param {string|null} since - First version with the item
 * @param {string|null} until - First version without the item
 * @returns {boolean} True when the item exists in that version
 */
export function tag_visible(minor, since, until) {
	let first = tag_minor(since);
	let gone = tag_minor(until);

	if (first != null && minor < first)
		return false;

	if (gone != null && minor >= gone)
		return false;

	return true;
};

let raw = trim(readfile(VERSION_PATH) ?? '');
let known = index(DM_VERSIONS, raw) >= 0;

export const DM_VERSION = known ? raw : DM_VERSIONS[0];

export const DM_MINOR = +split(DM_VERSION, '.')[1];

// datamodel.uc logs this; the logging module cannot load where this one is
// imported without the data model.
export const DM_VERSION_ERROR = known ? null
	: `${VERSION_PATH}: "${raw}" is not one of ${join(', ', DM_VERSIONS)}, using ${DM_VERSION}`;

/**
 * Reports whether an item tagged `since` and `until` exists in the active
 * version.
 *
 * @param {string|null} since - First version with the item
 * @param {string|null} until - First version without the item
 * @returns {boolean} True when the item is part of the data model
 */
export function dm_visible(since, until) {
	return tag_visible(DM_MINOR, since, until);
};
