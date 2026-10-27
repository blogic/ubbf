// Host test of the ddns module handler: Status and LastError from the files
// of ddns-scripts, the provider address of a named service, and the value
// checks of the set handlers. The handler reads fixed paths, so run it in a
// private mount namespace from the repository root:
//   unshare -rm sh -c 'mount -t tmpfs none /run && mount -t tmpfs none /var/log &&
//     mount -t tmpfs none /usr/share && ucode -L "$PWD/tests/hosts/*.uc" \
//     -L "$PWD/files/usr/share/ucode/*.uc" -L "<host build>/*.so" tests/ddns.uc'
'use strict';

import * as ubbf from 'ubbf';
import { mkdir, writefile, unlink } from 'fs';

let pass = 0, fail = 0;

function check(name, got, expected) {
	if (sprintf('%J', got) == sprintf('%J', expected)) { pass++; return; }
	fail++;
	printf('FAIL %s\n  expected %J\n  got      %J\n', name, expected, got);
}

for (let d in [ '/run/ddns', '/var/log/ddns', '/usr/share/ddns', '/usr/share/ddns/default' ])
	mkdir(d);

writefile('/usr/share/ddns/default/dyndns.org.json',
	'{ "name": "dyndns.org", "ipv4": { "url": "http://[USERNAME]:[PASSWORD]@members.dyndns.org/v3/update?hostname=[DOMAIN]" } }');

const api = {
	ubbf: proto({ upstream_interface_ref: () => 'Device.IP.Interface.1' }, ubbf),
	utils: {
		'dm-version': { dm_visible: () => true }
	},
	schema: (k) => k,
	model: {}
};

include('../modules/ddns/handler.uc', { ubbf_module: api });

const m = api.model;
const client_m = m['Device.DynamicDNS.Client.{i}'];
const host_m = m['Device.DynamicDNS.Client.{i}.Hostname.{i}'];
const server_m = m['Device.DynamicDNS.Server.{i}'];

let client = { Enable: 'true', Server: 'Device.DynamicDNS.Server.1', IPVersion: '4',
	Hostname: { '1': { Enable: 'true', Name: 'home.example.net' } } };
let root = { Device: {
	IP: { Interface: { '1': { Name: 'wan', IPv4Enable: 'true', IPv6Enable: 'false' } } },
	DynamicDNS: {
		Server: { '1': { Enable: 'true', ServiceName: 'dyndns.org' } },
		Client: { '1': client }
	}
} };

function status() {
	let row = client_m.get({ instance: 1, config: client, root });
	return [ row.Status, row.LastError ];
}

function log(lines) {
	writefile('/var/log/ddns/ddns_1_1.log', join('\n', lines) + '\n');
}

check('no log, no updater: Error', status(), [ 'Error', 'MISCONFIGURATION_ERROR' ]);

log([ ' 101010  info : Starting main loop', ' 101011  info : Update successful - IP \'1.2.3.4\' send' ]);
writefile('/run/ddns/ddns_1_1.update', '100\n');
check('update successful: Updated', status(), [ 'Updated', 'NO_ERROR' ]);

log([ ' 101011  info : Update successful', ' 101020 ERROR : IP update not accepted by DDNS Provider' ]);
writefile('/run/ddns/ddns_1_1.dat', 'badauth\n');
check('badauth: AUTHENTICATION_ERROR', status(), [ 'Error', 'AUTHENTICATION_ERROR' ]);

writefile('/run/ddns/ddns_1_1.dat', 'nohost\n');
check('other answer: PROTOCOL_ERROR', status(), [ 'Error', 'PROTOCOL_ERROR' ]);

log([ ' 101020 ERROR : No or private or invalid IP \'172.16.100.2\' given! Please check your configuration' ]);
check('private address: MISCONFIGURATION_ERROR', status(), [ 'Error', 'MISCONFIGURATION_ERROR' ]);

log([ ' 101020 ERROR : cURL Error: \'28\'', ' 101021  WARN : Transfer failed - retry 1/1 in 60 seconds' ]);
check('curl timeout then retry: CONNECTION_ERROR from the newest line', status(), [ 'Error', 'CONNECTION_ERROR' ]);

log([ ' 101020 ERROR : cURL Error: \'28\'' ]);
check('curl timeout: TIMEOUT_ERROR', status(), [ 'Error', 'TIMEOUT_ERROR' ]);

root.Device.DynamicDNS.Server['1'].Enable = 'false';
check('disabled server: Error_Misconfigured', status(), [ 'Error_Misconfigured', 'MISCONFIGURATION_ERROR' ]);
root.Device.DynamicDNS.Server['1'].Enable = 'true';

client.IPVersion = '6';
check('IPv6 without an address: Error_Misconfigured', status(), [ 'Error_Misconfigured', 'MISCONFIGURATION_ERROR' ]);
client.IPVersion = '4';

client.Enable = 'false';
check('disabled client', status(), [ 'Disabled', 'NO_ERROR' ]);
client.Enable = 'true';

log([ ' 101011  info : Update successful' ]);
let host = host_m.get({ instance: '1', config: client.Hostname['1'], parent: client, root });
check('hostname Registered', host.Status, 'Registered');
check('hostname LastUpdate is a time', match(host.LastUpdate, /^20[0-9]{2}-/) != null, true);

let server = server_m.get({ instance: 1, config: root.Device.DynamicDNS.Server['1'], root });
check('named service reports its host', [ server.ServerAddress, server.ServerPort, server.Protocol, server.SupportedProtocols ],
	[ 'members.dyndns.org', '443', 'HTTPS', 'HTTP,HTTPS' ]);

let generic = server_m.get({ instance: 2, config: { ServiceName: 'dyndns2', ServerAddress: 'ddns.example.net', ServerPort: '8443', Protocol: 'HTTP' }, root });
check('generic service keeps its values', [ generic.ServerAddress, generic.ServerPort, generic.Protocol ], [ 'ddns.example.net', '8443', 'HTTP' ]);

check('supported services', m['Device.DynamicDNS'].get({ config: {} }).SupportedServices, 'dyndns.org,dyndns2');

const set = (model_entry, param, value) => model_entry.set({ param, value, instance: 1, config: {} });
check('ServiceName from the list', set(server_m, 'ServiceName', 'dyndns2'), 0);
check('ServiceName outside the list', set(server_m, 'ServiceName', '../x'), -USP_ERR_INVALID_VALUE);
check('ServerAddress host name', set(server_m, 'ServerAddress', 'ddns.example.net'), 0);
check('ServerAddress IPv6', set(server_m, 'ServerAddress', '2001:db8::1'), 0);
check('ServerAddress with a quote', set(server_m, 'ServerAddress', "x'y"), -USP_ERR_INVALID_VALUE);
check('ServerAddress as a URL', set(server_m, 'ServerAddress', 'http://x/'), -USP_ERR_INVALID_VALUE);
check('Server reference', set(client_m, 'Server', 'Device.DynamicDNS.Server.3'), 0);
check('Server reference to another table', set(client_m, 'Server', 'Device.IP.Interface.1'), -USP_ERR_INVALID_VALUE);
check('Interface reference to another table', set(client_m, 'Interface', 'Device.DynamicDNS.Server.1'), -USP_ERR_INVALID_VALUE);
check('Hostname wildcard', set(host_m, 'Name', '*.home.example.net'), 0);
check('Hostname with a space', set(host_m, 'Name', 'bad name'), -USP_ERR_INVALID_VALUE);

printf('passed: %d\nfailed: %d\n', pass, fail);
exit(fail ? 1 : 0);
