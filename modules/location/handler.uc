'use strict';

// Out-of-tree module. `ubbf_module` is the scope datamodel.uc includes this
// file with, and it is visible only while the include runs, so anything the
// handlers below use later has to be bound here. See docs/ARCHITECTURE.md.

const ubbf = ubbf_module.ubbf;
const utils = ubbf_module.utils;
const model = ubbf_module.model;

const ubus = require('ubus');

let schemas = {};
include('schema.uc', { schemas });

const GPS = 'gps';
const CRS_WGS84_2D = 'urn:ogc:def:crs:EPSG::4326';

/**
 * Fetches the receiver state from the gps daemon.
 *
 * @returns {object|null} `gps info` reply, null when the object is absent
 */
function gps_info_fetch() {
	return ubus.call(GPS, 'info', {});
}

/**
 * Cached wrapper around `gps_info_fetch`.
 *
 * @returns {object|null} `gps info` reply, null when the daemon is absent
 */
function gps_info_get() {
	return utils.cache.call(gps_info_fetch);
}

/**
 * Whether the reply carries a position.
 *
 * Every key of a `gps info` reply is optional, and the daemon answers
 * `{ signal: false }` alone until its first fix.
 *
 * @param {object} info - `gps info` reply
 * @returns {boolean} true when latitude and longitude are both present
 */
function fix_present(info) {
	return info.latitude != null && info.longitude != null;
}

/**
 * Time of the last fix as a TR-181 dateTime.
 *
 * The receiver's own date and time are authoritative; `age`, monotonic
 * seconds since the fix, is the fallback when the sentences carried no
 * date. Without either, the TR-181 unknown-time sentinel.
 *
 * @param {object} info - `gps info` reply
 * @returns {string} ISO 8601 UTC dateTime
 */
function acquired_time_get(info) {
	if (info.date != null && info.time != null)
		return sprintf('%sT%sZ', info.date, info.time);
	if (info.age != null)
		return ubbf.iso8601_format(time() - info.age);
	return utils.helpers.datetime_format(0);
}

/**
 * URI naming this device inside the PIDF-LO envelope.
 *
 * RFC 4479 makes `dm:deviceID` mandatory. The `mac:` form of RFC 5491 is
 * built from the OUI and serial, which on this hardware is the base MAC.
 *
 * @returns {string} `mac:` URI, empty when the identity file lacks either half
 */
function device_uri_get() {
	let info = utils.deviceinfo.deviceinfo_get();
	if (!info.ManufacturerOUI || !info.SerialNumber)
		return '';
	return 'mac:' + lc(info.ManufacturerOUI + info.SerialNumber);
}

/**
 * Renders the position as a PIDF-LO document in the RFC 5491 section 5.2.1
 * shape: one `dm:device` element holding a WGS 84 point and the GPS method.
 *
 * The point is 2-D because ucode-gps reports the GGA altitude above mean
 * sea level and the 3-D CRS, EPSG::4979, wants an ellipsoidal height. The
 * envelope identity is left out when the device has none rather than
 * invented. One line on the wire.
 *
 * @param {object} info - `gps info` reply carrying a position
 * @param {string} acquired - Fix time as TR-181 dateTime
 * @returns {string} PIDF-LO XML
 */
function pidf_lo_build(info, acquired) {
	let uri = device_uri_get();
	let entity = uri ? sprintf(' entity="%s"', uri) : '';
	let device_id = uri ? sprintf('<dm:deviceID>%s</dm:deviceID>', uri) : '';

	return '<presence xmlns="urn:ietf:params:xml:ns:pidf"' +
		' xmlns:dm="urn:ietf:params:xml:ns:pidf:data-model"' +
		' xmlns:gp="urn:ietf:params:xml:ns:pidf:geopriv10"' +
		' xmlns:gml="http://www.opengis.net/gml"' + entity + '>' +
		'<dm:device id="gps">' +
		'<gp:geopriv><gp:location-info>' +
		sprintf('<gml:Point srsName="%s"><gml:pos>%s %s</gml:pos></gml:Point>',
			CRS_WGS84_2D, info.latitude, info.longitude) +
		'</gp:location-info><gp:usage-rules/><gp:method>GPS</gp:method></gp:geopriv>' +
		device_id +
		sprintf('<dm:timestamp>%s</dm:timestamp>', acquired) +
		'</dm:device></presence>';
}

/**
 * Maps a `gps info` reply to a Device.DeviceInfo.Location.{i} row.
 *
 * @param {object} info - `gps info` reply
 * @returns {object} TR-181 Location row
 */
function location_to_object(info) {
	let acquired = acquired_time_get(info);

	return {
		Source: 'GPS',
		AcquiredTime: acquired,
		ExternalSource: '',
		ExternalProtocol: '',
		DataObject: fix_present(info) ? pidf_lo_build(info, acquired) : ''
	};
}

/**
 * Get handler for Device.DeviceInfo.Location.{i}.
 *
 * One row while the gps daemon answers, fix or not; none when it is absent,
 * so the row count tells a receiver without a fix apart from no receiver.
 *
 * @param {object} ctx - Context with instance
 * @returns {object|null} Enumerated rows, single row, or null
 */
function location_get(ctx) {
	let info = gps_info_get();
	if (!info)
		return null;

	let sources = [info];
	if (ctx.instance == null)
		return ubbf.enumerate_instances(sources, location_to_object);

	let source = ubbf.get_by_instance(sources, ctx.instance);
	if (!source)
		return null;
	return location_to_object(source);
}

model['Device.DeviceInfo.Location'] = {};

// maxInstances 0 refuses a controller Add: a persisted row would take the
// dispatcher's runtime discovery away from the GPS row and hide it.
model['Device.DeviceInfo.Location.{i}'] = {
	schema: schemas.Location,
	get: location_get,
	maxInstances: 0
};
