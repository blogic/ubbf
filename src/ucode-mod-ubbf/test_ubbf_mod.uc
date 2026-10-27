// Host test of the native modules ubbf.so, usb, led, wol, wde, multicast and
// users. Run from the repository root:
//   UBBF_HOST_BUILD=/var/tmp/ubbf-si-host/lib LD_LIBRARY_PATH=/var/tmp/ubbf-si-host/libdir utest -c src/ucode-mod-ubbf/utest.config.uc src/ucode-mod-ubbf/test_ubbf_mod.uc
// Set UBBF_BUILD_DIR to the host build as well to run the schema table checks.
'use strict';

import { describe, it, skip, assert } from 'utest';
import * as fs_mod from 'fs';
import * as ubbf from 'ubbf';
import * as usb_lib from 'usb';
import * as led_lib from 'led';
import * as wol_lib from 'wol';
import * as wde_lib from 'wde';
import * as multicast_lib from 'multicast';
import * as users_lib from 'users';

const W = 0x80000000;
const T_STRING = 0x1, T_BOOL = 0x4, T_INT = 0x8, T_UINT = 0x10, T_ULONG = 0x20, T_HEXBIN = 0x80, T_LONG = 0x200;
const ISO8601_UTC = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/;

// netifd leaves out an infinite lifetime and wraps an expired valid one;
// 0xffffffff is infinite (RFC 4861)
const FOREVER = '9999-12-31T23:59:59Z';

const tree = {
	Device: {
		WiFi: {
			Radio: {
				'1': { Enable: 'true', Channel: '6' }
			}
		}
	}
};

const container = { '1': {}, '2': {}, '3': {}, Name: 'test' };

const collect_data = {
	Device: {
		IP: {
			Interface: {
				'1': { Name: 'lan', IPv4Address: { '1': { IPAddress: '192.168.1.1' } } },
				'2': { Name: 'wan' }
			}
		}
	}
};

const dm_config = {
	Device: {
		IP: {
			Interface: {
				'1': { Name: 'lan', Enable: 'true', LowerLayers: 'Device.Ethernet.Link.1' },
				'2': { Name: 'wan', Enable: 'false', LowerLayers: '' }
			}
		},
		Ethernet: {
			Link: { '1': { Name: 'br-lan' } }
		}
	}
};

const l3_config = {
	Device: {
		IP: {
			Interface: {
				'1': { Name: 'lan', Upstream: 'false' },
				'2': { Name: 'wan', Upstream: 'true' }
			}
		}
	}
};

const l3_netifd = [
	{ name: 'lan', addresses: [{ ip: '192.168.1.1', mask: 24 }], ipv6_addresses: [] },
	{ name: 'wan', addresses: [{ ip: '10.0.0.1', mask: 8 }], ipv6_addresses: [] }
];

const rules_build_dir = getenv('UBBF_BUILD_DIR');
const mdns_table_loaded = rules_build_dir && length(ubbf.schema_tables_load(rules_build_dir + '/schema-mdns.so') ?? []) > 0;
const core_table_loaded = rules_build_dir && length(ubbf.schema_tables_load(rules_build_dir + '/schema-core.so') ?? []) > 0;

function config_echo_get(ctx) {
	return { ...ubbf.ctx_config(ctx) };
}

function rows_get(rows, ctx) {
	if (ctx.instance == null)
		return ubbf.enumerate_instances(rows, (r) => r);
	return ubbf.get_by_instance(rows, ctx.instance);
}

function dm_test_create() {
	let dm = ubbf.create();

	dm.register({
		'Device.Test': {
			schema: {
				schema: { Name: 1, Count: 1 },
				defaults: { Name: 'default', Count: '0' }
			},
			get: function(ctx) {
				return { Name: ctx.config?.Name ?? 'unknown', Count: '42' };
			}
		},
		'Device.Test.Item.{i}': {
			schema: {
				schema: { Enable: 1, Value: 1, Alias: 1 },
				defaults: { Enable: 'false', Value: '', Alias: '' }
			},
			get: function(ctx) {
				return { Enable: ctx.config?.Enable ?? 'false', Value: 'computed' };
			},
			set: function(ctx) {
				return;
			}
		}
	});
	dm.load('/dev/null');
	dm.set_config({
		Device: {
			Test: {
				Name: 'mytest',
				ItemNumberOfEntries: '1',
				Item: {
					'1': { Enable: 'true', Value: 'hello', Alias: 'cpe-Item1' }
				}
			}
		}
	});
	dm.runtime_reload();

	return dm;
}

// Row.{i} is registered before its parent on purpose: the walk follows
// registration order, so the parent's merge of the schema default "0" lands
// after the rows were enumerated and would clobber any count set earlier
// than the post-walk apply.
function dm_counts_create() {
	let dm = ubbf.create();
	let t_rows = [{ Name: 'a' }, { Name: 'b' }];
	let sub_rows = [{ Id: '1' }, { Id: '2' }, { Id: '3' }];

	dm.register({
		'Device.T.Row.{i}': {
			schema: { schema: { Name: 1 }, defaults: { Name: '' } },
			get: (ctx) => rows_get(t_rows, ctx)
		},
		'Device.T': {
			schema: {
				schema: { RowNumberOfEntries: 1, Label: 1 },
				defaults: { RowNumberOfEntries: '0', Label: 'x' }
			},
			get: config_echo_get
		},
		'Device.U': {
			schema: {
				schema: { Label: 1 },
				defaults: { RowNumberOfEntries: '0', Label: 'y' }
			},
			get: config_echo_get
		},
		'Device.U.Row.{i}': {
			schema: { schema: { Name: 1 }, defaults: { Name: '' } },
			get: (ctx) => rows_get(t_rows, ctx)
		},
		'Device.V.Item.{i}': {
			schema: {
				schema: { Enable: 1, SubNumberOfEntries: 1 },
				defaults: { Enable: 'false', SubNumberOfEntries: '0' }
			},
			get: config_echo_get
		},
		'Device.P.Item.{i}': {
			schema: { schema: { Tag: 1 }, defaults: { Tag: '' } },
			get: config_echo_get
		},
		'Device.P.Item.{i}.Sub.{i}': {
			schema: { schema: { Of: 1 }, defaults: { Of: '' } },
			get: (ctx) => rows_get([{ Of: ctx.parent?.Tag ?? 'no parent' }], ctx)
		},
		'Device.V.Item.{i}.Sub.{i}': {
			schema: { schema: { Id: 1 }, defaults: { Id: '' } },
			get: (ctx) => rows_get(sub_rows, ctx)
		},
		// W synthesises its own table, as WiFi.Radio does for
		// X_UBBF_ChannelHistory; the table's handler enumerates nothing.
		'Device.W': {
			schema: {
				schema: { HistNumberOfEntries: 1 },
				defaults: { HistNumberOfEntries: '0' }
			},
			get: function(ctx) {
				return {
					HistNumberOfEntries: '2',
					Hist: { '1': { To: '11' }, '2': { To: '1' } }
				};
			}
		},
		'Device.W.Hist.{i}': {
			schema: { schema: { To: 1 }, defaults: { To: '' } },
			get: function(ctx) {
				return ctx.instance == null ? {} : null;
			}
		}
	});
	dm.load('/dev/null');
	dm.set_config({ Device: {
		V: { Item: { '1': { Enable: 'true' } } },
		P: { Item: { '1': { Tag: 'one' }, '2': { Tag: 'two' } } }
	} });
	dm.runtime_reload();

	return dm;
}

function dm_firewall_create(chains) {
	let dm = ubbf.create();

	dm.register({
		'Device.Firewall': {},
		'Device.Firewall.Chain.{i}': {
			schema: {
				schema: { Enable: 1, Alias: 1, Name: 1 },
				defaults: { Enable: 'false', Alias: '', Name: '' }
			}
		},
		'Device.Firewall.Chain.{i}.Rule.{i}': {
			schema: {
				schema: { Enable: 1, Alias: 1, Target: 1 },
				defaults: { Enable: 'false', Alias: '', Target: 'Drop' }
			}
		}
	});
	dm.load('/dev/null');
	dm.set_config({ Device: { Firewall: { Chain: chains } } });
	dm.runtime_reload();

	return dm;
}

function dm_rules_create() {
	let dm = ubbf.create();

	dm.register({
		'Device.V': {
			schema: {
				schema: {
					Flag: T_BOOL | W, Port: T_UINT | W, Level: T_INT | W,
					Mode: T_STRING | W, Name: T_STRING | W, Code: T_STRING | W,
					Modes: T_STRING | W, Free: T_UINT | W, Status: T_STRING,
					Bin: T_HEXBIN | W, Big: T_ULONG | W, Wide: T_LONG | W, Free32: T_INT | W,
					Oui: T_HEXBIN | W, Short: T_HEXBIN | W
				},
				defaults: {},
				constraints: {
					Port: { min: 1, max: 65535 },
					Level: { ranges: [ [ null, -10 ], [ 0, 5 ] ] },
					Mode: { enum: [ 'Auto', 'Manual' ] },
					Name: { min_length: 2, max_length: 4 },
					Code: { lengths: [ [ 3, 3 ], [ 5, 5 ] ] },
					Modes: { list: true, enum: [ 'A', 'B' ], list_max_length: 7 },
					Oui: { lengths: [ [ 0, 0 ], [ 3, 3 ] ] },
					Short: { max_length: 2 }
				}
			}
		},
		'Device.V.Fixed.{i}': {
			schema: { schema: { X: T_STRING }, defaults: {}, addable: false }
		},
		'Device.V.Two.{i}': {
			schema: { schema: { X: T_STRING }, defaults: {}, max_instances: 2 }
		},
		'Device.V.Own.{i}': {
			addable: true,
			maxInstances: 1,
			schema: { schema: { X: T_STRING }, defaults: {}, addable: false, max_instances: 5 }
		}
	});
	dm.load('/dev/null');
	dm.set_config({ Device: { V: {} } });

	return dm;
}

const RULE_CASES = [
	[ 'Flag', 'true', 0 ], [ 'Flag', '1', 0 ], [ 'Flag', 'yes', -4 ],
	[ 'Port', '80', 0 ], [ 'Port', '0', -4 ], [ 'Port', '65536', -4 ],
	[ 'Port', '12abc', -4 ], [ 'Port', '', -4 ], [ 'Port', 443, 0 ],
	[ 'Free', '4294967295', 0 ], [ 'Free', '4294967296', -4 ], [ 'Free', '-1', -4 ], [ 'Free', 'x', -4 ],
	[ 'Free32', '-2147483648', 0 ], [ 'Free32', '2147483648', -4 ],
	[ 'Big', '18446744073709551615', 0 ], [ 'Big', '18446744073709551616', -4 ], [ 'Big', '-1', -4 ],
	[ 'Wide', '-9223372036854775808', 0 ], [ 'Wide', '9223372036854775808', -4 ],
	[ 'Level', '-20', 0 ], [ 'Level', '3', 0 ], [ 'Level', '-5', -4 ], [ 'Level', '6', -4 ],
	[ 'Mode', 'Auto', 0 ], [ 'Mode', 'auto', -4 ],
	[ 'Name', 'abc', 0 ], [ 'Name', 'a', -4 ], [ 'Name', 'abcde', -4 ],
	[ 'Code', 'abc', 0 ], [ 'Code', 'abcde', 0 ], [ 'Code', 'abcd', -4 ],
	[ 'Modes', '', 0 ], [ 'Modes', 'A, B', 0 ], [ 'Modes', 'A,C', -4 ],
	[ 'Modes', 'A,B,A,B', 0 ], [ 'Modes', 'A,B,A,B,A', -4 ],
	[ 'Bin', '', 0 ], [ 'Bin', '00aF', 0 ], [ 'Bin', 'abc', -4 ], [ 'Bin', 'TEST', -4 ],
	[ 'Bin', '0a:0b', -4 ], [ 'Bin', 'ab\ncd', -4 ],
	[ 'Oui', '', 0 ], [ 'Oui', '009065', 0 ], [ 'Oui', '0090', -4 ], [ 'Oui', '00906500', -4 ],
	[ 'Short', 'abcd', 0 ], [ 'Short', 'abcdef', -4 ],
];

