'use strict';

let ubbf, usb_lib, led_lib, wol_lib, wde_lib, multicast_lib, users_lib;

try {
	ubbf = require('ubbf');
	usb_lib = require('usb');
	led_lib = require('led');
	wol_lib = require('wol');
	wde_lib = require('wde');
	multicast_lib = require('multicast');
	users_lib = require('users');
} catch (e) {
	printf('FATAL: cannot load a native module: %s\n', e);
	printf('Hint: pass -L for ubbf.so and the module libraries (usb, led, wol, wde, multicast, users)\n');
	exit(1);
}

let pass_count = 0;
let fail_count = 0;

function assert_eq(name, got, expected) {
	let got_json = sprintf('%.J', got);
	let exp_json = sprintf('%.J', expected);

	if (got_json == exp_json) {
		pass_count++;
		return;
	}

	fail_count++;
	printf('FAIL: %s\n  expected: %s\n  got:      %s\n', name, exp_json, got_json);
}

function assert_true(name, got) {
	assert_eq(name, got, true);
}

function assert_false(name, got) {
	assert_eq(name, got, false);
}

function assert_null(name, got) {
	assert_eq(name, got, null);
}

/* ---- path_to_parts ---------------------------------------------------- */

assert_eq('path_to_parts: simple',
	ubbf.path_to_parts('Device.WiFi.Radio'),
	['Device', 'WiFi', 'Radio']);

assert_eq('path_to_parts: with instance',
	ubbf.path_to_parts('Device.IP.Interface.1'),
	['Device', 'IP', 'Interface', '1']);

assert_eq('path_to_parts: trailing dot',
	ubbf.path_to_parts('Device.WiFi.'),
	['Device', 'WiFi']);

assert_eq('path_to_parts: leading dot',
	ubbf.path_to_parts('.Device.WiFi'),
	['Device', 'WiFi']);

assert_eq('path_to_parts: empty string',
	ubbf.path_to_parts(''),
	[]);

assert_eq('path_to_parts: single part',
	ubbf.path_to_parts('Device'),
	['Device']);

assert_eq('path_to_parts: null input',
	ubbf.path_to_parts(null),
	[]);

/* ---- navigate_data ---------------------------------------------------- */

let tree = {
	Device: {
		WiFi: {
			Radio: {
				'1': { Enable: 'true', Channel: '6' }
			}
		}
	}
};

assert_eq('navigate_data: deep path',
	ubbf.navigate_data(tree, ['Device', 'WiFi', 'Radio', '1', 'Enable']),
	'true');

assert_eq('navigate_data: intermediate object',
	ubbf.navigate_data(tree, ['Device', 'WiFi', 'Radio', '1']),
	{ Enable: 'true', Channel: '6' });

assert_null('navigate_data: missing key',
	ubbf.navigate_data(tree, ['Device', 'Ethernet']));

assert_null('navigate_data: null data',
	ubbf.navigate_data(null, ['Device']));

/* ---- pattern_matches_path --------------------------------------------- */

assert_true('pattern_matches_path: prefix match',
	ubbf.pattern_matches_path('Device.WiFi.Radio.{i}', 'Device.WiFi'));

assert_true('pattern_matches_path: empty path',
	ubbf.pattern_matches_path('Device.WiFi', ''));

assert_true('pattern_matches_path: Device only',
	ubbf.pattern_matches_path('Device.WiFi', 'Device'));

assert_false('pattern_matches_path: longer path than pattern',
	ubbf.pattern_matches_path('Device.WiFi', 'Device.WiFi.Radio'));

assert_false('pattern_matches_path: mismatch',
	ubbf.pattern_matches_path('Device.WiFi', 'Device.Ethernet'));

assert_true('pattern_matches_path: instance skipped',
	ubbf.pattern_matches_path('Device.IP.Interface.{i}', 'Device.IP.Interface'));

/* ---- to_bool ---------------------------------------------------------- */

assert_true('to_bool: string true', ubbf.to_bool('true'));
assert_true('to_bool: string 1', ubbf.to_bool('1'));
assert_false('to_bool: string false', ubbf.to_bool('false'));
assert_false('to_bool: string 0', ubbf.to_bool('0'));
assert_true('to_bool: bool true', ubbf.to_bool(true));
assert_false('to_bool: bool false', ubbf.to_bool(false));
assert_false('to_bool: null', ubbf.to_bool(null));

/* ---- to_int ----------------------------------------------------------- */

assert_eq('to_int: integer passthrough', ubbf.to_int(42), 42);
assert_eq('to_int: string number', ubbf.to_int('123'), 123);
assert_eq('to_int: string negative', ubbf.to_int('-5'), -5);
assert_null('to_int: non-numeric string', ubbf.to_int('abc'));
assert_null('to_int: null', ubbf.to_int(null));
assert_null('to_int: empty string', ubbf.to_int(''));

/* ---- csv_to_list ------------------------------------------------------ */

assert_eq('csv_to_list: basic',
	ubbf.csv_to_list('a,b,c'),
	['a', 'b', 'c']);

assert_eq('csv_to_list: with spaces',
	ubbf.csv_to_list(' a , b , c '),
	['a', 'b', 'c']);

assert_eq('csv_to_list: with filter',
	ubbf.csv_to_list('1,-1,3', '-1'),
	['1', '3']);

assert_eq('csv_to_list: empty string',
	ubbf.csv_to_list(''),
	[]);

assert_eq('csv_to_list: null',
	ubbf.csv_to_list(null),
	[]);

/* ---- IP utilities ----------------------------------------------------- */

assert_eq('ip_to_int: basic',
	ubbf.ip_to_int('192.168.1.1'),
	(192 << 24) | (168 << 16) | (1 << 8) | 1);

assert_eq('int_to_ip: basic',
	ubbf.int_to_ip((10 << 24) | (0 << 16) | (0 << 8) | 1),
	'10.0.0.1');

assert_eq('ip roundtrip',
	ubbf.int_to_ip(ubbf.ip_to_int('172.16.100.2')),
	'172.16.100.2');

assert_eq('cidr_to_netmask: /24',
	ubbf.cidr_to_netmask(24),
	'255.255.255.0');

assert_eq('cidr_to_netmask: /32',
	ubbf.cidr_to_netmask(32),
	'255.255.255.255');

assert_eq('cidr_to_netmask: /0',
	ubbf.cidr_to_netmask(0),
	'0.0.0.0');

assert_eq('netmask_to_cidr: /24',
	ubbf.netmask_to_cidr('255.255.255.0'),
	24);

assert_eq('netmask_to_cidr: /16',
	ubbf.netmask_to_cidr('255.255.0.0'),
	16);

assert_eq('cidr roundtrip',
	ubbf.netmask_to_cidr(ubbf.cidr_to_netmask(20)),
	20);

/* ---- instance utilities ----------------------------------------------- */

assert_true('is_instance_key: valid string', ubbf.is_instance_key('1'));
assert_true('is_instance_key: larger number', ubbf.is_instance_key('42'));
assert_false('is_instance_key: zero', ubbf.is_instance_key('0'));
assert_false('is_instance_key: negative', ubbf.is_instance_key('-1'));
assert_false('is_instance_key: non-numeric', ubbf.is_instance_key('abc'));
assert_false('is_instance_key: leading space', ubbf.is_instance_key(' 1'));
assert_false('is_instance_key: plus sign', ubbf.is_instance_key('+1'));
assert_false('is_instance_key: beyond int', ubbf.is_instance_key('2147483648'));
assert_true('is_instance_key: int maximum', ubbf.is_instance_key('2147483647'));
assert_true('is_instance_key: integer 5', ubbf.is_instance_key(5));
assert_false('is_instance_key: integer 0', ubbf.is_instance_key(0));

let container = { '1': {}, '2': {}, '3': {}, Name: 'test' };
assert_eq('instance_count: mixed keys', ubbf.instance_count(container), 3);
assert_eq('instance_count: empty object', ubbf.instance_count({}), 0);
assert_eq('instance_count: null', ubbf.instance_count(null), 0);

assert_eq('find_next_instance: contiguous', ubbf.find_next_instance(container), 4);
assert_eq('find_next_instance: with gap',
	ubbf.find_next_instance({ '1': {}, '3': {} }), 2);
assert_eq('find_next_instance: empty', ubbf.find_next_instance({}), 1);

/* ---- tree operations -------------------------------------------------- */

let nav_obj = {};
ubbf.navigate_or_create(nav_obj, ['Device', 'WiFi', 'Radio']);
assert_eq('navigate_or_create: creates path',
	type(nav_obj?.Device?.WiFi?.Radio), 'object');

/* ---- collect_instances_for_pattern ------------------------------------ */

let collect_data = {
	Device: {
		IP: {
			Interface: {
				'1': { Name: 'lan', IPv4Address: { '1': { IPAddress: '192.168.1.1' } } },
				'2': { Name: 'wan' }
			}
		}
	}
};

let collected = ubbf.collect_instances_for_pattern(
	['Device', 'IP', 'Interface', '{i}'],
	collect_data, 0, '');
assert_true('collect_instances: finds instance 1',
	index(collected, 'Device.IP.Interface.1') >= 0);
assert_true('collect_instances: finds instance 2',
	index(collected, 'Device.IP.Interface.2') >= 0);

let collected2 = ubbf.collect_instances_for_pattern(
	['Device', 'IP', 'Interface', '{i}', 'IPv4Address', '{i}'],
	collect_data, 0, '');
assert_true('collect_instances: nested pattern',
	index(collected2, 'Device.IP.Interface.1.IPv4Address.1') >= 0);

/* ---- entries_count_update --------------------------------------------- */

let parent_obj = {};
let child_container = { '1': {}, '2': {}, '3': {} };
ubbf.entries_count_update(parent_obj, 'Interface', child_container);
assert_eq('entries_count_update: sets count',
	parent_obj.InterfaceNumberOfEntries, '3');

/* ---- dm helper functions ----------------------------------------------- */

