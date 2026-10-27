/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

/*
 * Stable instance numbers for tables whose rows the CPE builds from the
 * devices present (cages, USB devices, modems, hosts). TR-369 R-ARC.8: an
 * instance number does not change until its object is deleted, so a row
 * keeps its number while other rows come and go, and a number is not given
 * to another device. The map keeps a key per device, for example a cage
 * name, and the next free number of each table.
 *
 * The map lives in /tmp only: a reboot ends a row that no configuration
 * points at, so it may come back with another number. The rows that the
 * configuration stores or names keep their numbers through pins, which
 * config.json carries in its `_instances` section (instance_pins_new()).
 *
 * Each entry holds its number and when a read last saw its key. A key that
 * no read saw for EXPIRE_S leaves the map, so a table of clients that come
 * and go does not grow until the next reboot; the next free number stays,
 * so the number is not given to another row. Pinned keys stay.
 *
 * Only the agent gives numbers: datamodel.uc calls instance_map_own(true).
 * In another process (apply, ubbf-device) the functions read the numbers
 * that the agent wrote and change nothing, except the seed from the pins
 * after a reboot, which the first reader writes.
 */

#include "ubbf.h"
#include "bindings.h"

#include <inttypes.h>
#include <syslog.h>

#define MAP_DIR		"/tmp/ubbf"
#define MAP_PATH	MAP_DIR "/instance-map.json"
#define CONFIG_PATH	"/etc/ubbf/config.json"

#define MAP_REG		"ubbf.imap"
#define MAP_ID_REG	"ubbf.imap.id"

/* last_seen is refreshed only when it is older than SEEN_STEP_S, so that a
 * read does not write the map each time. The clock is monotonic: the map
 * lives only until the next reboot. */
#define EXPIRE_S	86400
#define SEEN_STEP_S	(EXPIRE_S / 8)

static bool map_owner;

static int64_t
uptime(void)
{
	struct timespec ts;

	clock_gettime(CLOCK_MONOTONIC, &ts);
	return ts.tv_sec;
}

static int64_t
int_get(uc_value_t *obj, const char *key)
{
	uc_value_t *val = ucv_object_get(obj, key, NULL);

	return (ucv_type(val) == UC_INTEGER) ? ucv_int64_get(val) : 0;
}

/* An instance number from an integer or a decimal string, else -1. */
static int64_t
number_arg(uc_value_t *val)
{
	const char *s;
	char *end;
	long long n;

	if (ucv_type(val) == UC_INTEGER)
		return ucv_int64_get(val);

	if (ucv_type(val) != UC_STRING)
		return -1;

	s = ucv_string_get(val);
	if (!*s)
		return -1;

	n = strtoll(s, &end, 10);
	return *end ? -1 : n;
}

/* The key of a row as a string, copied: libucode keeps a short string
 * inside the value, so a pointer to it is valid only while the variable
 * that holds the value is. The caller frees the copy. */
static char *
key_dup(uc_vm_t *vm, uc_value_t *val)
{
	if (ucv_type(val) == UC_STRING)
		return xstrdup(ucv_string_get(val));

	return ucv_to_string(vm, val);
}

static void
maps_store(uc_vm_t *vm, uc_value_t *maps)
{
	char id[64], *json, *text;
	int len;

	mkdir(MAP_DIR, 0755);

	json = ucv_to_jsonstring_formatted(vm, maps, '\t', 0);
	len = xasprintf(&text, "%s\n", json);
	free(json);

	if (!file_write_atomic(MAP_PATH, text, len, 0644))
		ubbf_log(LOG_ERR, "instance map: failed to write %s", MAP_PATH);
	free(text);

	file_id(MAP_PATH, id, sizeof(id));
	uc_vm_registry_set(vm, MAP_ID_REG, ucv_string_new(id));
}

static bool pins_load(uc_vm_t *vm, uc_value_t *maps, uc_value_t *pins);

/*
 * The agent numbers the rows, and the render and ubbf-device read the
 * numbers, so a process reads the file again when another one wrote it.
 * After a reboot the first process to come seeds the map from the pins of
 * config.json, so that a render before the agent starts finds them.
 */
static uc_value_t *
maps_load(uc_vm_t *vm)
{
	uc_value_t *maps = uc_vm_registry_get(vm, MAP_REG);
	uc_value_t *old_id = uc_vm_registry_get(vm, MAP_ID_REG);
	uc_value_t *config;
	char id[64];

	file_id(MAP_PATH, id, sizeof(id));
	if (maps && ucv_type(old_id) == UC_STRING && !strcmp(ucv_string_get(old_id), id))
		return maps;

	maps = id[0] ? json_file_load_object(vm, MAP_PATH) : ucv_object_new(vm);
	uc_vm_registry_set(vm, MAP_REG, maps);
	uc_vm_registry_set(vm, MAP_ID_REG, ucv_string_new(id));

	if (!id[0]) {
		config = json_file_load(vm, CONFIG_PATH);
		if (pins_load(vm, maps, ucv_object_get(config, "_instances", NULL)))
			maps_store(vm, maps);
		ucv_put(config);
	}

	return maps;
}

