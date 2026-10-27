'use strict';

// ubbf-device plugin of ubbf-mod-hardware. Buttons (TR-181 2.21): the
// press and release events, which /etc/hotplug.d/button/50-ubbf-hardware
// forwards, the TriggerCondition timing and the Triggered! events, and the
// simulation of Push() and Release(). CPUs (2.20): the stored cpufreq
// settings are written to sysfs at start and after each commit.

import * as fs from 'fs';
import * as ubus from 'ubus';
import * as uloop from 'uloop';
import { log_info, log_err } from 'ubbf.utils.logging';
import { dm_event_send } from 'ubbf.utils.events';
import { dm_visible } from 'ubbf.utils.dm-version';

const MODULE_DIR = '/usr/share/ucode/ubbf/modules/hardware';
const CONFIG_PATH = '/etc/ubbf/config.json';
const RC_BUTTON_DIR = '/etc/rc.button';
const BUTTONS = dm_visible('2.21', null);
const CPUS = dm_visible('2.20', null);

export let hardware = {};
include(MODULE_DIR + '/hardware.uc', { hardware });

let config = {};
let buttons = [];
let state = {};
let active = {};

/**
 * Returns the monotonic time in milliseconds.
 *
 * @returns {number} Milliseconds
 */
function now_ms() {
	let c = clock(true);
	return c[0] * 1000 + c[1] / 1000000;
}

/**
 * Loads Device.Hardware of the stored configuration.
 */
function config_load() {
	let data = fs.readfile(CONFIG_PATH);
	config = {};

	try {
		config = json(data ?? '{}')?.Device?.Hardware ?? {};
	} catch (e) {
		log_err('hardware: invalid JSON in %s', CONFIG_PATH);
	}
}

/**
 * Returns the state of a button, created on first use.
 *
 * @param {string} name - Button name of gpio-button-hotplug
 * @returns {object} { pressed, press, changed, timers, simulation }
 */
function button_state(name) {
	return state[name] ??= { pressed: false, press: 0, changed: now_ms(), timers: [], simulation: null };
}

/**
 * Returns the Device.Hardware.Buttons.Button instance of a button.
 *
 * @param {string} name - Button name
 * @returns {number|null} Instance number, or null for an unknown button
 */
function button_instance(name) {
	for (let n = 0; n < length(buttons); n++)
		if (buttons[n].name == name)
			return n + 1;
	return null;
}

/**
 * Returns the enabled TriggerCondition rows of a button.
 *
 * @param {number} n - Button instance
 * @returns {array} [ instance, row ] pairs
 */
function triggers_get(n) {
	let rows = config?.Buttons?.Button?.[sprintf('%d', n)]?.TriggerCondition ?? {};
	return map(filter(keys(rows), (t) => rows[t]?.Enable == 'true' || rows[t]?.Enable == true),
		(t) => [ t, rows[t] ]);
}

/**
 * Activates a trigger condition: Active for ActiveTime ms and the
 * Triggered! event.
 *
 * @param {number} n - Button instance
 * @param {string} t - TriggerCondition instance
 * @param {object} trig - TriggerCondition row
 * @param {number} interval - Milliseconds from the press to the activation
 */
function trigger_fire(n, t, trig, interval) {
	let key = sprintf('%d.%s', n, t);
	let name = config?.Buttons?.Button?.[sprintf('%d', n)]?.Name ?? buttons[n - 1]?.name;

	active[key] = now_ms() + (+(trig.ActiveTime ?? 0));
	dm_event_send(`Device.Hardware.Buttons.Button.${n}.TriggerCondition.${t}.Triggered!`, {
		Name: trig.Name ?? '',
		ButtonName: name ?? '',
		Type: trig.Type ?? 'Pressed',
		Interval: sprintf('%d', interval)
	});
}

/**
 * Arms a LongPressed trigger for the current press of a button.
 *
 * @param {object} st - Button state
 * @param {number} n - Button instance
 * @param {string} t - TriggerCondition instance
 * @param {object} trig - TriggerCondition row
 */
