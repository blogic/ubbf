'use strict';

// The TR-181 data type Order: an entry created without a value goes last,
// a value that an existing entry holds moves that entry and all lower
// ones down by one, and a deletion compacts the values.

import * as ubbf from 'ubbf';

// The TR-181 2.21 tables whose Order parameter has the data type Order.
export const ORDER_TABLES = [
	'Device.Bridging.Filter',
	'Device.DHCPv4.Client.{i}.ReqOption',
	'Device.DHCPv4.Relay.Forwarding',
	'Device.DHCPv4.Server.Pool',
	'Device.DHCPv6.Server.Pool',
	'Device.Firewall.Chain.{i}.Rule',
	'Device.Firewall.Level',
	'Device.GRE.Filter',
	'Device.IPsec.Filter',
	'Device.L2TPv3.Filter',
	'Device.MQTT.BrokerSecurity.ACL',
	'Device.QoS.Classification',
	'Device.UserInterface.HTTPAccess',
	'Device.VXLAN.Filter',
];

function order_of(row) {
	let n = ubbf.to_int(row?.Order);
	return (n != null && n >= 1) ? n : null;
}

function by_order(a, b) {
	return (a.order != b.order) ? a.order - b.order : a.n - b.n;
}

/**
 * The rows of each Order table in a config tree.
 *
 * @param {object} data - Config tree
 * @returns {object} Table path to its rows object
 */
function order_tables(data) {
	let tables = {};

	for (let table in ORDER_TABLES) {
		let parts = split(table, '.');
		let name = pop(parts);
		let parents = (index(parts, '{i}') >= 0)
			? ubbf.collect_instances_for_pattern(parts, data, 0, '')
			: [ join('.', parts) ];

		for (let parent in parents) {
			let rows = ubbf.navigate_data(data, split(parent, '.'))?.[name];
			if (type(rows) == 'object')
				tables[`${parent}.${name}`] = rows;
		}
	}

	return tables;
}

function row_keys(rows) {
	return sort(filter(keys(rows), (k) => match(k, /^[0-9]+$/)), (a, b) => +a - +b);
}

/**
 * The Order values of a config tree, to compare a later tree against.
 *
 * @param {object} data - Config tree
 * @returns {object} Table path to `{ instance: Order }`
 */
export function order_snapshot(data) {
	let snap = {};

	for (let path, rows in order_tables(data)) {
		snap[path] = {};
		for (let k in row_keys(rows))
			snap[path][k] = order_of(rows[k]);
	}

	return snap;
};

/**
 * Order values for a table whose earlier values are unknown: duplicates
 * move down in instance order, and rows without a value go last.
 */
function order_loaded(rows) {
	let ordered = [], result = {}, last = 0;

	for (let k in row_keys(rows))
		if (order_of(rows[k]) != null)
			push(ordered, { k, n: +k, order: order_of(rows[k]) });

	for (let e in sort(ordered, by_order))
		result[e.k] = last = max(last + 1, e.order);

	for (let k in row_keys(rows))
		if (!exists(result, k))
			result[k] = ++last;

	return result;
}

/**
 * Moves the entries from a taken value on down by one.
 */
function order_room_make(base, value) {
	if (index(values(base), value) < 0)
		return;

	for (let k, order in base)
		if (order >= value)
			base[k] = order + 1;
}

/**
 * Order values for a table after a change against its earlier values.
 */
function order_changed(rows, before) {
	let base = {}, written = [], unset = [];

	for (let k in row_keys(rows)) {
		let order = order_of(rows[k]);
		if (order == null)
			push(unset, k);
		else if (exists(before, k) && before[k] == order)
			base[k] = order;
		else
			push(written, { k, n: +k, order });
	}

	for (let w in sort(written, by_order)) {
		order_room_make(base, w.order);
		base[w.k] = w.order;
	}

	if (length(filter(keys(before), (k) => !exists(rows, k)))) {
		let list = sort(map(keys(base), (k) => ({ k, n: +k, order: base[k] })), by_order);
		for (let i = 0; i < length(list); i++)
			base[list[i].k] = i + 1;
	}

	let last = max(0, ...values(base));
	for (let k in unset)
		base[k] = ++last;

	return base;
}

/**
 * Applies the data type Order to every Order table of a config tree.
 *
 * @param {object} data - Config tree, changed in place
 * @param {object|null} before - order_snapshot() of the tree before the
 *     change, or null when it is not known
 * @returns {boolean} True when a value changed
 */
export function orders_compute(data, before) {
	let changed = false;

	for (let path, rows in order_tables(data)) {
		let prev = before?.[path];
		let orders = (prev == null) ? order_loaded(rows) : order_changed(rows, prev);

		for (let k, order in orders) {
			let value = sprintf('%d', order);
			if (rows[k].Order == value)
				continue;
			rows[k].Order = value;
			changed = true;
		}
	}

	return changed;
};
