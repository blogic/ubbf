'use strict';

// Out-of-tree module. `ubbf_module` is the scope datamodel.uc includes this
// file with, and it is visible only while the include runs, so anything the
// handlers below use later has to be bound here. See docs/ARCHITECTURE.md.

const ubbf = ubbf_module.ubbf;
const utils = ubbf_module.utils;
const model = ubbf_module.model;
const operations = ubbf_module.operations;
const members = ubbf_module.members;

const schema = ubbf_module.schema;

const DEFAULT_DATETIME = '0001-01-01T00:00:00Z';

// MAX_MC_COUNT in udpst.h
const MAX_FLOWS = 24;

const INPUT_RANGES = {
	Port: [ 1, 65535 ],
	DSCP: [ 0, 63 ],
	MTU: [ 1250, null ],
	FlowCount: [ 0, MAX_FLOWS ],
	MaximumFlows: [ 0, MAX_FLOWS ],
	MaximumTestBandwidth: [ 0, 32767 ],
	StartSendingRateIndex: [ 0, 11108 ],
	NumberTestSubIntervals: [ 1, 100 ],
	NumberFirstModeTestSubIntervals: [ 0, 100 ],
	TestSubInterval: [ 100, 6000 ],
	StatusFeedbackInterval: [ 5, 250 ],
	SeqErrThresh: [ 0, 100 ],
	LowerThresh: [ 5, 250 ],
	UpperThresh: [ 5, 250 ],
	HighSpeedDelta: [ 2, null ],
	SlowAdjThresh: [ 2, null ]
};

// UDPPayloadContent lists only the contents udpst can send.
const INPUT_ENUMS = {
	Role: [ 'Receiver', 'Sender' ],
	ProtocolVersion: [ 'Any', 'IPv4', 'IPv6' ],
	UDPPayloadContent: [ 'zeroes', 'random' ],
	TestType: [ 'Search', 'Fixed' ],
	RateAdjAlgorithm: [ 'B', 'C' ]
};

const INPUT_BOOLS = [
	'JumboFramesPermitted', 'IPDVEnable', 'ReordDupIgnoreEnable',
	'LocalInterfaceRateIncluded'
];

const SERVER_RE = regexp('^([A-Za-z0-9][A-Za-z0-9.-]*|\\[[0-9A-Fa-f:.]+\\])(:([0-9]+))?$');
const IPV6_RE = regexp('^[0-9A-Fa-f]*:[0-9A-Fa-f:.]*:[0-9A-Fa-f:.]*$');

let test_running = false;

/**
 * Tests whether an input value is absent.
 *
 * @param {*} val - Input value
 * @returns {boolean} True for null or the empty string
 */
function input_absent(val) {
	return val == null || val === '';
}

/**
 * Converts an unsignedInt input to an integer.
 *
 * @param {*} val - Input value
 * @returns {number|null} The integer, or null when the value is absent or
 *          not a decimal number
 */
function uint_parse(val) {
	if (input_absent(val))
		return null;
	if (type(val) == 'int')
		return val >= 0 ? val : null;
	if (!match(sprintf('%s', val), /^[0-9]+$/))
		return null;
	return int(val);
}

/**
 * Returns an unsignedInt input, or a default when it is absent.
 *
 * @param {*} val - Input value, checked by input_check()
 * @param {number} def - Default value
 * @returns {number} Integer value
 */
function uint_default(val, def) {
	return uint_parse(val) ?? def;
}

/**
 * Formats a udpst number as a TR-181 decimal string.
 *
 * @param {number|null} val - Number from the udpst JSON
 * @param {number} digits - Digits after the decimal point
 * @returns {string} The decimal string, or '' when udpst gave no value
 */
function decimal_format(val, digits) {
	if (val == null)
		return '';
	return sprintf(`%.${digits}f`, +val);
}

/**
 * Formats a Mbps value with 2 decimal digits.
 *
 * @param {number|null} val - Number from the udpst JSON
 * @returns {string} Decimal string
 */
