// Host test of the NDP parameters that TR-181 2.21 has under two names,
// NeighborDiscovery.InterfaceSetting.{i}.<Param> and
// InterfaceSetting.{i}.NDP.<Param>: a write to either name reads back
// under both, and the last write wins. The schema comes from
// schema-core.so of the host build in UBBF_BUILD_DIR.
'use strict';

import { describe, it, assert, beforeEach, setup } from 'utest';
import { netifd_patch } from 'netifd_mock';
import * as ubbf from 'ubbf';
import { model } from 'ubbf.tr181.NeighborDiscovery';

const ROW = 'Device.NeighborDiscovery.InterfaceSetting.1';

let dm;

setup(() => {
	let build_dir = getenv('UBBF_BUILD_DIR');
	if (!build_dir || !length(ubbf.schema_tables_load(build_dir + '/schema-core.so') ?? []))
		die('UBBF_BUILD_DIR not set or without schema-core.so');
	ubbf.schema_version_set(21);

	dm = ubbf.create();
	dm.register(model);
	dm.load('/dev/null');
});

function writes(start, sets) {
	dm.set_config({ Device: { NeighborDiscovery: { InterfaceSetting: { '1': start } } } });
	dm.trans_start();
	for (let s in sets)
		dm.params_set({ [ROW + '.' + s[0]]: s[1] });
	let row = dm.config().Device.NeighborDiscovery.InterfaceSetting['1'];
	dm.trans_abort();
	return [ row.RetransTimer, row.NDP?.RetransTimer ];
}

describe('NeighborDiscovery NDP parameters under two names', () => {
	beforeEach(() => netifd_patch({}));

	it('reads an NDP write under both names', () => {
		assert.match([ '2000', '2000' ], writes({ Enable: 'false', NDP: {} }, [ [ 'NDP.RetransTimer', '2000' ] ]));
	});

	it('lets a later write of the deprecated name win', () => {
		assert.match([ '3000', '3000' ],
			writes({ Enable: 'false', NDP: {} }, [ [ 'NDP.RetransTimer', '2000' ], [ 'RetransTimer', '3000' ] ]));
	});

	it('lets a later write of the NDP name win', () => {
		assert.match([ '2000', '2000' ],
			writes({ Enable: 'false', NDP: {} }, [ [ 'RetransTimer', '3000' ], [ 'NDP.RetransTimer', '2000' ] ]));
	});

	it('keeps a deprecated write in the row before the NDP object exists', () => {
		assert.match([ '3000', null ], writes({ Enable: 'false' }, [ [ 'RetransTimer', '3000' ] ]));
	});

	it('gives the same value in both reads', () => {
		let row = { Enable: 'false', RetransTimer: '2000', NDP: { RetransTimer: '2000' } };
		let ndp = model['Device.NeighborDiscovery.InterfaceSetting.{i}.NDP'].get({ config: row.NDP, parent: row });
		let legacy = model['Device.NeighborDiscovery.InterfaceSetting.{i}'].get({ config: row });
		assert.match([ '2000', '2000' ], [ legacy.RetransTimer, ndp.RetransTimer ]);
	});
});
