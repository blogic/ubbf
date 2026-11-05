// Host test of the settle check of the testbed RPC handler, through onRequest()
// and onBody(): apply-config and dm-set against a ubus mock of netifd and a fake
// /sys/class/net. The clock runs on sleep(), so a wait for 30 s takes no time.
'use strict';

import { describe, it, assert, mock, teardown } from 'utest';
import * as fs from 'fs';
import { onRequest, onBody } from '../../modules/testbed/files/usr/share/ucode/ubbf/testbed/uwsd-handler.uc';

const WLAN_DEVICES = [ 'ap-mld0', 'sta-mld0', 'phy0-guest', 'phy1-guest' ];
const SETTLE_TIMEOUT_MS = 30000;
const POLL_MS = 250;

function mkdir_p(path) {
	let cur = '';
	for (let part in split(ltrim(path, '/'), '/')) {
		cur += '/' + part;
		fs.mkdir(cur);
	}
}

mkdir_p('/sys/class/ieee80211/phy0');
for (let name in WLAN_DEVICES) {
	mkdir_p(`/sys/class/net/${name}`);
	fs.symlink('/sys/class/ieee80211/phy0', `/sys/class/net/${name}/phy80211`);
}

function iface_make(name, l3_device, fields) {
	return {
		interface: name, l3_device, proto: 'static',
		up: true, pending: false, autostart: true, available: true,
		...(fields ?? {})
	};
}

/**
 * Serves the handler one device: interfaces and devices are what netifd
 * reports, and the steps change them. `apply` runs in the change, each entry
 * of `polls` before the next read of the interface dump after the change.
 */
function netifd_make(interfaces, devices, apply, polls) {
	let bed = { interfaces, devices, apply, polls: polls ?? [], applied: false, dumps: 0 };

	mock.global.patch('ubus', { behavior: {
		call: (object, method, args) => {
			if (object == 'network.device' && method == 'status')
				return bed.devices[args.name];
			if (object == 'bbf-device' && method == 'apply_state')
				return { pending: false };
			if (object == 'bbf-dm' && method == 'batch') {
				bed.apply?.(bed);
				bed.applied = true;
				return { success: true, digest: 'digest' };
			}
			if (object == 'network.interface' && method == 'dump') {
				if (bed.applied && bed.dumps < length(bed.polls))
					bed.polls[bed.dumps]?.(bed);
				if (bed.applied)
					bed.dumps++;
				return { interface: bed.interfaces };
			}
			return null;
		},
		error: () => 'Not found'
	} });

	return bed;
}

function rpc_call(bed, method, params) {
	let elapsed_ms = 0;
	let answer;
	let state = {};
	let request = {
		data: (value) => {
			if (value != null)
				state = value;
			return state;
		},
		reply: (headers, body) => {
			answer = json(body);
			return true;
		}
	};
	let body = sprintf('%J', { jsonrpc: '2.0', id: 1, method, params });

	let run = () => {
		onRequest(request, 'POST', '/rpc');
		onBody(request, body);
		onBody(request, '');
	};
	let system_stub = (command) => {
		bed.apply?.(bed);
		bed.applied = true;
		return 0;
	};

	mock.inject_builtin('system', system_stub, () =>
		mock.inject_builtin('time', () => 1000 + elapsed_ms / 1000, () =>
			mock.inject_builtin('sleep', (ms) => { elapsed_ms += ms; return true; }, run)));

	return { answer, elapsed_ms };
}

function config_apply(bed) {
	let r = rpc_call(bed, 'apply-config', { profile: 'Test' });

	return { success: r.answer.result.success, output: r.answer.result.output, elapsed_ms: r.elapsed_ms };
}

function agent_bridge(sta_carrier) {
	return {
		'br-lan': { carrier: sta_carrier, 'bridge-members': [ 'ap-mld0', 'lan1', 'lan2', 'lan3', 'sta-mld0' ] },
		'ap-mld0': { carrier: false },
		'sta-mld0': { carrier: sta_carrier },
		lan1: { carrier: false },
		lan2: { carrier: false },
		lan3: { carrier: false }
	};
}

function sta_lost(bed) {
	bed.devices['sta-mld0'].carrier = false;
	bed.devices['br-lan'].carrier = false;
}

