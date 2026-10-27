// Host test of the render of the ieee8021x module: netdev "lo" stands for
// the port of an X_UBBF_Authenticator row, which gets the netifd option
// auth on its device section. On a VLAN-aware bridge it also gets an
// auth_vlan with a VLAN ID that no bridge uses, and a bridge-vlan section
// without ports makes the bridge a member of that VLAN. A row that cannot
// run leaves its port open, with auth 0. Run from
// the repository root with the native module built for the
// host:
//   tests/render/run.sh <host build> tests/ieee8021x-render.uc
'use strict';

import { generate } from 'ubbf.render.renderer';

let pass = 0, fail = 0;

function check(name, got, expected) {
	if (sprintf('%J', got) == sprintf('%J', expected)) { pass++; return; }
	fail++;
	printf('FAIL %s\n  expected %J\n  got      %J\n', name, expected, got);
}

function config(row, bridge) {
	let root = { Device: {
		Ethernet: {
			Interface: { '1': { Enable: 'true', Name: 'lo' } },
			Link: { '1': { Enable: 'true', Name: 'lo', LowerLayers: 'Device.Ethernet.Interface.1' } }
		},
		IEEE8021x: { X_UBBF_Authenticator: { '1': row } }
	} };
	if (bridge)
		root.Device.Bridging = { Bridge: { '1': bridge } };
	return root;
}

// A VLAN-aware bridge whose port on "lo" has the explicit VLAN 4094.
const BRIDGE = {
	Enable: 'true',
	Name: 'br-lan',
	Standard: '802.1Q-2011',
	Port: {
		'1': { Enable: 'true', Name: 'br-lan', ManagementPort: 'true' },
		'2': { Enable: 'true', Name: 'lo', LowerLayers: 'Device.Ethernet.Link.1' }
	},
	VLAN: { '1': { Enable: 'true', VLANID: '4094' } },
	VLANPort: { '1': { Enable: 'true', VLAN: 'Device.Bridging.Bridge.1.VLAN.1',
		Port: 'Device.Bridging.Bridge.1.Port.2', Untagged: 'true' } }
};

/**
 * Returns the options of the network device section of a netdev.
 *
 * @param {string} uci - UCI batch
 * @param {string} name - Netdev name
 * @returns {array} The option lines of the section
 */
function device_section(uci, name) {
	for (let section in split(uci, 'add network device\n')) {
		let lines = filter(split(section, '\n'), (l) => index(l, 'network.@device[-1].') >= 0);
		if (index(lines, `set network.@device[-1].name='${name}'`) >= 0)
			return lines;
	}

	return [];
}

function auth_lines(row, bridge) {
	let logs = [];
	let uci = generate(config(row, bridge), logs, true).uci;
	return {
		auth: filter(device_section(uci, 'lo'), (l) => index(l, '.auth') >= 0),
		bridge_vlan: filter(split(uci, '\n'), (l) => index(l, 'network.auth_lo') >= 0),
		warnings: map(filter(logs, (l) => index(l.msg, 'ieee8021x') == 0), (l) => l.msg)
	};
}

const ROW = {
	enable: 'true',
	interface: 'Device.Ethernet.Link.1',
	auth_server_addr: '192.0.2.1',
	auth_server_shared_secret: 'radius'
};

const OPEN = [ "set network.@device[-1].auth='0'" ];

check('an enabled authenticator closes its port', auth_lines(ROW),
	{ auth: [ "set network.@device[-1].auth='1'" ], bridge_vlan: [], warnings: [] });
check('on a VLAN-aware bridge the closed port has a VLAN of its own, which the bridge joins', auth_lines(ROW, BRIDGE), {
	auth: [ "set network.@device[-1].auth='1'", "add_list network.@device[-1].auth_vlan='4093:u'" ],
	bridge_vlan: [
		"set network.auth_lo=bridge-vlan",
		"set network.auth_lo.device='br-lan'",
		"set network.auth_lo.vlan=4093"
	],
	warnings: []
});
check('a disabled authenticator states auth 0', auth_lines({ ...ROW, enable: 'false' }),
	{ auth: OPEN, bridge_vlan: [], warnings: [] });
check('a row that cannot run leaves its port open', auth_lines({ ...ROW, auth_server_shared_secret: '' }),
	{ auth: OPEN, bridge_vlan: [], warnings: [ 'ieee8021x: X_UBBF_Authenticator.1: auth_server_shared_secret is empty' ] });

printf('passed: %d\nfailed: %d\n', pass, fail);
exit(fail ? 1 : 0);
