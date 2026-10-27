// Host test of the ieee8021x module: the resolution of Interface to a
// netdev, the checks of a Supplicant row and the wpa_supplicant file
// (shared.uc), and the get, set and command handlers (handler.uc) against a
// ubus mock of wpa_supplicant.<netdev> and hostapd.<netdev>. The netdev "lo"
// stands for a port.
'use strict';

import { describe, it, assert, mock, beforeEach } from 'utest';
import { state_clear } from 'test_env';
import * as ubbf from 'ubbf';

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

const MD5_ROW = {
	Enable: 'true',
	Interface: 'Device.Ethernet.Link.1',
	EAPIdentity: 'user"1',
	EAPMD5: { Enable: 'true', SharedSecret: 'pa ss\n' }
};

const TLS_ROW = {
	Enable: 'true',
	Interface: 'Device.Ethernet.Link.1',
	EAPIdentity: 'device',
	EAPTLS: { Enable: 'true', Certificate: 'Device.Security.Certificate.1', MutualAuthenticationEnable: 'true', CABundle: 'Device.Security.CABundle.2' }
};

const AUTHENTICATOR_ROW = {
	enable: 'true',
	interface: 'Device.Bridging.Bridge.1.Port.2',
	auth_server_addr: '192.0.2.1',
	auth_server_shared_secret: 'radius'
};

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

// A copy that a test can change: the module resets the counters of the
// reply in place, as wpa_supplicant does.
function eapol_new() {
	return json(sprintf('%J', EAPOL));
}

// Answers the methods of wpa_supplicant.<netdev> from env.eapol
// (eapol_status reply keyed by netdev) and records the control commands in
// env.control; answers the methods of hostapd.<netdev> from env.hostapd
// (station flags keyed by netdev, then by MAC address).
function ubus_set(env) {
	mock.global.patch('ubus', { behavior: { call: (object, method, args) => {
		let h = match(object, /^hostapd\.(.+)$/);
		let clients = h ? env.hostapd?.[h[1]] : null;
		if (clients && method == 'get_status')
			return { driver: 'wired', status: 'ENABLED', iface: h[1] };
		if (clients && method == 'get_clients')
			return { clients };
		if (h)
			return null;

		let m = match(object, /^wpa_supplicant\.(.+)$/);
		let eapol = m ? env.eapol?.[m[1]] : null;
		if (!eapol)
			return null;

		if (method == 'eapol_status')
			return eapol;
		if (method == 'eapol_reset') {
			eapol.success_count = 0;
			eapol.failure_count = 0;
			return null;
		}
		if (method != 'control')
			return null;

		push(env.control, args.command);
		if (args.command == 'GET_CAPABILITY eap')
			return { result: 'MD5 TLS PEAP MSCHAPV2' };
		return { result: 'OK\n' };
	} } });
}

// The handler requires ubus when it loads, so it loads after the mock.
function handler_load() {
	let env = { eapol: null, hostapd: null, control: [] };
	let schemas = {};

	ubus_set(env);
	include('../modules/ieee8021x/schema.uc', { schemas });

	let api = {
		ubbf: proto({ cache_call: (fn, ...args) => fn(...args), cache_invalidate: () => null }, ubbf),
		utils: {},
		schema: (key) => key,
		schema_defaults: (key) => schemas[key]?.defaults,
		model: {},
		operations: {}
	};

	include('../modules/ieee8021x/handler.uc', { ubbf_module: api });
	env.model = api.model;
	env.ops = api.operations;
	return env;
}

