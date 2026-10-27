/* SPDX-License-Identifier: GPL-2.0-only */

/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

/*
 * log.c and protocol.c. The log is read back from the stdio channel of
 * ulog, which a test opens before each case; the udebug ring has no reader
 * without udebugd, so the cases only show that writing to it is safe.
 */

#include "harness.h"
#include "ubbf.h"

#include <stdio.h>
#include <syslog.h>
#include <unistd.h>

#include <libubox/ulog.h>

static int saved_stderr = -1;
static FILE *capture;

static void
capture_start(void)
{
	capture = tmpfile();
	assert_non_null(capture);

	fflush(stderr);
	saved_stderr = dup(STDERR_FILENO);
	dup2(fileno(capture), STDERR_FILENO);

	ulog_open(ULOG_STDIO, LOG_DAEMON, "t");
}

static char *
capture_end(void)
{
	static char text[4096];
	size_t len;

	fflush(stderr);
	dup2(saved_stderr, STDERR_FILENO);
	close(saved_stderr);

	rewind(capture);
	len = fread(text, 1, sizeof(text) - 1, capture);
	text[len] = '\0';
	fclose(capture);

	return text;
}

static void
test_log_formats_as_sprintf(void **state)
{
	uc_vm_t *vm = *state;

	capture_start();
	ucv_put(vm_eval(vm,
		"ubbf.log_info('a %d %s %J', 5, 'x', { k: [ 1 ] });"
		"ubbf.log_warn('plain');"
		"ubbf.log_err('%s', null);"
		"ubbf.log_debug('d %d', 1);"));
	assert_string_equal(capture_end(),
		"t: a 5 x { \"k\": [ 1 ] }\n"
		"t: plain\n"
		"t: (null)\n"
		"t: DEBUG: d 1\n");
}

static void
test_log_from_c(void **state)
{
	(void)state;

	capture_start();
	ubbf_log(LOG_INFO, "c %d", 7);
	ubbf_log(LOG_DEBUG, "dbg %s", "x");
	assert_string_equal(capture_end(), "t: c 7\nt: DEBUG: dbg x\n");
}

static void
test_log_exception(void **state)
{
	uc_vm_t *vm = *state;
	const char *text, *line2;

	capture_start();
	ucv_put(vm_eval(vm, "try { die('boom'); } catch (e) { ubbf.log_exception('Device.X', e); }"));
	text = capture_end();

	assert_memory_equal(text, "t: EXCEPTION at path: Device.X\nt: Exception: boom\n",
			    strlen("t: EXCEPTION at path: Device.X\nt: Exception: boom\n"));
	line2 = strstr(text, "die('boom')");
	assert_non_null(line2);
}

static void
test_log_init_once(void **state)
{
	uc_vm_t *vm = *state;

	ubbf_log_init("ubbf-test");
	ubbf_log_init("other");
	ucv_put(vm_call(vm, uc_ubbf_log_init, 1, ucv_string_new("third")));

	/* The ring is set up now; a message goes to it and to the log. */
	capture_start();
	ubbf_log(LOG_INFO, "after init");
	assert_string_equal(capture_end(), "t: after init\n");
}

static void
test_active_protocol(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *res;
	struct stat st;
	bool cwmp = (stat("/usr/sbin/cwmpd", &st) == 0);

	assert_int_equal(ubbf_cwmp_mode(), cwmp);

	res = vm_call(vm, uc_ubbf_active_protocol, 0);
	assert_string_equal(ucv_string_get(res), cwmp ? "cwmp" : "usp");
	ucv_put(res);

	res = vm_call(vm, uc_ubbf_cwmp_mode, 0);
	assert_int_equal(ucv_boolean_get(res), cwmp);
	ucv_put(res);
}

int
main(void)
{
	const struct CMUnitTest tests[] = {
		cmocka_unit_test(test_log_formats_as_sprintf),
		cmocka_unit_test(test_log_from_c),
		cmocka_unit_test(test_log_exception),
		cmocka_unit_test(test_log_init_once),
		cmocka_unit_test(test_active_protocol),
	};

	return cmocka_run_group_tests(tests, vm_setup, vm_teardown);
}