static uc_value_t *
table_map(uc_vm_t *vm, uc_value_t *maps, const char *table)
{
	uc_value_t *map = ucv_object_get(maps, table, NULL);

	if (ucv_type(map) == UC_OBJECT)
		return map;

	map = ucv_object_new(vm);
	ucv_object_add(map, "next", ucv_int64_new(1));
	ucv_object_add(map, "keys", ucv_object_new(vm));
	ucv_object_add(maps, table, map);

	return map;
}

static int64_t
number_take(uc_value_t *map, int64_t floor)
{
	int64_t next = int_get(map, "next");
	int64_t n = (floor > next) ? floor : next;

	if (n < 1)
		n = 1;

	ucv_object_add(map, "next", ucv_int64_new(n + 1));
	return n;
}

static uc_value_t *
entry_new(uc_vm_t *vm, int64_t n, int64_t last_seen)
{
	uc_value_t *entry = ucv_object_new(vm);

	ucv_object_add(entry, "n", ucv_int64_new(n));
	if (last_seen >= 0)
		ucv_object_add(entry, "last_seen", ucv_int64_new(last_seen));

	return entry;
}

/* Numbers a key that is new and refreshes last_seen of a known one. */
static bool
key_see(uc_vm_t *vm, uc_value_t *map, const char *key, int64_t floor, int64_t now)
{
	uc_value_t *keys = ucv_object_get(map, "keys", NULL);
	uc_value_t *entry = ucv_object_get(keys, key, NULL);
	uc_value_t *seen;

	if (ucv_type(entry) != UC_OBJECT) {
		ucv_object_add(keys, key, entry_new(vm, number_take(map, floor), now));
		return true;
	}

	seen = ucv_object_get(entry, "last_seen", NULL);
	if (ucv_type(seen) == UC_INTEGER && now - ucv_int64_get(seen) < SEEN_STEP_S)
		return false;

	ucv_object_add(entry, "last_seen", ucv_int64_new(now));
	return true;
}

/* A retired key (#n) keeps its number reserved for good. */
static bool
keys_expire(uc_vm_t *vm, const char *table, uc_value_t *map, int64_t now)
{
	uc_value_t *keys = ucv_object_get(map, "keys", NULL);
	uc_value_t *stale = ucv_array_new(vm), *config = NULL, *pinned = NULL;
	bool changed = false;

	ucv_object_foreach(keys, key, entry) {
		uc_value_t *seen = ucv_object_get(entry, "last_seen", NULL);

		if (key[0] == '#' || ucv_type(seen) != UC_INTEGER)
			continue;
		if (now - ucv_int64_get(seen) > EXPIRE_S)
			ucv_array_push(stale, ucv_string_new(key));
	}

	if (ucv_array_length(stale)) {
		config = json_file_load(vm, CONFIG_PATH);
		pinned = ucv_object_get(ucv_object_get(config, "_instances", NULL), table, NULL);
	}

	for (size_t i = 0; i < ucv_array_length(stale); i++) {
		uc_value_t *key_val = ucv_array_get(stale, i);
		const char *key = ucv_string_get(key_val);
		bool is_pinned = false;

		ucv_object_foreach(pinned, n, pin) {
			(void)n;
			if (ucv_type(pin) == UC_STRING && !strcmp(ucv_string_get(pin), key))
				is_pinned = true;
		}

		if (is_pinned)
			ucv_object_add(ucv_object_get(keys, key, NULL), "last_seen", ucv_int64_new(now));
		else
			ucv_object_delete(keys, key);

		changed = true;
	}

	ucv_put(config);
	ucv_put(stale);
	return changed;
}

static int64_t
known_number(uc_value_t *maps, const char *table, const char *key)
{
	uc_value_t *keys = ucv_object_get(ucv_object_get(maps, table, NULL), "keys", NULL);
	uc_value_t *entry = ucv_object_get(keys, key, NULL);

	return (ucv_type(entry) == UC_OBJECT) ? int_get(entry, "n") : 0;
}

/*
 * The numbers of the keys present: key to number, in the order of `keys`.
 * The owner gives new keys numbers and removes stale ones; another process
 * leaves out the keys the map does not hold.
 */
