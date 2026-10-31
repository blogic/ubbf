// No secret value leaves the device's apply in clear. A config sets every
// parameter the schemas mark secured, and every field EASYMESH_SECRETS names,
// to a value of its own. The render must write each such value that it renders
// into the UCI batch, and its masked batch and its logs must hold none of them.
// bbf-cli prints none of them for `apply -n`, `apply -n -v` and `apply`, with
// the reply that the bbf-device apply of this tree gives for the same config.
'use strict';

import * as fs from 'fs';
import { describe, it, assert, mock, beforeEach } from 'utest';
import { state_clear } from 'test_env';
import * as ubbf from 'ubbf';
import { render_scope_build, templates_render } from 'ubbf.render.renderer';
import { uci_secret_set, uci_output_masked, EASYMESH_SECRETS } from 'ubbf.render.uci_helpers';

const REPO = fs.getcwd();
const TESTS = `${REPO}/tests`;
const CONFIG_PATH = '/tmp/ubbf/secret-output.json';
const REPLY_PATH = '/tmp/ubbf/secret-output-reply.json';
const HWSIM = 'virtual/mac80211_hwsim/hwsim0';
const CAPABILITIES = { radios: [
	{ band: '2g', path: HWSIM, name: 'radio0', radio: 0, phy: 'phy0', freq_ranges: [ [ 2402000, 2494000 ] ] },
	{ band: '5g', path: HWSIM, name: 'radio1', radio: 1, phy: 'phy0', freq_ranges: [ [ 5170000, 5935000 ] ] }
] };

function config_base() {
	let ap = (ssid, mode) => ({
		Enable: 'true', SSIDReference: `Device.WiFi.SSID.${ssid}`,
		Security: { ModeEnabled: mode, RadiusServerIPAddr: '192.0.2.1', RadiusServerPort: '1812' },
		Accounting: { Enable: 'true', ServerIPAddr: '192.0.2.2', ServerPort: '1813' },
		WPS: { Enable: 'true', ConfigMethodsEnabled: 'PushButton,PIN' }
	});
	let radio = (name, band, channel) => ({ Enable: 'true', Name: name, OperatingFrequencyBand: band,
		Channel: channel, AutoChannelEnable: 'false', OperatingChannelBandwidth: '20MHz' });

	return {
		Device: {
			WiFi: {
				Radio: { '1': radio('radio0', '2.4GHz', '6'), '2': radio('radio1', '5GHz', '36') },
				SSID: {
					'1': { Enable: 'true', SSID: 'personal', LowerLayers: 'Device.WiFi.Radio.1' },
					'2': { Enable: 'true', SSID: 'enterprise', LowerLayers: 'Device.WiFi.Radio.2' },
					'3': { Enable: 'true', SSID: 'mld', LowerLayers: 'Device.WiFi.Radio.1' },
					'4': { Enable: 'true', SSID: 'mld', LowerLayers: 'Device.WiFi.Radio.2' },
					'5': { Enable: 'true', SSID: 'mldent', LowerLayers: 'Device.WiFi.Radio.1' },
					'6': { Enable: 'true', SSID: 'mldent', LowerLayers: 'Device.WiFi.Radio.2' },
					'7': { Enable: 'true', SSID: 'unbridged', LowerLayers: 'Device.WiFi.Radio.1' },
					'8': { Enable: 'true', SSID: 'sae', LowerLayers: 'Device.WiFi.Radio.2' }
				},
				AccessPoint: {
					'1': ap(1, 'WPA2-Personal'),
					'2': ap(2, 'WPA2-Enterprise'),
					'3': { ...ap(3, 'WPA2-Personal'), APMLDTemplateRef: 'Device.WiFi.Templates.APMLDTemplate.1' },
					'4': { ...ap(4, 'WPA2-Personal'), APMLDTemplateRef: 'Device.WiFi.Templates.APMLDTemplate.1' },
					'5': { ...ap(5, 'WPA2-Enterprise'), APMLDTemplateRef: 'Device.WiFi.Templates.APMLDTemplate.2' },
					'6': { ...ap(6, 'WPA2-Enterprise'), APMLDTemplateRef: 'Device.WiFi.Templates.APMLDTemplate.2' },
					'7': ap(8, 'WPA3-Personal')
				},
				Templates: { APMLDTemplate: { '1': { MLOEnable: 'true' }, '2': { MLOEnable: 'true' } } },
				DataElements: { Network: { X_UBBF_EasyMesh: {
					Bridge: 'Device.Bridging.Bridge.1',
					Controller: { Enable: 'true' }
				} } }
			},
			Bridging: { Bridge: { '1': { Enable: 'true', Name: 'br-lan', Port: {
				'1': { Enable: 'true', ManagementPort: 'true' },
				'2': { Enable: 'true', LowerLayers: 'Device.WiFi.SSID.1,Device.WiFi.SSID.2,Device.WiFi.SSID.3,' +
					'Device.WiFi.SSID.4,Device.WiFi.SSID.5,Device.WiFi.SSID.6,Device.WiFi.SSID.8' }
			} } } },
			IP: { Interface: {
				'1': { Enable: 'true', Name: 'lan', LowerLayers: 'Device.Bridging.Bridge.1.Port.1' },
				'2': { Enable: 'true', Name: 'wwan', LowerLayers: 'Device.Cellular.Interface.1' }
			} },
			PPP: { Interface: { '1': { Enable: 'true', Name: 'wan', Username: 'u' } } },
			DynamicDNS: {
				Server: { '1': { Enable: 'true', ServiceName: 'dyndns.org' } },
				Client: { '1': { Enable: 'true', Server: 'Device.DynamicDNS.Server.1', Username: 'u',
					Interface: 'Device.IP.Interface.1',
					Hostname: { '1': { Enable: 'true', Name: 'h.example' } } } }
			},
			BulkData: { Enable: 'true', Profile: { '1': { Enable: 'true', Name: 'p', Protocol: 'HTTP',
				EncodingType: 'JSON', ReportingInterval: '300', HTTP: { URL: 'https://b.example', Username: 'u' } } } },
			Cellular: {
				Interface: { '1': { Enable: 'true', X_UBBF_Device: '/sys/devices/modem0', USIM: {} } },
				AccessPoint: { '1': { Enable: 'true', Interface: 'Device.Cellular.Interface.1', APN: 'apn', Username: 'u' } }
			}
		},
		EasyMesh: {
			Controller: { c_sign_key_pubkey_x: 'aa', connector: 'eyJ' },
			SSIDs: [ { enabled: true, ssid: 'mesh', fronthaul: true, band: [ '2g' ] } ]
		}
	};
}

