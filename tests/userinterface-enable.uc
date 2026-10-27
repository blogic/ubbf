// Host test of Device.UserInterface.Enable: false stops the web UI, its
// listeners and the firewall openings of every HTTPAccess row.
'use strict';

import { describe, it, assert, mock, beforeEach } from 'utest';
import * as ubbf from 'ubbf';
import { generate } from 'ubbf.render.renderer';
import * as services from 'ubbf.render.services';

function config(enable) {
	return { Device: {
		IP: { Interface: { '2': { Enable: 'true', Name: 'lan' } } },
		UserInterface: { Enable: enable, HTTPAccess: {
			'1': { Enable: 'true', Alias: 'http', Protocol: 'HTTP', Port: '80', Interface: 'Device.IP.Interface.2', AllowAllIPv4: 'true', AllowAllIPv6: 'true' },
			'2': { Enable: 'true', Alias: 'https', Protocol: 'HTTPS', Port: '443', Interface: 'Device.IP.Interface.2', AllowAllIPv4: 'true', AllowAllIPv6: 'true' }
		} }
	} };
}

function render(enable) {
	let result = generate(config(enable), [], true);
	return {
		service: services.services['ubbf-ui'],
		listeners: length(match(result.uci, /add webui server/g) ?? [])
	};
}

function firewall_hook() {
	const api = {
		ubbf: proto({ datetime_format: (t) => t }, ubbf),
		utils: {},
		schema: (k) => k,
		on_commit: () => null,
		config_apply: () => ({ success: true }),
		model: {},
		operations: {}
	};
	include('/usr/share/ucode/ubbf/modules/userinterface/handler.uc', { ubbf_module: api });
	return api.model['Device.UserInterface.HTTPAccess.{i}'].firewall;
}

function openings(enable) {
	let hook = firewall_hook();
	let root = config(enable);
	let claims = map(values(root.Device.UserInterface.HTTPAccess), (row) => hook(row, root, ''));
	return map(claims, (c) => length(c ?? []));
}

describe('Device.UserInterface.Enable', () => {
	beforeEach(() => mock.global.patch('uci', { data: {} }));

	it('true runs the service with both listeners', () => {
		assert.match({ service: true, listeners: 2 }, render('true'));
	});

	it('false runs no service and no listener', () => {
		assert.match({ service: false, listeners: 0 }, render('false'));
	});

	it('true opens the firewall for every HTTPAccess row', () => {
		assert.match([ 1, 1 ], openings('true'), 'UserInterface.Enable=true: firewall openings');
	});

	it('false opens the firewall for no HTTPAccess row', () => {
		assert.match([ 0, 0 ], openings('false'), 'UserInterface.Enable=false: firewall openings');
	});
});
