/* SPDX-License-Identifier: GPL-2.0-only */

/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

/*
 * sysfs.c: the file readers, the operstate map, the Link and Ethernet
 * properties, the ARP parser, hosts_merge(), layer3_interface_find() and
 * host_primary_ip(); with them the FDB and IPv6 neighbour dumps of rtnl.c,
 * which read the same setup. Runs isolated
 * (run-isolated.sh): the setup adds
 * - the veth pair v0/v1 (up, set MAC and MTU) with ARP and IPv6 neighbours,
 * - the veth v4 (up) with its peer v5 down,
 * - the bridge br0 with the port v2 (peer v3), the VLAN device br0.10 on
 *   it, and static, dynamic and multicast FDB entries,
 * - the empty bridge br1, the dummy d0 and the tap t0 (65535, half duplex).
 */

#include "harness.h"
#include "ubbf.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define FDB_BULK 120

static const char *const setup_cmds[] = {
	"ip link add v0 type veth peer name v1",
	"ip link set v0 address 02:aa:00:00:00:a0 mtu 1400 addrgenmode none",
	"ip link set v1 addrgenmode none",
	"ip link set v0 up",
	"ip link set v1 up",
	"ip link add v4 type veth peer name v5",
	"ip link set v4 address 02:aa:00:00:00:a4 addrgenmode none",
	"ip link set v4 up",
	"ip link add br0 type bridge",
	"ip link set br0 addrgenmode none",
	"ip link add v2 type veth peer name v3",
	"ip link set v2 address 02:cc:00:00:00:02 addrgenmode none",
	"ip link set v3 addrgenmode none",
	"ip link set v2 master br0",
	"ip link set v2 up",
	"ip link set v3 up",
	"ip link set br0 up",
	"ip link add link br0 name br0.10 type vlan id 10",
	"ip link set br0.10 addrgenmode none",
	"ip link set br0.10 up",
	"ip link add br1 type bridge",
	"ip link set br1 addrgenmode none",
	"ip link set br1 up",
	"ip link add d0 address 02:dd:00:00:00:0f type dummy",
	"ip link set d0 up",
	"ip tuntap add t0 mode tap",
	"ip link set t0 up",
	"ethtool -s t0 speed 65535 duplex half",
	"ip neigh add 192.0.2.5 lladdr 02:aa:00:00:00:05 dev v0 nud permanent",
	"ip neigh add 192.0.2.6 lladdr 02:aa:00:00:00:06 dev v0 nud stale",
	"ip neigh add 192.0.2.7 dev v0 nud incomplete",
	"ip neigh add 192.0.2.8 lladdr 00:00:00:00:00:00 dev v0 nud permanent",
	"ip neigh add 192.0.2.9 dev v0 nud failed",
	"ip neigh add 192.0.2.10 lladdr 02:aa:00:00:00:0a dev br0.10 nud permanent",
	"ip -6 neigh add 2001:db8::5 lladdr 02:aa:00:00:00:05 dev v0 nud permanent",
	"ip -6 neigh add 2001:db8::55 lladdr 02:aa:00:00:00:05 dev v0 nud permanent",
	"ip -6 neigh add 2001:db8::5 lladdr 02:aa:00:00:00:05 dev v1 nud permanent",
	"ip -6 neigh add fe80::5 lladdr 02:aa:00:00:00:05 dev v0 nud permanent",
	"ip -6 neigh add febf::5 lladdr 02:aa:00:00:00:0d dev v0 nud permanent",
	"ip -6 neigh add fec0::5 lladdr 02:aa:00:00:00:0c dev v0 nud permanent",
	"ip -6 neigh add 2001:db8::7 dev v0 nud incomplete",
	"ip -6 neigh add 2001:db8::9 dev v0 nud failed",
	"ip -6 neigh add 2001:db8::8 lladdr 00:00:00:00:00:00 dev v0 nud permanent",
	"ip -6 neigh add 2001:db8::b lladdr 02:aa:00:00:00:0b dev v0 router nud stale",
	"bridge fdb add 02:bb:00:00:00:01 dev v2 master static",
	"bridge fdb add 02:bb:00:00:00:02 dev v2 master dynamic",
	"bridge fdb add 01:00:5e:00:00:01 dev v2 master static",
	"bridge fdb add 33:33:00:00:00:02 dev v2 master static",
	"bridge -batch /tmp/fdb.batch",
	"sleep 1",
};

