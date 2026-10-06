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

const USFPD = 'usfpd';

/**
 * Fetches the cage name list from the usfpd daemon.
 *
 * @returns {string[]} Array of cage names, empty array on failure
 */
function cages_fetch() {
	return ubus.call(USFPD, 'cages', {})?.cages ?? [];
}

/**
 * Fetches per-cage status (SFPCage row data and the usfpd Optical
 * classification) from the usfpd daemon.
 *
 * @param {string} name - Cage name
 * @returns {object} Daemon cage_status payload, empty object on failure
 */
function cage_status_fetch(name) {
	return ubus.call(USFPD, 'cage_status', { name }) ?? {};
}

/**
 * Fetches the transceiver bundle (vendor, status, thresholds, alarms, warnings)
 * for a cage from the usfpd daemon.
 *
 * @param {string} name - Cage name
 * @returns {object} Daemon transceiver payload, empty object on failure
 */
function transceiver_fetch(name) {
	return ubus.call(USFPD, 'transceiver', { name }) ?? {};
}

/**
 * Fetches Optical.Interface-shaped status for one cage from usfpd.
 *
 * @param {string} name - Cage name
 * @returns {object} Daemon optical_status payload, empty object on failure
 */
function optical_status_fetch(name) {
	return ubus.call(USFPD, 'optical_status', { name }) ?? {};
}

/**
 * Cached wrapper around `cages_fetch`.
 *
 * @returns {string[]} Array of cage names
 */
function cages_get() {
	return utils.cache.call(cages_fetch);
}

/**
 * Cached wrapper around `cage_status_fetch`.
 *
 * @param {string} name - Cage name
 * @returns {object} Cage status payload
 */
function cage_status_get(name) {
	return utils.cache.call(cage_status_fetch, name);
}

/**
 * Cached wrapper around `transceiver_fetch`.
 *
 * @param {string} name - Cage name
 * @returns {object} Transceiver payload
 */
function transceiver_get(name) {
	return utils.cache.call(transceiver_fetch, name);
}

/**
 * Cached wrapper around `optical_status_fetch`.
 *
 * @param {string} name - Cage name
 * @returns {object} Optical status payload
 */
function optical_status_get(name) {
	return utils.cache.call(optical_status_fetch, name);
}

/**
 * Cages whose `SFPPresent` flag is true; ordering is preserved from the
 * daemon's `cages` list so SFF8472 instance indices follow the same order
 * as the daemon's SFPReference numbering.
 *
 * @returns {string[]} Names of cages with an SFP present
 */
function present_cages_get() {
	let result = [];
	for (let name in cages_get()) {
		let status = cage_status_get(name);
		if (status.SFPPresent)
			push(result, name);
	}
	return result;
}

/**
 * Cages classified by usfpd as carrying an optical SFP, in cage-list order.
 * Classification lives in usfpd (SFF-8024 Connector + Wavelength); this
 * handler only consumes the boolean.
 *
 * @returns {string[]} Names of optical cages
 */
function optical_cages_get() {
	let result = [];
	for (let name in cages_get()) {
		if (cage_status_get(name)?.Optical)
			push(result, name);
	}
	return result;
}

/**
 * Maps a cage name to a TR-181 Device.SFPs.SFPCage.{i} row.
 *
 * @param {string} name - Cage name
 * @returns {object} TR-181 SFPCage row
 */
function cage_to_object(name) {
	let status = cage_status_get(name);
	return {
		Alias: ubbf.alias_from_name(name),
		Name: status.Name ?? name,
		SFPPresent: status.SFPPresent ? 'true' : 'false',
		SFF8024Identifier: sprintf('%d', status.SFF8024Identifier ?? 0),
		MgmtInterface: status.MgmtInterface ?? '',
		SFPType: status.SFPType ?? '',
		SFPReference: status.SFPReference ?? ''
	};
}

/**
 * Maps the daemon's `vendor` block to a TR-181 Transceiver parameter set.
 *
 * @param {object} vendor - Daemon `vendor` payload
 * @returns {object} TR-181 Transceiver flat parameter set
 */
