'use strict';

import * as fs from 'fs';
import { log_info, log_debug, log_err } from 'ubbf';
import { task_run, TASK_MARGIN_S } from 'ubbf.utils.process';
import * as ubbf from 'ubbf';
import { netifd_status_get } from 'ubbf.utils.netifd';

/**
 * Parses nslookup command output into structured result.
 *
 * @param {string} data - Raw nslookup output
 * @param {string} dns_server - DNS server used for lookup
 * @returns {object} Parsed result with status, addresses, and response time
 */
function nslookup_parse(data, dns_server) {
	let result = {
		Status: 'Error_Other',
		AnswerType: 'None',
		HostNameReturned: '',
		IPAddresses: '',
		DNSServerIP: dns_server,
		ResponseTime: '0'
	};

	if (!data)
		return result;

	let lines = split(data, '\n');
	let addresses = [];
	let in_answer = false;
	let is_authoritative = false;

	for (let line in lines) {
		line = trim(line);

		if (match(line, /^Server:/)) {
			let m = match(line, /Server:\s*(\S+)/);
			if (m)
				result.DNSServerIP = m[1];
			continue;
		}

		if (match(line, /^Non-authoritative answer/i)) {
			in_answer = true;
			is_authoritative = false;
			continue;
		}

		if (match(line, /^Authoritative answer/i)) {
			in_answer = true;
			is_authoritative = true;
			continue;
		}

		if (match(line, /^Name:/)) {
			let m = match(line, /Name:\s*(\S+)/);
			if (m)
				result.HostNameReturned = m[1];
			continue;
		}

		if (match(line, /^Address.*:/)) {
			if (!result.HostNameReturned)
				continue;
			let m = match(line, /Address[^:]*:\s*(\S+)/);
			// 0.0.0.0 is returned by some resolvers as a sentinel for negative cache hits
			if (m && m[1] != '0.0.0.0')
				push(addresses, m[1]);
			continue;
		}

		if (match(line, /server can.t find|NXDOMAIN|can.t resolve/i)) {
			if (length(addresses) == 0) {
				result.Status = 'Error_DNSServerNotResolved';
				return result;
			}
			continue;
		}

		if (match(line, /connection timed out|no servers could be reached|network unreachable|can.t connect to remote host|^Terminated$/i)) {
			if (length(addresses) == 0) {
				result.Status = 'Error_Timeout';
				return result;
			}
			continue;
		}
	}

	if (length(addresses) > 0) {
		result.IPAddresses = join(',', addresses);
		result.Status = 'Success';
		result.AnswerType = is_authoritative ? 'Authoritative' : 'NonAuthoritative';
	}

	return result;
}

/**
 * Async operation handler for Device.DNS.Diagnostics.NSLookupDiagnostics().
 *
 * @param {object} input - Operation input with HostName, DNSServer, etc.
 * @param {number} instance - Operation instance identifier
 * @param {function} complete - Callback to signal operation completion
 * @param {string} command_key - USP command key
 * @param {object} root - Root configuration object
 */
export function handler(input, instance, complete, command_key, root) {
	let hostname = input.HostName ?? '';
	let dns_server = input.DNSServer ?? '';
	let repetitions = int(input.NumberOfRepetitions) || 1;
	let timeout = int(input.Timeout) || 5000;

	if (hostname == '') {
		complete(instance, USP_ERR_INVALID_ARGUMENTS, 'HostName is required', {});
		return;
	}

	if (repetitions < 1)
		repetitions = 1;

	if (!dns_server && input.Interface) {
		let iface_name = ubbf.get(root, input.Interface)?.Name;
		if (iface_name) {
			let status = netifd_status_get(iface_name);
			let dns_list = status?.['dns-server'];
			if (dns_list && length(dns_list) > 0)
				dns_server = dns_list[0];
		}
	}

	log_info('nslookup: host=%s server=%s repetitions=%d', hostname, dns_server, repetitions);

	let timeout_sec = (timeout + 999) / 1000;

	let cmd_template = sprintf('timeout %d nslookup %s', timeout_sec, ubbf.shell_escape(hostname));
	if (dns_server != '')
		cmd_template += ' ' + ubbf.shell_escape(dns_server);
	cmd_template += ' 2>&1';

	task_run(
		() => {
			let results = [];
			let success_count = 0;

			for (let i = 0; i < repetitions; i++) {
				let cmd = cmd_template;

				log_debug('nslookup: %s', cmd);

				let t0 = clock(true);
				let p = fs.popen(cmd, 'r');

				if (!p) {
					log_err('nslookup: popen failed');
					push(results, {
						Status: 'Error_Other',
						AnswerType: 'None',
						HostNameReturned: '',
						IPAddresses: '',
						DNSServerIP: dns_server,
						ResponseTime: '0'
					});
					continue;
				}

				let data = p.read('all');
				let exitcode = p.close();
				let t1 = clock(true);
				let elapsed_ms = (t1[0] - t0[0]) * 1000 + (t1[1] - t0[1]) / 1000000;

				log_debug('nslookup: exitcode=%d', exitcode);

				let result = nslookup_parse(data, dns_server);
				result.ResponseTime = sprintf('%d', elapsed_ms);

				if (result.Status == 'Success')
					success_count++;

				push(results, result);
			}

			return { results, success_count };
		},
		(result) => {
			if (result.error) {
				log_err('nslookup: %s', result.error);
				complete(instance, USP_ERR_COMMAND_FAILURE, 'Task failed', {});
				return;
			}

			let output = {
				Status: result.success_count > 0 ? 'Complete' : 'Error_Other',
				SuccessCount: sprintf('%d', result.success_count),
				ResultNumberOfEntries: sprintf('%d', length(result.results))
			};

			for (let i = 0; i < length(result.results); i++) {
				let r = result.results[i];
				let idx = i + 1;
				output[sprintf('Result.%d.Status', idx)] = r.Status;
				output[sprintf('Result.%d.AnswerType', idx)] = r.AnswerType;
				output[sprintf('Result.%d.HostNameReturned', idx)] = r.HostNameReturned;
				output[sprintf('Result.%d.IPAddresses', idx)] = r.IPAddresses;
				output[sprintf('Result.%d.DNSServerIP', idx)] = r.DNSServerIP;
				output[sprintf('Result.%d.ResponseTime', idx)] = r.ResponseTime;
			}

			log_info('nslookup: complete status=%s success=%d', output.Status, result.success_count);
			complete(instance, 0, null, output);
		},
		{ timeout: timeout_sec * repetitions + TASK_MARGIN_S }
	);
};
