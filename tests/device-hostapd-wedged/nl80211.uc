// Stands in for nl80211 in a load of the modules of ubbf-device. The load
// writes the mark file; a call raises.
'use strict';

import { writefile } from 'fs';

const C = { NL80211_CMD_GET_STATION: 17, NLM_F_DUMP: 0x300 };

writefile(getenv('WEDGED_MARKS') + '/nl80211', 'loaded\n');

export function request() { die('nl80211.request in a load'); };
export function listener() { die('nl80211.listener in a load'); };
export { C as 'const' };