function mbps_format(val) {
	return decimal_format(val, 2);
}

/**
 * Formats a ratio or a time in seconds with 9 decimal digits.
 *
 * @param {number|null} val - Number from the udpst JSON
 * @returns {string} Decimal string
 */
function fraction_format(val) {
	return decimal_format(val, 9);
}

/**
 * Returns the test servers from ServerList, or from the obsoleted Host and
 * Port when ServerList is absent.
 *
 * @param {object} input - Operation input
 * @returns {array} Server strings as udpst takes them
 */
function servers_get(input) {
	if (!input_absent(input.ServerList)) {
		let list = (type(input.ServerList) == 'array')
			? input.ServerList : split(input.ServerList, ',');
		return filter(map(list, (s) => trim(sprintf('%s', s))), (s) => s != '');
	}

	if (input_absent(input.Host))
		return [];

	return [ trim(input.Host) ];
}

/**
 * Checks one server of the server list.
 *
 * udpst takes a host name, an IPv4 address or an IPv6 address, each with
 * an optional `:port`, and an IPv6 address with a port in brackets.
 *
 * @param {string} server - Server string
 * @returns {string|null} Error message, or null when the server is valid
 */
function server_check(server) {
	if (match(server, IPV6_RE))
		return null;

	let m = match(server, SERVER_RE);
	if (!m)
		return sprintf('invalid server "%s"', server);

	if (m[3] != null && (int(m[3]) < 1 || int(m[3]) > 65535))
		return sprintf('invalid port in server "%s"', server);

	return null;
}

/**
 * Checks the scalar inputs against their TR-181 ranges and enumerations.
 *
 * @param {object} input - Operation input
 * @returns {string|null} Error message, or null when all values are valid
 */
function input_values_check(input) {
	for (let name, range in INPUT_RANGES) {
		if (input_absent(input[name]))
			continue;

		let val = uint_parse(input[name]);
		if (val == null || val < range[0] || (range[1] != null && val > range[1]))
			return sprintf('%s out of range', name);
	}

	for (let name, values in INPUT_ENUMS) {
		if (input_absent(input[name]))
			continue;
		if (index(values, input[name]) < 0)
			return sprintf('%s value %s not supported', name, input[name]);
	}

	for (let name in INPUT_BOOLS) {
		if (input_absent(input[name]))
			continue;
		if (index([ 'true', 'false', '1', '0', true, false ], input[name]) < 0)
			return sprintf('%s is not a boolean', name);
	}

	return null;
}

/**
 * Checks the operation input before udpst runs.
 *
 * @param {object} input - Operation input
 * @param {array} servers - Servers from servers_get()
 * @returns {string|null} Error message, or null when the input is valid
 */
function input_check(input, servers) {
	if (input_absent(input.Role))
		return 'Role is required';

	if (!length(servers))
		return 'ServerList is required';
	if (length(servers) > MAX_FLOWS)
		return sprintf('ServerList has more than %d servers', MAX_FLOWS);

	for (let server in servers) {
		let err = server_check(server);
		if (err)
			return err;
	}

	let err = input_values_check(input);
	if (err)
		return err;

	// udpst sets the sub-interval in whole seconds, 1 to 10 (-P)
	let sub_interval = uint_default(input.TestSubInterval, 1000);
	if (sub_interval % 1000)
		return 'TestSubInterval must be a multiple of 1000';

	let num_intervals = uint_default(input.NumberTestSubIntervals, 10);
	let total_time = sub_interval * num_intervals / 1000;
	if (total_time < 5 || total_time > 60)
		return sprintf('Test duration must be 5-60 seconds (got %d)', total_time);

	let mode_intervals = uint_default(input.NumberFirstModeTestSubIntervals, 0);
	if (mode_intervals > 0 && mode_intervals >= num_intervals)
		return 'NumberFirstModeTestSubIntervals must be < NumberTestSubIntervals';

	if (input.TestType == 'Fixed' && input_absent(input.StartSendingRateIndex))
		return 'StartSendingRateIndex is required when TestType is Fixed';

	let flows = uint_default(input.FlowCount, 0);
	let max_flows = uint_default(input.MaximumFlows, 0);
	if (max_flows > 0 && (max_flows < flows || max_flows < length(servers)))
		return 'MaximumFlows must not be less than FlowCount or the server count';

	return null;
}

