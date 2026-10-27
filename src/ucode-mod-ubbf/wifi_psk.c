/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

/*
 * The WPA2 pre-shared key of a passphrase: PBKDF2 with HMAC-SHA1, the SSID
 * as salt, 4096 iterations, 256 bits (802.11-2024 J.4.1, RFC 2898).
 */

#include "ubbf.h"
#include "bindings.h"

#include <sha1.h>

#define PSK_ITERATIONS	4096
#define PSK_HEX_LEN	64
#define PSK_CACHE_SIZE	32

struct hmac_sha1 {
	SHA1_CTX inner;
	SHA1_CTX outer;
};

/* The get handlers ask for the key of every AccessPoint on each read. */
static struct {
	char *passphrase;
	char *ssid;
	size_t passphrase_len;
	size_t ssid_len;
	char psk[PSK_HEX_LEN + 1];
} psk_cache[PSK_CACHE_SIZE];

static size_t psk_cache_next;

/* A key longer than the block is cut, not hashed: the passphrase has at
 * most 63 characters. */
static void
hmac_init(struct hmac_sha1 *h, const uint8_t *key, size_t len)
{
	uint8_t pad[SHA1_BLOCK_LENGTH];

	for (size_t i = 0; i < SHA1_BLOCK_LENGTH; i++)
		pad[i] = ((i < len) ? key[i] : 0) ^ 0x36;
	SHA1Init(&h->inner);
	SHA1Update(&h->inner, pad, sizeof(pad));

	for (size_t i = 0; i < SHA1_BLOCK_LENGTH; i++)
		pad[i] = ((i < len) ? key[i] : 0) ^ 0x5c;
	SHA1Init(&h->outer);
	SHA1Update(&h->outer, pad, sizeof(pad));
}

static void
hmac_run(const struct hmac_sha1 *h, const uint8_t *msg, size_t len, uint8_t out[SHA1_DIGEST_LENGTH])
{
	SHA1_CTX ctx = h->inner;

	SHA1Update(&ctx, msg, len);
	SHA1Final(out, &ctx);

	ctx = h->outer;
	SHA1Update(&ctx, out, SHA1_DIGEST_LENGTH);
	SHA1Final(out, &ctx);
}

static void
psk_derive(const char *passphrase, size_t passphrase_len, const char *ssid, size_t ssid_len,
	   char hex[PSK_HEX_LEN + 1])
{
	uint8_t u[SHA1_DIGEST_LENGTH], t[SHA1_DIGEST_LENGTH], out[2 * SHA1_DIGEST_LENGTH];
	uint8_t *salt = xalloc(ssid_len + 4);
	struct hmac_sha1 h;

	hmac_init(&h, (const uint8_t *)passphrase, passphrase_len);
	memcpy(salt, ssid, ssid_len);

	for (uint8_t block = 1; block <= 2; block++) {
		salt[ssid_len] = salt[ssid_len + 1] = salt[ssid_len + 2] = 0;
		salt[ssid_len + 3] = block;

		hmac_run(&h, salt, ssid_len + 4, u);
		memcpy(t, u, sizeof(t));

		for (int i = 1; i < PSK_ITERATIONS; i++) {
			hmac_run(&h, u, sizeof(u), u);
			for (size_t j = 0; j < sizeof(t); j++)
				t[j] ^= u[j];
		}

		memcpy(out + (block - 1) * SHA1_DIGEST_LENGTH, t, sizeof(t));
	}

	free(salt);

	for (size_t i = 0; i < PSK_HEX_LEN / 2; i++)
		snprintf(hex + 2 * i, 3, "%02x", out[i]);
}

static const char *
psk_cache_find(const char *passphrase, size_t passphrase_len, const char *ssid, size_t ssid_len)
{
	for (size_t i = 0; i < PSK_CACHE_SIZE; i++) {
		if (!psk_cache[i].ssid || psk_cache[i].passphrase_len != passphrase_len ||
		    psk_cache[i].ssid_len != ssid_len)
			continue;

		if (!memcmp(psk_cache[i].passphrase, passphrase, passphrase_len) &&
		    !memcmp(psk_cache[i].ssid, ssid, ssid_len))
			return psk_cache[i].psk;
	}

	return NULL;
}

static const char *
psk_cache_add(const char *passphrase, size_t passphrase_len, const char *ssid, size_t ssid_len)
{
	size_t slot = psk_cache_next++ % PSK_CACHE_SIZE;

	free(psk_cache[slot].passphrase);
	free(psk_cache[slot].ssid);

	psk_cache[slot].passphrase = xalloc(passphrase_len + 1);
	memcpy(psk_cache[slot].passphrase, passphrase, passphrase_len);
	psk_cache[slot].passphrase_len = passphrase_len;
	psk_cache[slot].ssid = xalloc(ssid_len + 1);
	memcpy(psk_cache[slot].ssid, ssid, ssid_len);
	psk_cache[slot].ssid_len = ssid_len;

	psk_derive(passphrase, passphrase_len, ssid, ssid_len, psk_cache[slot].psk);

	return psk_cache[slot].psk;
}

/**
 * ucode: `wpa_psk(passphrase, ssid)`, the WPA2 pre-shared key of a
 * passphrase. A passphrase that is not a string counts as empty; an SSID
 * that is not a string counts as its string form, as in `ssid + ...`.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (2 expected: passphrase of 8 to 63
 *               characters, SSID of the BSS)
 * @return       64 hex digits
 */
uc_value_t *
uc_ubbf_wpa_psk(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *passphrase = uc_fn_arg(0), *ssid = uc_fn_arg(1);
	const char *pass = "", *salt, *psk;
	size_t pass_len = 0, salt_len;
	char *salt_text = NULL;

	if (ucv_type(passphrase) == UC_STRING) {
		pass = ucv_string_get(passphrase);
		pass_len = ucv_string_length(passphrase);
	}

	if (ucv_type(ssid) == UC_STRING) {
		salt = ucv_string_get(ssid);
		salt_len = ucv_string_length(ssid);
	} else {
		salt = salt_text = ucv_to_string(vm, ssid);
		salt_len = strlen(salt_text);
	}

	psk = psk_cache_find(pass, pass_len, salt, salt_len);
	if (!psk)
		psk = psk_cache_add(pass, pass_len, salt, salt_len);

	free(salt_text);

	return ucv_string_new(psk);
}
