// Host test of the NDP parameters that TR-181 2.21 has under two names,
// NeighborDiscovery.InterfaceSetting.{i}.<Param> and
// InterfaceSetting.{i}.NDP.<Param>: a write to either name reads back
// under both, and the last write wins. Run from the repository root with a
// host build of src/ucode-mod-ubbf in $B; tests/ip/ and tests/hosts/ hold
// stand-ins for ubus and udebug:
//   UBBF_BUILD_DIR=$B ucode -L "$PWD/tests/ip/*.uc" -L "$PWD/tests/hosts/*.uc" \
//     -L "$PWD/files/usr/share/ucode" -L "$B/*.so" tests/ndp.uc
'use strict';

import * as ubbf from 'ubbf';
import { model } from 'ubbf.tr181.NeighborDiscovery';

let pass = 0, fail = 0;

function check(name, got, expected) {
	if (sprintf('%J', got) == sprintf('%J', expected)) { pass++; return; }
	fail++;
	printf('FAIL %s\n  expected %J\n  got      %J\n', name, expected, got);
}

let build_dir = getenv('UBBF_BUILD_DIR');
if (!build_dir || !length(ubbf.schema_tables_load(build_dir + '/schema-core.so') ?? [])) {
	printf('UBBF_BUILD_DIR not set or without schema-core.so\n');
	exit(1);
}
ubbf.schema_version_set(21);

const ROW = 'Device.NeighborDiscovery.InterfaceSetting.1';

let dm = ubbf.create();
dm.register(model);
dm.load('/dev/null');

function writes(start, sets) {
	dm.set_config({ Device: { NeighborDiscovery: { InterfaceSetting: { '1': start } } } });
	dm.trans_start();
	for (let s in sets)
		dm.params_set({ [ROW + '.' + s[0]]: s[1] });
	let row = dm.config().Device.NeighborDiscovery.InterfaceSetting['1'];
	dm.trans_abort();
	return [ row.RetransTimer, row.NDP?.RetransTimer ];
}

check('NDP write reads under both names',
	writes({ Enable: 'false', NDP: {} }, [ [ 'NDP.RetransTimer', '2000' ] ]), [ '2000', '2000' ]);
check('a later write of the deprecated name wins',
	writes({ Enable: 'false', NDP: {} }, [ [ 'NDP.RetransTimer', '2000' ], [ 'RetransTimer', '3000' ] ]), [ '3000', '3000' ]);
check('a later write of the NDP name wins',
	writes({ Enable: 'false', NDP: {} }, [ [ 'RetransTimer', '3000' ], [ 'NDP.RetransTimer', '2000' ] ]), [ '2000', '2000' ]);
check('a deprecated write before the NDP object exists stays in the row',
	writes({ Enable: 'false' }, [ [ 'RetransTimer', '3000' ] ]), [ '3000', null ]);

let row = { Enable: 'false', RetransTimer: '2000', NDP: { RetransTimer: '2000' } };
let ndp = model['Device.NeighborDiscovery.InterfaceSetting.{i}.NDP'].get({ config: row.NDP, parent: row });
let legacy = model['Device.NeighborDiscovery.InterfaceSetting.{i}'].get({ config: row });
check('both reads agree', [ legacy.RetransTimer, ndp.RetransTimer ], [ '2000', '2000' ]);

printf('passed: %d\nfailed: %d\n', pass, fail);
exit(fail ? 1 : 0);
