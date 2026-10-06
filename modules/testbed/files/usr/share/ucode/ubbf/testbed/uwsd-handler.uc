'use strict';

// Nothing here imports from ubbf.*: the base tree is minified into the ubbf
// package while a module's files/ subtree ships as written, so an import
// across that boundary would resolve against mangled export names.

import * as uloop from 'uloop';
import * as log from 'log';
import * as ubus from 'ubus';
import { readfile, unlink } from 'fs';

const ERROR_PARSE = -32700;
const ERROR_INVALID_REQUEST = -32600;
const ERROR_METHOD_NOT_FOUND = -32601;
const ERROR_INVALID_PARAMS = -32602;
const ERROR_UNAUTHORISED = -32001;

const TOKEN_PATH = '/etc/ubbf/testbed-rpc.token';
const OUTPUT_PATH = '/tmp/ubbf-testbed-rpc.out';
const RPC_URI = '/rpc';
const BODY_MAX = 32 * 1024;
const SETTLE_TIMEOUT = 30;
const SETTLE_POLL_MS = 250;

const PROFILE_CONFIG_PATH = {
	'Test': '/etc/ubbf/test_config.json',
	'PRPL': '/etc/ubbf/prpl_config.json'
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
 * Waits for the apply that bbf-cli scheduled, then for netifd to bring the
 * interfaces back. The handler reloads netifd itself because the procd
 * trigger of reload_config fires only a second later, and until then the
 * interfaces still look up from before. The trigger then finds no change
 * and causes no second bounce.
 */
function network_settle() {
	let deadline = time() + SETTLE_TIMEOUT;

	if (!wait_until(apply_idle, deadline))
		return false;

	ubus.call('network', 'reload');

	return wait_until(interfaces_settled, deadline);
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
	if (result.success && !network_settle()) {
		result.success = false;
		result.output += sprintf('network did not settle within %ds\n', SETTLE_TIMEOUT);
	}

	return reply_success(request, id, result);
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

const handlers = {
	'ping': handle_ping,
	'apply-config': handle_apply_config,
	'crash-process': handle_crash_process,
	'crash-kernel': handle_crash_kernel,
	'log-message': handle_log_message
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
	if (!ctx)
		return false;

	if (data != '') {
		if (length(ctx.body) + length(data) > BODY_MAX)
			return request.reply({
				'Status': '413 Payload Too Large',
				'Content-Type': 'text/plain'
			}, 'Request too large');

		ctx.body += data;
		return true;
	}

	return dispatch(request, ctx.body);
};
