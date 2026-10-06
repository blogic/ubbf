'use strict';

import { popen_async, cmd_build } from 'ubbf.utils.process';
import { interface_resolve } from 'ubbf.utils.path';
import { log_info, log_debug, log_err } from 'ubbf.utils.logging';
import * as ubbf from 'ubbf';

const DEFAULT_DATETIME = '0001-01-01T00:00:00.000000Z';

/**
 * Returns integer value or default if null/empty.
 *
 * @param {*} val - Value to convert to integer
 * @param {number} def - Default value if val is null or empty
 * @returns {number} Integer value or default
 */
function int_default(val, def) {
	if (val == null || val === '')
		return def;
	return int(val);
}

export const IPLayerCapacity_schema = {
	path: 'Device.IP.Diagnostics.IPLayerCapacity.',
	schema: {
		'DiagnosticsState': dm_type.STRING | dm_type.WRITABLE,
		'Interface': dm_type.STRING | dm_type.WRITABLE,
		'Role': dm_type.STRING | dm_type.WRITABLE,
		'Host': dm_type.STRING | dm_type.WRITABLE,
		'Port': dm_type.UINT | dm_type.WRITABLE,
		'JumboFramesPermitted': dm_type.BOOL | dm_type.WRITABLE,
		'DSCP': dm_type.UINT | dm_type.WRITABLE,
		'ProtocolVersion': dm_type.STRING | dm_type.WRITABLE,
		'UDPPayloadContent': dm_type.STRING | dm_type.WRITABLE,
		'TestType': dm_type.STRING | dm_type.WRITABLE,
		'IPDVEnable': dm_type.BOOL | dm_type.WRITABLE,
		'StartSendingRateIndex': dm_type.UINT | dm_type.WRITABLE,
		'NumberTestSubIntervals': dm_type.UINT | dm_type.WRITABLE,
		'NumberFirstModeTestSubIntervals': dm_type.UINT | dm_type.WRITABLE,
		'TestSubInterval': dm_type.UINT | dm_type.WRITABLE,
		'StatusFeedbackInterval': dm_type.UINT | dm_type.WRITABLE,
		'SeqErrThresh': dm_type.UINT | dm_type.WRITABLE,
		'ReordDupIgnoreEnable': dm_type.BOOL | dm_type.WRITABLE,
		'LowerThresh': dm_type.UINT | dm_type.WRITABLE,
		'UpperThresh': dm_type.UINT | dm_type.WRITABLE,
		'HighSpeedDelta': dm_type.UINT | dm_type.WRITABLE,
		'SlowAdjThresh': dm_type.UINT | dm_type.WRITABLE,
		'RateAdjAlgorithm': dm_type.STRING | dm_type.WRITABLE,

		'BOMTime': dm_type.DATETIME,
		'EOMTime': dm_type.DATETIME,
		'TmaxUsed': dm_type.UINT,
		'TestInterval': dm_type.UINT,
		'TmaxRTTUsed': dm_type.UINT,
		'TimestampResolutionUsed': dm_type.UINT,

		'MaxIPLayerCapacity': dm_type.STRING,
		'TimeOfMax': dm_type.DATETIME,
		'MaxETHCapacityNoFCS': dm_type.STRING,
		'MaxETHCapacityWithFCS': dm_type.STRING,
		'MaxETHCapacityWithFCSVLAN': dm_type.STRING,
		'LossRatioAtMax': dm_type.STRING,
		'RTTRangeAtMax': dm_type.STRING,
		'PDVRangeAtMax': dm_type.STRING,
		'MinOnewayDelayAtMax': dm_type.STRING,
		'ReorderedRatioAtMax': dm_type.STRING,
		'ReplicatedRatioAtMax': dm_type.STRING,
		'InterfaceEthMbpsAtMax': dm_type.STRING,

		'IPLayerCapacitySummary': dm_type.STRING,
		'LossRatioSummary': dm_type.STRING,
		'RTTRangeSummary': dm_type.STRING,
		'PDVRangeSummary': dm_type.STRING,
		'MinOnewayDelaySummary': dm_type.STRING,
		'MinRTTSummary': dm_type.STRING,
		'ReorderedRatioSummary': dm_type.STRING,
		'ReplicatedRatioSummary': dm_type.STRING,
		'InterfaceEthMbpsSummary': dm_type.STRING,

		'ModalResultNumberOfEntries': dm_type.UINT,
		'IncrementalResultNumberOfEntries': dm_type.UINT,

		'IPLayerCapacity()': {
			type: 'async',
			input: [
				'Interface', 'Role', 'Host', 'Port', 'JumboFramesPermitted',
				'DSCP', 'ProtocolVersion', 'UDPPayloadContent', 'TestType',
				'IPDVEnable', 'StartSendingRateIndex', 'NumberTestSubIntervals',
				'NumberFirstModeTestSubIntervals', 'TestSubInterval',
				'StatusFeedbackInterval', 'SeqErrThresh', 'ReordDupIgnoreEnable',
				'LowerThresh', 'UpperThresh', 'HighSpeedDelta', 'SlowAdjThresh',
				'RateAdjAlgorithm'
			],
			output: [
				'Status', 'BOMTime', 'EOMTime', 'TmaxUsed', 'TestInterval',
				'TmaxRTTUsed', 'TimestampResolutionUsed', 'MaxIPLayerCapacity',
				'TimeOfMax', 'MaxETHCapacityNoFCS', 'MaxETHCapacityWithFCS',
				'MaxETHCapacityWithFCSVLAN', 'LossRatioAtMax', 'RTTRangeAtMax',
				'PDVRangeAtMax', 'MinOnewayDelayAtMax', 'ReorderedRatioAtMax',
				'ReplicatedRatioAtMax', 'InterfaceEthMbpsAtMax',
				'IPLayerCapacitySummary', 'LossRatioSummary', 'RTTRangeSummary',
				'PDVRangeSummary', 'MinOnewayDelaySummary', 'MinRTTSummary',
				'ReorderedRatioSummary', 'ReplicatedRatioSummary',
				'InterfaceEthMbpsSummary'
			]
		}
	},
	defaults: {
		'DiagnosticsState': 'None',
		'Interface': '',
		'Role': '',
		'Host': '',
		'Port': '25000',
		'JumboFramesPermitted': '',
		'DSCP': '',
		'ProtocolVersion': '',
		'UDPPayloadContent': '',
		'TestType': 'Search',
		'IPDVEnable': '',
		'StartSendingRateIndex': '',
		'NumberTestSubIntervals': '10',
		'NumberFirstModeTestSubIntervals': '',
		'TestSubInterval': '1000',
		'StatusFeedbackInterval': '50',
		'SeqErrThresh': '',
		'ReordDupIgnoreEnable': '',
		'LowerThresh': '30',
		'UpperThresh': '90',
		'HighSpeedDelta': '10',
		'SlowAdjThresh': '3',
		'RateAdjAlgorithm': '',
		'BOMTime': '0001-01-01T00:00:00Z',
		'EOMTime': '0001-01-01T00:00:00Z',
		'TmaxUsed': '0',
		'TestInterval': '0',
		'TmaxRTTUsed': '0',
		'TimestampResolutionUsed': '0',
		'MaxIPLayerCapacity': '0',
		'TimeOfMax': '0001-01-01T00:00:00Z',
		'MaxETHCapacityNoFCS': '0',
		'MaxETHCapacityWithFCS': '0',
		'MaxETHCapacityWithFCSVLAN': '0',
		'LossRatioAtMax': '0',
		'RTTRangeAtMax': '0',
		'PDVRangeAtMax': '0',
		'MinOnewayDelayAtMax': '0',
		'ReorderedRatioAtMax': '0',
		'ReplicatedRatioAtMax': '0',
		'InterfaceEthMbpsAtMax': '0',
		'IPLayerCapacitySummary': '0',
		'LossRatioSummary': '0',
		'RTTRangeSummary': '0',
		'PDVRangeSummary': '0',
		'MinOnewayDelaySummary': '0',
		'MinRTTSummary': '0',
		'ReorderedRatioSummary': '0',
		'ReplicatedRatioSummary': '0',
		'InterfaceEthMbpsSummary': '0',
		'ModalResultNumberOfEntries': '0',
		'IncrementalResultNumberOfEntries': '0'
	}
};