function schema_definitions() {
	let names = map(fs.glob(`${REPO}/files/usr/share/ucode/ubbf/schemas/*.uc`),
		(f) => replace(fs.basename(f), /\.uc$/, ''));
	let src = '';
	for (let n in names)
		src += `import * as m_${n} from 'ubbf.schemas.${n}';\n`;
	src += 'return [ ' + join(', ', map(names, (n) => `m_${n}`)) + ' ];\n';

	let sets = loadstring(src)();
	for (let path in fs.glob(`${REPO}/modules/*/schema.uc`)) {
		let schemas = {};
		include(path, { schemas });
		push(sets, schemas);
	}
	return sets;
}

// Object pattern to the names of its parameters that a schema marks secured.
function secured_params() {
	let out = {};
	for (let set in schema_definitions())
		for (let name, def in set)
			for (let param, rule in def?.constraints ?? {})
				if (rule.secured)
					push(out[rtrim(def.path, '.')] ??= [], param);
	return out;
}

// Calls fn on every object of the config that an object pattern names, and
// makes the object, with instance 1 for a {i}, where the config has none.
function pattern_walk(node, parts, fn) {
	if (!length(parts))
		return fn(node);

	let part = parts[0];
	let rest = slice(parts, 1);
	if (part != '{i}') {
		node[part] ??= {};
		return pattern_walk(node[part], rest, fn);
	}

	if (!length(keys(node)))
		node['1'] = {};
	for (let inst, child in node)
		pattern_walk(child, rest, fn);
}