let dm_config = {
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

assert_eq('get: simple path',
	ubbf.get(dm_config, 'Device.IP.Interface.1.Name'), 'lan');

assert_null('get: missing path',
	ubbf.get(dm_config, 'Device.WiFi'));

let insts = ubbf.instances(dm_config, 'Device.IP.Interface');
assert_eq('instances: count', length(insts), 2);
assert_true('instances: has .instance key',
	insts[0]['.instance'] != null);
assert_true('instances: has .path key',
	insts[0]['.path'] != null);

assert_true('enabled: true string',
	ubbf.enabled(dm_config, 'Device.IP.Interface.1.Enable'));
assert_false('enabled: false string',
	ubbf.enabled(dm_config, 'Device.IP.Interface.2.Enable'));
assert_false('enabled: missing path',
	ubbf.enabled(dm_config, 'Device.IP.Interface.99.Enable'));

assert_eq('interface_to_name: resolves',
	ubbf.interface_to_name(dm_config, 'Device.IP.Interface.1'), 'lan');
assert_null('interface_to_name: null ref',
	ubbf.interface_to_name(dm_config, null));

assert_eq('lower_layer_resolve: resolves first',
	ubbf.lower_layer_resolve(dm_config, 'Device.Ethernet.Link.1'), 'br-lan');
assert_null('lower_layer_resolve: empty',
	ubbf.lower_layer_resolve(dm_config, ''));

/* ---- name aliases ----------------------------------------------------- */

assert_eq('navigate_data alias: works',
	ubbf.navigate_data(dm_config, ['Device', 'IP', 'Interface', '1', 'Name']), 'lan');

assert_eq('instance_count alias: works',
	ubbf.instance_count({ '1': {}, '2': {} }), 2);

/* ---- datamodel resource ----------------------------------------------- */

let dm = ubbf.create();
assert_eq('create: returns resource', type(dm), 'resource');

let model = {
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
};

assert_true('dm.register: succeeds', dm.register(model));

/* dm.lookup with in-memory config */
let test_config = {
	Device: {
		WiFi: {
			RadioNumberOfEntries: '1',
			Radio: {
				'1': { Enable: 'true', Channel: '11' }
			}
		}
	}
};

/* test transaction lifecycle without file I/O */
dm.trans_start();
dm.trans_abort();

/* test find_get_handler */
let handler = dm.find_get_handler('Device.WiFi');
assert_eq('find_get_handler: finds WiFi handler',
	handler?.pattern, 'Device.WiFi');
assert_eq('find_get_handler: handler is callable',
	type(handler?.handler), 'function');

let handler2 = dm.find_get_handler('Device.WiFi.Radio.1.Enable');
assert_eq('find_get_handler: finds Radio handler',
	handler2?.pattern, 'Device.WiFi.Radio.{i}');
assert_eq('find_get_handler: extracts instance',
	handler2?.instance, 1);
assert_eq('find_get_handler: remaining parts',
	handler2?.remaining, ['Enable']);

let handler3 = dm.find_get_handler('Device.Ethernet');
assert_null('find_get_handler: no match returns null', handler3);

/* test find_set_handler */
let set_handler = dm.find_set_handler('Device.WiFi.Radio.1.Enable');
assert_eq('find_set_handler: finds Radio set handler',
	set_handler?.pattern, 'Device.WiFi.Radio.{i}');
assert_eq('find_set_handler: extracts instance',
	set_handler?.instance, 1);

let set_handler2 = dm.find_set_handler('Device.WiFi.RadioNumberOfEntries');
assert_null('find_set_handler: no set handler on WiFi', set_handler2);

/* ---- dm.params_get / dm.params_set ------------------------------------ */

let dm2 = ubbf.create();
let model2 = {
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
};

dm2.register(model2);
dm2.load('/dev/null');

let init_config = {
	Device: {
		Test: {
			Name: 'mytest',
			ItemNumberOfEntries: '1',
			Item: {
				'1': { Enable: 'true', Value: 'hello', Alias: 'cpe-Item1' }
			}
		}
	}
};
dm2.set_config(init_config);
dm2.runtime_reload();

let get_paths = {
	'Device.Test.Name': null,
	'Device.Test.Item.1.Value': null,
	'Device.Test.Count': null
};
dm2.params_get(get_paths);
assert_eq('dm.params_get: handler result', get_paths['Device.Test.Name'], 'mytest');
assert_eq('dm.params_get: nested handler', get_paths['Device.Test.Item.1.Value'], 'computed');
assert_eq('dm.params_get: handler count', get_paths['Device.Test.Count'], '42');

/* params_get with schema default fallback */
let get_paths2 = { 'Device.Test.Item.1.Enable': null };
dm2.params_get(get_paths2);
assert_eq('dm.params_get: from handler', get_paths2['Device.Test.Item.1.Enable'], 'true');

/* params_set */
dm2.trans_start();
dm2.params_set({ 'Device.Test.Item.1.Value': 'updated' });
let cfg = dm2.config();
assert_eq('dm.params_set: value stored',
	cfg?.Device?.Test?.Item?.['1']?.Value, 'updated');
dm2.trans_abort();

/* ---- dm.object_add / dm.object_del ----------------------------------- */

dm2.trans_start();
let new_inst = dm2.object_add('Device.Test.Item');
assert_true('dm.object_add: returns instance > 0', new_inst > 0);

let cfg2 = dm2.config();
let new_obj = cfg2?.Device?.Test?.Item?.[sprintf('%d', new_inst)];
assert_eq('dm.object_add: created with defaults', new_obj?.Enable, 'false');
assert_eq('dm.object_add: alias generated with the cpe- prefix',
	new_obj?.Alias, sprintf('cpe-Item%d', new_inst));
assert_eq('dm.object_add: NumberOfEntries updated',
	cfg2?.Device?.Test?.ItemNumberOfEntries, '2');

dm2.object_del(sprintf('Device.Test.Item.%d', new_inst));
let cfg3 = dm2.config();
assert_null('dm.object_del: instance removed',
	cfg3?.Device?.Test?.Item?.[sprintf('%d', new_inst)]);
assert_eq('dm.object_del: NumberOfEntries updated',
	cfg3?.Device?.Test?.ItemNumberOfEntries, '1');
dm2.trans_abort();

/* ---- runtime table counts on the parent ------------------------------- */

/* Row.{i} is registered before its parent on purpose: the walk follows
 * registration order, so the parent's merge of the schema default "0"
 * lands after the rows were enumerated and would clobber any count set
 * earlier than the post-walk apply. */
let dm5 = ubbf.create();
let t_rows = [{ Name: 'a' }, { Name: 'b' }];
let sub_rows = [{ Id: '1' }, { Id: '2' }, { Id: '3' }];

function t_row_get(ctx) {
	if (ctx.instance == null)
		return ubbf.enumerate_instances(t_rows, (r) => r);
	return ubbf.get_by_instance(t_rows, ctx.instance);
}

function config_echo_get(ctx) {
	return { ...ubbf.ctx_config(ctx) };
}

let model5 = {
	'Device.T.Row.{i}': {
		schema: { schema: { Name: 1 }, defaults: { Name: '' } },
		get: t_row_get
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
		get: t_row_get
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
		get: function(ctx) {
			let rows = [{ Of: ctx.parent?.Tag ?? 'no parent' }];
			if (ctx.instance == null)
				return ubbf.enumerate_instances(rows, (r) => r);
			return ubbf.get_by_instance(rows, ctx.instance);
		}
	},
	'Device.V.Item.{i}.Sub.{i}': {
		schema: { schema: { Id: 1 }, defaults: { Id: '' } },
		get: function(ctx) {
			if (ctx.instance == null)
				return ubbf.enumerate_instances(sub_rows, (r) => r);
			return ubbf.get_by_instance(sub_rows, ctx.instance);
		}
	},
	/* W synthesises its own table, as WiFi.Radio does for
	 * X_UBBF_ChannelHistory; the table's handler enumerates nothing. */
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
};
dm5.register(model5);
dm5.load('/dev/null');
dm5.set_config({ Device: {
	V: { Item: { '1': { Enable: 'true' } } },
	P: { Item: { '1': { Tag: 'one' }, '2': { Tag: 'two' } } }
} });
dm5.runtime_reload();

let w_tree = dm5.get_subtree_with_state('Device.W');
assert_eq('runtime count: a table the parent synthesises keeps its rows',
	w_tree?.Hist?.['2']?.To, '1');
assert_eq('runtime count: and its count follows those rows',
	w_tree?.HistNumberOfEntries, '2');
let w_paths = { 'Device.W.HistNumberOfEntries': null };
dm5.params_get(w_paths);
assert_eq('runtime count: params_get agrees for the synthesised table',
	w_paths['Device.W.HistNumberOfEntries'], '2');

let t_tree = dm5.get_subtree_with_state('Device.T');
assert_eq('runtime count: parent carries the enumerated count',
	t_tree?.RowNumberOfEntries, '2');
assert_eq('runtime count: rows are present',
	t_tree?.Row?.['2']?.Name, 'b');
assert_eq('runtime count: visible from the root',
	dm5.get_subtree_with_state('Device')?.T?.RowNumberOfEntries, '2');
assert_null('runtime count: no stray key on the table itself',
	dm5.get_subtree_with_state('Device.T.Row')?.RowNumberOfEntries);
assert_null('runtime count: an undeclared key gets no count and no default',
	dm5.get_subtree_with_state('Device.U')?.RowNumberOfEntries);
assert_eq('undeclared key: a declared one stays',
	dm5.get_subtree_with_state('Device.U')?.Label, 'y');
assert_eq('runtime count: nested table under a persisted row',
	dm5.get_subtree_with_state('Device.V')?.Item?.['1']?.SubNumberOfEntries, '3');

let p_tree = dm5.get_subtree_with_state('Device.P');
assert_eq('nested table: the handler gets its row as the parent',
	[ p_tree?.Item?.['1']?.Sub?.['1']?.Of, p_tree?.Item?.['2']?.Sub?.['1']?.Of ], [ 'one', 'two' ]);
assert_eq('nested table: also below the row path',
	dm5.get_subtree_with_state('Device.P.Item.2')?.Sub?.['1']?.Of, 'two');

let count_paths = { 'Device.T.RowNumberOfEntries': null };
dm5.params_get(count_paths);
assert_eq('runtime count: params_get sees the count',
	count_paths['Device.T.RowNumberOfEntries'], '2');

/* ---- container handler registered after its descendants ---------------- */

/* Device is registered after the domains below it, and its handler returns
 * the stored config. A walk in registration order let that config replace
 * the runtime state the deeper handlers had merged. */
let dm6 = ubbf.create();
let model6 = {
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
};
dm6.register(model6);
dm6.load('/dev/null');
dm6.set_config({ Device: { S: { Item: { '1': { Enable: 'true' } } } } });
dm6.runtime_reload();

assert_eq('handler order: container query keeps the row state',
	dm6.get_subtree_with_state('Device.S')?.Item?.['1']?.Status, 'Up');
assert_eq('handler order: root query keeps the row state',
	dm6.get_subtree_with_state('Device')?.S?.Item?.['1']?.Status, 'Up');
assert_eq('handler order: root query keeps the stored value',
	dm6.get_subtree_with_state('Device')?.S?.Item?.['1']?.Enable, 'true');
assert_eq('handler order: root handler still contributes',
	dm6.get_subtree_with_state('Device')?.Label, 'd');

/* ---- alias-keyed path resolution -------------------------------------- */

/* The existing test_config seeded Item.1 with Alias='cpe-Item1'. */

dm2.trans_start();

let alias_get = { 'Device.Test.Item.cpe-Item1.Value': null };
dm2.params_get(alias_get);
assert_eq('params_get: resolves alias to instance',
	alias_get['Device.Test.Item.cpe-Item1.Value'], 'computed');

let bracket_get = { 'Device.Test.Item.[cpe-Item1].Value': null };
dm2.params_get(bracket_get);
assert_eq('params_get: resolves bracketed alias form',
	bracket_get['Device.Test.Item.[cpe-Item1].Value'], 'computed');

dm2.params_set({ 'Device.Test.Item.cpe-Item1.Value': 'alias-set' });
let cfg_a = dm2.config();
assert_eq('params_set: stores via alias path',
	cfg_a?.Device?.Test?.Item?.['1']?.Value, 'alias-set');

let alias_get_miss = { 'Device.Test.Item.NoSuchAlias.Value': null };
dm2.params_get(alias_get_miss);
assert_null('params_get: unknown alias returns null',
	alias_get_miss['Device.Test.Item.NoSuchAlias.Value']);

dm2.trans_abort();

/* ---- alias-keyed nested-table add (Firewall.Chain.Medium.Rule style) --- */

let dm3 = ubbf.create();
let model3 = {
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
};
dm3.register(model3);
dm3.load('/dev/null');

let fw_config = {
	Device: {
		Firewall: {
			Chain: {
				'3': { Enable: 'true', Alias: 'MediumAlias', Name: 'Medium' },
				'7': { Enable: 'true', Alias: 'IPV6MediumAlias', Name: 'IPV6_Medium' }
			}
		}
	}
};
dm3.set_config(fw_config);
dm3.runtime_reload();

dm3.trans_start();

let rule_inst = dm3.object_add('Device.Firewall.Chain.Medium.Rule');
assert_true('object_add: Chain.<Name>.Rule resolves via Name key',
	rule_inst > 0);

let fw_cfg = dm3.config();
let added_rule = fw_cfg?.Device?.Firewall?.Chain?.['3']?.Rule?.[sprintf('%d', rule_inst)];
assert_eq('object_add: rule landed under numeric instance 3',
	added_rule?.Target, 'Drop');

dm3.params_set({
	[sprintf('Device.Firewall.Chain.Medium.Rule.%d.Target', rule_inst)]: 'Accept'
});
let fw_cfg2 = dm3.config();
assert_eq('params_set: alias in mid-path resolves for rule Target',
	fw_cfg2?.Device?.Firewall?.Chain?.['3']?.Rule?.[sprintf('%d', rule_inst)]?.Target,
	'Accept');

dm3.params_set({
	'Device.Firewall.Chain.IPV6MediumAlias.Enable': 'false'
});
let fw_cfg3 = dm3.config();
assert_eq('params_set: Alias key resolves alongside Name',
	fw_cfg3?.Device?.Firewall?.Chain?.['7']?.Enable, 'false');

dm3.object_del(sprintf('Device.Firewall.Chain.Medium.Rule.%d', rule_inst));
let fw_cfg4 = dm3.config();
assert_null('object_del: removes rule via alias parent',
	fw_cfg4?.Device?.Firewall?.Chain?.['3']?.Rule?.[sprintf('%d', rule_inst)]);

dm3.trans_abort();

/* ---- named-instance-key preset (generator-style) --------------------- */

/* Boot-time preset stores instances under their name directly:
 * Chain: { Medium: {...}, IPV6_Medium: {...} }. The path validator must
 * accept non-numeric {i} segments when they already exist in the tree. */

let dm4 = ubbf.create();
let model4 = {
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
};
dm4.register(model4);
dm4.load('/dev/null');

let named_config = {
	Device: {
		Firewall: {
			Chain: {
				Medium: { Enable: 'true', Alias: 'MediumChain', Name: 'MEDIUM' },
				IPV6_Medium: { Enable: 'true', Alias: 'IPV6_MediumChain', Name: 'IPV6_MEDIUM' }
			}
		}
	}
};
dm4.set_config(named_config);
dm4.runtime_reload();

dm4.trans_start();

let nrule = dm4.object_add('Device.Firewall.Chain.Medium.Rule');
assert_true('object_add: named-key container accepts add', nrule > 0);

let named_cfg = dm4.config();
let named_rule = named_cfg?.Device?.Firewall?.Chain?.Medium?.Rule?.[sprintf('%d', nrule)];
assert_eq('object_add: rule lands under named-key container',
	named_rule?.Target, 'Drop');

dm4.params_set({
	[sprintf('Device.Firewall.Chain.Medium.Rule.%d.Target', nrule)]: 'Accept'
});
let named_cfg2 = dm4.config();
assert_eq('params_set: named-key mid-path set works',
	named_cfg2?.Device?.Firewall?.Chain?.Medium?.Rule?.[sprintf('%d', nrule)]?.Target,
	'Accept');

dm4.object_del(sprintf('Device.Firewall.Chain.Medium.Rule.%d', nrule));
let named_cfg3 = dm4.config();
assert_null('object_del: removes rule under named-key container',
	named_cfg3?.Device?.Firewall?.Chain?.Medium?.Rule?.[sprintf('%d', nrule)]);

dm4.trans_abort();

/* ---- dm.digest / dm.set_digest --------------------------------------- */

dm2.set_digest('abc123');
assert_eq('dm.digest: returns stored hash', dm2.digest(), 'abc123');

/* ---- ctx helpers ------------------------------------------------------ */

assert_eq('ctx_config: extracts config',
	ubbf.ctx_config({ config: { Name: 'test' } }),
	{ Name: 'test' });
assert_eq('ctx_config: null returns empty',
	ubbf.ctx_config(null), {});

/* ---- alias helpers ---------------------------------------------------- */

assert_eq('alias_from_mac: basic',
	ubbf.alias_from_mac('04:7C:16:5D:B5:2C'), 'cpe-047c165db52c');
assert_eq('alias_from_mac: null', ubbf.alias_from_mac(null), '');
assert_eq('alias_from_name: basic',
	ubbf.alias_from_name('eth0.1'), 'cpe-eth0_1');
assert_eq('alias_from_name: null', ubbf.alias_from_name(null), '');
assert_eq('alias_from_name: LED name',
	ubbf.alias_from_name('blue:wps'), 'cpe-blue_wps');
let long_alias = ubbf.alias_from_name(
	'mt7530-0:00:green:wan-with-a-name-that-is-much-longer-than-sixty-four-bytes');
assert_eq('alias_from_name: at most 64 bytes', length(long_alias), 64);
assert_eq('alias_from_name: cut keeps the prefix',
	substr(long_alias, 0, 17), 'cpe-mt7530-0_00_g');

/* ---- enumerate helpers ------------------------------------------------ */

let items = ['a', 'b', 'c'];
let enumerated = ubbf.enumerate_instances(items, (item, i) => ({ val: item }));
assert_eq('enumerate_instances: keys are 1-based',
	type(enumerated['1']), 'object');
assert_eq('enumerate_instances: converter called',
	enumerated['2']?.val, 'b');

assert_eq('get_by_instance: valid',
	ubbf.get_by_instance(['x', 'y', 'z'], 2), 'y');
assert_null('get_by_instance: out of range',
	ubbf.get_by_instance(['x'], 5));

/* ---- shell escape ----------------------------------------------------- */

assert_eq('shell_escape: simple', ubbf.shell_escape('hello'), "'hello'");
assert_eq('shell_escape: with quote',
	ubbf.shell_escape("it's"), "'it'\\''s'");
assert_eq('shell_escape: null', ubbf.shell_escape(null), "''");

/* ---- format / time ---------------------------------------------------- */

let ts = ubbf.iso8601_format(0);
assert_eq('iso8601_format: epoch', ts, '1970-01-01T00:00:00Z');

let ts_usec = ubbf.iso8601_format_usec(0, 123456);
assert_eq('iso8601_format_usec: epoch with usec',
	ts_usec, '1970-01-01T00:00:00.123456Z');

/* ---- readfile (test with /proc which exists on any linux) ------------ */

let uptime = ubbf.uptime_read();
assert_true('uptime_read: returns positive', uptime > 0);

let hostname = ubbf.readfile_trim('/proc/sys/kernel/hostname');
assert_true('readfile_trim: reads proc file', length(hostname) > 0);

assert_eq('readfile_trim: default on missing',
	ubbf.readfile_trim('/nonexistent', 'fallback'), 'fallback');

let pid_max = ubbf.readfile_int('/proc/sys/kernel/pid_max', 0);
assert_true('readfile_int: reads integer', pid_max > 0);

/* ---- operstate_to_status ---------------------------------------------- */

assert_eq('operstate_to_status: up', ubbf.operstate_to_status('up'), 'Up');
assert_eq('operstate_to_status: down', ubbf.operstate_to_status('down'), 'Down');
assert_eq('operstate_to_status: unknown', ubbf.operstate_to_status('bogus'), 'Error');

/* ---- host discovery --------------------------------------------------- */

let arp = ubbf.arp_parse();
assert_eq('arp_parse: returns array', type(arp), 'array');

assert_eq('mr_cache_parse: returns array', type(multicast_lib.mr_cache_parse()), 'array');

let fdb = ubbf.bridge_fdb_parse();
assert_eq('bridge_fdb_parse: returns object', type(fdb), 'object');

let ndp = ubbf.ipv6_neigh_parse();
assert_eq('ipv6_neigh_parse: returns object', type(ndp), 'object');

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
assert_eq('hosts_merge: returns array', type(merged), 'array');
assert_eq('hosts_merge: two hosts in fdb', length(merged), 2);

let h1 = filter(merged, h => h.mac == 'AA:BB:CC:DD:EE:01')[0];
assert_eq('hosts_merge: hostname from lease', h1?.hostname, 'laptop');
assert_eq('hosts_merge: ipv4 address', h1?.ipv4_addresses?.[0], '192.168.1.10');
assert_eq('hosts_merge: ipv6 from ndp', h1?.ipv6_addresses?.[0], 'fe80::1');
assert_eq('hosts_merge: address_source DHCP', h1?.address_source, 'DHCP');

let h2 = filter(merged, h => h.mac == 'AA:BB:CC:DD:EE:02')[0];
assert_eq('hosts_merge: static host', h2?.address_source, 'Static');

let merged6 = ubbf.hosts_merge([], {}, {
	'AA:BB:CC:DD:EE:03': ['2001:db8::3'],
	'AA:BB:CC:DD:EE:04': ['2001:db8::4']
}, { 'AA:BB:CC:DD:EE:03': 'eth0' });
assert_eq('hosts_merge: ipv6-only host in fdb listed', length(merged6), 1);
assert_eq('hosts_merge: ipv6-only host address', merged6[0]?.ipv6_addresses?.[0], '2001:db8::3');
assert_eq('hosts_merge: ipv6-only host active', merged6[0]?.active, true);

let merged_nb = ubbf.hosts_merge([
	{ ip: '10.9.0.2', mac: 'AA:BB:CC:DD:EE:05', device: 'ubbf-test-nobridge0', active: true }
], {}, {}, {});
assert_eq('hosts_merge: arp host on a non-bridge device listed', length(merged_nb), 1);

assert_eq('host_primary_ip: returns ipv4',
	ubbf.host_primary_ip({ ipv4_addresses: ['10.0.0.1'], ipv6_addresses: [] }), '10.0.0.1');
assert_eq('host_primary_ip: falls back to ipv6',
	ubbf.host_primary_ip({ ipv4_addresses: [], ipv6_addresses: ['fe80::1'] }), 'fe80::1');
assert_eq('host_primary_ip: empty',
	ubbf.host_primary_ip({ ipv4_addresses: [], ipv6_addresses: [] }), '');

let l3_config = {
	Device: {
		IP: {
			Interface: {
				'1': { Name: 'lan', Upstream: 'false' },
				'2': { Name: 'wan', Upstream: 'true' }
			}
		}
	}
};
let l3_netifd = [
	{ name: 'lan', addresses: [{ ip: '192.168.1.1', mask: 24 }], ipv6_addresses: [] },
	{ name: 'wan', addresses: [{ ip: '10.0.0.1', mask: 8 }], ipv6_addresses: [] }
];

let l3 = ubbf.layer3_interface_find(l3_config, '192.168.1.50', l3_netifd);
assert_eq('layer3_interface_find: matches lan', l3?.path, 'Device.IP.Interface.1');
assert_false('layer3_interface_find: lan not upstream', l3?.upstream);

let l3_wan = ubbf.layer3_interface_find(l3_config, '10.1.2.3', l3_netifd);
assert_eq('layer3_interface_find: matches wan', l3_wan?.path, 'Device.IP.Interface.2');
assert_true('layer3_interface_find: wan is upstream', l3_wan?.upstream);

let l3_miss = ubbf.layer3_interface_find(l3_config, '172.16.0.1', l3_netifd);
assert_eq('layer3_interface_find: no match', l3_miss?.path, '');

/* ---- string.c: name_sanitise / uci_value_sanitise / transfer_url_validate */

assert_eq('name_sanitise: passthrough',
	ubbf.name_sanitise('abc_123'), 'abc_123');
assert_eq('name_sanitise: rewrites specials',
	ubbf.name_sanitise('wlan0.1 :-('), 'wlan0_1____');
assert_null('name_sanitise: non-string', ubbf.name_sanitise(42));

assert_eq('uci_value_sanitise: passthrough',
	ubbf.uci_value_sanitise('hello'), 'hello');
assert_eq('uci_value_sanitise: strips control bytes',
	ubbf.uci_value_sanitise('a\nb\tc\x7fd'), 'abcd');
assert_eq('uci_value_sanitise: non-string passthrough',
	ubbf.uci_value_sanitise(42), 42);

assert_true('transfer_url_validate: http',
	ubbf.transfer_url_validate('http://example.com/file'));
assert_true('transfer_url_validate: https',
	ubbf.transfer_url_validate('https://example.com/file'));
assert_true('transfer_url_validate: ftp',
	ubbf.transfer_url_validate('ftp://example.com'));
assert_true('transfer_url_validate: ftps',
	ubbf.transfer_url_validate('ftps://example.com'));
assert_false('transfer_url_validate: no scheme',
	ubbf.transfer_url_validate('example.com'));
assert_false('transfer_url_validate: file scheme',
	ubbf.transfer_url_validate('file:///etc/passwd'));
assert_false('transfer_url_validate: non-string',
	ubbf.transfer_url_validate(null));

/* ---- path.c: tr181_ref_parse ----------------------------------------- */

assert_eq('tr181_ref_parse: basic',
	ubbf.tr181_ref_parse('Device.IP.Interface.3', 'Device.IP.Interface'), 3);
assert_eq('tr181_ref_parse: trailing dot',
	ubbf.tr181_ref_parse('Device.IP.Interface.3.', 'Device.IP.Interface'), 3);
assert_null('tr181_ref_parse: missing index',
	ubbf.tr181_ref_parse('Device.IP.Interface', 'Device.IP.Interface'));
assert_null('tr181_ref_parse: prefix mismatch',
	ubbf.tr181_ref_parse('Device.WiFi.Radio.1', 'Device.IP.Interface'));
assert_null('tr181_ref_parse: zero instance',
	ubbf.tr181_ref_parse('Device.IP.Interface.0', 'Device.IP.Interface'));
assert_null('tr181_ref_parse: non-numeric',
	ubbf.tr181_ref_parse('Device.IP.Interface.abc', 'Device.IP.Interface'));
assert_null('tr181_ref_parse: non-string',
	ubbf.tr181_ref_parse(null, 'Device.IP.Interface'));

/* ---- mac.c: mac_is_valid / mac_normalise / mac_from_duid ------------- */

assert_true('mac_is_valid: lowercase',
	ubbf.mac_is_valid('aa:bb:cc:dd:ee:ff'));
assert_true('mac_is_valid: uppercase',
	ubbf.mac_is_valid('AA:BB:CC:DD:EE:FF'));
assert_false('mac_is_valid: too short', ubbf.mac_is_valid('aa:bb:cc'));
assert_false('mac_is_valid: missing colons',
	ubbf.mac_is_valid('aabbccddeeff'));
assert_false('mac_is_valid: non-hex',
	ubbf.mac_is_valid('gg:bb:cc:dd:ee:ff'));
assert_false('mac_is_valid: wrong separator',
	ubbf.mac_is_valid('aa-bb-cc-dd-ee-ff'));
assert_false('mac_is_valid: non-string', ubbf.mac_is_valid(42));
assert_false('mac_is_valid: trailing text',
	ubbf.mac_is_valid('aa:bb:cc:dd:ee:f0x'));
assert_false('mac_is_valid: embedded NUL',
	ubbf.mac_is_valid('aa:bb:cc:dd:ee:\x00f'));

assert_eq('mac_normalise: uppercases',
	ubbf.mac_normalise('aa:bb:cc'), 'AA:BB:CC');
assert_eq('mac_normalise: strips given separators',
	ubbf.mac_normalise('aa-bb-cc-dd', '-'), 'AABBCCDD');
assert_eq('mac_normalise: strips multiple separators',
	ubbf.mac_normalise('aa:bb-cc:dd', ':-'), 'AABBCCDD');
assert_null('mac_normalise: non-string', ubbf.mac_normalise(null));

assert_eq('mac_from_duid: DUID-LL',
	ubbf.mac_from_duid('00030001aabbccddeeff'), 'AA:BB:CC:DD:EE:FF');
assert_eq('mac_from_duid: DUID-LLT',
	ubbf.mac_from_duid('00010001deadbeef3418d1f12e4a'), '34:18:D1:F1:2E:4A');
assert_null('mac_from_duid: unsupported type',
	ubbf.mac_from_duid('00020001aabbccddeeff'));
assert_null('mac_from_duid: wrong hw type',
	ubbf.mac_from_duid('00030002aabbccddeeff'));
assert_null('mac_from_duid: too short',
	ubbf.mac_from_duid('0003'));
assert_null('mac_from_duid: non-string',
	ubbf.mac_from_duid(null));

/* ---- firewall.c: port_range_format / protocol_to_uci ----------------- */

assert_eq('port_range_format: single port',
	ubbf.port_range_format(80, 0), '80');
assert_eq('port_range_format: range',
	ubbf.port_range_format(1000, 2000), '1000-2000');
assert_eq('port_range_format: pe<=p collapses',
	ubbf.port_range_format(80, 80), '80');
assert_eq('port_range_format: string ports',
	ubbf.port_range_format('443', '445'), '443-445');
assert_null('port_range_format: p<=0',
	ubbf.port_range_format(0, 100));
assert_null('port_range_format: non-numeric',
	ubbf.port_range_format('abc', 100));

assert_eq('protocol_to_uci: numeric tcp',
	ubbf.protocol_to_uci(6), 'tcp');
assert_eq('protocol_to_uci: numeric udp',
	ubbf.protocol_to_uci(17), 'udp');
assert_eq('protocol_to_uci: numeric icmp',
	ubbf.protocol_to_uci(1), 'icmp');
assert_eq('protocol_to_uci: numeric icmpv6',
	ubbf.protocol_to_uci(58), 'icmpv6');
assert_eq('protocol_to_uci: -1 is all',
	ubbf.protocol_to_uci(-1), 'all');
assert_eq('protocol_to_uci: other positive number',
	ubbf.protocol_to_uci(47), '47');
assert_eq('protocol_to_uci: string TCP lowercase',
	ubbf.protocol_to_uci('TCP'), 'tcp');
assert_eq('protocol_to_uci: string numeric',
	ubbf.protocol_to_uci('6'), 'tcp');
assert_null('protocol_to_uci: unknown string',
	ubbf.protocol_to_uci('bogus'));

/* ---- wifi.c: freq / antenna / htmode / txpower / operating_standard -- */

assert_eq('freq_to_channel: 2.4 GHz ch1',
	ubbf.freq_to_channel(2412), 1);
assert_eq('freq_to_channel: 2.4 GHz ch6',
	ubbf.freq_to_channel(2437), 6);
assert_eq('freq_to_channel: 2.4 GHz ch14',
	ubbf.freq_to_channel(2484), 14);
assert_eq('freq_to_channel: 5 GHz ch36',
	ubbf.freq_to_channel(5180), 36);
assert_eq('freq_to_channel: 6 GHz',
	ubbf.freq_to_channel(5955), 1);
assert_eq('freq_to_channel: string',
	ubbf.freq_to_channel('2412'), 1);
assert_eq('freq_to_channel: out of range',
	ubbf.freq_to_channel(1000), 0);
assert_eq('freq_to_channel: non-numeric',
	ubbf.freq_to_channel('abc'), 0);

assert_eq('antenna_count: zero mask -> 1',
	ubbf.antenna_count(0), 1);
assert_eq('antenna_count: 0b0001 -> 1',
	ubbf.antenna_count(1), 1);
assert_eq('antenna_count: 0b0011 -> 2',
	ubbf.antenna_count(3), 2);
assert_eq('antenna_count: 0b1111 -> 4',
	ubbf.antenna_count(15), 4);
assert_eq('antenna_count: non-integer -> 1',
	ubbf.antenna_count('abc'), 1);

assert_null('txpower_pct_to_dbm: 0%',
	ubbf.txpower_pct_to_dbm(0, 20));
assert_null('txpower_pct_to_dbm: 100%',
	ubbf.txpower_pct_to_dbm(100, 20));
assert_null('txpower_pct_to_dbm: zero cap',
	ubbf.txpower_pct_to_dbm(50, 0));
assert_null('txpower_pct_to_dbm: non-integer',
	ubbf.txpower_pct_to_dbm('50', 20));
let tp = ubbf.txpower_pct_to_dbm(50, 30);
assert_true('txpower_pct_to_dbm: mid-range reasonable',
	tp >= 25 && tp <= 29);
assert_eq('txpower_pct_to_dbm: 1% of a 29 dBm cap',
	ubbf.txpower_pct_to_dbm(1, 29), 9);
assert_eq('txpower_pct_to_dbm: reduction below the cap clamps to the floor',
	ubbf.txpower_pct_to_dbm(1, 12), 1);
assert_null('txpower_pct_to_dbm: cap at the floor',
	ubbf.txpower_pct_to_dbm(1, 1));

assert_eq('wifi_operating_standard: EHT',
	ubbf.wifi_operating_standard(['EHT-MCS0', '320MHz']), 'be');
assert_eq('wifi_operating_standard: HE',
	ubbf.wifi_operating_standard(['HE-MCS0']), 'ax');
assert_eq('wifi_operating_standard: VHT',
	ubbf.wifi_operating_standard(['VHT-MCS0']), 'ac');
assert_eq('wifi_operating_standard: MCS',
	ubbf.wifi_operating_standard(['MCS7']), 'n');
assert_eq('wifi_operating_standard: empty array',
	ubbf.wifi_operating_standard([]), '');
assert_eq('wifi_operating_standard: unknown flag',
	ubbf.wifi_operating_standard(['Foo']), '');
assert_eq('wifi_operating_standard: non-array',
	ubbf.wifi_operating_standard(null), '');

/* ---- inet.c: ipv6_lifetime_status / addr+prefix builders ------------- */

assert_eq('ipv6_lifetime_status: preferred',
	ubbf.ipv6_lifetime_status({ preferred: 3600, valid: 7200 }), 'Preferred');
assert_eq('ipv6_lifetime_status: deprecated',
	ubbf.ipv6_lifetime_status({ preferred: 0, valid: 7200 }), 'Deprecated');
assert_eq('ipv6_lifetime_status: invalid',
	ubbf.ipv6_lifetime_status({ preferred: 3600, valid: 0 }), 'Invalid');
assert_eq('ipv6_lifetime_status: non-object',
	ubbf.ipv6_lifetime_status(null), 'Invalid');

let v4 = ubbf.ipv4_addr_to_object({ address: '192.168.1.1', mask: 24 });
assert_eq('ipv4_addr_to_object: IPAddress',
	v4?.IPAddress, '192.168.1.1');
assert_eq('ipv4_addr_to_object: SubnetMask',
	v4?.SubnetMask, '255.255.255.0');
assert_eq('ipv4_addr_to_object: default AddressingType',
	v4?.AddressingType, 'DHCP');
let v4s = ubbf.ipv4_addr_to_object({ address: '10.0.0.1', mask: 8 }, 'Static');
assert_eq('ipv4_addr_to_object: explicit AddressingType',
	v4s?.AddressingType, 'Static');
assert_eq('ipv4_addr_to_object: mask 0',
	ubbf.ipv4_addr_to_object({ address: '0.0.0.0', mask: 0 })?.SubnetMask, '0.0.0.0');
assert_eq('ipv4_addr_to_object: non-object',
	ubbf.ipv4_addr_to_object(null), {});

let v6 = ubbf.ipv6_addr_to_object(
	{ address: '2001:db8::1', preferred: 3600, valid: 7200 });
assert_eq('ipv6_addr_to_object: IPAddress',
	v6?.IPAddress, '2001:db8::1');
assert_eq('ipv6_addr_to_object: preferred status',
	v6?.IPAddressStatus, 'Preferred');
// lifetimes are TR-181 dateTime (absolute expiry), not raw seconds
assert_true('ipv6_addr_to_object: PreferredLifetime is ISO8601',
	match(v6?.PreferredLifetime, /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/) != null);
assert_true('ipv6_addr_to_object: ValidLifetime is ISO8601',
	match(v6?.ValidLifetime, /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/) != null);
assert_eq('ipv6_addr_to_object: default Origin',
	v6?.Origin, 'DHCPv6');
let v6s = ubbf.ipv6_addr_to_object(
	{ address: '::1', preferred: 0, valid: 0 }, 'Static');
assert_eq('ipv6_addr_to_object: invalid status',
	v6s?.IPAddressStatus, 'Invalid');
assert_eq('ipv6_addr_to_object: override Origin',
	v6s?.Origin, 'Static');
assert_eq('ipv6_addr_to_object: non-object',
	ubbf.ipv6_addr_to_object(null), {});

let v6f = ubbf.ipv6_addr_to_object(
	{ address: 'fe80::1' }, 'AutoConfigured', true);
assert_eq('ipv6_addr_to_object: forever Status',
	v6f?.IPAddressStatus, 'Preferred');
assert_eq('ipv6_addr_to_object: forever PreferredLifetime',
	v6f?.PreferredLifetime, '9999-12-31T23:59:59Z');
assert_eq('ipv6_addr_to_object: forever ValidLifetime',
	v6f?.ValidLifetime, '9999-12-31T23:59:59Z');
assert_eq('ipv6_addr_to_object: forever Origin',
	v6f?.Origin, 'AutoConfigured');
assert_eq('ipv6_addr_to_object: forever IPAddress',
	v6f?.IPAddress, 'fe80::1');

/* netifd leaves out an infinite lifetime and wraps an expired valid one;
 * 0xffffffff is infinite (RFC 4861) */
const FOREVER = '9999-12-31T23:59:59Z';
assert_eq('ipv6_lifetime_status: no lifetimes is infinite',
	ubbf.ipv6_lifetime_status({}), 'Preferred');
assert_eq('ipv6_lifetime_status: wrapped valid is expired',
	ubbf.ipv6_lifetime_status({ preferred: 0, valid: 4294967290 }), 'Invalid');

let v6inf = ubbf.ipv6_addr_to_object({ address: '2001:db8::2' });
assert_eq('ipv6_addr_to_object: no lifetimes',
	[ v6inf?.IPAddressStatus, v6inf?.PreferredLifetime, v6inf?.ValidLifetime ],
	[ 'Preferred', FOREVER, FOREVER ]);

let v6x = ubbf.ipv6_addr_to_object({ address: '2001:db8::3', preferred: 4294967295, valid: 4294967295 });
assert_eq('ipv6_addr_to_object: 0xffffffff is infinite',
	[ v6x?.IPAddressStatus, v6x?.ValidLifetime ], [ 'Preferred', FOREVER ]);

let v6dep = ubbf.ipv6_addr_to_object({ address: '2001:db8::4', preferred: 0, valid: 600 });
assert_eq('ipv6_addr_to_object: preferred run out',
	v6dep?.IPAddressStatus, 'Deprecated');
assert_true('ipv6_addr_to_object: a run out lifetime is a time, not infinite',
	v6dep?.PreferredLifetime != FOREVER &&
	match(v6dep?.PreferredLifetime, /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/) != null);

let v6p = ubbf.ipv6_prefix_to_object(
	{ address: '2001:db8::', mask: 32, preferred: 3600, valid: 7200 });
assert_eq('ipv6_prefix_to_object: Prefix',
	v6p?.Prefix, '2001:db8::/32');
assert_eq('ipv6_prefix_to_object: PrefixStatus',
	v6p?.PrefixStatus, 'Preferred');
assert_eq('ipv6_prefix_to_object: default Origin',
	v6p?.Origin, 'PrefixDelegation');
assert_eq('ipv6_prefix_to_object: override Origin',
	ubbf.ipv6_prefix_to_object(
		{ address: '2001:db8::', mask: 64, preferred: 100, valid: 200 },
		'Static')?.Origin, 'Static');
assert_eq('ipv6_prefix_to_object: non-object',
	ubbf.ipv6_prefix_to_object(null), {});

/* ---- wde.c: mac_to_base64 / int_to_hexbin / dscp_map / bss_index ----- */

assert_eq('mac_to_base64: all zero',
	wde_lib.mac_to_base64('00:00:00:00:00:00'), 'AAAAAAAA');
assert_eq('mac_to_base64: all ones',
	wde_lib.mac_to_base64('ff:ff:ff:ff:ff:ff'), '////////');
assert_eq('mac_to_base64: length is 8',
	length(wde_lib.mac_to_base64('aa:bb:cc:dd:ee:ff')), 8);
assert_eq('mac_to_base64: missing colon',
	wde_lib.mac_to_base64('aabbccddeeff'), '');
assert_eq('mac_to_base64: non-hex',
	wde_lib.mac_to_base64('gg:bb:cc:dd:ee:ff'), '');
assert_eq('mac_to_base64: null', wde_lib.mac_to_base64(null), '');
assert_eq('mac_to_base64: trailing text',
	wde_lib.mac_to_base64('aa:bb:cc:dd:ee:ff:00'), '');
assert_eq('mac_to_base64: mixed case',
	wde_lib.mac_to_base64('aA:Bb:cc:dd:ee:ff'), wde_lib.mac_to_base64('aa:bb:cc:dd:ee:ff'));

assert_eq('int_to_hexbin: 255 as 2 bytes',
	wde_lib.int_to_hexbin(255, 2), '00ff');
assert_eq('int_to_hexbin: zero',
	wde_lib.int_to_hexbin(0, 4), '00000000');
assert_eq('int_to_hexbin: full-width value',
	wde_lib.int_to_hexbin(0xdeadbeef, 4), 'deadbeef');
assert_eq('int_to_hexbin: bytes=0 rejected',
	wde_lib.int_to_hexbin(5, 0), '');
assert_eq('int_to_hexbin: bytes>16 rejected',
	wde_lib.int_to_hexbin(5, 17), '');
assert_eq('int_to_hexbin: non-int',
	wde_lib.int_to_hexbin('5', 2), '');

assert_eq('dscp_map_to_hex: basic',
	wde_lib.dscp_map_to_hex([15, 255, 0]), '0fff00');
assert_eq('dscp_map_to_hex: masks to 8 bits',
	wde_lib.dscp_map_to_hex([256, 257]), '0001');
assert_eq('dscp_map_to_hex: empty',
	wde_lib.dscp_map_to_hex([]), '');
assert_eq('dscp_map_to_hex: non-array',
	wde_lib.dscp_map_to_hex(null), '');

let bss_entries = [
	{ bssid: 'AA:BB:CC:DD:EE:01', name: 'radio1' },
	{ bssid: 'AA:BB:CC:DD:EE:02', name: 'radio2' }
];
let bss_idx = wde_lib.bss_index_by_bssid(bss_entries);
assert_eq('bss_index_by_bssid: entry found',
	bss_idx['AA:BB:CC:DD:EE:01']?.name, 'radio1');
assert_eq('bss_index_by_bssid: other entry',
	bss_idx['AA:BB:CC:DD:EE:02']?.name, 'radio2');

let nested = [
	{ radio: 'r1', bss: [
		{ bssid: 'AA:BB:CC:00:00:01', ssid: 'net1' },
		{ bssid: 'AA:BB:CC:00:00:02', ssid: 'net2' }
	] }
];
let bss_idx2 = wde_lib.bss_index_by_bssid(nested, 'bss');
assert_eq('bss_index_by_bssid: nested finds inner',
	bss_idx2['AA:BB:CC:00:00:01']?.ssid, 'net1');
assert_eq('bss_index_by_bssid: nested second inner',
	bss_idx2['AA:BB:CC:00:00:02']?.ssid, 'net2');

assert_eq('bss_index_by_bssid: non-array',
	wde_lib.bss_index_by_bssid(null), {});

/* ---- diag.c: curl / ping / traceroute -------------------------------- */

let curl_out = ubbf.curl_w_metrics_parse(
	"time_connect:0.123\ntime_total:0.456\n");
assert_eq('curl_w_metrics_parse: time_connect',
	curl_out?.time_connect, '0.123');
assert_eq('curl_w_metrics_parse: time_total',
	curl_out?.time_total, '0.456');
assert_eq('curl_w_metrics_parse: skips colonless line',
	length(keys(ubbf.curl_w_metrics_parse("one\ntwo:three\n"))), 1);
assert_eq('curl_w_metrics_parse: skips leading colon',
	length(keys(ubbf.curl_w_metrics_parse(":value\nkey:x\n"))), 1);
assert_eq('curl_w_metrics_parse: non-string',
	ubbf.curl_w_metrics_parse(null), {});

let ping_in = "PING 8.8.8.8 (8.8.8.8) 56(84) bytes of data.\n" +
	"3 packets transmitted, 3 received, 0% packet loss\n" +
	"rtt min/avg/max/mdev = 10.500/15.200/20.100/0.000 ms\n";
let ping_out = ubbf.ping_output_parse(ping_in, 3);
assert_eq('ping_output_parse: Status',
	ping_out?.Status, 'Complete');
assert_eq('ping_output_parse: IPAddressUsed',
	ping_out?.IPAddressUsed, '8.8.8.8');
assert_eq('ping_output_parse: SuccessCount',
	ping_out?.SuccessCount, '3');
assert_eq('ping_output_parse: FailureCount',
	ping_out?.FailureCount, '0');
assert_eq('ping_output_parse: MinimumResponseTime',
	ping_out?.MinimumResponseTime, '10');
assert_eq('ping_output_parse: AverageResponseTime',
	ping_out?.AverageResponseTime, '15');
assert_eq('ping_output_parse: MaximumResponseTime',
	ping_out?.MaximumResponseTime, '20');
assert_eq('ping_output_parse: MinimumResponseTimeDetailed',
	ping_out?.MinimumResponseTimeDetailed, '10500');
assert_eq('ping_output_parse: no data',
	ubbf.ping_output_parse("", 0)?.Status, 'Error_Other');
assert_eq('ping_output_parse: non-string',
	ubbf.ping_output_parse(null, 3)?.Status, 'Error_Other');
assert_eq('ping_output_parse: non-string FailureCount from count',
	ubbf.ping_output_parse(null, 3)?.FailureCount, '3');

let ping_busybox = "PING 172.16.100.1 (172.16.100.1): 56 data bytes\n" +
	"3 packets transmitted, 3 packets received, 0% packet loss\n" +
	"round-trip min/avg/max = 0.500/1.200/2.100 ms\n";
let ping_busybox_out = ubbf.ping_output_parse(ping_busybox, 3);
assert_eq('ping_output_parse: busybox Status',
	ping_busybox_out?.Status, 'Complete');
assert_eq('ping_output_parse: busybox SuccessCount',
	ping_busybox_out?.SuccessCount, '3');
assert_eq('ping_output_parse: busybox FailureCount',
	ping_busybox_out?.FailureCount, '0');
assert_eq('ping_output_parse: busybox AverageResponseTime',
	ping_busybox_out?.AverageResponseTime, '1');

let tr_in = "traceroute to example.com (93.184.216.34), 30 hops max, 60 byte packets\n" +
	" 1  router.local (192.168.1.1)  1.234 ms\n" +
	" 2  isp-gw (203.0.113.1)  15.567 ms\n" +
	" 3  * * *\n";
let tr_out = ubbf.traceroute_output_parse(tr_in);
assert_eq('traceroute_output_parse: Status',
	tr_out?.Status, 'Complete');
assert_eq('traceroute_output_parse: IPAddressUsed',
	tr_out?.IPAddressUsed, '93.184.216.34');
assert_eq('traceroute_output_parse: hop 1 Host',
	tr_out?.['RouteHops.1.Host'], 'router.local');
assert_eq('traceroute_output_parse: hop 1 HostAddress',
	tr_out?.['RouteHops.1.HostAddress'], '192.168.1.1');
assert_eq('traceroute_output_parse: hop 1 ErrorCode',
	tr_out?.['RouteHops.1.ErrorCode'], '0');
assert_eq('traceroute_output_parse: hop 2 Host',
	tr_out?.['RouteHops.2.Host'], 'isp-gw');
assert_eq('traceroute_output_parse: hop 3 timeout ErrorCode',
	tr_out?.['RouteHops.3.ErrorCode'], '1');
assert_eq('traceroute_output_parse: non-string',
	ubbf.traceroute_output_parse(null)?.Status, 'Error_Other');

/* ---- sysfs.c: interface helpers (shape only) ------------------------ */

let link_lo = ubbf.link_properties_get('lo');
assert_eq('link_properties_get: MTU present',
	type(link_lo?.MTU), 'string');
assert_eq('link_properties_get: has MACAddress',
	type(link_lo?.MACAddress), 'string');
assert_eq('link_properties_get: non-string',
	ubbf.link_properties_get(null), {});

let eth_lo = ubbf.ethernet_properties_get('lo');
assert_eq('ethernet_properties_get: Enable',
	eth_lo?.Enable, 'true');
assert_eq('ethernet_properties_get: MACAddress present',
	type(eth_lo?.MACAddress), 'string');
assert_eq('ethernet_properties_get: non-string',
	ubbf.ethernet_properties_get(null), {});

/* ---- atomic.c: tmpfile_name / write_file_atomic / counter_bump ------ */

let tmpname = ubbf.tmpfile_name('ubbf_test', '.tmp');
assert_eq('tmpfile_name: under /tmp',
	substr(tmpname, 0, 5), '/tmp/');
assert_eq('tmpfile_name: extension preserved',
	substr(tmpname, length(tmpname) - 4, 4), '.tmp');
assert_null('tmpfile_name: non-string prefix',
	ubbf.tmpfile_name(42));
ubbf.write_file_atomic(tmpname, '');

let atomic_path = sprintf('/tmp/ubbf_unittest_%d.txt', time());
assert_true('write_file_atomic: success',
	ubbf.write_file_atomic(atomic_path, 'hello\n'));
assert_eq('write_file_atomic: content readable',
	ubbf.readfile_trim(atomic_path, ''), 'hello');
assert_true('write_file_atomic: delete on empty content',
	ubbf.write_file_atomic(atomic_path, ''));
assert_eq('write_file_atomic: file gone',
	ubbf.readfile_trim(atomic_path, 'missing'), 'missing');
assert_false('write_file_atomic: non-string path',
	ubbf.write_file_atomic(null, 'x'));

let fs_mod = require('fs');
assert_true('write_file_atomic: default mode',
	ubbf.write_file_atomic(atomic_path, 'x') && (fs_mod.stat(atomic_path).mode & 0777) == 0644);
fs_mod.writefile(atomic_path + '.tmp', 'stale');
fs_mod.chmod(atomic_path + '.tmp', 0666);
assert_true('write_file_atomic: mode 0600 over a stale temp file',
	ubbf.write_file_atomic(atomic_path, 'secret', 0600) && (fs_mod.stat(atomic_path).mode & 0777) == 0600);
ubbf.write_file_atomic(atomic_path, '');

let counter_path = sprintf('/tmp/ubbf_unittest_counter_%d', time());
assert_eq('counter_bump: first call returns 0',
	ubbf.counter_bump(counter_path), 0);
assert_eq('counter_bump: second call returns 1',
	ubbf.counter_bump(counter_path), 1);
assert_eq('counter_bump: third call returns 2',
	ubbf.counter_bump(counter_path), 2);
assert_null('counter_bump: non-string path',
	ubbf.counter_bump(42));
ubbf.write_file_atomic(counter_path, '');

/* ---- rate_limit.c: rate_limit_check --------------------------------- */

let rl_key = sprintf('ubbf_rl_test_%d', time());
assert_true('rate_limit_check: first call within window',
	users_lib.rate_limit_check(rl_key, 3, 60));
assert_true('rate_limit_check: second',
	users_lib.rate_limit_check(rl_key, 3, 60));
assert_true('rate_limit_check: third',
	users_lib.rate_limit_check(rl_key, 3, 60));
assert_false('rate_limit_check: fourth blocked',
	users_lib.rate_limit_check(rl_key, 3, 60));
assert_false('rate_limit_check: non-string key',
	users_lib.rate_limit_check(null, 3, 60));

/* ---- wol.c: wol_send ------------------------------------------------- */

assert_null('wol_send: non-string iface',
	wol_lib.send(null, 'aa:bb:cc:dd:ee:ff'));
assert_null('wol_send: non-string mac',
	wol_lib.send('lo', null));
assert_null('wol_send: invalid mac',
	wol_lib.send('lo', 'zz:bb:cc:dd:ee:ff'));
assert_null('wol_send: mac with dashes',
	wol_lib.send('lo', 'aa-bb-cc-dd-ee-ff'));
assert_null('wol_send: mac with trailing text',
	wol_lib.send('lo', 'aa:bb:cc:dd:ee:ff0'));
assert_null('wol_send: mac with 0x prefix',
	wol_lib.send('lo', '0xa:bb:cc:dd:ee:ff'));
assert_null('wol_send: invalid password',
	wol_lib.send('lo', 'aa:bb:cc:dd:ee:ff', 'ZZ'));
assert_null('wol_send: password with trailing separator',
	wol_lib.send('lo', 'aa:bb:cc:dd:ee:ff', 'aa:bb:cc:dd:'));
assert_null('wol_send: password with mixed separators',
	wol_lib.send('lo', 'aa:bb:cc:dd:ee:ff', 'aa:bb-cc:dd'));
assert_null('wol_send: password with separator in bare hex',
	wol_lib.send('lo', 'aa:bb:cc:dd:ee:ff', 'aabb:ccdd'));
assert_null('wol_send: password of 3 bytes',
	wol_lib.send('lo', 'aa:bb:cc:dd:ee:ff', 'aa:bb:cc'));
assert_null('wol_send: password of 5 bytes',
	wol_lib.send('lo', 'aa:bb:cc:dd:ee:ff', 'aabbccddee'));
assert_null('wol_send: dotted-decimal password',
	wol_lib.send('lo', 'aa:bb:cc:dd:ee:ff', '192.168.1.5'));
/* actual send may or may not succeed depending on privilege; type only */
assert_eq('wol_send: valid args return bool',
	type(wol_lib.send('nonexistent_iface', 'aa:bb:cc:dd:ee:ff')), 'bool');
for (let pw in ['aabbccdd', 'aabbccddeeff', 'aa:bb:cc:dd', 'aa-bb-cc-dd-ee-ff'])
	assert_eq(`wol_send: password ${pw} accepted`,
		type(wol_lib.send('nonexistent_iface', 'aa:bb:cc:dd:ee:ff', pw)), 'bool');

/* ---- sys.c: arch_get / apk_installed / statvfs_info / du_kib -------- */

assert_eq('arch_get: returns string',
	type(ubbf.arch_get()), 'string');
assert_true('arch_get: non-empty',
	length(ubbf.arch_get()) > 0);

assert_false('apk_installed: non-string',
	ubbf.apk_installed(null));
assert_false('apk_installed: empty',
	ubbf.apk_installed(''));
assert_eq('apk_installed: returns bool',
	type(ubbf.apk_installed('some-package-name')), 'bool');

assert_eq('apk_version: non-string',
	ubbf.apk_version(null), null);
assert_eq('apk_version: empty',
	ubbf.apk_version(''), null);
assert_eq('apk_version: absent package',
	ubbf.apk_version('no-such-package-name'), null);

let svfs = ubbf.statvfs_info('/');
assert_eq('statvfs_info: object',
	type(svfs), 'object');
assert_true('statvfs_info: total_kib positive',
	svfs?.total_kib > 0);
assert_true('statvfs_info: avail_kib is integer',
	type(svfs?.avail_kib) == 'int64' || type(svfs?.avail_kib) == 'int');
assert_null('statvfs_info: missing path',
	ubbf.statvfs_info('/nonexistent/path/xyz'));
assert_null('statvfs_info: non-string',
	ubbf.statvfs_info(null));

assert_true('du_kib: /tmp >= 0',
	ubbf.du_kib('/tmp') >= 0);
assert_eq('du_kib: non-string',
	ubbf.du_kib(null), -1);
assert_eq('du_kib: missing path',
	ubbf.du_kib('/nonexistent/path/xyz'), -1);

/* ---- led.c: led_read_info ------------------------------------------- */

let led = led_lib.read_info('bogus_led_name_does_not_exist');
assert_eq('led_read_info: returns object',
	type(led), 'object');
assert_eq('led_read_info: Name field',
	led?.Name, 'bogus_led_name_does_not_exist');
assert_eq('led_read_info: missing LED is Error',
	led?.Status, 'Error');
assert_eq('led_read_info: missing LED is not enabled',
	led?.Enable, 'false');
assert_eq('led_read_info: missing LED MaxBrightness',
	led?.MaxBrightness, '0');
assert_eq('led_read_info: no keys outside the schema',
	sort(keys(led)), sort(['Enable', 'Name', 'Status', 'CyclePeriodRepetitions',
		'Location', 'RelativeXPosition', 'RelativeYPosition', 'MaxBrightness',
		'CycleElementNumberOfEntries']));
assert_eq('led_read_info: name without a colon',
	led_lib.read_info('mt76-phy0')?.CurrentColor, null);
assert_null('led_read_info: non-string',
	led_lib.read_info(null));
assert_null('led_read_info: name with a slash',
	led_lib.read_info('../../../etc'));
assert_null('led_read_info: name ..',
	led_lib.read_info('..'));
assert_null('led_read_info: empty name',
	led_lib.read_info(''));

/* ---- proc.c: cpu_stats / process_count / process_info --------------- */

let cpu = ubbf.cpu_stats();
assert_eq('cpu_stats: returns object', type(cpu), 'object');
assert_eq('cpu_stats: cpu key is object',
	type(cpu?.cpu), 'object');
assert_eq('cpu_stats: cpu has CPUUtilization',
	type(cpu?.cpu?.CPUUtilization), 'string');

assert_true('process_count: positive integer',
	ubbf.process_count() > 0);

let pi_init = ubbf.process_info(1);
assert_eq('process_info: PID 1 returns object',
	type(pi_init), 'object');
assert_eq('process_info: PID field',
	pi_init?.PID, '1');
assert_true('process_info: Command non-empty',
	length(pi_init?.Command ?? '') > 0);
assert_true('process_info: State is a string',
	length(pi_init?.State ?? '') > 0);
assert_null('process_info: non-int',
	ubbf.process_info('abc'));
assert_null('process_info: missing pid',
	ubbf.process_info(99999999));

/* ---- dhcp.c: leases_parse ------------------------------------------- */

assert_eq('leases_parse: returns array',
	type(ubbf.leases_parse()), 'array');

/* ---- usb.c: enumerate / device_info / interface_info / net_interfaces */

let usb = usb_lib.enumerate();
assert_eq('usb_enumerate: object',
	type(usb), 'object');
assert_eq('usb_enumerate: hosts is array',
	type(usb?.hosts), 'array');
assert_eq('usb_enumerate: devices is array',
	type(usb?.devices), 'array');
assert_eq('usb_enumerate: interfaces is array',
	type(usb?.interfaces), 'array');

let udi = usb_lib.device_info('nonexistent-usb-dev');
assert_eq('usb_device_info: returns object',
	type(udi), 'object');
assert_eq('usb_device_info: defaults for missing files',
	udi?.manufacturer, '');
assert_null('usb_device_info: non-string',
	usb_lib.device_info(null));

let uii = usb_lib.interface_info('nonexistent-iface:1.0');
assert_eq('usb_interface_info: returns object',
	type(uii), 'object');
assert_eq('usb_interface_info: bInterfaceNumber defaults',
	uii?.bInterfaceNumber, 0);
assert_null('usb_interface_info: non-string',
	usb_lib.interface_info(null));

assert_eq('usb_net_interfaces: returns array',
	type(usb_lib.net_interfaces()), 'array');

/* ---- get results follow the schema ------------------------------------ */

let dm_project = ubbf.create();
let x_rows = [{ Name: 'a', Stray: 's' }, { Name: 'b', Stray: 't' }];

dm_project.register({
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
		get: function(ctx) {
			if (ctx.instance == null)
				return ubbf.enumerate_instances(x_rows, (r) => r);
			return ubbf.get_by_instance(x_rows, ctx.instance);
		}
	},
	'Device.Y': {
		get: () => ({ Free: 'f' })
	}
});
dm_project.load('/dev/null');
dm_project.set_config({ Device: { X: {}, Y: {} } });
dm_project.runtime_reload();

