// Sets the TR-181 version 2.21 for tests/sysfs/hardware-plugin.uc. The
// plugin reads the version when it loads, so the test imports this module
// first and the file exists before the plugin evaluates.
'use strict';

import { writefile } from 'fs';

writefile('/etc/ubbf/tr181-version', '2.21.0\n');

export const DM_VERSION = '2.21.0';