// Gives each secured parameter and each EasyMesh secret field of config a value
// of its own; a parameter takes one value in every instance, so the links of an
// AP MLD agree. A value has the 64 digits that a PreSharedKey needs. Returns each
// value with its name, "<pattern>.<param>".
function secrets_set(config, secured) {
	let names = {};
	let n = 0;

	let value_new = (name) => {
		let value = sprintf('5ec%061d', n++);
		names[value] = name;
		return value;
	};

	for (let pattern, params in secured) {
		for (let param in params) {
			let value = value_new(`${pattern}.${param}`);
			pattern_walk(config, split(pattern, '.'), (obj) => { obj[param] = value; });
		}
	}

	for (let section, fields in EASYMESH_SECRETS) {
		let node = config.EasyMesh[section];
		for (let field in fields) {
			let value = value_new(`EasyMesh.${section}.${field}`);
			for (let obj in (type(node) == 'array') ? node : [ node ])
				obj[field] = value;
		}
	}

	return names;
}

function render(config) {
	let output = [], logs = [], effects = [];
	let scope = render_scope_build(config, output, logs, effects);
	let scope_fs = scope.fs;
	scope.fs = { ...scope_fs, stat: (p) => (p == '/usr/sbin/umapd') ? { type: 'file' } : scope_fs.stat(p) };

	templates_render(scope);

	push(output, '');
	return { uci: join('\n', output), masked: uci_output_masked(output, scope.uci_secrets), logs };
}

function secrets_in(names, text) {
	return sort(map(filter(keys(names), (v) => index(text, v) >= 0), (v) => names[v]));
}

function process_read(cmd) {
	let p = fs.popen(cmd, 'r');
	let out = p.read('all');
	return { out, rc: p.close() };
}

const LIB_PATHS = `-L '${TESTS}/lib/*.uc' -L /usr/share/ucode -L '${getenv('UBBF_BUILD_DIR')}/*.so'`;

// The bbf-device apply of this tree in a mount namespace of its own: the device
// has umapd, and /usr/libexec/ubbf/apply is the apply of this tree.
function device_apply_reply() {
	let shadow = `shadow() { host=$(mktemp -d); mount --bind "$1" "$host"; mount -t tmpfs none "$1"; ` +
		`for entry in "$host"/*; do ln -s "$entry" "$1"/; done; }; ` +
		`shadow /usr/sbin; touch /usr/sbin/umapd; shadow /usr/libexec; rm -f /usr/libexec/ubbf; mkdir /usr/libexec/ubbf; ` +
		`printf '#!/bin/sh\\nexec ucode -L "${TESTS}/datamodel/*.uc" ${replace(LIB_PATHS, /'/g, '"')} ${REPO}/files/usr/libexec/ubbf/apply "$@"\\n' > /usr/libexec/ubbf/apply; ` +
		`chmod +x /usr/libexec/ubbf/apply; ` +
		`exec ucode -L '${TESTS}/datamodel/*.uc' ${LIB_PATHS} ${TESTS}/secret-output/device-apply.uc ${CONFIG_PATH}`;
	let r = process_read(`unshare -m sh -ec ${ubbf.shell_escape(shadow)}`);
	assert.match(0, r.rc, `the apply method runs: ${r.out}`);
	return json(r.out);
}

function cli_run(args) {
	return process_read(`APPLY_REPLY=${REPLY_PATH} ucode -L '${TESTS}/secret-output/*.uc' ${LIB_PATHS} ` +
		`${REPO}/files/usr/bin/bbf-cli ${args} 2>&1`);
}

// What the fixture renders; a secret that is not here has no render site, or
// the fixture does not reach it.
const RENDERED = [
	'Device.BulkData.Profile.{i}.HTTP.Password',
	'Device.Cellular.AccessPoint.{i}.Password',
	'Device.Cellular.Interface.{i}.USIM.PIN',
	'Device.DynamicDNS.Client.{i}.Password',
	'Device.PPP.Interface.{i}.Password',
	'Device.WiFi.AccessPoint.{i}.Accounting.Secret',
	'Device.WiFi.AccessPoint.{i}.Security.KeyPassphrase',
	'Device.WiFi.AccessPoint.{i}.Security.PreSharedKey',
	'Device.WiFi.AccessPoint.{i}.Security.RadiusSecret',
	'Device.WiFi.AccessPoint.{i}.Security.SAEPassphrase',
	'Device.WiFi.AccessPoint.{i}.WPS.PIN',
	'EasyMesh.Controller.c_sign_key_privkey',
	'EasyMesh.Controller.net_access_key_privkey',
	'EasyMesh.Controller.pp_key_privkey',
	'EasyMesh.SSIDs.key'
];