const LIVE_ROWS = [ 1, 2 ];

function live_row_get(ctx) {
	if (ctx.config)
		return { ...ctx.config, Live: 'stored' };

	if (ctx.instance)
		return (index(LIVE_ROWS, ctx.instance) >= 0) ? { Live: 'yes' } : null;

	let rows = {};
	for (let n in LIVE_ROWS)
		if (!ctx.root?.Device?.L?.Row?.[n])
			rows[n] = { Live: 'yes' };
	return rows;
}

const live_schema = { schema: { Live: T_STRING, Enable: T_BOOL | W }, defaults: {}, addable: false };

const seen_schema = { schema: { Seen: T_STRING }, defaults: {} };

function seen_get(ctx) {
	if (ctx.instance == null)
		return { '7': { Seen: 'enumerated below ' + join('.', ctx.instances) } };
	return { ...(ctx.config ?? {}), Seen: join('.', ctx.instances) };
}

describe('path helpers', () => {
	it('path_to_parts splits a path', () => {
		assert.match(['Device', 'WiFi', 'Radio'], ubbf.path_to_parts('Device.WiFi.Radio'), 'path_to_parts: simple');
		assert.match(['Device', 'IP', 'Interface', '1'], ubbf.path_to_parts('Device.IP.Interface.1'), 'path_to_parts: with instance');
		assert.match(['Device', 'WiFi'], ubbf.path_to_parts('Device.WiFi.'), 'path_to_parts: trailing dot');
		assert.match(['Device', 'WiFi'], ubbf.path_to_parts('.Device.WiFi'), 'path_to_parts: leading dot');
		assert.match([], ubbf.path_to_parts(''), 'path_to_parts: empty string');
		assert.match(['Device'], ubbf.path_to_parts('Device'), 'path_to_parts: single part');
		assert.match([], ubbf.path_to_parts(null), 'path_to_parts: null input');
	});

	it('navigate_data follows a path', () => {
		assert.match('true', ubbf.navigate_data(tree, ['Device', 'WiFi', 'Radio', '1', 'Enable']), 'navigate_data: deep path');
		assert.match({ Enable: 'true', Channel: '6' }, ubbf.navigate_data(tree, ['Device', 'WiFi', 'Radio', '1']),
			'navigate_data: intermediate object');
		assert.match(null, ubbf.navigate_data(tree, ['Device', 'Ethernet']), 'navigate_data: missing key');
		assert.match(null, ubbf.navigate_data(null, ['Device']), 'navigate_data: null data');
		assert.match('lan', ubbf.navigate_data(dm_config, ['Device', 'IP', 'Interface', '1', 'Name']),
			'navigate_data alias: works');
	});

	it('pattern_matches_path matches a path against a pattern', () => {
		assert.match(true, ubbf.pattern_matches_path('Device.WiFi.Radio.{i}', 'Device.WiFi'), 'pattern_matches_path: prefix match');
		assert.match(true, ubbf.pattern_matches_path('Device.WiFi', ''), 'pattern_matches_path: empty path');
		assert.match(true, ubbf.pattern_matches_path('Device.WiFi', 'Device'), 'pattern_matches_path: Device only');
		assert.match(false, ubbf.pattern_matches_path('Device.WiFi', 'Device.WiFi.Radio'),
			'pattern_matches_path: longer path than pattern');
		assert.match(false, ubbf.pattern_matches_path('Device.WiFi', 'Device.Ethernet'), 'pattern_matches_path: mismatch');
		assert.match(true, ubbf.pattern_matches_path('Device.IP.Interface.{i}', 'Device.IP.Interface'),
			'pattern_matches_path: instance skipped');
	});

	it('tr181_ref_parse gives the instance of a reference', () => {
		assert.match(3, ubbf.tr181_ref_parse('Device.IP.Interface.3', 'Device.IP.Interface'), 'tr181_ref_parse: basic');
		assert.match(3, ubbf.tr181_ref_parse('Device.IP.Interface.3.', 'Device.IP.Interface'), 'tr181_ref_parse: trailing dot');
		assert.match(null, ubbf.tr181_ref_parse('Device.IP.Interface', 'Device.IP.Interface'), 'tr181_ref_parse: missing index');
		assert.match(null, ubbf.tr181_ref_parse('Device.WiFi.Radio.1', 'Device.IP.Interface'), 'tr181_ref_parse: prefix mismatch');
		assert.match(null, ubbf.tr181_ref_parse('Device.IP.Interface.0', 'Device.IP.Interface'), 'tr181_ref_parse: zero instance');
		assert.match(null, ubbf.tr181_ref_parse('Device.IP.Interface.abc', 'Device.IP.Interface'), 'tr181_ref_parse: non-numeric');
		assert.match(null, ubbf.tr181_ref_parse(null, 'Device.IP.Interface'), 'tr181_ref_parse: non-string');
	});
});

describe('value conversion', () => {
	it('to_bool', () => {
		assert.match(true, ubbf.to_bool('true'), 'to_bool: string true');
		assert.match(true, ubbf.to_bool('1'), 'to_bool: string 1');
		assert.match(false, ubbf.to_bool('false'), 'to_bool: string false');
		assert.match(false, ubbf.to_bool('0'), 'to_bool: string 0');
		assert.match(true, ubbf.to_bool(true), 'to_bool: bool true');
		assert.match(false, ubbf.to_bool(false), 'to_bool: bool false');
		assert.match(false, ubbf.to_bool(null), 'to_bool: null');
	});

	it('to_int', () => {
		assert.match(42, ubbf.to_int(42), 'to_int: integer passthrough');
		assert.match(123, ubbf.to_int('123'), 'to_int: string number');
		assert.match(-5, ubbf.to_int('-5'), 'to_int: string negative');
		assert.match(null, ubbf.to_int('abc'), 'to_int: non-numeric string');
		assert.match(null, ubbf.to_int(null), 'to_int: null');
		assert.match(null, ubbf.to_int(''), 'to_int: empty string');
	});

	it('csv_to_list', () => {
		assert.match(['a', 'b', 'c'], ubbf.csv_to_list('a,b,c'), 'csv_to_list: basic');
		assert.match(['a', 'b', 'c'], ubbf.csv_to_list(' a , b , c '), 'csv_to_list: with spaces');
		assert.match(['1', '3'], ubbf.csv_to_list('1,-1,3', '-1'), 'csv_to_list: with filter');
		assert.match([], ubbf.csv_to_list(''), 'csv_to_list: empty string');
		assert.match([], ubbf.csv_to_list(null), 'csv_to_list: null');
	});

	it('ip_to_int and int_to_ip', () => {
		assert.match((192 << 24) | (168 << 16) | (1 << 8) | 1, ubbf.ip_to_int('192.168.1.1'), 'ip_to_int: basic');
		assert.match('10.0.0.1', ubbf.int_to_ip((10 << 24) | (0 << 16) | (0 << 8) | 1), 'int_to_ip: basic');
		assert.match('172.16.100.2', ubbf.int_to_ip(ubbf.ip_to_int('172.16.100.2')), 'ip roundtrip');
	});

	it('cidr_to_netmask and netmask_to_cidr', () => {
		assert.match('255.255.255.0', ubbf.cidr_to_netmask(24), 'cidr_to_netmask: /24');
		assert.match('255.255.255.255', ubbf.cidr_to_netmask(32), 'cidr_to_netmask: /32');
		assert.match('0.0.0.0', ubbf.cidr_to_netmask(0), 'cidr_to_netmask: /0');
		assert.match(24, ubbf.netmask_to_cidr('255.255.255.0'), 'netmask_to_cidr: /24');
		assert.match(16, ubbf.netmask_to_cidr('255.255.0.0'), 'netmask_to_cidr: /16');
		assert.match(20, ubbf.netmask_to_cidr(ubbf.cidr_to_netmask(20)), 'cidr roundtrip');
	});

	it('shell_escape', () => {
		assert.match("'hello'", ubbf.shell_escape('hello'), 'shell_escape: simple');
		assert.match("'it'\\''s'", ubbf.shell_escape("it's"), 'shell_escape: with quote');
		assert.match("''", ubbf.shell_escape(null), 'shell_escape: null');
	});
});

describe('instance helpers', () => {
	it('is_instance_key', () => {
		assert.match(true, ubbf.is_instance_key('1'), 'is_instance_key: valid string');
		assert.match(true, ubbf.is_instance_key('42'), 'is_instance_key: larger number');
		assert.match(false, ubbf.is_instance_key('0'), 'is_instance_key: zero');
		assert.match(false, ubbf.is_instance_key('-1'), 'is_instance_key: negative');
		assert.match(false, ubbf.is_instance_key('abc'), 'is_instance_key: non-numeric');
		assert.match(false, ubbf.is_instance_key(' 1'), 'is_instance_key: leading space');
		assert.match(false, ubbf.is_instance_key('+1'), 'is_instance_key: plus sign');
		assert.match(false, ubbf.is_instance_key('2147483648'), 'is_instance_key: beyond int');
		assert.match(true, ubbf.is_instance_key('2147483647'), 'is_instance_key: int maximum');
		assert.match(true, ubbf.is_instance_key(5), 'is_instance_key: integer 5');
		assert.match(false, ubbf.is_instance_key(0), 'is_instance_key: integer 0');
	});

	it('instance_count', () => {
		assert.match(3, ubbf.instance_count(container), 'instance_count: mixed keys');
		assert.match(0, ubbf.instance_count({}), 'instance_count: empty object');
		assert.match(0, ubbf.instance_count(null), 'instance_count: null');
		assert.match(2, ubbf.instance_count({ '1': {}, '2': {} }), 'instance_count alias: works');
	});

	it('find_next_instance', () => {
		assert.match(4, ubbf.find_next_instance(container), 'find_next_instance: contiguous');
		assert.match(2, ubbf.find_next_instance({ '1': {}, '3': {} }), 'find_next_instance: with gap');
		assert.match(1, ubbf.find_next_instance({}), 'find_next_instance: empty');
	});

	it('navigate_or_create creates the path', () => {
		let nav_obj = {};

		ubbf.navigate_or_create(nav_obj, ['Device', 'WiFi', 'Radio']);
		assert.match('object', type(nav_obj?.Device?.WiFi?.Radio), 'navigate_or_create: creates path');
	});

	it('collect_instances_for_pattern', () => {
		let collected = ubbf.collect_instances_for_pattern(['Device', 'IP', 'Interface', '{i}'], collect_data, 0, '');
		assert.match(true, index(collected, 'Device.IP.Interface.1') >= 0, 'collect_instances: finds instance 1');
		assert.match(true, index(collected, 'Device.IP.Interface.2') >= 0, 'collect_instances: finds instance 2');

		let collected2 = ubbf.collect_instances_for_pattern(
			['Device', 'IP', 'Interface', '{i}', 'IPv4Address', '{i}'], collect_data, 0, '');
		assert.match(true, index(collected2, 'Device.IP.Interface.1.IPv4Address.1') >= 0, 'collect_instances: nested pattern');
	});

	it('entries_count_update sets the count', () => {
		let parent_obj = {};

		ubbf.entries_count_update(parent_obj, 'Interface', { '1': {}, '2': {}, '3': {} });
		assert.match('3', parent_obj.InterfaceNumberOfEntries, 'entries_count_update: sets count');
	});

	it('enumerate_instances and get_by_instance', () => {
		let enumerated = ubbf.enumerate_instances(['a', 'b', 'c'], (item, i) => ({ val: item }));

		assert.match('object', type(enumerated['1']), 'enumerate_instances: keys are 1-based');
		assert.match('b', enumerated['2']?.val, 'enumerate_instances: converter called');
		assert.match('y', ubbf.get_by_instance(['x', 'y', 'z'], 2), 'get_by_instance: valid');
		assert.match(null, ubbf.get_by_instance(['x'], 5), 'get_by_instance: out of range');
	});
});

