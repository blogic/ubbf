// Host test of the BulkData JSON values (TR-369 A.7.2.5) in
// modules/bulkdata: integer types are JSON numbers, also an unsignedLong
// above 2^63, and text that is no number of its type stays a string.
'use strict';

import { describe, it, assert } from 'utest';
import { json_value } from '../modules/bulkdata/files/usr/share/ucode/ubbf/utils/bulkdata-encode.uc';

function encoded(t, v) {
	return sprintf('%J', json_value({ type: t, value: v }));
}

describe('BulkData JSON values', () => {
	it('encodes the integer types as numbers', () => {
		assert.match('18446744073709551615', encoded('DM_ULONG', '18446744073709551615'));
		assert.match('-9223372036854775808', encoded('DM_LONG', '-9223372036854775808'));
		assert.match('42', encoded('DM_UINT', '42'));
		assert.match('-1', encoded('DM_INT', '-1'));
		assert.match('42', encoded('DM_UINT', '0042'));
	});

	it('keeps text that is no number of its type as a string', () => {
		assert.match('"18446744073709551616"', encoded('DM_ULONG', '18446744073709551616'));
		assert.match('""', encoded('DM_UINT', ''));
		assert.match('"5"', encoded('DM_STRING', '5'));
	});

	it('encodes a boolean as a JSON boolean', () => {
		assert.match('true', encoded('DM_BOOL', 'true'));
	});
});