/**
 * Returns the udpst -C value for the flow count inputs.
 *
 * @param {object} input - Operation input
 * @param {number} server_count - Number of servers
 * @returns {string|null} `count` or `count-max`, or null when neither
 *          FlowCount nor MaximumFlows is set
 */
function flows_arg(input, server_count) {
	let flows = uint_default(input.FlowCount, 0);
	let max_flows = uint_default(input.MaximumFlows, 0);

	if (flows == 0 && max_flows == 0)
		return null;

	let count = (flows > 0) ? flows : server_count;
	return (max_flows > 0) ? sprintf('%d-%d', count, max_flows) : sprintf('%d', count);
}

/**
 * Builds the argv list for the udpst binary from TR-471 input.
 * Returns an argv array suitable for cmd_build(), NOT a shell
 * command string: each flag and its value are separate elements
 * so cmd_build can shell-escape user-controlled values.
 *
 * @param {object} input - IPLayerCapacity operation input parameters
 * @param {array} servers - Servers from servers_get()
 * @param {string} iface_name - Resolved interface name or null
 * @returns {array} Argv-style list of command fragments
 */
function udpst_args(input, servers, iface_name) {
	let args = [];

	push(args, (input.Role == 'Receiver') ? '-d' : '-u');

	if (input.ProtocolVersion == 'IPv4')
		push(args, '-4');
	else if (input.ProtocolVersion == 'IPv6')
		push(args, '-6');

	// The udpst server refuses a client whose jumbo and MTU settings
	// differ from its own, so an absent input keeps the udpst sizes
	// instead of the spec defaults (jumbo permitted, MTU 1500).
	if (!ubbf.to_bool(input.JumboFramesPermitted))
		push(args, '-j');

	if (uint_default(input.MTU, 1250) >= 1500)
		push(args, '-T');

	let dscp = uint_default(input.DSCP, 0);
	if (dscp > 0)
		push(args, '-m', dscp << 2);

	if (input.UDPPayloadContent == 'random')
		push(args, '-X');

	if (ubbf.to_bool(input.IPDVEnable))
		push(args, '-o');

	let test_type = input.TestType ?? 'Search';

	let rate_idx = uint_parse(input.StartSendingRateIndex);
	if (rate_idx != null)
		push(args, '-I', (test_type == 'Fixed') ? rate_idx : sprintf('@%d', rate_idx));

	if (!input_absent(input.RateAdjAlgorithm))
		push(args, '-A', input.RateAdjAlgorithm);

	let bandwidth = uint_default(input.MaximumTestBandwidth, 0);
	if (bandwidth > 0)
		push(args, '-B', bandwidth);

	let flows = flows_arg(input, length(servers));
	if (flows)
		push(args, '-C', flows);

	if (iface_name) {
		push(args, '-E', iface_name);
		if (ubbf.to_bool(input.LocalInterfaceRateIncluded ?? 'true'))
			push(args, '-M');
	}

	let port = uint_default(input.Port, 25000);
	if (port != 25000)
		push(args, '-p', port);

	let sub_interval_sec = uint_default(input.TestSubInterval, 1000) / 1000;
	let num_intervals = uint_default(input.NumberTestSubIntervals, 10);
	push(args, '-P', sub_interval_sec);
	push(args, '-t', sub_interval_sec * num_intervals);

	push(args, '-F', uint_default(input.StatusFeedbackInterval, 50));

	let mode_intervals = uint_default(input.NumberFirstModeTestSubIntervals, 0);
	if (mode_intervals > 0)
		push(args, '-i', mode_intervals);

	if (test_type == 'Search') {
		let seq_err = uint_parse(input.SeqErrThresh);
		if (seq_err != null)
			push(args, '-q', seq_err);

		push(args, '-L', uint_default(input.LowerThresh, 30));
		push(args, '-U', uint_default(input.UpperThresh, 90));
		push(args, '-h', uint_default(input.HighSpeedDelta, 10));
		push(args, '-c', uint_default(input.SlowAdjThresh, 3));

		if (!ubbf.to_bool(input.ReordDupIgnoreEnable ?? 'true'))
			push(args, '-R');
	}

	push(args, '-f', 'jsonf', { raw: '--' }, ...servers);

	return args;
}

