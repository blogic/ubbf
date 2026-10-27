// Host test of the pcp module handler: the Status and the assigned values
// of Device.PCP and its Client, Server and mapping rows from the status
// file of the daemon, and the countdown of a mapping Lifetime.
'use strict';

import { describe, it, assert, beforeEach } from 'utest';
import { state_clear } from 'test_env';
import * as ubbf from 'ubbf';
import * as uloop from 'uloop';
import { writefile } from 'fs';

const IN = 'Device.PCP.Client.{i}.Server.{i}.InboundMapping.{i}';
const OUT = 'Device.PCP.Client.{i}.Server.{i}.OutboundMapping.{i}';

const mapping = { Enable: 'true', Lifetime: '600', InternalPort: '8080', ProtocolNumber: '6' };
const peer = { Enable: 'true', Lifetime: '0', InternalPort: '5070', ProtocolNumber: '17' };
const server = { Enable: 'true', ServerNameOrAddress: '192.0.2.1', InboundMapping: { '1': mapping }, OutboundMapping: { '1': peer } };
const server_off = { Enable: 'false', ServerNameOrAddress: '192.0.2.2' };
const client = { Enable: 'true', THIRDPARTYEnable: 'true', Server: { '1': server, '2': server_off } };
const root = {
	Device: {
		IP: { Interface: { '1': { Name: 'wan' }, '2': { Name: 'lan' } } },
		PCP: { Enable: 'true', Client: { '3': client } }
	}
};

// env.hooks holds the commit hooks of the handler, env.applied the
// operations that it applies.
function handler_load() {
	let env = { hooks: [], applied: [] };
	let api = {
		ubbf: proto({ cache_call: (fn, ...args) => fn(...args) }, ubbf),
		utils: {},
		schema: (k) => k,
		on_commit: (cb) => push(env.hooks, cb),
		on_abort: () => null,
		config_apply: (ops, done) => {
			push(env.applied, ...ops);
			return { success: true };
		},
		model: {}
	};

	include('../modules/pcp/handler.uc', { ubbf_module: api });
	env.model = api.model;
	return env;
}

function status_write() {
	writefile('/tmp/ubbf/pcp-status.json', sprintf('%J', {
		servers: {
			'Device.PCP.Client.3.Server.1': {
				status: 'Enabled', address: '192.0.2.1', additional: '192.0.2.9',
				version: 2, external_ip: '198.51.100.77', wan_interface: 'wan'
			}
		},
		mappings: {
			'Device.PCP.Client.3.Server.1.InboundMapping.1': {
				status: 'Enabled', external_ip: '198.51.100.77', external_port: 18080
			},
			'Device.PCP.Client.3.Server.1.OutboundMapping.1': {
				status: 'Error_PCPErrorCodeReceived', error_code: 2
			}
		}
	}));
}

describe('pcp handler', () => {
	beforeEach(() => {
		state_clear();
		status_write();
	});

	it('reads the rows from the status of the daemon', () => {
		const model = handler_load().model;

		let p = model['Device.PCP'].get({ config: { Enable: 'true', Client: { '3': client } } });
		assert.match([ '0,1,2', '1,3', '1' ], [ p.SupportedVersions, p.OptionList, p.ClientNumberOfEntries ], 'PCP: lists');

		let c = model['Device.PCP.Client.{i}'].get({ instance: 3, config: client, root });
		assert.match([ 'Enabled', 'Enabled', 'Device.IP.Interface.1', '2' ],
			[ c.Status, c.THIRDPARTYStatus, c.WANInterface, c.ServerNumberOfEntries ],
			'Client: status, third party, WAN interface');

		let off_root = { Device: { PCP: { Enable: 'false', Client: { '3': client } } } };
		assert.match('StackDisabled', model['Device.PCP.Client.{i}'].get({ instance: 3, config: client, root: off_root }).Status,
			'Client: stack disabled');
		assert.match('Disabled', model['Device.PCP.Client.{i}'].get({ instance: 3, config: { Enable: 'false' }, root }).Status,
			'Client: disabled');

		let s = model['Device.PCP.Client.{i}.Server.{i}'].get({ instance: 1, config: server, parent: client, root });
		assert.match([ 'Enabled', '192.0.2.1', '192.0.2.9', '198.51.100.77', '2' ],
			[ s.Status, s.ServerAddressInUse, s.AdditionalServerAddresses, s.ExternalIPAddress, s.CurrentVersion ],
			'Server: daemon result');
		assert.match('Disabled',
			model['Device.PCP.Client.{i}.Server.{i}'].get({ instance: 2, config: server_off, parent: client, root }).Status,
			'Server: disabled row');

		let m = model[IN].get({ instance: 1, config: mapping, parent: server, root });
		assert.match([ 'Enabled', '0', '198.51.100.77', '18080', '0' ],
			[ m.Status, m.ErrorCode, m.AssignedExternalIPAddress, m.AssignedExternalPort, m.AssignedExternalPortEndRange ],
			'InboundMapping: assigned values');

		let o = model[OUT].get({ instance: 1, config: peer, parent: server, root });
		assert.match([ 'Error_PCPErrorCodeReceived', '2', '0' ], [ o.Status, o.ErrorCode, o.Lifetime ],
			'OutboundMapping: PCP error code');

		assert.match('Error', model[IN].get({ instance: 2, config: mapping, parent: server, root }).Status,
			'InboundMapping: no result yet');
	});

	// The lease of a Lifetime counts down and the row is deleted when it runs
	// out; a write of Lifetime starts it again.
	it('counts the Lifetime down and deletes the row when it runs out', () => {
		let env = handler_load();
		const model = env.model;

		let cfg = { Device: { PCP: { Enable: 'true', Client: { '3': {
			Enable: 'true',
			Server: { '1': { Enable: 'true', InboundMapping: {
				'1': { Enable: 'true', Lifetime: '600' },
				'2': { Enable: 'true', Lifetime: '1' },
				'3': { Enable: 'true', Lifetime: '0' },
				'4': { Enable: 'false', Lifetime: '5' }
			} } }
		} } } } };
		writefile('/etc/ubbf/config.json', sprintf('%J', cfg));
		for (let cb in env.hooks)
			cb();

		let lt = model[IN].get({ instance: 1, config: mapping, parent: server, root }).Lifetime;
		assert.match(true, +lt >= 599 && +lt <= 600, 'Lifetime: counts down from 600');

		uloop.init();
		uloop.timer(1500, () => uloop.end());
		uloop.run();
		assert.match([ { op: 'del', path: 'Device.PCP.Client.3.Server.1.InboundMapping.2' } ], env.applied,
			'Lifetime: expired row deleted');

		model[IN].set({ param: 'Lifetime', path: 'Device.PCP.Client.3.Server.1.InboundMapping.1.Lifetime', value: '600' });
		cfg.Device.PCP.Client['3'].Server['1'].InboundMapping['2'].Enable = 'false';
		writefile('/etc/ubbf/config.json', sprintf('%J', cfg));
		for (let cb in env.hooks)
			cb();
		lt = model[IN].get({ instance: 1, config: mapping, parent: server, root }).Lifetime;
		assert.match('600', lt, 'Lifetime: a write starts the lease again');
	});
});