export const ModalResult_schema = {
	path: 'Device.IP.Diagnostics.IPLayerCapacity.ModalResult.{i}.',
	schema: {
		'MaxIPLayerCapacity': dm_type.STRING,
		'TimeOfMax': dm_type.DATETIME,
		'MaxETHCapacityNoFCS': dm_type.STRING,
		'MaxETHCapacityWithFCS': dm_type.STRING,
		'MaxETHCapacityWithFCSVLAN': dm_type.STRING,
		'LossRatioAtMax': dm_type.STRING,
		'RTTRangeAtMax': dm_type.STRING,
		'PDVRangeAtMax': dm_type.STRING,
		'MinOnewayDelayAtMax': dm_type.STRING,
		'ReorderedRatioAtMax': dm_type.STRING,
		'ReplicatedRatioAtMax': dm_type.STRING,
		'InterfaceEthMbpsAtMax': dm_type.STRING
	},
	defaults: {}
};

export const IncrementalResult_schema = {
	path: 'Device.IP.Diagnostics.IPLayerCapacity.IncrementalResult.{i}.',
	schema: {
		'IPLayerCapacity': dm_type.STRING,
		'TimeOfSubInterval': dm_type.DATETIME,
		'LossRatio': dm_type.STRING,
		'RTTRange': dm_type.STRING,
		'PDVRange': dm_type.STRING,
		'MinOnewayDelay': dm_type.STRING,
		'ReorderedRatio': dm_type.STRING,
		'ReplicatedRatio': dm_type.STRING,
		'InterfaceEthMbps': dm_type.STRING
	},
	defaults: {}
};

