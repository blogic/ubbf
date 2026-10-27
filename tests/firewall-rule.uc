// Host test of Device.Firewall.Chain.{i}.Rule.{i}: the render of the
// *Exclude flags, the interface excludes and ExpiryDate in
// render/templates/firewall-chains.uc, and the refusal of what fw4 cannot
// express (chain_rule_unsupported() of ubbf.so, the Rule handler in
// tr181/Firewall.uc). Run from the repository root with the native module
// built for the host; tests/hosts/ holds stand-ins for iwinfo and udebug:
//   ucode -L "$PWD/tests/hosts/*.uc" -L "$PWD/files/usr/share/ucode" \
//     -L "<host build>/*.so" tests/firewall-rule.uc
'use strict';

import * as ubbf from 'ubbf';
import * as h from 'ubbf.render.uci_helpers';
import {
	chain_rule_unsupported, chain_rules_ordered, chain_rule_set_matches, firewall_set_resolve,
	firewall_reconcile, firewall_rules_expired, firewall_expiry_next
} from 'ubbf';
import { model } from 'ubbf.tr181.Firewall';

global.USP_ERR_INVALID_VALUE = 7012;

let pass = 0, fail = 0;

function check(name, got, expected) {
	if (sprintf('%J', got) == sprintf('%J', expected)) { pass++; return; }
	fail++;
	printf('FAIL %s\n  expected %J\n  got      %J\n', name, expected, got);
}

const TEMPLATE = sourcepath(0, true) + '/../files/usr/share/ucode/ubbf/render/templates/firewall-chains.uc';

// Renders one rule in Advanced mode, LAN to WAN unless overridden, and
// returns the emitted rule sections as objects.
function render(fields, sets) {
	let rule = {
		Enable: 'true', Alias: 'r', Target: 'Accept',
		SourceInterface: 'Device.IP.Interface.2', DestInterface: 'Device.IP.Interface.1',
		...fields
	};
	let config = { Device: {
		IP: { Interface: { '1': { Name: 'wan' }, '2': { Name: 'lan' }, '3': { Name: 'guest' } } },
		Firewall: {
			Config: 'Advanced', AdvancedLevel: 'Device.Firewall.Level.1',
			Level: { '1': { Chain: 'Device.Firewall.Chain.1' } },
			Chain: {
				'1': { Enable: 'true', Rule: { '1': rule } },
				'2': { Enable: 'true', Rule: { '1': { ...rule, SourceIP: '192.0.2.222' } } }
			},
			Set: sets ?? {}
		}
	} };
	let output = [], warnings = [];

	include(TEMPLATE, { ...h, output, config, ubbf, ubbf_get: ubbf.get, ubbf_instances: ubbf.instances,
		ubbf_to_bool: ubbf.to_bool, ubbf_to_int: ubbf.to_int, interface_to_name: ubbf.interface_to_name,
		chain_rule_unsupported, chain_rules_ordered, chain_rule_set_matches, firewall_set_resolve,
		render_state: { firewall_zones: [ 'wan', 'lan', 'guest' ] },
		warn: (f, ...a) => push(warnings, sprintf(f, ...a)) });

	let sections = [], ipsets = [], cur;
	for (let line in output) {
		let a = match(line, /^add firewall ([a-z]+)$/);
		if (a) {
			cur = {};
			push((a[1] == 'ipset') ? ipsets : sections, cur);
			continue;
		}
		let m = match(line, /^(set|add_list) firewall\.@[a-z]+\[-1\]\.([a-z_]+)='?([^']*)'?$/);
		if (!m || !cur)
			continue;
		if (m[1] == 'set')
			cur[m[2]] = m[3];
		else
			push(cur[m[2]] ??= [], m[3]);
	}
	return { sections, ipsets, warnings };
}

function zones(r) {
	return map(r.sections, (s) => `${s.src ?? '-'}>${s.dest ?? '-'}`);
}

let r = render({ SourceIP: '192.0.2.1' });
check('only the chain of the active level', map(r.sections, (s) => s.src_ip), [ '192.0.2.1' ]);
check('no Protocol is every protocol, not fw4 TCP and UDP', r.sections[0].proto, 'all');