static int
fdb_batch_write(void)
{
	FILE *fp = fopen("/tmp/fdb.batch", "w");

	if (!fp)
		return -1;

	for (int i = 0; i < FDB_BULK; i++)
		fprintf(fp, "fdb add 02:ee:00:00:00:%02x dev v2 master static\n", i);

	return fclose(fp);
}

static int
group_setup(void **state)
{
	const char *path = getenv("PATH");
	char buf[4096];

	/* ip, bridge and ethtool live in sbin, which a user PATH may lack */
	snprintf(buf, sizeof(buf), "/usr/sbin:/sbin:%s", path ? path : "/usr/bin:/bin");
	if (setenv("PATH", buf, 1) || fdb_batch_write())
		return -1;

	for (size_t i = 0; i < sizeof(setup_cmds) / sizeof(setup_cmds[0]); i++)
		if (system(setup_cmds[i]))
			return -1;

	return vm_setup(state);
}

static void
file_write(const char *path, const char *text, size_t len)
{
	FILE *fp = fopen(path, "w");

	assert_non_null(fp);
	assert_int_equal(fwrite(text, 1, len, fp), len);
	assert_int_equal(fclose(fp), 0);
}

static void
eval_expect(uc_vm_t *vm, const char *code, const char *json)
{
	uc_value_t *res = vm_eval(vm, code);

	assert_json_equal(vm, res, json);
	ucv_put(res);
}

static void
call_expect(uc_vm_t *vm, uc_cfn_ptr_t fn, uc_value_t *a, uc_value_t *b, const char *json)
{
	uc_value_t *res = vm_call(vm, fn, 2, a, b);

	assert_json_equal(vm, res, json);
	ucv_put(res);
}

static void
test_readfile_trim(void **state)
{
	uc_vm_t *vm = *state;
	static char big[9000];
	uc_value_t *res;

	file_write("/tmp/t_plain", " \t value with  inner  \r\n\n", 25);
	file_write("/tmp/t_blank", "  \n", 3);
	file_write("/tmp/t_empty", "", 0);

	call_expect(vm, uc_ubbf_readfile_trim, ucv_string_new("/tmp/t_plain"), NULL,
		    "\"value with  inner\"");
	call_expect(vm, uc_ubbf_readfile_trim, ucv_string_new("/tmp/t_plain"), ucv_string_new("d"),
		    "\"value with  inner\"");
	call_expect(vm, uc_ubbf_readfile_trim, ucv_string_new("/tmp/t_blank"), ucv_string_new("d"),
		    "\"\"");
	call_expect(vm, uc_ubbf_readfile_trim, ucv_string_new("/tmp/t_empty"), ucv_string_new("d"),
		    "\"d\"");
	call_expect(vm, uc_ubbf_readfile_trim, ucv_string_new("/tmp/t_none"), ucv_int64_new(7), "7");
	call_expect(vm, uc_ubbf_readfile_trim, ucv_string_new("/tmp"), ucv_string_new("dir"),
		    "\"dir\"");
	call_expect(vm, uc_ubbf_readfile_trim, ucv_int64_new(1), vm_json(vm, "[ 1 ]"), "[ 1 ]");

	assert_null(vm_call(vm, uc_ubbf_readfile_trim, 1, ucv_string_new("/tmp/t_none")));
	assert_null(vm_call(vm, uc_ubbf_readfile_trim, 0));

	memset(big, 'x', sizeof(big));
	file_write("/tmp/t_big", big, sizeof(big));
	res = vm_call(vm, uc_ubbf_readfile_trim, 1, ucv_string_new("/tmp/t_big"));
	assert_int_equal(ucv_string_length(res), 8191);
	ucv_put(res);

	call_expect(vm, uc_ubbf_readfile_trim, ucv_string_new("/sys/class/net/v0/mtu"), NULL,
		    "\"1400\"");
}

