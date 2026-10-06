'use strict';

// Out-of-tree module. `ubbf_module` is the scope datamodel.uc includes this
// file with, and it is visible only while the include runs, so anything the
// handlers below use later has to be bound here. See docs/ARCHITECTURE.md.

const ubbf = ubbf_module.ubbf;
const model = ubbf_module.model;
const operations = ubbf_module.operations;
const logging = ubbf_module.utils.logging;

const ubus = require('ubus');

const schema = ubbf_module.schema;

const AGENT_STATES = {
	idle: 'Idle',
	connecting: 'Connecting',
	connected: 'Connected',
	active: 'Active'
};

const BOOLEAN_VALUES = [ 'true', 'false', '1', '0' ];

/**
 * Get handler for Device.X_UBBF.UPTY.
 *
 * @param {object} ctx - Handler context with the stored object
 * @returns {object} Enable, Status mapped from the agent's own state names,
 *   and the reason of the last failed session
 */
function upty_get(ctx) {
	let enable = ctx.config?.Enable ?? 'true';
	let status = ubus.call('upty', 'status');

	if (!status)
		return { Enable: enable, Status: 'Unavailable', LastError: '' };

	let state = status.enabled ? (AGENT_STATES[status.state] ?? 'Unavailable') : 'Disabled';

	return {
		Enable: enable,
		Status: state,
		LastError: status.last_error ?? ''
	};
}

/**
 * Sync handler for Device.X_UBBF.UPTY.StartSession().
 *
 * Hands the token and server URL to the agent, which dials out. AllowInsecure
 * and CACert are forwarded only when given; the agent permits plaintext only
 * where its own configuration allows it.
 *
 * Input that the agent refuses is a USP error. A refusal for another reason
 * (disabled, busy, agent not reachable) comes back as Status 'Error' with a
 * Message, so the controller can show it.
 *
 * @param {object} input - Token, URL, optional AllowInsecure and CACert
 * @param {string} command_key - Command key of the controller
 * @param {object} root - Configuration tree
 * @returns {object|number} Status 'Started' or 'Error' with a Message, or a
 *   negative USP error code
 */
function start_session_handler(input, command_key, root) {
	let args = {
		token: input?.Token,
		url: input?.URL,
		command_key: command_key ?? ''
	};

	if (input?.AllowInsecure != null) {
		if (index(BOOLEAN_VALUES, lc(`${input.AllowInsecure}`)) < 0) {
			logging.log_warn('upty: StartSession() AllowInsecure is not a boolean');
			return -USP_ERR_INVALID_COMMAND_ARGS;
		}
		args.allow_insecure = ubbf.to_bool(input.AllowInsecure);
	}

	if (input?.CACert)
		args.ca_cert = input.CACert;

	let result = ubus.call('upty', 'start', args);

	if (!result)
		return { Status: 'Error', Message: 'upty agent not reachable: ' + (ubus.error() ?? 'unknown error') };

	if (result.invalid) {
		logging.log_warn('upty: StartSession() refused: %s', result.error);
		return -USP_ERR_INVALID_COMMAND_ARGS;
	}

	if (result.error)
		return { Status: 'Error', Message: result.error };

	return { Status: 'Started', Message: '' };
}

model['Device.X_UBBF.UPTY'] = {
	schema: schema('UPTY'),
	get: upty_get
};

operations['Device.X_UBBF.UPTY.StartSession()'] = {
	type: 'sync',
	handler: start_session_handler
};
