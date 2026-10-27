// Host test of Device.Firewall.Chain.{i}.Rule.{i}: the render of the
// *Exclude flags, the interface excludes and ExpiryDate in
// render/templates/firewall-chains.uc, and the refusal of what fw4 cannot
// express (chain_rule_unsupported() of ubbf.so, the Rule handler in
// tr181/Firewall.uc).
'use strict';

import { describe, it, assert } from 'utest';
import * as ubbf from 'ubbf';
import * as h from 'ubbf.render.uci_helpers';
import {
	chain_rule_unsupported, chain_rules_ordered, chain_rule_set_matches, firewall_set_resolve,
	firewall_reconcile, firewall_rules_expired, firewall_expiry_next
} from 'ubbf';
import { model } from 'ubbf.tr181.Firewall';

global.USP_ERR_INVALID_VALUE = 7012;

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

const rule = model['Device.Firewall.Chain.{i}.Rule.{i}'];

const SETS = {
	'1': { Enable: 'true', Type: 'IPAddresses', IPVersion: '-1', Rule: {
		'1': { IPAddressList: '192.0.2.0/24,2001:db8::/32' }, '2': { IPAddressList: '198.51.100.7' } } },
	'2': { Enable: 'true', Type: 'Ports', Rule: { '1': { PortList: '80,8000-8002' } } },
	'3': { Enable: 'true', Type: 'MACAddresses', Rule: { '1': { Exclude: 'true', MACAddressList: '02:00:00:00:00:AA' } } },
	'4': { Enable: 'true', Type: 'IPAddresses', IPVersion: '4', Rule: {
		'1': { IPAddressList: '192.0.2.1' }, '2': { Exclude: 'true', IPAddressList: '192.0.2.2' } } },
	'5': { Enable: 'false', Type: 'IPAddresses', Rule: { '1': { IPAddressList: '192.0.2.3' } } }
};

describe('Firewall Rule render', () => {
	it('renders only the chain of the active level, for every protocol', () => {
		let r = render({ SourceIP: '192.0.2.1' });
		assert.match([ '192.0.2.1' ], map(r.sections, (s) => s.src_ip), 'only the chain of the active level');
		assert.match('all', r.sections[0].proto, 'no Protocol is every protocol, not fw4 TCP and UDP');
	});

	it('renders the IP excludes', () => {
		let r = render({ SourceIP: '192.0.2.10', SourceIPExclude: 'true', DestIP: '198.51.100.0', DestMask: '/24', DestIPExclude: 'true' });
		assert.match('!192.0.2.10', r.sections[0].src_ip, 'source IP exclude');
		assert.match('!198.51.100.0/24', r.sections[0].dest_ip, 'dest IP exclude');
	});

	it('renders the port excludes', () => {
		let r = render({ Protocol: '6', SourcePort: '1024', SourcePortExclude: 'true', DestPort: '22', DestPortRangeMax: '23', DestPortExclude: 'true' });
		assert.match('!1024', r.sections[0].src_port, 'source port exclude');
		assert.match('!22-23', r.sections[0].dest_port, 'dest port range exclude');
		assert.match('tcp', r.sections[0].proto, 'protocol kept');
	});

	it('renders the protocol exclude', () => {
		assert.match('!udp', render({ Protocol: '17', ProtocolExclude: 'true' }).sections[0].proto);
		assert.match('all', render({ Protocol: '-1', ProtocolExclude: 'true', SourceIP: '192.0.2.1' }).sections[0].proto,
			'exclude of any protocol is no match');
	});

	it('renders the MAC exclude', () => {
		assert.match('!02:00:00:00:00:01', render({ SourceMAC: '02:00:00:00:00:01', SourceMACExclude: 'true' }).sections[0].src_mac);
	});

	it('renders the interface excludes as the other zones', () => {
		assert.match([ 'wan>wan', 'guest>wan', '->wan' ], zones(render({ SourceInterfaceExclude: 'true', Protocol: '6' })),
			'source interface exclude');
		assert.match([ 'lan>lan', 'lan>guest', 'lan>-' ], zones(render({ DestInterfaceExclude: 'true', Protocol: '6' })),
			'dest interface exclude');

		let r = render({ SourceInterfaceExclude: 'true', DestInterfaceExclude: 'true', Protocol: '6' });
		assert.match(-1, index(zones(r), '->-'), 'both excluded, no rule without zones');
		assert.match(8, length(r.sections), 'both excluded, count');
	});

	it('renders a plain zone pair as a forwarding and a zone pair with a match as a rule', () => {
		assert.match([ { src: 'lan', dest: 'wan' } ], render({}).sections);
		assert.match('02:00:00:00:00:01', render({ SourceMAC: '02:00:00:00:00:01' }).sections[0].src_mac);
	});

	it('renders ExpiryDate as stop_date', () => {
		let r = render({ SourceIP: '192.0.2.1', ExpiryDate: '2027-01-01T00:00:00Z' });
		assert.match([ '2027-01-01T00:00:00', '1' ], [ r.sections[0].stop_date, r.sections[0].utc_time ]);
		assert.match(null, render({ SourceIP: '192.0.2.1', ExpiryDate: '9999-12-31T23:59:59Z' }).sections[0].stop_date,
			'infinite expiry');
		assert.match(null, render({ SourceIP: '192.0.2.1', ExpiryDate: '0001-01-01T00:00:00Z' }).sections[0].stop_date,
			'unknown expiry');

		r = render({ SourceIP: '192.0.2.1', ExpiryDate: '2050-01-01T00:00:00Z' });
		assert.match([ null, 1 ], [ r.sections[0].stop_date, length(r.warnings) ], 'expiry after 2038 not applied');
	});

	it('does not render what fw4 cannot express', () => {
		for (let c in [
			[ 'ConnectionState', { ConnectionState: 'ESTABLISHED' } ],
			[ 'Target', { Target: 'Return' } ],
			[ 'Target', { Target: 'TargetChain', TargetChain: 'Device.Firewall.Chain.2' } ],
			[ 'missing SourceMatchSet', { SourceMatchSet: 'Device.Firewall.Set.1' } ],
			[ 'missing DestMatchSet', { DestMatchSet: 'Device.Firewall.Set.1' } ],
			[ 'ProtocolExclude', { Protocol: '6', ProtocolExclude: 'true', DestPort: '22' } ]
		]) {
			let r = render(c[1]);
			assert.match([ 0, 1 ], [ length(r.sections), length(r.warnings) ], `${c[0]} not rendered`);
		}

		assert.match(0, length(render({ SourceInterface: 'Device.IP.Interface.9', SourceMAC: '02:00:00:00:00:01' }).sections),
			'unresolved interface not rendered');
	});
});