function vendor_to_object(vendor) {
	vendor ??= {};
	return {
		Connector: vendor.Connector ?? '',
		Transceiver: vendor.Transceiver ?? '',
		Encoding: sprintf('%d', vendor.Encoding ?? 0),
		BRNominal: sprintf('%d', vendor.BRNominal ?? 0),
		RateIdentifier: vendor.RateIdentifier ?? '',
		VendorName: vendor.VendorName ?? '',
		VendorOUI: vendor.VendorOUI ?? '',
		VendorPN: vendor.VendorPN ?? '',
		VendorRev: vendor.VendorRev ?? '',
		BRMax: sprintf('%d', vendor.BRMax ?? 0),
		BRMin: sprintf('%d', vendor.BRMin ?? 0),
		VendorSN: vendor.VendorSN ?? '',
		DateCode: vendor.DateCode ?? '',
		LengthSMFkm: sprintf('%d', vendor.LengthSMFkm ?? 0),
		LengthSMF: sprintf('%d', vendor.LengthSMF ?? 0),
		LengthOM2: sprintf('%d', vendor.LengthOM2 ?? 0),
		LengthOM1: sprintf('%d', vendor.LengthOM1 ?? 0),
		LengthOM3: sprintf('%d', vendor.LengthOM3 ?? 0),
		Wavelength: sprintf('%d', vendor.Wavelength ?? 0),
		VerCompliance: vendor.VerCompliance ?? '',
		OptCooledTrans: vendor.OptCooledTrans ? 'true' : 'false',
		OptPowerlvl: vendor.OptPowerlvl ? 'true' : 'false',
		OptLinearRcvr: vendor.OptLinearRcvr ? 'true' : 'false',
		OptRateSelect: vendor.OptRateSelect ? 'true' : 'false',
		OptTxDisable: vendor.OptTxDisable ? 'true' : 'false',
		OptTxFault: vendor.OptTxFault ? 'true' : 'false',
		OptInvertedLOS: vendor.OptInvertedLOS ? 'true' : 'false',
		OptLOS: vendor.OptLOS ? 'true' : 'false',
		DMCtypeImplemented: vendor.DMCtypeImplemented ? 'true' : 'false',
		DMCtypeInternalCal: vendor.DMCtypeInternalCal ? 'true' : 'false',
		DMCtypeExternalCal: vendor.DMCtypeExternalCal ? 'true' : 'false',
		DMCtypeRxAvgPwr: vendor.DMCtypeRxAvgPwr ? 'true' : 'false',
		EOCalarmsImplemented: vendor.EOCalarmsImplemented ? 'true' : 'false',
		EOCSoftTxDisable: vendor.EOCSoftTxDisable ? 'true' : 'false',
		EOCSoftTxFault: vendor.EOCSoftTxFault ? 'true' : 'false',
		EOCSoftRxLOS: vendor.EOCSoftRxLOS ? 'true' : 'false',
		EOCSoftRateSelect: vendor.EOCSoftRateSelect ? 'true' : 'false',
		SFF8079AppSelect: vendor.SFF8079AppSelect ? 'true' : 'false',
		SFF8431SoftRateSelect: vendor.SFF8431SoftRateSelect ? 'true' : 'false',
		EMCSPowerLvlOp: vendor.EMCSPowerLvlOp ? 'true' : 'false',
		EMCSPowerLvlSelect: vendor.EMCSPowerLvlSelect ? 'true' : 'false'
	};
}

/**
 * Maps the daemon's `status` block to a TR-181 Transceiver.Status object.
 *
 * @param {object} status - Daemon `status` payload
 * @returns {object} TR-181 Transceiver.Status object
 */
