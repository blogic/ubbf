// Host test of Device.IEEE1905.AL.NetworkTopology.IEEE1905Device.{i}.
// IEEE1905Neighbor in modules/easymesh: umapd names a neighbour of an AP MLD
// under the BSS of its link and its Link Metric entries under the AP MLD, and
// the Metric rows of the neighbour hold them.
'use strict';

import { describe, it, assert } from 'utest';
import * as ubbf from 'ubbf';

const AGENT = '02:00:00:00:00:a1';
const CHILD = '02:00:00:00:00:b1';
const OTHER = '02:00:00:00:00:b2';
const AP_MLD = '02:00:00:00:03:00';
const LINK = '42:00:00:00:03:00';
const PORT = '02:00:00:00:10:01';
const CHILD_STA = '02:00:00:00:05:00';

let topo;

const api = {
	ubbf: { ...ubbf, cache_call: () => topo },
	model: {},
	schema: (k) => k,
};

include(sourcepath(0, true) + '/../modules/easymesh/ieee1905.uc', { ubbf_module: api, em: {} });

const topology_read = api.model['Device.IEEE1905.AL.NetworkTopology'].get;

function metric(local, al) {
	return {
		neighbor_al_mac_address: al,
		link_metrics: [ { local_if_mac_address: local, remote_if_mac_address: CHILD_STA, phy_rate: 866 } ],
	};
}

function neighbor_rows(local, map_data, metric_local) {
	topo = { devices: [ {
		al_address: AGENT,
		interfaces: [ { local_if_mac_address: local } ],
		map: map_data,
		neighbors: { ieee1905: [ { local_if_mac_address: local,
		                           ieee1905_neighbors: [ { neighbor_al_mac_address: CHILD } ] } ] },
		metrics: { tx: [ metric(metric_local, CHILD), metric(metric_local, OTHER) ], rx: [ metric(metric_local, CHILD) ] },
	} ] };

	return topology_read({ config: {} }).IEEE1905Device['1'].IEEE1905Neighbor['1'];
}

const AP_MLDS = { ap_mlds: [ { ap_mld_mac_addr: AP_MLD, affiliated_aps: [ { affiliated_ap_mac_addr: LINK } ] } ] };

describe('IEEE1905Neighbor Metric of an AP MLD', () => {
	it('a neighbour on a link reads the metrics of its AP MLD', () => {
		const row = neighbor_rows(LINK, AP_MLDS, AP_MLD);

		assert.match('1', row.MetricNumberOfEntries, 'one row, of this neighbour');
		assert.match(CHILD_STA, row.Metric['1'].NeighborMACAddress, 'the remote interface');
		assert.match('866', row.Metric['1'].PHYRate, 'the rate');
	});

	it('a neighbour on a link reads metrics on that link', () => {
		assert.match('1', neighbor_rows(LINK, AP_MLDS, LINK).MetricNumberOfEntries, 'one row');
	});

	it('a neighbour on the AP MLD address, of an older agent, keeps its metrics', () => {
		assert.match('1', neighbor_rows(AP_MLD, AP_MLDS, AP_MLD).MetricNumberOfEntries, 'one row');
	});

	it('an interface outside the AP MLD reads none of its metrics', () => {
		assert.match('0', neighbor_rows(PORT, AP_MLDS, AP_MLD).MetricNumberOfEntries, 'no row');
	});

	it('a device with no AP MLD compares the address alone', () => {
		assert.match('0', neighbor_rows(LINK, null, AP_MLD).MetricNumberOfEntries, 'no row');
	});
});
