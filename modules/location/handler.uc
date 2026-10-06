'use strict';

// Out-of-tree module. `ubbf_module` is the scope datamodel.uc includes this
// file with, and it is visible only while the include runs, so anything the
// handlers below use later has to be bound here. See docs/ARCHITECTURE.md.

const ubbf = ubbf_module.ubbf;
const utils = ubbf_module.utils;
const model = ubbf_module.model;

const ubus = require('ubus');
const uci = require('uci');

const schema = ubbf_module.schema;

const GPS = 'gps';
const CRS_WGS84_2D = 'urn:ogc:def:crs:EPSG::4326';
const PROTOCOL = uc(utils.protocol.ACTIVE_PROTOCOL);

// Stored rows are numbered from 1 by the dispatcher; the GPS row keeps a
// number they never reach.
const GPS_INSTANCE = 10000;

let identity_warned;

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
 * `{ signal: false }` alone until its first fix. After a fix is lost the
 * daemon keeps the last position, and so does DataObject; AcquiredTime
 * tells its age.
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
		return utils.helpers.datetime_format(time() - info.age);
	return utils.helpers.datetime_format(0);
}

/**
 * Escapes a value for an XML attribute or element.
 *
 * @param {string} value - Text
 * @returns {string} Escaped text
 */
function xml_escape(value) {
	return replace(value, /[&<>"']/g, (c) => ({
		'&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&apos;'
	})[c]);
}

/**
 * URI naming this device inside the PIDF-LO envelope.
 *
 * RFC 3863 makes the `entity` of `presence` and RFC 4479 the `dm:deviceID`
 * mandatory. The `mac:` form of RFC 5491 is built from the OUI and serial,
 * which on this hardware is the base MAC.
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
 * sea level and the 3-D CRS, EPSG::4979, wants an ellipsoidal height. One
 * line on the wire.
 *
 * @param {object} info - `gps info` reply carrying a position
 * @param {string} acquired - Fix time as TR-181 dateTime
 * @returns {string} PIDF-LO XML, empty without a device identity
 */
function pidf_lo_build(info, acquired) {
	let uri = device_uri_get();
	if (!uri) {
		if (!identity_warned)
			utils.logging.log_warn('location: no device identity for the PIDF-LO entity');
		identity_warned = true;
		return '';
	}

	uri = xml_escape(uri);

	return '<presence xmlns="urn:ietf:params:xml:ns:pidf"' +
		' xmlns:dm="urn:ietf:params:xml:ns:pidf:data-model"' +
		' xmlns:gp="urn:ietf:params:xml:ns:pidf:geopriv10"' +
		' xmlns:gml="http://www.opengis.net/gml"' +
		sprintf(' entity="%s">', uri) +
		'<dm:device id="gps">' +
		'<gp:geopriv><gp:location-info>' +
		sprintf('<gml:Point srsName="%s"><gml:pos>%s %s</gml:pos></gml:Point>',
			CRS_WGS84_2D, info.latitude, info.longitude) +
		'</gp:location-info><gp:usage-rules/><gp:method>GPS</gp:method></gp:geopriv>' +
		sprintf('<dm:deviceID>%s</dm:deviceID>', uri) +
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
 * Names the controller of this device: the ACS URL for CWMP, the
 * EndpointID of the controller for USP.
 *
 * @returns {string} Controller identity, empty when none is configured
 */
function controller_id_get() {
	let cursor = uci.cursor();

	if (PROTOCOL == 'CWMP')
		return cursor.get('cwmp', 'acs', 'url') ?? '';

	return cursor.get('obuspa', 'acs', 'endpoint_id') ?? '';
}

/**
 * Maps a stored row, the location a controller configured, to a
 * Device.DeviceInfo.Location.{i} row.
 *
 * @param {object} ctx - Context with the stored row
 * @returns {object} TR-181 Location row
 */
function external_to_object(ctx) {
	return {
		...ubbf.ctx_config(ctx),
		Source: 'External',
		ExternalProtocol: PROTOCOL
	};
}

/**
 * Get handler for Device.DeviceInfo.Location.{i}.
 *
 * Stored rows are the controller's location. The GPS row is a runtime row
 * while the gps daemon answers, fix or not, and absent without the daemon,
 * so the row count tells a receiver without a fix apart from no receiver.
 *
 * @param {object} ctx - Context with instance and config
 * @returns {object|null} Row, runtime rows by instance, or null
 */
function location_get(ctx) {
	if (ctx.config)
		return external_to_object(ctx);

	let info = gps_info_get();
	if (!info)
		return ctx.instance ? null : {};

	if (ctx.instance)
		return (ctx.instance == GPS_INSTANCE) ? location_to_object(info) : null;

	return { [GPS_INSTANCE]: location_to_object(info) };
}

/**
 * Set handler for Device.DeviceInfo.Location.{i}: a written DataObject
 * records when and from which controller the location came.
 *
 * @param {object} ctx - Context with the stored row
 * @returns {number} 0
 */
function location_set(ctx) {
	if (ctx.param != 'DataObject' || !ctx.config)
		return 0;

	ctx.config.AcquiredTime = utils.helpers.datetime_format(time());
	ctx.config.ExternalSource = controller_id_get();
	return 0;
}

/**
 * Delete hook for Device.DeviceInfo.Location.{i}: the GPS row belongs to
 * the receiver.
 *
 * @param {object} ctx - `{ path, instance }`
 * @returns {number|null} Refusal for the GPS row
 */
function location_del(ctx) {
	return (ctx.instance == GPS_INSTANCE) ? -USP_ERR_OBJECT_NOT_DELETABLE : null;
}

model['Device.DeviceInfo.Location'] = {};

// TR-181 allows one location configured over CWMP or USP, and every stored
// row is one.
model['Device.DeviceInfo.Location.{i}'] = {
	schema: schema('Location'),
	get: location_get,
	set: location_set,
	del: location_del,
	runtime_instances: true,
	maxInstances: 1
};
