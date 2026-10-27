// Host test of the ieee8021x module: the resolution of Interface to a
// netdev, the checks of a Supplicant row and the wpa_supplicant file
// (shared.uc), and the get, set and command handlers (handler.uc) against a
// stand-in of wpa_supplicant.<netdev>. The netdev "lo" stands for a port.
// The certificate helpers scan /etc, and Stats.Reset() writes below
// /tmp/ubbf, so run it in a private mount namespace from the repository
// root:
//   unshare -rm sh -c 'mount -t tmpfs none /etc && mount -t tmpfs none /tmp/ubbf &&
//     exec ucode -L "$PWD/tests/ieee8021x/*.uc" -L "$PWD/tests/render/*.uc" \
//     -L "$PWD/tests/hosts/*.uc" -L "$PWD/files/usr/share/ucode" \
//     -L "<host build>/*.so" tests/ieee8021x.uc'
'use strict';

import * as fs from 'fs';
import * as ubbf from 'ubbf';
import { instance_numbers, instance_key, instance_rows, instance_prune } from 'ubbf';

// This process numbers rows, as the agent does.
ubbf.instance_map_own(true);

let pass = 0, fail = 0;

function check(name, got, expected) {
	if (sprintf('%J', got) == sprintf('%J', expected)) { pass++; return; }
	fail++;
	printf('FAIL %s\n  expected %J\n  got      %J\n', name, expected, got);
}

const certificates_stub = {
	certificate_path_resolve: (ref) => (ref == 'Device.Security.Certificate.1') ? '/etc/ubbf/dev.pem' : null,
	certificate_key_path: (path) => (path == '/etc/ubbf/dev.pem') ? '/etc/ubbf/dev.key' : null,
	cabundle_path_resolve: (ref) => (ref == 'Device.Security.CABundle.2') ? '/etc/ubbf/ca' : null
};

let ieee8021x = {};
include('../modules/ieee8021x/shared.uc', { ieee8021x, certificates: certificates_stub });

function root_build(rows) {
	return { Device: {
		Ethernet: {
			Interface: { '1': { Name: 'lo' } },
			Link: {
				'1': { Name: 'lo', LowerLayers: 'Device.Ethernet.Interface.1' },
				'2': { Name: 'ubbf-test0', LowerLayers: 'Device.Ethernet.Interface.1' },
				'3': { Name: 'ubbf-test0', LowerLayers: '' }
			}
		},
		Bridging: { Bridge: { '1': { Port: { '2': { Name: 'lanport1', LowerLayers: 'Device.Ethernet.Link.1' } } } } },
		IP: { Interface: { '1': { Name: 'lo' } } },
		IEEE8021x: { Supplicant: rows ?? {} }
	} };
}

let root = root_build();

check('Ethernet.Link resolves to its netdev', ieee8021x.netdev_resolve(root, 'Device.Ethernet.Link.1'), 'lo');
check('a trailing dot is allowed', ieee8021x.netdev_resolve(root, 'Device.Ethernet.Link.1.'), 'lo');
check('a bridge port resolves through LowerLayers', ieee8021x.netdev_resolve(root, 'Device.Bridging.Bridge.1.Port.2'), 'lo');
check('a missing netdev falls back to LowerLayers', ieee8021x.netdev_resolve(root, 'Device.Ethernet.Link.2'), 'lo');
check('a missing netdev without LowerLayers', ieee8021x.netdev_resolve(root, 'Device.Ethernet.Link.3'), null);
check('an IP interface is not a port', ieee8021x.netdev_resolve(root, 'Device.IP.Interface.1'), null);
check('a missing row', ieee8021x.netdev_resolve(root, 'Device.Ethernet.Link.9'), null);

const MD5_ROW = {
	Enable: 'true',
	Interface: 'Device.Ethernet.Link.1',
	EAPIdentity: 'user"1',
	EAPMD5: { Enable: 'true', SharedSecret: 'pa ss\n' }
};

check('plan of an MD5 row', ieee8021x.supplicant_plan(root, MD5_ROW),
	{ netdev: 'lo', identity: 'user"1', methods: [ 'MD5' ], password: 'pa ss\n' });
