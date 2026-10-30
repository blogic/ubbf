// The ACS passwords of ManagementServer have no generated constraint, so their
// secured marks are curated in the schema file and reach the schema table.
'use strict';

import { describe, it, assert, setup } from 'utest';
import * as ubbf from 'ubbf';

const ID = 'ManagementServer.ManagementServer';

setup(() => {
	let build_dir = getenv('UBBF_BUILD_DIR');
	if (!build_dir || !length(ubbf.schema_tables_load(build_dir + '/schema-core.so') ?? []))
		die('UBBF_BUILD_DIR not set or without schema-core.so');
});

describe('ManagementServer secured marks', () => {
	it('marks the two passwords', () => {
		for (let name in [ 'Password', 'ConnectionRequestPassword' ])
			assert.match(true, ubbf.schema_param_info(ID, name)?.secured, name);
	});

	it('leaves the other credentials unmarked', () => {
		for (let name in [ 'Username', 'ConnectionRequestUsername', 'URL' ])
			assert.match([ 'DM_STRING', null ], [ ubbf.schema_param_info(ID, name)?.type, ubbf.schema_param_info(ID, name)?.secured ], name);
	});
});