describe('config helpers', () => {
	it('get', () => {
		assert.match('lan', ubbf.get(dm_config, 'Device.IP.Interface.1.Name'), 'get: simple path');
		assert.match(null, ubbf.get(dm_config, 'Device.WiFi'), 'get: missing path');
	});

	it('instances', () => {
		let insts = ubbf.instances(dm_config, 'Device.IP.Interface');

		assert.match(2, length(insts), 'instances: count');
		assert.match(true, insts[0]['.instance'] != null, 'instances: has .instance key');
		assert.match(true, insts[0]['.path'] != null, 'instances: has .path key');
	});

	it('enabled', () => {
		assert.match(true, ubbf.enabled(dm_config, 'Device.IP.Interface.1.Enable'), 'enabled: true string');
		assert.match(false, ubbf.enabled(dm_config, 'Device.IP.Interface.2.Enable'), 'enabled: false string');
		assert.match(false, ubbf.enabled(dm_config, 'Device.IP.Interface.99.Enable'), 'enabled: missing path');
	});

	it('interface_to_name and lower_layer_resolve', () => {
		assert.match('lan', ubbf.interface_to_name(dm_config, 'Device.IP.Interface.1'), 'interface_to_name: resolves');
		assert.match(null, ubbf.interface_to_name(dm_config, null), 'interface_to_name: null ref');
		assert.match('br-lan', ubbf.lower_layer_resolve(dm_config, 'Device.Ethernet.Link.1'), 'lower_layer_resolve: resolves first');
		assert.match(null, ubbf.lower_layer_resolve(dm_config, ''), 'lower_layer_resolve: empty');
	});

	it('ctx_config', () => {
		assert.match({ Name: 'test' }, ubbf.ctx_config({ config: { Name: 'test' } }), 'ctx_config: extracts config');
		assert.match({}, ubbf.ctx_config(null), 'ctx_config: null returns empty');
	});

	it('alias_from_mac and alias_from_name', () => {
		assert.match('cpe-047c165db52c', ubbf.alias_from_mac('04:7C:16:5D:B5:2C'), 'alias_from_mac: basic');
		assert.match('', ubbf.alias_from_mac(null), 'alias_from_mac: null');
		assert.match('cpe-eth0_1', ubbf.alias_from_name('eth0.1'), 'alias_from_name: basic');
		assert.match('', ubbf.alias_from_name(null), 'alias_from_name: null');
		assert.match('cpe-blue_wps', ubbf.alias_from_name('blue:wps'), 'alias_from_name: LED name');

		let long_alias = ubbf.alias_from_name(
			'mt7530-0:00:green:wan-with-a-name-that-is-much-longer-than-sixty-four-bytes');
		assert.match(64, length(long_alias), 'alias_from_name: at most 64 bytes');
		assert.match('cpe-mt7530-0_00_g', substr(long_alias, 0, 17), 'alias_from_name: cut keeps the prefix');
	});
});

describe('datamodel', () => {
	it('create returns a resource that takes a model', () => {
		let dm = ubbf.create();

		assert.match('resource', type(dm), 'create: returns resource');
		assert.match(true, dm.register({
			'Device.WiFi': {
				schema: { defaults: { RadioNumberOfEntries: '0' } },
				get: function(ctx) {
					return { RadioNumberOfEntries: '1' };
				}
			},
			'Device.WiFi.Radio.{i}': {
				schema: { defaults: { Enable: 'false', Channel: '0' } },
				get: function(ctx) {
					return { Enable: ctx.config?.Enable ?? 'false', Channel: '6' };
				},
				set: function(ctx) {
					return;
				}
			}
		}), 'dm.register: succeeds');

		dm.trans_start();
		dm.trans_abort();
	});

	it('params_get returns the handler results', () => {
		let dm = dm_test_create();
		let get_paths = {
			'Device.Test.Name': null,
			'Device.Test.Item.1.Value': null,
			'Device.Test.Count': null
		};

		dm.params_get(get_paths);
		assert.match('mytest', get_paths['Device.Test.Name'], 'dm.params_get: handler result');
		assert.match('computed', get_paths['Device.Test.Item.1.Value'], 'dm.params_get: nested handler');
		assert.match('42', get_paths['Device.Test.Count'], 'dm.params_get: handler count');

		let get_paths2 = { 'Device.Test.Item.1.Enable': null };
		dm.params_get(get_paths2);
		assert.match('true', get_paths2['Device.Test.Item.1.Enable'], 'dm.params_get: from handler');
	});

	it('params_set stores the value', () => {
		let dm = dm_test_create();

		dm.trans_start();
		dm.params_set({ 'Device.Test.Item.1.Value': 'updated' });
		assert.match('updated', dm.config()?.Device?.Test?.Item?.['1']?.Value, 'dm.params_set: value stored');
		dm.trans_abort();
	});

	it('object_add and object_del', () => {
		let dm = dm_test_create();

		dm.trans_start();
		let new_inst = dm.object_add('Device.Test.Item');
		assert.match(true, new_inst > 0, 'dm.object_add: returns instance > 0');

		let cfg2 = dm.config();
		let new_obj = cfg2?.Device?.Test?.Item?.[sprintf('%d', new_inst)];
		assert.match('false', new_obj?.Enable, 'dm.object_add: created with defaults');
		assert.match(sprintf('cpe-Item%d', new_inst), new_obj?.Alias, 'dm.object_add: alias generated with the cpe- prefix');
		assert.match('2', cfg2?.Device?.Test?.ItemNumberOfEntries, 'dm.object_add: NumberOfEntries updated');

		dm.object_del(sprintf('Device.Test.Item.%d', new_inst));
		let cfg3 = dm.config();
		assert.match(null, cfg3?.Device?.Test?.Item?.[sprintf('%d', new_inst)], 'dm.object_del: instance removed');
		assert.match('1', cfg3?.Device?.Test?.ItemNumberOfEntries, 'dm.object_del: NumberOfEntries updated');
		dm.trans_abort();
	});

	it('resolves an alias in a path', () => {
		let dm = dm_test_create();

		dm.trans_start();

		let alias_get = { 'Device.Test.Item.cpe-Item1.Value': null };
		dm.params_get(alias_get);
		assert.match('computed', alias_get['Device.Test.Item.cpe-Item1.Value'], 'params_get: resolves alias to instance');

		let bracket_get = { 'Device.Test.Item.[cpe-Item1].Value': null };
		dm.params_get(bracket_get);
		assert.match('computed', bracket_get['Device.Test.Item.[cpe-Item1].Value'], 'params_get: resolves bracketed alias form');

		dm.params_set({ 'Device.Test.Item.cpe-Item1.Value': 'alias-set' });
		assert.match('alias-set', dm.config()?.Device?.Test?.Item?.['1']?.Value, 'params_set: stores via alias path');

		let alias_get_miss = { 'Device.Test.Item.NoSuchAlias.Value': null };
		dm.params_get(alias_get_miss);
		assert.match(null, alias_get_miss['Device.Test.Item.NoSuchAlias.Value'], 'params_get: unknown alias returns null');

		dm.trans_abort();
	});

	it('digest returns the stored hash', () => {
		let dm = dm_test_create();

		dm.set_digest('abc123');
		assert.match('abc123', dm.digest(), 'dm.digest: returns stored hash');
	});
});

describe('runtime table counts', () => {
	it('a table the parent synthesises keeps its rows and count', () => {
		let dm = dm_counts_create();
		let w_tree = dm.get_subtree_with_state('Device.W');

		assert.match('1', w_tree?.Hist?.['2']?.To, 'runtime count: a table the parent synthesises keeps its rows');
		assert.match('2', w_tree?.HistNumberOfEntries, 'runtime count: and its count follows those rows');

		let w_paths = { 'Device.W.HistNumberOfEntries': null };
		dm.params_get(w_paths);
		assert.match('2', w_paths['Device.W.HistNumberOfEntries'], 'runtime count: params_get agrees for the synthesised table');
	});

	it('the parent carries the count of the enumerated rows', () => {
		let dm = dm_counts_create();
		let t_tree = dm.get_subtree_with_state('Device.T');

		assert.match('2', t_tree?.RowNumberOfEntries, 'runtime count: parent carries the enumerated count');
		assert.match('b', t_tree?.Row?.['2']?.Name, 'runtime count: rows are present');
		assert.match('2', dm.get_subtree_with_state('Device')?.T?.RowNumberOfEntries, 'runtime count: visible from the root');
		assert.match(null, dm.get_subtree_with_state('Device.T.Row')?.RowNumberOfEntries,
			'runtime count: no stray key on the table itself');
		assert.match(null, dm.get_subtree_with_state('Device.U')?.RowNumberOfEntries,
			'runtime count: an undeclared key gets no count and no default');
		assert.match('y', dm.get_subtree_with_state('Device.U')?.Label, 'undeclared key: a declared one stays');
		assert.match('3', dm.get_subtree_with_state('Device.V')?.Item?.['1']?.SubNumberOfEntries,
			'runtime count: nested table under a persisted row');

		let count_paths = { 'Device.T.RowNumberOfEntries': null };
		dm.params_get(count_paths);
		assert.match('2', count_paths['Device.T.RowNumberOfEntries'], 'runtime count: params_get sees the count');
	});

	it('a nested table handler gets its row as the parent', () => {
		let dm = dm_counts_create();
		let p_tree = dm.get_subtree_with_state('Device.P');

		assert.match([ 'one', 'two' ], [ p_tree?.Item?.['1']?.Sub?.['1']?.Of, p_tree?.Item?.['2']?.Sub?.['1']?.Of ],
			'nested table: the handler gets its row as the parent');
		assert.match('two', dm.get_subtree_with_state('Device.P.Item.2')?.Sub?.['1']?.Of, 'nested table: also below the row path');
	});

	// Device is registered after the domains below it, and its handler returns
	// the stored config. A walk in registration order let that config replace
	// the runtime state the deeper handlers had merged.
	it('a container handler registered after its descendants keeps their state', () => {
		let dm = ubbf.create();

		dm.register({
			'Device.S.Item.{i}': {
				schema: {
					schema: { Enable: 1, Status: 1 },
					defaults: { Enable: 'false', Status: 'Down' }
				},
				get: function(ctx) {
					return { ...ubbf.ctx_config(ctx), Status: 'Up' };
				}
			},
			'Device': {
				schema: { schema: { Label: 1 }, defaults: { Label: 'd' } },
				get: config_echo_get
			},
			'Device.S': {
				schema: { schema: { Label: 1 }, defaults: { Label: 's' } },
				get: config_echo_get
			}
		});
		dm.load('/dev/null');
		dm.set_config({ Device: { S: { Item: { '1': { Enable: 'true' } } } } });
		dm.runtime_reload();

		assert.match('Up', dm.get_subtree_with_state('Device.S')?.Item?.['1']?.Status, 'handler order: container query keeps the row state');
		assert.match('Up', dm.get_subtree_with_state('Device')?.S?.Item?.['1']?.Status, 'handler order: root query keeps the row state');
		assert.match('true', dm.get_subtree_with_state('Device')?.S?.Item?.['1']?.Enable, 'handler order: root query keeps the stored value');
		assert.match('d', dm.get_subtree_with_state('Device')?.Label, 'handler order: root handler still contributes');
	});
});

