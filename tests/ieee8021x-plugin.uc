// Host test of the ubbf-device plugin of the ieee8021x module: it starts a
// wired wpa_supplicant interface for a Supplicant row, adds it again only
// when its file changes, sets the EAPOL timers, stops it, starts it again
// after a restart of wpad, renews the connection for RenewConnection and
// logs off for FailAuthentication; it runs hostapd for an authenticator and
// opens its port for authorised stations. The netdev "lo" stands for a
// port, and wpad and netifd come from a ubus mock.
'use strict';

import { describe, it, assert, mock, beforeEach } from 'utest';
import { state_clear } from 'test_env';
import * as fs from 'fs';
import * as uloop from 'uloop';
import * as plugin from '../modules/ieee8021x/files/usr/share/ucode/ubbf/device/plugins/ieee8021x.uc';

const RUN_DIR = '/var/run/ubbf-ieee8021x';
const STATS_BASELINE = '/tmp/ubbf/ieee8021x-stats.json';

/**
 * Answers a call to the wpad daemon objects.
 *
 * @param {object} wpas - Mock state from ubus_set()
 * @param {string} object - Object name
 * @param {string} method - Method name
 * @param {object} data - Arguments
 * @returns {*} The answer, or null
 */
function wpad_call(wpas, object, method, data) {
	let sets = { wpa_supplicant: wpas.present, hostapd: wpas.hostapd };

	if (sets[object] && method == 'config_add') {
		sets[object][data.iface] = true;
		return { pid: 1 };
	}
	if (sets[object] && method == 'config_remove') {
		delete sets[object][data.iface];
		return null;
	}

	let m = match(object, /^(wpa_supplicant|hostapd)\.(.+)$/);
	if (!m)
		return null;
	if (!sets[m[1]][m[2]]) {
		wpas.last_error = 'Not found';
		return null;
	}

	if (method == 'eapol_status')
		return wpas.eapol ?? { pae_state: 'CONNECTING' };
	if (method == 'control')
		return { result: 'OK\n' };
	if (method == 'get_status')
		return { driver: 'wired', status: 'ENABLED' };
	return null;
}

// Keeps the wpa_supplicant and hostapd interfaces in present and hostapd,
// records each call in calls, answers eapol_status from eapol and the
// netifd dump from ifaces, and keeps the listeners, and the subscribers
// with their objects.
function ubus_set() {
	let wpas = { present: {}, hostapd: {}, calls: [], eapol: null, ifaces: [], listeners: {}, subscribers: [] };

	mock.global.patch('ubus', { behavior: {
		call: (object, method, data) => {
			push(wpas.calls, [ object, method, data ]);
			wpas.last_error = null;

			if (object == 'network.interface' && method == 'dump')
				return { interface: wpas.ifaces };

			return wpad_call(wpas, object, method, data);
		},
		error: () => wpas.last_error,
		listener: (pattern, cb) => {
			wpas.listeners[pattern] = cb;
			return {};
		},
		subscriber: (cb, remove_cb, patterns) => {
			let entry = { cb, objects: [ ...(patterns ?? []) ] };
			push(wpas.subscribers, entry);
			return { subscribe: (object) => push(entry.objects, object) };
		}
	} });
	return wpas;
}

function wait(ms) {
	uloop.timer(ms, () => uloop.end());
	uloop.run();
}

function calls_take(wpas) {
	let calls = filter(wpas.calls, (c) => c[1] != 'eapol_status');
	wpas.calls = [];
	return calls;
}

function config_write(row, authenticator) {
	fs.writefile('/etc/ubbf/config.json', sprintf('%J', { Device: {
		Ethernet: { Link: { '1': { Name: 'lo' } } },
		IEEE8021x: {
			Supplicant: { '1': row },
			X_UBBF_Authenticator: authenticator ? { '1': authenticator } : {}
		}
	} }));
}

function digest(wpas) {
	wpas.listeners['bbf-dm.digest']('bbf-dm.digest', {});
	wait(400);
}

/**
 * Sends a notification of an object to the subscribers that follow it. As
 * on the device, the request does not name the object.
 *
 * @param {object} wpas - Mock state from ubus_set()
 * @param {string} path - Object name
 * @param {string} type - Notification type
 * @param {object} data - Notification data
 */
function notify(wpas, path, type, data) {
	for (let entry in wpas.subscribers)
		if (length(filter(entry.objects, (o) => wildcard(path, o))))
			entry.cb({ type, info: { object: { id: 1 } }, data });
}

function subscribed(wpas, path) {
	return length(filter(wpas.subscribers, (e) => index(e.objects, path) >= 0)) > 0;
}

const SETS = [
	[ 'wpa_supplicant.lo', 'control', { command: 'SET EAPOL::heldPeriod 60' } ],
	[ 'wpa_supplicant.lo', 'control', { command: 'SET EAPOL::authPeriod 30' } ],
	[ 'wpa_supplicant.lo', 'control', { command: 'SET EAPOL::startPeriod 30' } ],
	[ 'wpa_supplicant.lo', 'control', { command: 'SET EAPOL::maxStart 3' } ]
];
const ADD = [ 'wpa_supplicant', 'config_add', { driver: 'wired', iface: 'lo', config: `${RUN_DIR}/lo.conf` } ];
const REMOVE = [ 'wpa_supplicant', 'config_remove', { iface: 'lo' } ];
const OPEN = [ 'network.device', 'set_state', { name: 'lo', auth_status: true } ];