describe('ieee8021x shared.uc', () => {
	const root = root_build();

	it('resolves Interface to a netdev', () => {
		assert.match('lo', ieee8021x.netdev_resolve(root, 'Device.Ethernet.Link.1'), 'Ethernet.Link resolves to its netdev');
		assert.match('lo', ieee8021x.netdev_resolve(root, 'Device.Ethernet.Link.1.'), 'a trailing dot is allowed');
		assert.match('lo', ieee8021x.netdev_resolve(root, 'Device.Bridging.Bridge.1.Port.2'), 'a bridge port resolves through LowerLayers');
		assert.match('lo', ieee8021x.netdev_resolve(root, 'Device.Ethernet.Link.2'), 'a missing netdev falls back to LowerLayers');
		assert.match(null, ieee8021x.netdev_resolve(root, 'Device.Ethernet.Link.3'), 'a missing netdev without LowerLayers');
		assert.match(null, ieee8021x.netdev_resolve(root, 'Device.IP.Interface.1'), 'an IP interface is not a port');
		assert.match(null, ieee8021x.netdev_resolve(root, 'Device.Ethernet.Link.9'), 'a missing row');
	});

	it('checks an EAP-MD5 Supplicant row', () => {
		assert.match({ netdev: 'lo', identity: 'user"1', methods: [ 'MD5' ], password: 'pa ss\n' },
			ieee8021x.supplicant_plan(root, MD5_ROW), 'plan of an MD5 row');
		assert.match({ error: 'Interface Device.IP.Interface.1 has no netdev' },
			ieee8021x.supplicant_plan(root, { ...MD5_ROW, Interface: 'Device.IP.Interface.1' }), 'no netdev');
		assert.match({ error: 'EAPIdentity is empty' }, ieee8021x.supplicant_plan(root, { ...MD5_ROW, EAPIdentity: '' }), 'no identity');
		assert.match({ error: 'EAPMD5.SharedSecret is empty' },
			ieee8021x.supplicant_plan(root, { ...MD5_ROW, EAPMD5: { Enable: 'true' } }), 'no MD5 secret');
		assert.match({ error: 'neither EAPMD5 nor EAPTLS is enabled' },
			ieee8021x.supplicant_plan(root, { ...MD5_ROW, EAPMD5: { Enable: 'false' } }), 'no method');
	});

	it('checks an EAP-TLS Supplicant row', () => {
		assert.match({ netdev: 'lo', identity: 'device', methods: [ 'TLS' ], cert: '/etc/ubbf/dev.pem', key: '/etc/ubbf/dev.key', cabundle: 2 },
			ieee8021x.supplicant_plan(root, TLS_ROW), 'plan of a TLS row');
		assert.match({ error: 'EAPTLS.Certificate  is not a certificate with a key' },
			ieee8021x.supplicant_plan(root, { ...TLS_ROW, EAPTLS: { ...TLS_ROW.EAPTLS, Certificate: '' } }),
			'TLS without a certificate');
		assert.match({ error: 'EAPTLS.CABundle Device.Security.CABundle.7 is not a CA bundle with certificates' },
			ieee8021x.supplicant_plan(root, { ...TLS_ROW, EAPTLS: { ...TLS_ROW.EAPTLS, CABundle: 'Device.Security.CABundle.7' } }),
			'mutual authentication without CAs');
		assert.match(null,
			ieee8021x.supplicant_plan(root, { ...TLS_ROW, EAPTLS: { ...TLS_ROW.EAPTLS, MutualAuthenticationEnable: 'false', CABundle: '' } })?.cabundle,
			'TLS without mutual authentication needs no CAs');
	});

	it('writes the wpa_supplicant file', () => {
		assert.match('ctrl_interface=/var/run/wpa_supplicant\nap_scan=0\nnetwork={\n\tkey_mgmt=IEEE8021X\n\teapol_flags=0\n\teap=MD5\n' +
			'\tidentity=757365722231\n\tpassword=70612073730a\n}\n',
			ieee8021x.supplicant_config(ieee8021x.supplicant_plan(root, MD5_ROW), {}), 'MD5 file: hex identity and password');
		assert.match('ctrl_interface=/var/run/wpa_supplicant\nap_scan=0\nnetwork={\n\tkey_mgmt=IEEE8021X\n\teapol_flags=0\n\teap=TLS\n' +
			'\tidentity=646576696365\n\tclient_cert="/run/x/lo.crt"\n\tprivate_key="/run/x/lo.key"\n\tca_cert="/run/x/lo-ca.pem"\n}\n',
			ieee8021x.supplicant_config(ieee8021x.supplicant_plan(root, TLS_ROW),
				{ cert: '/run/x/lo.crt', key: '/run/x/lo.key', ca: '/run/x/lo-ca.pem' }),
			'TLS file: the copies of the certificates');
	});

	it('gives the EAPOL timer commands', () => {
		assert.match([ 'SET EAPOL::heldPeriod 60', 'SET EAPOL::authPeriod 30', 'SET EAPOL::startPeriod 30', 'SET EAPOL::maxStart 3' ],
			ieee8021x.timer_commands({}), 'timer defaults');
		assert.match([ 'SET EAPOL::heldPeriod 5', 'SET EAPOL::authPeriod 0', 'SET EAPOL::startPeriod 2', 'SET EAPOL::maxStart 10' ],
			ieee8021x.timer_commands({ HeldPeriod: '5', AuthPeriod: '0', StartPeriod: '2', MaxStart: '10' }), 'timers of a row');
	});

	it('checks an authenticator row and writes the hostapd file', () => {
		assert.match({
			netdev: 'lo', auth_server_addr: '192.0.2.1', auth_server_shared_secret: 'radius', acct_server_addr: '',
			acct_server_shared_secret: '', nas_identifier: '', auth_server_port: 1812, acct_server_port: 1813, eap_reauth_period: 3600
		}, ieee8021x.authenticator_plan(root, AUTHENTICATOR_ROW), 'plan of an authenticator');
		assert.match({ error: 'interface  has no netdev' },
			ieee8021x.authenticator_plan(root, { ...AUTHENTICATOR_ROW, interface: '' }), 'an authenticator without a port');
		assert.match({ error: 'auth_server_addr radius.lan is not an IP address' },
			ieee8021x.authenticator_plan(root, { ...AUTHENTICATOR_ROW, auth_server_addr: 'radius.lan' }), 'a RADIUS server name');
		assert.match({ error: 'auth_server_shared_secret is empty' },
			ieee8021x.authenticator_plan(root, { ...AUTHENTICATOR_ROW, auth_server_shared_secret: '' }), 'no RADIUS secret');
		assert.match({ error: 'acct_server_shared_secret is empty' },
			ieee8021x.authenticator_plan(root, { ...AUTHENTICATOR_ROW, acct_server_addr: '2001:db8::1' }), 'accounting without a secret');
		assert.match({ error: 'nas_identifier holds a line break' },
			ieee8021x.authenticator_plan(root, { ...AUTHENTICATOR_ROW, nas_identifier: 'a\nauth_server_addr=x' }),
			'a line break in a value');
		assert.match('driver=wired\ninterface=lo\nctrl_interface=/var/run/hostapd\nieee8021x=1\neapol_version=2\nuse_pae_group_addr=1\n' +
			'eap_reauth_period=0\ndynamic_own_ip_addr=1\nauth_server_addr=192.0.2.1\nauth_server_port=1812\n' +
			'auth_server_shared_secret=radius\nacct_server_addr=2001:db8::1\nacct_server_port=1913\nacct_server_shared_secret=acct\n',
			ieee8021x.authenticator_config(ieee8021x.authenticator_plan(root, {
				...AUTHENTICATOR_ROW, acct_server_addr: '2001:db8::1', acct_server_port: '1913', acct_server_shared_secret: 'acct',
				eap_reauth_period: '0'
			})), 'hostapd file with accounting');
	});
});

