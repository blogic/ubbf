'use strict';

// Out-of-tree module. `ubbf_module` is the scope datamodel.uc includes this
// file with, and it is visible only while the include runs, so anything the
// handlers below use later has to be bound here. See docs/ARCHITECTURE.md.

const ubbf = ubbf_module.ubbf;
const utils = ubbf_module.utils;
const model = ubbf_module.model;
const operations = ubbf_module.operations;

const ubus = require('ubus');

let schemas = {};
include('schema.uc', { schemas });

const MODEMMANAGER = 'modemmanager';

// mmcli modem states, as ModemManager's rpcd plugin passes them through, to
// the TR-181 interface Status values.
const MODEM_STATUS = {
	'connected': 'Up',
	'failed': 'Error',
	'locked': 'Error',
	'disabled': 'Down',
	'disabling': 'Down',
	'initializing': 'Down',
	'enabling': 'Dormant',
	'enabled': 'Dormant',
	'searching': 'Dormant',
	'registered': 'Dormant',
	'connecting': 'Dormant',
	'disconnecting': 'Dormant'
};

/**
 * Fetches every modem ModemManager manages, through its rpcd plugin.
 *
 * The plugin forks mmcli several times per modem, so callers go through
 * `modems_get()`, which caches the reply for one subtree walk.
 *
 * @returns {array} Modem objects in dump order, empty when the plugin or
 *   the daemon is absent
 */
function modems_fetch() {
	return ubus.call(MODEMMANAGER, 'dump', {})?.modem ?? [];
}

/**
 * Cached wrapper around `modems_fetch`.
 *
 * @returns {array} Modem objects in dump order
 */
function modems_get() {
	return utils.cache.call(modems_fetch);
}

/**
 * Resolves a TR-181 instance number to its modem.
 *
 * @param {number} instance - 1-based instance number
 * @returns {object|null} Modem object, null when there is no such modem
 */
function modem_by_instance(instance) {
	return ubbf.get_by_instance(modems_get(), instance);
}

/**
 * The network device ModemManager reports for a modem, from its port list.
 *
 * @param {object} modem - Modem object from the dump
 * @returns {string} netdev name, empty when the modem has no net port
 */
function modem_netdev(modem) {
	for (let port in modem.generic?.ports ?? []) {
		let m = match(port, /^(\S+) \(net\)$/);
		if (m)
			return m[1];
	}
	return '';
}

/**
 * Maps ModemManager access technology to TR-181 format.
 *
 * @param {string} tech - Access technology string
 * @returns {string} TR-181 access technology (GPRS, EDGE, UMTS, LTE, NR)
 */
function access_tech_map(tech) {
	if (!tech)
		return '';

	let t = lc(tech);
	if (t == 'gsm')
		return 'GPRS';
	if (t == 'edge')
		return 'EDGE';
	if (t == 'umts')
		return 'UMTS';
	if (t == 'hspa' || t == 'hspa+' || t == 'hsdpa' || t == 'hsupa')
		return 'UMTSHSPA';
	if (t == 'lte')
		return 'LTE';
	if (t == '5gnr' || t == 'nr')
		return 'NR';

	return tech;
}

/**
 * Derives the TR-181 USIM Status from the modem's SIM and lock state.
 *
 * mmcli reports no SIM state of its own: an absent card leaves the sim
 * object empty, a PIN- or PUK-locked card shows up as the modem's
 * `unlock-required`, and a card in use carries its identifiers. Only the
 * first PIN and PUK gate the card; PIN2 protects optional features and a
 * modem reporting it as the pending lock is in service.
 *
 * @param {object} modem - Modem object from the dump
 * @returns {string} None, Available, Valid, Blocked or Error
 */
function usim_status(modem) {
	let props = modem.generic?.sim?.properties;
	if (!props || !length(props))
		return 'None';

	let lock = modem.generic?.['unlock-required'] ?? '';
	if (lock == 'sim-puk')
		return 'Blocked';
	if (lock == 'sim-pin')
		return 'Available';
	if (modem.generic?.state == 'failed')
		return 'Error';

	return 'Valid';
}

/**
 * Builds a Device.Cellular.Interface.{i} row from a modem and its stored
 * configuration.
 *
 * @param {object} modem - Modem object from the dump
 * @param {object} stored - Persisted row (may be empty)
 * @returns {object} TR-181 Interface row
 */
