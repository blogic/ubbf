'use strict';

import * as fs from 'fs';
import { call as cache_call } from 'ubbf.utils.cache';

/**
 * Fetches per-host traffic data from nlbwmon (uncached).
 *
 * @returns {object} Map of MAC address to traffic counters
 */
function stats_fetch() {
	let result = {};

	let p = fs.popen('nlbw -c show -c json 2>/dev/null', 'r');
	if (!p)
		return result;

	let output = p.read('all');
	p.close();

	if (!output)
		return result;

	let data;
	try {
		data = json(output);
	} catch (e) {
		return result;
	}

	if (!data?.data)
		return result;

	for (let entry in data.data) {
		let mac = uc(entry[3] ?? '');
		if (!mac || mac == '')
			continue;

		let rx_bytes = int(entry[6]) ?? 0;
		let rx_pkts = int(entry[7]) ?? 0;
		let tx_bytes = int(entry[8]) ?? 0;
		let tx_pkts = int(entry[9]) ?? 0;

		if (!(mac in result)) {
			result[mac] = {
				bytes_sent: 0,
				bytes_received: 0,
				packets_sent: 0,
				packets_received: 0
			};
		}

		result[mac].bytes_sent += tx_bytes;
		result[mac].bytes_received += rx_bytes;
		result[mac].packets_sent += tx_pkts;
		result[mac].packets_received += rx_pkts;
	}

	return result;
}

/**
 * Gets per-host traffic data from nlbwmon (cached).
 *
 * @returns {object} Map of MAC address to traffic counters
 */
export function stats_get() {
	return cache_call(stats_fetch);
};
