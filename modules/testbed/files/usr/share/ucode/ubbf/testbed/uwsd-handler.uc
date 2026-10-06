'use strict';

import * as uloop from 'uloop';
import * as log from 'log';
import * as ubus from 'ubus';
import * as socket from 'socket';
import { readfile, writefile, rename, readlink, lsdir, unlink, realpath } from 'fs';

const ERROR_PARSE = -32700;
const ERROR_INVALID_REQUEST = -32600;
const ERROR_METHOD_NOT_FOUND = -32601;
const ERROR_INVALID_PARAMS = -32602;
const ERROR_INTERNAL = -32603;
const ERROR_UNAUTHORISED = -32001;

const TOKEN_PATH = '/etc/ubbf/testbed-rpc.token';
const OUTPUT_PATH = '/tmp/ubbf-testbed-rpc.out';
const UWSD_CONF_DIR = '/tmp/uwsd';
const RPC_URI = '/rpc';
const BODY_MAX = 32 * 1024;
const APPLY_TIMEOUT = 60;
const SETTLE_TIMEOUT = 30;
const SETTLE_POLL_MS = 250;

// The worker serves one request at a time; two reloads per cycle must fit
// in the transfer timeout of the listener and of the client.
const UWSD_CYCLE_MAX = 250;

// A dm-set below these objects can change the interfaces, so it waits for
// the network; any other write answers once the apply ended.
const NETWORK_PATHS = [
	'Device.IP.', 'Device.Ethernet.', 'Device.PPP.', 'Device.Bridging.',
	'Device.DHCPv4.Client.', 'Device.DHCPv6.Client.', 'Device.WiFi.'
];

const PROFILE_CONFIG_PATH = {
	'Test': '/etc/ubbf/test_config.json',
	'Firewall': '/etc/ubbf/firewall_config.json'
};

const PRIORITY_SYSLOG = {
	'debug': log.LOG_DEBUG,
	'info': log.LOG_INFO,
	'notice': log.LOG_NOTICE,
	'warning': log.LOG_WARNING,
	'error': log.LOG_ERR
};

log.openlog('ubbf-testbed-rpc', 0, log.LOG_DAEMON);

// No token file means no token check: the port is opened on the lan zone
// alone, by a package that only a lab image installs. Writing one turns the
// check on for a deployment that wants it.
let token = trim(readfile(TOKEN_PATH) ?? '');

function reply_json(request, body) {
	return request.reply({
		'Status': '200 OK',
		'Content-Type': 'application/json'
	}, sprintf('%J', body));
}

function reply_success(request, id, result) {
	return reply_json(request, { jsonrpc: '2.0', id, result });
}

function reply_error(request, id, code, message) {
	return reply_json(request, { jsonrpc: '2.0', id, error: { code, message } });
}

/**
 * Runs a command and returns its exit code and combined output.
 * system() is what reports the exit status; a popen handle's close()
 * does not, and the harness needs both halves. Every caller is a short
 * synchronous lab action, so blocking the handler is acceptable here.
 */
function command_exec(command) {
	let exitcode = system(`${command} >${OUTPUT_PATH} 2>&1`);
	let output = readfile(OUTPUT_PATH) ?? '';

	unlink(OUTPUT_PATH);

	return {
		exitcode,
		output,
		success: exitcode == 0
	};
}

function command_run(request, id, command) {
	return reply_success(request, id, command_exec(command));
}

function wait_until(check, deadline) {
	while (time() < deadline) {
		if (check())
			return true;
		sleep(SETTLE_POLL_MS);
	}
	return false;
}

function apply_idle() {
	let state = ubus.call('bbf-device', 'apply_state');
	return state != null && !state.pending;
}

function interfaces_settled() {
	let dump = ubus.call('network.interface', 'dump');
	if (!dump?.interface)
		return false;

	for (let iface in dump.interface) {
		if (!iface.autostart || !iface.available)
			continue;
		if (!iface.up || iface.pending)
			return false;

		let device = ubus.call('network.device', 'status', { name: iface.l3_device });
		if (!device?.carrier)
			return false;
	}

	return true;
}

