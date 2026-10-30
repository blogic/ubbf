// Host test of the instance numbers of Device.WiFi.DataElements.Network.Device
// and Network.SSID in modules/easymesh: a device keeps its number, and its
// stored row, by AL MAC when the topology lists the devices in another
// order; an EasyMesh SSID keeps its number when another SSID is removed;
// outside EasyMesh, Network.SSID.{i} has the number of its WiFi.SSID row;
// a BSS keeps its number by BSSID and a STA by MAC, so ClientSteer()
// reaches the STA a read showed. The instance map lives in /tmp/ubbf.
'use strict';

import { describe, it, assert, beforeEach, setup } from 'utest';
import { state_clear } from 'test_env';
import { netifd_patch } from 'netifd_mock';
import * as ubbf from 'ubbf';
import { capability_radios_get } from 'ubbf.utils.capabilities';
import { radio_instances_for_bands } from 'ubbf.utils.wifi_radio';
import { radios_bss_sort } from 'ubbf.utils.wifi-dataelements';

let topo;

const api = {
	ubbf,
	model: {},
	operations: {},
	schema: (k) => k,
	utils: {
		'wifi-dataelements': {
			topology_devices_get: () => topo,
			local_device_get: () => ({ al_address: 'local' }),
			ubus_topology_get: () => ({}),
			device_api_data_get: () => ({}),
			local_api_data_get: () => ({}),
			steering_stats_get: () => ({}),
			steering_history_get: () => ({}),
			radios_bss_sort
		},
		capabilities: { capability_radios_get },
		wifi_radio: { radio_instances_for_bands }
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
const steer = api.operations['Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.BSS.{i}.STA.{i}.ClientSteer()'].handler;

function root_new() {
	return { Device: { WiFi: { DataElements: { Network: {
		X_UBBF_EasyMesh: { Controller: { Enable: 'true' } },
		Device: { '2': { Tag: 'stored-b' } }
	} } } } };
}

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

function steer_result(root, sta) {
	let msg;
	steer({ TargetBSSID: 'b9' }, 1, (inst, code, err) => { msg = err; }, [ 2, 1, 1, sta ], '', root);
	return msg;
}

function ssids(root) {
	let out = {};
	for (let n, s in ssid_get({ root }))
		out[n] = s.SSID;
	return out;
}

function ssid_op(root, change, name) {
	set_ssid({ SSID: name, AddRemoveChange: change }, 1, () => null, '', root);
}

// This process numbers rows, as the agent does.
setup(() => ubbf.instance_map_own(true));

describe('DataElements instance numbers', () => {
	beforeEach(() => {
		state_clear();
		netifd_patch({});
		topo = null;
	});

	it('keeps the Device, BSS and STA numbers, so that an operation reaches the row a read showed', () => {
		let root = root_new();

		topo = [ { al_address: 'aa' }, { al_address: 'bb' } ];
		assert.match({ '1': [ 'aa', null ], '2': [ 'bb', 'stored-b' ] }, devices(root), 'first numbers follow the topology');

		topo = [ { al_address: 'bb' }, { al_address: 'aa' } ];
		assert.match({ '2': [ 'bb', 'stored-b' ], '1': [ 'aa', null ] }, devices(root), 'another order moves no device and no stored row');
		assert.match('bb', device_get({ root, instance: 2 }).ID, 'one device by number');

		topo = [ { al_address: 'bb' } ];
		assert.match({ '2': [ 'bb', 'stored-b' ] }, devices(root), 'a leaving device does not shift the other');
		assert.match('Device not found', scan_result(root, 1), 'an operation on the gone device');
		assert.match('Radio not found', scan_result(root, 2), 'an operation finds the device by number');

		let bss_a = { mac_address: 'b1', associated_clients: [ { mac_address: 's1' }, { mac_address: 's2' } ] };
		let bss_b = { mac_address: 'b2', associated_clients: [] };
		let radio = { radio_unique_identifier: 'r1', bss: [ bss_a, bss_b ] };
		assert.match('b2', em.bss_by_instance(radio, 2).mac_address, 'BSS by number');
		radio.bss = [ bss_b, bss_a ];
		assert.match('b1', em.bss_by_instance(radio, 1).mac_address, 'another BSS order moves no BSS');
		assert.match('s2', em.sta_by_instance(bss_a, 2).mac_address, 'STA by number');
		bss_a.associated_clients = [ { mac_address: 's2' } ];
		assert.match([ null, 's2' ], [ em.sta_by_instance(bss_a, 1), em.sta_by_instance(bss_a, 2).mac_address ],
			'a leaving STA does not shift the other');

		topo = [ { al_address: 'bb', map: { ap_operational_bss: [ radio ] } } ];
		assert.match('STA not found', steer_result(root, 1), 'ClientSteer on the gone STA');
		assert.match(true, steer_result(root, 2) != 'STA not found', 'ClientSteer finds the STA by number');
	});

	it('keeps the number of an EasyMesh SSID when another SSID is removed', () => {
		let root = root_new();

		for (let name in [ 'x', 'y', 'z' ])
			ssid_op(root, 'Add', name);
		assert.match({ '1': 'x', '2': 'y', '3': 'z' }, ssids(root), 'SSIDs numbered as added');
		ssid_op(root, 'Remove', 'x');
		assert.match({ '2': 'y', '3': 'z' }, ssids(root), 'a removal moves no other SSID');
		ssid_op(root, 'Change', 'y');
		ssid_op(root, 'Add', 'w');
		assert.match({ '2': 'y', '3': 'z', '4': 'w' }, ssids(root), 'a change keeps the number, an add takes the next');
		assert.match('w', ssid_get({ root, instance: 4 }).SSID, 'one SSID by number');

		root.EasyMesh.SSIDs = [ { ssid: 'p' }, { ssid: 'q' } ];
		ssid_op(root, 'Add', 'r');
		ssid_op(root, 'Remove', 'p');
		assert.match({ '2': 'q', '3': 'r' }, ssids(root), 'entries without a number keep the one they had at the add');
	});

	it('gives Network.SSID the numbers of WiFi.SSID outside EasyMesh', () => {
		let plain = { Device: { WiFi: { SSID: { '1': { SSID: 'a' }, '3': { SSID: 'c' } } } } };
		assert.match({ '1': 'a', '3': 'c' }, ssids(plain));
	});
});
