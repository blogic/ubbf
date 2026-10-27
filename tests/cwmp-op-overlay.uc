// Host test of the result overlay of utils/cwmp-op-trigger.uc: the file
// name of an operation object and the round trip through the file.
// tests/ip/ holds the ubus stand-in. The test writes /tmp/ubbf, so it runs
// on a private tmpfs:
//   unshare -rm sh -c 'mount -t tmpfs none /tmp && ucode -L "$PWD/tests/ip/*.uc" \
//     -L "$PWD/tests/hosts/*.uc" -L "$PWD/files/usr/share/ucode" \
//     -L "<host build>/*.so" tests/cwmp-op-overlay.uc'
'use strict';

import * as fs from 'fs';
import { OP_DIR, overlay_path, overlay_read, overlay_write } from 'ubbf.utils.cwmp-op-trigger';

let pass = 0, fail = 0;

function check(name, got, expected) {
	if (sprintf('%J', got) == sprintf('%J', expected)) { pass++; return; }
	fail++;
	printf('FAIL %s\n  expected %J\n  got      %J\n', name, expected, got);
}

check('path', overlay_path('Device.IP.Diagnostics.IPPing.'),
	'/tmp/ubbf/op/Device_IP_Diagnostics_IPPing_.json');

fs.mkdir('/tmp/ubbf');
fs.mkdir(OP_DIR);

let path = 'Device.IP.Diagnostics.TraceRoute.';
check('absent', overlay_read(path), {});
check('write', overlay_write(path, { DiagnosticsState: 'Complete', ResponseTime: 12 }), true);
check('read', overlay_read(path), { DiagnosticsState: 'Complete', ResponseTime: 12 });
check('no temp file', fs.lsdir(OP_DIR), [ 'Device_IP_Diagnostics_TraceRoute_.json' ]);

fs.writefile(overlay_path(path), '{ "Diagnostics');
check('invalid', overlay_read(path), {});

printf('passed: %d failed: %d\n', pass, fail);
exit(fail ? 1 : 0);
