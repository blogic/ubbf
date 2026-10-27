// Host test of the ubbf-device plugin of the ieee8021x module: it starts a
// wired wpa_supplicant interface for a Supplicant row, adds it again only
// when its file changes, sets the EAPOL timers, stops it, starts it again
// after a restart of wpad, renews the connection for RenewConnection and
// logs off for FailAuthentication. The netdev "lo" stands for a port. Run
// from the repository root in a private mount namespace:
//   unshare -rm sh -e -c 'repo=$PWD; mount -t tmpfs none /etc; mount -t tmpfs none /run;
//     mkdir -p /tmp/ubbf; mount -t tmpfs none /tmp/ubbf;
//     mkdir -p /etc/ubbf; mount -t tmpfs none /usr/share; mkdir -p /usr/share/ucode/ubbf/modules;
//     ln -s "$repo/modules/ieee8021x" "$repo/modules/security" /usr/share/ucode/ubbf/modules/;
//     exec ucode -L "$repo/tests/ieee8021x-plugin/*.uc" -L "$repo/tests/render/*.uc" \
//       -L "$repo/tests/hosts/*.uc" -L "$repo/files/usr/share/ucode" \
//       -L "$repo/modules/ieee8021x/files/usr/share/ucode" -L "$1/*.so" \
//       "$repo/tests/ieee8021x-plugin.uc"' sh <host build>
'use strict';

import * as fs from 'fs';
import * as uloop from 'uloop';
import * as plugin from 'ubbf.device.plugins.ieee8021x';

const RUN_DIR = '/var/run/ubbf-ieee8021x';
const STATS_BASELINE = '/tmp/ubbf/ieee8021x-stats.json';

let pass = 0, fail = 0;

function check(name, got, expected) {
	if (sprintf('%J', got) == sprintf('%J', expected)) { pass++; return; }
	fail++;
	printf('FAIL %s\n  expected %J\n  got      %J\n', name, expected, got);
}

function wait(ms) {
	uloop.timer(ms, () => uloop.end());
	uloop.run();
}

