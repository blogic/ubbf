'use strict';

// Out-of-tree module. `ubbf_module` is the scope datamodel.uc includes this
// file with, and it is visible only while the include runs, so anything the
// handlers below use later has to be bound here. See docs/ARCHITECTURE.md.

const ubbf = ubbf_module.ubbf;
const utils = ubbf_module.utils;
const model = ubbf_module.model;
const operations = ubbf_module.operations;
const members = ubbf_module.members;

const fs = require('fs');

const schema = ubbf_module.schema;

const CAPTURE_DIR = '/tmp';
const DURATION_DEFAULT_S = 60;
const DURATION_MAX_S = 3600;
const BYTE_COUNT_MAX = 25 * 1024 * 1024;
const BYTE_COUNT_DEFAULT = 5 * 1024 * 1024;
const TMP_RESERVE = 64 * 1024 * 1024;
const PCAP_HEADER_LEN = 24;
const PCAP_RECORD_HEADER_LEN = 16;
const STRING_MAX = 256;
const FILE_TARGET_MAX = 2048;

const PCAP_BYTE_ORDER = {
	a1b2c3d4: 'big',
	a1b23c4d: 'big',
	d4c3b2a1: 'little',
	'4d3cb2a1': 'little'
};

// 0 is a PacketCount stop or the graceful exit of tcpdump on SIGTERM;
// 124 and 143 are the SIGTERM of coreutils and of busybox timeout;
// 141 is the SIGPIPE when head closes the pipe at the byte limit.
const TCPDUMP_RC_OK = [ 0, 124, 141, 143 ];

let capture_active;

/**
 * Reads a little or big endian 32 bit number from a string.
 *
 * @param {string} data - Bytes
 * @param {number} off - Offset of the number
 * @param {boolean} little - True for little endian
 * @returns {number} The number
 */
function u32_at(data, off, little) {
	let b = map([ 0, 1, 2, 3 ], (i) => ord(data, off + i));

	if (little)
		return b[0] | (b[1] << 8) | (b[2] << 16) | (b[3] << 24);

	return (b[0] << 24) | (b[1] << 16) | (b[2] << 8) | b[3];
}

/**
 * Counts the records of a pcap file and drops a trailing partial record.
 *
 * head -c cuts the tcpdump stream at an arbitrary byte, and a reader
 * rejects a record whose captured length runs past the end of the file.
 * The file is read one record header at a time, so memory use does not
 * grow with the file.
 *
 * @param {string} path - pcap file to trim in place
 * @returns {number|null} Number of complete records, or null when the
 *                        file has no pcap header
 */
function pcap_records_trim(path) {
	let f = fs.open(path, 'r+');
	if (!f)
		return null;

	let header = f.read(PCAP_HEADER_LEN);
	let order = (length(header) == PCAP_HEADER_LEN)
		? PCAP_BYTE_ORDER[hexenc(substr(header, 0, 4))] : null;

	if (!order) {
		f.close();
		return null;
	}

	f.seek(0, 2);
	let size = f.tell();
	let off = PCAP_HEADER_LEN;
	let count = 0;

	while (off + PCAP_RECORD_HEADER_LEN <= size) {
		f.seek(off);
		let record = f.read(PCAP_RECORD_HEADER_LEN);
		let next = off + PCAP_RECORD_HEADER_LEN + u32_at(record, 8, order == 'little');
		if (next > size)
			break;
		off = next;
		count++;
	}

	if (off < size)
		f.truncate(off);

	f.close();
	return count;
}

/**
 * Parses an unsignedInt command argument.
 *
 * @param {*} value - Argument value
 * @param {number} fallback - Value for an absent or empty argument
 * @returns {number|null} The number, or null when it is not a number
 */
function uint_parse(value, fallback) {
	if (value == null || value == '')
		return fallback;

	if (type(value) == 'int')
		return value >= 0 ? value : null;

	if (type(value) != 'string' || !match(value, /^[0-9]+$/))
		return null;

	return int(value);
}

/**
 * Resolves the Interface argument to a netdev.
 *
 * A layer 3 row resolves through netifd; a layer 2 row (an Ethernet
 * interface or link, a bridge port, an SSID) has no netifd interface, so
 * its Name is taken as the netdev when that netdev exists.
 *
 * @param {object} root - Root configuration object
 * @param {string} iface - TR-181 interface path
 * @returns {string|null} Netdev name, or null when it cannot be resolved
 */
function capture_device_resolve(root, iface) {
	let name = utils.path.interface_resolve(root, iface);
	if (name)
		return name;

	name = ubbf.navigate_data(root, ubbf.path_to_parts(iface))?.Name;
	if (type(name) != 'string' || !match(name, /^[^\/]+$/))
		return null;

	return fs.stat('/sys/class/net/' + name) ? name : null;
}

