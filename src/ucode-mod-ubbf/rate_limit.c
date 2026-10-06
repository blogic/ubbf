/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

#include "ubbf.h"

#define RATE_LIMIT_SLOTS  128
#define RATE_LIMIT_KEY    64

struct rate_limit_slot {
	char key[RATE_LIMIT_KEY];
	time_t window_start;
	int count;
};

static struct rate_limit_slot rate_limit_table[RATE_LIMIT_SLOTS];

/**
 * Returns a stable hash of `key` for bucket selection.
 */
static unsigned int
rate_limit_hash(const char *key)
{
	unsigned int h = 5381;
	for (; *key; key++)
		h = h * 33 + (unsigned char)*key;
	return h;
}

/**
 * Tests and consumes a per-key rate-limit slot.
 *
 * Maintains a module-global fixed-size table of `(key, window_start, count)`
 * triples. On call, locates the slot for `key` (empty slots reuse the first
 * match in a short linear probe starting at the hash bucket; full probe
 * chains evict the entry whose window has been expired the longest). When
 * the existing window has elapsed, or the key was unseen, the slot is
 * reinitialised to `{count = 1, window_start = now}` and the call returns
 * true. Otherwise the count is incremented and the call returns true while
 * the count is at or below `max`, false once the limit is exceeded.
 *
 * Defaults: `max = 5`, `window = 60` seconds. `key` is silently truncated to
 * 63 characters.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1-3 expected: key, optional max,
 *               optional window seconds)
 * @return       boolean indicating whether the caller may proceed
 */
uc_value_t *
uc_ubbf_rate_limit_check(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *key_val = uc_fn_arg(0);
	uc_value_t *max_val = uc_fn_arg(1);
	uc_value_t *window_val = uc_fn_arg(2);
	const char *key;
	int max = 5, window = 60;
	time_t now = time(NULL);
	unsigned int h, start, i;
	int oldest_i = -1;
	time_t oldest = now + 1;

	if (ucv_type(key_val) != UC_STRING)
		return ucv_boolean_new(false);

	key = ucv_string_get(key_val);
	if (ucv_type(max_val) == UC_INTEGER)
		max = (int)ucv_int64_get(max_val);
	if (ucv_type(window_val) == UC_INTEGER)
		window = (int)ucv_int64_get(window_val);

	h = rate_limit_hash(key);
	start = h % RATE_LIMIT_SLOTS;

	/* Linear probe over 16 slots; find match or track the entry whose
	 * window started earliest so we can evict it if no slot matches. */
	for (i = 0; i < 16; i++) {
		struct rate_limit_slot *s = &rate_limit_table[(start + i) % RATE_LIMIT_SLOTS];

		if (s->key[0] == '\0') {
			strncpy(s->key, key, RATE_LIMIT_KEY - 1);
			s->key[RATE_LIMIT_KEY - 1] = '\0';
			s->window_start = now;
			s->count = 1;
			return ucv_boolean_new(true);
		}

		if (strcmp(s->key, key) == 0) {
			if ((now - s->window_start) >= window) {
				s->window_start = now;
				s->count = 1;
				return ucv_boolean_new(true);
			}
			s->count++;
			return ucv_boolean_new(s->count <= max);
		}

		if (s->window_start < oldest) {
			oldest = s->window_start;
			oldest_i = (int)((start + i) % RATE_LIMIT_SLOTS);
		}
	}

	/* Probe full: evict the oldest entry and reuse its slot. */
	if (oldest_i >= 0) {
		struct rate_limit_slot *s = &rate_limit_table[oldest_i];
		strncpy(s->key, key, RATE_LIMIT_KEY - 1);
		s->key[RATE_LIMIT_KEY - 1] = '\0';
		s->window_start = now;
		s->count = 1;
		return ucv_boolean_new(true);
	}

	return ucv_boolean_new(false);
}