function status_to_object(status) {
	status ??= {};
	return {
		Temperature: sprintf('%d', status.Temperature ?? 0),
		Vcc: sprintf('%d', status.Vcc ?? 0),
		TxBias: sprintf('%d', status.TxBias ?? 0),
		TxPower: sprintf('%d', status.TxPower ?? 0),
		RxPower: sprintf('%d', status.RxPower ?? 0),
		TxDisableState: status.TxDisableState ? 'true' : 'false',
		SoftTxDisableSelect: status.SoftTxDisableSelect ? 'true' : 'false',
		RS1State: status.RS1State ? 'true' : 'false',
		RateSelectState: status.RateSelectState ? 'true' : 'false',
		SoftRateSelectSelect: status.SoftRateSelectSelect ? 'true' : 'false',
		TXFaultState: status.TXFaultState ? 'true' : 'false',
		RxLOSState: status.RxLOSState ? 'true' : 'false',
		DataReadyBarState: status.DataReadyBarState ? 'true' : 'false'
	};
}

/**
 * Maps the daemon's `thresholds` block to a TR-181 Transceiver.Thresholds object.
 *
 * @param {object} t - Daemon `thresholds` payload
 * @returns {object} TR-181 Transceiver.Thresholds object
 */
function thresholds_to_object(t) {
	t ??= {};
	return {
		HighTempAlarm: sprintf('%d', t.HighTempAlarm ?? 0),
		HighTempWarning: sprintf('%d', t.HighTempWarning ?? 0),
		LowTempWarning: sprintf('%d', t.LowTempWarning ?? 0),
		LowTempAlarm: sprintf('%d', t.LowTempAlarm ?? 0),
		HighVccAlarm: sprintf('%d', t.HighVccAlarm ?? 0),
		HighVccWarning: sprintf('%d', t.HighVccWarning ?? 0),
		LowVccWarning: sprintf('%d', t.LowVccWarning ?? 0),
		LowVccAlarm: sprintf('%d', t.LowVccAlarm ?? 0),
		HighTxBiasAlarm: sprintf('%d', t.HighTxBiasAlarm ?? 0),
		HighTxBiasWarning: sprintf('%d', t.HighTxBiasWarning ?? 0),
		LowTxBiasWarning: sprintf('%d', t.LowTxBiasWarning ?? 0),
		LowTxBiasAlarm: sprintf('%d', t.LowTxBiasAlarm ?? 0),
		HighTxPowerAlarm: sprintf('%d', t.HighTxPowerAlarm ?? 0),
		HighTxPowerWarning: sprintf('%d', t.HighTxPowerWarning ?? 0),
		LowTxPowerWarning: sprintf('%d', t.LowTxPowerWarning ?? 0),
		LowTxPowerAlarm: sprintf('%d', t.LowTxPowerAlarm ?? 0),
		HighRxPowerAlarm: sprintf('%d', t.HighRxPowerAlarm ?? 0),
		HighRxPowerWarning: sprintf('%d', t.HighRxPowerWarning ?? 0),
		LowRxPowerWarning: sprintf('%d', t.LowRxPowerWarning ?? 0),
		LowRxPowerAlarm: sprintf('%d', t.LowRxPowerAlarm ?? 0)
	};
}

/**
 * Maps a daemon flag block (alarms or warnings, same shape) to a TR-181 object.
 *
 * @param {object} flags - Daemon `alarms` or `warnings` payload
 * @returns {object} TR-181 Alarms/Warnings object
 */
function flags_to_object(flags) {
	flags ??= {};
	return {
		TemperatureHigh: flags.TemperatureHigh ? 'true' : 'false',
		TemperatureLow: flags.TemperatureLow ? 'true' : 'false',
		VccHigh: flags.VccHigh ? 'true' : 'false',
		VccLow: flags.VccLow ? 'true' : 'false',
		TxBiasHigh: flags.TxBiasHigh ? 'true' : 'false',
		TxBiasLow: flags.TxBiasLow ? 'true' : 'false',
		TxPowerHigh: flags.TxPowerHigh ? 'true' : 'false',
		TxPowerLow: flags.TxPowerLow ? 'true' : 'false',
		RxPowerHigh: flags.RxPowerHigh ? 'true' : 'false',
		RxPowerLow: flags.RxPowerLow ? 'true' : 'false'
	};
}

/**
 * Builds the full TR-181 Mgmt.SFF8472.{i} row for a cage, including the
 * nested Transceiver / Thresholds / Status / Alarms / Warnings objects.
 *
 * @param {string} name - Cage name
 * @returns {object} TR-181 SFF8472 row with nested Transceiver tree
 */
