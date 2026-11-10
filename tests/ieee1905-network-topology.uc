// Host test of Device.IEEE1905.AL.NetworkTopology in modules/easymesh: Status
// takes a value of its TR-181 enumeration, Available where umapd answers the
// topology request and Incomplete where it does not, whatever Enable holds,
// and MaxChangeLogEntries reads a value of its range unsignedInt(1:).
'use strict';

import { describe, it, assert } from 'utest';
import * as ubbf from 'ubbf';

const AL = '02:00:00:00:00:a1';
const PATH = 'Device.IEEE1905.AL.NetworkTopology';

let topo;

let schemas = {};
const DIR = sourcepath(0, true) + '/../modules/easymesh';
include(DIR + '/schema.uc', { schemas });

const api = {
	ubbf: { ...ubbf, cache_call: () => topo },
	model: {},
	schema: (k) => schemas[k],
};

include(DIR + '/ieee1905.uc', { ubbf_module: api, em: {} });

// enable: null leaves Enable out of the configuration
function topology_read(answer, enable) {
	topo = answer;

	let topology = (enable == null) ? {} : { Enable: enable };
	let dm = ubbf.create();
	assert.match(true, dm.register(api.model), 'model registers');
	dm.load('/dev/null');
	dm.set_config({ Device: { IEEE1905: { AL: { NetworkTopology: topology } } } });
	dm.runtime_reload();
	return dm.get_subtree_with_state(PATH);
}

const ANSWER = { devices: [ { al_address: AL, interfaces: [] } ] };

describe('NetworkTopology Status', () => {
	it('umapd answers and Enable is true: Available', () => {
		assert.match('Available', topology_read(ANSWER, 'true')?.Status);
	});

	it('umapd answers and Enable is false: Available', () => {
		assert.match('Available', topology_read(ANSWER, 'false')?.Status);
	});

	it('umapd answers and Enable is not set: Available', () => {
		assert.match('Available', topology_read(ANSWER, null)?.Status);
	});

	it('umapd answers with no device: Available', () => {
		assert.match('Available', topology_read({ devices: [] }, 'true')?.Status);
	});

	it('no answer and Enable is true: Incomplete', () => {
		assert.match('Incomplete', topology_read(null, 'true')?.Status);
	});

	it('no answer and Enable is false: Incomplete', () => {
		assert.match('Incomplete', topology_read(null, 'false')?.Status);
	});

	it('no answer and Enable is not set: Incomplete', () => {
		assert.match('Incomplete', topology_read(null, null)?.Status);
	});
});

describe('NetworkTopology MaxChangeLogEntries', () => {
	it('reads 1 where the configuration holds no value', () => {
		assert.match('1', topology_read(ANSWER, null)?.MaxChangeLogEntries);
	});
});
