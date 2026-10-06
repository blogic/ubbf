/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "filter.h"
#include "frame.h"
#include "msg.h"
#include "template.h"

static int failures;

#define CHECK(_cond) do {							\
	if (!(_cond)) {								\
		fprintf(stderr, "%s:%d: check failed: %s\n",			\
			__FILE__, __LINE__, #_cond);				\
		failures++;							\
	}									\
} while (0)

#define CHECK_STR(_a, _b) do {							\
	if (strcmp((_a), (_b))) {						\
		fprintf(stderr, "%s:%d: \"%s\" != \"%s\"\n",			\
			__FILE__, __LINE__, (_a), (_b));			\
		failures++;							\
	}									\
} while (0)

static struct log_msg msg;

static void
frame_parse(const char *frame, int default_pri)
{
	memset(&msg, 0, sizeof(msg));
	msg_from_frame(&msg, frame, strlen(frame), default_pri, "192.0.2.7", 1791786791);
}

static void
test_local(void)
{
	msg_from_local(&msg, 30, false, 1760000000, "dnsmasq[123]: query A x", "dut");
	CHECK_STR(msg.program, "dnsmasq");
	CHECK_STR(msg.pid, "123");
	CHECK_STR(msg.text, "query A x");
	CHECK_STR(msg.host, "dut");

	msg_from_local(&msg, 30, false, 1760000000, "netifd: Interface 'wan' is up", "dut");
	CHECK_STR(msg.program, "netifd");
	CHECK_STR(msg.pid, "");
	CHECK_STR(msg.text, "Interface 'wan' is up");

	msg_from_local(&msg, 30, false, 1760000000, "no tag here: at all", "dut");
	CHECK_STR(msg.program, "");
	CHECK_STR(msg.text, "no tag here: at all");

	msg_from_local(&msg, 6, true, 1760000000, "[ 12.345] eth0: link up", "dut");
	CHECK_STR(msg.program, "kernel");
	CHECK_STR(msg.text, "[ 12.345] eth0: link up");
	CHECK(msg.kernel);
}

static void
test_frames(void)
{
	frame_parse("<14>Oct 12 06:32:11 slot-1-dut tpltest: MARKER one\n", 13);
	CHECK(msg.pri == 14);
	CHECK_STR(msg.host, "slot-1-dut");
	CHECK_STR(msg.program, "tpltest");
	CHECK_STR(msg.text, "MARKER one");

	frame_parse("<38>Oct  2 06:32:11 sshd[42]: no host field", 13);
	CHECK_STR(msg.host, "192.0.2.7");
	CHECK_STR(msg.program, "sshd");
	CHECK_STR(msg.pid, "42");
	CHECK_STR(msg.text, "no host field");

	frame_parse("<14>1 2026-10-12T06:32:11.123456Z h5 rfctest 4711 - - RFC5424MARKER", 13);
	CHECK(msg.pri == 14);
	CHECK_STR(msg.host, "h5");
	CHECK_STR(msg.program, "rfctest");
	CHECK_STR(msg.pid, "4711");
	CHECK_STR(msg.text, "RFC5424MARKER");
	CHECK(msg.time == 1791786731);

	frame_parse("<14>1 2026-10-12T08:32:11+02:00 h5 app - id [a b=\"c\\]\"][d] \xef\xbb\xbftext", 13);
	CHECK_STR(msg.program, "app");
	CHECK_STR(msg.pid, "");
	CHECK_STR(msg.text, "text");
	CHECK(msg.time == 1791786731);

	frame_parse("plain text without header\r\n", 85);
	CHECK(msg.pri == 85);
	CHECK_STR(msg.host, "192.0.2.7");
	CHECK_STR(msg.text, "plain text without header");

	frame_parse("<999>bad pri", 13);
	CHECK(msg.pri == 13);
	CHECK_STR(msg.text, "<999>bad pri");
}

static void
test_framing(void)
{
	const char *f;
	size_t len, used;

	used = frame_next("<13>one\n<13>two", 15, false, &f, &len);
	CHECK(used == 8 && len == 7 && !strncmp(f, "<13>one", 7));
	CHECK(frame_next("<13>two", 7, false, &f, &len) == 0);
	CHECK(frame_next("<13>two", 7, true, &f, &len) == 7 && len == 7);

	used = frame_next("7 <13>abc8 <13>abcd", 19, false, &f, &len);
	CHECK(used == 9 && len == 7 && !strncmp(f, "<13>abc", 7));
	CHECK(frame_next("8 <13>abc", 9, false, &f, &len) == 0);
	CHECK(frame_next("12", 2, false, &f, &len) == 0);
}

static void
test_templates(void)
{
	char out[LINE_MAX_SIZE];

	setenv("TZ", "UTC", 1);
	tzset();

	frame_parse("<14>Oct 12 06:32:11 dut tpltest: say \"hi\" \\o/", 13);

	template_render("<$PRI>$ISODATE $HOST ubbftest:$MSGHDR$MSG", false, &msg, out, sizeof(out));
	CHECK_STR(out, "<14>2026-10-12T06:32:11+00:00 dut ubbftest:tpltest: say \"hi\" \\o/");

	template_render("${FACILITY}.${LEVEL} $MSG", true, &msg, out, sizeof(out));
	CHECK_STR(out, "user.info say \\\"hi\\\" \\\\o/");

	template_render("$UNKNOWN costs $5 ${NOPE", false, &msg, out, sizeof(out));
	CHECK_STR(out, "$UNKNOWN costs $5 ${NOPE");

	format_rfc3164(&msg, out, sizeof(out));
	CHECK_STR(out, "<14>Oct 12 06:32:11 dut tpltest: say \"hi\" \\o/");

	format_rfc5424(&msg, out, sizeof(out));
	CHECK_STR(out, "<14>1 2026-10-12T06:32:11+00:00 dut tpltest - - - say \"hi\" \\o/");

	format_file(&msg, out, sizeof(out));
	CHECK_STR(out, "Oct 12 06:32:11 dut tpltest: say \"hi\" \\o/");

	frame_parse("<13>Oct  2 06:32:11 dut x", 13);
	format_rfc3164(&msg, out, sizeof(out));
	CHECK_STR(out, "<13>Oct  2 06:32:11 dut x");
}