describe('nested-table paths with a named parent', () => {
	it('resolves a Name or Alias key of a numbered row', () => {
		let dm = dm_firewall_create({
			'3': { Enable: 'true', Alias: 'MediumAlias', Name: 'Medium' },
			'7': { Enable: 'true', Alias: 'IPV6MediumAlias', Name: 'IPV6_Medium' }
		});

		dm.trans_start();

		let rule_inst = dm.object_add('Device.Firewall.Chain.Medium.Rule');
		assert.match(true, rule_inst > 0, 'object_add: Chain.<Name>.Rule resolves via Name key');

		let added_rule = dm.config()?.Device?.Firewall?.Chain?.['3']?.Rule?.[sprintf('%d', rule_inst)];
		assert.match('Drop', added_rule?.Target, 'object_add: rule landed under numeric instance 3');

		dm.params_set({
			[sprintf('Device.Firewall.Chain.Medium.Rule.%d.Target', rule_inst)]: 'Accept'
		});
		assert.match('Accept', dm.config()?.Device?.Firewall?.Chain?.['3']?.Rule?.[sprintf('%d', rule_inst)]?.Target,
			'params_set: alias in mid-path resolves for rule Target');

		dm.params_set({ 'Device.Firewall.Chain.IPV6MediumAlias.Enable': 'false' });
		assert.match('false', dm.config()?.Device?.Firewall?.Chain?.['7']?.Enable, 'params_set: Alias key resolves alongside Name');

		dm.object_del(sprintf('Device.Firewall.Chain.Medium.Rule.%d', rule_inst));
		assert.match(null, dm.config()?.Device?.Firewall?.Chain?.['3']?.Rule?.[sprintf('%d', rule_inst)],
			'object_del: removes rule via alias parent');

		dm.trans_abort();
	});

	// A boot-time preset stores instances under their name directly, so the
	// path validator must accept a non-numeric {i} segment that exists.
	it('accepts a row stored under its name', () => {
		let dm = dm_firewall_create({
			Medium: { Enable: 'true', Alias: 'MediumChain', Name: 'MEDIUM' },
			IPV6_Medium: { Enable: 'true', Alias: 'IPV6_MediumChain', Name: 'IPV6_MEDIUM' }
		});

		dm.trans_start();

		let nrule = dm.object_add('Device.Firewall.Chain.Medium.Rule');
		assert.match(true, nrule > 0, 'object_add: named-key container accepts add');

		let named_rule = dm.config()?.Device?.Firewall?.Chain?.Medium?.Rule?.[sprintf('%d', nrule)];
		assert.match('Drop', named_rule?.Target, 'object_add: rule lands under named-key container');

		dm.params_set({
			[sprintf('Device.Firewall.Chain.Medium.Rule.%d.Target', nrule)]: 'Accept'
		});
		assert.match('Accept', dm.config()?.Device?.Firewall?.Chain?.Medium?.Rule?.[sprintf('%d', nrule)]?.Target,
			'params_set: named-key mid-path set works');

		dm.object_del(sprintf('Device.Firewall.Chain.Medium.Rule.%d', nrule));
		assert.match(null, dm.config()?.Device?.Firewall?.Chain?.Medium?.Rule?.[sprintf('%d', nrule)],
			'object_del: removes rule under named-key container');

		dm.trans_abort();
	});
});

describe('time formats', () => {
	it('iso8601_format', () => {
		assert.match('1970-01-01T00:00:00Z', ubbf.iso8601_format(0), 'iso8601_format: epoch');
		assert.match('1970-01-01T00:00:00.123456Z', ubbf.iso8601_format_usec(0, 123456), 'iso8601_format_usec: epoch with usec');
	});

	it('iso8601_local_format', () => {
		let lt = localtime(86400);
		let lt_offset = timegm(lt) - 86400;
		let lt_abs = (lt_offset < 0) ? -lt_offset : lt_offset;

		assert.match(sprintf('%04d-%02d-%02dT%02d:%02d:%02d%s%02d:%02d', lt.year, lt.mon, lt.mday, lt.hour, lt.min, lt.sec,
				lt_offset < 0 ? '-' : '+', lt_abs / 3600, (lt_abs % 3600) / 60),
			ubbf.iso8601_local_format(86400), 'iso8601_local_format: local time with its offset');
		assert.match(true,
			match(ubbf.iso8601_local_format(), /^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}[+-][0-9]{2}:[0-9]{2}$/) != null,
			'iso8601_local_format: now has an offset');
	});
});

describe('file and proc readers', () => {
	it('uptime_read, readfile_trim and readfile_int', () => {
		assert.match(true, ubbf.uptime_read() > 0, 'uptime_read: returns positive');
		assert.match(true, length(ubbf.readfile_trim('/proc/sys/kernel/hostname')) > 0, 'readfile_trim: reads proc file');
		assert.match('fallback', ubbf.readfile_trim('/nonexistent', 'fallback'), 'readfile_trim: default on missing');
		assert.match(true, ubbf.readfile_int('/proc/sys/kernel/pid_max', 0) > 0, 'readfile_int: reads integer');
	});

	it('cpu_stats', () => {
		let cpu = ubbf.cpu_stats();

		assert.match('object', type(cpu), 'cpu_stats: returns object');
		assert.match('object', type(cpu?.cpu), 'cpu_stats: cpu key is object');
		assert.match('string', type(cpu?.cpu?.CPUUtilization), 'cpu_stats: cpu has CPUUtilization');
	});

	it('process_count and process_info', () => {
		assert.match(true, ubbf.process_count() > 0, 'process_count: positive integer');

		let pi_init = ubbf.process_info(1);
		assert.match('object', type(pi_init), 'process_info: PID 1 returns object');
		assert.match('1', pi_init?.PID, 'process_info: PID field');
		assert.match(true, length(pi_init?.Command ?? '') > 0, 'process_info: Command non-empty');
		assert.match(true, length(pi_init?.State ?? '') > 0, 'process_info: State is a string');
		assert.match(null, ubbf.process_info('abc'), 'process_info: non-int');
		assert.match(null, ubbf.process_info(99999999), 'process_info: missing pid');
	});

	it('leases_parse', () => {
		assert.match('array', type(ubbf.leases_parse()), 'leases_parse: returns array');
	});

	it('arch_get', () => {
		assert.match('string', type(ubbf.arch_get()), 'arch_get: returns string');
		assert.match(true, length(ubbf.arch_get()) > 0, 'arch_get: non-empty');
	});

	it('apk_version', () => {
		assert.match(null, ubbf.apk_version(null), 'apk_version: non-string');
		assert.match(null, ubbf.apk_version(''), 'apk_version: empty');
		assert.match(null, ubbf.apk_version('no-such-package-name'), 'apk_version: absent package');
	});

	it('statvfs_info', () => {
		let svfs = ubbf.statvfs_info('/');

		assert.match('object', type(svfs), 'statvfs_info: object');
		assert.match(true, svfs?.total_kib > 0, 'statvfs_info: total_kib positive');
		assert.match(true, type(svfs?.avail_kib) == 'int64' || type(svfs?.avail_kib) == 'int', 'statvfs_info: avail_kib is integer');
		assert.match(null, ubbf.statvfs_info('/nonexistent/path/xyz'), 'statvfs_info: missing path');
		assert.match(null, ubbf.statvfs_info(null), 'statvfs_info: non-string');
	});
});

describe('host discovery', () => {
	it('the parsers return their container types', () => {
		assert.match('array', type(ubbf.arp_parse()), 'arp_parse: returns array');
		assert.match('array', type(multicast_lib.mr_cache_parse()), 'mr_cache_parse: returns array');
		assert.match('object', type(ubbf.bridge_fdb_parse()), 'bridge_fdb_parse: returns object');
		assert.match('object', type(ubbf.ipv6_neigh_parse()), 'ipv6_neigh_parse: returns object');
	});

	it('hosts_merge joins ARP, leases, NDP and the FDB', () => {
		let test_arp = [
			{ ip: '192.168.1.10', mac: 'AA:BB:CC:DD:EE:01', device: 'br-lan', active: true },
			{ ip: '192.168.1.11', mac: 'AA:BB:CC:DD:EE:02', device: 'br-lan', active: true }
		];
		let test_leases = {
			'AA:BB:CC:DD:EE:01': { ip: '192.168.1.10', hostname: 'laptop' }
		};
		let test_ipv6 = {
			'AA:BB:CC:DD:EE:01': ['fe80::1']
		};
		let test_fdb = {
			'AA:BB:CC:DD:EE:01': 'eth0',
			'AA:BB:CC:DD:EE:02': 'eth1'
		};

		let merged = ubbf.hosts_merge(test_arp, test_leases, test_ipv6, test_fdb);
		assert.match('array', type(merged), 'hosts_merge: returns array');
		assert.match(2, length(merged), 'hosts_merge: two hosts in fdb');

		let h1 = filter(merged, h => h.mac == 'AA:BB:CC:DD:EE:01')[0];
		assert.match('laptop', h1?.hostname, 'hosts_merge: hostname from lease');
		assert.match('192.168.1.10', h1?.ipv4_addresses?.[0], 'hosts_merge: ipv4 address');
		assert.match('fe80::1', h1?.ipv6_addresses?.[0], 'hosts_merge: ipv6 from ndp');
		assert.match('DHCP', h1?.address_source, 'hosts_merge: address_source DHCP');

		let h2 = filter(merged, h => h.mac == 'AA:BB:CC:DD:EE:02')[0];
		assert.match('Static', h2?.address_source, 'hosts_merge: static host');
	});

	it('hosts_merge lists an IPv6-only host in the FDB', () => {
		let merged6 = ubbf.hosts_merge([], {}, {
			'AA:BB:CC:DD:EE:03': ['2001:db8::3'],
			'AA:BB:CC:DD:EE:04': ['2001:db8::4']
		}, { 'AA:BB:CC:DD:EE:03': 'eth0' });

		assert.match(1, length(merged6), 'hosts_merge: ipv6-only host in fdb listed');
		assert.match('2001:db8::3', merged6[0]?.ipv6_addresses?.[0], 'hosts_merge: ipv6-only host address');
		assert.match(true, merged6[0]?.active, 'hosts_merge: ipv6-only host active');
	});

	it('hosts_merge lists an ARP host on a device that is not a bridge', () => {
		let merged_nb = ubbf.hosts_merge([
			{ ip: '10.9.0.2', mac: 'AA:BB:CC:DD:EE:05', device: 'ubbf-test-nobridge0', active: true }
		], {}, {}, {});

		assert.match(1, length(merged_nb), 'hosts_merge: arp host on a non-bridge device listed');
	});

	it('host_primary_ip', () => {
		assert.match('10.0.0.1', ubbf.host_primary_ip({ ipv4_addresses: ['10.0.0.1'], ipv6_addresses: [] }), 'host_primary_ip: returns ipv4');
		assert.match('fe80::1', ubbf.host_primary_ip({ ipv4_addresses: [], ipv6_addresses: ['fe80::1'] }), 'host_primary_ip: falls back to ipv6');
		assert.match('', ubbf.host_primary_ip({ ipv4_addresses: [], ipv6_addresses: [] }), 'host_primary_ip: empty');
	});

	it('layer3_interface_find', () => {
		let l3 = ubbf.layer3_interface_find(l3_config, '192.168.1.50', l3_netifd);
		assert.match('Device.IP.Interface.1', l3?.path, 'layer3_interface_find: matches lan');
		assert.match(false, l3?.upstream, 'layer3_interface_find: lan not upstream');

		let l3_wan = ubbf.layer3_interface_find(l3_config, '10.1.2.3', l3_netifd);
		assert.match('Device.IP.Interface.2', l3_wan?.path, 'layer3_interface_find: matches wan');
		assert.match(true, l3_wan?.upstream, 'layer3_interface_find: wan is upstream');

		let l3_miss = ubbf.layer3_interface_find(l3_config, '172.16.0.1', l3_netifd);
		assert.match('', l3_miss?.path, 'layer3_interface_find: no match');
	});
});

