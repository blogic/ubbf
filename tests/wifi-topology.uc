// Host test of the umap topology of utils/wifi-dataelements.uc: the agents that
// topology_devices_get() lists from the controller and the local agent, the
// controller and the local agent that ubus_topology_get() names, and the one
// snapshot per umap object that a cache period reads.
'use strict';

import { describe, it, assert, mock } from 'utest';
import { topology_devices_build } from 'ubbf';
import { topology_devices_get, ubus_topology_get } from 'ubbf.utils.wifi-dataelements';

function device(al_address, services) {
	return {
		al_address,
		map: { supported_services: map(services, (s) => ({ supported_service: s })) }
	};
}

const CONTROLLER = { devices: [ device('02:00:00:00:00:01', [ 0 ]), device('02:00:00:00:00:02', [ 0, 1 ]) ] };
const AGENT = { devices: [ device('02:00:00:00:00:02', [ 1 ]), device('02:00:00:00:00:03', [ 1 ]) ] };

describe('umap topology', () => {
	it('lists the agents of the controller and of the local agent, each once', () => {
		let devices = topology_devices_build(CONTROLLER, AGENT);
		assert.match([ '02:00:00:00:00:02', '02:00:00:00:00:03' ], map(devices, (d) => d.al_address));
		assert.match([ { supported_service: 0 }, { supported_service: 1 } ], devices[0].map.supported_services,
			'the controller entry of an agent wins');
	});

	it('leaves out an agent without an AL address and keeps the next one', () => {
		let controller = { devices: [
			{ map: { supported_services: [ { supported_service: 1 } ] } },
			device('02:00:00:00:00:04', [ 1 ])
		] };
		assert.match([ '02:00:00:00:00:04' ], map(topology_devices_build(controller, null), (d) => d.al_address));
	});

	// The results stay in ubbf.cache_call() for 2 s of event loop time, so only
	// this test calls the cached functions.
	it('reads one snapshot per umap object in a cache period', () => {
		let calls = [];
		let replies = { umap: CONTROLLER, 'umap-agent': AGENT };
		mock.global.patch('ubus', { behavior: { call: (object, method) => {
			if (method != 'get_topology')
				return null;
			push(calls, object);
			return replies[object];
		} } });

		let devices = topology_devices_get();
		assert.match([ '02:00:00:00:00:02', '02:00:00:00:00:03' ], map(devices, (d) => d.al_address));
		assert.match({ controller_id: '02:00:00:00:00:01', colocated_agent_id: '02:00:00:00:00:02' }, ubus_topology_get(),
			'the controller and the local agent of the same snapshot');
		assert.match([ 'umap', 'umap-agent' ], calls, 'one get_topology call per umap object');
		assert.match(true, topology_devices_get() === devices, 'the device list of one cache period is one list');
	});
});
