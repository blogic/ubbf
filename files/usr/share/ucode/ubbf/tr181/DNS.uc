'use strict';

import * as uloop from 'uloop';
import * as fs from 'fs';
import * as schemas from 'ubbf.schemas.DNS';
import { log_info, log_debug, log_err } from 'ubbf.utils.logging';
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
function nslookup_handler(input, instance, complete, command_key, root) {
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

	let called;

	let task = uloop.task(
		(pipe) => {
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

			pipe.send({ results, success_count });
		},
		(result) => {
			// uloop fires the output callback once per pipe.send() and again
			// with null on EOF; complete() must run at most once.
			if (called)
				return;
			called = true;

			if (!result) {
				log_err('nslookup: task returned null');
				complete(instance, USP_ERR_COMMAND_FAILURE, 'Task failed', {});
				return;
			}

			let output = {
				Status: result.success_count > 0 ? 'Complete' : 'Error_Other',
				SuccessCount: sprintf('%d', result.success_count)
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
		}
	);

	if (!task) {
		log_err('nslookup: failed to create task');
		complete(instance, USP_ERR_COMMAND_FAILURE, 'Failed to create task', {});
		return;
	}
}

/**
 * Sync operation handler for Device.DNS.Relay.Config.{i}.FlushCache().
 *
 * @param {object} input - Unused
 * @param {string} command_key - USP command key
 * @returns {object} Empty result object
 */
function flush_cache_handler(input, command_key) {
	system('killall -HUP dnsmasq');
	return {};
}

/**
 * Get handler for Device.DNS.
 *
 * @param {object} ctx - Context with config
 * @returns {object} DNS properties with instance counts
 */
function dns_get(ctx) {
	return {
		...ubbf.ctx_config(ctx),
		ZoneNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config?.Zone))
	};
}

/**
 * Classifies a learned DNS server address by netifd proto and family.
 *
 * odhcp6c merges DHCPv6 OPTION_DNS_SERVERS and RA RDNSS into one
 * `dns-server` list before netifd publishes it. The RA-only addresses
 * are captured by /etc/odhcp6c.user.d/10-ubbf-dns-source and handled
 * by the caller; this function is the fallback classifier for
 * addresses not flagged as RA-sourced.
 *
 * @param {string} address - DNS server literal
 * @param {string} proto - netifd interface proto (dhcp, dhcpv6, static, ...)
 * @returns {string} TR-181 Type string (DHCPv4, DHCPv6, Static)
 */
function dns_server_type_classify(address, proto) {
	let is_ipv4 = !!match(address, /^[0-9.]+$/);
	if (is_ipv4)
		return (proto == 'dhcp' || proto == 'dhcpv4') ? 'DHCPv4' : 'Static';
	return (proto == 'dhcpv6') ? 'DHCPv6' : 'Static';
}

/**
 * Reads the RA-sourced DNS address set for a netifd interface.
 *
 * The state file is written by /etc/odhcp6c.user.d/10-ubbf-dns-source
 * on every odhcp6c event, one address per line, for the interface in
 * $INTERFACE. An absent or empty file yields an empty set.
 *
 * @param {string} iface_name - netifd logical interface (e.g. 'wan6')
 * @returns {object} Map with each RA DNS address as a truthy key
 */
function ra_dns_set_read(iface_name) {
	if (!iface_name)
		return {};
	let data = fs.readfile(sprintf('/tmp/ubbf/ra-dns.%s', iface_name));
	if (!data)
		return {};
	let set = {};
	for (let line in split(data, '\n')) {
		let addr = trim(line);
		if (addr != '')
			set[addr] = true;
	}
	return set;
}

/**
 * Appends one TR-181 Client.Server-shaped record per address in a
 * netifd dns-server list. When `ra_set` is provided, addresses
 * present in it are tagged Type=RouterAdvertisement regardless of
 * the netifd proto classification.
 *
 * @param {array} result - Destination array
 * @param {array} dns_list - netifd status['dns-server']
 * @param {string} proto - netifd interface proto
 * @param {string} iface_ref - TR-181 path of the source interface
 * @param {object} [ra_set] - RA-sourced address set (may be null)
 */
function dns_servers_collect(result, dns_list, proto, iface_ref, ra_set) {
	if (!dns_list || !length(dns_list))
		return;

	for (let addr in dns_list) {
		let dns_type = (ra_set && ra_set[addr])
			? 'RouterAdvertisement'
			: dns_server_type_classify(addr, proto);
		push(result, {
			Enable: 'true',
			Status: 'Enabled',
			Alias: sprintf('%s-%s', proto != '' ? proto : 'learned', addr),
			DNSServer: addr,
			Interface: iface_ref,
			Type: dns_type
		});
	}
}

