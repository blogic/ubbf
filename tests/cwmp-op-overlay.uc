// Host test of the result overlay of utils/cwmp-op-trigger.uc: the file
// name of an operation object and the round trip through the file below
// /tmp/ubbf.
'use strict';

import { describe, it, assert, beforeEach } from 'utest';
import { state_clear } from 'test_env';
import { netifd_patch } from 'netifd_mock';
import * as fs from 'fs';
import { OP_DIR, overlay_path, overlay_read, overlay_write } from 'ubbf.utils.cwmp-op-trigger';

describe('cwmp-op-trigger result overlay', () => {
	beforeEach(() => {
		state_clear();
		netifd_patch({});
	});

	it('names the file after the operation object', () => {
		assert.match('/tmp/ubbf/op/Device_IP_Diagnostics_IPPing_.json', overlay_path('Device.IP.Diagnostics.IPPing.'));
	});

	it('writes and reads back the result, and reads an absent or invalid file as empty', () => {
		fs.mkdir(OP_DIR);

		let path = 'Device.IP.Diagnostics.TraceRoute.';
		assert.match({}, overlay_read(path), 'absent');
		assert.match(true, overlay_write(path, { DiagnosticsState: 'Complete', ResponseTime: 12 }), 'write');
		assert.match({ DiagnosticsState: 'Complete', ResponseTime: 12 }, overlay_read(path), 'read');
		assert.match([ 'Device_IP_Diagnostics_TraceRoute_.json' ], fs.lsdir(OP_DIR), 'no temp file');

		fs.writefile(overlay_path(path), '{ "Diagnostics');
		assert.match({}, overlay_read(path), 'invalid');
	});
});