/**
 * Maps a udpst ErrorStatus to the TR-181 Status of the test.
 *
 * Ranges from udpst.h: 1 to 49 warnings (1 is the server response
 * timeout), 75 to 99 initialisation errors, 100 to 149 setup request
 * errors (104 to 108 authentication), 150 to 199 test activation errors,
 * 200 connection errors, 255 general errors. A failed name lookup has no
 * code of its own, only the message.
 *
 * @param {number} code - udpst ErrorStatus
 * @param {string} message - udpst ErrorMessage
 * @returns {string} TR-181 Status value
 */
function error_status_map(code, message) {
	if (code == 1)
		return 'Error_NoResponse';
	if (code >= 75 && code < 100)
		return 'Error_Internal';
	if (code >= 104 && code <= 108)
		return 'Error_LoginFailed';
	if (code >= 100 && code < 200)
		return 'Error_RejectedByRemote';
	if (code == 200)
		return 'Error_InitConnectionFailed';
	if (index(message ?? '', 'GETADDRINFO ERROR') == 0)
		return 'Error_CannotResolveHostName';
	return 'Error_Other';
}

/**
 * Builds the output of a test that produced no results. Both tables are
 * empty, so a stored result of an earlier run does not remain.
 *
 * @param {string} status - TR-181 Status value
 * @param {number} code - udpst status code
 * @param {string} message - udpst message
 * @returns {object} Output object
 */
function failure_output(status, code, message) {
	return {
		Status: status,
		StatusCode: sprintf('%d', code),
		StatusMessage: message ?? '',
		ModalResultNumberOfEntries: '0',
		IncrementalResultNumberOfEntries: '0'
	};
}

/**
 * Returns the TR-181 values of a result at the maximum, for AtMax and for
 * each ModalResult entry.
 *
 * @param {object} m - udpst AtMax or ModalResult object
 * @returns {object} TR-181 parameters
 */
function at_max_to_object(m) {
	return {
		MaxIPLayerCapacity: mbps_format(m.MaxIPLayerCapacity),
		TimeOfMax: m.TimeOfMax ?? DEFAULT_DATETIME,
		MaxETHCapacityNoFCS: mbps_format(m.MaxETHCapacityNoFCS),
		MaxETHCapacityWithFCS: mbps_format(m.MaxETHCapacityWithFCS),
		MaxETHCapacityWithFCSVLAN: mbps_format(m.MaxETHCapacityWithFCSVLAN),
		LossRatioAtMax: fraction_format(m.LossRatioAtMax),
		RTTRangeAtMax: fraction_format(m.RTTRangeAtMax),
		PDVRangeAtMax: fraction_format(m.PDVRangeAtMax),
		MinOnewayDelayAtMax: fraction_format(m.MinOnewayDelayAtMax),
		ReorderedRatioAtMax: fraction_format(m.ReorderedRatioAtMax),
		ReplicatedRatioAtMax: fraction_format(m.ReplicatedRatioAtMax),
		InterfaceEthMbpsAtMax: mbps_format(m.InterfaceEthMbps)
	};
}

/**
 * Returns the TR-181 values of one sub-interval.
 *
 * @param {object} r - udpst IncrementalResult entry
 * @returns {object} TR-181 parameters
 */
