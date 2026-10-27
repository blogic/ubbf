// Host test of the ubbf-device plugin of the hardware module: the trigger
// conditions of a button (Pressed, LongPressed, Released, ActiveTime), the
// Triggered! events, the simulation of Push() and Release() with
// /etc/rc.button and its timeout, and the cpufreq settings written to
// sysfs. Run from the repository root in a private mount namespace:
//   unshare -rm sh -e -c 'repo=$PWD; mount -t tmpfs none /sys; mount -t tmpfs none /etc;
//     mkdir -p /etc/ubbf; echo 2.21.0 > /etc/ubbf/tr181-version;
//     mount -t tmpfs none /usr/share; mkdir -p /usr/share/ucode/ubbf/modules;
//     ln -s "$repo/modules/hardware" /usr/share/ucode/ubbf/modules/;
//     exec ucode -L "$repo/tests/hardware-plugin/*.uc" -L "$repo/tests/hardware/*.uc" \
//       -L "$repo/tests/hosts/*.uc" -L "$repo/files/usr/share/ucode" \
//       -L "$repo/modules/hardware/files/usr/share/ucode" -L "$1/*.so" \
//       "$repo/tests/hardware-plugin.uc"' sh <host build>
'use strict';

import * as fs from 'fs';
import * as uloop from 'uloop';
import { build } from 'hardware_fixtures';
import * as plugin from 'ubbf.device.plugins.hardware';

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

function events_take() {
	let out = [];
	for (let c in global.UBUS_CALLS ?? []) {
		let req = c[0];
		if (type(req) == 'object' && req.method == 'event')
			push(out, [ replace(req.data.path, 'Device.Hardware.Buttons.', ''), req.data.args.Name,
				req.data.args.ButtonName, req.data.args.Type ]);
	}
	global.UBUS_CALLS = [];
	return out;
}

function rc_log_take() {
	let lines = filter(split(fs.readfile('/etc/rc.log') ?? '', '\n'), (l) => l != '');
	fs.writefile('/etc/rc.log', '');
	return lines;
}

build();

fs.writefile('/etc/ubbf/config.json', sprintf('%J', { Device: { Hardware: {
	CPUs: { CPU: {
		'1': { DVFS: { ScalingMaxFrequency: '1312500', ScalingGovernor: 'performance' } },
		'2': { DVFS: { ScalingMinFrequency: '875000' } }
	} },
	Buttons: { Button: { '2': { Name: 'factory', TriggerCondition: {
		'1': { Enable: 'true', Name: 'short', Type: 'Pressed', ActiveTime: '1000' },
		'2': { Enable: 'true', Name: 'long', Type: 'LongPressed', Timeout: '200' },
		'3': { Enable: 'true', Name: 'tap', Type: 'Released', Min: '0', Max: '5000' },
		'4': { Enable: 'false', Name: 'off', Type: 'Pressed' }
	} } } }
} } }));

fs.mkdir('/etc/rc.button');
fs.writefile('/etc/rc.button/reset',
	'#!/bin/sh\necho "$BUTTON $ACTION $SEEN" >> /etc/rc.log\n[ "$ACTION" = pressed ] && exit 1\nexit 0\n');
fs.writefile('/etc/rc.button/wps', '#!/bin/sh\necho "$BUTTON $ACTION $SEEN" >> /etc/rc.log\nexit 0\n');
fs.chmod('/etc/rc.button/reset', 0755);
fs.chmod('/etc/rc.button/wps', 0755);

uloop.init();
plugin.init();
let m = plugin.ubus_methods();

let cpu0 = '/sys/devices/system/cpu/cpu0/cpufreq/';
let cpu1 = '/sys/devices/system/cpu/cpu1/cpufreq/';
check('the stored settings reach cpufreq', [
	trim(fs.readfile(cpu0 + 'scaling_max_freq')), trim(fs.readfile(cpu0 + 'scaling_governor')),
	trim(fs.readfile(cpu1 + 'scaling_min_freq')), trim(fs.readfile(cpu1 + 'scaling_max_freq'))
], [ '1312500', 'performance', '875000', '1750000' ]);

let status = () => m.hardware_status.call({ args: {} });
check('the buttons start released', status(), { buttons: { reset: 'Released', wps: 'Released' }, active: [] });

m.button_event.call({ args: { button: 'reset', action: 'pressed' } });
check('a press fires the Pressed condition', events_take(),
	[ [ 'Button.2.TriggerCondition.1.Triggered!', 'short', 'factory', 'Pressed' ] ]);
check('the button is pressed and the condition active', status(),
	{ buttons: { reset: 'Pressed', wps: 'Released' }, active: [ '2.1' ] });

wait(400);
check('LongPressed fires after Timeout', events_take(),
	[ [ 'Button.2.TriggerCondition.2.Triggered!', 'long', 'factory', 'LongPressed' ] ]);

m.button_event.call({ args: { button: 'reset', action: 'released' } });
check('a release inside Min and Max fires Released', events_take(),
	[ [ 'Button.2.TriggerCondition.3.Triggered!', 'tap', 'factory', 'Released' ] ]);
check('a hardware event runs no rc.button script', rc_log_take(), []);

m.button_event.call({ args: { button: 'reset', action: 'pressed' } });
m.button_event.call({ args: { button: 'reset', action: 'released' } });
events_take();
wait(1100);
check('Active ends after ActiveTime', status().active, []);

check('Push() of wps', m.button_simulate.call({ args: { button: 'wps', action: 'push', duration: 150 } }),
	{ applied: true });
check('a second Push() has no effect', m.button_simulate.call({ args: { button: 'wps', action: 'push', duration: 0 } }),
	{ applied: false });
wait(400);
check('the simulated press runs rc.button and releases after Duration',
	map(rc_log_take(), (l) => split(l, ' ')[1]), [ 'pressed', 'released' ]);
check('wps is released again', status().buttons.wps, 'Released');

check('Push() of reset', m.button_simulate.call({ args: { button: 'reset', action: 'push', duration: 1500 } }),
	{ applied: true });
wait(1800);
let runs = rc_log_take();
check('the exit code of rc.button gives a timeout run, as procd does',
	map(runs, (l) => split(l, ' ')[1]), [ 'pressed', 'timeout', 'released' ]);
check('SEEN of the timeout run is the exit code, of the release the held seconds',
	slice(map(runs, (l) => split(l, ' ')[2]), 1), [ '1', '1' ]);
check('the simulated press fires the conditions', map(events_take(), (e) => e[1]), [ 'short', 'long', 'tap' ]);

check('Release() of a released button has no effect',
	m.button_simulate.call({ args: { button: 'reset', action: 'release', duration: 0 } }), { applied: false });
check('an unknown button', m.button_simulate.call({ args: { button: 'power', action: 'push', duration: 0 } }),
	{ error: 'unknown button' });

printf('passed: %d\nfailed: %d\n', pass, fail);
exit(fail ? 1 : 0);