describe('string helpers', () => {
	it('name_sanitise', () => {
		assert.match('abc_123', ubbf.name_sanitise('abc_123'), 'name_sanitise: passthrough');
		assert.match('wlan0_1____', ubbf.name_sanitise('wlan0.1 :-('), 'name_sanitise: rewrites specials');
		assert.match(null, ubbf.name_sanitise(42), 'name_sanitise: non-string');
	});

	it('uci_value_sanitise', () => {
		assert.match('hello', ubbf.uci_value_sanitise('hello'), 'uci_value_sanitise: passthrough');
		assert.match('abcd', ubbf.uci_value_sanitise('a\nb\tc\x7fd'), 'uci_value_sanitise: strips control bytes');
		assert.match(42, ubbf.uci_value_sanitise(42), 'uci_value_sanitise: non-string passthrough');
	});

	it('transfer_url_validate', () => {
		assert.match(true, ubbf.transfer_url_validate('http://example.com/file'), 'transfer_url_validate: http');
		assert.match(true, ubbf.transfer_url_validate('https://example.com/file'), 'transfer_url_validate: https');
		assert.match(true, ubbf.transfer_url_validate('ftp://example.com'), 'transfer_url_validate: ftp');
		assert.match(true, ubbf.transfer_url_validate('ftps://example.com'), 'transfer_url_validate: ftps');
		assert.match(false, ubbf.transfer_url_validate('example.com'), 'transfer_url_validate: no scheme');
		assert.match(false, ubbf.transfer_url_validate('file:///etc/passwd'), 'transfer_url_validate: file scheme');
		assert.match(false, ubbf.transfer_url_validate(null), 'transfer_url_validate: non-string');
	});
});

describe('MAC helpers', () => {
	it('mac_is_valid', () => {
		assert.match(true, ubbf.mac_is_valid('aa:bb:cc:dd:ee:ff'), 'mac_is_valid: lowercase');
		assert.match(true, ubbf.mac_is_valid('AA:BB:CC:DD:EE:FF'), 'mac_is_valid: uppercase');
		assert.match(false, ubbf.mac_is_valid('aa:bb:cc'), 'mac_is_valid: too short');
		assert.match(false, ubbf.mac_is_valid('aabbccddeeff'), 'mac_is_valid: missing colons');
		assert.match(false, ubbf.mac_is_valid('gg:bb:cc:dd:ee:ff'), 'mac_is_valid: non-hex');
		assert.match(false, ubbf.mac_is_valid('aa-bb-cc-dd-ee-ff'), 'mac_is_valid: wrong separator');
		assert.match(false, ubbf.mac_is_valid(42), 'mac_is_valid: non-string');
		assert.match(false, ubbf.mac_is_valid('aa:bb:cc:dd:ee:f0x'), 'mac_is_valid: trailing text');
		assert.match(false, ubbf.mac_is_valid('aa:bb:cc:dd:ee:\x00f'), 'mac_is_valid: embedded NUL');
	});

	it('mac_normalise', () => {
		assert.match('AA:BB:CC', ubbf.mac_normalise('aa:bb:cc'), 'mac_normalise: uppercases');
		assert.match('AABBCCDD', ubbf.mac_normalise('aa-bb-cc-dd', '-'), 'mac_normalise: strips given separators');
		assert.match('AABBCCDD', ubbf.mac_normalise('aa:bb-cc:dd', ':-'), 'mac_normalise: strips multiple separators');
		assert.match(null, ubbf.mac_normalise(null), 'mac_normalise: non-string');
	});

	it('mac_from_duid', () => {
		assert.match('AA:BB:CC:DD:EE:FF', ubbf.mac_from_duid('00030001aabbccddeeff'), 'mac_from_duid: DUID-LL');
		assert.match('34:18:D1:F1:2E:4A', ubbf.mac_from_duid('00010001deadbeef3418d1f12e4a'), 'mac_from_duid: DUID-LLT');
		assert.match(null, ubbf.mac_from_duid('00020001aabbccddeeff'), 'mac_from_duid: unsupported type');
		assert.match(null, ubbf.mac_from_duid('00030002aabbccddeeff'), 'mac_from_duid: wrong hw type');
		assert.match(null, ubbf.mac_from_duid('0003'), 'mac_from_duid: too short');
		assert.match(null, ubbf.mac_from_duid(null), 'mac_from_duid: non-string');
	});
});

describe('firewall helpers', () => {
	it('port_range_format', () => {
		assert.match('80', ubbf.port_range_format(80, 0), 'port_range_format: single port');
		assert.match('1000-2000', ubbf.port_range_format(1000, 2000), 'port_range_format: range');
		assert.match('80', ubbf.port_range_format(80, 80), 'port_range_format: pe<=p collapses');
		assert.match('443-445', ubbf.port_range_format('443', '445'), 'port_range_format: string ports');
		assert.match(null, ubbf.port_range_format(0, 100), 'port_range_format: p<=0');
		assert.match(null, ubbf.port_range_format('abc', 100), 'port_range_format: non-numeric');
	});

	it('protocol_to_uci', () => {
		assert.match('tcp', ubbf.protocol_to_uci(6), 'protocol_to_uci: numeric tcp');
		assert.match('udp', ubbf.protocol_to_uci(17), 'protocol_to_uci: numeric udp');
		assert.match('icmp', ubbf.protocol_to_uci(1), 'protocol_to_uci: numeric icmp');
		assert.match('icmpv6', ubbf.protocol_to_uci(58), 'protocol_to_uci: numeric icmpv6');
		assert.match('all', ubbf.protocol_to_uci(-1), 'protocol_to_uci: -1 is all');
		assert.match('47', ubbf.protocol_to_uci(47), 'protocol_to_uci: other positive number');
		assert.match('tcp', ubbf.protocol_to_uci('TCP'), 'protocol_to_uci: string TCP lowercase');
		assert.match('tcp', ubbf.protocol_to_uci('6'), 'protocol_to_uci: string numeric');
		assert.match(null, ubbf.protocol_to_uci('bogus'), 'protocol_to_uci: unknown string');
	});
});

describe('WiFi helpers', () => {
	it('freq_to_channel', () => {
		assert.match(1, ubbf.freq_to_channel(2412), 'freq_to_channel: 2.4 GHz ch1');
		assert.match(6, ubbf.freq_to_channel(2437), 'freq_to_channel: 2.4 GHz ch6');
		assert.match(14, ubbf.freq_to_channel(2484), 'freq_to_channel: 2.4 GHz ch14');
		assert.match(36, ubbf.freq_to_channel(5180), 'freq_to_channel: 5 GHz ch36');
		assert.match(1, ubbf.freq_to_channel(5955), 'freq_to_channel: 6 GHz');
		assert.match(1, ubbf.freq_to_channel('2412'), 'freq_to_channel: string');
		assert.match(0, ubbf.freq_to_channel(1000), 'freq_to_channel: out of range');
		assert.match(0, ubbf.freq_to_channel('abc'), 'freq_to_channel: non-numeric');
	});

	it('antenna_count', () => {
		assert.match(1, ubbf.antenna_count(0), 'antenna_count: zero mask -> 1');
		assert.match(1, ubbf.antenna_count(1), 'antenna_count: 0b0001 -> 1');
		assert.match(2, ubbf.antenna_count(3), 'antenna_count: 0b0011 -> 2');
		assert.match(4, ubbf.antenna_count(15), 'antenna_count: 0b1111 -> 4');
		assert.match(1, ubbf.antenna_count('abc'), 'antenna_count: non-integer -> 1');
	});

	it('txpower_pct_to_dbm', () => {
		assert.match(null, ubbf.txpower_pct_to_dbm(0, 20), 'txpower_pct_to_dbm: 0%');
		assert.match(null, ubbf.txpower_pct_to_dbm(100, 20), 'txpower_pct_to_dbm: 100%');
		assert.match(null, ubbf.txpower_pct_to_dbm(50, 0), 'txpower_pct_to_dbm: zero cap');
		assert.match(null, ubbf.txpower_pct_to_dbm('50', 20), 'txpower_pct_to_dbm: non-integer');

		let tp = ubbf.txpower_pct_to_dbm(50, 30);
		assert.match(true, tp >= 25 && tp <= 29, 'txpower_pct_to_dbm: mid-range reasonable');
		assert.match(9, ubbf.txpower_pct_to_dbm(1, 29), 'txpower_pct_to_dbm: 1% of a 29 dBm cap');
		assert.match(1, ubbf.txpower_pct_to_dbm(1, 12), 'txpower_pct_to_dbm: reduction below the cap clamps to the floor');
		assert.match(null, ubbf.txpower_pct_to_dbm(1, 1), 'txpower_pct_to_dbm: cap at the floor');
	});

	it('wifi_operating_standard', () => {
		assert.match('be', ubbf.wifi_operating_standard(['EHT-MCS0', '320MHz']), 'wifi_operating_standard: EHT');
		assert.match('ax', ubbf.wifi_operating_standard(['HE-MCS0']), 'wifi_operating_standard: HE');
		assert.match('ac', ubbf.wifi_operating_standard(['VHT-MCS0']), 'wifi_operating_standard: VHT');
		assert.match('n', ubbf.wifi_operating_standard(['MCS7']), 'wifi_operating_standard: MCS');
		assert.match('', ubbf.wifi_operating_standard([]), 'wifi_operating_standard: empty array');
		assert.match('', ubbf.wifi_operating_standard(['Foo']), 'wifi_operating_standard: unknown flag');
		assert.match('', ubbf.wifi_operating_standard(null), 'wifi_operating_standard: non-array');
	});
});

