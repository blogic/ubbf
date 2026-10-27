/* SPDX-License-Identifier: GPL-2.0-only */

/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

/*
 * status.c. Runs isolated (run-isolated.sh): the setup adds a veth pair
 * that is up (operstate up), a veth whose peer is down (lowerlayerdown)
 * and a dummy device (unknown).
 */

#include "harness.h"
#include "ubbf.h"

#include <stdlib.h>

static const char *const setup_cmds[] = {
	"ip link add v0 type veth peer name v1",
	"ip link add v2 type veth peer name v3",
	"ip link set v0 up",
	"ip link set v1 up",
	"ip link set v2 up",
	"ip link add d0 type dummy",
	"ip link set d0 up",
	"sleep 1",
};

static int
group_setup(void **state)
{
	for (size_t i = 0; i < sizeof(setup_cmds) / sizeof(setup_cmds[0]); i++)
		if (system(setup_cmds[i]))
			return -1;

	return vm_setup(state);
}

static void
eval_expect(uc_vm_t *vm, const char *code, const char *json)
{
	uc_value_t *res = vm_eval(vm, code);

	assert_json_equal(vm, res, json);
	ucv_put(res);
}

static void
test_bridge(void **state)
{
	eval_expect(*state,
		"return [ ubbf.bridge_status_derive('true', 'v0'), ubbf.bridge_status_derive('1', 'd0'),"
		"  ubbf.bridge_status_derive(true, 'v2'), ubbf.bridge_status_derive('false', 'v0'),"
		"  ubbf.bridge_status_derive('true', ''), ubbf.bridge_status_derive('true', 'nope') ];",
		"[ \"Enabled\", \"Error\", \"Error\", \"Disabled\", \"Error\", \"Error\" ]");
}

static void
test_ifop_netdev(void **state)
{
	eval_expect(*state,
		"return [ ubbf.ifop_status_derive('true', 'v0'), ubbf.ifop_status_derive('true', 'v2'),"
		"  ubbf.ifop_status_derive('true', 'd0'), ubbf.ifop_status_derive('true', 'nope'),"
		"  ubbf.ifop_status_derive('true', null), ubbf.ifop_status_derive('false', 'v0') ];",
		"[ \"Up\", \"LowerLayerDown\", \"Unknown\", \"Unknown\", \"Down\", \"Down\" ]");
}

static void
test_ifop_lower_layers(void **state)
{
	eval_expect(*state,
		"let root = { Device: {"
		"  E: { '1': { Name: 'v0' }, '2': { Name: 'v2' }, '3': { Status: 'Up' },"
		"       '4': { Status: 'Dormant' }, '5': { Name: 'd0' }, '6': 'text' },"
		"  WiFi: { SSID: { '1': {}, '2': {} } } } };"
		"let asked = [];"
		"let ssid = (n) => { push(asked, n); return n == 1 ? 'v0' : null; };"
		"let f = (ll) => ubbf.ifop_status_derive('true', 'd0', ll, root, ssid);"
		"return [ f('Device.E.1'), f('Device.E.2'), f('Device.E.4,Device.E.3'),"
		"  f('Device.E.2, Device.E.5'), f('Device.E.9'), f('Device.E.6'),"
		"  f('Device.WiFi.SSID.1'), f('Device.WiFi.SSID.2'), f('Device.WiFi.SSID.2,Device.E.2'),"
		"  ubbf.ifop_status_derive('true', 'v0', 'Device.E.2', null), asked ];",
		"[ \"Up\", \"LowerLayerDown\", \"Up\", \"Unknown\", \"Unknown\", \"Unknown\","
		" \"Up\", \"Unknown\", \"Unknown\", \"Up\", [ 1, 2, 2 ] ]");
}

static void
test_ifop_resolver_throws(void **state)
{
	eval_expect(*state,
		"let root = { Device: { WiFi: { SSID: { '1': {} } } } };"
		"try { ubbf.ifop_status_derive('true', 'v0', 'Device.WiFi.SSID.1', root, () => die('no wifi')); }"
		"catch (e) { return e.message; }",
		"\"no wifi\"");
}

int
main(void)
{
	const struct CMUnitTest tests[] = {
		cmocka_unit_test(test_bridge),
		cmocka_unit_test(test_ifop_netdev),
		cmocka_unit_test(test_ifop_lower_layers),
		cmocka_unit_test(test_ifop_resolver_throws),
	};

	return cmocka_run_group_tests(tests, group_setup, vm_teardown);
}