/**
 * Builds the argv list for the udpst binary from TR-471 input.
 * Returns an argv array suitable for cmd_build(), NOT a shell
 * command string: each flag and its value are separate elements
 * so cmd_build can shell-escape user-controlled values.
 *
 * @param {object} input - IPLayerCapacity operation input parameters
 * @param {string} iface_name - Resolved interface name or null
 * @returns {array} Argv-style list of command fragments
 */
function udpst_args(input, iface_name) {
	let args = [];

	let role = input.Role ?? '';
	push(args, (role == 'Receiver') ? '-d' : '-u');

	let proto = input.ProtocolVersion ?? '';
	if (proto == 'IPv4')
		push(args, '-4');
	else if (proto == 'IPv6')
		push(args, '-6');

	// udpst -j DISABLES jumbo datagram sizes; pass it when jumbo frames
	// are not permitted
	if (!ubbf.to_bool(input.JumboFramesPermitted))
		push(args, '-j');

	let dscp = int(input.DSCP);
	if (dscp > 0) {
		// udpst -m takes the full TOS/TCLASS octet; DSCP is its upper 6 bits
		push(args, '-m', dscp << 2);
	}

	let content = input.UDPPayloadContent ?? '';
	if (content == 'random')
		push(args, '-X');

	if (ubbf.to_bool(input.IPDVEnable))
		push(args, '-o');

	let test_type = input.TestType ?? 'Search';

	let rate_idx = input.StartSendingRateIndex;
	if (rate_idx != null && rate_idx != '') {
		if (test_type == 'Fixed')
			push(args, '-I', int(rate_idx));
		else
			push(args, '-I', sprintf('@%d', int(rate_idx)));
	}

	let algorithm = input.RateAdjAlgorithm ?? '';
	if (algorithm != '')
		push(args, '-A', algorithm);

	if (iface_name)
		push(args, '-E', iface_name);

	let port = int_default(input.Port, 25000);
	if (port != 25000)
		push(args, '-p', port);

	// TestSubInterval is milliseconds (TR-181, 100-6000); udpst -P/-t take
	// whole seconds and ucode / on ints truncates, so 500 ms gave -P 0 -t 0
	let sub_interval_ms = int_default(input.TestSubInterval, 1000);
	let sub_interval_sec = int((sub_interval_ms + 500) / 1000);
	if (sub_interval_sec < 1)
		sub_interval_sec = 1;
	push(args, '-P', sub_interval_sec);

	let num_intervals = int_default(input.NumberTestSubIntervals, 10);
	// derive the total from the ms product; rounding per interval would drift
	let total_time = int((sub_interval_ms * num_intervals) / 1000);
	if (total_time < 1)
		total_time = 1;
	push(args, '-t', total_time);

	let feedback = int_default(input.StatusFeedbackInterval, 50);
	push(args, '-F', feedback);

	let mode_intervals = int(input.NumberFirstModeTestSubIntervals);
	if (mode_intervals > 0 && mode_intervals < num_intervals)
		push(args, '-i', mode_intervals);

	if (test_type == 'Search') {
		let seq_err = input.SeqErrThresh;
		if (seq_err != null && seq_err != '')
			push(args, '-q', int(seq_err));

		push(args, '-L', int_default(input.LowerThresh, 30));
		push(args, '-U', int_default(input.UpperThresh, 90));
		push(args, '-h', int_default(input.HighSpeedDelta, 10));
		push(args, '-c', int_default(input.SlowAdjThresh, 3));

		let dup_ignore = input.ReordDupIgnoreEnable;
		if (dup_ignore != '1' && dup_ignore != 'true')
			push(args, '-R');
	}

	push(args, '-f', 'jsonf');
	push(args, input.Host);

	return args;
}