describe('ieee8021x device plugin', () => {
	beforeEach(() => state_clear());

	it('runs wpa_supplicant for a Supplicant row and hostapd for an authenticator', () => {
		let wpas = ubus_set();
		let row = {
			Enable: 'true',
			Interface: 'Device.Ethernet.Link.1',
			EAPIdentity: 'user',
			EAPMD5: { Enable: 'true', SharedSecret: 'secret' }
		};

		fs.writefile('/etc/passwd', 'root:x:0:0:root:/root:/bin/sh\nnetwork:x:101:101:network:/var:/bin/false\n');
		config_write(row);
		fs.mkdir(RUN_DIR, 0700);
		fs.writefile(`${RUN_DIR}/old0.conf`, '');

		plugin.init();
		plugin.subscribe();
		wait(400);

		assert.match([ [ 'wpa_supplicant.old0', 'control', { command: 'LOGOFF' } ],
			  [ 'wpa_supplicant', 'config_remove', { iface: 'old0' } ], ADD, ...SETS ], calls_take(wpas),
			'start: the file of an earlier run is removed, the row starts');
		assert.match('ctrl_interface=/var/run/wpa_supplicant\nap_scan=0\nnetwork={\n\tkey_mgmt=IEEE8021X\n\teapol_flags=0\n\teap=MD5\n' +
			'\tidentity=75736572\n\tpassword=736563726574\n}\n', fs.readfile(`${RUN_DIR}/lo.conf`), 'the file of the row');
		assert.match([ 0600, 0700 ], [ fs.stat(`${RUN_DIR}/lo.conf`).mode & 0777, fs.stat(RUN_DIR).mode & 0777 ],
			'only the owner reads the file and the directory');
		assert.match(false, !!fs.access(`${RUN_DIR}/old0.conf`), 'no file is left of the earlier run');

		digest(wpas);
		assert.match(SETS, calls_take(wpas), 'an unchanged row only sets the timers');

		row.MaxStart = '5';
		config_write(row);
		digest(wpas);
		assert.match([ 'wpa_supplicant.lo', 'control', { command: 'SET EAPOL::maxStart 5' } ], calls_take(wpas)[3],
			'a timer is a runtime setting');
		delete row.MaxStart;

		row.EAPMD5.SharedSecret = 'other';
		config_write(row);
		fs.writefile(STATS_BASELINE, '{"1":{"TransmittedLogoffFrames":4},"2":{"TransmittedLogoffFrames":7}}');
		digest(wpas);
		assert.match([ REMOVE, ADD, ...SETS ], calls_take(wpas), 'a changed file adds the interface again');
		assert.match({ '2': { TransmittedLogoffFrames: 7 } }, json(fs.readfile(STATS_BASELINE)),
			'and drops the Stats baseline of its row only');

		wpas.present = {};
		wpas.listeners['ubus.object.add']('ubus.object.add', { path: 'wpa_supplicant' });
		wait(400);
		assert.match([ ADD, ...SETS ], calls_take(wpas), 'a restarted wpad gets the interface again');

		row.AuthenticationSuccessPolicy = 'RenewConnection';
		config_write(row);
		digest(wpas);
		calls_take(wpas);
		wpas.ifaces = [
			{ interface: 'wan', up: true, l3_device: 'lo', device: 'lo' },
			{ interface: 'wan6', up: false, l3_device: 'lo', device: 'lo' },
			{ interface: 'lan', up: true, l3_device: 'br-lan', device: 'br-lan' }
		];
		notify(wpas, 'wpa_supplicant.lo', 'ctrl-event',
			{ ifname: 'lo', event: 'CTRL-EVENT-EAP-SUCCESS EAP authentication completed successfully' });
		assert.match([ [ 'network.interface', 'dump', {} ], [ 'network.interface.wan', 'renew', {} ] ], calls_take(wpas),
			'RenewConnection renews the interfaces that are up on the port');
		notify(wpas, 'wpa_supplicant.lo', 'ctrl-event', { ifname: 'lo', event: 'CTRL-EVENT-EAP-FAILURE EAP authentication failed' });
		assert.match([], calls_take(wpas), 'a failure renews nothing');

		row.AuthenticationSuccessPolicy = 'NoAction';
		row.StartFailurePolicy = 'FailAuthentication';
		row.MaxStart = '1';
		row.StartPeriod = '1';
		row.HeldPeriod = '1';
		config_write(row);
		wpas.eapol = { pae_state: 'AUTHENTICATED', eap_state: 'IDLE' };
		digest(wpas);
		calls_take(wpas);
		wait(2200);
		assert.match([ [ 'wpa_supplicant.lo', 'control', { command: 'LOGOFF' } ] ], calls_take(wpas),
			'FailAuthentication logs off a port that no authenticator answers');
		wait(1200);
		assert.match([ [ 'wpa_supplicant.lo', 'control', { command: 'LOGON' } ] ], calls_take(wpas), 'and logs on after HeldPeriod');

		wpas.eapol = { pae_state: 'AUTHENTICATED', eap_state: 'SUCCESS' };
		wait(2200);
		assert.match([], calls_take(wpas), 'an authenticated port stays logged on');

		row.Enable = 'false';
		config_write(row);
		digest(wpas);
		assert.match([ [ 'wpa_supplicant.lo', 'control', { command: 'LOGOFF' } ], REMOVE ], calls_take(wpas),
			'a disabled row logs off and stops the interface');
		assert.match(false, !!fs.access(`${RUN_DIR}/lo.conf`), 'and removes its file');

		// X_UBBF_Authenticator

		let authenticator = {
			enable: 'true',
			interface: 'Device.Ethernet.Link.1',
			auth_server_addr: '192.0.2.1',
			auth_server_shared_secret: 'radius',
			nas_identifier: 'ubbf'
		};

		config_write(row, authenticator);
		digest(wpas);
		assert.match([
			[ 'hostapd.lo', 'get_status', {} ],
			[ 'hostapd', 'config_add', { iface: 'lo', config: `${RUN_DIR}/lo.hostapd` } ],
			[ 'network.device', 'set_state', { name: 'lo', auth_status: false } ]
		], calls_take(wpas), 'an authenticator starts closed');
		assert.match(true, subscribed(wpas, 'hostapd.lo'), 'the plugin follows the port');
		assert.match('driver=wired\ninterface=lo\nctrl_interface=/var/run/hostapd\nieee8021x=1\neapol_version=2\nuse_pae_group_addr=1\n' +
			'eap_reauth_period=3600\ndynamic_own_ip_addr=1\nauth_server_addr=192.0.2.1\nauth_server_port=1812\n' +
			'auth_server_shared_secret=radius\nnas_identifier=ubbf\n', fs.readfile(`${RUN_DIR}/lo.hostapd`),
			'the file of the authenticator');

		digest(wpas);
		assert.match([ [ 'hostapd.lo', 'get_status', {} ] ], calls_take(wpas), 'an unchanged authenticator stays as it is');

		notify(wpas, 'hostapd.lo', 'sta-authorized', { address: '02:00:00:00:00:01', ifname: 'lo' });
		assert.match([ OPEN ], calls_take(wpas), 'an authorised station opens the port');
		notify(wpas, 'hostapd.lo', 'sta-authorized', { address: '02:00:00:00:00:02', ifname: 'lo' });
		notify(wpas, 'hostapd.lo', 'disassoc', { address: '02:00:00:00:00:01', ifname: 'lo' });
		assert.match([], calls_take(wpas), 'the port stays open while a station is authorised');
		notify(wpas, 'hostapd.lo', 'deauth', { address: '02:00:00:00:00:02', ifname: 'lo' });
		assert.match([ [ 'network.device', 'set_state', { name: 'lo', auth_status: false } ] ], calls_take(wpas),
			'the last station closes the port');
		notify(wpas, 'hostapd.wlan0', 'sta-authorized', { address: '02:00:00:00:00:03', ifname: 'wlan0' });
		assert.match([], calls_take(wpas), 'a WiFi BSS is not a port');
		assert.match(false, subscribed(wpas, 'hostapd.wlan0'), 'and has no subscriber of the plugin');

		notify(wpas, 'hostapd.lo', 'sta-authorized', { address: '02:00:00:00:00:01', ifname: 'lo' });
		calls_take(wpas);
		notify(wpas, 'network.device', 'link_down', { name: 'lo' });
		assert.match([ [ 'hostapd.lo', 'del_clients', {} ] ], calls_take(wpas), 'a link loss makes hostapd forget the stations');
		notify(wpas, 'hostapd.lo', 'sta-authorized', { address: '02:00:00:00:00:01', ifname: 'lo' });
		assert.match([ OPEN ], calls_take(wpas), 'and the next station opens the port again');

		row = { ...row, Enable: 'true', StartFailurePolicy: 'AssumeAuthentication' };
		for (let timer in [ 'MaxStart', 'StartPeriod', 'HeldPeriod' ])
			delete row[timer];
		config_write(row, authenticator);
		digest(wpas);
		assert.match([
			OPEN,
			[ 'hostapd', 'config_remove', { iface: 'lo' } ],
			ADD, ...SETS
		], calls_take(wpas), 'a supplicant and an authenticator cannot share a port');

		row.Enable = 'false';
		authenticator.auth_server_shared_secret = 'other';
		config_write(row, authenticator);
		digest(wpas);
		calls_take(wpas);
		authenticator.enable = 'false';
		config_write(row, authenticator);
		digest(wpas);
		assert.match([ OPEN, [ 'hostapd', 'config_remove', { iface: 'lo' } ] ], calls_take(wpas),
			'a disabled authenticator opens its port and stops');
		assert.match(false, !!fs.access(`${RUN_DIR}/lo.hostapd`), 'and removes its file');
	});
});
