// Host test of the Protocol and DestPort render of Device.Firewall.Service
// and Device.Firewall.Pinhole: -1 means the criterion is not used for
// matching.
'use strict';

import { describe, it, assert } from 'utest';
import * as ubbf from 'ubbf';
import * as h from 'ubbf.render.uci_helpers';

const TEMPLATES = sourcepath(0, true) + '/../files/usr/share/ucode/ubbf/render/templates/';

function render(template, table, row) {
	let config = { Device: {
		IP: { Interface: { '1': { Name: 'wan' } } },
		Firewall: { [table]: { '1': { Enable: 'true', Interface: 'Device.IP.Interface.1', ...row } } }
	} };
	let output = [];

	include(TEMPLATES + template, { ...h, output, config, ubbf, ubbf_instances: ubbf.instances,
		ubbf_to_bool: ubbf.to_bool, ubbf_to_int: ubbf.to_int, interface_to_name: ubbf.interface_to_name,
		csv_to_list: ubbf.csv_to_list, schedule_windows: () => null });

	let rule = {};
	for (let line in output) {
		let m = match(line, /^(set|add_list) firewall\.@rule\[-1\]\.([a-z_]+)='?([^']*)'?$/);
		if (!m)
			continue;
		if (m[1] == 'set')
			rule[m[2]] = m[3];
		else
			push(rule[m[2]] ??= [], m[3]);
	}
	return rule;
}

function service(row) {
	let r = render('firewall-services.uc', 'Service', row);
	return [ r.proto, r.dest_port ];
}

function pinhole(protocol) {
	return render('firewall-pinholes.uc', 'Pinhole', { Protocol: protocol, DestIP: '2001:db8::1', DestPort: '443' }).proto;
}

describe('Firewall.Service render', () => {
	it('matches any protocol and port for -1', () => {
		assert.match([ [ 'all' ], null ], service({ Protocol: '-1', DestPort: '-1' }));
	});

	it('renders the protocol and port lists', () => {
		assert.match([ [ 'tcp', 'udp' ], [ '22', '80' ] ], service({ Protocol: '6,17', DestPort: '22,80' }));
	});

	it('lets -1 in a list win', () => {
		assert.match([ [ 'all' ], null ], service({ Protocol: '6,-1', DestPort: '22,-1' }));
	});

	it('keeps the fw4 default without Protocol', () => {
		assert.match([ null, null ], service({}));
	});
});

describe('Firewall.Pinhole render', () => {
	it('matches any protocol for -1', () => {
		assert.match([ 'all' ], pinhole('-1'));
	});

	it('renders a protocol list and a single protocol', () => {
		assert.match([ 'tcp', 'udp' ], pinhole('6,17'));
		assert.match([ 'udp' ], pinhole('17'));
	});
});
