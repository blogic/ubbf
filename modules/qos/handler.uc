'use strict';

// Out-of-tree module. `ubbf_module` is the scope datamodel.uc includes this
// file with, and it is visible only while the include runs, so anything the
// handlers below use later has to be bound here. See docs/ARCHITECTURE.md.

const ubbf = ubbf_module.ubbf;
const model = ubbf_module.model;
const cache_call = ubbf_module.ubbf.cache_call;
const netifd_status_get = ubbf_module.utils.netifd.netifd_status_get;
const cmd_build = ubbf_module.ubbf.cmd_build;

const fs = require('fs');

const schema = ubbf_module.schema;

// bbf-qos-apply writes the result of each row it handled here.
const STATUS_PATH = '/tmp/ubbf/qos-status.json';

const MAX_ENTRIES = 64;

// The HTB class of a queue without TrafficClasses, as in bbf-qos-apply.
const DEFAULT_CLASS = 10;

/**
 * Reads a JSON file.
 *
 * @param {string} path - File path
 * @returns {*} Parsed value, or null when the file is missing or invalid
 */
function json_load(path) {
	let data = fs.readfile(path);
	if (!data)
		return null;

	try {
		return json(data);
	} catch (e) {
		return null;
	}
}

/**
 * Reads the results of the last bbf-qos-apply run (uncached).
 *
 * @returns {object} Status by row path
 */
function apply_status_fetch() {
	let status = json_load(STATUS_PATH);
	return (type(status) == 'object') ? status : {};
}

/**
 * Reads the results of the last bbf-qos-apply run (cached).
 *
 * @returns {object} Status by row path
 */
function apply_status_get() {
	return cache_call(apply_status_fetch);
}

/**
 * Returns the Status of a row that bbf-qos-apply handles. An enabled row
 * without a result is not applied yet, or the apply failed before it.
 *
 * @param {string} path - Row path without the trailing dot
 * @param {object} row - Stored row
 * @returns {string} TR-181 Status
 */
function row_status(path, row) {
	if (!ubbf.to_bool(row?.Enable))
		return 'Disabled';
	return apply_status_get()[path] ?? 'Error';
}

/**
 * Resolves an interface reference to its kernel device: the device of a
 * netifd interface, or a netdev with the Name of the referenced row.
 *
 * @param {object} root - Root config
 * @param {string} ref - Interface reference
 * @returns {string|null} Device name
 */
function ref_device(root, ref) {
	let name = ubbf.interface_to_name(root, ref);
	if (!name || !match(name, /^[a-zA-Z0-9._-]+$/))
		return null;

	let status = netifd_status_get(name);
	let dev = status?.l3_device ?? status?.device;
	if (dev)
		return dev;

	return fs.stat(`/sys/class/net/${name}`) ? name : null;
}

/**
 * Returns the instance number of a Device.WiFi.SSID reference.
 *
 * @param {string} ref - Interface reference
 * @returns {string|null} Instance number, or null for another reference
 */
function ssid_ref_instance(ref) {
	let m = match(ref, /^Device\.WiFi\.SSID\.(\d+)\.?$/);
	return m ? m[1] : null;
}

/**
 * Returns the Status of a shaper on a WiFi SSID, which render.uc turns
 * into ratelimit defaults: a rate in bits per second, or -1.
 *
 * @param {object} row - Stored shaper row
 * @param {object} root - Root config
 * @returns {string} TR-181 Status
 */
function wifi_shaper_status(row, root) {
	if (!ubbf.to_bool(row.Enable))
		return 'Disabled';

	let ssid = root?.Device?.WiFi?.SSID?.[ssid_ref_instance(row.Interface)];
	let rate = ubbf.to_int(row.ShapingRate);
	if (!ssid?.SSID || rate == null || (rate >= 0 && rate <= 100))
		return 'Error_Misconfigured';

	return 'Enabled';
}

/**
 * Returns the get handler of a table whose Status bbf-qos-apply records.
 *
 * @param {string} table - Table name below Device.QoS
 * @returns {function} Get handler
 */
function applied_row_get(table) {
	return (ctx) => {
		if (!ctx.config)
			return null;

		return {
			...ctx.config,
			Status: row_status(`Device.QoS.${table}.${ctx.instance}`, ctx.config)
		};
	};
}

/**
 * Get handler for Device.QoS.Shaper.{i}.
 *
 * @param {object} ctx - Context with config, instance and root
 * @returns {object|null} Shaper row with Status
 */
function shaper_get(ctx) {
	if (!ctx.config)
		return null;

	let status = ssid_ref_instance(ctx.config.Interface)
		? wifi_shaper_status(ctx.config, ctx.root)
		: row_status(`Device.QoS.Shaper.${ctx.instance}`, ctx.config);

	return { ...ctx.config, Status: status };
}

