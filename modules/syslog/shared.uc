'use strict';

// Included with { syslog } as the scope by handler.uc in the agent and by
// render.uc in apply, so the set-time checks and the render accept the same
// values. Each function is added to that object.

const ubbf = require('ubbf');

const LOG_DIR = '/var/log/';
const SOCKET_DIR = '/var/run/ubbf-syslog/';

/**
 * Trims surrounding whitespace and `[`/`]` brackets from a TR-181 list
 * literal so callers see a bare comma-separated payload.
 *
 * @param {string} value - Raw TR-181 list value
 * @returns {string} Trimmed payload
 */
function trim_list(value) {
	if (type(value) != 'string')
		return '';
	let v = trim(value);
	if (length(v) >= 2 && substr(v, 0, 1) == '[' && substr(v, length(v) - 1) == ']')
		v = trim(substr(v, 1, length(v) - 2));
	return v;
}

/**
 * Splits a TR-181 list value into trimmed non-empty tokens.
 *
 * @param {string} value - TR-181 list value (optionally bracketed)
 * @returns {array} Tokens with surrounding whitespace removed
 */
function split_list(value) {
	let v = trim_list(value);
	if (v == '')
		return [];
	let out = [];
	for (let part in split(v, ',')) {
		let t = trim(part);
		if (t != '')
			push(out, t);
	}
	return out;
}

/**
 * Returns the instance number of a reference to a row of a Syslog table.
 *
 * @param {string} table - Table name: Source, Filter, Template or Action
 * @param {string} ref - TR-181 path such as `Device.Syslog.Source.3`
 * @returns {number|null} Instance number, or null for a row of another table
 */
function ref_instance(table, ref) {
	if (type(ref) != 'string')
		return null;
	let m = match(ref, regexp(`^Device\\.Syslog\\.${table}\\.([0-9]+)\\.?$`));
	return m ? +m[1] : null;
}

/**
 * Returns the absolute path of a local file URI (RFC 8089).
 *
 * @param {string} uri - `file:///path` or `file://localhost/path`
 * @returns {string|null} The path, or null for another URI
 */
function uri_file_path(uri) {
	// ucode regexps match $ at the end of each line
	if (type(uri) != 'string' || index(uri, '\n') >= 0)
		return null;

	let m = match(uri, /^file:\/\/(localhost)?(\/.*)$/);
	return m ? m[2] : null;
}

/**
 * Returns the file path of a LogFile.FilePath. TR-181 asks for a file URI
 * (RFC 8089). The path must lie below /var/log, because ubbf-logd writes
 * the file as root and the controller chooses the path.
 *
 * @param {string} uri - `file:///var/log/...` or `file://localhost/var/log/...`
 * @returns {string|null} The path, or null when the value is not accepted
 */
function logfile_path(uri) {
	let path = uri_file_path(uri);
	if (path == null)
		return null;

	if (substr(path, 0, length(LOG_DIR)) != LOG_DIR || length(path) == length(LOG_DIR))
		return null;

	for (let part in split(substr(path, length(LOG_DIR)), '/'))
		if (part == '' || part == '.' || part == '..')
			return null;

	return path;
}

/**
 * Converts a Source.{i}.UnixDomainSocket.Path URI to the socket path. Only
 * one file name directly in SOCKET_DIR is accepted: ubbf-logd runs as root
 * in a jail that mounts this directory writable. ubbf-logd checks the path
 * again.
 *
 * @param {string} uri - `file:///var/run/ubbf-syslog/<name>`, also with
 *   `localhost` as the host
 * @returns {string|null} The path, or null when the value is not accepted
 */
function socket_path(uri) {
	let path = uri_file_path(uri);
	if (path == null)
		return null;

	let name = substr(path, length(SOCKET_DIR));
	if (substr(path, 0, length(SOCKET_DIR)) != SOCKET_DIR || name == '' || index(name, '/') >= 0)
		return null;

	// sun_path of struct sockaddr_un holds 108 bytes with the terminator
	if (name == '.' || name == '..' || length(path) > 107)
		return null;

	return path;
}

/**
 * Tells whether an action writes somewhere: an enabled LogFile with an
 * accepted path, or an enabled LogRemote with an address.
 *
 * @param {object} action - Action row
 * @returns {boolean} True when the action has a destination
 */
function action_has_destination(action) {
	let lf = action?.LogFile;
	let lr = action?.LogRemote;

	if (lf && ubbf.to_bool(lf.Enable) && logfile_path(lf.FilePath))
		return true;

	return !!(lr && ubbf.to_bool(lr.Enable) && (lr.Address ?? '') != '');
}

syslog.LOG_DIR = LOG_DIR;
syslog.SOCKET_DIR = SOCKET_DIR;
syslog.socket_path = socket_path;
syslog.split_list = split_list;
syslog.ref_instance = ref_instance;
syslog.logfile_path = logfile_path;
syslog.action_has_destination = action_has_destination;
