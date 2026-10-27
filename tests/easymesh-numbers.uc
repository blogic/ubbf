// Host test of the instance numbers of Device.WiFi.DataElements.Network.Device
// and Network.SSID in modules/easymesh: a device keeps its number, and its
// stored row, by AL MAC when the topology lists the devices in another
// order; an EasyMesh SSID keeps its number when another SSID is removed;
// outside EasyMesh, Network.SSID.{i} has the number of its WiFi.SSID row;
// a BSS keeps its number by BSSID and a STA by MAC, so ClientSteer()
// reaches the STA a read showed. The instance map lives in /tmp/ubbf, so
// run it in a private mount namespace; tests/instance-map/ holds a
// stand-in for ubus, tests/easymesh/ one for wde:
//   unshare -rm sh -c 'mount -t tmpfs none /tmp/ubbf && \
//     ucode -L "$PWD/tests/instance-map/*.uc" -L "$PWD/tests/easymesh/*.uc" \
//     -L "$PWD/tests/hosts/*.uc" -L "$PWD/files/usr/share/ucode" \
//     -L "<host build>/*.so" tests/easymesh-numbers.uc'
'use strict';

import * as ubbf from 'ubbf';
import { instance_numbers, instance_rows, instance_key } from 'ubbf.utils.instance-map';

let pass = 0, fail = 0;

function check(name, got, expected) {
	if (sprintf('%J', got) == sprintf('%J', expected)) { pass++; return; }
	fail++;
	printf('FAIL %s\n  expected %J\n  got      %J\n', name, expected, got);
}

const api = {
	ubbf,
	model: {},
	operations: {},
	schema: (k) => k,
	utils: {
		'instance-map': { instance_numbers, instance_rows, instance_key },
		logging: { log_info: () => null, log_warn: () => null, log_err: () => null },
		'wifi-dataelements': {
			topology_devices_get: () => global.topo,
			local_device_get: () => ({ al_address: 'local' }),
			ubus_topology_get: () => ({}),
			device_api_data_get: () => ({}),
			local_api_data_get: () => ({}),
			steering_stats_get: () => ({}),
			steering_history_get: () => ({}),
			radio_band_priority: () => 0
		}
	}
};

const em = {
	device_to_object: (device, api_data, is_controller, easymesh, cfg) => ({ ID: device.al_address, Tag: cfg?.Tag }),
	al_index_map: () => ({}),
	ap_by_ssid_ref_find: () => null,
	easymesh_model: {}
};

const DIR = sourcepath(0, true) + '/../modules/easymesh';
const device_stub = em.device_to_object;
include(DIR + '/objectdata.uc', { ubbf_module: api, em });
em.device_to_object = device_stub;
include(DIR + '/operations.uc', { ubbf_module: api, em });
include(DIR + '/dataelements.uc', { ubbf_module: api, em });

const device_get = api.model['Device.WiFi.DataElements.Network.Device.{i}'].get;
const ssid_get = api.model['Device.WiFi.DataElements.Network.SSID.{i}'].get;
const set_ssid = api.operations['Device.WiFi.DataElements.Network.SetSSID()'].handler;
const scan = api.operations['Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.ChannelScanRequest()'].handler;

function devices(root) {
	let out = {};
	for (let n, d in device_get({ root }))
		out[n] = [ d.ID, d.Tag ];
	return out;
}

function scan_result(root, device) {
	let msg;
	scan({}, 1, (inst, code, err) => { msg = err; }, [ device, 1 ], '', root);
	return msg;
}

let root = { Device: { WiFi: { DataElements: { Network: {
	X_UBBF_EasyMesh: { Controller: { Enable: 'true' } },
	Device: { '2': { Tag: 'stored-b' } }
} } } } };

global.topo = [ { al_address: 'aa' }, { al_address: 'bb' } ];
check('first numbers follow the topology', devices(root), { '1': [ 'aa', null ], '2': [ 'bb', 'stored-b' ] });

global.topo = [ { al_address: 'bb' }, { al_address: 'aa' } ];
check('another order moves no device and no stored row', devices(root), { '2': [ 'bb', 'stored-b' ], '1': [ 'aa', null ] });
check('one device by number', device_get({ root, instance: 2 }).ID, 'bb');

global.topo = [ { al_address: 'bb' } ];
check('a leaving device does not shift the other', devices(root), { '2': [ 'bb', 'stored-b' ] });
check('an operation on the gone device', scan_result(root, 1), 'Device not found');
check('an operation finds the device by number', scan_result(root, 2), 'Radio not found');

function ssids(root) {
	let out = {};
	for (let n, s in ssid_get({ root }))
		out[n] = s.SSID;
	return out;
}

function ssid_op(root, change, name) {
	set_ssid({ SSID: name, AddRemoveChange: change }, 1, () => null, '', root);
}

for (let name in [ 'x', 'y', 'z' ])
	ssid_op(root, 'Add', name);
check('SSIDs numbered as added', ssids(root), { '1': 'x', '2': 'y', '3': 'z' });
ssid_op(root, 'Remove', 'x');
check('a removal moves no other SSID', ssids(root), { '2': 'y', '3': 'z' });
ssid_op(root, 'Change', 'y');
ssid_op(root, 'Add', 'w');
check('a change keeps the number, an add takes the next', ssids(root), { '2': 'y', '3': 'z', '4': 'w' });
check('one SSID by number', ssid_get({ root, instance: 4 }).SSID, 'w');

root.EasyMesh.SSIDs = [ { ssid: 'p' }, { ssid: 'q' } ];
ssid_op(root, 'Add', 'r');
ssid_op(root, 'Remove', 'p');
check('entries without a number keep the one they had at the add', ssids(root), { '2': 'q', '3': 'r' });

let plain = { Device: { WiFi: { SSID: { '1': { SSID: 'a' }, '3': { SSID: 'c' } } } } };
check('outside EasyMesh the WiFi.SSID numbers', ssids(plain), { '1': 'a', '3': 'c' });

const steer = api.operations['Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.BSS.{i}.STA.{i}.ClientSteer()'].handler;

let bss_a = { mac_address: 'b1', associated_clients: [ { mac_address: 's1' }, { mac_address: 's2' } ] };
let bss_b = { mac_address: 'b2', associated_clients: [] };
let radio = { radio_unique_identifier: 'r1', bss: [ bss_a, bss_b ] };
check('BSS by number', em.bss_by_instance(radio, 2).mac_address, 'b2');
radio.bss = [ bss_b, bss_a ];
check('another BSS order moves no BSS', em.bss_by_instance(radio, 1).mac_address, 'b1');
check('STA by number', em.sta_by_instance(bss_a, 2).mac_address, 's2');
bss_a.associated_clients = [ { mac_address: 's2' } ];
check('a leaving STA does not shift the other', [ em.sta_by_instance(bss_a, 1), em.sta_by_instance(bss_a, 2).mac_address ], [ null, 's2' ]);

function steer_result(sta) {
	let msg;
	steer({ TargetBSSID: 'b9' }, 1, (inst, code, err) => { msg = err; }, [ 2, 1, 1, sta ], '', root);
	return msg;
}

global.topo = [ { al_address: 'bb', map: { ap_operational_bss: [ radio ] } } ];
check('ClientSteer on the gone STA', steer_result(1), 'STA not found');
check('ClientSteer finds the STA by number', steer_result(2) != 'STA not found', true);

printf('passed: %d\nfailed: %d\n', pass, fail);
exit(fail ? 1 : 0);
