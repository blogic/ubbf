// Host test of the security module: Certificate.{i}.Delete() and
// CABundle.{i}.Delete() clear the references to the deleted row in the
// stored configuration (TR-181: "If the referenced object is deleted, the
// parameter value MUST be set to an empty string"). It needs the real
// openssl module, not the stand-in of tests/render, and writes below /etc.
// Run from the repository root; <host build> holds ubbf.so and openssl.so:
//   unshare -rm sh -e -c 'repo=$PWD; mount -t tmpfs none /usr/share;
//     mkdir -p /usr/share/ucode/ubbf/modules;
//     for e in "$repo"/files/usr/share/ucode/ubbf/*; do ln -s "$e" /usr/share/ucode/ubbf/; done;
//     ln -s "$repo/modules/security" /usr/share/ucode/ubbf/modules/;
//     mount -t tmpfs none /etc; mount -t tmpfs none /run;
//     exec ucode -L /usr/share/ucode -L "$1/*.so" "$repo/tests/security-refs.uc"' sh <host build>
'use strict';

import * as fs from 'fs';
import * as ubbf from 'ubbf';

let pass = 0, fail = 0;

function check(name, got, expected) {
	if (sprintf('%J', got) == sprintf('%J', expected)) { pass++; return; }
	fail++;
	printf('FAIL %s\n  expected %J\n  got      %J\n', name, expected, got);
}

for (let dir in [ '/etc/ubbf', '/etc/ubbf/certs', '/etc/ubbf/cabundles', '/etc/ubbf/cabundles/lab' ])
	fs.mkdir(dir, 0755);

system('OPENSSL_CONF=/dev/null openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 1 -subj /CN=refs ' +
	'-keyout /etc/ubbf/certs/refs.key -out /etc/ubbf/certs/refs.pem 2>/dev/null');
system('OPENSSL_CONF=/dev/null openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 1 -subj /CN=lab ' +
	'-keyout /dev/null -out /etc/ubbf/cabundles/lab/bundle.pem 2>/dev/null');

let applied = [];

const api = {
	ubbf,
	utils: {
		cache: { call: (fn, ...args) => fn(...args), invalidate: () => null },
		logging: { log_warn: () => null }
	},
	schema: (k) => k,
	schema_defaults: () => ({}),
	config_apply: (ops) => { push(applied, ...ops); return { success: true }; },
	model: {},
	operations: {}
};
include('/usr/share/ucode/ubbf/modules/security/handler.uc', { ubbf_module: api });

const cert_get = api.model['Device.Security.Certificate.{i}'].get;
const bundle_get = api.model['Device.Security.CABundle.{i}'].get;
let cert_inst, bundle_inst;

for (let n, row in cert_get({}))
	if (row.Name == 'refs')
		cert_inst = n;
for (let n, row in bundle_get({}))
	if (row.Name == 'lab')
		bundle_inst = n;

check('added certificate and bundle found', [ cert_inst != null, bundle_inst != null ], [ true, true ]);

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
check('Certificate Delete()', del({}, '', [ +cert_inst ], {}), {});
check('certificate references cleared', sort(applied, (a, b) => (a.path < b.path) ? -1 : 1), [
	{ op: 'set', path: 'Device.Syslog.Action.1.LogRemote.Certificate', value: '' },
	{ op: 'set', path: 'Device.UserInterface.HTTPAccess.1.Certificate', value: '' },
	{ op: 'set', path: 'Device.X.List', value: other }
]);

applied = [];
del = api.operations['Device.Security.CABundle.{i}.Delete()'].handler;
check('CABundle Delete()', del({}, '', [ +bundle_inst ], {}), {});
check('bundle references cleared', sort(applied, (a, b) => (a.path < b.path) ? -1 : 1), [
	{ op: 'set', path: 'Device.Syslog.Action.1.LogRemote.CABundle', value: '' },
	{ op: 'set', path: 'Device.UserInterface.HTTPAccess.1.CABundle', value: '' }
]);

applied = [];
del = api.operations['Device.Security.Certificate.{i}.Delete()'].handler;
check('Delete() of a gone certificate fails', del({}, '', [ +cert_inst ], {}) < 0, true);
check('a failed Delete() clears nothing', applied, []);

printf('passed: %d\nfailed: %d\n', pass, fail);
exit(fail ? 1 : 0);
