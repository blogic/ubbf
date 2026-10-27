'use strict';

// Out-of-tree module. `ubbf_module` is the scope datamodel.uc includes this
// file with, and it is visible only while the include runs, so anything the
// handlers below use later has to be bound here. See docs/ARCHITECTURE.md.

const ubbf = ubbf_module.ubbf;
const utils = ubbf_module.utils;
const model = ubbf_module.model;
const operations = ubbf_module.operations;

const ubus = require('ubus');

const schema = ubbf_module.schema;

const USFPD = 'usfpd';

// Optical.Interface rows follow the cages that hold an optical SFP now; the
// instance map keeps each cage on its number while others come and go.
const OPTICAL_TABLE = 'Device.Optical.Interface';
const instance_map = utils['instance-map'];

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
 * Cages whose `SFPPresent` flag is true.
 *
 * @returns {string[]} Names of cages with an SFP present
 */
function present_cages_get() {
	return filter(cages_get(), (name) => cage_status_get(name).SFPPresent);
}

/**
 * Instance number of a cage in Device.SFPs.SFPCage.{i}. The SFF8472 row of
 * a present SFP carries the same number, so a row keeps its number while
 * an SFP enters or leaves another cage.
 *
 * @param {string} name - Cage name
 * @returns {number} Instance number, 0 for an unknown cage
 */
function cage_instance(name) {
	return index(cages_get(), name) + 1;
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
 * Returns the cage of a Device.Optical.Interface instance.
 *
 * @param {*} instance - Instance number
 * @returns {string|null} Cage name, or null when no optical cage has it
 */
function optical_cage(instance) {
	return instance_map.instance_key(OPTICAL_TABLE, optical_cages_get(), instance);
}

/**
 * Maps a cage name to a TR-181 Device.SFPs.SFPCage.{i} row. SFPType comes
 * from SFPProperties.SFP.{i} when a row matches the SFP (TR-181 2.21), else
 * from usfpd; IsAllowed applies the allow list of AllowedSFPs.
 *
 * @param {string} name - Cage name
 * @param {object|null} root - Configuration root with Device
 * @returns {object} TR-181 SFPCage row
 */
function cage_to_object(name, root) {
	let status = cage_status_get(name);
	let row = {
		Alias: ubbf.alias_from_name(name),
		Name: status.Name ?? name,
		SFPPresent: status.SFPPresent ? 'true' : 'false',
		SFF8024Identifier: sprintf('%d', status.SFF8024Identifier ?? 0),
		MgmtInterface: status.MgmtInterface ?? '',
		SFPType: status.SFPType ?? '',
		SFPReference: status.SFPPresent ? sprintf('Device.SFPs.Mgmt.SFF8472.%d.', cage_instance(name)) : '',
		IsAllowed: 'true'
	};

	if (!status.SFPPresent)
		return row;

	let sfps = root?.Device?.SFPs;
	let ident = transceiver_get(name).vendor ?? {};

	row.SFPType = utils.sfp.sfp_type_resolve(sfps, ident, row.SFPType);
	row.IsAllowed = utils.sfp.sfp_allowed(sfps, ident, row.SFPType) ? 'true' : 'false';

	return row;
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
		SFPCageNumberOfEntries: sprintf('%d', length(cages_get())),
		SupportedSFPTypes: join(',', utils.sfp.SUPPORTED_SFP_TYPES)
	};
}

/**
 * Get handler for Device.SFPs.AllowedSFPs (TR-181 2.21).
 *
 * @param {object} ctx - Context with config
 * @returns {object} Stored values with the row count
 */
function allowed_sfps_get(ctx) {
	return {
		...ubbf.ctx_config(ctx),
		AllowedSFPNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config?.AllowedSFP))
	};
}

/**
 * Get handler for Device.SFPs.SFPProperties (TR-181 2.21).
 *
 * @param {object} ctx - Context with config
 * @returns {object} Stored values with the row count
 */
function sfp_properties_get(ctx) {
	return {
		...ubbf.ctx_config(ctx),
		SFPNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config?.SFP))
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
		return ubbf.enumerate_instances(cages, (name) => cage_to_object(name, ctx.root));

	let name = ubbf.get_by_instance(cages, ctx.instance);
	if (!name)
		return null;
	return cage_to_object(name, ctx.root);
}

/**
 * Get handler for Device.SFPs.Mgmt.SFF8472.{i}.
 *
 * @param {object} ctx - Context with optional instance number
 * @returns {object|null} Single SFF8472 row or enumerated rows
 */