static uc_value_t *
numbers_get(uc_vm_t *vm, const char *table, uc_value_t *keys, int64_t floor, bool expire)
{
	uc_value_t *maps = maps_load(vm), *map = NULL, *numbers = ucv_object_new(vm);
	int64_t now = uptime(), n;
	bool changed = false;

	if (map_owner) {
		map = table_map(vm, maps, table);

		for (size_t i = 0; i < ucv_array_length(keys); i++) {
			char *key = key_dup(vm, ucv_array_get(keys, i));

			if (key_see(vm, map, key, floor, now))
				changed = true;
			free(key);
		}

		if (expire && keys_expire(vm, table, map, now))
			changed = true;

		if (changed)
			maps_store(vm, maps);
	}

	for (size_t i = 0; i < ucv_array_length(keys); i++) {
		char *key = key_dup(vm, ucv_array_get(keys, i));

		n = known_number(maps, table, key);
		if (n > 0)
			ucv_object_add(numbers, key, ucv_int64_new(n));
		free(key);
	}

	return numbers;
}

/**
 * The number of a new row in a table on the map, for dm.object_add(): the
 * next free number, at least `floor`, so that no row the CPE finds gets it
 * later.
 *
 * @param vm     ucode VM context
 * @param table  table path
 * @param floor  one above the highest stored row
 * @return       the number, or 0 when the map does not number the table
 */
int64_t
instance_map_add_number(uc_vm_t *vm, const char *table, int64_t floor)
{
	uc_value_t *maps = maps_load(vm);
	uc_value_t *map = ucv_object_get(maps, table, NULL);
	int64_t n;

	if (!map_owner || ucv_type(map) != UC_OBJECT)
		return 0;

	n = number_take(map, floor);
	maps_store(vm, maps);
	return n;
}

/* The table path of a binding. The string lives in table_val (see
 * key_dup()), so the pointer is valid while the binding runs. */