describe('address objects', () => {
	it('ipv4_addr_to_object', () => {
		let v4 = ubbf.ipv4_addr_to_object({ address: '192.168.1.1', mask: 24 });
		assert.match('192.168.1.1', v4?.IPAddress, 'ipv4_addr_to_object: IPAddress');
		assert.match('255.255.255.0', v4?.SubnetMask, 'ipv4_addr_to_object: SubnetMask');
		assert.match('DHCP', v4?.AddressingType, 'ipv4_addr_to_object: default AddressingType');

		let v4s = ubbf.ipv4_addr_to_object({ address: '10.0.0.1', mask: 8 }, 'Static');
		assert.match('Static', v4s?.AddressingType, 'ipv4_addr_to_object: explicit AddressingType');
		assert.match('0.0.0.0', ubbf.ipv4_addr_to_object({ address: '0.0.0.0', mask: 0 })?.SubnetMask, 'ipv4_addr_to_object: mask 0');
		assert.match({}, ubbf.ipv4_addr_to_object(null), 'ipv4_addr_to_object: non-object');
	});

	// The lifetimes are TR-181 dateTime (absolute expiry), not raw seconds.
	it('ipv6_addr_to_object with lifetimes', () => {
		let v6 = ubbf.ipv6_addr_to_object({ address: '2001:db8::1', preferred: 3600, valid: 7200 });
		assert.match('2001:db8::1', v6?.IPAddress, 'ipv6_addr_to_object: IPAddress');
		assert.match('Preferred', v6?.IPAddressStatus, 'ipv6_addr_to_object: preferred status');
		assert.match(true, match(v6?.PreferredLifetime, ISO8601_UTC) != null, 'ipv6_addr_to_object: PreferredLifetime is ISO8601');
		assert.match(true, match(v6?.ValidLifetime, ISO8601_UTC) != null, 'ipv6_addr_to_object: ValidLifetime is ISO8601');
		assert.match('DHCPv6', v6?.Origin, 'ipv6_addr_to_object: default Origin');

		let v6s = ubbf.ipv6_addr_to_object({ address: '::1', preferred: 0, valid: 0 }, 'Static');
		assert.match('Invalid', v6s?.IPAddressStatus, 'ipv6_addr_to_object: invalid status');
		assert.match('Static', v6s?.Origin, 'ipv6_addr_to_object: override Origin');
		assert.match({}, ubbf.ipv6_addr_to_object(null), 'ipv6_addr_to_object: non-object');
	});

	it('ipv6_addr_to_object for a lifetime without end', () => {
		let v6f = ubbf.ipv6_addr_to_object({ address: 'fe80::1' }, 'AutoConfigured', true);
		assert.match('Preferred', v6f?.IPAddressStatus, 'ipv6_addr_to_object: forever Status');
		assert.match(FOREVER, v6f?.PreferredLifetime, 'ipv6_addr_to_object: forever PreferredLifetime');
		assert.match(FOREVER, v6f?.ValidLifetime, 'ipv6_addr_to_object: forever ValidLifetime');
		assert.match('AutoConfigured', v6f?.Origin, 'ipv6_addr_to_object: forever Origin');
		assert.match('fe80::1', v6f?.IPAddress, 'ipv6_addr_to_object: forever IPAddress');

		let v6inf = ubbf.ipv6_addr_to_object({ address: '2001:db8::2' });
		assert.match([ 'Preferred', FOREVER, FOREVER ],
			[ v6inf?.IPAddressStatus, v6inf?.PreferredLifetime, v6inf?.ValidLifetime ], 'ipv6_addr_to_object: no lifetimes');

		let v6x = ubbf.ipv6_addr_to_object({ address: '2001:db8::3', preferred: 4294967295, valid: 4294967295 });
		assert.match([ 'Preferred', FOREVER ], [ v6x?.IPAddressStatus, v6x?.ValidLifetime ], 'ipv6_addr_to_object: 0xffffffff is infinite');
	});

	it('ipv6_addr_to_object for a run out preferred lifetime', () => {
		let v6dep = ubbf.ipv6_addr_to_object({ address: '2001:db8::4', preferred: 0, valid: 600 });

		assert.match('Deprecated', v6dep?.IPAddressStatus, 'ipv6_addr_to_object: preferred run out');
		assert.match(true, v6dep?.PreferredLifetime != FOREVER && match(v6dep?.PreferredLifetime, ISO8601_UTC) != null,
			'ipv6_addr_to_object: a run out lifetime is a time, not infinite');
	});

	it('ipv6_prefix_to_object', () => {
		let v6p = ubbf.ipv6_prefix_to_object({ address: '2001:db8::', mask: 32, preferred: 3600, valid: 7200 });

		assert.match('2001:db8::/32', v6p?.Prefix, 'ipv6_prefix_to_object: Prefix');
		assert.match('Preferred', v6p?.PrefixStatus, 'ipv6_prefix_to_object: PrefixStatus');
		assert.match('PrefixDelegation', v6p?.Origin, 'ipv6_prefix_to_object: default Origin');
		assert.match('Static', ubbf.ipv6_prefix_to_object({ address: '2001:db8::', mask: 64, preferred: 100, valid: 200 },
			'Static')?.Origin, 'ipv6_prefix_to_object: override Origin');
		assert.match({}, ubbf.ipv6_prefix_to_object(null), 'ipv6_prefix_to_object: non-object');
	});
});

describe('wde module', () => {
	it('mac_to_base64', () => {
		assert.match('AAAAAAAA', wde_lib.mac_to_base64('00:00:00:00:00:00'), 'mac_to_base64: all zero');
		assert.match('////////', wde_lib.mac_to_base64('ff:ff:ff:ff:ff:ff'), 'mac_to_base64: all ones');
		assert.match(8, length(wde_lib.mac_to_base64('aa:bb:cc:dd:ee:ff')), 'mac_to_base64: length is 8');
		assert.match('', wde_lib.mac_to_base64('aabbccddeeff'), 'mac_to_base64: missing colon');
		assert.match('', wde_lib.mac_to_base64('gg:bb:cc:dd:ee:ff'), 'mac_to_base64: non-hex');
		assert.match('', wde_lib.mac_to_base64(null), 'mac_to_base64: null');
		assert.match('', wde_lib.mac_to_base64('aa:bb:cc:dd:ee:ff:00'), 'mac_to_base64: trailing text');
		assert.match(wde_lib.mac_to_base64('aa:bb:cc:dd:ee:ff'), wde_lib.mac_to_base64('aA:Bb:cc:dd:ee:ff'), 'mac_to_base64: mixed case');
	});

	it('int_to_hexbin', () => {
		assert.match('00ff', wde_lib.int_to_hexbin(255, 2), 'int_to_hexbin: 255 as 2 bytes');
		assert.match('00000000', wde_lib.int_to_hexbin(0, 4), 'int_to_hexbin: zero');
		assert.match('deadbeef', wde_lib.int_to_hexbin(0xdeadbeef, 4), 'int_to_hexbin: full-width value');
		assert.match('', wde_lib.int_to_hexbin(5, 0), 'int_to_hexbin: bytes=0 rejected');
		assert.match('', wde_lib.int_to_hexbin(5, 17), 'int_to_hexbin: bytes>16 rejected');
		assert.match('', wde_lib.int_to_hexbin('5', 2), 'int_to_hexbin: non-int');
	});

	it('dscp_map_to_hex', () => {
		assert.match('0fff00', wde_lib.dscp_map_to_hex([15, 255, 0]), 'dscp_map_to_hex: basic');
		assert.match('0001', wde_lib.dscp_map_to_hex([256, 257]), 'dscp_map_to_hex: masks to 8 bits');
		assert.match('', wde_lib.dscp_map_to_hex([]), 'dscp_map_to_hex: empty');
		assert.match('', wde_lib.dscp_map_to_hex(null), 'dscp_map_to_hex: non-array');
	});

	it('bss_index_by_bssid', () => {
		let bss_idx = wde_lib.bss_index_by_bssid([
			{ bssid: 'AA:BB:CC:DD:EE:01', name: 'radio1' },
			{ bssid: 'AA:BB:CC:DD:EE:02', name: 'radio2' }
		]);
		assert.match('radio1', bss_idx['AA:BB:CC:DD:EE:01']?.name, 'bss_index_by_bssid: entry found');
		assert.match('radio2', bss_idx['AA:BB:CC:DD:EE:02']?.name, 'bss_index_by_bssid: other entry');

		let bss_idx2 = wde_lib.bss_index_by_bssid([
			{ radio: 'r1', bss: [
				{ bssid: 'AA:BB:CC:00:00:01', ssid: 'net1' },
				{ bssid: 'AA:BB:CC:00:00:02', ssid: 'net2' }
			] }
		], 'bss');
		assert.match('net1', bss_idx2['AA:BB:CC:00:00:01']?.ssid, 'bss_index_by_bssid: nested finds inner');
		assert.match('net2', bss_idx2['AA:BB:CC:00:00:02']?.ssid, 'bss_index_by_bssid: nested second inner');
		assert.match({}, wde_lib.bss_index_by_bssid(null), 'bss_index_by_bssid: non-array');
	});
});

describe('diagnostics parsers', () => {
	it('curl_w_metrics_parse', () => {
		let curl_out = ubbf.curl_w_metrics_parse("time_connect:0.123\ntime_total:0.456\n");

		assert.match('0.123', curl_out?.time_connect, 'curl_w_metrics_parse: time_connect');
		assert.match('0.456', curl_out?.time_total, 'curl_w_metrics_parse: time_total');
		assert.match(1, length(keys(ubbf.curl_w_metrics_parse("one\ntwo:three\n"))), 'curl_w_metrics_parse: skips colonless line');
		assert.match(1, length(keys(ubbf.curl_w_metrics_parse(":value\nkey:x\n"))), 'curl_w_metrics_parse: skips leading colon');
		assert.match({}, ubbf.curl_w_metrics_parse(null), 'curl_w_metrics_parse: non-string');
	});

	it('ping_output_parse of iputils ping', () => {
		let ping_in = "PING 8.8.8.8 (8.8.8.8) 56(84) bytes of data.\n" +
			"3 packets transmitted, 3 received, 0% packet loss\n" +
			"rtt min/avg/max/mdev = 10.500/15.200/20.100/0.000 ms\n";
		let ping_out = ubbf.ping_output_parse(ping_in, 3);

		assert.match('Complete', ping_out?.Status, 'ping_output_parse: Status');
		assert.match('8.8.8.8', ping_out?.IPAddressUsed, 'ping_output_parse: IPAddressUsed');
		assert.match('3', ping_out?.SuccessCount, 'ping_output_parse: SuccessCount');
		assert.match('0', ping_out?.FailureCount, 'ping_output_parse: FailureCount');
		assert.match('10', ping_out?.MinimumResponseTime, 'ping_output_parse: MinimumResponseTime');
		assert.match('15', ping_out?.AverageResponseTime, 'ping_output_parse: AverageResponseTime');
		assert.match('20', ping_out?.MaximumResponseTime, 'ping_output_parse: MaximumResponseTime');
		assert.match('10500', ping_out?.MinimumResponseTimeDetailed, 'ping_output_parse: MinimumResponseTimeDetailed');
		assert.match('Error_Other', ubbf.ping_output_parse("", 0)?.Status, 'ping_output_parse: no data');
		assert.match('Error_Other', ubbf.ping_output_parse(null, 3)?.Status, 'ping_output_parse: non-string');
		assert.match('3', ubbf.ping_output_parse(null, 3)?.FailureCount, 'ping_output_parse: non-string FailureCount from count');
	});

	it('ping_output_parse of busybox ping', () => {
		let ping_busybox = "PING 172.16.100.1 (172.16.100.1): 56 data bytes\n" +
			"3 packets transmitted, 3 packets received, 0% packet loss\n" +
			"round-trip min/avg/max = 0.500/1.200/2.100 ms\n";
		let ping_busybox_out = ubbf.ping_output_parse(ping_busybox, 3);

		assert.match('Complete', ping_busybox_out?.Status, 'ping_output_parse: busybox Status');
		assert.match('3', ping_busybox_out?.SuccessCount, 'ping_output_parse: busybox SuccessCount');
		assert.match('0', ping_busybox_out?.FailureCount, 'ping_output_parse: busybox FailureCount');
		assert.match('1', ping_busybox_out?.AverageResponseTime, 'ping_output_parse: busybox AverageResponseTime');
	});

	it('traceroute_output_parse', () => {
		let tr_in = "traceroute to example.com (93.184.216.34), 30 hops max, 60 byte packets\n" +
			" 1  router.local (192.168.1.1)  1.234 ms\n" +
			" 2  isp-gw (203.0.113.1)  15.567 ms\n" +
			" 3  * * *\n";
		let tr_out = ubbf.traceroute_output_parse(tr_in);

		assert.match('Complete', tr_out?.Status, 'traceroute_output_parse: Status');
		assert.match('93.184.216.34', tr_out?.IPAddressUsed, 'traceroute_output_parse: IPAddressUsed');
		assert.match('router.local', tr_out?.['RouteHops.1.Host'], 'traceroute_output_parse: hop 1 Host');
		assert.match('192.168.1.1', tr_out?.['RouteHops.1.HostAddress'], 'traceroute_output_parse: hop 1 HostAddress');
		assert.match('0', tr_out?.['RouteHops.1.ErrorCode'], 'traceroute_output_parse: hop 1 ErrorCode');
		assert.match('isp-gw', tr_out?.['RouteHops.2.Host'], 'traceroute_output_parse: hop 2 Host');
		assert.match('1', tr_out?.['RouteHops.3.ErrorCode'], 'traceroute_output_parse: hop 3 timeout ErrorCode');
		assert.match('Error_Other', ubbf.traceroute_output_parse(null)?.Status, 'traceroute_output_parse: non-string');
	});
});