let x_tree = dm_project.get_subtree_with_state('Device.X');
assert_eq('get result: a declared parameter stays', x_tree?.Kept, 'k');
assert_null('get result: an undeclared parameter goes', x_tree?.Hidden);
assert_eq('get result: a registered child object stays', x_tree?.Child?.Inner, 'i');
assert_null('get result: an inline child follows its own schema', x_tree?.Child?.Stray);
assert_eq('get result: an inline table keeps its rows',
	x_tree?.Inline?.['1']?.Name, 'r');
assert_null('get result: an inline row follows the row schema',
	x_tree?.Inline?.['1']?.Stray);
assert_null('get result: an unregistered child object goes', x_tree?.Gone);
assert_eq('get result: a metadata key stays', x_tree?.['.name'], 'n');
assert_eq('get result: enumerated rows keep declared parameters',
	[ x_tree?.Row?.['1']?.Name, x_tree?.Row?.['2']?.Name ], [ 'a', 'b' ]);
assert_null('get result: enumerated rows lose undeclared parameters',
	x_tree?.Row?.['1']?.Stray);
assert_null('get result: also for one row',
	dm_project.get_subtree_with_state('Device.X.Row.2')?.Stray);
assert_eq('get result: an entry without a schema is left alone',
	dm_project.get_subtree_with_state('Device.Y')?.Free, 'f');