function incremental_to_object(r) {
	return {
		IPLayerCapacity: mbps_format(r.IPLayerCapacity),
		TimeOfSubInterval: r.TimeOfSubInterval ?? DEFAULT_DATETIME,
		LossRatio: fraction_format(r.LossRatio),
		RTTRange: fraction_format(r.RTTRange),
		PDVRange: fraction_format(r.PDVRange),
		MinOnewayDelay: fraction_format(r.MinOnewayDelay),
		ReorderedRatio: fraction_format(r.ReorderedRatio),
		ReplicatedRatio: fraction_format(r.ReplicatedRatio),
		InterfaceEthMbps: mbps_format(r.InterfaceEthMbps)
	};
}

/**
 * Adds the rows of a result table to the output as dotted keys.
 *
 * @param {object} output - Output object to fill
 * @param {string} table - Table name
 * @param {array} rows - udpst entries
 * @param {function} to_object - Converter of one entry
 */
function table_add(output, table, rows, to_object) {
	for (let i = 0; i < length(rows); i++)
		for (let name, value in to_object(rows[i]))
			output[sprintf('%s.%d.%s', table, i + 1, name)] = value;

	output[table + 'NumberOfEntries'] = sprintf('%d', length(rows));
}

/**
 * Parses the udpst JSON of a test into TR-471 result format.
 *
 * @param {object} result - Parsed udpst JSON
 * @returns {object} IPLayerCapacity output
 */
function result_to_output(result) {
	let code = result.ErrorStatus ?? 255;
	let message = join(' / ', filter([ result.ErrorMessage, result.ErrorMessage2 ],
		(m) => m != null && m != ''));
	let out = result.Output;

	if (code != 0)
		utils.logging.log_err('iplayercap: udpst error %d: %s', code, message);

	// A warning (1 to 49) still comes with the results of the test.
	if (!out || code >= 50)
		return failure_output(error_status_map(code, result.ErrorMessage), code, message);

	let atmax = out.AtMax ?? {};
	let summary = out.Summary ?? {};
	let output = {
		Status: (code == 0) ? 'Complete' : error_status_map(code, result.ErrorMessage),
		StatusCode: sprintf('%d', code),
		StatusMessage: message,
		BOMTime: out.BOMTime ?? DEFAULT_DATETIME,
		EOMTime: out.EOMTime ?? DEFAULT_DATETIME,
		TmaxUsed: sprintf('%d', out.TmaxUsed ?? 0),
		TestInterval: sprintf('%d', out.TestInterval ?? 0),
		TmaxRTTUsed: sprintf('%d', out.TmaxRTTUsed ?? 0),
		TimestampResolutionUsed: sprintf('%d', out.TimestampResolutionUsed ?? 0),
		...at_max_to_object(atmax),
		RTTMinAtMax: fraction_format(atmax.RTTMin),
		RTTMaxAtMax: fraction_format(atmax.RTTMax),
		ActiveFlows: sprintf('%d', atmax.ActiveConnections ?? 0),
		IPLayerCapacitySummary: mbps_format(summary.IPLayerCapacitySummary),
		LossRatioSummary: fraction_format(summary.LossRatioSummary),
		RTTRangeSummary: fraction_format(summary.RTTRangeSummary),
		PDVRangeSummary: fraction_format(summary.PDVRangeSummary),
		MinOnewayDelaySummary: fraction_format(summary.MinOnewayDelaySummary),
		MinRTTSummary: fraction_format(summary.MinRTTSummary),
		ReorderedRatioSummary: fraction_format(summary.ReorderedRatioSummary),
		ReplicatedRatioSummary: fraction_format(summary.ReplicatedRatioSummary),
		InterfaceEthMbpsSummary: mbps_format(summary.InterfaceEthMbps)
	};

	table_add(output, 'ModalResult', out.ModalResult ?? [], at_max_to_object);
	table_add(output, 'IncrementalResult', out.IncrementalResult ?? [], incremental_to_object);

	return output;
}