function sff8472_to_object(name) {
	let status = cage_status_get(name);
	let trx = transceiver_get(name);

	return {
		Alias: ubbf.alias_from_name(name),
		Name: status.Name ?? name,
		Transceiver: {
			...vendor_to_object(trx.vendor),
			Thresholds: thresholds_to_object(trx.thresholds),
			Status: status_to_object(trx.status),
			Alarms: flags_to_object(trx.alarms),
			Warnings: flags_to_object(trx.warnings)
		}
	};
}

/**
 * Get handler for Device.SFPs.
 *
 * @param {object} ctx - Context (unused)
 * @returns {object} SFPs root properties
 */
function sfps_get(ctx) {
	return {
		SFPCageNumberOfEntries: sprintf('%d', length(cages_get()))
	};
}

/**
 * Get handler for Device.SFPs.Mgmt.
 *
 * @param {object} ctx - Context (unused)
 * @returns {object} Mgmt properties
 */
function mgmt_get(ctx) {
	return {
		SFF8472NumberOfEntries: sprintf('%d', length(present_cages_get()))
	};
}

/**
 * Get handler for Device.SFPs.SFPCage.{i}.
 *
 * @param {object} ctx - Context with optional instance number
 * @returns {object|null} Single SFPCage row or enumerated rows
 */
function cage_get(ctx) {
	let cages = cages_get();

	if (ctx.instance == null)
		return ubbf.enumerate_instances(cages, cage_to_object);

	let name = ubbf.get_by_instance(cages, ctx.instance);
	if (!name)
		return null;
	return cage_to_object(name);
}

/**
 * Get handler for Device.SFPs.Mgmt.SFF8472.{i}.
 *
 * @param {object} ctx - Context with optional instance number
 * @returns {object|null} Single SFF8472 row or enumerated rows
 */
function sff8472_get(ctx) {
	let present = present_cages_get();

	if (ctx.instance == null)
		return ubbf.enumerate_instances(present, sff8472_to_object);

	let name = ubbf.get_by_instance(present, ctx.instance);
	if (!name)
		return null;
	return sff8472_to_object(name);
}

/**
 * Get handler for Device.Optical.
 *
 * @param {object} ctx - Context (unused)
 * @returns {object} Optical container properties
 */
function optical_get(ctx) {
	return {
		InterfaceNumberOfEntries: sprintf('%d', length(optical_cages_get()))
	};
}

/**
 * Builds a TR-181 Optical.Interface row from the cage name and any
 * stored per-row config (carrying writable Enable).
 *
 * @param {string} name - Cage name
 * @param {object} stored - Stored per-row config (may be empty)
 * @returns {object} TR-181 Interface row
 */
function interface_row(name, stored) {
	let s = optical_status_get(name);
	return {
		Enable: stored?.Enable ?? 'true',
		Status: s.Status ?? '',
		Alias: ubbf.alias_from_name(name),
		Name: s.Name ?? name,
		LastChange: '0',
		LowerLayers: '',
		Upstream: s.Upstream ? 'true' : 'false',
		MaxBitRate: sprintf('%d', s.MaxBitRate ?? 0),
		SFPReferenceList: s.SFPReferenceList ?? '',
		OpticalSignalLevel: sprintf('%d', s.OpticalSignalLevel ?? 0),
		TransmitOpticalLevel: sprintf('%d', s.TransmitOpticalLevel ?? 0)
	};
}

/**
 * Get handler for Device.Optical.Interface.{i}.
 *
 * Enumerate mode (ctx.instance == null) returns all rows keyed by
 * instance number; the per-row mode resolves one cage.
 *
 * @param {object} ctx - Context with instance and stored config
 * @returns {object|null} Enumerated rows, single row, or null
 */
