// Host test of the pcp module handler. The handler reads fixed paths, so
// run it from the repository root in a private mount namespace with the
// native module built for the host. The logging helper imports udebug, so
// the search path needs that module or a stand-in for it:
//   unshare -rm sh -c 'mount -t tmpfs tmpfs /etc/ubbf &&
//     mkdir -p /tmp/ubbf && mount -t tmpfs tmpfs /tmp/ubbf &&
//     ucode -L "$PWD/files/usr/share/ucode" -L "<host build>/*.so" \
//     -L "<ucode modules>/*.so" tests/pcp.uc'
'use strict';

import * as ubbf from 'ubbf';
import * as uloop from 'uloop';
import { writefile } from 'fs';

let pass_count = 0;
let fail_count = 0;

function assert_eq(name, got, expected) {
	let got_json = sprintf('%J', got);
	let exp_json = sprintf('%J', expected);

	if (got_json == exp_json) {
		pass_count++;
		return;
	}

	fail_count++;
	printf('FAIL: %s\n  expected: %s\n  got:      %s\n', name, exp_json, got_json);
}

let hooks = [];
let applied = [];

const api = {
	ubbf: proto({ cache_call: (fn, ...args) => fn(...args) }, ubbf),
	utils: {},
	schema: (k) => k,
	on_commit: (cb) => push(hooks, cb),
	on_abort: () => null,
	config_apply: (ops, done) => {
		push(applied, ...ops);
		return { success: true };
	},
	model: {}
};

include('../modules/pcp/handler.uc', { ubbf_module: api });

const model = api.model;
const IN = 'Device.PCP.Client.{i}.Server.{i}.InboundMapping.{i}';
const OUT = 'Device.PCP.Client.{i}.Server.{i}.OutboundMapping.{i}';

let mapping = { Enable: 'true', Lifetime: '600', InternalPort: '8080', ProtocolNumber: '6' };
let peer = { Enable: 'true', Lifetime: '0', InternalPort: '5070', ProtocolNumber: '17' };
let server = { Enable: 'true', ServerNameOrAddress: '192.0.2.1', InboundMapping: { '1': mapping }, OutboundMapping: { '1': peer } };
let server_off = { Enable: 'false', ServerNameOrAddress: '192.0.2.2' };
let client = { Enable: 'true', THIRDPARTYEnable: 'true', Server: { '1': server, '2': server_off } };
let root = {
	Device: {
		IP: { Interface: { '1': { Name: 'wan' }, '2': { Name: 'lan' } } },
		PCP: { Enable: 'true', Client: { '3': client } }
	}
};

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

let p = model['Device.PCP'].get({ config: { Enable: 'true', Client: { '3': client } } });
assert_eq('PCP: lists', [ p.SupportedVersions, p.OptionList, p.ClientNumberOfEntries ], [ '0,1,2', '1,3', '1' ]);

let c = model['Device.PCP.Client.{i}'].get({ instance: 3, config: client, root });
assert_eq('Client: status, third party, WAN interface',
	[ c.Status, c.THIRDPARTYStatus, c.WANInterface, c.ServerNumberOfEntries ],
	[ 'Enabled', 'Enabled', 'Device.IP.Interface.1', '2' ]);

let off_root = { Device: { PCP: { Enable: 'false', Client: { '3': client } } } };
assert_eq('Client: stack disabled',
	model['Device.PCP.Client.{i}'].get({ instance: 3, config: client, root: off_root }).Status, 'StackDisabled');
assert_eq('Client: disabled',
	model['Device.PCP.Client.{i}'].get({ instance: 3, config: { Enable: 'false' }, root }).Status, 'Disabled');

let s = model['Device.PCP.Client.{i}.Server.{i}'].get({ instance: 1, config: server, parent: client, root });
assert_eq('Server: daemon result',
	[ s.Status, s.ServerAddressInUse, s.AdditionalServerAddresses, s.ExternalIPAddress, s.CurrentVersion ],
	[ 'Enabled', '192.0.2.1', '192.0.2.9', '198.51.100.77', '2' ]);
assert_eq('Server: disabled row',
	model['Device.PCP.Client.{i}.Server.{i}'].get({ instance: 2, config: server_off, parent: client, root }).Status,
	'Disabled');

let m = model[IN].get({ instance: 1, config: mapping, parent: server, root });
assert_eq('InboundMapping: assigned values',
	[ m.Status, m.ErrorCode, m.AssignedExternalIPAddress, m.AssignedExternalPort, m.AssignedExternalPortEndRange ],
	[ 'Enabled', '0', '198.51.100.77', '18080', '0' ]);

let o = model[OUT].get({ instance: 1, config: peer, parent: server, root });
assert_eq('OutboundMapping: PCP error code', [ o.Status, o.ErrorCode, o.Lifetime ],
	[ 'Error_PCPErrorCodeReceived', '2', '0' ]);

assert_eq('InboundMapping: no result yet',
	model[IN].get({ instance: 2, config: mapping, parent: server, root }).Status, 'Error');

// The lease of a Lifetime counts down and the row is deleted when it runs
// out; a write of Lifetime starts it again.
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
for (let cb in hooks)
	cb();

let lt = model[IN].get({ instance: 1, config: mapping, parent: server, root }).Lifetime;
assert_eq('Lifetime: counts down from 600', +lt >= 599 && +lt <= 600, true);

uloop.init();
uloop.timer(1500, () => uloop.end());
uloop.run();
assert_eq('Lifetime: expired row deleted',
	applied, [ { op: 'del', path: 'Device.PCP.Client.3.Server.1.InboundMapping.2' } ]);

model[IN].set({ param: 'Lifetime', path: 'Device.PCP.Client.3.Server.1.InboundMapping.1.Lifetime', value: '600' });
cfg.Device.PCP.Client['3'].Server['1'].InboundMapping['2'].Enable = 'false';
writefile('/etc/ubbf/config.json', sprintf('%J', cfg));
for (let cb in hooks)
	cb();
lt = model[IN].get({ instance: 1, config: mapping, parent: server, root }).Lifetime;
assert_eq('Lifetime: a write starts the lease again', lt, '600');

printf('\n--- pcp handler test results ---\n  passed: %d\n  failed: %d\n', pass_count, fail_count);
exit(fail_count ? 1 : 0);