/**
 * Checks and normalises the command arguments.
 *
 * @param {object} input - Operation input
 * @param {object} root - Root configuration object
 * @returns {object} `{ args }`, or `{ err, msg }` on a refusal
 */
function capture_args_parse(input, root) {
	let args = {
		iface: input.Interface ?? '',
		format: input.Format ?? 'libpcap',
		duration: uint_parse(input.Duration, DURATION_DEFAULT_S),
		packet_count: uint_parse(input.PacketCount, 0),
		byte_count: uint_parse(input.ByteCount, 0),
		file_target: input.FileTarget ?? '',
		filter_expr: input.FilterExpression ?? '',
		username: input.Username ?? '',
		password: input.Password ?? ''
	};

	let strings = {
		Interface: args.iface,
		FilterExpression: args.filter_expr,
		Username: args.username,
		Password: args.password
	};

	for (let name, value in strings)
		if (type(value) != 'string' || length(value) > STRING_MAX)
			return { err: USP_ERR_INVALID_COMMAND_ARGS, msg: sprintf('%s must be a string of at most %d bytes', name, STRING_MAX) };

	if (type(args.file_target) != 'string' || length(args.file_target) > FILE_TARGET_MAX)
		return { err: USP_ERR_INVALID_COMMAND_ARGS, msg: sprintf('FileTarget must be a string of at most %d bytes', FILE_TARGET_MAX) };

	if (args.format != '' && args.format != 'libpcap')
		return { err: USP_ERR_INVALID_COMMAND_ARGS, msg: 'Only libpcap format is supported' };

	if (args.duration == null || args.duration < 1 || args.duration > DURATION_MAX_S)
		return { err: USP_ERR_INVALID_COMMAND_ARGS, msg: sprintf('Duration must be 1 to %d', DURATION_MAX_S) };

	if (args.packet_count == null)
		return { err: USP_ERR_INVALID_COMMAND_ARGS, msg: 'PacketCount must be an unsignedInt' };

	if (args.byte_count == null || (args.byte_count > 0 && args.byte_count < PCAP_HEADER_LEN) || args.byte_count > BYTE_COUNT_MAX)
		return { err: USP_ERR_INVALID_COMMAND_ARGS, msg: sprintf('ByteCount must be 0 or %d to %d', PCAP_HEADER_LEN, BYTE_COUNT_MAX) };

	if (args.file_target == '')
		return { err: USP_ERR_INVALID_COMMAND_ARGS, msg: 'FileTarget is required' };

	if (!ubbf.transfer_url_validate(args.file_target))
		return { err: USP_ERR_INVALID_COMMAND_ARGS, msg: 'FileTarget must be an HTTP or FTP URL' };

	args.device = 'any';
	if (args.iface != '') {
		args.device = capture_device_resolve(root, args.iface);
		if (!args.device)
			return { err: USP_ERR_INVALID_COMMAND_ARGS, msg: 'Cannot resolve interface' };
	}

	return { args };
}

/**
 * Gives the byte limit of a capture from ByteCount and the free space.
 *
 * Every capture streams through head -c, so the file in tmpfs never grows
 * past this limit, also without a ByteCount.
 *
 * @param {number} byte_count - ByteCount, 0 for none
 * @returns {number|null} The limit, or null when /tmp has no room for it
 */
function capture_limit_get(byte_count) {
	let room = (ubbf.statvfs_info(CAPTURE_DIR)?.free_kib ?? 0) * 1024 - TMP_RESERVE;
	let limit = (byte_count > 0) ? byte_count : min(BYTE_COUNT_DEFAULT, room);

	return (limit >= PCAP_HEADER_LEN && limit <= room) ? limit : null;
}

/**
 * Builds the capture command.
 *
 * The subshell writes the exit status of tcpdump to `files.rc`, because
 * the status of the pipeline is the one of head.
 *
 * @param {object} args - Arguments from capture_args_parse()
 * @param {number} limit - Byte limit
 * @param {object} files - Paths `pcap`, `err` and `rc`
 * @returns {string} Shell command
 */