function interface_get(ctx) {
	let cages = optical_cages_get();

	if (ctx.instance == null) {
		// enumerate mode passes ctx.config = null; the persisted rows
		// (carrying writable Enable) live under the runtime root
		let stored_rows = ctx.root?.Device?.Optical?.Interface ?? {};
		let make_row = (name, idx) => {
			let stored = stored_rows[sprintf('%d', idx + 1)] ?? {};
			return interface_row(name, stored);
		};
		return ubbf.enumerate_instances(cages, make_row);
	}

	let name = ubbf.get_by_instance(cages, ctx.instance);
	if (!name)
		return null;
	return interface_row(name, ctx.config ?? {});
}

/**
 * Set handler for Device.Optical.Interface.{i}.
 *
 * Persists the cage's netdev Name to config the first time any writable
 * param is set, so the render template can match the stored row to its
 * network UCI device section.
 *
 * @param {object} ctx - Set context with instance and workspace config
 */
function interface_set(ctx) {
	if (ctx.config.Name)
		return;

	let cages = optical_cages_get();
	let name = ubbf.get_by_instance(cages, ctx.instance);
	if (!name)
		return;

	let s = optical_status_get(name);
	ctx.config.Name = s.Name ?? name;
}

/**
 * Get handler for Device.Optical.Interface.{i}.Stats.
 *
 * @param {object} ctx - Context with parent config
 * @returns {object|null} udevstats counters for the optical netdev
 */
function interface_stats_get(ctx) {
	let parent = ctx.parent ?? ctx.config;
	let instance = parent?.['.instance'] ?? ctx.instance;

	// the stored Name only exists after the first write to the row;
	// resolve the netdev live from the cage list like Stats.Reset() does
	let name = ubbf.get_by_instance(optical_cages_get(), instance);
	if (!name)
		return null;

	let netdev = optical_status_get(name)?.Name ?? name;
	return utils.ifstats.ifstats_get(netdev);
}

/**
 * Sync operation handler for Device.Optical.Interface.{i}.Stats.Reset().
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

	let cages = optical_cages_get();
	let name = ubbf.get_by_instance(cages, idx);
	if (!name)
		return null;

	let netdev = optical_status_get(name)?.Name ?? name;
	if (!utils.ifstats.ifstats_reset(netdev))
		return null;
	return {};
}

model['Device.SFPs'] = {
	schema: schemas.SFPs,
	get: sfps_get
};

model['Device.SFPs.SFPCage'] = {
};

model['Device.SFPs.SFPCage.{i}'] = {
	schema: schemas.SFPCage,
	get: cage_get
};

model['Device.SFPs.Mgmt'] = {
	schema: schemas.Mgmt,
	get: mgmt_get
};

model['Device.SFPs.Mgmt.SFF8472'] = {
};

model['Device.SFPs.Mgmt.SFF8472.{i}'] = {
	schema: schemas.Mgmt_SFF8472,
	get: sff8472_get
};

model['Device.SFPs.Mgmt.SFF8472.{i}.Transceiver'] = {
	schema: schemas.SFF8472_Transceiver
};

model['Device.SFPs.Mgmt.SFF8472.{i}.Transceiver.Alarms'] = {
	schema: schemas.Transceiver_Alarms
};

model['Device.SFPs.Mgmt.SFF8472.{i}.Transceiver.Status'] = {
	schema: schemas.Transceiver_Status
};

model['Device.SFPs.Mgmt.SFF8472.{i}.Transceiver.Thresholds'] = {
	schema: schemas.Transceiver_Thresholds
};

model['Device.SFPs.Mgmt.SFF8472.{i}.Transceiver.Warnings'] = {
	schema: schemas.Transceiver_Warnings
};

model['Device.Optical'] = {
	schema: schemas.Optical,
	get: optical_get
};

model['Device.Optical.Interface'] = {
};

model['Device.Optical.Interface.{i}'] = {
	schema: schemas.Optical_Interface,
	get: interface_get,
	set: interface_set
};

model['Device.Optical.Interface.{i}.Stats'] = {
	schema: schemas.Optical_Interface_Stats,
	get: interface_stats_get
};

operations['Device.Optical.Interface.{i}.Stats.Reset()'] = {
	type: 'sync',
	handler: interface_stats_reset
};