function interface_row(modem, stored) {
	let generic = modem.generic ?? {};
	let access_techs = generic['access-technologies'] ?? [];
	let current_tech = length(access_techs) > 0 ? access_techs[0] : '';

	// no fallback to generic signal-quality: that is a 0-100 percentage,
	// not dBm
	let lte_sig = modem.signal?.lte ?? {};

	let operator = modem['3gpp']?.['operator-name'] ?? '';
	if (operator == '--')
		operator = '';

	let supported_techs = [];
	for (let tech in access_techs)
		push(supported_techs, access_tech_map(tech));

	let netdev = modem_netdev(modem);

	return {
		Enable: stored.Enable ?? 'true',
		Status: MODEM_STATUS[generic.state] ?? 'Unknown',
		Alias: stored.Alias ?? ubbf.alias_from_name(netdev || generic.device || 'modem'),
		Name: netdev,
		LastChange: '0',
		LowerLayers: stored.LowerLayers ?? '',
		Upstream: 'true',
		IMEI: modem['3gpp']?.imei ?? '',
		SupportedAccessTechnologies: join(',', supported_techs),
		PreferredAccessTechnology: stored.PreferredAccessTechnology ?? 'Auto',
		CurrentAccessTechnology: access_tech_map(current_tech),
		AvailableNetworks: '',
		NetworkRequested: stored.NetworkRequested ?? '',
		NetworkInUse: operator,
		RSSI: sprintf('%d', int(lte_sig.rssi ?? 0)),
		RSRP: sprintf('%d', int(lte_sig.rsrp ?? 0)),
		RSRQ: sprintf('%d', int(lte_sig.rsrq ?? 0)),
		UpstreamMaxBitRate: '0',
		DownstreamMaxBitRate: '0',
		SIMReferenceList: '',
		X_UBBF_Device: generic.device ?? stored.X_UBBF_Device ?? ''
	};
}

/**
 * Records the modem's sysfs device path and netdev on its persisted
 * Interface row.
 *
 * The render needs the path to bind the netifd interface to the modem, and
 * it runs at every boot before ModemManager has probed anything, so the
 * path has to come from the stored configuration rather than the dump. The
 * netdev and the direction are what an IP.Interface stacked on this row
 * takes its own Name and Upstream from: both are computed from the stored
 * tree, never from a live get.
 *
 * @param {object} root - Writable configuration tree
 * @param {number} instance - 1-based Interface instance
 */
function interface_stamp(root, instance) {
	let modem = modem_by_instance(instance);
	if (!modem?.generic?.device) {
		utils.logging.log_warn('cellular: modem %d not present, device path not recorded', instance);
		return;
	}

	let row = ubbf.navigate_or_create(root, ['Device', 'Cellular', 'Interface', sprintf('%d', instance)]);
	if (!row.X_UBBF_Device)
		row.X_UBBF_Device = modem.generic.device;

	let netdev = modem_netdev(modem);
	if (!row.Name && netdev)
		row.Name = netdev;

	if (!row.Upstream)
		row.Upstream = 'true';
}

/**
 * Get handler for Device.Cellular.
 *
 * @param {object} ctx - Context with config
 * @returns {object} Cellular properties
 */
function cellular_get(ctx) {
	return {
		RoamingEnabled: ctx.config?.RoamingEnabled ?? 'false',
		RoamingStatus: '',
		InterfaceNumberOfEntries: sprintf('%d', length(modems_get())),
		AccessPointNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config?.AccessPoint))
	};
}

/**
 * Get handler for Device.Cellular.Interface.{i}.
 *
 * Enumerate mode (ctx.instance == null) returns one row per modem in dump
 * order; the per-row mode resolves one modem.
 *
 * @param {object} ctx - Context with instance and stored config
 * @returns {object|null} Enumerated rows, single row, or null
 */
function interface_get(ctx) {
	let modems = modems_get();

	if (ctx.instance == null) {
		let stored_rows = ctx.root?.Device?.Cellular?.Interface ?? {};
		let make_row = (modem, idx) => interface_row(modem, stored_rows[sprintf('%d', idx + 1)] ?? {});
		return ubbf.enumerate_instances(modems, make_row);
	}

	let modem = ubbf.get_by_instance(modems, ctx.instance);
	if (!modem)
		return null;
	return interface_row(modem, ctx.config ?? {});
}

/**
 * Set handler for Device.Cellular.Interface.{i}.
 *
 * @param {object} ctx - Set context with root and instance
 */
function interface_set(ctx) {
	interface_stamp(ctx.root, ctx.instance);
}

/**
 * Get handler for Device.Cellular.Interface.{i}.Stats.
 *
 * @param {object} ctx - Context with parent
 * @returns {object|null} Interface statistics
 */