/**
 * Parses udpst JSON output into TR-471 result format.
 *
 * @param {string} data - Raw JSON output from udpst command
 * @returns {object} Parsed IPLayerCapacity results including status, timing, and metrics
 */
function output_parse(data) {
	let output = {
		Status: 'Error_Other',
		BOMTime: DEFAULT_DATETIME,
		EOMTime: DEFAULT_DATETIME,
		TmaxUsed: '0',
		TestInterval: '0',
		TmaxRTTUsed: '0',
		TimestampResolutionUsed: '0',
		MaxIPLayerCapacity: '',
		TimeOfMax: DEFAULT_DATETIME,
		MaxETHCapacityNoFCS: '',
		MaxETHCapacityWithFCS: '',
		MaxETHCapacityWithFCSVLAN: '',
		LossRatioAtMax: '',
		RTTRangeAtMax: '',
		PDVRangeAtMax: '',
		MinOnewayDelayAtMax: '',
		ReorderedRatioAtMax: '',
		ReplicatedRatioAtMax: '',
		InterfaceEthMbpsAtMax: '',
		IPLayerCapacitySummary: '',
		LossRatioSummary: '',
		RTTRangeSummary: '',
		PDVRangeSummary: '',
		MinOnewayDelaySummary: '',
		MinRTTSummary: '',
		ReorderedRatioSummary: '',
		ReplicatedRatioSummary: '',
		InterfaceEthMbpsSummary: ''
	};

	if (!data)
		return output;

	let result;
	try {
		result = json(data);
	} catch (e) {
		log_err('iplayercap: JSON parse error: %s', e);
		return output;
	}

	if (!result)
		return output;

	if (result.ErrorStatus != 0) {
		log_err('iplayercap: udpst error %d: %s%s%s',
			result.ErrorStatus ?? -1,
			result.ErrorMessage ?? 'no error message',
			result.ErrorMessage2 ? ' / ' : '',
			result.ErrorMessage2 ?? '');
		output.Status = 'Error_Internal';
		return output;
	}

	let out = result.Output;
	if (!out)
		return output;

	output.Status = out.Status ?? 'Complete';
	output.BOMTime = out.BOMTime ?? DEFAULT_DATETIME;
	output.EOMTime = out.EOMTime ?? DEFAULT_DATETIME;
	output.TmaxUsed = sprintf('%d', out.TmaxUsed ?? 0);
	output.TestInterval = sprintf('%d', out.TestInterval ?? 0);
	output.TmaxRTTUsed = sprintf('%d', out.TmaxRTTUsed ?? 0);
	output.TimestampResolutionUsed = sprintf('%d', out.TimestampResolutionUsed ?? 0);

	let atmax = out.AtMax;
	if (atmax) {
		output.MaxIPLayerCapacity = atmax.MaxIPLayerCapacity ?? '';
		output.TimeOfMax = atmax.TimeOfMax ?? DEFAULT_DATETIME;
		output.MaxETHCapacityNoFCS = atmax.MaxETHCapacityNoFCS ?? '';
		output.MaxETHCapacityWithFCS = atmax.MaxETHCapacityWithFCS ?? '';
		output.MaxETHCapacityWithFCSVLAN = atmax.MaxETHCapacityWithFCSVLAN ?? '';
		output.LossRatioAtMax = atmax.LossRatioAtMax ?? '';
		output.RTTRangeAtMax = atmax.RTTRangeAtMax ?? '';
		output.PDVRangeAtMax = atmax.PDVRangeAtMax ?? '';
		output.MinOnewayDelayAtMax = atmax.MinOnewayDelayAtMax ?? '';
		output.ReorderedRatioAtMax = atmax.ReorderedRatioAtMax ?? '';
		output.ReplicatedRatioAtMax = atmax.ReplicatedRatioAtMax ?? '';
		output.InterfaceEthMbpsAtMax = atmax.InterfaceEthMbps ?? '';
	}

	let summary = out.Summary;
	if (summary) {
		output.IPLayerCapacitySummary = summary.IPLayerCapacitySummary ?? '';
		output.LossRatioSummary = summary.LossRatioSummary ?? '';
		output.RTTRangeSummary = summary.RTTRangeSummary ?? '';
		output.PDVRangeSummary = summary.PDVRangeSummary ?? '';
		output.MinOnewayDelaySummary = summary.MinOnewayDelaySummary ?? '';
		output.MinRTTSummary = summary.MinRTTSummary ?? '';
		output.ReorderedRatioSummary = summary.ReorderedRatioSummary ?? '';
		output.ReplicatedRatioSummary = summary.ReplicatedRatioSummary ?? '';
		output.InterfaceEthMbpsSummary = summary.InterfaceEthMbps ?? '';
	}

	let modal = out.ModalResult;
	if (modal && length(modal) > 0) {
		for (let i = 0; i < length(modal); i++) {
			let m = modal[i];
			let prefix = sprintf('ModalResult.%d.', i + 1);
			output[prefix + 'MaxIPLayerCapacity'] = m.MaxIPLayerCapacity ?? '';
			output[prefix + 'TimeOfMax'] = m.TimeOfMax ?? DEFAULT_DATETIME;
			output[prefix + 'MaxETHCapacityNoFCS'] = m.MaxETHCapacityNoFCS ?? '';
			output[prefix + 'MaxETHCapacityWithFCS'] = m.MaxETHCapacityWithFCS ?? '';
			output[prefix + 'MaxETHCapacityWithFCSVLAN'] = m.MaxETHCapacityWithFCSVLAN ?? '';
			output[prefix + 'LossRatioAtMax'] = m.LossRatioAtMax ?? '';
			output[prefix + 'RTTRangeAtMax'] = m.RTTRangeAtMax ?? '';
			output[prefix + 'PDVRangeAtMax'] = m.PDVRangeAtMax ?? '';
			output[prefix + 'MinOnewayDelayAtMax'] = m.MinOnewayDelayAtMax ?? '';
			output[prefix + 'ReorderedRatioAtMax'] = m.ReorderedRatioAtMax ?? '';
			output[prefix + 'ReplicatedRatioAtMax'] = m.ReplicatedRatioAtMax ?? '';
			output[prefix + 'InterfaceEthMbpsAtMax'] = m.InterfaceEthMbps ?? '';
		}
	}

	let incremental = out.IncrementalResult;
	if (incremental && length(incremental) > 0) {
		for (let i = 0; i < length(incremental); i++) {
			let r = incremental[i];
			let prefix = sprintf('IncrementalResult.%d.', i + 1);
			output[prefix + 'IPLayerCapacity'] = r.IPLayerCapacity ?? '';
			output[prefix + 'TimeOfSubInterval'] = r.TimeOfSubInterval ?? DEFAULT_DATETIME;
			output[prefix + 'LossRatio'] = r.LossRatio ?? '';
			output[prefix + 'RTTRange'] = r.RTTRange ?? '';
			output[prefix + 'PDVRange'] = r.PDVRange ?? '';
			output[prefix + 'MinOnewayDelay'] = r.MinOnewayDelay ?? '';
			output[prefix + 'ReorderedRatio'] = r.ReorderedRatio ?? '';
			output[prefix + 'ReplicatedRatio'] = r.ReplicatedRatio ?? '';
			output[prefix + 'InterfaceEthMbps'] = r.InterfaceEthMbps ?? '';
		}
	}

	output.ModalResultNumberOfEntries = sprintf('%d', length(modal ?? []));
	output.IncrementalResultNumberOfEntries = sprintf('%d', length(incremental ?? []));

	return output;
}