/**
 * Waits for the apply that bbf-cli scheduled, then, when the change can
 * touch the interfaces, for netifd to bring them back. The handler reloads
 * netifd itself because the procd trigger of reload_config fires only a
 * second later, and until then the interfaces still look up from before.
 * The trigger then finds no change and causes no second bounce. The apply
 * and the network have a budget each, so a slow apply does not eat the
 * time of the DHCP lease.
 *
 * @param {boolean} network - Whether to wait for the interfaces
 * @returns {string|null} Why the device did not settle, null when it did
 */
function device_settle(network) {
	if (!wait_until(apply_idle, time() + APPLY_TIMEOUT))
		return sprintf('apply did not end within %ds', APPLY_TIMEOUT);

	if (!network)
		return null;

	ubus.call('network', 'reload');

	if (!wait_until(interfaces_settled, time() + SETTLE_TIMEOUT))
		return sprintf('network did not settle within %ds', SETTLE_TIMEOUT);

	return null;
}

/**
 * Tells whether a dm-set can change the interfaces.
 *
 * @param {array} operations - bbf-dm batch operations
 * @returns {boolean} true when a path lies below NETWORK_PATHS
 */
function operations_touch_network(operations) {
	for (let op in operations)
		for (let prefix in NETWORK_PATHS)
			if (index(op.path, prefix) == 0)
				return true;

	return false;
}

function handle_apply_config(request, id, params) {
	let profile = params?.profile;
	let config_path = PROFILE_CONFIG_PATH[profile];

	if (!config_path)
		return reply_error(request, id, ERROR_INVALID_PARAMS,
			sprintf('unknown profile %s (allowed: %s)',
				profile ?? '(none)',
				join(', ', keys(PROFILE_CONFIG_PATH))));

	log.syslog(log.LOG_INFO, 'applying %s (%s)', config_path, profile);

	let result = command_exec(`bbf-cli apply ${config_path}`);
	let unsettled = result.success ? device_settle(true) : null;
	if (unsettled) {
		result.success = false;
		result.output += unsettled + '\n';
	}

	return reply_success(request, id, result);
}

/**
 * Sets data model parameters through bbf-dm. A test that cuts the ACS off
 * from the device, such as a WAN without IPv4, restores the device with it.
 */
function handle_dm_set(request, id, params) {
	let values = params?.values;
	let operations = [];

	if (type(values) != 'array' || !length(values))
		return reply_error(request, id, ERROR_INVALID_PARAMS,
				   'values must be a list of { path, value }');

	for (let entry in values) {
		if (type(entry?.path) != 'string' || type(entry?.value) != 'string')
			return reply_error(request, id, ERROR_INVALID_PARAMS,
					   'each value needs a string path and a string value');

		push(operations, { op: 'set', path: entry.path, value: entry.value });
	}

	log.syslog(log.LOG_INFO, 'setting %s', join(', ', map(operations, (op) => op.path)));

	let result = ubus.call('bbf-dm', 'batch', { operations });
	if (!result?.success)
		return reply_error(request, id, ERROR_INTERNAL,
				   result?.error ?? ubus.error() ?? 'bbf-dm batch failed');

	let unsettled = device_settle(operations_touch_network(operations));
	if (unsettled)
		return reply_error(request, id, ERROR_INTERNAL, unsettled);

	return reply_success(request, id, { success: true, digest: result.digest });
}

/**
 * Reads one data model parameter through bbf-dm, for a test that checks the
 * device while the ACS cannot reach it.
 */
function handle_dm_get(request, id, params) {
	let path = params?.path;

	if (type(path) != 'string' || substr(path, -1) == '.')
		return reply_error(request, id, ERROR_INVALID_PARAMS,
				   'path must name a parameter');

	// The plain form answers null for an unknown leaf and for a known leaf
	// without a value alike; the typed form tells them apart.
	let result = ubus.call('bbf-dm', 'get', { paths: [ path ], typed: true });
	if (type(result?.params) != 'array' || length(result.params) != 1)
		return reply_error(request, id, ERROR_INTERNAL,
				   sprintf('%s: %s', path, result?.error ?? ubus.error() ?? 'not one parameter'));

	return reply_success(request, id, { value: result.params[0].value });
}