function calls_take() {
	let calls = filter(global.WPAS?.calls ?? [], (c) => c[1] != 'eapol_status');
	if (global.WPAS)
		global.WPAS.calls = [];
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

function digest() {
	global.LISTENERS['bbf-dm.digest']('bbf-dm.digest', {});
	wait(400);
}

/**
 * Sends a notification of an object to the subscribers that follow it. As
 * on the device, the request does not name the object.
 *
 * @param {string} path - Object name
 * @param {string} type - Notification type
 * @param {object} data - Notification data
 */
function notify(path, type, data) {
	for (let entry in global.SUBSCRIBERS ?? [])
		if (length(filter(entry.objects, (o) => wildcard(path, o))))
			entry.cb({ type, info: { object: { id: 1 } }, data });
}

function subscribed(path) {
	return length(filter(global.SUBSCRIBERS ?? [], (e) => index(e.objects, path) >= 0)) > 0;
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

check('start: the file of an earlier run is removed, the row starts', calls_take(),
	[ [ 'wpa_supplicant.old0', 'control', { command: 'LOGOFF' } ],
	  [ 'wpa_supplicant', 'config_remove', { iface: 'old0' } ], ADD, ...SETS ]);
check('the file of the row', fs.readfile(`${RUN_DIR}/lo.conf`),
	'ctrl_interface=/var/run/wpa_supplicant\nap_scan=0\nnetwork={\n\tkey_mgmt=IEEE8021X\n\teapol_flags=0\n\teap=MD5\n' +
	'\tidentity=75736572\n\tpassword=736563726574\n}\n');
check('only the owner reads the file and the directory',
	[ fs.stat(`${RUN_DIR}/lo.conf`).mode & 0777, fs.stat(RUN_DIR).mode & 0777 ], [ 0600, 0700 ]);
check('no file is left of the earlier run', !!fs.access(`${RUN_DIR}/old0.conf`), false);

digest();
check('an unchanged row only sets the timers', calls_take(), SETS);

row.MaxStart = '5';
config_write(row);
digest();
check('a timer is a runtime setting', calls_take()[3], [ 'wpa_supplicant.lo', 'control', { command: 'SET EAPOL::maxStart 5' } ]);
delete row.MaxStart;

row.EAPMD5.SharedSecret = 'other';
config_write(row);
fs.writefile(STATS_BASELINE, '{"1":{"TransmittedLogoffFrames":4},"2":{"TransmittedLogoffFrames":7}}');
digest();
check('a changed file adds the interface again', calls_take(), [ REMOVE, ADD, ...SETS ]);
check('and drops the Stats baseline of its row only', json(fs.readfile(STATS_BASELINE)),
	{ '2': { TransmittedLogoffFrames: 7 } });

global.WPAS.present = {};
global.LISTENERS['ubus.object.add']('ubus.object.add', { path: 'wpa_supplicant' });
wait(400);
check('a restarted wpad gets the interface again', calls_take(), [ ADD, ...SETS ]);

row.AuthenticationSuccessPolicy = 'RenewConnection';
config_write(row);
digest();
calls_take();
global.IFACES = [
	{ interface: 'wan', up: true, l3_device: 'lo', device: 'lo' },
	{ interface: 'wan6', up: false, l3_device: 'lo', device: 'lo' },
	{ interface: 'lan', up: true, l3_device: 'br-lan', device: 'br-lan' }
];
notify('wpa_supplicant.lo', 'ctrl-event',
	{ ifname: 'lo', event: 'CTRL-EVENT-EAP-SUCCESS EAP authentication completed successfully' });
check('RenewConnection renews the interfaces that are up on the port', calls_take(),
	[ [ 'network.interface', 'dump', {} ], [ 'network.interface.wan', 'renew', {} ] ]);
notify('wpa_supplicant.lo', 'ctrl-event', { ifname: 'lo', event: 'CTRL-EVENT-EAP-FAILURE EAP authentication failed' });
check('a failure renews nothing', calls_take(), []);

row.AuthenticationSuccessPolicy = 'NoAction';
row.StartFailurePolicy = 'FailAuthentication';
row.MaxStart = '1';
row.StartPeriod = '1';
row.HeldPeriod = '1';
config_write(row);
global.EAPOL = { pae_state: 'AUTHENTICATED', eap_state: 'IDLE' };
digest();
calls_take();
wait(2200);
check('FailAuthentication logs off a port that no authenticator answers', calls_take(),
	[ [ 'wpa_supplicant.lo', 'control', { command: 'LOGOFF' } ] ]);
wait(1200);
check('and logs on after HeldPeriod', calls_take(),
	[ [ 'wpa_supplicant.lo', 'control', { command: 'LOGON' } ] ]);

global.EAPOL = { pae_state: 'AUTHENTICATED', eap_state: 'SUCCESS' };
wait(2200);
check('an authenticated port stays logged on', calls_take(), []);

row.Enable = 'false';
config_write(row);
digest();
check('a disabled row logs off and stops the interface', calls_take(),
	[ [ 'wpa_supplicant.lo', 'control', { command: 'LOGOFF' } ], REMOVE ]);
check('and removes its file', !!fs.access(`${RUN_DIR}/lo.conf`), false);

// X_UBBF_Authenticator

let authenticator = {
	enable: 'true',
	interface: 'Device.Ethernet.Link.1',
	auth_server_addr: '192.0.2.1',
	auth_server_shared_secret: 'radius',
	nas_identifier: 'ubbf'
};

config_write(row, authenticator);
digest();
check('an authenticator starts closed', calls_take(), [
	[ 'hostapd.lo', 'get_status', {} ],
	[ 'hostapd', 'config_add', { iface: 'lo', config: `${RUN_DIR}/lo.hostapd` } ],
	[ 'network.device', 'set_state', { name: 'lo', auth_status: false } ]
]);
check('the plugin follows the port', subscribed('hostapd.lo'), true);
check('the file of the authenticator', fs.readfile(`${RUN_DIR}/lo.hostapd`),
	'driver=wired\ninterface=lo\nctrl_interface=/var/run/hostapd\nieee8021x=1\neapol_version=2\nuse_pae_group_addr=1\n' +
	'eap_reauth_period=3600\ndynamic_own_ip_addr=1\nauth_server_addr=192.0.2.1\nauth_server_port=1812\n' +
	'auth_server_shared_secret=radius\nnas_identifier=ubbf\n');

digest();
check('an unchanged authenticator stays as it is', calls_take(), [ [ 'hostapd.lo', 'get_status', {} ] ]);

notify('hostapd.lo', 'sta-authorized', { address: '02:00:00:00:00:01', ifname: 'lo' });
check('an authorised station opens the port', calls_take(), [ OPEN ]);
notify('hostapd.lo', 'sta-authorized', { address: '02:00:00:00:00:02', ifname: 'lo' });
notify('hostapd.lo', 'disassoc', { address: '02:00:00:00:00:01', ifname: 'lo' });
check('the port stays open while a station is authorised', calls_take(), []);
notify('hostapd.lo', 'deauth', { address: '02:00:00:00:00:02', ifname: 'lo' });
check('the last station closes the port', calls_take(), [ [ 'network.device', 'set_state', { name: 'lo', auth_status: false } ] ]);
notify('hostapd.wlan0', 'sta-authorized', { address: '02:00:00:00:00:03', ifname: 'wlan0' });
check('a WiFi BSS is not a port', calls_take(), []);
check('and has no subscriber of the plugin', subscribed('hostapd.wlan0'), false);

notify('hostapd.lo', 'sta-authorized', { address: '02:00:00:00:00:01', ifname: 'lo' });
calls_take();
notify('network.device', 'link_down', { name: 'lo' });
check('a link loss makes hostapd forget the stations', calls_take(), [ [ 'hostapd.lo', 'del_clients', {} ] ]);
notify('hostapd.lo', 'sta-authorized', { address: '02:00:00:00:00:01', ifname: 'lo' });
check('and the next station opens the port again', calls_take(), [ OPEN ]);

row = { ...row, Enable: 'true', StartFailurePolicy: 'AssumeAuthentication' };
for (let timer in [ 'MaxStart', 'StartPeriod', 'HeldPeriod' ])
	delete row[timer];
config_write(row, authenticator);
digest();
check('a supplicant and an authenticator cannot share a port', calls_take(), [
	OPEN,
	[ 'hostapd', 'config_remove', { iface: 'lo' } ],
	ADD, ...SETS
]);

row.Enable = 'false';
authenticator.auth_server_shared_secret = 'other';
config_write(row, authenticator);
digest();
calls_take();
authenticator.enable = 'false';
config_write(row, authenticator);
digest();
check('a disabled authenticator opens its port and stops', calls_take(),
	[ OPEN, [ 'hostapd', 'config_remove', { iface: 'lo' } ] ]);
check('and removes its file', !!fs.access(`${RUN_DIR}/lo.hostapd`), false);

printf('passed: %d\nfailed: %d\n', pass, fail);
exit(fail ? 1 : 0);