function wired_bridge(lan1_carrier, sta_carrier) {
	return {
		'br-lan': { carrier: lan1_carrier || sta_carrier, 'bridge-members': [ 'lan1', 'sta-mld0' ] },
		lan1: { carrier: lan1_carrier },
		'sta-mld0': { carrier: sta_carrier }
	};
}

function lan1_set(carrier) {
	return (bed) => {
		bed.devices.lan1.carrier = carrier;
		bed.devices['br-lan'].carrier = carrier || bed.devices['sta-mld0'].carrier;
	};
}

teardown(() => {
	mock.global.unpatch('ubus');
	for (let name in WLAN_DEVICES) {
		fs.unlink(`/sys/class/net/${name}/phy80211`);
		fs.rmdir(`/sys/class/net/${name}`);
	}
	fs.rmdir('/sys/class/net');
	fs.rmdir('/sys/class/ieee80211/phy0');
	fs.rmdir('/sys/class/ieee80211');
	fs.rmdir('/sys/class');
});

describe('settle check of a device on a Wi-Fi backhaul', () => {
	it('passes when the link goes after the snapshot and no BSS is left', () => {
		let bed = netifd_make([ iface_make('lan', 'br-lan') ], agent_bridge(true), sta_lost);
		let r = config_apply(bed);

		assert.match([ true, '', 0 ], [ r.success, r.output, r.elapsed_ms ]);
	});

	it('passes when the link goes before the snapshot', () => {
		let bed = netifd_make([ iface_make('lan', 'br-lan') ], agent_bridge(false));
		let r = config_apply(bed);

		assert.match([ true, '', 0 ], [ r.success, r.output, r.elapsed_ms ]);
	});

	it('passes when the link goes after the snapshot and the station joins another BSS', () => {
		let joined = (bed) => {
			bed.devices['sta-mld0'].carrier = true;
			bed.devices['br-lan'].carrier = true;
		};
		let bed = netifd_make([ iface_make('lan', 'br-lan') ], agent_bridge(true), sta_lost, [ null, joined ]);

		assert.match(true, config_apply(bed).success);
	});

	it('still waits while lan is not up', () => {
		let lan = iface_make('lan', 'br-lan');
		let down = (bed) => { sta_lost(bed); lan.up = false; };
		let up = () => { lan.up = true; };
		let r = config_apply(netifd_make([ lan ], agent_bridge(true), down, [ null, null, up ]));

		assert.match([ true, 2 * POLL_MS ], [ r.success, r.elapsed_ms ]);
	});

	it('fails when lan does not come back up', () => {
		let lan = iface_make('lan', 'br-lan');
		let down = (bed) => { sta_lost(bed); lan.up = false; };
		let r = config_apply(netifd_make([ lan ], agent_bridge(true), down));

		assert.match([ false, 'network did not settle within 30s: lan is not up\n', SETTLE_TIMEOUT_MS ],
			[ r.success, r.output, r.elapsed_ms ]);
	});

	it('needs no carrier on an interface that is a wlan device', () => {
		let bed = netifd_make([ iface_make('backhaul', 'sta-mld0', { up: false }) ], { 'sta-mld0': { carrier: false } },
			(bed) => { bed.interfaces[0].up = true; });

		assert.match(true, config_apply(bed).success);
	});
});

describe('settle check of br-guest with Wi-Fi ports alone', () => {
	const GUEST_DEVICES = {
		'br-guest': { carrier: false, 'bridge-members': [ 'phy0-guest', 'phy1-guest' ] },
		'phy0-guest': { carrier: false },
		'phy1-guest': { carrier: false }
	};

	it('needs no carrier when the interface is new in the apply', () => {
		let added = (bed) => { push(bed.interfaces, iface_make('guest', 'br-guest')); };
		let r = config_apply(netifd_make([], GUEST_DEVICES, added));

		assert.match([ true, 0 ], [ r.success, r.elapsed_ms ]);
	});

	it('needs no carrier when the interface was not up before the apply', () => {
		let guest = iface_make('guest', 'br-guest', { up: false });
		let r = config_apply(netifd_make([ guest ], GUEST_DEVICES, () => { guest.up = true; }));

		assert.match([ true, 0 ], [ r.success, r.elapsed_ms ]);
	});

	it('needs no carrier on a bridge that holds no member yet', () => {
		let guest = iface_make('guest', 'br-guest', { up: false });
		let devices = { 'br-guest': { carrier: false, 'bridge-members': [] } };

		assert.match(true, config_apply(netifd_make([ guest ], devices, () => { guest.up = true; })).success);
	});
});

