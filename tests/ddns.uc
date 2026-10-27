// Host test of the ddns module handler: Status and LastError from the files
// of ddns-scripts, the provider address of a named service, and the value
// checks of the set handlers. /usr/share is not writable in the test
// namespace, so the handler reads the provider files of ddns-scripts from
// SHARE_DIR through an fs stand-in.
'use strict';

import { describe, it, assert, beforeEach } from 'utest';
import * as ubbf from 'ubbf';

const fs = require('fs');

const SHARE_DIR = '/tmp/ubbf-ddns-share';
const DIRS = [ '/run/ddns', '/var/log/ddns', SHARE_DIR, SHARE_DIR + '/default' ];

function share_path(path) {
	return replace(path, /^\/usr\/share\/ddns\//, SHARE_DIR + '/');
}

const fs_share = proto({
	glob: (pattern) => fs.glob(share_path(pattern)),
	readfile: (path, ...rest) => fs.readfile(share_path(path), ...rest)
}, fs);

function require_share(name) {
	return (name == 'fs') ? fs_share : require(name);
}

const api = {
	ubbf: proto({ upstream_interface_ref: () => 'Device.IP.Interface.1' }, ubbf),
	utils: {
		'dm-version': { dm_visible: () => true }
	},
	schema: (k) => k,
	model: {}
};

include('../modules/ddns/handler.uc', { ubbf_module: api, require: require_share });

const m = api.model;
const client_m = m['Device.DynamicDNS.Client.{i}'];
const host_m = m['Device.DynamicDNS.Client.{i}.Hostname.{i}'];
const server_m = m['Device.DynamicDNS.Server.{i}'];

function dirs_reset() {
	for (let d in reverse([ ...DIRS ])) {
		for (let name in fs.lsdir(d) ?? [])
			fs.unlink(`${d}/${name}`);
		fs.rmdir(d);
	}
	for (let d in DIRS)
		fs.mkdir(d);

	fs.writefile(SHARE_DIR + '/default/dyndns.org.json',
		'{ "name": "dyndns.org", "ipv4": { "url": "http://[USERNAME]:[PASSWORD]@members.dyndns.org/v3/update?hostname=[DOMAIN]" } }');
}

function client_new() {
	return { Enable: 'true', Server: 'Device.DynamicDNS.Server.1', IPVersion: '4',
		Hostname: { '1': { Enable: 'true', Name: 'home.example.net' } } };
}

function root_new(client) {
	return { Device: {
		IP: { Interface: { '1': { Name: 'wan', IPv4Enable: 'true', IPv6Enable: 'false' } } },
		DynamicDNS: {
			Server: { '1': { Enable: 'true', ServiceName: 'dyndns.org' } },
			Client: { '1': client }
		}
	} };
}

function status(client, root) {
	let row = client_m.get({ instance: 1, config: client, root });
	return [ row.Status, row.LastError ];
}

function updater_files(lines, answer) {
	fs.writefile('/var/log/ddns/ddns_1_1.log', join('\n', lines) + '\n');
	fs.writefile('/run/ddns/ddns_1_1.update', '100\n');
	if (answer)
		fs.writefile('/run/ddns/ddns_1_1.dat', answer + '\n');
}

const CURL_TIMEOUT = [ ' 101020 ERROR : cURL Error: \'28\'' ];

beforeEach(() => dirs_reset());

describe('DynamicDNS Client Status and LastError', () => {
	it('is Error without a log and an updater', () => {
		let client = client_new();
		assert.match([ 'Error', 'MISCONFIGURATION_ERROR' ], status(client, root_new(client)));
	});

	it('is Updated after a successful update', () => {
		let client = client_new();
		updater_files([ ' 101010  info : Starting main loop', ' 101011  info : Update successful - IP \'1.2.3.4\' send' ]);
		assert.match([ 'Updated', 'NO_ERROR' ], status(client, root_new(client)));
	});

	it('tells the error of a rejected update from the answer of the provider', () => {
		let client = client_new();
		let root = root_new(client);
		let rejected = [ ' 101011  info : Update successful', ' 101020 ERROR : IP update not accepted by DDNS Provider' ];

		updater_files(rejected, 'badauth');
		assert.match([ 'Error', 'AUTHENTICATION_ERROR' ], status(client, root));

		updater_files(rejected, 'nohost');
		assert.match([ 'Error', 'PROTOCOL_ERROR' ], status(client, root));
	});

	it('is MISCONFIGURATION_ERROR for a private address', () => {
		let client = client_new();
		updater_files([ ' 101020 ERROR : No or private or invalid IP \'172.16.100.2\' given! Please check your configuration' ], 'nohost');
		assert.match([ 'Error', 'MISCONFIGURATION_ERROR' ], status(client, root_new(client)));
	});

	it('takes the newest log line for a curl timeout', () => {
		let client = client_new();
		let root = root_new(client);

		updater_files([ ...CURL_TIMEOUT, ' 101021  WARN : Transfer failed - retry 1/1 in 60 seconds' ], 'nohost');
		assert.match([ 'Error', 'CONNECTION_ERROR' ], status(client, root), 'retry after a curl timeout');

		updater_files(CURL_TIMEOUT, 'nohost');
		assert.match([ 'Error', 'TIMEOUT_ERROR' ], status(client, root));
	});

	it('is Error_Misconfigured for a disabled server and for IPv6 without an address', () => {
		let client = client_new();
		let root = root_new(client);
		updater_files(CURL_TIMEOUT, 'nohost');

		root.Device.DynamicDNS.Server['1'].Enable = 'false';
		assert.match([ 'Error_Misconfigured', 'MISCONFIGURATION_ERROR' ], status(client, root));
		root.Device.DynamicDNS.Server['1'].Enable = 'true';

		client.IPVersion = '6';
		assert.match([ 'Error_Misconfigured', 'MISCONFIGURATION_ERROR' ], status(client, root));
	});

	it('is Disabled for a disabled client', () => {
		let client = client_new();
		updater_files(CURL_TIMEOUT, 'nohost');
		client.Enable = 'false';
		assert.match([ 'Disabled', 'NO_ERROR' ], status(client, root_new(client)));
	});
});

describe('DynamicDNS Client Hostname', () => {
	it('is Registered with a LastUpdate after a successful update', () => {
		let client = client_new();
		updater_files([ ' 101011  info : Update successful' ], 'nohost');
		let host = host_m.get({ instance: '1', config: client.Hostname['1'], parent: client, root: root_new(client) });
		assert.match('Registered', host.Status);
		assert.match(true, match(host.LastUpdate, /^20[0-9]{2}-/) != null);
	});
});

describe('DynamicDNS Server', () => {
	it('reports the host of a named service', () => {
		let root = root_new(client_new());
		let server = server_m.get({ instance: 1, config: root.Device.DynamicDNS.Server['1'], root });
		assert.match([ 'members.dyndns.org', '443', 'HTTPS', 'HTTP,HTTPS' ],
			[ server.ServerAddress, server.ServerPort, server.Protocol, server.SupportedProtocols ]);
	});

	it('keeps the values of the generic service', () => {
		let generic = server_m.get({ instance: 2, config: { ServiceName: 'dyndns2', ServerAddress: 'ddns.example.net', ServerPort: '8443', Protocol: 'HTTP' }, root: root_new(client_new()) });
		assert.match([ 'ddns.example.net', '8443', 'HTTP' ], [ generic.ServerAddress, generic.ServerPort, generic.Protocol ]);
	});

	it('lists the supported services', () => {
		assert.match('dyndns.org,dyndns2', m['Device.DynamicDNS'].get({ config: {} }).SupportedServices);
	});
});

describe('DynamicDNS value checks', () => {
	const set = (model_entry, param, value) => model_entry.set({ param, value, instance: 1, config: {} });

	it('takes a ServiceName from the list only', () => {
		assert.match(0, set(server_m, 'ServiceName', 'dyndns2'));
		assert.match(-USP_ERR_INVALID_VALUE, set(server_m, 'ServiceName', '../x'));
	});

	it('takes a host name or an address as ServerAddress', () => {
		assert.match(0, set(server_m, 'ServerAddress', 'ddns.example.net'));
		assert.match(0, set(server_m, 'ServerAddress', '2001:db8::1'));
		assert.match(-USP_ERR_INVALID_VALUE, set(server_m, 'ServerAddress', "x'y"));
		assert.match(-USP_ERR_INVALID_VALUE, set(server_m, 'ServerAddress', 'http://x/'));
	});

	it('takes references to the right table only', () => {
		assert.match(0, set(client_m, 'Server', 'Device.DynamicDNS.Server.3'));
		assert.match(-USP_ERR_INVALID_VALUE, set(client_m, 'Server', 'Device.IP.Interface.1'));
		assert.match(-USP_ERR_INVALID_VALUE, set(client_m, 'Interface', 'Device.DynamicDNS.Server.1'));
	});

	it('takes a wildcard host name and no space', () => {
		assert.match(0, set(host_m, 'Name', '*.home.example.net'));
		assert.match(-USP_ERR_INVALID_VALUE, set(host_m, 'Name', 'bad name'));
	});
});