static void
test_readfile_int(void **state)
{
	uc_vm_t *vm = *state;

	file_write("/tmp/i_pos", "42\n", 3);
	file_write("/tmp/i_neg", "  -17 \n", 7);
	file_write("/tmp/i_text", "abc\n", 4);
	file_write("/tmp/i_tail", "12abc\n", 6);
	file_write("/tmp/i_hex", "0x10\n", 5);
	file_write("/tmp/i_empty", "", 0);
	file_write("/tmp/i_blank", " \n", 2);

	call_expect(vm, uc_ubbf_readfile_int, ucv_string_new("/tmp/i_pos"), NULL, "42");
	call_expect(vm, uc_ubbf_readfile_int, ucv_string_new("/tmp/i_pos"), ucv_int64_new(9), "42");
	call_expect(vm, uc_ubbf_readfile_int, ucv_string_new("/tmp/i_neg"), ucv_int64_new(9), "-17");
	call_expect(vm, uc_ubbf_readfile_int, ucv_string_new("/tmp/i_text"), ucv_int64_new(9), "9");
	call_expect(vm, uc_ubbf_readfile_int, ucv_string_new("/tmp/i_tail"), ucv_int64_new(9), "9");
	call_expect(vm, uc_ubbf_readfile_int, ucv_string_new("/tmp/i_hex"), ucv_int64_new(-1), "-1");
	call_expect(vm, uc_ubbf_readfile_int, ucv_string_new("/tmp/i_empty"), ucv_int64_new(9), "9");
	call_expect(vm, uc_ubbf_readfile_int, ucv_string_new("/tmp/i_blank"), ucv_int64_new(9), "9");
	call_expect(vm, uc_ubbf_readfile_int, ucv_string_new("/tmp/i_none"), ucv_int64_new(9), "9");
	call_expect(vm, uc_ubbf_readfile_int, ucv_string_new("/tmp/i_none"), NULL, "0");
	call_expect(vm, uc_ubbf_readfile_int, ucv_string_new("/tmp/i_text"), ucv_string_new("9"), "0");
	call_expect(vm, uc_ubbf_readfile_int, ucv_string_new("/tmp/i_text"), ucv_double_new(9.5), "0");
	call_expect(vm, uc_ubbf_readfile_int, NULL, ucv_int64_new(3), "3");
	call_expect(vm, uc_ubbf_readfile_int, ucv_int64_new(1), NULL, "0");
	call_expect(vm, uc_ubbf_readfile_int, ucv_string_new("/sys/class/net/v0/mtu"), NULL, "1400");
}

static long long
proc_uptime(void)
{
	FILE *fp = fopen("/proc/uptime", "r");
	long long secs = -1;

	assert_non_null(fp);
	assert_int_equal(fscanf(fp, "%lld", &secs), 1);
	fclose(fp);

	return secs;
}

static void
test_uptime_read(void **state)
{
	uc_vm_t *vm = *state;
	long long before = proc_uptime(), after;
	uc_value_t *res = vm_call(vm, uc_ubbf_uptime_read, 0);

	after = proc_uptime();
	assert_int_equal(ucv_type(res), UC_INTEGER);
	assert_true(ucv_int64_get(res) >= before && ucv_int64_get(res) <= after);
	ucv_put(res);
}

static void
test_operstate(void **state)
{
	static const char *const states[][2] = {
		{ "up", "Up" }, { "down", "Down" }, { "unknown", "Unknown" },
		{ "dormant", "Dormant" }, { "notpresent", "NotPresent" },
		{ "lowerlayerdown", "LowerLayerDown" }, { "testing", "Error" }, { "up ", "Error" },
	};

	(void)state;

	for (size_t i = 0; i < sizeof(states) / sizeof(states[0]); i++)
		assert_string_equal(operstate_map(states[i][0]), states[i][1]);

	assert_string_equal(operstate_map(NULL), "Error");
	assert_string_equal(operstate_map(""), "Error");
	assert_string_equal(operstate_map("up"), "Up");
	assert_string_equal(operstate_map("UP"), "Error");
	assert_string_equal(operstate_map("testing"), "Error");
}

