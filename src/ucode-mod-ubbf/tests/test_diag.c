/* SPDX-License-Identifier: GPL-2.0-only */

/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

/*
 * diag.c: curl_w_metrics_parse(), ping_output_parse() and
 * traceroute_output_parse() on curl -w, busybox and iputils output.
 */

#include "harness.h"
#include "ubbf.h"

#include <string.h>

static void
curl_expect(uc_vm_t *vm, uc_value_t *text, const char *expected)
{
	uc_value_t *res = vm_call(vm, uc_ubbf_curl_w_metrics_parse, 1, text);

	assert_json_equal(vm, res, expected);
	ucv_put(res);
}

static void
test_curl_metrics(void **state)
{
	uc_vm_t *vm = *state;

	curl_expect(vm, NULL, "{ }");
	curl_expect(vm, ucv_int64_new(5), "{ }");
	curl_expect(vm, ucv_string_new(""), "{ }");
	curl_expect(vm, ucv_string_new(
		"time_namelookup:0.001234\ntime_connect:0.012\ntime_starttransfer:0.150\n"
		"time_total:1.234\nsize_download:1048576\nhttp_code:200\n"),
		"{ \"time_namelookup\": \"0.001234\", \"time_connect\": \"0.012\","
		" \"time_starttransfer\": \"0.150\", \"time_total\": \"1.234\","
		" \"size_download\": \"1048576\", \"http_code\": \"200\" }");
	curl_expect(vm, ucv_string_new("one\n:value\n\nkey:x\nurl:http://h:8080/f"),
		"{ \"key\": \"x\", \"url\": \"http://h:8080/f\" }");
	curl_expect(vm, ucv_string_new("a:1\nb:2\na:3"), "{ \"a\": \"3\", \"b\": \"2\" }");
}

static void
test_curl_metrics_bounds(void **state)
{
	uc_vm_t *vm = *state;
	char text[600], key[64], val[256];
	uc_value_t *res, *got;

	memset(text, 'k', 70);
	text[70] = ':';
	memset(text + 71, 'v', 300);
	text[371] = '\0';

	memset(key, 'k', 63);
	key[63] = '\0';
	memset(val, 'v', 255);
	val[255] = '\0';

	res = vm_call(vm, uc_ubbf_curl_w_metrics_parse, 1, ucv_string_new(text));
	assert_int_equal(ucv_object_length(res), 1);
	got = ucv_object_get(res, key, NULL);
	assert_string_equal(ucv_string_get(got), val);
	ucv_put(res);
}

#define PING_DEFAULTS(status, ip, ok, fail) \
	"{ \"Status\": \"" status "\", \"IPAddressUsed\": \"" ip "\"," \
	" \"SuccessCount\": \"" ok "\", \"FailureCount\": \"" fail "\","

#define PING_RTT(avg, min, max, avg_us, min_us, max_us) \
	" \"AverageResponseTime\": \"" avg "\", \"MinimumResponseTime\": \"" min "\"," \
	" \"MaximumResponseTime\": \"" max "\", \"AverageResponseTimeDetailed\": \"" avg_us "\"," \
	" \"MinimumResponseTimeDetailed\": \"" min_us "\", \"MaximumResponseTimeDetailed\": \"" max_us "\" }"

#define PING_NO_RTT PING_RTT("0", "0", "0", "0", "0", "0")

static void
ping_expect(uc_vm_t *vm, uc_value_t *text, uc_value_t *count, const char *expected)
{
	uc_value_t *res = vm_call(vm, uc_ubbf_ping_output_parse, 2, text, count);

	assert_json_equal(vm, res, expected);
	ucv_put(res);
}

