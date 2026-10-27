/* SPDX-License-Identifier: GPL-2.0-only */

/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

/*
 * ifstats.c: Stats objects from udevstats replies, and the netdevs behind
 * an IP.Interface.
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
test_build(void **state)
{
	uc_vm_t *vm = *state;

	eval_expect(vm,
		"let r = { rx: { bytes: 100, packets: 2, unicast: 1, multicast: 1 }, tx: { bytes: 50, packets: 1, broadcast: 1 } };"
		"return ubbf.ifstats_build([ r, null, { rx: { bytes: 2.5 } } ], false);",
		"{ \"BytesSent\": \"50\", \"BytesReceived\": \"102\", \"PacketsSent\": \"1\", \"PacketsReceived\": \"2\", "
		"\"ErrorsSent\": \"0\", \"ErrorsReceived\": \"0\", \"DiscardPacketsSent\": \"0\", \"DiscardPacketsReceived\": \"0\" }");
	eval_expect(vm,
		"let s = ubbf.ifstats_build([ { rx: { unicast: 3, multicast: 4 }, tx: { broadcast: 5 } } ], true);"
		"return [ s.UnicastPacketsReceived, s.MulticastPacketsReceived, s.BroadcastPacketsSent,"
		"  s.UnknownProtoPacketsReceived, length(s) ];",
		"[ \"3\", \"4\", \"5\", \"0\", 15 ]");
}

static void
test_members(void **state)
{
	eval_expect(*state,
		"let root = { Device: { Ethernet: { Interface: { '1': { Name: 'lan1' }, '2': { Name: 'lan2' }, '3': { Name: 'wan' } } },"
		"  Bridging: { Bridge: { '1': { Port: {"
		"    '1': { Enable: 'true', ManagementPort: 'true', LowerLayers: 'Device.Ethernet.Interface.3' },"
		"    '2': { Enable: 'true', LowerLayers: 'Device.Ethernet.Interface.2,Device.Ethernet.Interface.1' },"
		"    '3': { Enable: 'true', LowerLayers: 'Device.Ethernet.Interface.1' },"
		"    '4': { Enable: 'false', LowerLayers: 'Device.Ethernet.Interface.3' } } } } } } };"
		"let m = (ll) => ubbf.ip_interface_members(root, { LowerLayers: ll });"
		"return [ m('Device.Bridging.Bridge.1.Port.1.'), m('Device.Ethernet.Interface.3,Device.Bridging.Bridge.1.Port.9'),"
		"  m('Device.Bridging.Bridge.1.Port'), m(''), ubbf.ip_interface_members(null, { LowerLayers: 'Device.Ethernet.Interface.3' }) ];",
		"[ [ \"lan2\", \"lan1\" ], [ \"wan\", \"lan2\", \"lan1\" ], [ ], [ ], [ ] ]");
}

int
main(void)
{
	const struct CMUnitTest tests[] = {
		cmocka_unit_test(test_build),
		cmocka_unit_test(test_members),
	};

	return cmocka_run_group_tests(tests, vm_setup, vm_teardown);
}