function handle_crash_process(request, id, params) {
	let name = params?.name;

	if (type(name) != 'string' || !match(name, /^[A-Za-z0-9._-]+$/))
		return reply_error(request, id, ERROR_INVALID_PARAMS,
				   'name is required');

	log.syslog(log.LOG_INFO, 'crashing process %s', name);
	return command_run(request, id, `killall -9 ${name}`);
}

/**
 * The signal follows the restart without a pause, the way odhcpd-update
 * sends SIGHUP to dnsmasq on a lease change while dnsmasq restarts, so it
 * reaches the instances while they are still starting.
 */
function handle_service_restart(request, id, params) {
	let name = params?.name;
	let signo = params?.signal;

	if (type(name) != 'string' || !match(name, /^[A-Za-z0-9._-]+$/))
		return reply_error(request, id, ERROR_INVALID_PARAMS,
				   'name is required');
	if (signo != null && (type(signo) != 'int' || signo < 1 || signo > 31))
		return reply_error(request, id, ERROR_INVALID_PARAMS,
				   'signal must be a number from 1 to 31');

	let command = `/etc/init.d/${name} restart`;
	if (signo != null)
		command += sprintf(" && ubus call service signal '%J'",
				   { name, signal: signo });

	log.syslog(log.LOG_INFO, 'restarting service %s', name);
	return command_run(request, id, command);
}

// The uwsd-* ops below act only on configuration files named test-*, so a
// test cannot replace the file of a service, this handler's own included.
// The firewall opens only the service ports to the LAN, so test listeners
// are probed from the device itself.

function test_name_valid(name) {
	return type(name) == 'string' && match(name, /^test-[a-z0-9-]+$/) != null;
}

function port_valid(port) {
	return type(port) == 'int' && port >= 1 && port <= 65535;
}

function uwsd_conf_write(name, content) {
	let path = `${UWSD_CONF_DIR}/${name}.conf`;
	let tmp = `${UWSD_CONF_DIR}/.${name}.tmp`;

	if (content == null) {
		unlink(path);
		return true;
	}

	return writefile(tmp, content) != null && rename(tmp, path);
}

function uwsd_reload() {
	let reload = ubus.call('uwsd', 'reload');

	return { files: reload?.files, success: reload?.success ?? false };
}

function proc_status(pid) {
	let status = {};

	for (let line in split(readfile(`/proc/${pid}/status`) ?? '', '\n')) {
		let m = match(line, /^([A-Za-z_]+):[ \t]*(.*)$/);
		if (m)
			status[m[1]] = m[2];
	}

	return status;
}

function proc_test_marker(pid) {
	for (let entry in split(readfile(`/proc/${pid}/environ`) ?? '', '\0'))
		if (index(entry, 'UWSD_TEST=') == 0)
			return substr(entry, length('UWSD_TEST='));

	return null;
}

function uwsd_main_pid() {
	return int(proc_status('self').PPid);
}

/**
 * The workers of a test file carry UWSD_TEST=<name> through the
 * "environment" property of its run-script, which tells them apart from the
 * workers of the services. An orphan is a worker that lost its main
 * process: its parent is init.
 */
function uwsd_status(test) {
	let main = uwsd_main_pid();
	let main_status = proc_status(main);
	let status = {
		main_pid: main,
		anon_kb: int(split(main_status.RssAnon ?? '0', ' ')[0]),
		fds: length(lsdir(`/proc/${main}/fd`) ?? []),
		workers: 0,
		test_workers: [],
		orphans: 0
	};

	for (let pid in lsdir('/proc') ?? []) {
		if (!match(pid, /^[0-9]+$/))
			continue;

		let st = proc_status(pid);
		if (st.Name != 'uwsd' || int(pid) == main)
			continue;

		if (st.PPid == '1' && index(readfile(`/proc/${pid}/cmdline`) ?? '', '--config') < 0)
			status.orphans++;

		if (int(st.PPid) != main)
			continue;

		status.workers++;

		if (test != null && proc_test_marker(pid) == test)
			push(status.test_workers, int(pid));
	}

	status.test_worker_count = length(status.test_workers);

	return status;
}

/**
 * Half a request keeps the connection open past the reload: uwsd closes it
 * only if it drops the listener, or once the request timeout of the
 * listener runs out, which a test sets well above the reload.
 */