r = render({ SourceIP: '192.0.2.10', SourceIPExclude: 'true', DestIP: '198.51.100.0', DestMask: '/24', DestIPExclude: 'true' });
check('source IP exclude', r.sections[0].src_ip, '!192.0.2.10');
check('dest IP exclude', r.sections[0].dest_ip, '!198.51.100.0/24');

r = render({ Protocol: '6', SourcePort: '1024', SourcePortExclude: 'true', DestPort: '22', DestPortRangeMax: '23', DestPortExclude: 'true' });
check('source port exclude', r.sections[0].src_port, '!1024');
check('dest port range exclude', r.sections[0].dest_port, '!22-23');
check('protocol kept', r.sections[0].proto, 'tcp');

r = render({ Protocol: '17', ProtocolExclude: 'true' });
check('protocol exclude', r.sections[0].proto, '!udp');

r = render({ Protocol: '-1', ProtocolExclude: 'true', SourceIP: '192.0.2.1' });
check('exclude of any protocol is no match', r.sections[0].proto, 'all');

r = render({ SourceMAC: '02:00:00:00:00:01', SourceMACExclude: 'true' });
check('MAC exclude', r.sections[0].src_mac, '!02:00:00:00:00:01');

r = render({ SourceInterfaceExclude: 'true', Protocol: '6' });
check('source interface exclude', zones(r), [ 'wan>wan', 'guest>wan', '->wan' ]);

r = render({ DestInterfaceExclude: 'true', Protocol: '6' });
check('dest interface exclude', zones(r), [ 'lan>lan', 'lan>guest', 'lan>-' ]);

r = render({ SourceInterfaceExclude: 'true', DestInterfaceExclude: 'true', Protocol: '6' });
check('both excluded, no rule without zones', index(zones(r), '->-'), -1);
check('both excluded, count', length(r.sections), 8);

r = render({});
check('plain zone pair is a forwarding', r.sections, [ { src: 'lan', dest: 'wan' } ]);

r = render({ SourceMAC: '02:00:00:00:00:01' });
check('zone pair with a match is a rule', r.sections[0].src_mac, '02:00:00:00:00:01');

r = render({ SourceIP: '192.0.2.1', ExpiryDate: '2027-01-01T00:00:00Z' });
check('expiry as stop_date', [ r.sections[0].stop_date, r.sections[0].utc_time ], [ '2027-01-01T00:00:00', '1' ]);

r = render({ SourceIP: '192.0.2.1', ExpiryDate: '9999-12-31T23:59:59Z' });
check('infinite expiry', r.sections[0].stop_date, null);

r = render({ SourceIP: '192.0.2.1', ExpiryDate: '0001-01-01T00:00:00Z' });
check('unknown expiry', r.sections[0].stop_date, null);

r = render({ SourceIP: '192.0.2.1', ExpiryDate: '2050-01-01T00:00:00Z' });
check('expiry after 2038 not applied', [ r.sections[0].stop_date, length(r.warnings) ], [ null, 1 ]);

for (let c in [
	[ 'ConnectionState', { ConnectionState: 'ESTABLISHED' } ],
	[ 'Target', { Target: 'Return' } ],
	[ 'Target', { Target: 'TargetChain', TargetChain: 'Device.Firewall.Chain.2' } ],
	[ 'missing SourceMatchSet', { SourceMatchSet: 'Device.Firewall.Set.1' } ],
	[ 'missing DestMatchSet', { DestMatchSet: 'Device.Firewall.Set.1' } ],
	[ 'ProtocolExclude', { Protocol: '6', ProtocolExclude: 'true', DestPort: '22' } ]
]) {
	r = render(c[1]);
	check(`${c[0]} not rendered`, [ length(r.sections), length(r.warnings) ], [ 0, 1 ]);
}

r = render({ SourceInterface: 'Device.IP.Interface.9', SourceMAC: '02:00:00:00:00:01' });
check('unresolved interface not rendered', length(r.sections), 0);

const rule = model['Device.Firewall.Chain.{i}.Rule.{i}'];