describe('sysfs interface properties', () => {
	it('link_properties_get', () => {
		let link_lo = ubbf.link_properties_get('lo');

		assert.match('string', type(link_lo?.MTU), 'link_properties_get: MTU present');
		assert.match('string', type(link_lo?.MACAddress), 'link_properties_get: has MACAddress');
		assert.match({}, ubbf.link_properties_get(null), 'link_properties_get: non-string');
	});

	it('ethernet_properties_get', () => {
		let eth_lo = ubbf.ethernet_properties_get('lo');

		assert.match('true', eth_lo?.Enable, 'ethernet_properties_get: Enable');
		assert.match('string', type(eth_lo?.MACAddress), 'ethernet_properties_get: MACAddress present');
		assert.match({}, ubbf.ethernet_properties_get(null), 'ethernet_properties_get: non-string');
	});
});

describe('atomic file writes', () => {
	it('tmpfile_name', () => {
		let tmpname = ubbf.tmpfile_name('ubbf_test', '.tmp');

		assert.match('/tmp/', substr(tmpname, 0, 5), 'tmpfile_name: under /tmp');
		assert.match('.tmp', substr(tmpname, length(tmpname) - 4, 4), 'tmpfile_name: extension preserved');
		assert.match(null, ubbf.tmpfile_name(42), 'tmpfile_name: non-string prefix');
		ubbf.write_file_atomic(tmpname, '');
	});

	it('write_file_atomic', () => {
		let atomic_path = sprintf('/tmp/ubbf_unittest_%d.txt', time());

		assert.match(true, ubbf.write_file_atomic(atomic_path, 'hello\n'), 'write_file_atomic: success');
		assert.match('hello', ubbf.readfile_trim(atomic_path, ''), 'write_file_atomic: content readable');
		assert.match(true, ubbf.write_file_atomic(atomic_path, ''), 'write_file_atomic: delete on empty content');
		assert.match('missing', ubbf.readfile_trim(atomic_path, 'missing'), 'write_file_atomic: file gone');
		assert.match(false, ubbf.write_file_atomic(null, 'x'), 'write_file_atomic: non-string path');

		assert.match(true, ubbf.write_file_atomic(atomic_path, 'x') && (fs_mod.stat(atomic_path).mode & 0777) == 0644,
			'write_file_atomic: default mode');
		fs_mod.writefile(atomic_path + '.tmp', 'stale');
		fs_mod.chmod(atomic_path + '.tmp', 0666);
		assert.match(true, ubbf.write_file_atomic(atomic_path, 'secret', 0600) && (fs_mod.stat(atomic_path).mode & 0777) == 0600,
			'write_file_atomic: mode 0600 over a stale temp file');
		ubbf.write_file_atomic(atomic_path, '');
	});
});

describe('users module', () => {
	it('rate_limit_check', () => {
		let rl_key = sprintf('ubbf_rl_test_%d', time());

		assert.match(true, users_lib.rate_limit_check(rl_key, 3, 60), 'rate_limit_check: first call within window');
		assert.match(true, users_lib.rate_limit_check(rl_key, 3, 60), 'rate_limit_check: second');
		assert.match(true, users_lib.rate_limit_check(rl_key, 3, 60), 'rate_limit_check: third');
		assert.match(false, users_lib.rate_limit_check(rl_key, 3, 60), 'rate_limit_check: fourth blocked');
		assert.match(false, users_lib.rate_limit_check(null, 3, 60), 'rate_limit_check: non-string key');
	});
});

describe('wol module', () => {
	it('send refuses bad arguments', () => {
		assert.match(null, wol_lib.send(null, 'aa:bb:cc:dd:ee:ff'), 'wol_send: non-string iface');
		assert.match(null, wol_lib.send('lo', null), 'wol_send: non-string mac');
		assert.match(null, wol_lib.send('lo', 'zz:bb:cc:dd:ee:ff'), 'wol_send: invalid mac');
		assert.match(null, wol_lib.send('lo', 'aa-bb-cc-dd-ee-ff'), 'wol_send: mac with dashes');
		assert.match(null, wol_lib.send('lo', 'aa:bb:cc:dd:ee:ff0'), 'wol_send: mac with trailing text');
		assert.match(null, wol_lib.send('lo', '0xa:bb:cc:dd:ee:ff'), 'wol_send: mac with 0x prefix');
		assert.match(null, wol_lib.send('lo', 'aa:bb:cc:dd:ee:ff', 'ZZ'), 'wol_send: invalid password');
		assert.match(null, wol_lib.send('lo', 'aa:bb:cc:dd:ee:ff', 'aa:bb:cc:dd:'), 'wol_send: password with trailing separator');
		assert.match(null, wol_lib.send('lo', 'aa:bb:cc:dd:ee:ff', 'aa:bb-cc:dd'), 'wol_send: password with mixed separators');
		assert.match(null, wol_lib.send('lo', 'aa:bb:cc:dd:ee:ff', 'aabb:ccdd'), 'wol_send: password with separator in bare hex');
		assert.match(null, wol_lib.send('lo', 'aa:bb:cc:dd:ee:ff', 'aa:bb:cc'), 'wol_send: password of 3 bytes');
		assert.match(null, wol_lib.send('lo', 'aa:bb:cc:dd:ee:ff', 'aabbccddee'), 'wol_send: password of 5 bytes');
		assert.match(null, wol_lib.send('lo', 'aa:bb:cc:dd:ee:ff', '192.168.1.5'), 'wol_send: dotted-decimal password');
	});

	// The send itself depends on privilege, so only the type of the result
	// is checked.
	it('send takes valid arguments', () => {
		assert.match('bool', type(wol_lib.send('nonexistent_iface', 'aa:bb:cc:dd:ee:ff')), 'wol_send: valid args return bool');
		for (let pw in ['aabbccdd', 'aabbccddeeff', 'aa:bb:cc:dd', 'aa-bb-cc-dd-ee-ff'])
			assert.match('bool', type(wol_lib.send('nonexistent_iface', 'aa:bb:cc:dd:ee:ff', pw)), `wol_send: password ${pw} accepted`);
	});
});

describe('led module', () => {
	it('read_info of a missing LED', () => {
		let led = led_lib.read_info('bogus_led_name_does_not_exist');

		assert.match('object', type(led), 'led_read_info: returns object');
		assert.match('bogus_led_name_does_not_exist', led?.Name, 'led_read_info: Name field');
		assert.match('Error', led?.Status, 'led_read_info: missing LED is Error');
		assert.match('false', led?.Enable, 'led_read_info: missing LED is not enabled');
		assert.match('0', led?.MaxBrightness, 'led_read_info: missing LED MaxBrightness');
		assert.match(sort(['Enable', 'Name', 'Status', 'CyclePeriodRepetitions',
				'Location', 'RelativeXPosition', 'RelativeYPosition', 'MaxBrightness',
				'CycleElementNumberOfEntries']), sort(keys(led)), 'led_read_info: no keys outside the schema');
		assert.match(null, led_lib.read_info('mt76-phy0')?.CurrentColor, 'led_read_info: name without a colon');
	});

	it('read_info refuses a bad name', () => {
		assert.match(null, led_lib.read_info(null), 'led_read_info: non-string');
		assert.match(null, led_lib.read_info('../../../etc'), 'led_read_info: name with a slash');
		assert.match(null, led_lib.read_info('..'), 'led_read_info: name ..');
		assert.match(null, led_lib.read_info(''), 'led_read_info: empty name');
	});
});

describe('usb module', () => {
	it('enumerate', () => {
		let usb = usb_lib.enumerate();

		assert.match('object', type(usb), 'usb_enumerate: object');
		assert.match('array', type(usb?.hosts), 'usb_enumerate: hosts is array');
		assert.match('array', type(usb?.devices), 'usb_enumerate: devices is array');
		assert.match('array', type(usb?.interfaces), 'usb_enumerate: interfaces is array');
	});

	it('device_info', () => {
		assert.match(null, usb_lib.device_info('nonexistent-usb-dev'), 'usb_device_info: not a USB name');
		assert.match(null, usb_lib.device_info('99-99'), 'usb_device_info: missing device');
		assert.match(null, usb_lib.device_info(null), 'usb_device_info: non-string');
	});

	it('interface_info', () => {
		assert.match(null, usb_lib.interface_info('nonexistent-iface:1.0'), 'usb_interface_info: not a USB name');
		assert.match(null, usb_lib.interface_info('99-99:1.0'), 'usb_interface_info: missing interface');
		assert.match(null, usb_lib.interface_info(null), 'usb_interface_info: non-string');
	});

	it('net_interfaces', () => {
		assert.match('array', type(usb_lib.net_interfaces()), 'usb_net_interfaces: returns array');
	});
});

describe('get results follow the schema', () => {
	it('keeps declared parameters and drops the others', () => {
		let dm = ubbf.create();
		let x_rows = [{ Name: 'a', Stray: 's' }, { Name: 'b', Stray: 't' }];

		dm.register({
			'Device.X': {
				schema: { schema: { Kept: 1 }, defaults: {} },
				get: () => ({
					Kept: 'k', Hidden: 'h', '.name': 'n',
					Child: { Inner: 'i', Stray: 'c' },
					Gone: { Inner: 'g' },
					Inline: { '1': { Name: 'r', Stray: 'z' } }
				})
			},
			'Device.X.Child': {
				schema: { schema: { Inner: 1 }, defaults: {} }
			},
			'Device.X.Inline': {
			},
			'Device.X.Inline.{i}': {
				schema: { schema: { Name: 1 }, defaults: {} }
			},
			'Device.X.Row.{i}': {
				schema: { schema: { Name: 1 }, defaults: { Name: '' } },
				get: (ctx) => rows_get(x_rows, ctx)
			},
			'Device.Y': {
				get: () => ({ Free: 'f' })
			}
		});
		dm.load('/dev/null');
		dm.set_config({ Device: { X: {}, Y: {} } });
		dm.runtime_reload();

		let x_tree = dm.get_subtree_with_state('Device.X');
		assert.match('k', x_tree?.Kept, 'get result: a declared parameter stays');
		assert.match(null, x_tree?.Hidden, 'get result: an undeclared parameter goes');
		assert.match('i', x_tree?.Child?.Inner, 'get result: a registered child object stays');
		assert.match(null, x_tree?.Child?.Stray, 'get result: an inline child follows its own schema');
		assert.match('r', x_tree?.Inline?.['1']?.Name, 'get result: an inline table keeps its rows');
		assert.match(null, x_tree?.Inline?.['1']?.Stray, 'get result: an inline row follows the row schema');
		assert.match(null, x_tree?.Gone, 'get result: an unregistered child object goes');
		assert.match('n', x_tree?.['.name'], 'get result: a metadata key stays');
		assert.match([ 'a', 'b' ], [ x_tree?.Row?.['1']?.Name, x_tree?.Row?.['2']?.Name ], 'get result: enumerated rows keep declared parameters');
		assert.match(null, x_tree?.Row?.['1']?.Stray, 'get result: enumerated rows lose undeclared parameters');
		assert.match(null, dm.get_subtree_with_state('Device.X.Row.2')?.Stray, 'get result: also for one row');
		assert.match('f', dm.get_subtree_with_state('Device.Y')?.Free, 'get result: an entry without a schema is left alone');
	});
});