describe('secret output of apply', () => {
	let config, names;

	beforeEach(() => {
		mock.global.patch('uci', { data: {} });
		state_clear();
		fs.writefile('/tmp/ubbf/capabilities.json', sprintf('%J', CAPABILITIES));
		config = config_base();
		names = secrets_set(config, secured_params());
		// The personal AP MLD renders its PreSharedKey, the other AP its passphrase.
		for (let ap in [ '3', '4' ])
			delete config.Device.WiFi.AccessPoint[ap].Security.KeyPassphrase;
	});

	it('sets an empty secret as it is and no null one, and masks the others', () => {
		let output = [], secrets = [];
		uci_secret_set(output, secrets, 'a.b.empty', '');
		uci_secret_set(output, secrets, 'a.b.none', null);
		uci_secret_set(output, secrets, 'a.b.key', "it's");
		push(output, '');

		assert.match([ "set a.b.empty=\nset a.b.key='it'\\''s'\n", "set a.b.empty=\nset a.b.key='<secret>'\n" ],
			[ join('\n', output), uci_output_masked(output, secrets) ]);
	});

	it('masks each secret in the batch a render shows, and keeps it in the batch it commits', () => {
		let r = render(config);

		assert.match(RENDERED, secrets_in(names, r.uci), 'the render writes every secret the fixture reaches');
		assert.match(2, length(match(r.uci, /wireless\.@wifi-iface\[-1\]\.mlo=1/g)),
			'the fixture renders a personal and an enterprise AP MLD, whose keys come from the MLD path');
		assert.match([], secrets_in(names, r.masked), 'the masked batch holds no secret');
		assert.match([], secrets_in(names, sprintf('%J', r.logs)), 'the logs hold no secret');

		let lines = split(r.uci, '\n');
		let masked = split(r.masked, '\n');
		let wrong = [];
		for (let i, line in lines) {
			let m = match(line, /^(set [^=]+=)'(.*)'$/);
			let expected = (m && exists(names, m[2])) ? `${m[1]}'<secret>'` : line;
			if (masked[i] != expected)
				push(wrong, [ line, masked[i] ]);
		}
		assert.match([ length(lines), [] ], [ length(masked), wrong ],
			'the masked batch shows each secret line as <secret> and every other line as it is');
	});

	it('prints no secret through bbf-cli', () => {
		fs.writefile(CONFIG_PATH, sprintf('%J', config));
		let reply = device_apply_reply();
		fs.writefile(REPLY_PATH, sprintf('%J', reply));

		assert.match([ true, [ 'easymesh' ], [] ], [
			reply.success,
			match(reply.output, /umapd\.controller\.pp_key_privkey='<secret>'/) ? [ 'easymesh' ] : [],
			secrets_in(names, sprintf('%J', reply))
		], `the reply of the apply method holds the masked batch and no secret: ${reply.error ?? ''}`);

		for (let c in [ [ 'apply -n', false ], [ `apply -n -v`, true ], [ 'apply', false ] ]) {
			let r = cli_run(c[0]);
			let verbose = c[1];

			assert.match([ 0, [] ], [ r.rc, secrets_in(names, r.out) ], `bbf-cli ${c[0]} succeeds and prints no secret`);
			assert.match([ verbose, verbose, verbose ], [
				index(r.out, '=== UCI Commands ===') >= 0,
				index(r.out, "network.wan.password='<secret>'") >= 0,
				index(r.out, '[WARNING] SSID unbridged has no Network configured') >= 0
			], `bbf-cli ${c[0]} prints the batch and the logs only with -v`);
		}
	});
});