/**
 * Reads the HTB class statistics of a device (uncached).
 *
 * @param {string} dev - Kernel device
 * @returns {array} Classes as tc prints them in JSON
 */
function class_stats_fetch(dev) {
	let p = fs.popen(cmd_build([ {raw: 'tc'}, '-s', '-j', 'class', 'show', 'dev', dev, {raw: '2>/dev/null'} ]), 'r');
	if (!p)
		return [];

	let out = p.read('all');
	p.close();

	try {
		let classes = json(out ?? '[]');
		return (type(classes) == 'array') ? classes : [];
	} catch (e) {
		return [];
	}
}

/**
 * Reads the HTB class statistics of a device (cached).
 *
 * @param {string} dev - Kernel device
 * @returns {array} Classes as tc prints them in JSON
 */
function class_stats_get(dev) {
	return cache_call(class_stats_fetch, dev);
}

/**
 * Returns the HTB leaf handles of a queue: one per traffic class, the
 * class number written in decimal as bbf-qos-apply does.
 *
 * @param {object} queue - Stored queue row
 * @returns {array} Handles such as "1:3"
 */
function queue_leaves(queue) {
	let classes = filter(map(ubbf.csv_to_list(queue.TrafficClasses), (c) => ubbf.to_int(c)),
		(n) => n != null);

	if (!length(classes))
		classes = [ DEFAULT_CLASS ];

	return map(uniq(classes), (n) => sprintf('1:%d', n));
}

/**
 * Get handler for Device.QoS.QueueStats.{i}. The counters are the sum
 * over the HTB leaves of the queue on the device; tc has no count of the
 * dropped bytes, so DroppedBytes stays 0.
 *
 * @param {object} ctx - Context with config and root
 * @returns {object|null} QueueStats row with Status and counters
 */
function queuestats_get(ctx) {
	let row = ctx.config;
	if (!row)
		return null;

	let result = {
		...row,
		Status: 'Disabled',
		OutputPackets: '0',
		OutputBytes: '0',
		DroppedPackets: '0',
		DroppedBytes: '0'
	};

	if (!ubbf.to_bool(row.Enable))
		return result;

	result.Status = 'Error_Misconfigured';
	if (!row.Queue)
		return result;

	let queue = ubbf.get(ctx.root, rtrim(row.Queue, '.'));
	let dev = ref_device(ctx.root, row.Interface);
	if (type(queue) != 'object' || !dev)
		return result;

	let leaves = queue_leaves(queue);
	let found = filter(class_stats_get(dev), (c) => index(leaves, c.handle) >= 0);
	if (length(found) != length(leaves))
		return result;

	let packets = 0, bytes = 0, drops = 0;
	for (let c in found) {
		packets += c.stats?.packets ?? 0;
		bytes += c.stats?.bytes ?? 0;
		drops += c.stats?.drops ?? 0;
	}

	result.Status = 'Enabled';
	result.OutputPackets = sprintf('%d', packets);
	result.OutputBytes = sprintf('%d', bytes);
	result.DroppedPackets = sprintf('%d', drops);
	return result;
}

/**
 * Get handler for Device.QoS.
 *
 * @param {object} ctx - Context with config
 * @returns {object} QoS properties with instance counts
 */
function qos_get(ctx) {
	let max = sprintf('%d', MAX_ENTRIES);

	return {
		...ubbf.ctx_config(ctx),
		MaxClassificationEntries: max,
		MaxPolicerEntries: max,
		MaxQueueEntries: max,
		MaxShaperEntries: max,
		ClassificationNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config?.Classification)),
		PolicerNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config?.Policer)),
		QueueNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config?.Queue)),
		QueueStatsNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config?.QueueStats)),
		ShaperNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config?.Shaper))
	};
}

model['Device.QoS'] = {
	schema: schema('QoS'),
	get: qos_get
};

model['Device.QoS.Classification'] = {};

model['Device.QoS.Classification.{i}'] = {
	schema: schema('Classification'),
	get: applied_row_get('Classification'),
	maxInstances: MAX_ENTRIES
};

model['Device.QoS.Policer'] = {};

model['Device.QoS.Policer.{i}'] = {
	schema: schema('Policer'),
	get: applied_row_get('Policer'),
	maxInstances: MAX_ENTRIES
};

model['Device.QoS.Queue'] = {};

model['Device.QoS.Queue.{i}'] = {
	schema: schema('Queue'),
	get: applied_row_get('Queue'),
	maxInstances: MAX_ENTRIES
};

model['Device.QoS.QueueStats'] = {};

model['Device.QoS.QueueStats.{i}'] = {
	schema: schema('QueueStats'),
	get: queuestats_get,
	maxInstances: MAX_ENTRIES
};

model['Device.QoS.Shaper'] = {};

model['Device.QoS.Shaper.{i}'] = {
	schema: schema('Shaper'),
	get: shaper_get,
	maxInstances: MAX_ENTRIES
};