function long_press_arm(st, n, t, trig) {
	let press = st.press;
	let timeout = +(trig.Timeout ?? 0);

	push(st.timers, uloop.timer(timeout, () => {
		if (st.pressed && st.press == press)
			trigger_fire(n, t, trig, timeout);
	}));
}

/**
 * Handles a press: Pressed triggers fire, LongPressed triggers start.
 *
 * @param {string} name - Button name
 * @returns {boolean} False when the button was pressed already
 */
function button_pressed(name) {
	let st = button_state(name);
	if (st.pressed)
		return false;

	st.pressed = true;
	st.press++;
	st.changed = now_ms();

	let n = button_instance(name);
	for (let pair in (n ? triggers_get(n) : [])) {
		if (pair[1].Type == 'LongPressed')
			long_press_arm(st, n, pair[0], pair[1]);
		else if ((pair[1].Type ?? 'Pressed') == 'Pressed')
			trigger_fire(n, pair[0], pair[1], 0);
	}

	return true;
}

/**
 * Handles a release: Released triggers whose Min and Max hold the press
 * time fire.
 *
 * @param {string} name - Button name
 * @returns {number|null} Milliseconds the button was held, or null when it
 *     was not pressed
 */
function button_released(name) {
	let st = button_state(name);
	if (!st.pressed)
		return null;

	let held = now_ms() - st.changed;
	st.pressed = false;
	st.changed = now_ms();

	for (let timer in st.timers)
		timer.cancel();
	st.timers = [];

	let n = button_instance(name);
	for (let pair in (n ? triggers_get(n) : [])) {
		let trig = pair[1];
		if (trig.Type == 'Released' && held >= +(trig.Min ?? 0) && held <= +(trig.Max ?? 0))
			trigger_fire(n, pair[0], trig, held);
	}

	return held;
}

/**
 * Runs /etc/rc.button/<name> as procd does for a press of the button
 * (handle_button_complete() in procd plug/hotplug.c): the exit code of a
 * press is a timeout in seconds, after which the script runs again with
 * ACTION=timeout while the press lasts.
 *
 * @param {string} name - Button name
 * @param {string} action - pressed, released or timeout
 * @param {number} seen - SEEN in seconds
 * @param {number} press - Press counter of the button state
 */
function rc_button_run(name, action, seen, press) {
	let path = `${RC_BUTTON_DIR}/${name}`;
	if (!fs.access(path, 'x'))
		return;

	let env = { BUTTON: name, ACTION: action, SEEN: sprintf('%d', seen), PATH: '/usr/sbin:/usr/bin:/sbin:/bin' };

	uloop.process(path, [], env, (code) => {
		if (action != 'pressed' || code <= 0)
			return;

		uloop.timer(code * 1000, () => {
			let st = button_state(name);
			if (st.pressed && st.press == press)
				rc_button_run(name, 'timeout', code, press);
		});
	});
}

/**
 * Simulates a press or a release of a button for Push() and Release().
 * The trigger conditions and /etc/rc.button/<name> see it like a real one.
 *
 * @param {string} name - Button name
 * @param {string} action - push or release
 * @param {number} duration - Milliseconds until the opposite action, 0 for
 *     none
 * @returns {boolean} False when the button already is in that state
 */
function button_simulate(name, action, duration) {
	let st = button_state(name);
	let seen = (now_ms() - st.changed) / 1000;

	if (st.pressed == (action == 'push'))
		return false;

	st.simulation?.cancel();
	st.simulation = null;

	if (action == 'push') {
		button_pressed(name);
		rc_button_run(name, 'pressed', seen, st.press);
	}
	else {
		let held = button_released(name);
		rc_button_run(name, 'released', held / 1000, st.press);
	}

	if (duration > 0)
		st.simulation = uloop.timer(duration,
			() => button_simulate(name, action == 'push' ? 'release' : 'push', 0));

	return true;
}

/**
 * ubus method button_event: a press or release from the hotplug script.
 *
 * @param {object} req - Request with args { button, action }
 * @returns {object} Empty reply
 */
