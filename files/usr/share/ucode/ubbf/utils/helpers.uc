'use strict';

/**
 * Formats a UNIX timestamp as an ISO 8601 string in UTC. Returns the
 * TR-181 "unknown time" sentinel `0001-01-01T00:00:00Z` when the input
 * is falsy so callers can safely pass missing/zero fields straight
 * through.
 *
 * @param {number} ts - UNIX timestamp, falsy for the unknown-time sentinel
 * @returns {string} ISO 8601 datetime or the unknown-time sentinel
 */
export function datetime_format(ts) {
	if (!ts)
		return '0001-01-01T00:00:00Z';

	return usp_unix_to_datetime(ts);
};

/**
 * Signals completion of a USP transfer operation.
 *
 * @param {object} ctx - Transfer context with command, command_key, url, etc.
 * @param {string} fault_string - Error message if failed, null if successful
 */
export function transfer_complete(ctx, fault_string) {
	let fault_code = fault_string ? 7000 : 0;
	let event_data = {
		Command: ctx.command,
		CommandKey: ctx.command_key ?? '',
		Requestor: '',
		TransferType: ctx.transfer_type,
		Affected: ctx.obj_path,
		TransferURL: ctx.url,
		StartTime: usp_unix_to_datetime(ctx.start_time),
		CompleteTime: usp_unix_to_datetime(time()),
		FaultCode: fault_code,
		FaultString: fault_string ?? ''
	};

	usp_datamodel_event('Device.LocalAgent.TransferComplete!', event_data);

	let output = {
		MaxRetries: '0',
		StartTime: usp_unix_to_datetime(ctx.start_time),
		CompleteTime: usp_unix_to_datetime(time())
	};

	if (fault_string)
		ctx.complete(ctx.instance, USP_ERR_COMMAND_FAILURE, fault_string, output);
	else
		ctx.complete(ctx.instance, 0, null, output);
};
