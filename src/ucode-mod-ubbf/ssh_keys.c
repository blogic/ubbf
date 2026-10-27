/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

/*
 * Check of an authorized_keys line of Device.SSH.Server.{i} before the
 * render deploys it to dropbear. The accepted key types and the minimum
 * RSA size stay in utils/ssh_keys.uc, which schema-gen.uc imports.
 */

#include "ubbf.h"
#include "bindings.h"

#include <libubox/utils.h>

#define KEY_LINE_MAX 8192

/* Fields of the wire-format blob of each key type, the type name included. */
static const struct {
	const char *type;
	size_t fields;
} blob_layouts[] = {
	{ "ssh-ed25519", 2 },
	{ "ssh-rsa", 3 },
	{ "sk-ssh-ed25519@openssh.com", 3 },
};

struct blob_field {
	const uint8_t *data;
	size_t len;
};

static size_t
blob_fields_expected(const char *type)
{
	for (size_t i = 0; i < ARRAY_SIZE(blob_layouts); i++)
		if (!strcmp(blob_layouts[i].type, type))
			return blob_layouts[i].fields;

	return 0;
}

/*
 * Splits a wire-format key blob into its length-prefixed fields. Returns
 * false when the blob is truncated or holds more than `max` fields.
 */
static bool
blob_split(const uint8_t *blob, size_t len, struct blob_field *fields, size_t max, size_t *count)
{
	uint64_t off = 0, field_len;

	for (*count = 0; off < len; (*count)++) {
		if (off + 4 > len || *count == max)
			return false;

		field_len = ((uint64_t)blob[off] << 24) | (blob[off + 1] << 16) |
			    (blob[off + 2] << 8) | blob[off + 3];
		off += 4;
		if (off + field_len > len)
			return false;

		fields[*count].data = blob + off;
		fields[*count].len = field_len;
		off += field_len;
	}

	return true;
}

/* Size in bits of an SSH mpint, from the highest set bit down. */
static unsigned int
mpint_bits(const struct blob_field *mpint)
{
	size_t i = 0;
	unsigned int bits;

	while (i < mpint->len && !mpint->data[i])
		i++;
	if (i == mpint->len)
		return 0;

	bits = (mpint->len - i) * 8;
	for (uint8_t top = mpint->data[i]; !(top & 0x80); top <<= 1)
		bits--;

	return bits;
}

static bool
type_accepted(uc_value_t *accepted, const char *type)
{
	uc_value_t *item;

	for (size_t i = 0; i < ucv_array_length(accepted); i++) {
		item = ucv_array_get(accepted, i);
		if (ucv_type(item) == UC_STRING && !strcmp(ucv_string_get(item), type))
			return true;
	}

	return false;
}

/*
 * Splits a key line into type, base64 blob and comment: the type is
 * [a-z0-9@.-]+, the blob [A-Za-z0-9+/=]+, and a comment starts with a
 * space or tab and holds printable ASCII after its leading blanks.
 */
static bool
key_line_split(const char *line, char **type, char **b64)
{
	size_t type_len = strspn(line, "abcdefghijklmnopqrstuvwxyz0123456789@.-");
	const char *p = line + type_len + strspn(line + type_len, " \t");
	size_t b64_len = strspn(p, "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=");
	const char *rest = p + b64_len;

	if (!type_len || p == line + type_len || !b64_len)
		return false;

	if (*rest) {
		if (*rest != ' ' && *rest != '\t')
			return false;

		for (rest += strspn(rest, " \t"); *rest; rest++)
			if (*rest < ' ' || *rest > '~')
				return false;
	}

	*type = strndup(line, type_len);
	*b64 = strndup(p, b64_len);

	return true;
}

static bool
key_blob_check(const char *type, const char *b64, double min_rsa_bits)
{
	size_t expected = blob_fields_expected(type), count, len;
	struct blob_field fields[4];
	uint8_t *blob;
	int n;
	bool ok;

	if (!expected)
		return false;

	len = B64_DECODE_LEN(strlen(b64));
	blob = xalloc(len);
	n = b64_decode(b64, blob, len);

	ok = n >= 0 && blob_split(blob, n, fields, ARRAY_SIZE(fields), &count) &&
	     count == expected && fields[0].len == strlen(type) &&
	     !memcmp(fields[0].data, type, fields[0].len);

	/* an ssh-rsa blob holds the type, the public exponent and the modulus */
	if (ok && !strcmp(type, "ssh-rsa") && mpint_bits(&fields[2]) < min_rsa_bits)
		ok = false;

	free(blob);

	return ok;
}

/**
 * ucode: `key_acceptable(key, accepted, min_rsa_bits)`, whether an
 * authorized_keys line may be deployed: its type is accepted, its blob is
 * well formed and of that type, and an RSA modulus has at least
 * `min_rsa_bits` bits. Embedded newlines and options prefixes (command=,
 * from=, ...) are rejected.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (3 expected: key line, accepted key
 *               types, minimum RSA modulus size)
 * @return       boolean
 */
uc_value_t *
uc_ubbf_key_acceptable(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *key = uc_fn_arg(0);
	char *type, *b64;
	const char *line;
	bool ok;

	if (ucv_type(key) != UC_STRING || !ucv_string_length(key) || ucv_string_length(key) > KEY_LINE_MAX)
		return ucv_boolean_new(false);

	line = ucv_string_get(key);
	if (strpbrk(line, "\r\n") || !key_line_split(line, &type, &b64))
		return ucv_boolean_new(false);

	ok = type_accepted(uc_fn_arg(1), type) &&
	     key_blob_check(type, b64, ucv_to_double(uc_fn_arg(2)));

	free(type);
	free(b64);

	return ucv_boolean_new(ok);
}