static void
test_filters(void)
{
	struct log_filter auth, err, block, stop, bad;
	struct log_filter *chain[3];

	/* facility auth (4), severities emerg..err */
	filter_init(&auth, 1, 1u << 4, 0x0f, NULL, FILTER_LOG);
	filter_init(&err, 2, 0, 0x0f, NULL, FILTER_LOG);
	filter_init(&block, 3, 0, FILTER_SEVERITIES_ALL, "^noise", FILTER_BLOCK);
	filter_init(&stop, 4, 0, FILTER_SEVERITIES_ALL, "STOPME", FILTER_STOP);
	CHECK(filter_init(&bad, 5, 0, FILTER_SEVERITIES_ALL, "(", FILTER_LOG) == -1);

	frame_parse("<35>Oct 12 06:32:11 dut sshd: auth error", 13);
	CHECK(filter_match(&auth, &msg));
	frame_parse("<36>Oct 12 06:32:11 dut sshd: auth warning", 13);
	CHECK(!filter_match(&auth, &msg));
	frame_parse("<11>Oct 12 06:32:11 dut x: user error", 13);
	CHECK(!filter_match(&auth, &msg));
	CHECK(filter_match(&err, &msg));
	CHECK(!filter_match(&bad, &msg));

	chain[0] = &err;
	chain[1] = &block;
	chain[2] = &stop;

	frame_parse("<11>Oct 12 06:32:11 dut x: fine", 13);
	CHECK(filter_chain_eval(chain, 3, &msg) == FILTER_DELIVER);
	frame_parse("<11>Oct 12 06:32:11 dut x: noise here", 13);
	CHECK(filter_chain_eval(chain, 3, &msg) == FILTER_SKIP);
	frame_parse("<14>Oct 12 06:32:11 dut x: info", 13);
	CHECK(filter_chain_eval(chain, 3, &msg) == FILTER_SKIP);
	frame_parse("<14>Oct 12 06:32:11 dut x: STOPME", 13);
	CHECK(filter_chain_eval(chain, 3, &msg) == FILTER_HALT);
	CHECK(filter_chain_eval(NULL, 0, &msg) == FILTER_DELIVER);

	filter_free(&auth);
	filter_free(&err);
	filter_free(&block);
	filter_free(&stop);
	filter_free(&bad);
}

static void
test_invalid_pattern(void)
{
	struct log_filter log, block, stop, block_auth;

	CHECK(filter_init(&log, 1, 0, FILTER_SEVERITIES_ALL, "(", FILTER_LOG) == -1);
	CHECK(filter_init(&block, 2, 0, FILTER_SEVERITIES_ALL, "(", FILTER_BLOCK) == -1);
	CHECK(filter_init(&stop, 3, 0, FILTER_SEVERITIES_ALL, "(", FILTER_STOP) == -1);
	CHECK(filter_init(&block_auth, 4, 1u << 4, FILTER_SEVERITIES_ALL, "(", FILTER_BLOCK) == -1);

	frame_parse("<11>Oct 12 06:32:11 dut x: secret", 13);
	CHECK(!filter_match(&log, &msg));
	CHECK(filter_match(&block, &msg));
	CHECK(filter_match(&stop, &msg));
	CHECK(!filter_match(&block_auth, &msg));

	filter_free(&log);
	filter_free(&block);
	filter_free(&stop);
	filter_free(&block_auth);
}

static void
test_control_chars(void)
{
	frame_parse("<13>Oct 12 06:32:11 dut x: one\n<13>Oct 12 06:32:11 forged y: two", 13);
	CHECK_STR(msg.host, "dut");
	CHECK_STR(msg.text, "one#012<13>Oct 12 06:32:11 forged y: two");

	frame_parse("<13>Oct 12 06:32:11 dut x: a\tb\x1b[31mc\x7f", 13);
	CHECK_STR(msg.text, "a#011b#033[31mc#177");

	frame_parse("<13>Oct 12 06:32:11 dut x: line\r\n", 13);
	CHECK_STR(msg.text, "line");

	msg_from_local(&msg, 30, false, 1760000000, "app: multi\nline", "dut");
	CHECK_STR(msg.text, "multi#012line");

	frame_parse("<13>Oct 12 06:32:11 dut x: \xc3\xbc", 13);
	CHECK_STR(msg.text, "\xc3\xbc");
}

int
main(void)
{
	test_local();
	test_frames();
	test_framing();
	test_templates();
	test_filters();
	test_invalid_pattern();
	test_control_chars();

	if (failures) {
		fprintf(stderr, "%d checks failed\n", failures);
		return 1;
	}

	printf("all checks passed\n");

	return 0;
}