static void
netdev_expect(const char *ifname, const char *file, const char *def, const char *expected)
{
	char *val = netdev_read(ifname, file, def);

	assert_string_equal(val, expected);
	free(val);
}

static void
test_netdev_read(void **state)
{
	(void)state;

	netdev_expect("v0", "mtu", "0", "1400");
	netdev_expect("v0", "address", NULL, "02:aa:00:00:00:a0");
	netdev_expect("v0", "nope", "dflt", "dflt");
	netdev_expect("nope", "mtu", "dflt", "dflt");
	netdev_expect("nope", "mtu", NULL, "");
	netdev_expect("d0", "speed", "-1", "-1");
}

static void
test_link_properties(void **state)
{
	eval_expect(*state,
		"return map([ 'v0', 'v4', 'd0', 'lo', 'nope', '' ], ubbf.link_properties_get);",
		"[ { \"Status\": \"Up\", \"MACAddress\": \"02:AA:00:00:00:A0\", \"MTU\": \"1400\" },"
		" { \"Status\": \"LowerLayerDown\", \"MACAddress\": \"02:AA:00:00:00:A4\", \"MTU\": \"1500\" },"
		" { \"Status\": \"Unknown\", \"MACAddress\": \"02:DD:00:00:00:0F\", \"MTU\": \"1500\" },"
		" { \"Status\": \"Unknown\", \"MACAddress\": \"00:00:00:00:00:00\", \"MTU\": \"65536\" },"
		" { \"Status\": \"Unknown\", \"MACAddress\": \"00:00:00:00:00:00\", \"MTU\": \"0\" },"
		" { \"Status\": \"Unknown\", \"MACAddress\": \"00:00:00:00:00:00\", \"MTU\": \"0\" } ]");
}

static void
test_link_properties_args(void **state)
{
	eval_expect(*state,
		"return [ ubbf.link_properties_get(), ubbf.link_properties_get(5),"
		"  ubbf.ethernet_properties_get(null), ubbf.ethernet_properties_get({}) ];",
		"[ { }, { }, { }, { } ]");
}

static void
test_ethernet_properties(void **state)
{
	eval_expect(*state,
		"let f = (dev) => ubbf.ethernet_properties_get(dev);"
		"let pick = (dev) => { let p = f(dev); return [ p.Status, p.CurrentBitRate, p.CurrentDuplexMode ]; };"
		"return [ f('v0'), pick('t0'), pick('d0'), pick('v5'), slice(pick('br1'), 1), f('nope') ];",
		"[ { \"Enable\": \"true\", \"Status\": \"Up\", \"LowerLayers\": \"\", \"MaxBitRate\": \"-1\","
		" \"MACAddress\": \"02:AA:00:00:00:A0\", \"CurrentBitRate\": \"10000\","
		" \"CurrentDuplexMode\": \"Full\", \"EEECapability\": \"true\", \"EEEEnable\": \"false\" },"
		" [ \"Down\", \"0\", \"Half\" ], [ \"Unknown\", \"0\", \"Auto\" ], [ \"Down\", \"0\", \"Auto\" ],"
		" [ \"0\", \"Auto\" ],"
		" { \"Enable\": \"true\", \"Status\": \"Unknown\", \"LowerLayers\": \"\", \"MaxBitRate\": \"-1\","
		" \"MACAddress\": \"00:00:00:00:00:00\", \"CurrentBitRate\": \"0\","
		" \"CurrentDuplexMode\": \"Auto\", \"EEECapability\": \"true\", \"EEEEnable\": \"false\" } ]");
}

static void
test_arp_parse(void **state)
{
	eval_expect(*state,
		"return sort(ubbf.arp_parse(), (a, b) => a.ip < b.ip ? -1 : 1);",
		"[ { \"ip\": \"192.0.2.10\", \"mac\": \"02:AA:00:00:00:0A\", \"device\": \"br0.10\", \"active\": true },"
		" { \"ip\": \"192.0.2.5\", \"mac\": \"02:AA:00:00:00:05\", \"device\": \"v0\", \"active\": true },"
		" { \"ip\": \"192.0.2.6\", \"mac\": \"02:AA:00:00:00:06\", \"device\": \"v0\", \"active\": true } ]");
}