/**
 * Enumerates DNS servers learned at runtime from netifd interface state.
 *
 * Walks Device.IP.Interface in the runtime tree. For each interface we
 * inspect its netifd status (`name`) for IPv4 DNS. Upstream interfaces
 * also get their sibling IPv6 netifd logical interface (`name + '6'`)
 * inspected, which is where odhcp6c publishes the DHCPv6-OPTION-DNS-
 * SERVERS / RA-RDNSS merged list on a typical OpenWrt WAN setup.
 *
 * @param {object} root - Runtime data model tree (ctx.root)
 * @returns {array} Array of server objects (Enable, Status, Alias, DNSServer, Interface, Type)
 */
function learned_dns_servers_get(root) {
	let interfaces = root?.Device?.IP?.Interface ?? {};
	let result = [];

	for (let inst_key, iface in interfaces) {
		if (!ubbf.is_instance_key(inst_key))
			continue;
		let name = iface?.Name;
		if (!name)
			continue;

		let iface_ref = sprintf('Device.IP.Interface.%d', +inst_key);

		let status = netifd_status_get(name);
		dns_servers_collect(result, status?.['dns-server'],
				    status?.proto ?? '', iface_ref, null);

		if (!ubbf.to_bool(iface.Upstream))
			continue;

		let status6 = netifd_status_get(name + '6');
		if (!status6)
			continue;
		let ra_set = ra_dns_set_read(name + '6');
		dns_servers_collect(result, status6['dns-server'],
				    status6.proto ?? '', iface_ref, ra_set);
	}

	return result;
}

/**
 * Get handler for Device.DNS.Client.Server.
 *
 * Produces dynamic server instances from netifd-learned DNS addresses
 * (DHCPv4 / DHCPv6 / merged-RA). Static instances persisted under the
 * same container are hydrated separately by the framework through the
 * Device.DNS.Client.Server.{i} pattern, so this handler only returns
 * the dynamic tail and never overwrites a static entry. Instance
 * numbers start above the highest static key in ctx.config.
 *
 * @param {object} ctx - Context with config (Server subtree) and root
 * @returns {object} Instance-keyed object with learned entries only
 */
function dns_client_server_get(ctx) {
	let config = ctx.config ?? {};
	let max_static = 0;
	for (let k in keys(config)) {
		if (!ubbf.is_instance_key(k))
			continue;
		let n = +k;
		if (n > max_static)
			max_static = n;
	}

	let dynamic = learned_dns_servers_get(ctx.root);
	let result = {};
	let next = max_static + 1;
	for (let srv in dynamic) {
		result[sprintf('%d', next)] = srv;
		next++;
	}
	return result;
}

/**
 * Get handler for Device.DNS.Client.
 *
 * @param {object} ctx - Context with config
 * @returns {object} DNS client properties with instance counts
 */
function dns_client_get(ctx) {
	let static_count = ubbf.instance_count(ctx.config?.Server);
	let learned_count = length(learned_dns_servers_get(ctx.root));
	return {
		...ubbf.ctx_config(ctx),
		ServerNumberOfEntries: sprintf('%d', static_count + learned_count)
	};
}

/**
 * Enumerates non-upstream Device.IP.Interface instances paired with
 * the TR-181 interface reference.
 *
 * @param {object} root - Runtime data model tree
 * @returns {array} Array of { ref, ipv6 } pairs
 */
function downstream_interfaces_get(root) {
	let interfaces = root?.Device?.IP?.Interface ?? {};
	let out = [];
	for (let inst_key, iface in interfaces) {
		if (!ubbf.is_instance_key(inst_key))
			continue;
		if (ubbf.to_bool(iface?.Upstream))
			continue;
		push(out, {
			ref: sprintf('Device.IP.Interface.%d', +inst_key),
			ipv6: ubbf.to_bool(iface?.IPv6Enable)
		});
	}
	return out;
}

/**
 * Get handler for Device.DNS.Relay.Forwarding.
 *
 * TR-181 semantics for Forwarding.Interface name the DOWNSTREAM
 * listener the relay binds to (mirrored by collect_relay_interfaces
 * in render/templates/dns.uc and dns_relay_collect in firewall-nat.uc).
 * DNS.Client.Server.Interface, by contrast, names the upstream source.
 *
 * For every learned upstream DNS server (via learned_dns_servers_get)
 * and every non-upstream IP.Interface, emit one Forwarding instance
 * with DNSServer=<upstream address>, Interface=<downstream ref> and
 * the learned Type. IPv6 forwarders are skipped on downstreams that
 * have IPv6Enable=false (e.g. Guest on the default initial.json).
 *
 * Static Forwarding entries are hydrated by the Forwarding.{i}
 * framework path; this handler only returns the dynamic tail.
 *
 * @param {object} ctx - Context with config (Forwarding subtree) and root
 * @returns {object} Instance-keyed object with learned entries only
 */
