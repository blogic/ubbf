/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

/*
 * A cache of function results for one request: a get of a subtree calls
 * the same status function for many rows, and the results hold for 2 s.
 */

#include "ubbf.h"
#include "bindings.h"

#include <inttypes.h>
#include <libubox/uloop.h>

#define CACHE_REG	"ubbf.cache"
#define CACHE_FNS_REG	"ubbf.cache.fns"
#define CACHE_TTL_MS	2000

struct cache_timer {
	struct uloop_timeout timeout;
	uc_vm_t *vm;
};

static void
cache_clear(struct uloop_timeout *t)
{
	struct cache_timer *timer = container_of(t, struct cache_timer, timeout);

	uc_vm_registry_delete(timer->vm, CACHE_REG);
	uc_vm_registry_delete(timer->vm, CACHE_FNS_REG);
}

static struct cache_timer cache_timer = {
	.timeout.cb = cache_clear,
};

/**
 * The position of a function in the list of cached functions, or -1. A
 * function converts to its signature only, "(x) => { ... }", so the key
 * uses this position, which compares references.
 */
static int64_t
cache_fn_index(uc_value_t *fns, uc_value_t *fn)
{
	for (size_t i = 0; i < ucv_array_length(fns); i++)
		if (ucv_array_get(fns, i) == fn)
			return i;

	return -1;
}

static char *
cache_key(uc_vm_t *vm, int64_t idx, uc_value_t *args)
{
	char *json = ucv_to_jsonstring(vm, args);
	char *key;

	xasprintf(&key, "%" PRId64 "%s", idx, json);
	free(json);

	return key;
}

/**
 * Calls a function with caching. Results are cached for 2 seconds after
 * the first result goes into the cache; a result of null is cached too.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (function, then its arguments)
 * @return       cached or fresh result of fn(...args)
 */
uc_value_t *
uc_ubbf_cache_call(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *fn = uc_fn_arg(0);
	uc_value_t *cache = registry_get(vm, CACHE_REG, UC_OBJECT);
	uc_value_t *fns = registry_get(vm, CACHE_FNS_REG, UC_ARRAY);
	uc_value_t *args, *result, **argv;
	int64_t idx;
	bool found;
	char *key;

	if (!ucv_is_callable(fn)) {
		uc_vm_raise_exception(vm, EXCEPTION_TYPE, "cache_call: not a function");
		return NULL;
	}

	args = ucv_array_new(vm);
	for (size_t i = 1; i < nargs; i++)
		ucv_array_push(args, ucv_get(uc_fn_arg(i)));

	idx = cache_fn_index(fns, fn);
	if (idx < 0) {
		ucv_array_push(fns, ucv_get(fn));
		idx = ucv_array_length(fns) - 1;
	}

	key = cache_key(vm, idx, args);
	result = ucv_object_get(cache, key, &found);
	if (found) {
		free(key);
		ucv_put(args);
		return ucv_get(result);
	}

	if (!cache_timer.timeout.pending) {
		cache_timer.vm = vm;
		uloop_timeout_set(&cache_timer.timeout, CACHE_TTL_MS);
	}

	argv = xalloc(sizeof(*argv) * (nargs + 1));
	for (size_t i = 0; i < ucv_array_length(args); i++)
		argv[i] = ucv_array_get(args, i);

	result = callback_call(vm, NULL, fn, ucv_array_length(args), argv);
	free(argv);
	ucv_put(args);

	if (vm->exception.type != EXCEPTION_NONE) {
		free(key);
		return NULL;
	}

	ucv_object_add(cache, key, ucv_get(result));
	free(key);

	return result;
}

/**
 * Drops the cached results of a function, for all arguments. A caller
 * that changed the state behind fn calls this, so that the next
 * cache_call() in the same 2 seconds reads the new state.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: function)
 * @return       null
 */
uc_value_t *
uc_ubbf_cache_invalidate(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *cache = uc_vm_registry_get(vm, CACHE_REG);
	uc_value_t *fns = uc_vm_registry_get(vm, CACHE_FNS_REG);
	uc_value_t *stale = ucv_array_new(vm);
	uc_value_t *name;
	char prefix[32];
	size_t len;
	int64_t idx;

	idx = cache_fn_index(fns, uc_fn_arg(0));
	if (idx < 0 || !cache) {
		ucv_put(stale);
		return NULL;
	}

	len = snprintf(prefix, sizeof(prefix), "%" PRId64 "[", idx);

	ucv_object_foreach(cache, key, val) {
		(void)val;
		if (!strncmp(key, prefix, len))
			ucv_array_push(stale, ucv_string_new(key));
	}

	for (size_t i = 0; i < ucv_array_length(stale); i++) {
		name = ucv_array_get(stale, i);
		ucv_object_delete(cache, ucv_string_get(name));
	}

	ucv_put(stale);

	return NULL;
}
