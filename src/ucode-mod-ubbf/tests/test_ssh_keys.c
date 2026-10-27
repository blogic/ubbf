/* SPDX-License-Identifier: GPL-2.0-only */

/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

/*
 * ssh_keys.c: the check of an authorized_keys line, its type, its blob
 * and the size of an RSA modulus.
 */

#include "harness.h"
#include "ubbf.h"

static const char keys_js[] =
	"let u32 = (n) => sprintf('%c%c%c%c', (n >> 24) & 255, (n >> 16) & 255, (n >> 8) & 255, n & 255);"
	"let field = (s) => u32(length(s)) + s;"
	"let bytes = (n, first) => chr(first) + sprintf(`%${n - 1}s`, '');"
	"let rsa = (bits) => 'ssh-rsa ' + b64enc(field('ssh-rsa') + field('\\x01\\x00\\x01') +"
	"  field('\\x00' + bytes(bits / 8, 0x80)));"
	"let ed = 'ssh-ed25519 ' + b64enc(field('ssh-ed25519') + field(bytes(32, 1)));"
	"let ok = (key, min) => ubbf.key_acceptable(key, [ 'ssh-ed25519', 'ssh-rsa' ], min ?? 2048);";

static void
eval_expect(uc_vm_t *vm, const char *code, const char *expected)
{
	char buf[4096];
	uc_value_t *res;

	snprintf(buf, sizeof(buf), "%s%s", keys_js, code);
	res = vm_eval(vm, buf);
	assert_json_equal(vm, res, expected);
	ucv_put(res);
}

static void
test_key_lines(void **state)
{
	eval_expect(*state,
		"return [ ok(ed), ok(ed + ' user@host'), ok(ed + '\\t user host'), ok(replace(ed, ' ', '\\t')),"
		"  ok(ed + '\\n'), ok(ed + ' a\\tb'), ok('command=\"x\" ' + ed), ok(ed + '\\x00junk'),"
		"  ok(null), ok(''), ok('ssh-ed25519'), ok(ed + sprintf('%8200s', '')) ];",
		"[ true, true, true, true, false, false, false, true, false, false, false, false ]");
}

static void
test_blobs(void **state)
{
	eval_expect(*state,
		"let typed = (type, blob) => ubbf.key_acceptable(type + ' ' + b64enc(blob),"
		"  [ type ], 2048);"
		"return [ typed('ssh-ed25519', field('ssh-rsa') + field('k')),"
		"  typed('ssh-ed25519', field('ssh-ed25519')),"
		"  typed('ssh-ed25519', field('ssh-ed25519') + field('k') + field('x')),"
		"  typed('ssh-ed25519', substr(field('ssh-ed25519') + field('key'), 0, 20)),"
		"  typed('ssh-dss', field('ssh-dss') + field('k')),"
		"  typed('sk-ssh-ed25519@openssh.com', field('sk-ssh-ed25519@openssh.com') + field('k') + field('ssh:')),"
		"  ubbf.key_acceptable(ed, [ 'ssh-rsa' ], 0),"
		"  ubbf.key_acceptable('ssh-ed25519 !!!!', [ 'ssh-ed25519' ], 0) ];",
		"[ false, false, false, false, false, true, false, false ]");
}

static void
test_rsa_bits(void **state)
{
	eval_expect(*state,
		"return [ ok(rsa(2048)), ok(rsa(1024)), ok(rsa(4096), 4096), ok(rsa(2048), 2049),"
		"  ok(rsa(1024), 0), ubbf.key_acceptable(rsa(1024), [ 'ssh-rsa' ], null) ];",
		"[ true, false, true, false, true, true ]");
}

int
main(void)
{
	const struct CMUnitTest tests[] = {
		cmocka_unit_test(test_key_lines),
		cmocka_unit_test(test_blobs),
		cmocka_unit_test(test_rsa_bits),
	};

	return cmocka_run_group_tests(tests, vm_setup, vm_teardown);
}
