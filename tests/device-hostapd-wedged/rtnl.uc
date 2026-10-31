// Stands in for rtnl, which the host lacks, in a load of the modules of
// ubbf-device. A load reads only the constants; a call raises.
'use strict';

const consts = {
	RTM_NEWLINK: 16,
	RTM_DELLINK: 17,
	RTM_GETLINK: 18,
	NLM_F_DUMP: 0x300
};

export { consts as 'const' };

export function request() { die('rtnl.request in a load'); };
export function listener() { die('rtnl.listener in a load'); };