function hold_open(port) {
	let sock = socket.connect('127.0.0.1', port, { socktype: socket.SOCK_STREAM }, 2000);

	if (sock)
		sock.send('GET / HTTP/1.1\r\nHost: test\r\n');

	return sock;
}

function hold_state(sock) {
	if (!sock)
		return 'failed';

	let events = socket.poll(500, [ sock, socket.POLLIN ]);
	let state = 'open';

	if (events?.[0]?.[1] & (socket.POLLIN | socket.POLLHUP | socket.POLLERR)) {
		let data = sock.recv(4096, socket.MSG_DONTWAIT);
		state = (data == null || data == '') ? 'closed' : 'answered';
	}

	sock.close();

	return state;
}

/**
 * The reply carries the pid of this worker: a test compares it across
 * reloads to see that an unchanged file keeps its worker.
 */
function handle_uwsd_conf(request, id, params) {
	let name = params?.name;
	let content = params?.content;
	let probe = params?.probe;
	let hold = params?.hold;

	if (!test_name_valid(name))
		return reply_error(request, id, ERROR_INVALID_PARAMS,
				   'name must match test-[a-z0-9-]+');
	if (content != null && type(content) != 'string')
		return reply_error(request, id, ERROR_INVALID_PARAMS,
				   'content must be a string');
	if ((probe != null && !port_valid(probe)) || (hold != null && !port_valid(hold)))
		return reply_error(request, id, ERROR_INVALID_PARAMS,
				   'probe and hold must be port numbers');

	let held = (hold != null) ? hold_open(hold) : null;

	if (!uwsd_conf_write(name, content))
		return reply_error(request, id, ERROR_INTERNAL,
				   sprintf('unable to write the configuration %s', name));

	log.syslog(log.LOG_INFO, '%s uwsd configuration %s',
		   content == null ? 'removing' : 'installing', name);

	let result = uwsd_reload();
	result.worker_pid = int(readlink('/proc/self'));

	if (hold != null)
		result.held = hold_state(held);

	if (probe != null)
		result.probe = command_exec(params?.probe_tls
			? `wget -q -T 5 --no-check-certificate -O - https://127.0.0.1:${probe}/`
			: `wget -q -T 5 -O - http://127.0.0.1:${probe}/`);

	return reply_success(request, id, result);
}

function handle_uwsd_status(request, id, params) {
	let test = params?.test;

	if (test != null && !test_name_valid(test))
		return reply_error(request, id, ERROR_INVALID_PARAMS,
				   'test must match test-[a-z0-9-]+');

	return reply_success(request, id, uwsd_status(test));
}

/**
 * Killing the main process is deferred so the answer reaches the harness
 * first; this worker dies with it.
 */
function handle_uwsd_kill(request, id, params) {
	let target = params?.target;
	let test = params?.test;

	if (target == 'main') {
		let main = uwsd_main_pid();

		log.syslog(log.LOG_NOTICE, 'killing the uwsd main process %d in 1s', main);
		uloop.timer(1000, () => system(`kill -9 ${main}`));

		return reply_success(request, id, { main_pid: main, scheduled: true });
	}

	if (target != 'worker' || !test_name_valid(test))
		return reply_error(request, id, ERROR_INVALID_PARAMS,
				   'target must be main, or worker with a test name');

	let pids = uwsd_status(test).test_workers;

	for (let pid in pids)
		system(`kill -9 ${pid}`);

	log.syslog(log.LOG_NOTICE, 'killed uwsd workers of %s: %s', test, join(' ', pids));

	return reply_success(request, id, { killed: pids });
}

/**
 * One cycle installs and removes the file. The first cycle runs before the
 * measurement, so that allocations made once, such as the first SSL
 * context, do not count as growth.
 */