function button_event_handler(req) {
	if (!BUTTONS)
		return {};

	if (req.args.action == 'pressed')
		button_pressed(req.args.button);
	else if (req.args.action == 'released')
		button_released(req.args.button);

	return {};
}

/**
 * ubus method button_simulate: Push() and Release() of the agent.
 *
 * @param {object} req - Request with args { button, action, duration }
 * @returns {object} { applied } or { error }
 */
function button_simulate_handler(req) {
	let name = req.args.button;
	if (!BUTTONS || button_instance(name) == null)
		return { error: 'unknown button' };
	if (req.args.action != 'push' && req.args.action != 'release')
		return { error: 'unknown action' };

	return { applied: button_simulate(name, req.args.action, +(req.args.duration ?? 0)) };
}

/**
 * ubus method hardware_status: button state and active trigger conditions.
 *
 * @param {object} req - Request
 * @returns {object} { buttons: { name: Pressed|Released }, active: [ 'b.t' ] }
 */
function hardware_status_handler(req) {
	let now = now_ms();
	let out = {};

	for (let b in buttons)
		if (b.name)
			out[b.name] = state[b.name]?.pressed ? 'Pressed' : 'Released';

	return { buttons: out, active: filter(keys(active), (k) => active[k] > now) };
}

/**
 * Writes one cpufreq attribute.
 *
 * @param {string} dir - cpufreq directory
 * @param {string} name - Attribute
 * @param {string} value - Value
 */
function cpufreq_write(dir, name, value) {
	if (fs.writefile(`${dir}/${name}`, value) == null)
		log_err('hardware: writing %s to %s/%s failed: %s', value, dir, name, fs.error());
}

/**
 * Writes the stored DVFS settings of one CPU. The limit that moves away
 * from the other is written first, so the kernel never sees min above max.
 *
 * @param {number} cpu - CPU number
 * @param {object} dvfs - Stored DVFS object
 */
function cpu_apply(cpu, dvfs) {
	let dir = hardware.cpufreq_dir(cpu);
	if (!dir || type(dvfs) != 'object')
		return;

	if (dvfs.ScalingGovernor)
		cpufreq_write(dir, 'scaling_governor', dvfs.ScalingGovernor);

	let min = dvfs.ScalingMinFrequency, max = dvfs.ScalingMaxFrequency;
	let cur_max = +(hardware.cpufreq_read(dir, 'scaling_max_freq') ?? 0);
	let order = (min != null && +min > cur_max)
		? [ [ 'scaling_max_freq', max ], [ 'scaling_min_freq', min ] ]
		: [ [ 'scaling_min_freq', min ], [ 'scaling_max_freq', max ] ];

	for (let o in order)
		if (o[1] != null && o[1] != '' && o[1] != '0')
			cpufreq_write(dir, o[0], o[1]);
}

/**
 * Writes the stored DVFS settings of every CPU.
 */
function cpus_apply() {
	let cpus = hardware.cpus_list();
	let rows = config?.CPUs?.CPU ?? {};

	for (let n = 0; n < length(cpus); n++)
		cpu_apply(cpus[n], rows[sprintf('%d', n + 1)]?.DVFS);
}

/**
 * Handles bbf-dm.digest: the configuration changed.
 */
function digest_event() {
	config_load();
	if (CPUS)
		cpus_apply();
}

/**
 * Finds the buttons and writes the stored cpufreq settings.
 */
export function init() {
	config_load();
	buttons = BUTTONS ? hardware.buttons_list() : [];
	log_info('hardware: %d buttons', length(buttons));

	if (CPUS)
		cpus_apply();

	ubus.listener('bbf-dm.digest', digest_event);
};

/**
 * Returns the ubus methods of the plugin.
 *
 * @returns {object} button_event, button_simulate and hardware_status
 */
export function ubus_methods() {
	return {
		button_event: {
			call: button_event_handler,
			args: { button: '', action: '' }
		},
		button_simulate: {
			call: button_simulate_handler,
			args: { button: '', action: '', duration: 0 }
		},
		hardware_status: {
			call: hardware_status_handler,
			args: {}
		}
	};
};