describe('ieee8021x handler.uc', () => {
	beforeEach(() => {
		state_clear();
		ubbf.instance_map_own(true);
	});

	function row_get(env, root, instance) {
		return env.model['Device.IEEE8021x.Supplicant.{i}'].get({ instance, config: root.Device.IEEE8021x.Supplicant[instance], root });
	}

	it('reads the Status and PAEState of the Supplicant rows', () => {
		let env = handler_load();
		let root = root_build({ '1': MD5_ROW, '2': { Enable: 'false' } });

		assert.match({ SupplicantNumberOfEntries: '2', X_UBBF_AuthenticatorNumberOfEntries: '0' },
			env.model['Device.IEEE8021x'].get({ config: root.Device.IEEE8021x }), 'number of rows');

		let got = row_get(env, root, 2);
		assert.match([ 'Disabled', 'Disconnected', '3', '' ], [ got.Status, got.PAEState, got.MaxStart, got.AuthenticationCapabilities ],
			'a disabled row');

		env.eapol = {};
		got = row_get(env, root, 1);
		assert.match([ 'Error', 'Disconnected' ], [ got.Status, got.PAEState ], 'an enabled row without a supplicant');

		env.eapol = { lo: eapol_new() };
		got = row_get(env, root, 1);
		assert.match([ 'Enabled', 'Authenticated', 'EAP-MD5,EAP-TLS', 'user"1' ],
			[ got.Status, got.PAEState, got.AuthenticationCapabilities, got.EAPIdentity ], 'a running supplicant');

		root.Device.IEEE8021x.Supplicant['3'] = { ...MD5_ROW, EAPIdentity: '' };
		got = row_get(env, root, 3);
		assert.match([ 'Error_Misconfigured', 'Disconnected' ], [ got.Status, got.PAEState ], 'a misconfigured row');
	});

	it('reads the Stats and resets them with Stats.Reset()', () => {
		let env = handler_load();
		let root = root_build({ '1': MD5_ROW, '2': { Enable: 'false' } });

		function stats_get() {
			return env.model['Device.IEEE8021x.Supplicant.{i}.Stats'].get({ instances: [ 1 ], parent: root.Device.IEEE8021x.Supplicant['1'], root });
		}

		env.eapol = { lo: eapol_new() };
		assert.match({
			ReceivedFrames: '7', TransmittedFrames: '9', TransmittedStartFrames: '2', TransmittedLogoffFrames: '1',
			TransmittedResponseIdFrames: '0', TransmittedResponseFrames: '6', ReceivedRequestIdFrames: '2',
			ReceivedRequestFrames: '3', ReceivedInvalidFrames: '0', ReceivedLengthErrorFrames: '0',
			LastFrameVersion: '2', LastFrameSourceMACAddress: '02:AA:BB:CC:DD:EE', SuccessCount: '2', FailureCount: '1'
		}, stats_get(), 'Stats of a running supplicant');

		assert.match({}, env.ops['Device.IEEE8021x.Supplicant.{i}.Stats.Reset()'].handler({}, '', [ 1 ], root), 'Stats.Reset()');
		env.eapol.lo.mib.dot1xSuppEapolFramesRx = '10';
		env.eapol.lo.mib.dot1xSuppEapolFramesTx = '3';
		let got = stats_get();
		assert.match([ '3', '3', '0', '0', '0' ],
			[ got.ReceivedFrames, got.TransmittedFrames, got.TransmittedStartFrames, got.SuccessCount, got.FailureCount ],
			'Stats after Stats.Reset()');
	});

	it('sends LOGOFF and LOGON for Reset() and Disconnect()', () => {
		let env = handler_load();
		let root = root_build({ '1': MD5_ROW, '2': { Enable: 'false' } });

		env.eapol = { lo: eapol_new() };
		assert.match({}, env.ops['Device.IEEE8021x.Supplicant.{i}.Reset()'].handler({}, '', [ 1 ], root), 'Reset()');
		assert.match({}, env.ops['Device.IEEE8021x.Supplicant.{i}.Disconnect()'].handler({}, '', [ 1 ], root), 'Disconnect()');
		assert.match([ 'LOGOFF', 'LOGON', 'LOGOFF' ], env.control, 'the commands of Reset() and Disconnect()');
		assert.match(null, env.ops['Device.IEEE8021x.Supplicant.{i}.Disconnect()'].handler({}, '', [ 2 ], root),
			'Disconnect() of a disabled row');
	});

	it('accepts a free port as the Interface of a Supplicant', () => {
		let env = handler_load();
		let root = root_build({ '1': MD5_ROW, '2': { Enable: 'false' } });
		const supplicant_set = env.model['Device.IEEE8021x.Supplicant.{i}'].set;
		let interface_set = (instance, value) => supplicant_set({ param: 'Interface', value, instance, root });

		assert.match(0, interface_set(2, ''), 'an empty Interface');
		assert.match(0, interface_set(2, 'Device.Bridging.Bridge.1.Port.2'), 'a free port');
		assert.match(-USP_ERR_UNIQUE_KEY_CONFLICT, interface_set(2, 'Device.Ethernet.Link.1.'), 'a port of another row');
		assert.match(0, interface_set(1, 'Device.Ethernet.Link.1'), 'the port of the same row');
		assert.match(-USP_ERR_INVALID_VALUE, interface_set(2, 'Device.IP.Interface.1'), 'an IP interface');
		assert.match(-USP_ERR_INVALID_VALUE, interface_set(2, 'Device.Ethernet.Link.9'), 'a missing row');
	});

	it('accepts only known EAPTLS certificates', () => {
		let env = handler_load();
		let root = root_build({ '1': MD5_ROW, '2': { Enable: 'false' } });
		const eaptls_set = env.model['Device.IEEE8021x.Supplicant.{i}.EAPTLS'].set;

		assert.match(0, eaptls_set({ param: 'Certificate', value: '', root }), 'no Certificate');
		assert.match(-USP_ERR_INVALID_VALUE, eaptls_set({ param: 'Certificate', value: 'Device.Security.Certificate.5', root }),
			'an unknown Certificate');
		assert.match(-USP_ERR_INVALID_VALUE, eaptls_set({ param: 'CABundle', value: 'Device.Security.CABundle.5', root }),
			'an unknown CABundle');
	});

	it('reads the X_UBBF_Authenticator rows and numbers their stations', () => {
		let env = handler_load();
		let root = root_build({ '1': MD5_ROW, '2': { Enable: 'false' } });
		root.Device.IEEE8021x.X_UBBF_Authenticator = { '1': AUTHENTICATOR_ROW, '2': { enable: 'false' } };

		function authenticator_get(instance) {
			return env.model['Device.IEEE8021x.X_UBBF_Authenticator.{i}'].get({ instance,
				config: root.Device.IEEE8021x.X_UBBF_Authenticator[instance], root });
		}

		function clients_get(instance) {
			return env.model['Device.IEEE8021x.X_UBBF_Authenticator.{i}.client.{i}'].get({ instance, instances: [ 1 ],
				parent: root.Device.IEEE8021x.X_UBBF_Authenticator['1'], root });
		}

		assert.match({ SupplicantNumberOfEntries: '2', X_UBBF_AuthenticatorNumberOfEntries: '2' },
			env.model['Device.IEEE8021x'].get({ config: root.Device.IEEE8021x }), 'number of rows of both tables');

		let got = authenticator_get(2);
		assert.match([ 'Disabled', '1812', '0' ], [ got.status, got.auth_server_port, got.client_number_of_entries ],
			'a disabled authenticator');

		env.hostapd = {};
		got = authenticator_get(1);
		assert.match([ 'Error', '0' ], [ got.status, got.client_number_of_entries ], 'an authenticator without hostapd');

		env.hostapd = { lo: { '02:00:00:00:00:0a': { authorized: true }, '02:00:00:00:00:0b': { authorized: false } } };
		got = authenticator_get(1);
		assert.match([ 'Enabled', '2' ], [ got.status, got.client_number_of_entries ], 'a running authenticator');
		assert.match({
			'1': { mac_address: '02:00:00:00:00:0A', authorized: 'true' },
			'2': { mac_address: '02:00:00:00:00:0B', authorized: 'false' }
		}, clients_get(null), 'the stations of the port');

		env.hostapd.lo = { '02:00:00:00:00:0b': { authorized: true } };
		assert.match({ '2': { mac_address: '02:00:00:00:00:0B', authorized: 'true' } }, clients_get(null), 'a station keeps its number');
		assert.match({ mac_address: '02:00:00:00:00:0B', authorized: 'true' }, clients_get(2), 'one station');
		assert.match(null, clients_get(1), 'a station that left');

		root.Device.IEEE8021x.X_UBBF_Authenticator['3'] = { ...AUTHENTICATOR_ROW, auth_server_shared_secret: '' };
		assert.match('Error_Misconfigured', authenticator_get(3).status, 'a misconfigured authenticator');
	});

	it('keeps the ports of supplicants and authenticators apart', () => {
		let env = handler_load();
		let root = root_build({ '1': MD5_ROW, '2': { Enable: 'false' } });
		root.Device.IEEE8021x.X_UBBF_Authenticator = { '1': AUTHENTICATOR_ROW, '2': { enable: 'false' } };

		const authenticator_set = env.model['Device.IEEE8021x.X_UBBF_Authenticator.{i}'].set;
		const supplicant_set = env.model['Device.IEEE8021x.Supplicant.{i}'].set;
		let param_set = (param, value) => authenticator_set({ param, value, instance: 2, root });
		let interface_set = (instance, value) => supplicant_set({ param: 'Interface', value, instance, root });

		assert.match(-USP_ERR_UNIQUE_KEY_CONFLICT, param_set('interface', 'Device.Ethernet.Link.1'), 'the port of a supplicant');
		assert.match(-USP_ERR_UNIQUE_KEY_CONFLICT, param_set('interface', 'Device.Bridging.Bridge.1.Port.2'),
			'the port of another authenticator');
		assert.match(-USP_ERR_UNIQUE_KEY_CONFLICT, interface_set(2, 'Device.Bridging.Bridge.1.Port.2'),
			'a supplicant on the port of an authenticator');
		assert.match(0, param_set('interface', 'Device.Ethernet.Interface.1'), 'a free port for an authenticator');
		assert.match(0, param_set('auth_server_addr', '2001:db8::1'), 'an IPv6 RADIUS server');
		assert.match(-USP_ERR_INVALID_VALUE, param_set('auth_server_addr', 'radius.lan'), 'a RADIUS server name');
		assert.match(-USP_ERR_INVALID_VALUE, param_set('auth_server_shared_secret', 'a\nb'), 'a secret with a line break');
		assert.match(0, param_set('auth_server_shared_secret', 'a b'), 'a secret');
	});
});
