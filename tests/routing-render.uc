// Host test of the render of Device.Routing (render/templates/routing.uc):
// a route of Router.1 goes to the main table without a table option, a
// route of Router.2 to table 101, and a route with a source to a source
// table with an ip rule. Run from the repository root with the native
// module built for the host:
//   tests/render/run.sh <host build> tests/routing-render.uc
'use strict';

import { generate } from 'ubbf.render.renderer';

let pass = 0, fail = 0;

function check(name, got, expected) {
	if (sprintf('%J', got) == sprintf('%J', expected)) { pass++; return; }
	fail++;
	printf('FAIL %s\n  expected %J\n  got      %J\n', name, expected, got);
}

const config = { Device: {
	IP: { Interface: { '1': { Enable: 'true', Name: 'wan', Upstream: 'true' }, '2': { Enable: 'true', Name: 'lan' } } },
	Routing: { Router: {
		'1': { Enable: 'true', IPv4Forwarding: {
			'1': { Enable: 'true', DestIPAddress: '10.1.0.0', DestSubnetMask: '255.255.0.0',
			       GatewayIPAddress: '192.0.2.1', Interface: 'Device.IP.Interface.1' },
			'2': { Enable: 'true', DestIPAddress: '10.2.0.0', DestSubnetMask: '255.255.0.0',
			       SourceIPAddress: '192.168.1.0', SourceSubnetMask: '255.255.255.0',
			       GatewayIPAddress: '192.0.2.1', Interface: 'Device.IP.Interface.1' } } },
		'2': { Enable: 'true', IPv4Forwarding: {
			'1': { Enable: 'true', DestIPAddress: '10.3.0.0', DestSubnetMask: '255.255.0.0',
			       GatewayIPAddress: '192.0.2.1', Interface: 'Device.IP.Interface.1' } } }
	} }
} };

function sections(uci, type) {
	let out = [], cur;
	for (let line in split(uci, '\n')) {
		if (match(line, regexp(`^add network ${type}$`))) {
			cur = {};
			push(out, cur);
			continue;
		}
		let m = match(line, regexp(`^set network\\.@${type}\\[-1\\]\\.([a-z0-9_]+)='?([^']*)'?$`));
		if (cur && m)
			cur[m[1]] = m[2];
		else if (!match(line, /^set network\.@/))
			cur = null;
	}
	return out;
}

let logs = [];
let res = generate(config, logs, true);
let routes = sections(res.uci, 'route');
let by_target = {};
for (let r in routes)
	by_target[r.target] = r;

check('main table route has no table option', [ by_target['10.1.0.0']?.netmask, by_target['10.1.0.0']?.table ],
	[ '255.255.0.0', null ]);
check('second router route', by_target['10.3.0.0']?.table, '101');
check('source route goes to a source table', by_target['10.2.0.0']?.table, '200');

let rules = sections(res.uci, 'rule');
check('rule to the source table', length(filter(rules, (r) => r.src == '192.168.1.0/24' && r.lookup == '200')), 1);

if (fail)
	printf('uci: %s\nlogs: %J\n', res.uci, logs);

printf('passed: %d\nfailed: %d\n', pass, fail);
exit(fail ? 1 : 0);