function handle_uwsd_cycle(request, id, params) {
	let name = params?.name;
	let content = params?.content;
	let count = params?.count;

	if (!test_name_valid(name) || type(content) != 'string')
		return reply_error(request, id, ERROR_INVALID_PARAMS,
				   'name must match test-[a-z0-9-]+ and content is required');
	if (type(count) != 'int' || count < 1 || count > UWSD_CYCLE_MAX)
		return reply_error(request, id, ERROR_INVALID_PARAMS,
				   sprintf('count must be a number from 1 to %d', UWSD_CYCLE_MAX));

	let failures = 0;
	let before;

	for (let i = 0; i <= count; i++) {
		if (i == 1)
			before = uwsd_status();

		if (!uwsd_conf_write(name, content) || !uwsd_reload().success)
			failures++;

		if (!uwsd_conf_write(name, null) || !uwsd_reload().success)
			failures++;
	}

	let after = uwsd_status();

	return reply_success(request, id, {
		cycles: count,
		failures,
		anon_kb_before: before.anon_kb,
		anon_kb_after: after.anon_kb,
		anon_growth_kb: after.anon_kb - before.anon_kb,
		fd_growth: after.fds - before.fds,
		worker_growth: after.workers - before.workers
	});
}

/**
 * The panic is deferred so the answer reaches the harness first. On eMMC
 * (overlayfs over f2fs, fsync_mode=posix) only a full sync forces a
 * checkpoint, without which the reboot can come back with torn state.
 */
function handle_crash_kernel(request, id, params) {
	log.syslog(log.LOG_NOTICE, 'scheduling kernel panic in 5s');
	uloop.timer(5000, () => {
		system('sync');
		system('echo c > /proc/sysrq-trigger');
	});
	return reply_success(request, id, { scheduled: true });
}

function handle_log_message(request, id, params) {
	let message = params?.message;
	let priority = PRIORITY_SYSLOG[params?.priority ?? 'info'];

	if (type(message) != 'string' || message == '')
		return reply_error(request, id, ERROR_INVALID_PARAMS,
				   'message is required');
	if (!priority)
		return reply_error(request, id, ERROR_INVALID_PARAMS,
			sprintf('unknown priority (allowed: %s)',
				join(', ', keys(PRIORITY_SYSLOG))));

	log.syslog(priority, '%s', message);

	return reply_success(request, id, { logged: true });
}

function handle_ping(request, id, params) {
	return reply_success(request, id, { pong: true });
}

function handle_tmp_count(request, id, params) {
	let prefix = params?.prefix;
	if (type(prefix) != 'string' || prefix == '' || index(prefix, '/') >= 0)
		return reply_error(request, id, ERROR_INVALID_PARAMS,
			'prefix must be a file name prefix without /');

	let names = filter(lsdir('/tmp') ?? [], (name) => substr(name, 0, length(prefix)) == prefix);

	return reply_success(request, id, { count: length(names), names });
}

const BRIDGE_MCAST_OPTIONS = [
	'multicast_snooping', 'multicast_querier', 'multicast_igmp_version',
	'multicast_mld_version', 'multicast_query_interval'
];

function handle_bridge_multicast(request, id, params) {
	let bridge = params?.bridge;
	if (type(bridge) != 'string' || !match(bridge, /^[A-Za-z0-9._-]+$/))
		return reply_error(request, id, ERROR_INVALID_PARAMS, 'bridge must be a netdev name');

	let dir = `/sys/class/net/${bridge}`;
	if (!lsdir(`${dir}/bridge`))
		return reply_error(request, id, ERROR_INVALID_PARAMS, `${bridge} is not a bridge`);

	let result = { ports: {} };
	for (let opt in BRIDGE_MCAST_OPTIONS)
		result[opt] = trim(readfile(`${dir}/bridge/${opt}`) ?? '');

	for (let port in lsdir(`${dir}/brif`) ?? [])
		result.ports[port] = {
			multicast_fast_leave: trim(readfile(`${dir}/brif/${port}/multicast_fast_leave`) ?? ''),
			multicast_router: trim(readfile(`${dir}/brif/${port}/multicast_router`) ?? '')
		};

	return reply_success(request, id, result);
}

function handle_led_state(request, id, params) {
	let name = params?.name;
	if (type(name) != 'string' || !match(name, /^[A-Za-z0-9:._-]+$/))
		return reply_error(request, id, ERROR_INVALID_PARAMS, 'name must be an LED name');

	let dir = `/sys/class/leds/${name}`;
	let triggers = readfile(`${dir}/trigger`);
	if (triggers == null)
		return reply_error(request, id, ERROR_INVALID_PARAMS, `${name} is not an LED`);

	let active = match(triggers, /\[([^\]]+)\]/);

	return reply_success(request, id, {
		trigger: active ? active[1] : '',
		brightness: trim(readfile(`${dir}/brightness`) ?? '')
	});
}