function capture_command_build(args, limit, files) {
	// libpcap's default interface can be a DSA conduit (mtk tag on
	// eth0) whose link-layer type rejects BPF filter compilation, so
	// there is no capture without -i.
	let cmd = sprintf('( timeout %d tcpdump -w - -i %s', args.duration, ubbf.shell_escape(args.device));

	if (args.packet_count > 0)
		cmd += sprintf(' -c %d', args.packet_count);

	if (args.filter_expr != '')
		cmd += ' ' + ubbf.shell_escape(args.filter_expr);

	return cmd + sprintf(' 2>%s; echo $? >%s ) | head -c %d >%s',
		ubbf.shell_escape(files.err), ubbf.shell_escape(files.rc),
		limit, ubbf.shell_escape(files.pcap));
}

/**
 * Runs the capture and the upload; the child function of task_run().
 *
 * @param {object} args - Arguments from capture_args_parse()
 * @param {string} cmd - Command from capture_command_build()
 * @param {object} files - Paths `pcap`, `err` and `rc`
 * @param {string} command_key - USP command key
 * @returns {object} `{ file_location, start_time, end_time, count }`, or
 *                   `{ error }`
 */
function capture_run(args, cmd, files, command_key) {
	let start_time = ubbf.iso8601_format();

	let p = fs.popen(cmd, 'r');
	if (!p)
		return { error: 'Failed to start tcpdump' };

	p.read('all');
	p.close();

	let end_time = ubbf.iso8601_format();
	let rc = int(trim(fs.readfile(files.rc) ?? ''));

	if (index(TCPDUMP_RC_OK, rc) < 0)
		return { error: sprintf('tcpdump failed (%s): %s', rc, trim(fs.readfile(files.err) ?? '')) };

	let count = pcap_records_trim(files.pcap);
	if (count == null)
		return { error: sprintf('tcpdump wrote no capture: %s', trim(fs.readfile(files.err) ?? '')) };

	let opts = { timeout: ubbf.CURL_TRANSFER_TIMEOUT_S, command_key };
	if (args.username != '')
		opts = { ...opts, username: args.username, password: args.password };
	if (ubbf.curl_insecure_allowed())
		opts.insecure = true;

	let result = ubbf.curl_upload(args.file_target, files.pcap, opts);
	if (!result.success)
		return { error: 'Failed to upload capture file' };

	return { file_location: result.url, start_time, end_time, count };
}

/**
 * Async operation handler for Device.PacketCaptureDiagnostics().
 *
 * @param {object} input - Operation input with Interface, Duration, FileTarget, etc.
 * @param {number} instance - Operation instance identifier
 * @param {function} complete - Callback to signal operation completion
 * @param {string} command_key - USP command key
 * @param {object} root - Root configuration object
 */
function packetcapture_handler(input, instance, complete, command_key, root) {
	let parsed = capture_args_parse(input, root);
	if (parsed.err) {
		complete(instance, parsed.err, parsed.msg, {});
		return;
	}

	let args = parsed.args;

	if (capture_active) {
		complete(instance, USP_ERR_RESOURCES_EXCEEDED, 'A packet capture is already running', {});
		return;
	}

	let limit = capture_limit_get(args.byte_count);
	if (!limit) {
		complete(instance, USP_ERR_RESOURCES_EXCEEDED, 'Not enough free space in /tmp', {});
		return;
	}

	let files = {
		pcap: ubbf.tmpfile_name('packetcapture', '.pcap'),
		err: ubbf.tmpfile_name('packetcapture', '.err'),
		rc: ubbf.tmpfile_name('packetcapture', '.rc')
	};

	let files_remove = () => {
		for (let name, path in files)
			if (path)
				fs.unlink(path);
	};

	if (!files.pcap || !files.err || !files.rc) {
		files_remove();
		complete(instance, USP_ERR_INTERNAL_ERROR, 'Failed to create temp file', {});
		return;
	}

	let cmd = capture_command_build(args, limit, files);

	capture_active = true;

	utils.process.task_run(
		() => capture_run(args, cmd, files, command_key),
		(result) => {
			capture_active = false;
			files_remove();

			if (result.error) {
				ubbf.log_warn('Device.PacketCaptureDiagnostics: %s', result.error);
				complete(instance, USP_ERR_COMMAND_FAILURE, result.error, {});
				return;
			}

			complete(instance, 0, null, {
				Status: 'Complete',
				'PacketCaptureResult.1.FileLocation': result.file_location,
				'PacketCaptureResult.1.StartTime': result.start_time,
				'PacketCaptureResult.1.EndTime': result.end_time,
				'PacketCaptureResult.1.Count': sprintf('%d', result.count)
			});
		},
		{ timeout: args.duration + ubbf.CURL_TRANSFER_TIMEOUT_S + utils.process.TASK_MARGIN_S }
	);
}

members['Device'] = schema('Device_Commands');

operations['Device.PacketCaptureDiagnostics()'] = {
	type: 'async',
	handler: packetcapture_handler
};
