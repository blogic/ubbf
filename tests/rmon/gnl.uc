// Stand-in for the gnl module in tests/rmon-stats.uc: an ethtool
// stats-get reply in the form gnl decodes it, with the receive buckets of
// mt7530_rmon_ranges[] in drivers/net/dsa/mt7530.c.
'use strict';

export function connect(family) {
	return {
		request: (op, flags, msg) => global.ethtool_replies?.[msg?.header?.["dev-name"]]
	};
};

export function error() {
	return null;
};
