// Host test of the ubbf-device plugin of the hardware module: the trigger
// conditions of a button (Pressed, LongPressed, Released, ActiveTime), the
// Triggered! events, the simulation of Push() and Release() with
// /etc/rc.button and its timeout, and the cpufreq settings written to
// sysfs. A ubus mock records the events and answers nothing.
'use strict';

import { describe, it, assert, mock, setup, beforeEach } from 'utest';
import * as fs from 'fs';
import * as uloop from 'uloop';
import { state_clear } from 'test_env';
import { DM_VERSION } from '../hardware/dm_version_221.uc';
import { build } from '../hardware/hardware_fixtures.uc';
import * as plugin from '../../modules/hardware/files/usr/share/ucode/ubbf/device/plugins/hardware.uc';

const CPU0 = '/sys/devices/system/cpu/cpu0/cpufreq/';
const CPU1 = '/sys/devices/system/cpu/cpu1/cpufreq/';

let ubus_calls = [];
let methods;

function plugin_start() {
	if (methods)
		return methods;

	uloop.init();
	plugin.init();
	methods = plugin.ubus_methods();
	return methods;
}

function wait(ms) {
	uloop.timer(ms, () => uloop.end());
	uloop.run();
}

function events_take() {
	let out = [];
	for (let c in ubus_calls)
		if (c.method == 'event')
			push(out, [ replace(c.data.path, 'Device.Hardware.Buttons.', ''), c.data.args.Name,
				c.data.args.ButtonName, c.data.args.Type ]);
	ubus_calls = [];
	return out;
}

function rc_log_take() {
	let lines = filter(split(fs.readfile('/etc/rc.log') ?? '', '\n'), (l) => l != '');
	fs.writefile('/etc/rc.log', '');
	return lines;
}

setup(() => {
	state_clear();
	build();

	fs.writefile('/etc/ubbf/tr181-version', DM_VERSION + '\n');
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
	fs.writefile('/etc/rc.log', '');
});

beforeEach(() => {
	ubus_calls = [];
	mock.global.patch('ubus', { behavior: {
		call: (object, method, data) => {
			push(ubus_calls, { object, method, data });
			return null;
		},
		listener: () => null,
		subscriber: () => null,
		error: () => null
	} });
});

describe('hardware plugin cpufreq', () => {
	it('writes the stored settings to cpufreq', () => {
		plugin_start();
		assert.match([ '1312500', 'performance', '875000', '1750000' ], [
			trim(fs.readfile(CPU0 + 'scaling_max_freq')), trim(fs.readfile(CPU0 + 'scaling_governor')),
			trim(fs.readfile(CPU1 + 'scaling_min_freq')), trim(fs.readfile(CPU1 + 'scaling_max_freq'))
		]);
	});
});

describe('hardware plugin buttons', () => {
	it('fires the trigger conditions and simulates Push() and Release()', () => {
		let m = plugin_start();
		let status = () => m.hardware_status.call({ args: {} });

		assert.match({ buttons: { reset: 'Released', wps: 'Released' }, active: [] }, status(), 'the buttons start released');

		m.button_event.call({ args: { button: 'reset', action: 'pressed' } });
		assert.match([ [ 'Button.2.TriggerCondition.1.Triggered!', 'short', 'factory', 'Pressed' ] ], events_take(),
			'a press fires the Pressed condition');
		assert.match({ buttons: { reset: 'Pressed', wps: 'Released' }, active: [ '2.1' ] }, status(),
			'the button is pressed and the condition active');

		wait(400);
		assert.match([ [ 'Button.2.TriggerCondition.2.Triggered!', 'long', 'factory', 'LongPressed' ] ], events_take(),
			'LongPressed fires after Timeout');

		m.button_event.call({ args: { button: 'reset', action: 'released' } });
		assert.match([ [ 'Button.2.TriggerCondition.3.Triggered!', 'tap', 'factory', 'Released' ] ], events_take(),
			'a release inside Min and Max fires Released');
		assert.match([], rc_log_take(), 'a hardware event runs no rc.button script');

		m.button_event.call({ args: { button: 'reset', action: 'pressed' } });
		m.button_event.call({ args: { button: 'reset', action: 'released' } });
		events_take();
		wait(1100);
		assert.match([], status().active, 'Active ends after ActiveTime');

		assert.match({ applied: true }, m.button_simulate.call({ args: { button: 'wps', action: 'push', duration: 150 } }));
		assert.match({ applied: false }, m.button_simulate.call({ args: { button: 'wps', action: 'push', duration: 0 } }),
			'a second Push() has no effect');
		wait(400);
		assert.match([ 'pressed', 'released' ], map(rc_log_take(), (l) => split(l, ' ')[1]),
			'the simulated press runs rc.button and releases after Duration');
		assert.match('Released', status().buttons.wps);

		assert.match({ applied: true }, m.button_simulate.call({ args: { button: 'reset', action: 'push', duration: 1500 } }));
		wait(1800);
		let runs = rc_log_take();
		assert.match([ 'pressed', 'timeout', 'released' ], map(runs, (l) => split(l, ' ')[1]),
			'the exit code of rc.button gives a timeout run, as procd does');
		assert.match([ '1', '1' ], slice(map(runs, (l) => split(l, ' ')[2]), 1),
			'SEEN of the timeout run is the exit code, of the release the held seconds');
		assert.match([ 'short', 'long', 'tap' ], map(events_take(), (e) => e[1]), 'the simulated press fires the conditions');

		assert.match({ applied: false }, m.button_simulate.call({ args: { button: 'reset', action: 'release', duration: 0 } }),
			'Release() of a released button has no effect');
		assert.match({ error: 'unknown button' }, m.button_simulate.call({ args: { button: 'power', action: 'push', duration: 0 } }));
	});
});