static void
test_bridge_fdb_parse(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *res;
	char name[32];

	/* learned entries and the ports of other links come and go, so only
	 * the MACs of the setup count */
	eval_expect(vm,
		"let fdb = ubbf.bridge_fdb_parse(), out = {};"
		"for (let k in sort(keys(fdb)))"
		"  if (match(k, /^(02:BB|02:CC|01:00:5E|33:33)/)) out[k] = fdb[k];"
		"return out;",
		"{ \"02:BB:00:00:00:01\": \"v2\", \"02:BB:00:00:00:02\": \"v2\" }");

	res = vm_call(vm, uc_ubbf_bridge_fdb_parse, 0);
	for (int i = 0; i < FDB_BULK; i++) {
		uc_value_t *dev;

		snprintf(name, sizeof(name), "02:EE:00:00:00:%02X", i);
		dev = ucv_object_get(res, name, NULL);
		assert_non_null(dev);
		assert_string_equal(ucv_string_get(dev), "v2");
	}
	ucv_put(res);
}

static void
test_ipv6_neigh_parse(void **state)
{
	eval_expect(*state,
		"let n = ubbf.ipv6_neigh_parse(), out = {};"
		"for (let k in sort(keys(n))) out[k] = sort(n[k]);"
		"return out;",
		"{ \"02:AA:00:00:00:05\": [ \"2001:db8::5\", \"2001:db8::55\" ],"
		" \"02:AA:00:00:00:0B\": [ \"2001:db8::b\" ], \"02:AA:00:00:00:0C\": [ \"fec0::5\" ] }");
}

static const char hosts_arp[] =
	"[ { \"ip\": \"192.0.2.5\", \"mac\": \"02:AA:00:00:00:05\", \"device\": \"v0\" },"
	"  { \"ip\": \"192.0.2.55\", \"mac\": \"02:AA:00:00:00:05\", \"device\": \"v0\" },"
	"  { \"ip\": \"192.0.2.5\", \"mac\": \"02:AA:00:00:00:05\", \"device\": \"v1\" },"
	"  { \"ip\": \"192.0.2.20\", \"mac\": \"02:AA:00:00:00:20\", \"device\": \"br0\" },"
	"  { \"ip\": \"192.0.2.21\", \"mac\": \"02:AA:00:00:00:21\", \"device\": \"br0.10\" },"
	"  { \"ip\": \"192.0.2.22\", \"mac\": \"02:AA:00:00:00:22\", \"device\": \"br0\" },"
	"  { \"ip\": \"192.0.2.23\", \"mac\": \"02:AA:00:00:00:23\", \"device\": \"nope\" },"
	"  { \"ip\": \"192.0.2.24\", \"mac\": \"02:AA:00:00:00:24\", \"device\": \"\" },"
	"  { \"ip\": \"192.0.2.25\", \"mac\": \"02:AA:00:00:00:25\", \"device\": \"v0/x\" },"
	"  { \"ip\": \"192.0.2.26\", \"mac\": \"02:AA:00:00:00:26\" },"
	"  { \"ip\": \"192.0.2.27\", \"mac\": \"02:AA:00:00:00:27\", \"device\": 5 },"
	"  { \"mac\": \"02:AA:00:00:00:28\", \"device\": \"v0\" },"
	"  { \"ip\": \"192.0.2.29\", \"device\": \"v0\" },"
	"  \"junk\" ]";

static const char hosts_leases[] =
	"{ \"02:AA:00:00:00:22\": { \"ip\": \"192.0.2.22\", \"hostname\": \"printer\" },"
	"  \"02:AA:00:00:00:05\": { \"ip\": \"192.0.2.5\", \"hostname\": \"laptop\" },"
	"  \"02:AA:00:00:00:30\": { \"ip\": \"192.0.2.30\", \"hostname\": \"tv\" },"
	"  \"02:AA:00:00:00:31\": { \"ip\": \"192.0.2.31\" },"
	"  \"02:AA:00:00:00:32\": { } }";