function interface_stats_get(ctx) {
	let parent = ctx.parent ?? ctx.config;
	let instance = parent?.['.instance'] ?? ctx.instance;

	let modem = modem_by_instance(instance);
	let netdev = modem ? modem_netdev(modem) : '';
	if (!netdev)
		return null;

	return utils.ifstats.ifstats_get(netdev);
}

/**
 * Sync operation handler for Cellular.Interface.{i}.Stats.Reset().
 *
 * @param {object} input - Operation input (unused)
 * @param {string} command_key - Command key (unused)
 * @param {array} instances - Instance numbers from path match
 * @returns {object|null} Empty object on success, null on failure
 */
function interface_stats_reset(input, command_key, instances) {
	let idx = instances[0];
	if (idx == null)
		return null;

	let modem = modem_by_instance(idx);
	let netdev = modem ? modem_netdev(modem) : '';
	if (!netdev)
		return null;

	if (!utils.ifstats.ifstats_reset(netdev))
		return null;
	return {};
}

/**
 * Get handler for Device.Cellular.Interface.{i}.USIM.
 *
 * @param {object} ctx - Context with parent config
 * @returns {object|null} USIM/SIM card properties
 */
function usim_get(ctx) {
	let parent = ctx.parent ?? ctx.config;
	let instance = parent?.['.instance'] ?? ctx.instance;

	let modem = modem_by_instance(instance);
	if (!modem)
		return null;

	let props = modem.generic?.sim?.properties ?? {};

	return {
		Status: usim_status(modem),
		IMSI: props.imsi ?? '',
		ICCID: props.iccid ?? '',
		MSISDN: props.msisdn ?? '',
		PINCheck: ctx.config?.PINCheck ?? '',
		PIN: ''
	};
}

/**
 * Set handler for Device.Cellular.Interface.{i}.USIM.
 *
 * A PIN write is what persists the Interface row, so the modem's device
 * path is recorded alongside it.
 *
 * @param {object} ctx - Set context with root and instance
 */
function usim_set(ctx) {
	interface_stamp(ctx.root, ctx.instance);
}

/**
 * Get handler for Device.Cellular.AccessPoint.{i}.
 *
 * @param {object} ctx - Context with config
 * @returns {object} Access point properties
 */
function accesspoint_get(ctx) {
	return {
		Enable: ctx.config?.Enable ?? 'true',
		Alias: ctx.config?.Alias ?? '',
		APN: ctx.config?.APN ?? '',
		Username: ctx.config?.Username ?? '',
		Password: '',
		Proxy: ctx.config?.Proxy ?? '',
		ProxyPort: ctx.config?.ProxyPort ?? '0',
		Interface: ctx.config?.Interface ?? '',
		IPVersion: ctx.config?.IPVersion ?? '-1',
		Type: ctx.config?.Type ?? ''
	};
}

/**
 * Set handler for Device.Cellular.AccessPoint.{i}.
 *
 * Binding the access point to a Cellular.Interface records that modem's
 * device path, so the render can bind the netifd interface to it.
 *
 * @param {object} ctx - Set context with config and root
 */
function accesspoint_set(ctx) {
	let m = match(ctx.config?.Interface ?? '', /^Device\.Cellular\.Interface\.(\d+)$/);
	if (!m)
		return;

	interface_stamp(ctx.root, int(m[1]));
}

model['Device.Cellular'] = {
	schema: schemas.Cellular,
	get: cellular_get
};

model['Device.Cellular.Interface'] = {
};

// maxInstances 0 refuses a controller Add: rows come from the modems
// ModemManager reports, and a row the controller made up would have no
// modem behind it.
model['Device.Cellular.Interface.{i}'] = {
	schema: schemas.Interface,
	get: interface_get,
	set: interface_set,
	maxInstances: 0
};

model['Device.Cellular.Interface.{i}.Stats'] = {
	schema: schemas.Interface_Stats,
	get: interface_stats_get
};

model['Device.Cellular.Interface.{i}.USIM'] = {
	schema: schemas.Interface_USIM,
	get: usim_get,
	set: usim_set
};

model['Device.Cellular.AccessPoint'] = {
};

model['Device.Cellular.AccessPoint.{i}'] = {
	schema: schemas.AccessPoint,
	get: accesspoint_get,
	set: accesspoint_set
};

operations['Device.Cellular.Interface.{i}.Stats.Reset()'] = {
	type: 'sync',
	handler: interface_stats_reset
};