describe('schema rules', () => {
	it('params_set checks each value against its rule', () => {
		let dm = dm_rules_create();

		for (let c in RULE_CASES) {
			dm.trans_start();
			let rc = dm.params_set({ ['Device.V.' + c[0]]: c[1] });
			let stored = dm.config()?.Device?.V?.[c[0]];
			dm.trans_abort();

			assert.match(c[2], rc, `params_set rule: ${c[0]} = ${c[1]}`);
			if (c[2] < 0)
				assert.match(null, stored, `params_set rule: ${c[0]} = ${c[1]} not stored`);
		}
	});

	it('one bad value refuses the whole set', () => {
		let dm = dm_rules_create();

		dm.trans_start();
		assert.match(-4, dm.params_set({ 'Device.V.Mode': 'Auto', 'Device.V.Port': '0' }), 'params_set rule: one bad value refuses the set');
		assert.match(null, dm.config()?.Device?.V?.Mode, 'params_set rule: the good value of that set is not stored');
		dm.trans_abort();
	});

	it('object_add follows addable and max_instances', () => {
		let dm = dm_rules_create();

		dm.trans_start();
		assert.match(0, dm.object_add('Device.V.Fixed'), 'object_add: schema addable false refuses');
		assert.match(true, dm.object_add('Device.V.Two') > 0, 'object_add: schema max_instances 1 of 2');
		assert.match(true, dm.object_add('Device.V.Two') > 0, 'object_add: schema max_instances 2 of 2');
		assert.match(0, dm.object_add('Device.V.Two'), 'object_add: schema max_instances refuses the third');
		assert.match(true, dm.object_add('Device.V.Own') > 0, 'object_add: entry addable wins over schema');
		assert.match(0, dm.object_add('Device.V.Own'), 'object_add: entry maxInstances wins over schema');
		dm.trans_abort();
	});

	it('schema_entry_addable', () => {
		assert.match(false, ubbf.schema_entry_addable({ maxInstances: 0 }), 'schema_entry_addable: maxInstances 0');
		assert.match(true, ubbf.schema_entry_addable({ maxInstances: 1 }), 'schema_entry_addable: maxInstances 1');
		assert.match(true, ubbf.schema_entry_addable({}), 'schema_entry_addable: no limit');
	});

	it('object_add needs the parents of the new row', () => {
		let dm = ubbf.create();

		dm.register({
			'Device.N': {},
			'Device.N.Chain.{i}': { schema: { schema: { Alias: T_STRING | W }, defaults: { Alias: '' } } },
			'Device.N.Chain.{i}.Rule.{i}': { schema: { schema: { Alias: T_STRING | W }, defaults: { Alias: '' } } }
		});
		dm.load('/dev/null');
		dm.set_config({ Device: { N: { Chain: { '1': { Alias: 'c1' } } } } });

		dm.trans_start();
		assert.match(true, dm.object_add('Device.N.Chain.1.Rule') > 0, 'object_add: row under an existing parent');
		assert.match(0, dm.object_add('Device.N.Chain.999.Rule'), 'object_add: row under a missing parent refused');
		assert.match(null, dm.config()?.Device?.N?.Chain?.['999'], 'object_add: missing parent not created');

		let digits = '';
		for (let i = 0; i < 600; i++)
			digits += '9';
		assert.match(0, dm.object_add(`Device.N.Chain.${digits}.Rule`), 'object_add: oversized instance refused');
		dm.trans_abort();
	});
});

describe('schema tables', () => {
	(mdns_table_loaded ? it : skip)('params_set checks the rules of a table', () => {
		let dm = ubbf.create();

		dm.register({
			'Device.DNS.SD.Advertise.{i}': { schema: 'mdns.SD_Advertise' },
			'Device.DNS.SD.Service.{i}': { schema: 'mdns.SD_Service' }
		});
		dm.load('/dev/null');
		dm.set_config({ Device: { DNS: { SD: { Advertise: { '1': {} } } } } });

		const TABLE_CASES = [
			[ 'TransportProtocol', 'UDP', 0 ], [ 'TransportProtocol', 'SCTP', -4 ],
			[ 'Port', '65535', 0 ], [ 'Port', '65536', -4 ],
			[ 'InstanceName', 'x', 0 ], [ 'InstanceName', sprintf('%64s', 'x'), -4 ],
			[ 'Enable', 'maybe', -4 ],
		];

		for (let c in TABLE_CASES) {
			dm.trans_start();
			assert.match(c[2], dm.params_set({ ['Device.DNS.SD.Advertise.1.' + c[0]]: c[1] }), `params_set table rule: ${c[0]} = ${c[1]}`);
			dm.trans_abort();
		}

		dm.trans_start();
		assert.match(0, dm.object_add('Device.DNS.SD.Service'), 'object_add: table addable false refuses');
		dm.trans_abort();
	});

	(mdns_table_loaded ? it : skip)('schema_param_info and schema_entry_addable read a table', () => {
		assert.match({ enum: [ 'TCP', 'UDP' ], writable: true, type: 'DM_STRING' },
			ubbf.schema_param_info('mdns.SD_Advertise', 'TransportProtocol'), 'schema_param_info: table rule facts');
		assert.match({ max: 65535, writable: true, type: 'DM_UINT' },
			ubbf.schema_param_info('mdns.SD_Advertise', 'Port'), 'schema_param_info: table max');
		assert.match(false, ubbf.schema_entry_addable({ schema: 'mdns.SD_Service' }), 'schema_entry_addable: table');
		assert.match(true, ubbf.schema_entry_addable({ schema: 'mdns.SD_Service', addable: true }), 'schema_entry_addable: entry wins');
	});

	// Named TR-181 data types carry their base type: StatsCounter32 and Order
	// are unsignedInt, StatsCounter64 is unsignedLong.
	(core_table_loaded ? it : skip)('named data types carry their base type', () => {
		const TYPE_CASES = [
			[ 'Bridging.Port_Stats', 'BytesSent', 'DM_ULONG' ],
			[ 'Bridging.Port_Stats', 'ErrorsSent', 'DM_UINT' ],
			[ 'Firewall.Chain_Rule', 'Order', 'DM_UINT' ],
			[ 'Routing.Router_IPv4Forwarding', 'MTU', 'DM_UINT' ],
		];

		for (let c in TYPE_CASES)
			assert.match(c[2], ubbf.schema_param_info(c[0], c[1])?.type, `schema_param_info: ${c[0]}.${c[1]} type`);

		let stats_defaults = ubbf.schema_defaults('Bridging.Port_Stats');
		assert.match('18446744073709551615', stats_defaults?.BytesSent, 'schema_defaults: StatsCounter64 without data');
		assert.match('4294967295', stats_defaults?.ErrorsSent, 'schema_defaults: StatsCounter32 without data');
	});

	(core_table_loaded ? it : skip)('params_set checks the Order of a firewall rule', () => {
		let dm = ubbf.create();

		dm.register({ 'Device.Firewall.Chain.{i}.Rule.{i}': { schema: 'Firewall.Chain_Rule' } });
		dm.load('/dev/null');
		dm.set_config({ Device: { Firewall: { Chain: { '1': { Rule: { '1': {} } } } } } });

		for (let c in [ [ '2', 0 ], [ 'abc', -4 ], [ '0', -4 ], [ '4294967296', -4 ] ]) {
			dm.trans_start();
			assert.match(c[1], dm.params_set({ 'Device.Firewall.Chain.1.Rule.1.Order': c[0] }), `params_set: Chain.Rule.Order = ${c[0]}`);
			dm.trans_abort();
		}
	});
});

describe('get context', () => {
	it('gives the instances of the path', () => {
		let dm = ubbf.create();

		dm.register({
			'Device.N': {},
			'Device.N.Row.{i}': { schema: seen_schema, get: seen_get },
			'Device.N.Row.{i}.Sub.{i}': { schema: seen_schema, get: seen_get },
			'Device.N.Row.{i}.Live.{i}': { schema: seen_schema, get: seen_get }
		});
		dm.load('/dev/null');
		dm.set_config({ Device: { N: { Row: { '2': { Sub: { '3': {} } } } } } });
		dm.runtime_reload();

		let inst_tree = dm.get_subtree_with_state('Device.N');
		assert.match('2', inst_tree?.Row?.['2']?.Seen, 'get context: instances of a row');
		assert.match('2.3', inst_tree?.Row?.['2']?.Sub?.['3']?.Seen, 'get context: instances of a row below a row');
		assert.match('enumerated below 2', inst_tree?.Row?.['2']?.Live?.['7']?.Seen,
			'get context: enumerate mode gets the instances of the parent row');

		let inst_paths = { 'Device.N.Row.2.Sub.3.Seen': null };
		dm.params_get(inst_paths);
		assert.match('2.3', inst_paths['Device.N.Row.2.Sub.3.Seen'], 'get context: instances for a single parameter');
	});
});

describe('writable_rows', () => {
	it('a write into a live row that is not stored', () => {
		let dm = ubbf.create();

		dm.register({
			'Device.L': {},
			'Device.L.Row.{i}': { schema: live_schema, get: live_row_get, set: () => 0,
			                      runtime_instances: true, writable_rows: true },
			'Device.M': {},
			'Device.M.Row.{i}': { schema: live_schema, get: live_row_get, set: () => 0,
			                      runtime_instances: true }
		});
		dm.load('/dev/null');
		dm.set_config({ Device: { L: {}, M: {} } });

		dm.trans_start();
		assert.match(0, dm.params_set({ 'Device.L.Row.2.Enable': 'false' }), 'writable_rows: write into a live row');
		assert.match('false', dm.config()?.Device?.L?.Row?.['2']?.Enable, 'writable_rows: the write is stored');
		assert.match(0, dm.params_set({ 'Device.L.Row.1.Enable': 'true' }),
			'writable_rows: write into a second live row, the table being stored');
		assert.match(-2, dm.params_set({ 'Device.L.Row.5.Enable': 'false' }), 'writable_rows: write into a row that is not live');
		assert.match(null, dm.config()?.Device?.L?.Row?.['5'], 'writable_rows: no phantom row');
		assert.match(-2, dm.params_set({ 'Device.M.Row.2.Enable': 'false' }), 'runtime_instances alone: a runtime row is read-only');
		dm.trans_commit();
		dm.runtime_reload();

		let live_tree = dm.get_subtree_with_state('Device.L')?.Row;
		assert.match([ 'stored', 'true', 'stored', 'false' ],
			[ live_tree?.['1']?.Live, live_tree?.['1']?.Enable, live_tree?.['2']?.Live, live_tree?.['2']?.Enable ],
			'writable_rows: both rows after the writes');
	});

	it('a row added below a live row', () => {
		let dm = ubbf.create();

		dm.register({
			'Device.L': {},
			'Device.L.Row.{i}': { schema: live_schema, get: live_row_get, set: () => 0,
			                      runtime_instances: true, writable_rows: true },
			'Device.L.Row.{i}.Child.{i}': { schema: { schema: { Alias: T_STRING, Enable: T_BOOL | W }, defaults: { Alias: '' } } }
		});
		dm.load('/dev/null');
		dm.set_config({ Device: { L: {} } });

		dm.trans_start();
		assert.match(0, dm.params_set({ 'Device.L.Row.1.Enable': 'true' }), 'writable_rows: store one live row');
		assert.match(1, dm.object_add('Device.L.Row.2.Child'), 'writable_rows: add below another live row, the table being stored');
		assert.match(0, dm.object_add('Device.L.Row.5.Child'), 'writable_rows: add below a row that is not live');
		assert.match(null, dm.config()?.Device?.L?.Row?.['5'], 'writable_rows: no phantom parent row');
		dm.trans_abort();
	});
});
