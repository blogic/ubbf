// Host test of the usfpd module handler: SFF8472 numbering and
// SFPReference, the Status, MaxBitRate and Upstream of Optical.Interface,
// and the errors of Stats.Reset(). The usfpd answers come from a ubus mock.
'use strict';

import { describe, it, assert, mock, beforeEach } from 'utest';
import { state_clear } from 'test_env';
import * as ubbf from 'ubbf';

// Answers the usfpd methods from u, { cages: [ names ], status: { name:
// cage_status }, optical: { name: optical_status }, transceiver: { name:
// transceiver } }.
function usfpd_set(u) {
	mock.global.patch('ubus', { behavior: { call: (object, method, args) => {
		if (object != 'usfpd')
			return null;
		if (method == 'cages')
			return { cages: u.cages ?? [] };
		if (method == 'cage_status')
			return u.status?.[args.name];
		if (method == 'optical_status')
			return u.optical?.[args.name];
		if (method == 'transceiver')
			return u.transceiver?.[args.name];
		return null;
	} } });
}

function usfpd_new() {
	return {
		cages: [ 'sfp1', 'sfp2' ],
		status: {
			sfp1: { Name: 'sfp1', SFPPresent: false },
			sfp2: { Name: 'sfp2', SFPPresent: true, Optical: true, SFPType: 'Optical Ethernet' }
		},
		optical: { sfp2: { Name: 'eth2', Status: 'Up' } },
		transceiver: { sfp2: { vendor: { VendorName: 'FS', VendorOUI: '009065', VendorPN: 'SFP-10GSR-85' } } }
	};
}

// The handler requires ubus when it loads, so it loads after the mock.
// ifstats.reset_ok steers the result of ifstats_reset().
function handler_load() {
	let ifstats = { ifstats_get: () => ({}), ifstats_basic_get: () => ({}) };
	ifstats.reset_ok = true;
	ifstats.ifstats_reset = () => ifstats.reset_ok;

	let api = {
		ubbf: proto({ cache_call: (fn, ...args) => fn(...args),
			ethtool_properties_get: () => ({ SupportedLinkModes: '1000baseX/Full,10000baseSR/Full,2500baseX/Full' }),
			upstream_interface_ref: (root) => root?.Device?.IP?.Interface ? 'Device.IP.Interface.1' : null }, ubbf),
		utils: {
			'dm-version': { dm_visible: () => true },
			netdev_change: { last_change_get: (netdev) => (netdev == 'eth2') ? '42' : '0' },
			netifd: { netifd_status_get: (name) => (name == 'wan') ? { device: 'eth2' } : null },
			ifstats
		},
		schema: (k) => k,
		model: {},
		operations: {}
	};

	include('../modules/usfpd/handler.uc', { ubbf_module: api });
	return api;
}

describe('usfpd handler', () => {
	beforeEach(() => {
		state_clear();
		ubbf.instance_map_own(true);
	});

	it('numbers the SFF8472 rows by cage', () => {
		usfpd_set(usfpd_new());
		const m = handler_load().model;

		let cages = m['Device.SFPs.SFPCage.{i}'].get({ root: {} });
		assert.match('Device.SFPs.Mgmt.SFF8472.2.', cages['2'].SFPReference, 'SFPReference of the second cage names SFF8472 row 2');
		assert.match('', cages['1'].SFPReference, 'an empty cage has no SFPReference');
		assert.match([ '2' ], keys(m['Device.SFPs.Mgmt.SFF8472.{i}'].get({})), 'SFF8472 rows are numbered by cage');
		assert.match('sfp2', m['Device.SFPs.Mgmt.SFF8472.{i}'].get({ instance: 2 }).Name, 'SFF8472 row 2 is the second cage');
		assert.match(null, m['Device.SFPs.Mgmt.SFF8472.{i}'].get({ instance: 1 }), 'SFF8472 row 1 is absent');
		assert.match(null, m['Device.SFPs.Mgmt.SFF8472.{i}'].get({ instance: 0 }), 'SFF8472 row 0 is absent');
	});

	it('reads the Status, MaxBitRate and Upstream of Optical.Interface', () => {
		let u = usfpd_new();
		usfpd_set(u);
		const optical = handler_load().model['Device.Optical.Interface.{i}'];
		const wan_root = { Device: { IP: { Interface: { '1': { Name: 'wan', Upstream: 'true' } } } } };

		let row = optical.get({ root: wan_root })['1'];
		assert.match([ 'eth2', 'Up', '10000', '42', 'true', 'Device.SFPs.SFPCage.2' ],
			[ row.Name, row.Status, row.MaxBitRate, row.LastChange, row.Upstream, row.SFPReferenceList ], 'optical row');
		assert.match('false', optical.get({ instance: 1, root: {} }).Upstream, 'not upstream without a WAN interface');
		assert.match('Down', optical.get({ instance: 1, config: { Enable: 'false' }, root: {} }).Status, 'Enable false reads Down');

		let blocked_root = { Device: { SFPs: { AllowedSFPs: { AllowAllSFPs: 'false' } } } };
		assert.match('NotAllowed', optical.get({ instance: 1, root: blocked_root }).Status, 'a refused SFP reads NotAllowed');

		u.optical = {};
		assert.match('Unknown', optical.get({ instance: 1, root: {} }).Status, 'no answer from usfpd reads Unknown');
	});

	it('returns the errors of Stats.Reset()', () => {
		usfpd_set(usfpd_new());
		const api = handler_load();
		const reset = api.operations['Device.Optical.Interface.{i}.Stats.Reset()'].handler;

		assert.match(-USP_ERR_OBJECT_DOES_NOT_EXIST, reset({}, '', [ 7 ]), 'Stats.Reset() of a row without SFP');
		api.utils.ifstats.reset_ok = false;
		assert.match(-USP_ERR_COMMAND_FAILURE, reset({}, '', [ 1 ]), 'Stats.Reset() that fails');
		api.utils.ifstats.reset_ok = true;
		assert.match({}, reset({}, '', [ 1 ]), 'Stats.Reset()');
	});
});
