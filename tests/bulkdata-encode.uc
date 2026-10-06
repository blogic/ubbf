// Host test of the BulkData JSON values (TR-369 A.7.2.5) in
// modules/bulkdata: integer types are JSON numbers, also an unsignedLong
// above 2^63, and text that is no number of its type stays a string. Run
// from the repository root with the native module built for the host:
//   ucode -L "$PWD/modules/bulkdata/files/usr/share/ucode" \
//     -L "$PWD/files/usr/share/ucode" -L "<host build>/*.so" tests/bulkdata-encode.uc
'use strict';

import { json_value } from 'ubbf.utils.bulkdata-encode';

let pass = 0, fail = 0;

function check(name, got, expected) {
	if (got === expected && type(got) == type(expected)) { pass++; return; }
	fail++;
	printf('FAIL %s\n  expected %J (%s)\n  got      %J (%s)\n', name, expected, type(expected), got, type(got));
}

function encoded(t, v) {
	return sprintf('%J', json_value({ type: t, value: v }));
}

check('unsignedLong maximum is a number', encoded('DM_ULONG', '18446744073709551615'), '18446744073709551615');
check('unsignedLong past uint64 stays text', encoded('DM_ULONG', '18446744073709551616'), '"18446744073709551616"');
check('long minimum is a number', encoded('DM_LONG', '-9223372036854775808'), '-9223372036854775808');
check('unsignedInt is a number', encoded('DM_UINT', '42'), '42');
check('int is a number', encoded('DM_INT', '-1'), '-1');
check('leading zero still a number', encoded('DM_UINT', '0042'), '42');
check('empty integer stays text', encoded('DM_UINT', ''), '""');
check('boolean', encoded('DM_BOOL', 'true'), 'true');
check('string stays text', encoded('DM_STRING', '5'), '"5"');

printf('passed: %d\nfailed: %d\n', pass, fail);
exit(fail ? 1 : 0);
