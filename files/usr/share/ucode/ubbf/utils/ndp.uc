'use strict';

// The parameters of NeighborDiscovery.InterfaceSetting.{i} that TR-181 2.21
// deprecates for the same ones in InterfaceSetting.{i}.NDP; both name one
// setting, so a write to either name stores the value under both.
export const NDP_SHARED = [
	'DADTransmits', 'RetransTimer', 'RtrSolicitationInterval',
	'MaxRtrSolicitations', 'NUDEnable', 'RSEnable'
];