const USB_DEVICES = '/sys/bus/usb/devices';

/**
 * Reads one sysfs attribute of a USB device or interface, trimmed and in
 * lower case.
 *
 * @param {string} dir - sysfs directory
 * @param {string} name - Attribute name
 * @returns {string} Value, '' when absent
 */
function usb_attr(dir, name) {
	return lc(trim(readfile(`${dir}/${name}`) ?? ''));
}

/**
 * Finds the first USB device that is not a hub.
 *
 * @returns {string|null} sysfs name, for example 1-1
 */
function usb_device_first() {
	for (let name in sort(lsdir(USB_DEVICES) ?? [])) {
		if (!match(name, /^[0-9]+-[0-9.]+$/))
			continue;
		if (usb_attr(`${USB_DEVICES}/${name}`, 'bDeviceClass') == '09')
			continue;
		return name;
	}

	return null;
}

function handle_usb_device(request, id, params) {
	let name = usb_device_first();
	if (!name)
		return reply_error(request, id, ERROR_INVALID_PARAMS, 'no USB device other than a hub');

	let dir = `${USB_DEVICES}/${name}`;
	let iface = sort(filter(lsdir(dir) ?? [], (n) => index(n, ':') > 0))[0];
	let idir = iface ? `${dir}/${iface}` : null;

	return reply_success(request, id, {
		name,
		busnum: usb_attr(dir, 'busnum'),
		devnum: usb_attr(dir, 'devnum'),
		vendor: usb_attr(dir, 'idVendor'),
		product: usb_attr(dir, 'idProduct'),
		class: usb_attr(dir, 'bDeviceClass'),
		subclass: usb_attr(dir, 'bDeviceSubClass'),
		protocol: usb_attr(dir, 'bDeviceProtocol'),
		iface_class: idir ? usb_attr(idir, 'bInterfaceClass') : '',
		iface_subclass: idir ? usb_attr(idir, 'bInterfaceSubClass') : '',
		iface_protocol: idir ? usb_attr(idir, 'bInterfaceProtocol') : '',
		authorized: usb_attr(dir, 'authorized')
	});
}

// Disabling and enabling the port disconnects the device, and the kernel
// enumerates it again with an add uevent, as a replug would.
function handle_usb_port_cycle(request, id, params) {
	let name = params?.name;
	if (type(name) != 'string' || !match(name, /^[0-9]+-[0-9.]+$/))
		return reply_error(request, id, ERROR_INVALID_PARAMS, 'name must be a USB device name');

	// The device directory goes with the device, the port stays.
	let port = realpath(`${USB_DEVICES}/${name}/port`);
	if (!port)
		return reply_error(request, id, ERROR_INVALID_PARAMS, `${name} has no port`);

	let disable = `${port}/disable`;
	if (writefile(disable, '1') == null)
		return reply_error(request, id, ERROR_INTERNAL, `cannot disable the port of ${name}`);

	sleep(1000);
	writefile(disable, '0');
	sleep(3000);

	return reply_success(request, id, { cycled: true });
}

function handle_syslog_unix_send(request, id, params) {
	let path = params?.path;
	let message = params?.message;
	if (type(path) != 'string' || !match(path, /^\/var\/run\/ubbf-syslog\/[A-Za-z0-9._-]+$/))
		return reply_error(request, id, ERROR_INVALID_PARAMS, 'path must be a socket in /var/run/ubbf-syslog/');
	if (type(message) != 'string' || message == '')
		return reply_error(request, id, ERROR_INVALID_PARAMS, 'message is required');

	let sock = socket.create(socket.AF_UNIX, socket.SOCK_DGRAM);
	if (!sock)
		return reply_error(request, id, ERROR_INTERNAL, socket.error());

	let sent = sock.send(message, 0, socket.sockaddr({ path }));
	let err = socket.error();
	sock.close();

	if (!sent)
		return reply_error(request, id, ERROR_INTERNAL, `send to ${path}: ${err}`);

	return reply_success(request, id, { sent });
}

function sysctl_int(path) {
	let v = trim(readfile(path) ?? '');
	return (v == '') ? null : +v;
}