function dns_relay_forwarding_get(ctx) {
	let config = ctx.config ?? {};
	let max_static = 0;
	for (let k in keys(config)) {
		if (!ubbf.is_instance_key(k))
			continue;
		let n = +k;
		if (n > max_static)
			max_static = n;
	}

	let upstream_servers = learned_dns_servers_get(ctx.root);
	let downstreams = downstream_interfaces_get(ctx.root);

	let result = {};
	let next = max_static + 1;
	for (let srv in upstream_servers) {
		let is_ipv6 = (srv.Type == 'DHCPv6' || srv.Type == 'RouterAdvertisement');
		for (let down in downstreams) {
			if (is_ipv6 && !down.ipv6)
				continue;
			result[sprintf('%d', next)] = {
				Enable: 'true',
				Status: 'Enabled',
				Alias: sprintf('%s-%s', srv.Type, down.ref),
				DNSServer: srv.DNSServer,
				Interface: down.ref,
				Type: srv.Type
			};
			next++;
		}
	}
	return result;
}

/**
 * Get handler for Device.DNS.Relay.
 *
 * @param {object} ctx - Context with config
 * @returns {object} DNS relay properties with instance counts
 */
function dns_relay_get(ctx) {
	let static_forwarding = ubbf.instance_count(ctx.config?.Forwarding);
	let upstream_servers = learned_dns_servers_get(ctx.root);
	let downstreams = downstream_interfaces_get(ctx.root);

	let learned_count = 0;
	for (let srv in upstream_servers) {
		let is_ipv6 = (srv.Type == 'DHCPv6' || srv.Type == 'RouterAdvertisement');
		for (let down in downstreams) {
			if (is_ipv6 && !down.ipv6)
				continue;
			learned_count++;
		}
	}

	return {
		...ubbf.ctx_config(ctx),
		ConfigNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config?.Config)),
		ForwardNumberOfEntries: sprintf('%d', static_forwarding + learned_count)
	};
}

/**
 * Get handler for Device.DNS.Zone.{i}.
 *
 * @param {object} ctx - Context with config
 * @returns {object} Zone entry with computed HostNumberOfEntries
 */
function zone_get(ctx) {
	return {
		...ubbf.ctx_config(ctx),
		HostNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config?.Host))
	};
}

export const model = {
	'Device.DNS': {
		schema: schemas.DNS,
		get: dns_get
	},

	'Device.DNS.Client': {
		schema: schemas.Client,
		get: dns_client_get,
		enable_status_derive: true
	},

	'Device.DNS.Client.Server': {
		get: dns_client_server_get
	},

	'Device.DNS.Client.Server.{i}': {
		schema: schemas.Client_Server,
		enable_status_derive: true
	},

	'Device.DNS.Relay': {
		schema: schemas.Relay,
		get: dns_relay_get,
		enable_status_derive: true
	},

	'Device.DNS.Relay.Forwarding': {
		get: dns_relay_forwarding_get
	},

	'Device.DNS.Relay.Forwarding.{i}': {
		schema: schemas.Relay_Forwarding,
		enable_status_derive: true
	},

	'Device.DNS.Relay.Config': {
	},

	'Device.DNS.Relay.Config.{i}': {
		schema: schemas.Relay_Config
	},

	'Device.DNS.Zone': {
	},

	'Device.DNS.Zone.{i}': {
		schema: schemas.Zone,
		get: zone_get
	},

	'Device.DNS.Zone.{i}.Host': {
	},

	'Device.DNS.Zone.{i}.Host.{i}': {
		schema: schemas.Zone_Host
	},

	'Device.DNS.Diagnostics': {
		schema: schemas.Diagnostics
	},

	'Device.DNS.Diagnostics.NSLookupDiagnostics': {
		schema: schemas.NSLookupDiagnostics,
		get: (ctx) => ubbf.ctx_config(ctx)
	},

	'Device.DNS.Diagnostics.NSLookupDiagnostics.Result': {
	},

	'Device.DNS.Diagnostics.NSLookupDiagnostics.Result.{i}': {
		schema: schemas.NSLookupResult
	}
};

export const operations = {
	'Device.DNS.Diagnostics.NSLookupDiagnostics()': {
		type: 'async',
		handler: nslookup_handler
	},

	'Device.DNS.Relay.Config.{i}.FlushCache()': {
		type: 'sync',
		handler: flush_cache_handler
	}
};
