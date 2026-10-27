// Host test of the security module: Certificate.{i}.Delete() and
// CABundle.{i}.Delete() clear the references to the deleted row in the
// stored configuration (TR-181: "If the referenced object is deleted, the
// parameter value MUST be set to an empty string"). It needs the real
// openssl module of the host build in UBBF_BUILD_DIR, not the stand-in of
// tests/lib, and writes below /etc/ubbf and /tmp/ubbf (the instance map).
'use strict';

import * as fs from 'fs';
import { describe, it, assert, beforeEach } from 'utest';
import { state_clear } from 'test_env';
import * as ubbf from 'ubbf';

// This process numbers rows, as the agent does.
ubbf.instance_map_own(true);

let applied = [];

const api = {
	ubbf: proto({ cache_call: (fn, ...args) => fn(...args), cache_invalidate: () => null }, ubbf),
	utils: {},
	schema: (k) => k,
	schema_defaults: () => ({}),
	config_apply: (ops) => { push(applied, ...ops); return { success: true }; },
	model: {},
	operations: {}
};

function handler_load() {
	include('/usr/share/ucode/ubbf/modules/security/handler.uc', { ubbf_module: api });
}

function by_path(rows) {
	return sort(rows, (a, b) => (a.path < b.path) ? -1 : 1);
}

describe('security Delete() references', () => {
	beforeEach(() => {
		state_clear();
		applied = [];
	});

	it('clears the references to a deleted certificate and CA bundle', () => {
		for (let dir in [ '/etc/ubbf/certs', '/etc/ubbf/cabundles', '/etc/ubbf/cabundles/lab' ])
			fs.mkdir(dir, 0755);

		system('OPENSSL_CONF=/dev/null openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 1 -subj /CN=refs ' +
			'-keyout /etc/ubbf/certs/refs.key -out /etc/ubbf/certs/refs.pem 2>/dev/null');
		system('OPENSSL_CONF=/dev/null openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 1 -subj /CN=lab ' +
			'-keyout /dev/null -out /etc/ubbf/cabundles/lab/bundle.pem 2>/dev/null');

		handler_load();

		const cert_get = api.model['Device.Security.Certificate.{i}'].get;
		const bundle_get = api.model['Device.Security.CABundle.{i}'].get;
		let cert_inst, bundle_inst;

		for (let n, row in cert_get({}))
			if (row.Name == 'refs')
				cert_inst = n;
		for (let n, row in bundle_get({}))
			if (row.Name == 'lab')
				bundle_inst = n;

		assert.match([ true, true ], [ cert_inst != null, bundle_inst != null ], 'added certificate and bundle found');

		let cert = `Device.Security.Certificate.${cert_inst}`;
		let bundle = `Device.Security.CABundle.${bundle_inst}`;
		let other = `Device.Security.Certificate.${+cert_inst + 10}`;

		fs.writefile('/etc/ubbf/config.json', sprintf('%J', { Device: {
			UserInterface: { HTTPAccess: {
				'1': { Alias: 'a', Certificate: `${cert}.`, CABundle: bundle },
				'2': { Alias: 'b', Certificate: other, CABundle: '' }
			} },
			Syslog: { Action: { '1': { LogRemote: { Certificate: cert, CABundle: `${bundle}.` } } } },
			X: { List: `${other},${cert}.` }
		} }));

		let del = api.operations['Device.Security.Certificate.{i}.Delete()'].handler;
		assert.match({}, del({}, '', [ +cert_inst ], {}), 'Certificate Delete()');
		assert.match([
			{ op: 'set', path: 'Device.Syslog.Action.1.LogRemote.Certificate', value: '' },
			{ op: 'set', path: 'Device.UserInterface.HTTPAccess.1.Certificate', value: '' },
			{ op: 'set', path: 'Device.X.List', value: other }
		], by_path(applied), 'certificate references cleared');

		applied = [];
		del = api.operations['Device.Security.CABundle.{i}.Delete()'].handler;
		assert.match({}, del({}, '', [ +bundle_inst ], {}), 'CABundle Delete()');
		assert.match([
			{ op: 'set', path: 'Device.Syslog.Action.1.LogRemote.CABundle', value: '' },
			{ op: 'set', path: 'Device.UserInterface.HTTPAccess.1.CABundle', value: '' }
		], by_path(applied), 'bundle references cleared');

		applied = [];
		del = api.operations['Device.Security.Certificate.{i}.Delete()'].handler;
		assert.match(true, del({}, '', [ +cert_inst ], {}) < 0, 'Delete() of a gone certificate fails');
		assert.match([], applied, 'a failed Delete() clears nothing');
	});
});