/* ---- schema rules: params_set and object_add ------------------------- */

const W = 0x80000000;
const T_STRING = 0x1, T_BOOL = 0x4, T_INT = 0x8, T_UINT = 0x10, T_ULONG = 0x20, T_HEXBIN = 0x80, T_LONG = 0x200;

let dm_rules = ubbf.create();
dm_rules.register({
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
dm_rules.load('/dev/null');
dm_rules.set_config({ Device: { V: {} } });

function rule_set(name, value) {
	dm_rules.trans_start();
	let rc = dm_rules.params_set({ ['Device.V.' + name]: value });
	let stored = dm_rules.config()?.Device?.V?.[name];
	dm_rules.trans_abort();
	return [ rc, stored ];
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

for (let c in RULE_CASES) {
	let r = rule_set(c[0], c[1]);

	assert_eq(`params_set rule: ${c[0]} = ${c[1]}`, r[0], c[2]);
	if (c[2] < 0)
		assert_null(`params_set rule: ${c[0]} = ${c[1]} not stored`, r[1]);
}

dm_rules.trans_start();
assert_eq('params_set rule: one bad value refuses the set',
	  dm_rules.params_set({ 'Device.V.Mode': 'Auto', 'Device.V.Port': '0' }), -4);
assert_null('params_set rule: the good value of that set is not stored',
	    dm_rules.config()?.Device?.V?.Mode);
dm_rules.trans_abort();

dm_rules.trans_start();
assert_eq('object_add: schema addable false refuses', dm_rules.object_add('Device.V.Fixed'), 0);
assert_true('object_add: schema max_instances 1 of 2', dm_rules.object_add('Device.V.Two') > 0);
assert_true('object_add: schema max_instances 2 of 2', dm_rules.object_add('Device.V.Two') > 0);
assert_eq('object_add: schema max_instances refuses the third', dm_rules.object_add('Device.V.Two'), 0);
assert_true('object_add: entry addable wins over schema', dm_rules.object_add('Device.V.Own') > 0);
assert_eq('object_add: entry maxInstances wins over schema', dm_rules.object_add('Device.V.Own'), 0);
dm_rules.trans_abort();

assert_false('schema_entry_addable: maxInstances 0', ubbf.schema_entry_addable({ maxInstances: 0 }));
assert_true('schema_entry_addable: maxInstances 1', ubbf.schema_entry_addable({ maxInstances: 1 }));
assert_true('schema_entry_addable: no limit', ubbf.schema_entry_addable({}));

/* ---- object_add: the parents of the new row must exist --------------- */

let dm_nest = ubbf.create();
dm_nest.register({
	'Device.N': {},
	'Device.N.Chain.{i}': { schema: { schema: { Alias: T_STRING | W }, defaults: { Alias: '' } } },
	'Device.N.Chain.{i}.Rule.{i}': { schema: { schema: { Alias: T_STRING | W }, defaults: { Alias: '' } } }
});
dm_nest.load('/dev/null');
dm_nest.set_config({ Device: { N: { Chain: { '1': { Alias: 'c1' } } } } });

dm_nest.trans_start();
assert_true('object_add: row under an existing parent', dm_nest.object_add('Device.N.Chain.1.Rule') > 0);
assert_eq('object_add: row under a missing parent refused', dm_nest.object_add('Device.N.Chain.999.Rule'), 0);
assert_null('object_add: missing parent not created', dm_nest.config()?.Device?.N?.Chain?.['999']);

let digits = '';
for (let i = 0; i < 600; i++)
	digits += '9';
assert_eq('object_add: oversized instance refused', dm_nest.object_add(`Device.N.Chain.${digits}.Rule`), 0);
dm_nest.trans_abort();

/* ---- writable_rows: a write into a live row that is not stored -------- */

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

let live_schema = { schema: { Live: T_STRING, Enable: T_BOOL | W }, defaults: {}, addable: false };

let dm_live = ubbf.create();
dm_live.register({
	'Device.L': {},
	'Device.L.Row.{i}': { schema: live_schema, get: live_row_get, set: () => 0,
	                      runtime_instances: true, writable_rows: true },
	'Device.M': {},
	'Device.M.Row.{i}': { schema: live_schema, get: live_row_get, set: () => 0,
	                      runtime_instances: true }
});
dm_live.load('/dev/null');
dm_live.set_config({ Device: { L: {}, M: {} } });

dm_live.trans_start();
assert_eq('writable_rows: write into a live row', dm_live.params_set({ 'Device.L.Row.2.Enable': 'false' }), 0);
assert_eq('writable_rows: the write is stored', dm_live.config()?.Device?.L?.Row?.['2']?.Enable, 'false');
assert_eq('writable_rows: write into a row that is not live',
	  dm_live.params_set({ 'Device.L.Row.5.Enable': 'false' }), -2);
assert_null('writable_rows: no phantom row', dm_live.config()?.Device?.L?.Row?.['5']);
assert_eq('runtime_instances alone: a runtime row is read-only',
	  dm_live.params_set({ 'Device.M.Row.2.Enable': 'false' }), -2);
dm_live.trans_commit();
dm_live.runtime_reload();

let live_tree = dm_live.get_subtree_with_state('Device.L')?.Row;
assert_eq('writable_rows: both rows after the write',
	  [ live_tree?.['1']?.Live, live_tree?.['2']?.Live, live_tree?.['2']?.Enable ],
	  [ 'yes', 'stored', 'false' ]);

/* The same rules compiled into a schema table, when a build tree is given. */
let rules_build_dir = getenv('UBBF_BUILD_DIR');

if (rules_build_dir && length(ubbf.schema_tables_load(rules_build_dir + '/schema-umdns.so') ?? [])) {
	let dm_table = ubbf.create();
	dm_table.register({
		'Device.DNS.SD.Advertise.{i}': { schema: 'umdns.SD_Advertise' },
		'Device.DNS.SD.Service.{i}': { schema: 'umdns.SD_Service' }
	});
	dm_table.load('/dev/null');
	dm_table.set_config({ Device: { DNS: { SD: { Advertise: { '1': {} } } } } });

	const TABLE_CASES = [
		[ 'TransportProtocol', 'UDP', 0 ], [ 'TransportProtocol', 'SCTP', -4 ],
		[ 'Port', '65535', 0 ], [ 'Port', '65536', -4 ],
		[ 'InstanceName', 'x', 0 ], [ 'InstanceName', sprintf('%64s', 'x'), -4 ],
		[ 'Enable', 'maybe', -4 ],
	];

	for (let c in TABLE_CASES) {
		dm_table.trans_start();
		assert_eq(`params_set table rule: ${c[0]} = ${c[1]}`,
			  dm_table.params_set({ ['Device.DNS.SD.Advertise.1.' + c[0]]: c[1] }), c[2]);
		dm_table.trans_abort();
	}

	dm_table.trans_start();
	assert_eq('object_add: table addable false refuses', dm_table.object_add('Device.DNS.SD.Service'), 0);
	dm_table.trans_abort();

	assert_eq('schema_param_info: table rule facts',
		  ubbf.schema_param_info('umdns.SD_Advertise', 'TransportProtocol'),
		  { enum: [ 'TCP', 'UDP' ], writable: true, type: 'DM_STRING' });
	assert_eq('schema_param_info: table max',
		  ubbf.schema_param_info('umdns.SD_Advertise', 'Port'),
		  { max: 65535, writable: true, type: 'DM_UINT' });
	assert_false('schema_entry_addable: table', ubbf.schema_entry_addable({ schema: 'umdns.SD_Service' }));
	assert_true('schema_entry_addable: entry wins',
		    ubbf.schema_entry_addable({ schema: 'umdns.SD_Service', addable: true }));
}
else
	printf('UBBF_BUILD_DIR not set: schema table rule checks skipped\n');

/* Named TR-181 data types carry their base type: StatsCounter32 and Order
 * are unsignedInt, StatsCounter64 is unsignedLong. */
if (rules_build_dir && length(ubbf.schema_tables_load(rules_build_dir + '/schema-core.so') ?? [])) {
	const TYPE_CASES = [
		[ 'Bridging.Port_Stats', 'BytesSent', 'DM_ULONG' ],
		[ 'Bridging.Port_Stats', 'ErrorsSent', 'DM_UINT' ],
		[ 'Firewall.Chain_Rule', 'Order', 'DM_UINT' ],
		[ 'Routing.Router_IPv4Forwarding', 'MTU', 'DM_UINT' ],
	];

	for (let c in TYPE_CASES)
		assert_eq(`schema_param_info: ${c[0]}.${c[1]} type`,
			  ubbf.schema_param_info(c[0], c[1])?.type, c[2]);

	let stats_defaults = ubbf.schema_defaults('Bridging.Port_Stats');
	assert_eq('schema_defaults: StatsCounter64 without data',
		  stats_defaults?.BytesSent, '18446744073709551615');
	assert_eq('schema_defaults: StatsCounter32 without data',
		  stats_defaults?.ErrorsSent, '4294967295');

	let dm_order = ubbf.create();
	dm_order.register({ 'Device.Firewall.Chain.{i}.Rule.{i}': { schema: 'Firewall.Chain_Rule' } });
	dm_order.load('/dev/null');
	dm_order.set_config({ Device: { Firewall: { Chain: { '1': { Rule: { '1': {} } } } } } });

	for (let c in [ [ '2', 0 ], [ 'abc', -4 ], [ '0', -4 ], [ '4294967296', -4 ] ]) {
		dm_order.trans_start();
		assert_eq(`params_set: Chain.Rule.Order = ${c[0]}`,
			  dm_order.params_set({ 'Device.Firewall.Chain.1.Rule.1.Order': c[0] }), c[1]);
		dm_order.trans_abort();
	}
}

/* ---- summary ---------------------------------------------------------- */

printf('\n--- ubbf module test results ---\n');
printf('  passed: %d\n', pass_count);
printf('  failed: %d\n', fail_count);
printf('  total:  %d\n', pass_count + fail_count);

if (fail_count > 0) {
	printf('\nSOME TESTS FAILED\n');
	exit(1);
}

printf('\nALL TESTS PASSED\n');
