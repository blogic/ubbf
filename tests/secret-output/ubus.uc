// Stand-in for ubus in a bbf-cli process of tests/secret-output.uc: each call
// answers with the reply in the file that APPLY_REPLY names.
'use strict';

import { readfile } from 'fs';

export function call(object, method, args) {
	return json(readfile(getenv('APPLY_REPLY')));
};