static void
test_ping_no_output(void **state)
{
	uc_vm_t *vm = *state;

	ping_expect(vm, NULL, ucv_int64_new(4), PING_DEFAULTS("Error_Other", "", "0", "4") PING_NO_RTT);
	ping_expect(vm, ucv_int64_new(1), NULL, PING_DEFAULTS("Error_Other", "", "0", "0") PING_NO_RTT);
	ping_expect(vm, ucv_string_new(""), ucv_string_new("4"),
		    PING_DEFAULTS("Error_Other", "", "0", "0") PING_NO_RTT);
	ping_expect(vm, ucv_string_new("ping: nohost.invalid: Name or service not known\n"),
		    ucv_int64_new(3), PING_DEFAULTS("Error_Other", "", "0", "3") PING_NO_RTT);
}

static void
test_ping_iputils(void **state)
{
	uc_vm_t *vm = *state;

	ping_expect(vm, ucv_string_new(
		"PING example.net (192.0.2.10) 56(84) bytes of data.\n"
		"64 bytes from 192.0.2.10: icmp_seq=1 ttl=56 time=10.1 ms\n"
		"64 bytes from 192.0.2.10: icmp_seq=2 ttl=56 time=12.7 ms\n"
		"64 bytes from 192.0.2.10: icmp_seq=3 ttl=56 time=11.6 ms\n"
		"\n"
		"--- example.net ping statistics ---\n"
		"3 packets transmitted, 3 received, 0% packet loss, time 2003ms\n"
		"rtt min/avg/max/mdev = 10.125/11.500/12.750/1.000 ms\n"),
		ucv_int64_new(3),
		PING_DEFAULTS("Complete", "192.0.2.10", "3", "0")
		PING_RTT("11", "10", "12", "11500", "10125", "12750"));

	ping_expect(vm, ucv_string_new(
		"PING 2001:db8::1(2001:db8::1) 56 data bytes\n"
		"--- 2001:db8::1 ping statistics ---\n"
		"5 packets transmitted, 3 received, 40% packet loss, time 4005ms\n"
		"rtt min/avg/max/mdev = 1.000/2.500/4.250/1.000 ms\n"),
		ucv_int64_new(5),
		PING_DEFAULTS("Complete", "2001:db8::1", "3", "2")
		PING_RTT("2", "1", "4", "2500", "1000", "4250"));

	ping_expect(vm, ucv_string_new(
		"PING 192.0.2.1 (192.0.2.1) 56(84) bytes of data.\n"
		"--- 192.0.2.1 ping statistics ---\n"
		"4 packets transmitted, 0 received, 100% packet loss, time 3062ms\n"),
		ucv_int64_new(4),
		PING_DEFAULTS("Error_Other", "192.0.2.1", "0", "4") PING_NO_RTT);
}

static void
test_ping_busybox(void **state)
{
	uc_vm_t *vm = *state;

	ping_expect(vm, ucv_string_new(
		"PING example.net (192.0.2.10): 56 data bytes\n"
		"64 bytes from 192.0.2.10: seq=0 ttl=56 time=10.250 ms\n"
		"64 bytes from 192.0.2.10: seq=1 ttl=56 time=12.750 ms\n"
		"\n"
		"--- example.net ping statistics ---\n"
		"2 packets transmitted, 2 packets received, 0% packet loss\n"
		"round-trip min/avg/max = 10.250/11.500/12.750 ms\n"),
		ucv_int64_new(2),
		PING_DEFAULTS("Complete", "192.0.2.10", "2", "0")
		PING_RTT("11", "10", "12", "11500", "10250", "12750"));

	ping_expect(vm, ucv_string_new(
		"PING 192.0.2.1 (192.0.2.1): 56 data bytes\n"
		"\n"
		"--- 192.0.2.1 ping statistics ---\n"
		"3 packets transmitted, 0 packets received, 100% packet loss\n"),
		ucv_int64_new(3),
		PING_DEFAULTS("Error_Other", "192.0.2.1", "0", "3") PING_NO_RTT);
}

