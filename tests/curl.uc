// Host test of the curl command of curl_upload() in curl.c of ubbf.so: the
// headers of the caller and of the device. The curl stand-in of tests/bin
// logs its arguments to CURL_LOG.
'use strict';

import { describe, it, assert } from 'utest';
import { readfile } from 'fs';
import { curl_upload } from 'ubbf';

function headers_sent() {
	let args = split(trim(readfile(getenv('CURL_LOG')) ?? ''), '\n');
	let out = [];
	for (let i = 0; i < length(args) - 1; i++)
		if (args[i] == '-H')
			push(out, args[i + 1]);
	return sort(out);
}

describe('curl_upload headers', () => {
	it('sends the caller and the device headers and keeps the options', () => {
		let opts = { headers: { 'X-Caller': 'one' }, command_key: 'k1' };
		let r = curl_upload('http://192.0.2.1/up/file.bin', '/tmp/file.bin', opts);

		assert.match(true, r.success);
		assert.match([ 'X-Caller: one', 'X-ubbf-key: k1' ], headers_sent());
		assert.match({ headers: { 'X-Caller': 'one' }, command_key: 'k1' }, opts);
	});

	it('sends no header without options', () => {
		curl_upload('http://192.0.2.1/up/file.bin', '/tmp/file.bin', null);
		assert.match([], headers_sent());
	});
});
