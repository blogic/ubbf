/* SPDX-License-Identifier: GPL-2.0-only */

/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

/*
 * firewall_reconcile.c: the claims of the `firewall` hooks against the
 * Service, InterfaceSetting and Policy tables, and a Chain for each Level.
 * The schema defaults are checked only as "every default is in the row":
 * the test VM may have no schema table.
 */

#include "harness.h"
#include "ubbf.h"

static void
eval_expect(uc_vm_t *vm, const char *code, const char *expected)
{
	uc_value_t *res = vm_eval(vm, code);

	assert_json_equal(vm, res, expected);
	ucv_put(res);
}

static void
test_claims(void **state)
{
	eval_expect(*state,
		"let svc = (alias, port) => ({ type: 'Service', alias, Interface: 'Device.IP.Interface.1',"
		"  Protocol: '6', DestPort: port, Action: 'Accept' });"
		"let model = {"
		"  'Device.SSH.Server.{i}': { firewall: (inst, root, path) =>"
		"    [ svc('cpe-ssh-' + inst.Port, inst.Port), { type: 'Bogus', alias: 'cpe-x' }, { type: 'Service' } ] },"
		"  'Device.IP.Interface.{i}': { firewall: (inst, root, path) => (inst.Name == 'lan')"
		"    ? [ { type: 'Policy', alias: 'cpe-lan', SourceInterface: path, DestinationInterface: 'Device.IP.Interface.1' },"
		"        { type: 'InterfaceSetting', alias: 'cpe-if-lan', Interface: path } ] : null },"
		"  'Device.X': {} };"
		"let root = { Device: {"
		"  SSH: { Server: { '1': { Port: '22' }, '2': { Port: '2222' } } },"
		"  IP: { Interface: { '1': { Name: 'wan' }, '2': { Name: 'lan' } } },"
		"  Firewall: { Service: {"
		"    '1': { Alias: 'mine', Interface: 'Device.IP.Interface.1', Protocol: 6, DestPort: '22' },"
		"    '2': { Alias: 'cpe-old-80', Interface: 'Device.IP.Interface.1', Protocol: '6', DestPort: '80' },"
		"    '3': { Alias: 'cpe-Service3', DestPort: '81' } } } } };"
		"ubbf.firewall_reconcile(model, root);"
		"let fw = root.Device.Firewall;"
		"return [ map(sort(keys(fw.Service)), (k) => [ k, fw.Service[k].Alias, fw.Service[k].DestPort ]),"
		"  fw.ServiceNumberOfEntries, fw.Policy['1'].SourceInterface, fw.InterfaceSetting['1'].Alias,"
		"  fw.Service['4'].Enable, fw.Service['4'].type, fw.PolicyNumberOfEntries ];",
		"[ [ [ \"1\", \"mine\", \"22\" ], [ \"3\", \"cpe-Service3\", \"81\" ], "
		"[ \"4\", \"cpe-ssh-2222\", \"2222\" ] ], \"3\", \"Device.IP.Interface.2\", "
		"\"cpe-if-lan\", \"true\", null, \"1\" ]");
}

static void
test_claim_adopts_hook_alias(void **state)
{
	/* a row that a hook made under another alias is matched by content,
	 * and its alias follows the claim */
	eval_expect(*state,
		"let model = { 'Device.SSH': { firewall: () => [ { type: 'Service', alias: 'cpe-ssh-new',"
		"  Interface: 'Device.IP.Interface.1', Protocol: '6', DestPort: '22', IPVersion: '-1' } ] } };"
		"let root = { Device: { SSH: {}, Firewall: { Service: {"
		"  '7': { Alias: 'cpe-ssh-old', Interface: 'Device.IP.Interface.1', Protocol: '6', DestPort: '22' } } } } };"
		"ubbf.firewall_reconcile(model, root);"
		"let row = root.Device.Firewall.Service['7'];"
		"let defs = ubbf.schema_defaults('Firewall.Service') ?? {};"
		"return [ keys(root.Device.Firewall.Service), row.Alias, row.DestPort,"
		"  length(filter(keys(defs), (k) => !(k in row))) ];",
		"[ [ \"7\" ], \"cpe-ssh-new\", \"22\", 0 ]");
}

static void
test_hook_exception(void **state)
{
	/* a failing hook stops the reconcile before a table changes */
	eval_expect(*state,
		"let model = { 'Device.SSH': { firewall: () => die('hook failed') } };"
		"let root = { Device: { SSH: {}, Firewall: { Service: { '1': { Alias: 'cpe-ssh-22' } } } } };"
		"let msg;"
		"try { ubbf.firewall_reconcile(model, root); } catch (e) { msg = e.message; }"
		"return [ msg, root.Device.Firewall ];",
		"[ \"hook failed\", { \"Service\": { \"1\": { \"Alias\": \"cpe-ssh-22\" } } } ]");
}

static void
test_level_chains(void **state)
{
	eval_expect(*state,
		"let root = { Device: { Firewall: {"
		"  Level: { '1': { Name: 'Default', Chain: 'Device.Firewall.Chain.1.' }, '2': { Name: 'Strict', Chain: '' },"
		"    '3': { Chain: 'Device.Firewall.Chain.9' }, 'x': { Chain: '' }, '4': 'junk' },"
		"  Chain: { '1': { Alias: 'DefaultChain' } } } } };"
		"ubbf.firewall_reconcile({}, root);"
		"let fw = root.Device.Firewall;"
		"return [ fw.Level['1'].Chain, fw.Level['2'].Chain, fw.Chain['2'].Alias, fw.Chain['2'].Name,"
		"  fw.Chain['2'].Enable, fw.Level['3'].Chain, fw.Chain['3'].Name, fw.ChainNumberOfEntries,"
		"  fw.Level.x.Chain ];",
		"[ \"Device.Firewall.Chain.1.\", \"Device.Firewall.Chain.2\", \"cpe-Level2\", \"Strict\", "
		"\"true\", \"Device.Firewall.Chain.3\", \"Level3\", \"3\", \"\" ]");
}

static void
test_empty(void **state)
{
	eval_expect(*state,
		"let root = {};"
		"ubbf.firewall_reconcile(null, root);"
		"ubbf.firewall_reconcile({}, null);"
		"return map(sort(keys(root.Device.Firewall)), (k) => [ k, root.Device.Firewall[k] ]);",
		"[ [ \"InterfaceSetting\", { } ], [ \"InterfaceSettingNumberOfEntries\", \"0\" ], "
		"[ \"Policy\", { } ], [ \"PolicyNumberOfEntries\", \"0\" ], "
		"[ \"Service\", { } ], [ \"ServiceNumberOfEntries\", \"0\" ] ]");
}

int
main(void)
{
	const struct CMUnitTest tests[] = {
		cmocka_unit_test(test_claims),
		cmocka_unit_test(test_claim_adopts_hook_alias),
		cmocka_unit_test(test_hook_exception),
		cmocka_unit_test(test_level_chains),
		cmocka_unit_test(test_empty),
	};

	return cmocka_run_group_tests(tests, vm_setup, vm_teardown);
}