static void
test_ping_partial(void **state)
{
	uc_vm_t *vm = *state;
	char text[200];

	ping_expect(vm, ucv_string_new("PING x (): 56 data bytes\n"), ucv_int64_new(1),
		    PING_DEFAULTS("Error_Other", "", "0", "1") PING_NO_RTT);
	ping_expect(vm, ucv_string_new("PING x (192.0.2.1: 56 data bytes\n"), ucv_int64_new(1),
		    PING_DEFAULTS("Error_Other", "", "0", "1") PING_NO_RTT);

	ping_expect(vm, ucv_string_new("2 packets transmitted\n"), ucv_int64_new(9),
		    PING_DEFAULTS("Error_Other", "", "0", "2") PING_NO_RTT);
	ping_expect(vm, ucv_string_new("round-trip min/avg/max = 1.0/2.0 ms\n"), ucv_int64_new(1),
		    PING_DEFAULTS("Error_Other", "", "0", "1") PING_NO_RTT);
	ping_expect(vm, ucv_string_new("rtt min/avg/max/mdev 1.0/2.0/3.0\n"), ucv_int64_new(1),
		    PING_DEFAULTS("Error_Other", "", "0", "1") PING_NO_RTT);

	/* the address buffer holds 63 characters */
	strcpy(text, "PING x (");
	memset(text + 8, 'a', 63);
	strcpy(text + 71, ")\n");
	ping_expect(vm, ucv_string_new(text), ucv_int64_new(1),
		    PING_DEFAULTS("Error_Other",
				  "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
				  "0", "1") PING_NO_RTT);

	memset(text + 8, 'a', 64);
	strcpy(text + 72, ")\n");
	ping_expect(vm, ucv_string_new(text), ucv_int64_new(1),
		    PING_DEFAULTS("Error_Other", "", "0", "1") PING_NO_RTT);
}

static void
trace_expect(uc_vm_t *vm, uc_value_t *text, const char *expected)
{
	uc_value_t *res = vm_call(vm, uc_ubbf_traceroute_output_parse, 1, text);

	assert_json_equal(vm, res, expected);
	ucv_put(res);
}

static void
test_traceroute_no_output(void **state)
{
	uc_vm_t *vm = *state;

	trace_expect(vm, NULL,
		"{ \"Status\": \"Error_Other\", \"IPAddressUsed\": \"\", \"ResponseTime\": \"0\" }");
	trace_expect(vm, ucv_int64_new(3),
		"{ \"Status\": \"Error_Other\", \"IPAddressUsed\": \"\", \"ResponseTime\": \"0\" }");
	trace_expect(vm, ucv_string_new(""),
		"{ \"Status\": \"Error_Other\", \"IPAddressUsed\": \"\", \"ResponseTime\": \"0\","
		" \"RouteHopsNumberOfEntries\": \"0\" }");
	trace_expect(vm, ucv_string_new(
		"traceroute: bad address 'nohost.invalid'\n"
		"traceroute to nohost, 30 hops max\n"
		"traceroute to y (192.0.2.99), 30 hops max\n"
		"traceroute to z (192.0.2.98), 30 hops max\n"
		"\n   \t\n"),
		"{ \"Status\": \"Error_Other\", \"IPAddressUsed\": \"192.0.2.99\", \"ResponseTime\": \"0\","
		" \"RouteHopsNumberOfEntries\": \"0\" }");
}

static void
test_traceroute_busybox(void **state)
{
	trace_expect(*state, ucv_string_new(
		"traceroute to example.net (192.0.2.10), 30 hops max, 38 byte packets\n"
		" 1  gw.lan (192.168.1.1)  1.000 ms  2.000 ms  3.000 ms\n"
		" 2  *  *  *\n"
		" 3  *  198.51.100.1 (198.51.100.1)  10.500 ms  11.500 ms\n"
		" 4  example.net (192.0.2.10)  20.000 ms  20.000 ms  20.000 ms\n"),
		"{ \"Status\": \"Complete\", \"IPAddressUsed\": \"192.0.2.10\", \"ResponseTime\": \"33\","
		" \"RouteHops.1.Host\": \"gw.lan\", \"RouteHops.1.HostAddress\": \"192.168.1.1\","
		" \"RouteHops.1.ErrorCode\": \"0\", \"RouteHops.1.RTTimes\": \"2\","
		" \"RouteHops.2.Host\": \"\", \"RouteHops.2.HostAddress\": \"\","
		" \"RouteHops.2.ErrorCode\": \"1\", \"RouteHops.2.RTTimes\": \"0\","
		" \"RouteHops.3.Host\": \"198.51.100.1\", \"RouteHops.3.HostAddress\": \"198.51.100.1\","
		" \"RouteHops.3.ErrorCode\": \"0\", \"RouteHops.3.RTTimes\": \"11\","
		" \"RouteHops.4.Host\": \"example.net\", \"RouteHops.4.HostAddress\": \"192.0.2.10\","
		" \"RouteHops.4.ErrorCode\": \"0\", \"RouteHops.4.RTTimes\": \"20\","
		" \"RouteHopsNumberOfEntries\": \"4\" }");
}