static const char hosts_ipv6[] =
	"{ \"02:AA:00:00:00:05\": [ \"2001:db8::5\" ],"
	"  \"02:AA:00:00:00:30\": [ \"2001:db8::30\" ],"
	"  \"02:AA:00:00:00:40\": [ \"2001:db8::40\" ],"
	"  \"02:AA:00:00:00:41\": [ \"2001:db8::41\" ] }";

static const char hosts_fdb[] =
	"{ \"02:AA:00:00:00:22\": \"v2\", \"02:AA:00:00:00:30\": \"v2\","
	"  \"02:AA:00:00:00:32\": \"v2\", \"02:AA:00:00:00:40\": \"v2\" }";

#define HOST(mac, v4, v6, name, dev, src) \
	"{ \"mac\": \"02:AA:00:00:00:" mac "\", \"ipv4_addresses\": " v4 ", \"ipv6_addresses\": " v6 "," \
	" \"hostname\": \"" name "\", \"device\": \"" dev "\", \"active\": true, \"address_source\": \"" src "\" }"

static void
hosts_expect(uc_vm_t *vm, const char *arp, const char *leases, const char *ipv6,
	     const char *fdb, const char *expected)
{
	uc_value_t *res = vm_call(vm, uc_ubbf_hosts_merge, 4,
				  arp ? vm_json(vm, arp) : NULL,
				  leases ? vm_json(vm, leases) : NULL,
				  ipv6 ? vm_json(vm, ipv6) : NULL,
				  fdb ? vm_json(vm, fdb) : NULL);

	assert_json_equal(vm, res, expected);
	ucv_put(res);
}

static void
test_hosts_merge(void **state)
{
	hosts_expect(*state, hosts_arp, hosts_leases, hosts_ipv6, hosts_fdb,
		"[ " HOST("05", "[ \"192.0.2.5\", \"192.0.2.55\" ]", "[ \"2001:db8::5\" ]", "laptop", "v0", "DHCP") ", "
		HOST("22", "[ \"192.0.2.22\" ]", "[ ]", "printer", "br0", "DHCP") ", "
		HOST("23", "[ \"192.0.2.23\" ]", "[ ]", "", "nope", "Static") ", "
		HOST("30", "[ \"192.0.2.30\" ]", "[ \"2001:db8::30\" ]", "tv", "", "DHCP") ", "
		HOST("32", "[ ]", "[ ]", "", "", "DHCP") ", "
		HOST("40", "[ ]", "[ \"2001:db8::40\" ]", "", "", "None") " ]");
}

static void
test_hosts_merge_args(void **state)
{
	uc_vm_t *vm = *state;

	hosts_expect(vm, NULL, NULL, NULL, NULL, "[ ]");
	hosts_expect(vm, "{ }", "[ ]", "[ ]", "[ ]", "[ ]");
	hosts_expect(vm, "[ { \"ip\": \"192.0.2.5\", \"mac\": \"02:AA:00:00:00:05\", \"device\": \"v0\" } ]",
		     NULL, NULL, NULL,
		     "[ " HOST("05", "[ \"192.0.2.5\" ]", "[ ]", "", "v0", "Static") " ]");

	/* without an FDB object only the ARP device decides */
	hosts_expect(vm, hosts_arp, hosts_leases, hosts_ipv6, "[ \"02:AA:00:00:00:22\" ]",
		     "[ " HOST("05", "[ \"192.0.2.5\", \"192.0.2.55\" ]", "[ \"2001:db8::5\" ]", "laptop", "v0", "DHCP") ", "
		     HOST("23", "[ \"192.0.2.23\" ]", "[ ]", "", "nope", "Static") " ]");

	hosts_expect(vm, "[ ]", hosts_leases, "[ ]", hosts_fdb,
		     "[ " HOST("22", "[ \"192.0.2.22\" ]", "[ ]", "printer", "", "DHCP") ", "
		     HOST("30", "[ \"192.0.2.30\" ]", "[ ]", "tv", "", "DHCP") ", "
		     HOST("32", "[ ]", "[ ]", "", "", "DHCP") " ]");
}

