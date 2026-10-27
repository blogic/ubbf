// Host test of the curl command of curl_upload() in curl.c of ubbf.so: the
// headers of the caller and of the device. tests/curl/bin holds a curl
// stand-in that logs its arguments:
//   PATH="$PWD/tests/curl/bin:$PATH" CURL_LOG=/tmp/curl-args.log \
//     ucode -L "<host build>/*.so" tests/curl.uc
'use strict';

import { readfile } from 'fs';
import { curl_upload } from 'ubbf';

let pass = 0, fail = 0;

function check(name, got, expected) {
	if (sprintf('%J', got) == sprintf('%J', expected)) { pass++; return; }
	fail++;
	printf('FAIL %s\n  expected %J\n  got      %J\n', name, expected, got);
}

function headers_sent() {
	let args = split(trim(readfile(getenv('CURL_LOG')) ?? ''), '\n');
	let out = [];
	for (let i = 0; i < length(args) - 1; i++)
		if (args[i] == '-H')
			push(out, args[i + 1]);
	return sort(out);
}

let opts = { headers: { 'X-Caller': 'one' }, command_key: 'k1' };
let r = curl_upload('http://192.0.2.1/up/file.bin', '/tmp/file.bin', opts);

check('upload ran', r.success, true);
check('caller and device headers', headers_sent(), [ 'X-Caller: one', 'X-ubbf-key: k1' ]);
check('caller options unchanged', opts, { headers: { 'X-Caller': 'one' }, command_key: 'k1' });

curl_upload('http://192.0.2.1/up/file.bin', '/tmp/file.bin', null);
check('no options', headers_sent(), []);

printf('passed: %d failed: %d\n', pass, fail);
exit(fail ? 1 : 0);