static void
test_traceroute_iputils(void **state)
{
	trace_expect(*state, ucv_string_new(
		"traceroute to 2001:db8::1 (2001:db8::1), 30 hops max, 80 byte packets\n"
		" 1  _gateway (2001:db8::fe)  1.000 ms  1.000 ms  1.000 ms\n"
		" 2  a.example (192.0.2.1)  5.000 ms b.example (192.0.2.2)  6.000 ms  7.000 ms\n"
		" 3  h (192.0.2.3)  3.000 ms !H  5.000 ms !H\n"
		"10  h10 (192.0.2.4)  ms\n"),
		"{ \"Status\": \"Complete\", \"IPAddressUsed\": \"2001:db8::1\", \"ResponseTime\": \"11\","
		" \"RouteHops.1.Host\": \"_gateway\", \"RouteHops.1.HostAddress\": \"2001:db8::fe\","
		" \"RouteHops.1.ErrorCode\": \"0\", \"RouteHops.1.RTTimes\": \"1\","
		" \"RouteHops.2.Host\": \"a.example\", \"RouteHops.2.HostAddress\": \"192.0.2.1\","
		" \"RouteHops.2.ErrorCode\": \"0\", \"RouteHops.2.RTTimes\": \"6\","
		" \"RouteHops.3.Host\": \"h\", \"RouteHops.3.HostAddress\": \"192.0.2.3\","
		" \"RouteHops.3.ErrorCode\": \"0\", \"RouteHops.3.RTTimes\": \"4\","
		" \"RouteHops.10.Host\": \"h10\", \"RouteHops.10.HostAddress\": \"192.0.2.4\","
		" \"RouteHops.10.ErrorCode\": \"1\", \"RouteHops.10.RTTimes\": \"0\","
		" \"RouteHopsNumberOfEntries\": \"4\" }");
}

static void
test_traceroute_numeric(void **state)
{
	trace_expect(*state, ucv_string_new(
		"traceroute to 192.0.2.10 (192.0.2.10), 30 hops max, 38 byte packets\n"
		" 1  192.168.1.1  1.000 ms  3.000 ms\n"
		" 2  192.0.2.10  4 ms\n"),
		"{ \"Status\": \"Complete\", \"IPAddressUsed\": \"192.0.2.10\", \"ResponseTime\": \"6\","
		" \"RouteHops.1.Host\": \"192.168.1.1\", \"RouteHops.1.HostAddress\": \"192.168.1.1\","
		" \"RouteHops.1.ErrorCode\": \"0\", \"RouteHops.1.RTTimes\": \"2\","
		" \"RouteHops.2.Host\": \"192.0.2.10\", \"RouteHops.2.HostAddress\": \"192.0.2.10\","
		" \"RouteHops.2.ErrorCode\": \"0\", \"RouteHops.2.RTTimes\": \"4\","
		" \"RouteHopsNumberOfEntries\": \"2\" }");
}