describe('Firewall Rule handler', () => {
	it('reports the Status', () => {
		assert.match('Enabled', rule.get({ config: { Enable: 'true' } }).Status);
		assert.match('Disabled', rule.get({ config: { Enable: 'false', ConnectionState: 'NEW' } }).Status);
		assert.match('Error_Misconfigured', rule.get({ config: { Enable: 'true', Target: 'Return' } }).Status, 'status unsupported');
		assert.match('Error_Misconfigured', rule.get({ config: { Enable: 'true', SourceMatchSet: 'Device.Firewall.Set.7' },
			root: { Device: {} } }).Status, 'status with a missing set');
	});

	// The dispatcher stores the value before it calls the handler
	it('refuses a write of what fw4 cannot express', () => {
		assert.match(-7012, rule.set({ param: 'ConnectionState', value: 'NEW', config: { ConnectionState: 'NEW' } }),
			'set ConnectionState refused');
		assert.match(0, rule.set({ param: 'ConnectionState', value: '', config: { ConnectionState: '' } }), 'set empty ConnectionState');
		assert.match(-7012, rule.set({ param: 'Target', value: 'Return', config: { Target: 'Return' } }), 'set Target Return refused');
		assert.match(0, rule.set({ param: 'Target', value: 'Accept', config: { Target: 'Accept' } }), 'set Target Accept');
		assert.match(0, rule.set({ param: 'SourceMatchSet', value: 'Device.Firewall.Set.1', config: { SourceMatchSet: 'Device.Firewall.Set.1' } }),
			'set SourceMatchSet');
		assert.match(-7012, rule.set({ param: 'DestMatchSetExclude', value: 'Device.Firewall.Set.2',
			config: { SourceMatchSet: 'Device.Firewall.Set.1', DestMatchSetExclude: 'Device.Firewall.Set.2' } }),
			'second set reference refused');
		assert.match(-7012,
			rule.set({ param: 'DestPort', value: '22', config: { Protocol: '6', ProtocolExclude: 'true', DestPort: '22' } }),
			'set DestPort with ProtocolExclude refused');
		assert.match(0,
			rule.set({ param: 'ProtocolExclude', value: 'true', config: { Protocol: '6', ProtocolExclude: 'true' } }),
			'set ProtocolExclude without ports');
		assert.match(0,
			rule.set({ param: 'Description', value: 'x', config: { Target: 'Return', Description: 'x' } }),
			'unrelated set on an unsupported rule');
	});
});