static const char l3_config[] =
	"{ \"Device\": { \"IP\": { \"Interface\": {"
	"  \"1\": { \"Name\": \"wan\", \"Upstream\": \"true\" },"
	"  \"2\": { \"Name\": \"lan\", \"Upstream\": \"false\" },"
	"  \"3\": { \"Name\": \"guest\" },"
	"  \"4\": { \"Name\": 5 },"
	"  \"6\": \"text\" } } } }";

static const char l3_netifd[] =
	"[ { \"name\": \"orphan\", \"addresses\": [ { \"ip\": \"198.51.100.1\", \"mask\": 24 } ] },"
	"  { \"addresses\": [ { \"ip\": \"192.0.2.1\", \"mask\": 24 } ] },"
	"  { \"name\": \"bad\", \"addresses\": \"192.0.2.1/24\" },"
	"  { \"name\": \"lan\", \"addresses\": [ { \"ip\": \"192.0.2.1\" }, { \"mask\": 24 },"
	"    { \"ip\": \"x.y\", \"mask\": 24 } ] },"
	"  { \"name\": \"wan\", \"addresses\": [ { \"ip\": \"203.0.113.2\", \"mask\": 24 } ],"
	"    \"ipv6_addresses\": [ { \"ip\": \"2001:db8:1::2\", \"mask\": 64 } ] },"
	"  { \"name\": \"lan\", \"addresses\": [ { \"ip\": \"192.168.1.1\", \"mask\": 24 },"
	"    { \"ip\": \"10.0.0.1\", \"mask\": 8 } ],"
	"    \"ipv6_addresses\": [ { \"ip\": \"2001:db8:2:10::1\", \"mask\": 62 },"
	"      { \"ip\": \"2001:db8:3::1\", \"mask\": 128 } ] },"
	"  { \"name\": \"guest\", \"addresses\": [ { \"ip\": \"192.168.2.1\", \"mask\": 32 } ] } ]";

static void
l3_expect(uc_vm_t *vm, const char *config, uc_value_t *ip, const char *netifd, const char *expected)
{
	uc_value_t *res = vm_call(vm, uc_ubbf_layer3_interface_find, 3,
				  config ? vm_json(vm, config) : NULL, ip,
				  netifd ? vm_json(vm, netifd) : NULL);

	assert_json_equal(vm, res, expected);
	ucv_put(res);
}

#define L3(path, up) "{ \"path\": \"" path "\", \"upstream\": " up " }"
#define L3_NONE L3("", "false")

static void
test_layer3_interface_find(void **state)
{
	uc_vm_t *vm = *state;

	l3_expect(vm, l3_config, ucv_string_new("203.0.113.77"), l3_netifd, L3("Device.IP.Interface.1", "true"));
	l3_expect(vm, l3_config, ucv_string_new("192.168.1.200"), l3_netifd, L3("Device.IP.Interface.2", "false"));
	l3_expect(vm, l3_config, ucv_string_new("10.200.3.4"), l3_netifd, L3("Device.IP.Interface.2", "false"));
	l3_expect(vm, l3_config, ucv_string_new("192.168.2.1"), l3_netifd, L3("Device.IP.Interface.3", "false"));
	l3_expect(vm, l3_config, ucv_string_new("192.168.2.2"), l3_netifd, L3_NONE);
	l3_expect(vm, l3_config, ucv_string_new("198.51.100.5"), l3_netifd, L3_NONE);
	l3_expect(vm, l3_config, ucv_string_new("192.0.2.1"), l3_netifd, L3_NONE);
	l3_expect(vm, l3_config, ucv_string_new("host.lan"), l3_netifd, L3_NONE);

	l3_expect(vm, l3_config, ucv_string_new("2001:db8:1::abcd"), l3_netifd, L3("Device.IP.Interface.1", "true"));
	l3_expect(vm, l3_config, ucv_string_new("2001:db8:2:13::5"), l3_netifd, L3("Device.IP.Interface.2", "false"));
	l3_expect(vm, l3_config, ucv_string_new("2001:db8:2:14::5"), l3_netifd, L3_NONE);
	l3_expect(vm, l3_config, ucv_string_new("2001:db8:3::1"), l3_netifd, L3("Device.IP.Interface.2", "false"));
	l3_expect(vm, l3_config, ucv_string_new("2001:db8:3::2"), l3_netifd, L3_NONE);

	l3_expect(vm, l3_config, ucv_string_new("8.8.8.8"),
		  "[ { \"name\": \"lan\", \"addresses\": [ { \"ip\": \"0.0.0.0\", \"mask\": 0 } ] } ]",
		  L3("Device.IP.Interface.2", "false"));
	l3_expect(vm, l3_config, ucv_string_new("2001:db8:9::1"),
		  "[ { \"name\": \"wan\", \"ipv6_addresses\": [ { \"ip\": \"::\", \"mask\": 0 } ] } ]",
		  L3("Device.IP.Interface.1", "true"));
}