check('status enabled', rule.get({ config: { Enable: 'true' } }).Status, 'Enabled');
check('status disabled', rule.get({ config: { Enable: 'false', ConnectionState: 'NEW' } }).Status, 'Disabled');
check('status unsupported', rule.get({ config: { Enable: 'true', Target: 'Return' } }).Status, 'Error_Misconfigured');

// The dispatcher stores the value before it calls the handler
check('set ConnectionState refused', rule.set({ param: 'ConnectionState', value: 'NEW', config: { ConnectionState: 'NEW' } }), -7012);
check('set empty ConnectionState', rule.set({ param: 'ConnectionState', value: '', config: { ConnectionState: '' } }), 0);
check('set Target Return refused', rule.set({ param: 'Target', value: 'Return', config: { Target: 'Return' } }), -7012);
check('set Target Accept', rule.set({ param: 'Target', value: 'Accept', config: { Target: 'Accept' } }), 0);
check('set SourceMatchSet', rule.set({ param: 'SourceMatchSet', value: 'Device.Firewall.Set.1', config: { SourceMatchSet: 'Device.Firewall.Set.1' } }), 0);
check('second set reference refused', rule.set({ param: 'DestMatchSetExclude', value: 'Device.Firewall.Set.2',
	config: { SourceMatchSet: 'Device.Firewall.Set.1', DestMatchSetExclude: 'Device.Firewall.Set.2' } }), -7012);
check('status with a missing set', rule.get({ config: { Enable: 'true', SourceMatchSet: 'Device.Firewall.Set.7' },
	root: { Device: {} } }).Status, 'Error_Misconfigured');
check('set DestPort with ProtocolExclude refused',
	rule.set({ param: 'DestPort', value: '22', config: { Protocol: '6', ProtocolExclude: 'true', DestPort: '22' } }), -7012);
check('set ProtocolExclude without ports',
	rule.set({ param: 'ProtocolExclude', value: 'true', config: { Protocol: '6', ProtocolExclude: 'true' } }), 0);
check('unrelated set on an unsupported rule',
	rule.set({ param: 'Description', value: 'x', config: { Target: 'Return', Description: 'x' } }), 0);

const SETS = {
	'1': { Enable: 'true', Type: 'IPAddresses', IPVersion: '-1', Rule: {
		'1': { IPAddressList: '192.0.2.0/24,2001:db8::/32' }, '2': { IPAddressList: '198.51.100.7' } } },
	'2': { Enable: 'true', Type: 'Ports', Rule: { '1': { PortList: '80,8000-8002' } } },
	'3': { Enable: 'true', Type: 'MACAddresses', Rule: { '1': { Exclude: 'true', MACAddressList: '02:00:00:00:00:AA' } } },
	'4': { Enable: 'true', Type: 'IPAddresses', IPVersion: '4', Rule: {
		'1': { IPAddressList: '192.0.2.1' }, '2': { Exclude: 'true', IPAddressList: '192.0.2.2' } } },
	'5': { Enable: 'false', Type: 'IPAddresses', Rule: { '1': { IPAddressList: '192.0.2.3' } } }
};

r = render({ SourceMatchSet: 'Device.Firewall.Set.1' }, SETS);
check('IP set per family', map(r.ipsets, (s) => [ s.name, s.family, s.match, s.entry ]), [
	[ 'ubbf_set_1_v4', 'ipv4', [ 'src_net' ], [ '192.0.2.0/24', '198.51.100.7' ] ],
	[ 'ubbf_set_1_v6', 'ipv6', [ 'src_net' ], [ '2001:db8::/32' ] ],
	[ 'ubbf_set_2', 'any', [ 'src_port' ], [ '80', '8000', '8001', '8002' ] ],
	[ 'ubbf_set_3', 'any', [ 'src_mac' ], [ '02:00:00:00:00:aa' ] ]
]);
check('rule per set family', map(r.sections, (s) => [ s.family, s.ipset ]),
	[ [ 'ipv4', 'ubbf_set_1_v4 src' ], [ 'ipv6', 'ubbf_set_1_v6 src' ] ]);

