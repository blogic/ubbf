'use strict';

import * as fs from 'fs';
import * as rtnl from 'rtnl';
import * as ubus from 'ubus';
import * as uloop from 'uloop';
import { log_err } from 'ubbf.utils.logging';
import {
	MAIN_TABLE, SOURCE_TABLE_BASE, SOURCE_TABLE_MAX, source_table_contents
} from 'ubbf.utils.routing';

const CONFIG_PATH = '/etc/ubbf/config.json';
const SYNC_DELAY = 250;

// The copies carry a protocol number of their own, which no routing daemon
// of OpenWrt uses, so that a sync finds and removes only its own routes and
// leaves the routes that netifd writes from the configuration alone.
const MIRROR_PROTO = 201;

const COPY_TYPES = [
	rtnl.const.RTN_UNICAST, rtnl.const.RTN_BLACKHOLE,
	rtnl.const.RTN_UNREACHABLE, rtnl.const.RTN_PROHIBIT
];

let targets = [];
let sync_timer;

/**
 * Reads the source tables of Router.1 from the configuration, with the
 * destinations that the configuration already routes in each of them.
 */
function config_load() {
	targets = [];

	let data = fs.readfile(CONFIG_PATH);
	if (!data)
		return;

	try {
		let contents = source_table_contents(json(data));
		targets = filter(contents, (c) => c.router == '1');
	} catch (e) {
		log_err('route-mirror: invalid JSON in %s', CONFIG_PATH);
	}
}

/**
 * Returns the destination of a route message in CIDR notation.
 *
 * @param {object} r - Route message
 * @returns {string} Destination prefix
 */
function route_dst(r) {
	return r.dst ?? '0.0.0.0/0';
}

/**
 * Returns what tells two routes of one table apart for the kernel.
 *
 * @param {object} r - Route message
 * @returns {string} Key of destination, TOS and metric
 */
function route_key(r) {
	return sprintf('%s|%d|%d', route_dst(r), r.tos ?? 0, r.priority ?? 0);
}

/**
 * Builds the copy of a route of the main table for a source table.
 *
 * @param {object} r - Route message of the main table
 * @param {number} table - Source table
 * @returns {object} Route message for RTM_NEWROUTE
 */
function route_copy(r, table) {
	let copy = {
		family: rtnl.const.AF_INET,
		table,
		protocol: MIRROR_PROTO,
		dst: route_dst(r),
		tos: r.tos ?? 0,
		scope: r.scope,
		type: r.type
	};

	for (let attr in [ 'oif', 'gateway', 'priority', 'prefsrc', 'metrics', 'multipath' ])
		if (r[attr] != null)
			copy[attr] = r[attr];

	return copy;
}

/**
 * Writes the routes a source table must hold and removes the copies it
 * must no longer hold.
 *
 * @param {array} main - Routes of the main table to copy
 * @param {array} present - Copies now in the table
 * @param {object|null} target - Entry of source_table_contents(), or null
 *                               when the table is no source table of
 *                               Router.1
 */
function table_sync(main, present, target) {
	let wanted = {};

	for (let r in target ? main : []) {
		if (index(target.dests, route_dst(r)) < 0)
			wanted[route_key(r)] = r;
	}

	for (let r in present) {
		if (route_key(r) in wanted)
			continue;
		if (!rtnl.request(rtnl.const.RTM_DELROUTE, 0, { family: rtnl.const.AF_INET, table: r.table,
				protocol: MIRROR_PROTO, dst: route_dst(r), tos: r.tos ?? 0, priority: r.priority }))
			log_err('route-mirror: delete %s from table %d: %s', route_dst(r), r.table, rtnl.error());
	}

	for (let key, r in wanted) {
		if (!rtnl.request(rtnl.const.RTM_NEWROUTE, rtnl.const.NLM_F_CREATE | rtnl.const.NLM_F_REPLACE,
				route_copy(r, target.table)))
			log_err('route-mirror: copy %s to table %d: %s', route_dst(r), target.table, rtnl.error());
	}
}

/**
 * Copies the IPv4 routes of the main table into the source tables of
 * Router.1 and removes copies that are no longer current.
 */
function sync() {
	sync_timer = null;

	let routes = rtnl.request(rtnl.const.RTM_GETROUTE, rtnl.const.NLM_F_DUMP, { family: rtnl.const.AF_INET });
	if (type(routes) != 'array') {
		log_err('route-mirror: route dump failed: %s', rtnl.error());
		return;
	}

	let main = [];
	let present = {};

	for (let r in routes) {
		if (r.table == MAIN_TABLE && index(COPY_TYPES, r.type) >= 0)
			push(main, r);
		else if (r.protocol == MIRROR_PROTO && r.table >= SOURCE_TABLE_BASE && r.table <= SOURCE_TABLE_MAX)
			push(present[r.table] ??= [], r);
	}

	// Connected routes first, so that the kernel finds the gateways of the
	// routes that follow.
	main = sort(main, (a, b) => (b.scope ?? 0) - (a.scope ?? 0));

	let by_table = {};
	for (let t in targets)
		by_table[t.table] = t;

	for (let table in uniq([ ...keys(by_table), ...keys(present) ]))
		table_sync(main, present[table] ?? [], by_table[table]);
}

/**
 * Runs a sync after a short delay, so that a burst of route changes leads
 * to one sync.
 */
function sync_schedule() {
	if (sync_timer)
		sync_timer.set(SYNC_DELAY);
	else
		sync_timer = uloop.timer(SYNC_DELAY, sync);
}

/**
 * Handles a change of an IPv4 route; only the main table is copied.
 *
 * @param {object} event - rtnl event
 */
function route_event(event) {
	if (event?.msg?.table == MAIN_TABLE)
		sync_schedule();
}

/**
 * Handles bbf-dm.digest: the source tables can change with the
 * configuration.
 */
function digest_event() {
	config_load();
	sync_schedule();
}

/**
 * Loads the source tables of Router.1, copies the main table into them,
 * and follows the main table and the configuration from then on.
 */
export function init() {
	config_load();
	rtnl.listener(route_event, [ rtnl.const.RTM_NEWROUTE, rtnl.const.RTM_DELROUTE ],
		[ rtnl.const.RTNLGRP_IPV4_ROUTE ]);
	ubus.listener('bbf-dm.digest', digest_event);
	sync_schedule();
};