function handle_neigh_state(request, id, params) {
	let iface = params?.interface;
	if (type(iface) != 'string' || !match(iface, /^[A-Za-z0-9._-]+$/))
		return reply_error(request, id, ERROR_INVALID_PARAMS, 'interface must be a netifd interface name');

	let status = ubus.call(`network.interface.${iface}`, 'status', {});
	let dev = status?.l3_device ?? status?.device;
	if (!dev)
		return reply_error(request, id, ERROR_INVALID_PARAMS, `${iface} has no device`);

	let flags = hex(trim(readfile(`/sys/class/net/${dev}/flags`) ?? ''));

	return reply_success(request, id, {
		device: dev,
		noarp: (type(flags) == 'int' && (flags & 0x80)) ? 1 : 0,
		ipv4_reachable_ms: sysctl_int(`/proc/sys/net/ipv4/neigh/${dev}/base_reachable_time_ms`),
		ipv4_retrans_ms: sysctl_int(`/proc/sys/net/ipv4/neigh/${dev}/retrans_time_ms`),
		ipv4_mcast_solicit: sysctl_int(`/proc/sys/net/ipv4/neigh/${dev}/mcast_solicit`),
		ipv4_proxy_arp: sysctl_int(`/proc/sys/net/ipv4/conf/${dev}/proxy_arp`),
		ipv6_reachable_ms: sysctl_int(`/proc/sys/net/ipv6/neigh/${dev}/base_reachable_time_ms`),
		ipv6_retrans_ms: sysctl_int(`/proc/sys/net/ipv6/neigh/${dev}/retrans_time_ms`),
		ipv6_dad_transmits: sysctl_int(`/proc/sys/net/ipv6/conf/${dev}/dad_transmits`)
	});
}

const handlers = {
	'ping': handle_ping,
	'neigh-state': handle_neigh_state,
	'syslog-unix-send': handle_syslog_unix_send,
	'usb-device': handle_usb_device,
	'usb-port-cycle': handle_usb_port_cycle,
	'led-state': handle_led_state,
	'bridge-multicast': handle_bridge_multicast,
	'apply-config': handle_apply_config,
	'dm-set': handle_dm_set,
	'dm-get': handle_dm_get,
	'crash-process': handle_crash_process,
	'service-restart': handle_service_restart,
	'uwsd-conf': handle_uwsd_conf,
	'uwsd-status': handle_uwsd_status,
	'uwsd-kill': handle_uwsd_kill,
	'uwsd-cycle': handle_uwsd_cycle,
	'crash-kernel': handle_crash_kernel,
	'log-message': handle_log_message,
	'tmp-count': handle_tmp_count
};

function dispatch(request, body) {
	let call;

	try {
		call = json(body);
	} catch (e) {
		return reply_error(request, null, ERROR_PARSE, 'Parse error');
	}

	if (type(call) != 'object' || call.jsonrpc != '2.0' ||
	    type(call.method) != 'string')
		return reply_error(request, null, ERROR_INVALID_REQUEST,
				   'Invalid Request');

	let handler = handlers[call.method];
	if (!handler)
		return reply_error(request, call.id, ERROR_METHOD_NOT_FOUND,
				   'Method not found');

	let params = call.params ?? {};
	if (token != '' && params.token != token)
		return reply_error(request, call.id, ERROR_UNAUTHORISED,
				   'token required');

	return handler(request, call.id, params);
}

export function onRequest(request, method, uri) {
	if (method != 'POST' || uri != RPC_URI)
		return request.reply({
			'Status': '404 Not Found',
			'Content-Type': 'text/plain'
		}, 'Not Found');

	request.data({ body: '' });
	return true;
};

export function onBody(request, data) {
	let ctx = request.data();
	if (!ctx || ctx.rejected)
		return false;

	if (data != '') {
		// uwsd delivers the rest of the body after the reply, which must
		// neither run the request nor answer it a second time
		if (length(ctx.body) + length(data) > BODY_MAX) {
			ctx.rejected = true;
			return request.reply({
				'Status': '413 Payload Too Large',
				'Content-Type': 'text/plain'
			}, 'Request too large');
		}

		ctx.body += data;
		return true;
	}

	return dispatch(request, ctx.body);
};