/**
 * Completes the operation with the result of a finished udpst run.
 *
 * udpst writes a configuration error (exit status 50 to 74) as text, not
 * as JSON; input_check() covers the TR-181 limits, so such an error is a
 * limit of udpst itself and goes back as an invalid argument.
 *
 * @param {object} result - popen_async() result
 * @param {number} instance - Operation instance
 * @param {function} complete - Completion callback
 */
function run_complete(result, instance, complete) {
	utils.logging.log_debug('iplayercap: output:\n%s', result.data ?? '');

	if (result.error) {
		complete(instance, USP_ERR_COMMAND_FAILURE, result.error, {});
		return;
	}

	let parsed;
	try {
		parsed = json(result.data ?? '');
	} catch (e) {
		parsed = null;
	}

	let text = trim(result.data ?? '');
	if (type(parsed) != 'object' && result.exitcode >= 50 && result.exitcode < 75) {
		utils.logging.log_err('iplayercap: udpst refused the input: %s', text);
		complete(instance, USP_ERR_INVALID_ARGUMENTS, text, {});
		return;
	}

	let output;
	if (type(parsed) == 'object') {
		output = result_to_output(parsed);
	} else {
		utils.logging.log_err('iplayercap: no JSON from udpst (exit %d): %s', result.exitcode, text);
		output = failure_output('Error_Internal', result.exitcode ?? 255, text);
	}

	utils.logging.log_info('iplayercap: complete status=%s', output.Status);
	complete(instance, 0, null, output);
}

/**
 * Async handler for Device.IP.Diagnostics.IPLayerCapacity operation.
 *
 * udpst cannot bind to an interface: `Interface` names the interface whose
 * counters it reads (-E, and -M with LocalInterfaceRateIncluded), and the
 * test traffic follows the routing table.
 *
 * @param {object} input - Input parameters with ServerList, Role and test configuration
 * @param {number} instance - Operation instance
 * @param {function} complete - Completion callback
 * @param {string} command_key - Command key (unused)
 * @param {object} root - Data model root
 */
function iplayercapacity_handler(input, instance, complete, command_key, root) {
	if (test_running) {
		complete(instance, USP_ERR_COMMAND_FAILURE, 'An IPLayerCapacity test is already running', {});
		return;
	}

	let servers = servers_get(input);
	let err = input_check(input, servers);
	if (err) {
		complete(instance, USP_ERR_INVALID_ARGUMENTS, err, {});
		return;
	}

	let iface_name;
	if (!input_absent(input.Interface)) {
		iface_name = utils.path.interface_resolve(root, input.Interface);
		if (!iface_name) {
			complete(instance, USP_ERR_INVALID_ARGUMENTS, 'Cannot resolve interface', {});
			return;
		}
	}

	let cmd = utils.process.cmd_build([
		{raw: '/usr/bin/udpst'},
		...udpst_args(input, servers, iface_name),
	]);
	utils.logging.log_info('iplayercap: %s', cmd);

	test_running = true;
	let task = utils.process.popen_async(cmd, (result) => {
		test_running = false;
		run_complete(result, instance, complete);
	});

	if (!task)
		test_running = false;
}

model['Device.IP.Diagnostics.IPLayerCapacity'] = {
	schema: schema('IPLayerCapacity'),
	get: (ctx) => ubbf.ctx_config(ctx)
};

model['Device.IP.Diagnostics.IPLayerCapacity.ModalResult'] = {};

model['Device.IP.Diagnostics.IPLayerCapacity.ModalResult.{i}'] = {
	schema: schema('ModalResult')
};

model['Device.IP.Diagnostics.IPLayerCapacity.IncrementalResult'] = {};

model['Device.IP.Diagnostics.IPLayerCapacity.IncrementalResult.{i}'] = {
	schema: schema('IncrementalResult')
};

members['Device.IP.Diagnostics'] = schema('Diagnostics_Commands');

operations['Device.IP.Diagnostics.IPLayerCapacity()'] = {
	type: 'async',
	handler: iplayercapacity_handler,
	store_results: 'Device.IP.Diagnostics.IPLayerCapacity',
	output_key_map: { Status: 'DiagnosticsState' }
};
