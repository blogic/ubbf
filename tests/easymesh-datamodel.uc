// Host test of modules/easymesh as datamodel.uc loads it: the module
// registers, and a Get of a DataElements STA row through the data model
// takes IPV4Address and Hostname from the dnsmasq lease and IPV6Address
// from the odhcpd lease of the station, through the utils.dhcp that the
// module API gives. A handler that requires both ubus and uci (location)
// registers too, so the stand-ins of tests/datamodel serve require().
// The datamodel loads config.json when it loads, which the utest worker
// must not do, so the test runs this file again in a plain ucode process
// with PHASE set, the stand-ins of tests/datamodel and tests/lib, and
// ubbf.datamodel and modules_registered in the scope. The process prints
// its results, and the test asserts on them.
'use strict';

import * as fs from 'fs';
import { describe, it, assert, beforeEach } from 'utest';
import { state_clear } from 'test_env';

const AL = '02:00:00:00:00:a1';
const RUID = '02:00:00:00:05:00';
const BSSID = '02:00:00:00:05:01';
const STA = '0a:00:00:00:00:01';
const NETWORK = 'Device.WiFi.DataElements.Network';
const RESULT_TAG = 'easymesh-datamodel result: ';

function result(name, got) {
	print(RESULT_TAG, sprintf('%J', { name, got }), '\n');
}

function phase_run(datamodel) {
	global.ubus_replies = {
		umap: {
			get_topology: { devices: [ { al_address: AL, map: {
				supported_services: [ { supported_service: 1 } ],
				ap_operational_bss: [ { radio_unique_identifier: RUID, bss: [
					{ mac_address: BSSID, associated_clients: [ { mac_address: STA } ] }
				] } ]
			} } ] }
		},
		dhcp: {
			ipv6leases: { device: { 'br-lan': { leases: [
				{ mac: STA, 'ipv6-addr': [ { address: '2001:db8::102' } ] }
			] } } }
		}
	};

	result('registered', [ modules_registered.easymesh ?? false, modules_registered.location ?? false ]);

	let devices = datamodel.dm.get_subtree_with_state(`${NETWORK}.Device`);
	let sta = devices?.['1']?.Radio?.['1']?.BSS?.['1']?.STA?.['1'];
	result('sta', [ sta?.MACAddress, sta?.IPV4Address, sta?.IPV6Address, sta?.Hostname ]);
}

function process_run() {
	let build_dir = getenv('UBBF_BUILD_DIR');
	let tests = `${fs.getcwd()}/tests`;
	let p = fs.popen(`PHASE=1 ucode -L '${tests}/datamodel/*.uc' -L '${tests}/lib/*.uc' ` +
		`-L /usr/share/ucode -L '${build_dir}/*.so' ` +
		`-e 'import * as datamodel from "ubbf.datamodel"; import { modules_registered } from "ubbf.utils.modules"; ` +
		`include("${tests}/easymesh-datamodel.uc", { datamodel, modules_registered });' 2>&1`, 'r');
	let output = p.read('all');
	let status = p.close();
	let results = {};

	for (let line in split(output, '\n'))
		if (index(line, RESULT_TAG) == 0) {
			let r = json(substr(line, length(RESULT_TAG)));
			results[r.name] = r.got;
		}

	assert.match(0, status, `the process exits 0: ${output}`);
	return results;
}

if (getenv('PHASE') == '1')
	phase_run(datamodel);
else
	describe('easymesh through datamodel.uc', () => {
		beforeEach(() => {
			state_clear();
			let config = json(fs.readfile('/usr/share/ucode/ubbf/initial.json'));
			config.Device.WiFi ??= {};
			config.Device.WiFi.DataElements = { Network: { X_UBBF_EasyMesh: { Controller: { Enable: true } } } };
			fs.writefile('/etc/ubbf/config.json', sprintf('%J', config));
			fs.writefile('/tmp/dhcp.leases', sprintf('%d %s 192.168.1.102 laptop *\n', time() + 600, STA));
		});

		it('registers the module and fills a STA row from the leases', () => {
			let results = process_run();

			assert.match([ true, true ], results.registered, 'easymesh and location register');
			assert.match([ STA, '192.168.1.102', '2001:db8::102', 'laptop' ], results.sta);
		});
	});