check('no netdev', ieee8021x.supplicant_plan(root, { ...MD5_ROW, Interface: 'Device.IP.Interface.1' }),
	{ error: 'Interface Device.IP.Interface.1 has no netdev' });
check('no identity', ieee8021x.supplicant_plan(root, { ...MD5_ROW, EAPIdentity: '' }), { error: 'EAPIdentity is empty' });
check('no MD5 secret', ieee8021x.supplicant_plan(root, { ...MD5_ROW, EAPMD5: { Enable: 'true' } }),
	{ error: 'EAPMD5.SharedSecret is empty' });
check('no method', ieee8021x.supplicant_plan(root, { ...MD5_ROW, EAPMD5: { Enable: 'false' } }),
	{ error: 'neither EAPMD5 nor EAPTLS is enabled' });

const TLS_ROW = {
	Enable: 'true',
	Interface: 'Device.Ethernet.Link.1',
	EAPIdentity: 'device',
	EAPTLS: { Enable: 'true', Certificate: 'Device.Security.Certificate.1', MutualAuthenticationEnable: 'true', CABundle: 'Device.Security.CABundle.2' }
};

check('plan of a TLS row', ieee8021x.supplicant_plan(root, TLS_ROW),
	{ netdev: 'lo', identity: 'device', methods: [ 'TLS' ], cert: '/etc/ubbf/dev.pem', key: '/etc/ubbf/dev.key', cabundle: 2 });
check('TLS without a certificate', ieee8021x.supplicant_plan(root, { ...TLS_ROW, EAPTLS: { ...TLS_ROW.EAPTLS, Certificate: '' } }),
	{ error: 'EAPTLS.Certificate  is not a certificate with a key' });
check('mutual authentication without CAs', ieee8021x.supplicant_plan(root, { ...TLS_ROW, EAPTLS: { ...TLS_ROW.EAPTLS, CABundle: 'Device.Security.CABundle.7' } }),
	{ error: 'EAPTLS.CABundle Device.Security.CABundle.7 is not a CA bundle with certificates' });
check('TLS without mutual authentication needs no CAs', ieee8021x.supplicant_plan(root, { ...TLS_ROW, EAPTLS: { ...TLS_ROW.EAPTLS, MutualAuthenticationEnable: 'false', CABundle: '' } })?.cabundle,
	null);

check('MD5 file: hex identity and password', ieee8021x.supplicant_config(ieee8021x.supplicant_plan(root, MD5_ROW), {}),
	'ctrl_interface=/var/run/wpa_supplicant\nap_scan=0\nnetwork={\n\tkey_mgmt=IEEE8021X\n\teapol_flags=0\n\teap=MD5\n' +
	'\tidentity=757365722231\n\tpassword=70612073730a\n}\n');
check('TLS file: the copies of the certificates', ieee8021x.supplicant_config(ieee8021x.supplicant_plan(root, TLS_ROW),
	{ cert: '/run/x/lo.crt', key: '/run/x/lo.key', ca: '/run/x/lo-ca.pem' }),
	'ctrl_interface=/var/run/wpa_supplicant\nap_scan=0\nnetwork={\n\tkey_mgmt=IEEE8021X\n\teapol_flags=0\n\teap=TLS\n' +
	'\tidentity=646576696365\n\tclient_cert="/run/x/lo.crt"\n\tprivate_key="/run/x/lo.key"\n\tca_cert="/run/x/lo-ca.pem"\n}\n');

check('timer defaults', ieee8021x.timer_commands({}),
	[ 'SET EAPOL::heldPeriod 60', 'SET EAPOL::authPeriod 30', 'SET EAPOL::startPeriod 30', 'SET EAPOL::maxStart 3' ]);
check('timers of a row', ieee8021x.timer_commands({ HeldPeriod: '5', AuthPeriod: '0', StartPeriod: '2', MaxStart: '10' }),
	[ 'SET EAPOL::heldPeriod 5', 'SET EAPOL::authPeriod 0', 'SET EAPOL::startPeriod 2', 'SET EAPOL::maxStart 10' ]);

const AUTHENTICATOR_ROW = {
	enable: 'true',
	interface: 'Device.Bridging.Bridge.1.Port.2',
	auth_server_addr: '192.0.2.1',
	auth_server_shared_secret: 'radius'
};