function sff8472_get(ctx) {
	if (ctx.instance == null) {
		let rows = {};
		for (let name in present_cages_get())
			rows[cage_instance(name)] = sff8472_to_object(name);
		return rows;
	}

	let name = (ctx.instance >= 1) ? cages_get()[ctx.instance - 1] : null;
	if (!name || !cage_status_get(name).SFPPresent)
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
 * Highest speed among the link modes the cage netdev supports.
 *
 * @param {string} netdev - Cage netdev
 * @returns {number} Mbit/s, 0 when ethtool reports no mode
 */
function max_bit_rate_get(netdev) {
	let modes = utils.ethtool.ethtool_properties_get(netdev).SupportedLinkModes ?? '';
	let best = 0;

	for (let mode in split(modes, ','))
		best = max(best, +(match(mode, /^[0-9]+/)?.[0] ?? 0));

	return best;
}

/**
 * Tells whether the cage netdev carries the upstream IP interface, directly
 * or as the base of a VLAN device.
 *
 * @param {object} root - Configuration root with Device
 * @param {string} netdev - Cage netdev
 * @returns {boolean} true for the WAN side
 */
function upstream_get(root, netdev) {
	let ref = utils.helpers.upstream_interface_ref(root);
	let iface = ref ? ubbf.navigate_data(root, ubbf.path_to_parts(ref)) : null;
	let device = iface?.Name ? utils.netifd.netifd_status_get(iface.Name)?.device : null;

	return device != null && (device == netdev || index(device, netdev + '.') == 0);
}

/**
 * Status of an optical interface. TR-181 2.21 adds NotAllowed for an SFP
 * that the allow list of Device.SFPs refuses.
 *
 * @param {string} name - Cage name
 * @param {object} s - usfpd optical_status reply
 * @param {object} stored - Stored row
 * @param {object|null} root - Configuration root with Device
 * @returns {string} TR-181 Status
 */
function interface_status(name, s, stored, root) {
	if (!s.Status)
		return 'Unknown';

	if (!ubbf.to_bool(stored?.Enable ?? 'true'))
		return 'Down';

	if (utils['dm-version'].dm_visible('2.21', null) && cage_to_object(name, root).IsAllowed == 'false')
		return 'NotAllowed';

	return s.Status;
}

/**
 * Builds a TR-181 Optical.Interface row from the cage name and any
 * stored per-row config (carrying writable Enable).
 *
 * @param {string} name - Cage name
 * @param {object} stored - Stored per-row config (may be empty)
 * @param {object|null} root - Configuration root with Device
 * @returns {object} TR-181 Interface row
 */
function interface_row(name, stored, root) {
	let s = optical_status_get(name);
	let netdev = s.Name ?? name;

	return {
		Enable: stored?.Enable ?? 'true',
		Status: interface_status(name, s, stored, root),
		Alias: stored?.Alias || ubbf.alias_from_name(name),
		Name: netdev,
		Description: stored?.Description ?? '',
		LastChange: utils.netdev_change.last_change_get(netdev),
		LowerLayers: '',
		Upstream: upstream_get(root, netdev) ? 'true' : 'false',
		MaxBitRate: sprintf('%d', max_bit_rate_get(netdev)),
		SFPReferenceList: sprintf('Device.SFPs.SFPCage.%d', cage_instance(name)),
		OpticalSignalLevel: sprintf('%d', s.OpticalSignalLevel ?? 0),
		TransmitOpticalLevel: sprintf('%d', s.TransmitOpticalLevel ?? 0)
	};
}

/**
 * Get handler for Device.Optical.Interface.{i}.
 *
 * The table holds the cages with an optical SFP (runtime_instances); a
 * write stores its row (writable_rows). A stored row whose cage holds no
 * optical SFP any more stays visible as NotPresent, so its Enable can
 * still be read and changed. Enumerate mode leaves out the stored rows,
 * which the dispatcher reads one by one.
 *
 * @param {object} ctx - Context with instance and stored config
 * @returns {object|null} Rows by instance, one row, or null
 */
function interface_get(ctx) {
	if (ctx.instance == null) {
		let stored = ctx.root?.Device?.Optical?.Interface ?? {};
		let rows = instance_map.instance_rows(OPTICAL_TABLE, optical_cages_get(),
			(name, n) => interface_row(name, {}, ctx.root));

		for (let n in keys(rows))
			if (stored[n])
				delete rows[n];

		return rows;
	}

	let name = optical_cage(ctx.instance);

	if (!ctx.config)
		return name ? interface_row(name, {}, ctx.root) : null;

	if (!name)
		return { ...ubbf.ctx_config(ctx), Status: 'NotPresent' };

	return interface_row(name, ctx.config, ctx.root);
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

	let name = optical_cage(ctx.instance);
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
	let name = optical_cage(instance);
	if (!name)
		return null;

	let netdev = optical_status_get(name)?.Name ?? name;
	return utils.ifstats.ifstats_basic_get(netdev);
}

/**
 * Sync operation handler for Device.Optical.Interface.{i}.Stats.Reset().
 *
 * @param {object} input - Operation input (unused)
 * @param {string} command_key - Command key (unused)
 * @param {array} instances - Instance numbers from path match
 * @returns {object|number} Empty object on success, else a negative USP
 *   error code
 */
function interface_stats_reset(input, command_key, instances) {
	let name = optical_cage(instances[0]);
	if (!name) {
		utils.logging.log_warn('Optical.Interface.%s.Stats.Reset(): no optical SFP', instances[0]);
		return -USP_ERR_OBJECT_DOES_NOT_EXIST;
	}

	let netdev = optical_status_get(name)?.Name ?? name;
	if (!utils.ifstats.ifstats_reset(netdev)) {
		utils.logging.log_warn('Optical.Interface.%s.Stats.Reset(): counters of %s not reset', instances[0], netdev);
		return -USP_ERR_COMMAND_FAILURE;
	}

	return {};
}

model['Device.SFPs'] = {
	schema: schema('SFPs'),
	get: sfps_get
};

model['Device.SFPs.SFPCage'] = {
};

model['Device.SFPs.AllowedSFPs'] = {
	schema: schema('AllowedSFPs'),
	get: allowed_sfps_get,
	since: '2.21'
};

model['Device.SFPs.AllowedSFPs.AllowedSFP'] = {
	since: '2.21'
};

model['Device.SFPs.AllowedSFPs.AllowedSFP.{i}'] = {
	schema: schema('AllowedSFP'),
	get: ubbf.ctx_config,
	since: '2.21'
};

model['Device.SFPs.SFPProperties'] = {
	schema: schema('SFPProperties'),
	get: sfp_properties_get,
	since: '2.21'
};

model['Device.SFPs.SFPProperties.SFP'] = {
	since: '2.21'
};

model['Device.SFPs.SFPProperties.SFP.{i}'] = {
	schema: schema('SFPProperties_SFP'),
	get: ubbf.ctx_config,
	since: '2.21'
};

model['Device.SFPs.SFPCage.{i}'] = {
	schema: schema('SFPCage'),
	get: cage_get
};

model['Device.SFPs.Mgmt'] = {
	schema: schema('Mgmt'),
	get: mgmt_get
};

model['Device.SFPs.Mgmt.SFF8472'] = {
};

model['Device.SFPs.Mgmt.SFF8472.{i}'] = {
	schema: schema('Mgmt_SFF8472'),
	get: sff8472_get
};

model['Device.SFPs.Mgmt.SFF8472.{i}.Transceiver'] = {
	schema: schema('SFF8472_Transceiver')
};

model['Device.SFPs.Mgmt.SFF8472.{i}.Transceiver.Alarms'] = {
	schema: schema('Transceiver_Alarms')
};

model['Device.SFPs.Mgmt.SFF8472.{i}.Transceiver.Status'] = {
	schema: schema('Transceiver_Status')
};

model['Device.SFPs.Mgmt.SFF8472.{i}.Transceiver.Thresholds'] = {
	schema: schema('Transceiver_Thresholds')
};

model['Device.SFPs.Mgmt.SFF8472.{i}.Transceiver.Warnings'] = {
	schema: schema('Transceiver_Warnings')
};

model['Device.Optical'] = {
	schema: schema('Optical'),
	get: optical_get
};

model['Device.Optical.Interface'] = {
};

model['Device.Optical.Interface.{i}'] = {
	schema: schema('Optical_Interface'),
	get: interface_get,
	set: interface_set,
	runtime_instances: true,
	writable_rows: true
};

model['Device.Optical.Interface.{i}.Stats'] = {
	schema: schema('Optical_Interface_Stats'),
	get: interface_stats_get
};

operations['Device.Optical.Interface.{i}.Stats.Reset()'] = {
	type: 'sync',
	handler: interface_stats_reset
};