describe('settle check of a wired port', () => {
	it('fails when a carrier of the bridge does not come back', () => {
		let bed = netifd_make([ iface_make('lan', 'br-lan') ],
			{ 'br-lan': { carrier: true, 'bridge-members': [ 'lan1' ] }, lan1: { carrier: true } },
			(bed) => { bed.devices.lan1.carrier = false; bed.devices['br-lan'].carrier = false; });
		let r = config_apply(bed);

		assert.match([ false, 'network did not settle within 30s: lan has no carrier on br-lan\n', SETTLE_TIMEOUT_MS ],
			[ r.success, r.output, r.elapsed_ms ]);
	});

	it('fails when a carrier of a plain device does not come back', () => {
		let bed = netifd_make([ iface_make('wan', 'eth0') ], { eth0: { carrier: true } },
			(bed) => { bed.devices.eth0.carrier = false; });

		assert.match('network did not settle within 30s: wan has no carrier on eth0\n', config_apply(bed).output);
	});

	it('waits until the carrier comes back', () => {
		let back = (bed) => { bed.devices.eth0.carrier = true; };
		let r = config_apply(netifd_make([ iface_make('wan', 'eth0') ], { eth0: { carrier: true } },
			(bed) => { bed.devices.eth0.carrier = false; }, [ null, null, null, back ]));

		assert.match([ true, 3 * POLL_MS ], [ r.success, r.elapsed_ms ]);
	});

	it('does not ask for a carrier that was not there before the change', () => {
		let devices = { 'br-lan': { carrier: false, 'bridge-members': [ 'lan1' ] }, lan1: { carrier: false } };

		assert.match(true, config_apply(netifd_make([ iface_make('lan', 'br-lan') ], devices)).success);
	});

	it('waits for the bridge when a port has a carrier and the bridge has none yet', () => {
		let forwarding = (bed) => { bed.devices['br-lan'].carrier = true; };
		let devices = { 'br-lan': { carrier: true, 'bridge-members': [ 'lan1' ] }, lan1: { carrier: true } };
		let r = config_apply(netifd_make([ iface_make('lan', 'br-lan') ], devices,
			(bed) => { bed.devices['br-lan'].carrier = false; }, [ null, forwarding ]));

		assert.match([ true, POLL_MS ], [ r.success, r.elapsed_ms ]);
	});
});

describe('settle check of a bridge with wired and Wi-Fi ports', () => {
	it('passes when the wired port keeps its carrier and the Wi-Fi link goes', () => {
		let bed = netifd_make([ iface_make('lan', 'br-lan') ], wired_bridge(true, true),
			(bed) => { bed.devices['sta-mld0'].carrier = false; });

		assert.match(true, config_apply(bed).success);
	});

	it('does not take the Wi-Fi link for the carrier of a wired port', () => {
		let bed = netifd_make([ iface_make('lan', 'br-lan') ], wired_bridge(true, true), lan1_set(false));
		let r = config_apply(bed);

		assert.match([ false, 'network did not settle within 30s: lan has no carrier on br-lan\n' ], [ r.success, r.output ]);
	});

	it('waits for the wired port behind a live Wi-Fi link', () => {
		let bed = netifd_make([ iface_make('lan', 'br-lan') ], wired_bridge(true, true), lan1_set(false),
			[ null, null, lan1_set(true) ]);
		let r = config_apply(bed);

		assert.match([ true, 2 * POLL_MS ], [ r.success, r.elapsed_ms ]);
	});
});

describe('settle check of a dm-set', () => {
	const VALUES = [ { path: 'Device.WiFi.SSID.1.SSID', value: 'x' } ];

	it('passes when the Wi-Fi link goes after the snapshot', () => {
		let bed = netifd_make([ iface_make('lan', 'br-lan') ], agent_bridge(true), sta_lost);

		assert.match({ success: true, digest: 'digest' }, rpc_call(bed, 'dm-set', { values: VALUES }).answer.result);
	});

	it('fails when a wired carrier does not come back', () => {
		let bed = netifd_make([ iface_make('wan', 'eth0') ], { eth0: { carrier: true } },
			(bed) => { bed.devices.eth0.carrier = false; });

		assert.match('network did not settle within 30s: wan has no carrier on eth0',
			rpc_call(bed, 'dm-set', { values: VALUES }).answer.error.message);
	});
});
