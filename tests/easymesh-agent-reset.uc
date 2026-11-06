// Host test of X_UBBF_EasyMesh.Agent.Reset() in modules/easymesh/operations.uc
// for an agent that is not running: the umapd state file it leaves holds the
// DPP bootstrap private key, so it has mode 0600 whether or not the file
// existed before, and it goes away where the reset gives no key.
'use strict';

import { describe, it, assert, beforeEach } from 'utest';
import * as fs from 'fs';
import * as ubbf from 'ubbf';

const STATE = '/etc/umap-agent.json';

const api = {
	ubbf,
	model: {},
	operations: {},
	schema: (k) => k,
	utils: {
		'wifi-dataelements': {
			ubus_topology_get: () => ({}),
			device_api_data_get: () => ({}),
			radios_bss_sort: () => []
		},
		capabilities: { capability_radios_get: () => [] },
		wifi_radio: { radio_instances_for_bands: () => [] }
	}
};

const em = {};

include(sourcepath(0, true) + '/../modules/easymesh/operations.uc', { ubbf_module: api, em });

const reset = api.operations['Device.WiFi.DataElements.Network.X_UBBF_EasyMesh.Agent.Reset()'].handler;

const KEY = {
	privkey: 'AA01', pubkey_x: 'bb02', pubkey_y: 'cc03', hash: 'dd04', curve: 'P-256'
};

function reset_run(input) {
	const root = { Device: { WiFi: { DataElements: { Network: {
		X_UBBF_EasyMesh: { Agent: { Enable: 'false' } }
	} } } } };
	let result;

	reset(input, 1, (inst, code, err) => { result = { code, err }; }, '', root);
	return result;
}

function mode_get() {
	return fs.stat(STATE).mode & 0777;
}

describe('Agent.Reset() of an agent that is not running', () => {
	beforeEach(() => {
		fs.unlink(STATE);
		fs.unlink(STATE + '.tmp');
	});

	it('creates the state file with the key at mode 0600', () => {
		assert.match(0, reset_run(KEY).code);
		assert.match(0600, mode_get());
		assert.match('aa01', json(fs.readfile(STATE)).dpp_state.bootstrap_key.privkey);
	});

	it('gives an existing state file of mode 0644 the mode 0600', () => {
		fs.writefile(STATE, '');
		fs.chmod(STATE, 0644);

		assert.match(0, reset_run(KEY).code);
		assert.match(0600, mode_get());
	});

	it('writes no key through a temporary file left at mode 0644', () => {
		fs.writefile(STATE + '.tmp', '');
		fs.chmod(STATE + '.tmp', 0644);

		assert.match(0, reset_run(KEY).code);
		assert.match(0600, mode_get());
		assert.match(null, fs.stat(STATE + '.tmp'));
	});

	it('writes dpp_disabled at mode 0600', () => {
		assert.match(0, reset_run({ disable_dpp: 'true' }).code);
		assert.match(0600, mode_get());
		assert.match(true, json(fs.readfile(STATE)).dpp_disabled);
	});

	it('removes the state file where the reset gives no key', () => {
		fs.writefile(STATE, '{"dpp_state":{}}\n');

		assert.match(0, reset_run({}).code);
		assert.match(null, fs.stat(STATE));
	});
});