check('plan of an authenticator', ieee8021x.authenticator_plan(root, AUTHENTICATOR_ROW), {
	netdev: 'lo', auth_server_addr: '192.0.2.1', auth_server_shared_secret: 'radius', acct_server_addr: '',
	acct_server_shared_secret: '', nas_identifier: '', auth_server_port: 1812, acct_server_port: 1813, eap_reauth_period: 3600
});
check('an authenticator without a port', ieee8021x.authenticator_plan(root, { ...AUTHENTICATOR_ROW, interface: '' }),
	{ error: 'interface  has no netdev' });
check('a RADIUS server name', ieee8021x.authenticator_plan(root, { ...AUTHENTICATOR_ROW, auth_server_addr: 'radius.lan' }),
	{ error: 'auth_server_addr radius.lan is not an IP address' });
check('no RADIUS secret', ieee8021x.authenticator_plan(root, { ...AUTHENTICATOR_ROW, auth_server_shared_secret: '' }),
	{ error: 'auth_server_shared_secret is empty' });
check('accounting without a secret', ieee8021x.authenticator_plan(root, { ...AUTHENTICATOR_ROW, acct_server_addr: '2001:db8::1' }),
	{ error: 'acct_server_shared_secret is empty' });
check('a line break in a value', ieee8021x.authenticator_plan(root, { ...AUTHENTICATOR_ROW, nas_identifier: 'a\nauth_server_addr=x' }),
	{ error: 'nas_identifier holds a line break' });
check('hostapd file with accounting', ieee8021x.authenticator_config(ieee8021x.authenticator_plan(root, {
	...AUTHENTICATOR_ROW, acct_server_addr: '2001:db8::1', acct_server_port: '1913', acct_server_shared_secret: 'acct',
	eap_reauth_period: '0'
})),
	'driver=wired\ninterface=lo\nctrl_interface=/var/run/hostapd\nieee8021x=1\neapol_version=2\nuse_pae_group_addr=1\n' +
	'eap_reauth_period=0\ndynamic_own_ip_addr=1\nauth_server_addr=192.0.2.1\nauth_server_port=1812\n' +
	'auth_server_shared_secret=radius\nacct_server_addr=2001:db8::1\nacct_server_port=1913\nacct_server_shared_secret=acct\n');

// handler.uc

let schemas = {};
include('../modules/ieee8021x/schema.uc', { schemas });

const api = {
	ubbf: proto({ cache_call: (fn, ...args) => fn(...args), cache_invalidate: () => null }, ubbf),
	utils: {},
	schema: (key) => key,
	schema_defaults: (key) => schemas[key]?.defaults,
	model: {},
	operations: {}
};

include('../modules/ieee8021x/handler.uc', { ubbf_module: api });

const model = api.model;
const ops = api.operations;

const EAPOL = {
	wpa_state: 'COMPLETED',
	pae_state: 'AUTHENTICATED',
	port_status: 'Authorized',
	eap_state: 'SUCCESS',
	mib: {
		dot1xSuppEapolFramesRx: '7',
		dot1xSuppEapolFramesTx: '9',
		dot1xSuppEapolStartFramesTx: '2',
		dot1xSuppEapolLogoffFramesTx: '1',
		dot1xSuppEapolRespFramesTx: '6',
		dot1xSuppEapolReqIdFramesRx: '2',
		dot1xSuppEapolReqFramesRx: '3',
		dot1xSuppInvalidEapolFramesRx: '0',
		dot1xSuppEapLengthErrorFramesRx: '0',
		dot1xSuppLastEapolFrameVersion: '2',
		dot1xSuppLastEapolFrameSource: '02:aa:bb:cc:dd:ee'
	},
	success_count: 2,
	failure_count: 1
};

root = root_build({ '1': MD5_ROW, '2': { Enable: 'false' } });

function row_get(instance) {
	return model['Device.IEEE8021x.Supplicant.{i}'].get({ instance, config: root.Device.IEEE8021x.Supplicant[instance], root });
}

check('number of rows', model['Device.IEEE8021x'].get({ config: root.Device.IEEE8021x }),
	{ SupplicantNumberOfEntries: '2', X_UBBF_AuthenticatorNumberOfEntries: '0' });