r = render({ SourceMatchSet: 'Device.Firewall.Set.1', IPVersion: '6' }, SETS);
check('rule of one family uses that set', map(r.sections, (s) => s.ipset), [ 'ubbf_set_1_v6 src' ]);

r = render({ DestMatchSetExclude: 'Device.Firewall.Set.2', Protocol: '6' }, SETS);
check('exclude set reference', r.sections[0].ipset, '!ubbf_set_2 dest');

r = render({ SourceMatchSetExclude: 'Device.Firewall.Set.3' }, SETS);
check('excluded entries invert an exclude reference', r.sections[0].ipset, 'ubbf_set_3 src');

r = render({ SourceMatchSet: 'Device.Firewall.Set.2', Protocol: '1' }, SETS);
check('port set needs TCP or UDP', [ length(r.sections), length(r.warnings) ], [ 0, 1 ]);

r = render({ SourceMatchSet: 'Device.Firewall.Set.4' }, SETS);
check('set with mixed excludes not rendered', [ length(r.sections), length(r.warnings) ], [ 0, 1 ]);

r = render({ SourceMatchSet: 'Device.Firewall.Set.5' }, SETS);
check('disabled set not rendered', [ length(r.sections), length(r.warnings) ], [ 0, 1 ]);

let fresh = { Device: { Firewall: {
	Level: { '1': { Name: 'Default', Chain: 'Device.Firewall.Chain.1' }, '2': { Name: 'Strict', Chain: '' }, '3': { Chain: 'Device.Firewall.Chain.9' } },
	Chain: { '1': { Enable: 'true', Alias: 'DefaultChain' } }
} } };

firewall_reconcile({}, fresh);
let fw = fresh.Device.Firewall;
check('level keeps its chain', fw.Level['1'].Chain, 'Device.Firewall.Chain.1');
check('new level gets a chain', [ fw.Level['2'].Chain, fw.Chain['2']?.Alias, fw.Chain['2']?.Name ],
	[ 'Device.Firewall.Chain.2', 'cpe-Level2', 'Strict' ]);
check('dangling chain replaced', [ fw.Level['3'].Chain, fw.Chain['3']?.Name ], [ 'Device.Firewall.Chain.3', 'Level3' ]);
check('chain count', fw.ChainNumberOfEntries, '3');

// A row that a controller added keeps the default Alias of the core,
// cpe-<Table><N>; an unclaimed row of a hook (cpe- and a lower-case name)
// goes.
let added = { Device: { Firewall: { Service: {
	'1': { Enable: 'true', Alias: 'cpe-Service1', DestPort: '8080' },
	'2': { Enable: 'true', Alias: 'cpe-ssh-22', DestPort: '22' },
	'3': { Enable: 'true', Alias: 'mine', DestPort: '81' }
} } } };
firewall_reconcile({}, added);
check('controller rows stay, unclaimed hook row goes', sort(keys(added.Device.Firewall.Service)), [ '1', '3' ]);

let expiring = { Device: { Firewall: { Chain: {
	'1': { Rule: {
		'1': { ExpiryDate: '2027-01-01T00:00:00Z' },
		'2': { ExpiryDate: '9999-12-31T23:59:59Z' },
		'3': { ExpiryDate: '2026-01-01T00:00:00Z' },
		'4': { ExpiryDate: '0001-01-01T00:00:00Z' },
		'5': {}
	} },
	'2': { Rule: { '1': { ExpiryDate: '2026-06-01T12:00:00Z' } } }
} } } };
let now = usp_datetime_to_unix('2026-10-18T00:00:00Z');

check('expired rules', firewall_rules_expired(expiring, now),
	[ 'Device.Firewall.Chain.1.Rule.3.', 'Device.Firewall.Chain.2.Rule.1.' ]);
check('next expiry', firewall_expiry_next(expiring, now), usp_datetime_to_unix('2027-01-01T00:00:00Z'));
check('nothing expires', firewall_expiry_next({ Device: {} }, now), null);

printf('passed: %d\nfailed: %d\n', pass, fail);
exit(fail ? 1 : 0);
