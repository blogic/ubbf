/* SPDX-License-Identifier: GPL-2.0-only */

/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

/*
 * hosts.c: the maps of the host scan, the DHCP client paths, the
 * ActiveLastChange state with the hosts that left the LAN, and the lookup
 * of a host by address. Runs isolated: the state file is in /tmp/ubbf.
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
test_maps(void **state)
{
	eval_expect(*state,
		"return [ ubbf.ipv6_maps_merge({ A: [ 'x', 'y' ] }, { A: [ 'y', 'z' ], B: [ 'w' ] }),"
		"  ubbf.hosts_ap_ssids({ radio0: { interfaces: [ { ifname: 'ap0', config: { ubbf_ssid: '2' } }, { ifname: 'ap1', config: {} } ] } }),"
		"  ubbf.ap_by_ssid_instance({ Device: { WiFi: { AccessPoint: { '1': { SSIDReference: 'Device.WiFi.SSID.2.' },"
		"    '2': { SSIDReference: 'Device.WiFi.SSID.2' }, '3': { SSIDReference: 'Device.WiFi.SSID.' } } } } }),"
		"  ubbf.netifd_interfaces_build({ interface: [ { interface: 'lan', 'ipv4-address': [ { address: '192.168.1.1', mask: 24 } ] } ] }) ];",
		"[ { \"A\": [ \"x\", \"y\", \"z\" ], \"B\": [ \"w\" ] }, { \"ap0\": 2 }, { \"2\": \"1\" }, "
		"[ { \"name\": \"lan\", \"addresses\": [ { \"ip\": \"192.168.1.1\", \"mask\": 24 } ], \"ipv6_addresses\": [ ] } ] ]");
}

static void
test_pool_paths(void **state)
{
	eval_expect(*state,
		"return ubbf.pool_client_paths({ 'Device.DHCPv4.Server.Pool.1': { '10': { mac: 'A' }, '2': { mac: 'A' }, '3': { mac: 'B' } } },"
		"  { 'Device.DHCPv6.Server.Pool.1': { '1': { mac: 'A' }, '2': { mac: 'C' } } });",
		"{ \"A\": \"Device.DHCPv4.Server.Pool.1.Client.2,Device.DHCPv6.Server.Pool.1.Client.1\", "
		"\"B\": \"Device.DHCPv4.Server.Pool.1.Client.3\", \"C\": \"Device.DHCPv6.Server.Pool.1.Client.2\" }");
}

static void
test_state(void **state)
{
	eval_expect(*state,
		"let now = 1700000000, ttl = 7 * 24 * 3600;"
		"let st = { entries: {"
		"  '02:00:00:00:00:01': { active: false, changed: now - 500, seen: now - 500, host: { hostname: 'a' } },"
		"  '02:00:00:00:00:02': { active: false, changed: now - 100, seen: now - 100, host: { hostname: 'b' } },"
		"  '02:00:00:00:00:03': { active: false, changed: now, seen: now - ttl, host: { hostname: 'c' } } },"
		"  dirty: false, now };"
		"let lc = ubbf.host_active_track(st, '02:00:00:00:00:09', true, { hostname: 'n' });"
		"let present = [ { mac: '02:00:00:00:00:09', hostname: 'n' } ];"
		"let rows = ubbf.hosts_downstream_build(st, present, '2');"
		"return [ lc, map(rows, (h) => [ h.mac, h.active ]), sort(keys(st.entries)), st.dirty,"
		"  ubbf.hosts_inactive_drop(st, present, 200), ubbf.hosts_inactive_drop(st, present, null) ];",
		"[ \"2023-11-14T22:13:20Z\", [ [ \"02:00:00:00:00:02\", false ], [ \"02:00:00:00:00:09\", null ] ], "
		"[ \"02:00:00:00:00:02\", \"02:00:00:00:00:03\", \"02:00:00:00:00:09\" ], true, 0, 1 ]");
	eval_expect(*state,
		"let st = ubbf.hosts_state_load(); st.entries.X = { seen: st.now, host: {} }; st.dirty = true;"
		"ubbf.hosts_state_flush(st); return [ st.dirty, keys(ubbf.hosts_state_load().entries) ];",
		"[ false, [ \"X\" ] ]");
}

static void
test_path_by_ip(void **state)
{
	eval_expect(*state,
		"let n = { '1': { ipv4_addresses: [ '192.168.1.5' ] }, '4': { ipv6_addresses: [ 'fd00::5%br-lan' ] } };"
		"return map([ '192.168.1.5', 'fd00:0::5', 'fd00::5%eth0', '::ffff:192.168.1.5', 'x', null ],"
		"  (ip) => ubbf.host_path_by_ip_find(n, ip));",
		"[ \"Device.Hosts.Host.1\", \"Device.Hosts.Host.4\", \"Device.Hosts.Host.4\", \"\", \"\", \"\" ]");
}

int
main(void)
{
	const struct CMUnitTest tests[] = {
		cmocka_unit_test(test_maps),
		cmocka_unit_test(test_pool_paths),
		cmocka_unit_test(test_state),
		cmocka_unit_test(test_path_by_ip),
	};

	return cmocka_run_group_tests(tests, vm_setup, vm_teardown);
}