#define TABLE_ARG(table)						\
	uc_value_t *table##_val = uc_fn_arg(0);				\
	const char *table = (ucv_type(table##_val) == UC_STRING)	\
		? ucv_string_get(table##_val) : NULL

static int64_t
floor_arg(uc_value_t *val)
{
	return (ucv_type(val) == UC_INTEGER) ? ucv_int64_get(val) : 1;
}

/**
 * ucode: `instance_map_own(owner)`: whether this process gives numbers.
 * Only the agent does; datamodel.uc sets it at start-up.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: boolean)
 * @return       null
 */
uc_value_t *
uc_ubbf_instance_map_own(uc_vm_t *vm, size_t nargs)
{
	map_owner = ucv_is_truish(uc_fn_arg(0));
	return NULL;
}

/**
 * ucode: `instance_numbers(table, keys, floor)`. Returns the instance number
 * of each key, giving new keys the next free numbers in the order of
 * `keys`. A first call thus numbers the rows as their position did. The
 * keys of absent rows that no read saw for a day leave the map, so `keys`
 * must hold every row present. Outside the agent the result holds only the
 * keys the map holds.
 *
 * @param vm     ucode VM context
 * @param nargs  table path (with the numbers of its parent rows), array of
 *               the stable keys of the rows present, optional floor: the
 *               lowest number a new key may take, one above the highest
 *               stored row, so that the rows the CPE finds follow them
 * @return       object key to instance number
 */
uc_value_t *
uc_ubbf_instance_numbers(uc_vm_t *vm, size_t nargs)
{
	TABLE_ARG(table);

	if (!table)
		return ucv_object_new(vm);

	return numbers_get(vm, table, uc_fn_arg(1), floor_arg(uc_fn_arg(2)), true);
}

/**
 * ucode: `instance_numbers_known(table, keys)`: the numbers the map holds
 * for keys, without numbering new keys.
 *
 * @param vm     ucode VM context
 * @param nargs  table path, array of keys
 * @return       object key to instance number, for the keys the map holds
 */
uc_value_t *
uc_ubbf_instance_numbers_known(uc_vm_t *vm, size_t nargs)
{
	TABLE_ARG(table);
	uc_value_t *keys = uc_fn_arg(1), *maps, *numbers = ucv_object_new(vm);
	int64_t n;

	if (!table)
		return numbers;

	maps = maps_load(vm);
	for (size_t i = 0; i < ucv_array_length(keys); i++) {
		char *key = key_dup(vm, ucv_array_get(keys, i));

		n = known_number(maps, table, key);
		if (n > 0)
			ucv_object_add(numbers, key, ucv_int64_new(n));
		free(key);
	}

	return numbers;
}

/**
 * ucode: `instance_number(table, key)`: the number of one row, for a caller
 * that does not know the other rows present; it removes no key.
 *
 * @param vm     ucode VM context
 * @param nargs  table path, key
 * @return       the number, or null outside the agent for an unknown key
 */
uc_value_t *
uc_ubbf_instance_number(uc_vm_t *vm, size_t nargs)
{
	TABLE_ARG(table);
	uc_value_t *keys, *numbers, *n;
	char *key;

	if (!table || !uc_fn_arg(1))
		return NULL;

	keys = ucv_array_new(vm);
	ucv_array_push(keys, ucv_get(uc_fn_arg(1)));
	numbers = numbers_get(vm, table, keys, 1, false);

	key = key_dup(vm, uc_fn_arg(1));
	n = ucv_get(ucv_object_get(numbers, key, NULL));
	free(key);

	ucv_put(numbers);
	ucv_put(keys);
	return n;
}

/* Drops the keys that are not in `present`; the owner only. */
static void
keys_prune(uc_vm_t *vm, const char *table, uc_value_t *present)
{
	uc_value_t *maps, *keys, *gone;

	if (!map_owner)
		return;

	maps = maps_load(vm);
	keys = ucv_object_get(ucv_object_get(maps, table, NULL), "keys", NULL);
	gone = ucv_array_new(vm);

	ucv_object_foreach(keys, key, entry) {
		bool found = false;

		(void)entry;
		for (size_t i = 0; i < ucv_array_length(present) && !found; i++) {
			char *p = key_dup(vm, ucv_array_get(present, i));

			found = !strcmp(p, key);
			free(p);
		}

		if (!found)
			ucv_array_push(gone, ucv_string_new(key));
	}

	for (size_t i = 0; i < ucv_array_length(gone); i++) {
		uc_value_t *key_val = ucv_array_get(gone, i);

		ucv_object_delete(keys, ucv_string_get(key_val));
	}

	if (ucv_array_length(gone))
		maps_store(vm, maps);

	ucv_put(gone);
}

/**
 * ucode: `instance_prune(table, present)`: drops the keys of rows that are
 * gone, for a table whose keys never come back, such as random session ids.
 * The next free number stays, so a number is not given to another row.
 *
 * @param vm     ucode VM context
 * @param nargs  table path, array of the keys present
 * @return       null
 */
uc_value_t *
uc_ubbf_instance_prune(uc_vm_t *vm, size_t nargs)
{
	TABLE_ARG(table);

	if (table)
		keys_prune(vm, table, uc_fn_arg(1));

	return NULL;
}

/**
 * ucode: `instance_key(table, keys, instance, floor)`: the key of the row
 * with an instance number.
 *
 * @param vm     ucode VM context
 * @param nargs  table path, array of the keys present, instance number,
 *               optional floor as for instance_numbers()
 * @return       the key, or null when no present row has the number
 */
uc_value_t *
uc_ubbf_instance_key(uc_vm_t *vm, size_t nargs)
{
	TABLE_ARG(table);
	int64_t want = number_arg(uc_fn_arg(2));
	uc_value_t *numbers, *res = NULL;

	if (!table)
		return NULL;

	numbers = numbers_get(vm, table, uc_fn_arg(1), floor_arg(uc_fn_arg(3)), true);
	ucv_object_foreach(numbers, key, n) {
		if (!res && ucv_int64_get(n) == want)
			res = ucv_string_new(key);
	}

	ucv_put(numbers);
	return res;
}

/**
 * ucode: `instance_lookup(table, instance)`: the key that the map holds for
 * an instance number, without numbering new keys.
 *
 * @param vm     ucode VM context
 * @param nargs  table path, instance number
 * @return       the key, or null when the map has none
 */
uc_value_t *
uc_ubbf_instance_lookup(uc_vm_t *vm, size_t nargs)
{
	TABLE_ARG(table);
	int64_t want = number_arg(uc_fn_arg(1));
	uc_value_t *keys;

	if (!table)
		return NULL;

	keys = ucv_object_get(ucv_object_get(maps_load(vm), table, NULL), "keys", NULL);
	ucv_object_foreach(keys, key, entry) {
		if (int_get(entry, "n") == want)
			return ucv_string_new(key);
	}

	return NULL;
}

/**
 * ucode: `instance_rows(table, keys, fn, floor)`: the rows of a table keyed
 * by their stable instance numbers.
 *
 * @param vm     ucode VM context
 * @param nargs  table path, array of the keys present, fn(key, number)
 *               returning the row, optional floor as for instance_numbers()
 * @return       object instance number to row
 */
uc_value_t *
uc_ubbf_instance_rows(uc_vm_t *vm, size_t nargs)
{
	TABLE_ARG(table);
	uc_value_t *fn = uc_fn_arg(2), *numbers, *rows = ucv_object_new(vm);
	char num[24];

	if (!table)
		return rows;

	numbers = numbers_get(vm, table, uc_fn_arg(1), floor_arg(uc_fn_arg(3)), true);
	ucv_object_foreach(numbers, key, n) {
		uc_value_t *k = ucv_string_new(key);
		uc_value_t *row = callback_invoke(vm, fn, 2, k, n);

		ucv_put(k);
		if (vm->exception.type != EXCEPTION_NONE)
			break;

		snprintf(num, sizeof(num), "%" PRId64, ucv_int64_get(n));
		ucv_object_add(rows, num, row);
	}

	ucv_put(numbers);
	return rows;
}

/**
 * ucode: `instance_items(table, items, key_fn, floor)`: numbers the items of
 * a table whose keys never come back, such as the row ids of a daemon; the
 * keys of the items that are gone leave the map.
 *
 * @param vm     ucode VM context
 * @param nargs  table path, array of the items present, key_fn(item)
 *               returning the key as a string, optional floor
 * @return       object instance number to item
 */
uc_value_t *
uc_ubbf_instance_items(uc_vm_t *vm, size_t nargs)
{
	TABLE_ARG(table);
	uc_value_t *items = uc_fn_arg(1), *key_fn = uc_fn_arg(2);
	uc_value_t *ids, *numbers, *rows = ucv_object_new(vm);
	char num[24];

	if (!table || !ucv_is_callable(key_fn))
		return rows;

	ids = ucv_array_new(vm);
	for (size_t i = 0; i < ucv_array_length(items); i++) {
		ucv_array_push(ids, callback_invoke(vm, key_fn, 1, ucv_array_get(items, i)));
		if (vm->exception.type != EXCEPTION_NONE) {
			ucv_put(ids);
			return rows;
		}
	}

	numbers = numbers_get(vm, table, ids, floor_arg(uc_fn_arg(3)), true);
	keys_prune(vm, table, ids);

	for (size_t i = 0; i < ucv_array_length(items); i++) {
		char *key = key_dup(vm, ucv_array_get(ids, i));
		uc_value_t *n = ucv_object_get(numbers, key, NULL);

		free(key);
		if (!n)
			continue;

		snprintf(num, sizeof(num), "%" PRId64, ucv_int64_get(n));
		ucv_object_add(rows, num, ucv_get(ucv_array_get(items, i)));
	}

	ucv_put(numbers);
	ucv_put(ids);
	return rows;
}

static int64_t
floor_of(uc_value_t *rows)
{
	int64_t top = 0;

	ucv_object_foreach(rows, key, row) {
		(void)row;
		if (key_is_instance(key) && strtoll(key, NULL, 10) > top)
			top = strtoll(key, NULL, 10);
	}

	return top + 1;
}

/**
 * ucode: `instance_floor(rows)`: one above the highest instance number of a
 * stored table, the floor of the numbers that the CPE gives the rows it
 * finds.
 *
 * @param vm     ucode VM context
 * @param nargs  stored table, instance number to row, or null
 * @return       the floor, 1 for an empty table
 */
uc_value_t *
uc_ubbf_instance_floor(uc_vm_t *vm, size_t nargs)
{
	return ucv_int64_new(floor_of(uc_fn_arg(0)));
}

/**
 * ucode: `instance_ids(entries, next)`: gives each entry of a record store
 * (faults, reboots) an `id`, the instance number of its row, so that a
 * removal or a rotation moves no other row. An entry without one gets the
 * next number in list order; the writer and the readers of a store thus
 * give the same numbers.
 *
 * @param vm     ucode VM context
 * @param nargs  array of entries (changed in place), optional next id that
 *               the store keeps
 * @return       the next free id
 */
uc_value_t *
uc_ubbf_instance_ids(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *entries = uc_fn_arg(0), *next_val = uc_fn_arg(1);
	int64_t top = 0, next;

	for (size_t i = 0; i < ucv_array_length(entries); i++) {
		uc_value_t *id = ucv_object_get(ucv_array_get(entries, i), "id", NULL);

		if (ucv_type(id) == UC_INTEGER && ucv_int64_get(id) > top)
			top = ucv_int64_get(id);
	}

	next = (ucv_type(next_val) == UC_INTEGER) ? ucv_int64_get(next_val) : 1;
	if (next < top + 1)
		next = top + 1;

	for (size_t i = 0; i < ucv_array_length(entries); i++) {
		uc_value_t *e = ucv_array_get(entries, i);

		if (ucv_type(e) == UC_OBJECT &&
		    ucv_type(ucv_object_get(e, "id", NULL)) != UC_INTEGER)
			ucv_object_add(e, "id", ucv_int64_new(next++));
	}

	return ucv_int64_new(next);
}

/**
 * ucode: `instance_id_rows(entries, fn)`: the rows of a record store keyed
 * by the ids of instance_ids().
 *
 * @param vm     ucode VM context
 * @param nargs  array of entries with ids, fn(entry) returning the row
 * @return       object instance number to row
 */
uc_value_t *
uc_ubbf_instance_id_rows(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *entries = uc_fn_arg(0), *fn = uc_fn_arg(1), *rows = ucv_object_new(vm);
	char num[24];

	for (size_t i = 0; i < ucv_array_length(entries); i++) {
		uc_value_t *e = ucv_array_get(entries, i);
		uc_value_t *row = callback_invoke(vm, fn, 1, e);

		if (vm->exception.type != EXCEPTION_NONE)
			break;

		snprintf(num, sizeof(num), "%" PRId64, int_get(e, "id"));
		ucv_object_add(rows, num, row);
	}

	return rows;
}

static int
number_cmp(const void *a, const void *b)
{
	int64_t x = *(const int64_t *)a, y = *(const int64_t *)b;

	return (x > y) - (x < y);
}

/* The instance numbers of a stored table, ascending; *count receives the
 * number of them, the caller frees the array. */
static int64_t *
stored_numbers(uc_value_t *stored, size_t *count)
{
	int64_t *numbers = xcalloc(ucv_object_length(stored) + 1, sizeof(*numbers));

	*count = 0;
	ucv_object_foreach(stored, key, row) {
		(void)row;
		if (key_is_instance(key))
			numbers[(*count)++] = strtoll(key, NULL, 10);
	}

	qsort(numbers, *count, sizeof(*numbers), number_cmp);
	return numbers;
}

static bool
stack_claim(uc_vm_t *vm, uc_value_t *stored, uc_value_t *items, bool *taken,
	    uc_value_t *rows, uc_value_t *claim_fn)
{
	size_t count;
	int64_t *numbers = stored_numbers(stored, &count);
	char num[24];

	for (size_t s = 0; s < count; s++) {
		snprintf(num, sizeof(num), "%" PRId64, numbers[s]);
		if (ucv_object_get(rows, num, NULL))
			continue;

		for (size_t i = 0; i < ucv_array_length(items); i++) {
			uc_value_t *item = ucv_array_get(items, i), *res;
			bool claims;

			if (taken[i])
				continue;

			res = callback_invoke(vm, claim_fn, 2, ucv_object_get(stored, num, NULL), item);
			claims = ucv_is_truish(res);
			ucv_put(res);

			if (vm->exception.type != EXCEPTION_NONE) {
				free(numbers);
				return false;
			}

			if (!claims)
				continue;

			taken[i] = true;
			ucv_object_add(rows, num, ucv_get(item));
			break;
		}
	}

	free(numbers);
	return true;
}

/**
 * ucode: `instance_stack(stored, items, exact_fn, loose_fn)`: numbers the
 * live items of a table that also stores rows, for a table whose items need
 * no number of their own across a reboot: a stored row keeps its number and
 * takes the item it claims, and the other items follow the highest stored
 * row in the order given.
 *
 * @param vm     ucode VM context
 * @param nargs  stored table (instance number to row, or null), array of
 *               live items, exact_fn(row, item): the row names the item
 *               (for example by its address), optional loose_fn(row, item):
 *               the row takes the item when no row names it (for example a
 *               DHCP row)
 * @return       object instance number to item; a stored row without an
 *               item is absent
 */
uc_value_t *
uc_ubbf_instance_stack(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *stored = uc_fn_arg(0), *items = uc_fn_arg(1);
	uc_value_t *exact_fn = uc_fn_arg(2), *loose_fn = uc_fn_arg(3);
	uc_value_t *rows = ucv_object_new(vm);
	size_t count = ucv_array_length(items);
	bool *taken = xcalloc(count + 1, sizeof(*taken));
	int64_t n = floor_of(stored);
	char num[24];

	if (!stack_claim(vm, stored, items, taken, rows, exact_fn) ||
	    (loose_fn && !stack_claim(vm, stored, items, taken, rows, loose_fn))) {
		free(taken);
		return rows;
	}

	for (size_t i = 0; i < count; i++) {
		if (taken[i])
			continue;

		snprintf(num, sizeof(num), "%" PRId64, n++);
		ucv_object_add(rows, num, ucv_get(ucv_array_get(items, i)));
	}

	free(taken);
	return rows;
}

static uc_value_t *
tree_node(uc_value_t *root, const char *table)
{
	char *buf = xstrdup(table), *parts[PATH_PARTS_MAX];
	int cnt = path_split(buf, parts, PATH_PARTS_MAX, 0);
	uc_value_t *node = cnt < 0 ? NULL : tree_node_get(root, parts, cnt);

	free(buf);
	return node;
}

static void
pin_add(uc_vm_t *vm, uc_value_t *pins, uc_value_t *reverse, const char *table, const char *n)
{
	uc_value_t *key = ucv_object_get(ucv_object_get(reverse, table, NULL), n, NULL);
	uc_value_t *numbers;

	if (!key)
		return;

	numbers = ucv_object_get(pins, table, NULL);
	if (!numbers) {
		numbers = ucv_object_new(vm);
		ucv_object_add(pins, table, numbers);
	}

	ucv_object_add(numbers, n, ucv_get(key));
}

static bool
path_char(char c)
{
	return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') ||
	       (c >= '0' && c <= '9') || c == '_' || c == '.';
}

/* Pins the mapped rows that the `Device.` paths in a string name. */
static void
string_pin(uc_vm_t *vm, uc_value_t *pins, uc_value_t *reverse, const char *s)
{
	const char *p = s, *end;

	while ((p = strstr(p, "Device.")) != NULL) {
		char *path, *parts[PATH_PARTS_MAX], *table;
		int cnt;

		end = p + strlen("Device.");
		if (!path_char(*end)) {
			p = end;
			continue;
		}

		while (path_char(*end))
			end++;

		path = xalloc(end - p + 1);
		memcpy(path, p, end - p);
		cnt = path_split(path, parts, PATH_PARTS_MAX, 0);

		for (int i = 1; i < cnt; i++) {
			if (!key_is_instance(parts[i]))
				continue;

			table = path_join(parts, 0, i);
			pin_add(vm, pins, reverse, table, parts[i]);
			free(table);
		}

		free(path);
		p = end;
	}
}

static void
references_pin(uc_vm_t *vm, uc_value_t *pins, uc_value_t *reverse, uc_value_t *value)
{
	switch (ucv_type(value)) {
	case UC_OBJECT:
		ucv_object_foreach(value, k, v) {
			(void)k;
			references_pin(vm, pins, reverse, v);
		}
		break;

	case UC_ARRAY:
		for (size_t i = 0; i < ucv_array_length(value); i++)
			references_pin(vm, pins, reverse, ucv_array_get(value, i));
		break;

	case UC_STRING:
		string_pin(vm, pins, reverse, ucv_string_get(value));
		break;

	default:
		break;
	}
}

static int
string_cmp(const void *a, const void *b)
{
	return strcmp(*(const char * const *)a, *(const char * const *)b);
}

static uc_value_t *
pins_sorted(uc_vm_t *vm, uc_value_t *pins)
{
	uc_value_t *sorted = ucv_object_new(vm);
	size_t count = 0;
	const char **tables = xcalloc(ucv_object_length(pins) + 1, sizeof(*tables));

	ucv_object_foreach(pins, table, numbers) {
		(void)numbers;
		tables[count++] = table;
	}
	qsort(tables, count, sizeof(*tables), string_cmp);

	for (size_t t = 0; t < count; t++) {
		uc_value_t *numbers = ucv_object_get(pins, tables[t], NULL), *out = ucv_object_new(vm);
		size_t ncount;
		int64_t *ns = stored_numbers(numbers, &ncount);
		char num[24];

		for (size_t i = 0; i < ncount; i++) {
			snprintf(num, sizeof(num), "%" PRId64, ns[i]);
			ucv_object_add(out, num, ucv_get(ucv_object_get(numbers, num, NULL)));
		}

		free(ns);
		ucv_object_add(sorted, tables[t], out);
	}

	free(tables);
	return sorted;
}

/**
 * The pins of a configuration: the numbers of the mapped rows that it
 * stores, and those of the mapped rows that a stored string names
 * (`Device.<table>.<n>`, also inside a comma list). A pin keeps its key
 * from the live map; a row that nothing names has no pin. The same
 * configuration gives the same pins, in a stable order.
 *
 * @param vm      ucode VM context
 * @param config  configuration tree with Device
 * @return        new object table path to { instance number: key }
 */
uc_value_t *
instance_pins_new(uc_vm_t *vm, uc_value_t *config)
{
	uc_value_t *maps = maps_load(vm);
	uc_value_t *reverse = ucv_object_new(vm), *pins = ucv_object_new(vm), *sorted;
	char num[24];

	ucv_object_foreach(maps, table, map) {
		uc_value_t *rev = ucv_object_new(vm), *keys = ucv_object_get(map, "keys", NULL);

		ucv_object_foreach(keys, key, entry) {
			snprintf(num, sizeof(num), "%" PRId64, int_get(entry, "n"));
			ucv_object_add(rev, num, ucv_string_new(key));
		}
		ucv_object_add(reverse, table, rev);
	}

	ucv_object_foreach(reverse, stored_table, rev) {
		uc_value_t *stored = tree_node(config, stored_table);

		(void)rev;
		ucv_object_foreach(stored, n, row) {
			(void)row;
			if (key_is_instance(n))
				pin_add(vm, pins, reverse, stored_table, n);
		}
	}

	references_pin(vm, pins, reverse, ucv_object_get(config, "Device", NULL));

	sorted = pins_sorted(vm, pins);
	ucv_put(pins);
	ucv_put(reverse);
	return sorted;
}

/*
 * Seeds the map from pins: a pinned key takes its number back, and a number
 * stays reserved while its row is absent. A pin yields to a key that holds
 * the number already. Returns whether the map changed.
 */
static bool
pins_load(uc_vm_t *vm, uc_value_t *maps, uc_value_t *pins)
{
	int64_t now = uptime();
	bool changed = false;

	ucv_object_foreach(pins, table, numbers) {
		uc_value_t *map, *keys, *used;
		char num[24];

		if (ucv_type(numbers) != UC_OBJECT)
			continue;

		map = table_map(vm, maps, table);
		keys = ucv_object_get(map, "keys", NULL);
		used = ucv_object_new(vm);

		ucv_object_foreach(keys, key, entry) {
			snprintf(num, sizeof(num), "%" PRId64, int_get(entry, "n"));
			ucv_object_add(used, num, ucv_string_new(key));
		}

		ucv_object_foreach(numbers, n_str, key_val) {
			int64_t n = key_is_instance(n_str) ? strtoll(n_str, NULL, 10) : -1;
			uc_value_t *old;
			const char *key;

			if (ucv_type(key_val) != UC_STRING || n < 1)
				continue;

			snprintf(num, sizeof(num), "%" PRId64, n);
			if (ucv_object_get(used, num, NULL))
				continue;

			key = ucv_string_get(key_val);
			old = ucv_object_get(keys, key, NULL);
			if (old) {
				snprintf(num, sizeof(num), "%" PRId64, int_get(old, "n"));
				ucv_object_delete(used, num);
			}

			ucv_object_add(keys, key, entry_new(vm, n, now));
			snprintf(num, sizeof(num), "%" PRId64, n);
			ucv_object_add(used, num, ucv_string_new(key));
			if (int_get(map, "next") < n + 1)
				ucv_object_add(map, "next", ucv_int64_new(n + 1));
			changed = true;
		}

		ucv_put(used);
	}

	return changed;
}

/**
 * Seeds the map from the pins of config.json as it is loaded; see
 * pins_load(). Any process may seed.
 *
 * @param vm    ucode VM context
 * @param pins  pins as instance_pins_new() returns, or NULL
 */
void
instance_pins_seed(uc_vm_t *vm, uc_value_t *pins)
{
	uc_value_t *maps = maps_load(vm);

	if (pins_load(vm, maps, pins))
		maps_store(vm, maps);
}

/**
 * ucode: `instance_retire(table, key)`: keeps the number of a row that is
 * gone for good under a key that no row can have, so that a new row with
 * the key of the old one gets a new number, and a stored reference to the
 * old number keeps it reserved.
 *
 * @param vm     ucode VM context
 * @param nargs  table path, key of the row
 * @return       null
 */
uc_value_t *
uc_ubbf_instance_retire(uc_vm_t *vm, size_t nargs)
{
	TABLE_ARG(table);
	uc_value_t *maps, *keys, *entry;
	char num[24], *key;
	int64_t n;

	if (!table || !map_owner || !uc_fn_arg(1))
		return NULL;

	maps = maps_load(vm);
	keys = ucv_object_get(ucv_object_get(maps, table, NULL), "keys", NULL);
	key = key_dup(vm, uc_fn_arg(1));
	entry = ucv_object_get(keys, key, NULL);

	if (ucv_type(entry) != UC_OBJECT) {
		free(key);
		return NULL;
	}

	n = int_get(entry, "n");
	ucv_object_delete(keys, key);
	free(key);

	snprintf(num, sizeof(num), "#%" PRId64, n);
	ucv_object_add(keys, num, entry_new(vm, n, -1));
	maps_store(vm, maps);

	return NULL;
}
