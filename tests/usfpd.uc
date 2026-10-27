// Host test of the usfpd module handler: SFF8472 numbering and
// SFPReference, the Status, MaxBitRate and Upstream of Optical.Interface,
// and the errors of Stats.Reset(). The instance map lives in /etc/ubbf, so
// run it in a private mount namespace; tests/usfpd/ holds a stand-in for
// ubus, tests/hosts/ one for udebug:
//   unshare -rm sh -c 'mount -t tmpfs none /etc/ubbf &&
//     mount -t tmpfs none /tmp/ubbf && ucode -L "$PWD/tests/usfpd/*.uc" \
//     -L "$PWD/tests/hosts/*.uc" -L "$PWD/files/usr/share/ucode" \
//     -L "<host build>/*.so" tests/usfpd.uc'
'use strict';

import * as ubbf from 'ubbf';
import { instance_numbers, instance_key, instance_rows } from 'ubbf';

// This process numbers rows, as the agent does.
ubbf.instance_map_own(true);

let pass = 0, fail = 0;

function check(name, got, expected) {
	if (sprintf('%J', got) == sprintf('%J', expected)) { pass++; return; }
	fail++;
	printf('FAIL %s\n  expected %J\n  got      %J\n', name, expected, got);
}

let reset_ok = true;

const api = {
	ubbf: proto({ cache_call: (fn, ...args) => fn(...args),
		ethtool_properties_get: () => ({ SupportedLinkModes: '1000baseX/Full,10000baseSR/Full,2500baseX/Full' }),
		upstream_interface_ref: (root) => root?.Device?.IP?.Interface ? 'Device.IP.Interface.1' : null }, ubbf),
	utils: {
		'dm-version': { dm_visible: () => true },
		netdev_change: { last_change_get: (netdev) => (netdev == 'eth2') ? '42' : '0' },
		netifd: { netifd_status_get: (name) => (name == 'wan') ? { device: 'eth2' } : null },
		ifstats: { ifstats_get: () => ({}), ifstats_basic_get: () => ({}), ifstats_reset: () => reset_ok }
	},
	schema: (k) => k,
	model: {},
	operations: {}
};

include('../modules/usfpd/handler.uc', { ubbf_module: api });

const m = api.model;
const reset = api.operations['Device.Optical.Interface.{i}.Stats.Reset()'].handler;

global.USFPD = {
	cages: [ 'sfp1', 'sfp2' ],
	status: {
		sfp1: { Name: 'sfp1', SFPPresent: false },
		sfp2: { Name: 'sfp2', SFPPresent: true, Optical: true, SFPType: 'Optical Ethernet' }
	},
	optical: { sfp2: { Name: 'eth2', Status: 'Up' } },
	transceiver: { sfp2: { vendor: { VendorName: 'FS', VendorOUI: '009065', VendorPN: 'SFP-10GSR-85' } } }
};

let cages = m['Device.SFPs.SFPCage.{i}'].get({ root: {} });
check('SFPReference of the second cage names SFF8472 row 2', cages['2'].SFPReference, 'Device.SFPs.Mgmt.SFF8472.2.');
check('an empty cage has no SFPReference', cages['1'].SFPReference, '');
check('SFF8472 rows are numbered by cage', keys(m['Device.SFPs.Mgmt.SFF8472.{i}'].get({})), [ '2' ]);
check('SFF8472 row 2 is the second cage', m['Device.SFPs.Mgmt.SFF8472.{i}'].get({ instance: 2 }).Name, 'sfp2');
check('SFF8472 row 1 is absent', m['Device.SFPs.Mgmt.SFF8472.{i}'].get({ instance: 1 }), null);
check('SFF8472 row 0 is absent', m['Device.SFPs.Mgmt.SFF8472.{i}'].get({ instance: 0 }), null);

const optical = m['Device.Optical.Interface.{i}'];
const wan_root = { Device: { IP: { Interface: { '1': { Name: 'wan', Upstream: 'true' } } } } };

let row = optical.get({ root: wan_root })['1'];
check('optical row', [ row.Name, row.Status, row.MaxBitRate, row.LastChange, row.Upstream, row.SFPReferenceList ],
	[ 'eth2', 'Up', '10000', '42', 'true', 'Device.SFPs.SFPCage.2' ]);
check('not upstream without a WAN interface', optical.get({ instance: 1, root: {} }).Upstream, 'false');
check('Enable false reads Down', optical.get({ instance: 1, config: { Enable: 'false' }, root: {} }).Status, 'Down');

let blocked_root = { Device: { SFPs: { AllowedSFPs: { AllowAllSFPs: 'false' } } } };
check('a refused SFP reads NotAllowed', optical.get({ instance: 1, root: blocked_root }).Status, 'NotAllowed');

global.USFPD.optical = {};
check('no answer from usfpd reads Unknown', optical.get({ instance: 1, root: {} }).Status, 'Unknown');
global.USFPD.optical = { sfp2: { Name: 'eth2', Status: 'Up' } };

check('Stats.Reset() of a row without SFP', reset({}, '', [ 7 ]), -USP_ERR_OBJECT_DOES_NOT_EXIST);
reset_ok = false;
check('Stats.Reset() that fails', reset({}, '', [ 1 ]), -USP_ERR_COMMAND_FAILURE);
reset_ok = true;
check('Stats.Reset()', reset({}, '', [ 1 ]), {});

printf('passed: %d\nfailed: %d\n', pass, fail);
exit(fail ? 1 : 0);