let got = row_get(2);
check('a disabled row', [ got.Status, got.PAEState, got.MaxStart, got.AuthenticationCapabilities ], [ 'Disabled', 'Disconnected', '3', '' ]);

global.EAPOL = {};
got = row_get(1);
check('an enabled row without a supplicant', [ got.Status, got.PAEState ], [ 'Error', 'Disconnected' ]);

global.EAPOL = { lo: { ...EAPOL } };
got = row_get(1);
check('a running supplicant', [ got.Status, got.PAEState, got.AuthenticationCapabilities, got.EAPIdentity ],
	[ 'Enabled', 'Authenticated', 'EAP-MD5,EAP-TLS', 'user"1' ]);

root.Device.IEEE8021x.Supplicant['3'] = { ...MD5_ROW, EAPIdentity: '' };
got = row_get(3);
check('a misconfigured row', [ got.Status, got.PAEState ], [ 'Error_Misconfigured', 'Disconnected' ]);
delete root.Device.IEEE8021x.Supplicant['3'];

function stats_get() {
	return model['Device.IEEE8021x.Supplicant.{i}.Stats'].get({ instances: [ 1 ], parent: root.Device.IEEE8021x.Supplicant['1'], root });
}

check('Stats of a running supplicant', stats_get(), {
	ReceivedFrames: '7', TransmittedFrames: '9', TransmittedStartFrames: '2', TransmittedLogoffFrames: '1',
	TransmittedResponseIdFrames: '0', TransmittedResponseFrames: '6', ReceivedRequestIdFrames: '2',
	ReceivedRequestFrames: '3', ReceivedInvalidFrames: '0', ReceivedLengthErrorFrames: '0',
	LastFrameVersion: '2', LastFrameSourceMACAddress: '02:AA:BB:CC:DD:EE', SuccessCount: '2', FailureCount: '1'
});

check('Stats.Reset()', ops['Device.IEEE8021x.Supplicant.{i}.Stats.Reset()'].handler({}, '', [ 1 ], root), {});
global.EAPOL.lo.mib.dot1xSuppEapolFramesRx = '10';
global.EAPOL.lo.mib.dot1xSuppEapolFramesTx = '3';
got = stats_get();
check('Stats after Stats.Reset()', [ got.ReceivedFrames, got.TransmittedFrames, got.TransmittedStartFrames, got.SuccessCount, got.FailureCount ],
	[ '3', '3', '0', '0', '0' ]);

global.CONTROL = [];
check('Reset()', ops['Device.IEEE8021x.Supplicant.{i}.Reset()'].handler({}, '', [ 1 ], root), {});
check('Disconnect()', ops['Device.IEEE8021x.Supplicant.{i}.Disconnect()'].handler({}, '', [ 1 ], root), {});
check('the commands of Reset() and Disconnect()', global.CONTROL, [ 'LOGOFF', 'LOGON', 'LOGOFF' ]);
check('Disconnect() of a disabled row', ops['Device.IEEE8021x.Supplicant.{i}.Disconnect()'].handler({}, '', [ 2 ], root), null);

const supplicant_set = model['Device.IEEE8021x.Supplicant.{i}'].set;

function interface_set(instance, value) {
	return supplicant_set({ param: 'Interface', value, instance, root });
}

check('an empty Interface', interface_set(2, ''), 0);
check('a free port', interface_set(2, 'Device.Bridging.Bridge.1.Port.2'), 0);
check('a port of another row', interface_set(2, 'Device.Ethernet.Link.1.'), -USP_ERR_UNIQUE_KEY_CONFLICT);
check('the port of the same row', interface_set(1, 'Device.Ethernet.Link.1'), 0);
check('an IP interface', interface_set(2, 'Device.IP.Interface.1'), -USP_ERR_INVALID_VALUE);
check('a missing row', interface_set(2, 'Device.Ethernet.Link.9'), -USP_ERR_INVALID_VALUE);

