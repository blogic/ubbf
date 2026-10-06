// Host test of Device.UserInterface.Enable: false stops the web UI, its
// listeners and the firewall openings of every HTTPAccess row. Run from the
// repository root with the native module built for the host:
//   tests/render/run.sh <host build> tests/userinterface-enable.uc
'use strict';

import * as ubbf from 'ubbf';
import { generate } from 'ubbf.render.renderer';
import * as services from 'ubbf.render.services';

let pass = 0, fail = 0;

function check(name, got, expected) {
	if (sprintf('%J', got) == sprintf('%J', expected)) { pass++; return; }
	fail++;
	printf('FAIL %s\n  expected %J\n  got      %J\n', name, expected, got);
}

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

check('enabled: service and both listeners', render('true'), { service: true, listeners: 2 });
check('disabled: no service and no listener', render('false'), { service: false, listeners: 0 });

const api = {
	ubbf,
	utils: {
		helpers: { datetime_format: (t) => t },
		logging: { log_err: () => null, log_exception: () => null }
	},
	schema: (k) => k,
	on_commit: () => null,
	config_apply: () => ({ success: true }),
	model: {},
	operations: {}
};
include('/usr/share/ucode/ubbf/modules/userinterface/handler.uc', { ubbf_module: api });
let hook = api.model['Device.UserInterface.HTTPAccess.{i}'].firewall;

for (let enable in [ 'true', 'false' ]) {
	let root = config(enable);
	let claims = map(values(root.Device.UserInterface.HTTPAccess), (row) => hook(row, root, ''));
	check(`UserInterface.Enable=${enable}: firewall openings`, map(claims, (c) => length(c ?? [])),
		(enable == 'true') ? [ 1, 1 ] : [ 0, 0 ]);
}

printf('passed: %d\nfailed: %d\n', pass, fail);
exit(fail ? 1 : 0);