static void
test_traceroute_bounds(void **state)
{
	uc_vm_t *vm = *state;
	char text[400], host[80], addr[64];
	uc_value_t *res, *got;

	memset(host, 'h', 79);
	host[79] = '\0';
	memset(addr, '1', 63);
	addr[63] = '\0';

	strcpy(text, " 1  ");
	memset(text + 4, 'h', 100);
	strcpy(text + 104, " (");
	memset(text + 106, '1', 70);
	strcpy(text + 176, ")  1.000 ms\n");

	res = vm_call(vm, uc_ubbf_traceroute_output_parse, 1, ucv_string_new(text));
	got = ucv_object_get(res, "RouteHops.1.Host", NULL);
	assert_string_equal(ucv_string_get(got), host);
	got = ucv_object_get(res, "RouteHops.1.HostAddress", NULL);
	assert_string_equal(ucv_string_get(got), addr);
	got = ucv_object_get(res, "RouteHops.1.RTTimes", NULL);
	assert_string_equal(ucv_string_get(got), "1");
	ucv_put(res);
}

static void
test_ping_duplicates(void **state)
{
	/* a duplicate reply does not count as a probe */
	ping_expect(*state, ucv_string_new(
		"PING 192.0.2.1 (192.0.2.1) 56(84) bytes of data.\n"
		"\n"
		"--- 192.0.2.1 ping statistics ---\n"
		"3 packets transmitted, 4 received, +1 duplicates, 0% packet loss, time 2003ms\n"),
		ucv_int64_new(3),
		PING_DEFAULTS("Complete", "192.0.2.1", "3", "0") PING_NO_RTT);
}

static void
test_traceroute_names(void **state)
{
	/* the probe times follow the responder; "ms" inside a name is no
	 * time, and numeric output names an IPv6 responder without parens */
	trace_expect(*state, ucv_string_new(
		"traceroute to 2001:db8::1 (2001:db8::1), 30 hops max\n"
		" 1  r1.ms (192.0.2.1)  4.000 ms  6.000 ms\n"
		" 2  2001:db8::fe  1.000 ms  3.000 ms\n"
		" 3  fd00::1  2.000 ms\n"
		" 4  host7ms.example (192.0.2.7)  5.000 ms\n"),
		"{ \"Status\": \"Complete\", \"IPAddressUsed\": \"2001:db8::1\", \"ResponseTime\": \"14\","
		" \"RouteHops.1.Host\": \"r1.ms\", \"RouteHops.1.HostAddress\": \"192.0.2.1\","
		" \"RouteHops.1.ErrorCode\": \"0\", \"RouteHops.1.RTTimes\": \"5\","
		" \"RouteHops.2.Host\": \"2001:db8::fe\", \"RouteHops.2.HostAddress\": \"2001:db8::fe\","
		" \"RouteHops.2.ErrorCode\": \"0\", \"RouteHops.2.RTTimes\": \"2\","
		" \"RouteHops.3.Host\": \"fd00::1\", \"RouteHops.3.HostAddress\": \"fd00::1\","
		" \"RouteHops.3.ErrorCode\": \"0\", \"RouteHops.3.RTTimes\": \"2\","
		" \"RouteHops.4.Host\": \"host7ms.example\", \"RouteHops.4.HostAddress\": \"192.0.2.7\","
		" \"RouteHops.4.ErrorCode\": \"0\", \"RouteHops.4.RTTimes\": \"5\","
		" \"RouteHopsNumberOfEntries\": \"4\" }");
}

int
main(void)
{
	const struct CMUnitTest tests[] = {
		cmocka_unit_test(test_curl_metrics),
		cmocka_unit_test(test_curl_metrics_bounds),
		cmocka_unit_test(test_ping_no_output),
		cmocka_unit_test(test_ping_iputils),
		cmocka_unit_test(test_ping_busybox),
		cmocka_unit_test(test_ping_partial),
		cmocka_unit_test(test_traceroute_no_output),
		cmocka_unit_test(test_traceroute_busybox),
		cmocka_unit_test(test_traceroute_iputils),
		cmocka_unit_test(test_traceroute_numeric),
		cmocka_unit_test(test_traceroute_bounds),
		cmocka_unit_test(test_ping_duplicates),
		cmocka_unit_test(test_traceroute_names),
	};

	return cmocka_run_group_tests(tests, vm_setup, vm_teardown);
}
