// Calls the bbf-device apply method for tests/lib/device_apply.uc, runs the
// dry-run it starts and prints the reply as JSON: device-apply.uc <config>.
'use strict';

import * as uloop from 'uloop';
import { ubus_methods } from 'ubbf.device.lifecycle';

uloop.init();

ubus_methods().apply.call({
	args: { file: ARGV[0] },
	defer: () => null,
	reply: (data) => {
		printf('%J\n', data);
		uloop.end();
	}
});

uloop.run();
