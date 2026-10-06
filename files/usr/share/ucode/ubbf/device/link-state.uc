'use strict';

import * as rtnl from 'rtnl';
import * as ubbf from 'ubbf';

let link_state = {};

function link_state_seed() {
	let links = rtnl.request(rtnl.const.RTM_GETLINK, rtnl.const.NLM_F_DUMP, {});
	if (type(links) != 'array')
		return;

	for (let link in links) {
		if (!link?.dev)
			continue;
		link_state[link.dev] = {
			ts: 0,
			operstate: link.operstate,
			master: link.master
		};
	}
}

function rtnl_link_cb(event) {
	let msg = event?.msg;
	let dev = msg?.dev;
	if (!dev)
		return;

	if (event.cmd == rtnl.const.RTM_DELLINK) {
		delete link_state[dev];
		return;
	}

	let prev = link_state[dev];
	if (prev && prev.operstate == msg.operstate && prev.master == msg.master)
		return;

	link_state[dev] = {
		ts: ubbf.uptime_read(),
		operstate: msg.operstate,
		master: msg.master
	};
}

function status_handler(req) {
	let now = ubbf.uptime_read();
	let result = {};
	for (let dev in link_state) {
		let delta = now - link_state[dev].ts;
		result[dev] = delta < 0 ? 0 : delta;
	}
	return result;
}

/**
 * Seeds the link state table from rtnl and registers the netlink listener.
 */
export function init() {
	link_state_seed();
	rtnl.listener(rtnl_link_cb,
		[rtnl.const.RTM_NEWLINK, rtnl.const.RTM_DELLINK]);
};

/**
 * Returns the ubus method table for link-change status.
 *
 * @returns {object} Method definition for link_change_status
 */
export function ubus_methods() {
	return {
		link_change_status: {
			call: status_handler,
			args: {}
		}
	};
};