describe('Firewall Set render', () => {
	it('renders an IP set per family with a rule per family', () => {
		let r = render({ SourceMatchSet: 'Device.Firewall.Set.1' }, SETS);
		assert.match([
			[ 'ubbf_set_1_v4', 'ipv4', [ 'src_net' ], [ '192.0.2.0/24', '198.51.100.7' ] ],
			[ 'ubbf_set_1_v6', 'ipv6', [ 'src_net' ], [ '2001:db8::/32' ] ],
			[ 'ubbf_set_2', 'any', [ 'src_port' ], [ '80', '8000', '8001', '8002' ] ],
			[ 'ubbf_set_3', 'any', [ 'src_mac' ], [ '02:00:00:00:00:aa' ] ]
		], map(r.ipsets, (s) => [ s.name, s.family, s.match, s.entry ]), 'IP set per family');
		assert.match([ [ 'ipv4', 'ubbf_set_1_v4 src' ], [ 'ipv6', 'ubbf_set_1_v6 src' ] ],
			map(r.sections, (s) => [ s.family, s.ipset ]), 'rule per set family');
	});

	it('uses the set of the family of a rule of one family', () => {
		assert.match([ 'ubbf_set_1_v6 src' ],
			map(render({ SourceMatchSet: 'Device.Firewall.Set.1', IPVersion: '6' }, SETS).sections, (s) => s.ipset));
	});

	it('renders the exclude references', () => {
		assert.match('!ubbf_set_2 dest', render({ DestMatchSetExclude: 'Device.Firewall.Set.2', Protocol: '6' }, SETS).sections[0].ipset,
			'exclude set reference');
		assert.match('ubbf_set_3 src', render({ SourceMatchSetExclude: 'Device.Firewall.Set.3' }, SETS).sections[0].ipset,
			'excluded entries invert an exclude reference');
	});

	it('does not render a rule with a set that fw4 cannot use', () => {
		let r = render({ SourceMatchSet: 'Device.Firewall.Set.2', Protocol: '1' }, SETS);
		assert.match([ 0, 1 ], [ length(r.sections), length(r.warnings) ], 'port set needs TCP or UDP');

		r = render({ SourceMatchSet: 'Device.Firewall.Set.4' }, SETS);
		assert.match([ 0, 1 ], [ length(r.sections), length(r.warnings) ], 'set with mixed excludes not rendered');

		r = render({ SourceMatchSet: 'Device.Firewall.Set.5' }, SETS);
		assert.match([ 0, 1 ], [ length(r.sections), length(r.warnings) ], 'disabled set not rendered');
	});
});

describe('Firewall reconcile', () => {
	it('gives each level a chain', () => {
		let fresh = { Device: { Firewall: {
			Level: { '1': { Name: 'Default', Chain: 'Device.Firewall.Chain.1' }, '2': { Name: 'Strict', Chain: '' }, '3': { Chain: 'Device.Firewall.Chain.9' } },
			Chain: { '1': { Enable: 'true', Alias: 'DefaultChain' } }
		} } };

		firewall_reconcile({}, fresh);
		let fw = fresh.Device.Firewall;
		assert.match('Device.Firewall.Chain.1', fw.Level['1'].Chain, 'level keeps its chain');
		assert.match([ 'Device.Firewall.Chain.2', 'cpe-Level2', 'Strict' ], [ fw.Level['2'].Chain, fw.Chain['2']?.Alias, fw.Chain['2']?.Name ],
			'new level gets a chain');
		assert.match([ 'Device.Firewall.Chain.3', 'Level3' ], [ fw.Level['3'].Chain, fw.Chain['3']?.Name ], 'dangling chain replaced');
		assert.match('3', fw.ChainNumberOfEntries, 'chain count');
	});

	// A row that a controller added keeps the default Alias of the core,
	// cpe-<Table><N>; an unclaimed row of a hook (cpe- and a lower-case name)
	// goes.
	it('keeps the controller rows and removes an unclaimed hook row', () => {
		let added = { Device: { Firewall: { Service: {
			'1': { Enable: 'true', Alias: 'cpe-Service1', DestPort: '8080' },
			'2': { Enable: 'true', Alias: 'cpe-ssh-22', DestPort: '22' },
			'3': { Enable: 'true', Alias: 'mine', DestPort: '81' }
		} } } };
		firewall_reconcile({}, added);
		assert.match([ '1', '3' ], sort(keys(added.Device.Firewall.Service)));
	});
});

describe('Firewall Rule expiry', () => {
	const expiring = { Device: { Firewall: { Chain: {
		'1': { Rule: {
			'1': { ExpiryDate: '2027-01-01T00:00:00Z' },
			'2': { ExpiryDate: '9999-12-31T23:59:59Z' },
			'3': { ExpiryDate: '2026-01-01T00:00:00Z' },
			'4': { ExpiryDate: '0001-01-01T00:00:00Z' },
			'5': {}
		} },
		'2': { Rule: { '1': { ExpiryDate: '2026-06-01T12:00:00Z' } } }
	} } } };

	it('lists the expired rules and the next expiry', () => {
		let now = usp_datetime_to_unix('2026-10-18T00:00:00Z');

		assert.match([ 'Device.Firewall.Chain.1.Rule.3.', 'Device.Firewall.Chain.2.Rule.1.' ],
			firewall_rules_expired(expiring, now), 'expired rules');
		assert.match(usp_datetime_to_unix('2027-01-01T00:00:00Z'), firewall_expiry_next(expiring, now), 'next expiry');
		assert.match(null, firewall_expiry_next({ Device: {} }, now), 'nothing expires');
	});
});
