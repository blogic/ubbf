/* SPDX-License-Identifier: GPL-2.0-only */

/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

/*
 * curl.c: the curl argument list, the credentials file, the result and
 * the exit status names. Runs isolated: a curl stand-in in /tmp logs its
 * arguments.
 */

#include "harness.h"
#include "ubbf.h"

#include <sys/stat.h>

#define STUB_DIR "/tmp/curl-stub"

static const char stub[] =
	"#!/bin/sh\n"
	": > " STUB_DIR "/log\n"
	"prev=\n"
	"for a in \"$@\"; do\n"
	"	if [ \"$prev\" = -K ]; then cat \"$a\"; else printf '%s\\n' \"$a\"; fi >> " STUB_DIR "/log\n"
	"	prev=\"$a\"\n"
	"done\n"
	"printf 'time_total:1.5\\n'\n"
	"exit 22\n";

static int
stub_setup(void **state)
{
	char path[256];
	FILE *fp;

	mkdir(STUB_DIR, 0755);
	fp = fopen(STUB_DIR "/curl", "w");
	if (!fp)
		return -1;
	fputs(stub, fp);
	fclose(fp);
	chmod(STUB_DIR "/curl", 0755);

	snprintf(path, sizeof(path), "%s:%s", STUB_DIR, getenv("PATH"));
	setenv("PATH", path, 1);

	return vm_setup(state);
}

static void
log_expect(const char *expected)
{
	char buf[1024];
	size_t n;
	FILE *fp = fopen(STUB_DIR "/log", "r");

	assert_non_null(fp);
	n = fread(buf, 1, sizeof(buf) - 1, fp);
	fclose(fp);
	buf[n] = '\0';

	/* the upload URL at the end carries the time */
	if (n > strlen(expected))
		buf[strlen(expected)] = '\0';

	assert_string_equal(buf, expected);
}

static void
eval_expect(uc_vm_t *vm, const char *code, const char *expected)
{
	uc_value_t *res = vm_eval(vm, code);

	assert_json_equal(vm, res, expected);
	ucv_put(res);
}

static void
test_status(void **state)
{
	eval_expect(*state,
		"return [ map([ 0, 6, 7, 18, 22, 28, 35, null, '6' ], (c) => ubbf.curl_exit_to_status(c)),"
		"  ubbf.CURL_TRANSFER_TIMEOUT_S, ubbf.curl_send('GET', 'http://h/', '/tmp/x', null) ];",
		"[ [ \"Complete\", \"Error_CannotResolveHostName\", \"Error_InitConnectionFailed\", \"Error_IncorrectSize\", "
		"\"Error_NoResponse\", \"Error_Timeout\", \"Error_Other\", \"Error_Other\", \"Error_CannotResolveHostName\" ], 1800, "
		"{ \"success\": false, \"exitcode\": -1, \"output\": \"unsupported method GET\", \"metrics\": null } ]");
}

static void
test_download(void **state)
{
	eval_expect(*state,
		"return ubbf.curl_download('-u', '/tmp/out', { username: 'a\"b', password: 'p', timeout: '30', headers: { X: 'y' },"
		"  format_string: 'time_total:%{time_total}' });",
		"{ \"success\": false, \"exitcode\": 22, \"output\": \"time_total:1.5\\n\", \"metrics\": { \"time_total\": \"1.5\" } }");
	log_expect("--fail\n--silent\n-K\nuser = \"a\\\"b:p\"\n--max-time\n30\n-H\nX: y\n"
		   "-w\ntime_total:%{time_total}\n-o\n/tmp/out\n--url\n-u\n");
}

static void
test_upload(void **state)
{
	eval_expect(*state,
		"let r = ubbf.curl_upload('http://h/up/', '/tmp/dir/f.bin', { extension: '.tgz', command_key: 'k' });"
		"return match(r.url, /^http:\\/\\/h\\/up\\/[0-9]+-unknown-unknown-f\\.bin$/) != null;",
		"true");
	log_expect("--fail\n--silent\n-H\nX-ubbf-key: k\n-H\nX-ubbf-extension: tgz\n-T\n/tmp/dir/f.bin\n--url\n");
}

int
main(void)
{
	const struct CMUnitTest tests[] = {
		cmocka_unit_test(test_status),
		cmocka_unit_test(test_download),
		cmocka_unit_test(test_upload),
	};

	return cmocka_run_group_tests(tests, stub_setup, vm_teardown);
}