const eaptls_set = model['Device.IEEE8021x.Supplicant.{i}.EAPTLS'].set;
check('no Certificate', eaptls_set({ param: 'Certificate', value: '', root }), 0);
check('an unknown Certificate', eaptls_set({ param: 'Certificate', value: 'Device.Security.Certificate.5', root }), -USP_ERR_INVALID_VALUE);
check('an unknown CABundle', eaptls_set({ param: 'CABundle', value: 'Device.Security.CABundle.5', root }), -USP_ERR_INVALID_VALUE);

// X_UBBF_Authenticator

root.Device.IEEE8021x.X_UBBF_Authenticator = { '1': AUTHENTICATOR_ROW, '2': { enable: 'false' } };

check('number of rows of both tables', model['Device.IEEE8021x'].get({ config: root.Device.IEEE8021x }),
	{ SupplicantNumberOfEntries: '2', X_UBBF_AuthenticatorNumberOfEntries: '2' });

function authenticator_get(instance) {
	return model['Device.IEEE8021x.X_UBBF_Authenticator.{i}'].get({ instance,
		config: root.Device.IEEE8021x.X_UBBF_Authenticator[instance], root });
}

function clients_get(instance) {
	return model['Device.IEEE8021x.X_UBBF_Authenticator.{i}.client.{i}'].get({ instance, instances: [ 1 ],
		parent: root.Device.IEEE8021x.X_UBBF_Authenticator['1'], root });
}

got = authenticator_get(2);
check('a disabled authenticator', [ got.status, got.auth_server_port, got.client_number_of_entries ], [ 'Disabled', '1812', '0' ]);

global.HOSTAPD = {};
got = authenticator_get(1);
check('an authenticator without hostapd', [ got.status, got.client_number_of_entries ], [ 'Error', '0' ]);

global.HOSTAPD = { lo: { '02:00:00:00:00:0a': { authorized: true }, '02:00:00:00:00:0b': { authorized: false } } };
got = authenticator_get(1);
check('a running authenticator', [ got.status, got.client_number_of_entries ], [ 'Enabled', '2' ]);
check('the stations of the port', clients_get(null), {
	'1': { mac_address: '02:00:00:00:00:0A', authorized: 'true' },
	'2': { mac_address: '02:00:00:00:00:0B', authorized: 'false' }
});

global.HOSTAPD.lo = { '02:00:00:00:00:0b': { authorized: true } };
check('a station keeps its number', clients_get(null), { '2': { mac_address: '02:00:00:00:00:0B', authorized: 'true' } });
check('one station', clients_get(2), { mac_address: '02:00:00:00:00:0B', authorized: 'true' });
check('a station that left', clients_get(1), null);

root.Device.IEEE8021x.X_UBBF_Authenticator['3'] = { ...AUTHENTICATOR_ROW, auth_server_shared_secret: '' };
check('a misconfigured authenticator', authenticator_get(3).status, 'Error_Misconfigured');
delete root.Device.IEEE8021x.X_UBBF_Authenticator['3'];

const authenticator_set = model['Device.IEEE8021x.X_UBBF_Authenticator.{i}'].set;

function param_set(param, value) {
	return authenticator_set({ param, value, instance: 2, root });
}

check('the port of a supplicant', param_set('interface', 'Device.Ethernet.Link.1'), -USP_ERR_UNIQUE_KEY_CONFLICT);
check('the port of another authenticator', param_set('interface', 'Device.Bridging.Bridge.1.Port.2'), -USP_ERR_UNIQUE_KEY_CONFLICT);
check('a supplicant on the port of an authenticator', interface_set(2, 'Device.Bridging.Bridge.1.Port.2'), -USP_ERR_UNIQUE_KEY_CONFLICT);
check('a free port for an authenticator', param_set('interface', 'Device.Ethernet.Interface.1'), 0);
check('an IPv6 RADIUS server', param_set('auth_server_addr', '2001:db8::1'), 0);
check('a RADIUS server name', param_set('auth_server_addr', 'radius.lan'), -USP_ERR_INVALID_VALUE);
check('a secret with a line break', param_set('auth_server_shared_secret', 'a\nb'), -USP_ERR_INVALID_VALUE);
check('a secret', param_set('auth_server_shared_secret', 'a b'), 0);

printf('passed: %d\nfailed: %d\n', pass, fail);
exit(fail ? 1 : 0);