static void
test_layer3_interface_find_args(void **state)
{
	uc_vm_t *vm = *state;

	l3_expect(vm, l3_config, NULL, l3_netifd, L3_NONE);
	l3_expect(vm, l3_config, ucv_int64_new(1), l3_netifd, L3_NONE);
	l3_expect(vm, l3_config, ucv_string_new(""), l3_netifd, L3_NONE);
	l3_expect(vm, l3_config, ucv_string_new("192.168.1.2"), NULL, L3_NONE);
	l3_expect(vm, l3_config, ucv_string_new("192.168.1.2"), "{ }", L3_NONE);
	l3_expect(vm, NULL, ucv_string_new("192.168.1.2"), l3_netifd, L3_NONE);
	l3_expect(vm, "{ \"Device\": { \"IP\": { \"Interface\": \"x\" } } }",
		  ucv_string_new("192.168.1.2"), l3_netifd, L3_NONE);
}

static void
primary_expect(uc_vm_t *vm, const char *host, const char *expected)
{
	uc_value_t *res = vm_call(vm, uc_ubbf_host_primary_ip, 1, host ? vm_json(vm, host) : NULL);

	assert_json_equal(vm, res, expected);
	ucv_put(res);
}

static void
test_host_primary_ip(void **state)
{
	uc_vm_t *vm = *state;

	primary_expect(vm, NULL, "\"\"");
	primary_expect(vm, "[ \"192.0.2.1\" ]", "\"\"");
	primary_expect(vm, "{ }", "\"\"");
	primary_expect(vm, "{ \"ipv4_addresses\": [ \"192.0.2.1\", \"192.0.2.2\" ],"
			   " \"ipv6_addresses\": [ \"2001:db8::1\" ] }", "\"192.0.2.1\"");
	primary_expect(vm, "{ \"ipv4_addresses\": [ ], \"ipv6_addresses\": [ \"2001:db8::1\", \"2001:db8::2\" ] }",
		       "\"2001:db8::1\"");
	primary_expect(vm, "{ \"ipv4_addresses\": \"192.0.2.1\", \"ipv6_addresses\": [ \"2001:db8::1\" ] }",
		       "\"2001:db8::1\"");
	primary_expect(vm, "{ \"ipv4_addresses\": [ ], \"ipv6_addresses\": [ ] }", "\"\"");
}

int
main(void)
{
	const struct CMUnitTest tests[] = {
		cmocka_unit_test(test_readfile_trim),
		cmocka_unit_test(test_readfile_int),
		cmocka_unit_test(test_uptime_read),
		cmocka_unit_test(test_operstate),
		cmocka_unit_test(test_netdev_read),
		cmocka_unit_test(test_link_properties),
		cmocka_unit_test(test_link_properties_args),
		cmocka_unit_test(test_ethernet_properties),
		cmocka_unit_test(test_arp_parse),
		cmocka_unit_test(test_bridge_fdb_parse),
		cmocka_unit_test(test_ipv6_neigh_parse),
		cmocka_unit_test(test_hosts_merge),
		cmocka_unit_test(test_hosts_merge_args),
		cmocka_unit_test(test_layer3_interface_find),
		cmocka_unit_test(test_layer3_interface_find_args),
		cmocka_unit_test(test_host_primary_ip),
	};

	return cmocka_run_group_tests(tests, group_setup, vm_teardown);
}