/**
 * Async handler for Device.IP.Diagnostics.IPLayerCapacity operation.
 *
 * @param {object} input - Input parameters with Host, Role, Port, test configuration
 * @param {number} instance - Operation instance
 * @param {function} complete - Completion callback
 */
export function handler(input, instance, complete, command_key, root) {
	let host = input.Host ?? '';
	if (host == '') {
		complete(instance, USP_ERR_INVALID_ARGUMENTS, 'Host parameter is required', {});
		return;
	}

	let iface = input.Interface ?? '';
	let iface_name;
	if (iface != '') {
		iface_name = interface_resolve(root, iface);
		if (!iface_name) {
			complete(instance, USP_ERR_INVALID_ARGUMENTS, 'Cannot resolve interface', {});
			return;
		}
	}

	let sub_interval = int_default(input.TestSubInterval, 1000);
	let num_intervals = int_default(input.NumberTestSubIntervals, 10);
	let total_time = (sub_interval * num_intervals) / 1000;

	if (total_time < 5 || total_time > 60) {
		complete(instance, USP_ERR_INVALID_ARGUMENTS,
			sprintf('Test duration must be 5-60 seconds (got %d)', total_time), {});
		return;
	}

	let mode_intervals = int(input.NumberFirstModeTestSubIntervals);
	if (mode_intervals > 0 && mode_intervals >= num_intervals) {
		complete(instance, USP_ERR_INVALID_ARGUMENTS,
			'NumberFirstModeTestSubIntervals must be < NumberTestSubIntervals', {});
		return;
	}

	let cmd = cmd_build([
		{raw: '/usr/bin/udpst'},
		...udpst_args(input, iface_name),
	]);
	log_info('iplayercap: %s', cmd);

	popen_async(cmd, (result) => {
		log_debug('iplayercap: output:\n%s', result.data ?? '');

		if (result.error) {
			complete(instance, USP_ERR_COMMAND_FAILURE, result.error, {});
			return;
		}

		let output = output_parse(result.data);

		if (result.exitcode != 0 && output.Status == 'Error_Other')
			output.Status = 'Error_Internal';

		log_info('iplayercap: complete status=%s', output.Status);
		complete(instance, 0, null, output);
	});
};

export const model = {
	'Device.IP.Diagnostics.IPLayerCapacity': {
		schema: IPLayerCapacity_schema,
		get: (ctx) => ubbf.ctx_config(ctx)
	},

	'Device.IP.Diagnostics.IPLayerCapacity.ModalResult': {
	},

	'Device.IP.Diagnostics.IPLayerCapacity.ModalResult.{i}': {
		schema: ModalResult_schema
	},

	'Device.IP.Diagnostics.IPLayerCapacity.IncrementalResult': {
	},

	'Device.IP.Diagnostics.IPLayerCapacity.IncrementalResult.{i}': {
		schema: IncrementalResult_schema
	}
};

export const operations = {
	'Device.IP.Diagnostics.IPLayerCapacity()': {
		type: 'async',
		handler: handler,
		store_results: 'Device.IP.Diagnostics.IPLayerCapacity',
		output_key_map: { Status: 'DiagnosticsState' }
	}
};
