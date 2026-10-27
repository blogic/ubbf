/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

/*
 * When the rendered UCI of each config last changed. The apply pipeline
 * hashes the rendered files after each apply; a render that produces the
 * same bytes keeps the time.
 */

#include "ubbf.h"
#include "bindings.h"

#include <dirent.h>
#include <sys/stat.h>
#include <libubox/md5.h>

#define UCI_TRACK_PATH	"/tmp/ubbf/uci-last-changed.json"

static bool
file_md5(const char *path, char hex[33])
{
	uint8_t sum[16];

	if (md5sum(path, sum) < 0)
		return false;

	for (size_t i = 0; i < sizeof(sum); i++)
		snprintf(hex + i * 2, 3, "%02x", sum[i]);

	return true;
}

/**
 * Hashes every regular file of a directory and stores `{ md5,
 * lastchanged }` per file name in a JSON state file. lastchanged moves
 * only when the MD5 differs from the stored one. A failure is not fatal:
 * readers treat the state as a cache.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (2 expected: directory of the
 *               rendered UCI files, state file path)
 * @return       null
 */
uc_value_t *
uc_ubbf_uci_change_update(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *dir_arg = uc_fn_arg(0);
	uc_value_t *path_arg = uc_fn_arg(1);
	uc_value_t *state, *entry, *now, *stored;
	struct dirent *e;
	struct stat st;
	char *full, *json, hex[33];
	DIR *dir;

	if (ucv_type(dir_arg) != UC_STRING || ucv_type(path_arg) != UC_STRING)
		return NULL;

	dir = opendir(ucv_string_get(dir_arg));
	if (!dir)
		return NULL;

	state = json_file_load_object(vm, ucv_string_get(path_arg));
	now = ucv_int64_new(time(NULL));

	while ((e = readdir(dir)) != NULL) {
		if (e->d_name[0] == '.' && (!e->d_name[1] || (e->d_name[1] == '.' && !e->d_name[2])))
			continue;

		xasprintf(&full, "%s/%s", ucv_string_get(dir_arg), e->d_name);
		if (stat(full, &st) || !S_ISREG(st.st_mode) || !file_md5(full, hex)) {
			free(full);
			continue;
		}
		free(full);

		stored = ucv_object_get(ucv_object_get(state, e->d_name, NULL), "md5", NULL);
		if (ucv_type(stored) == UC_STRING && !strcmp(ucv_string_get(stored), hex))
			continue;

		entry = ucv_object_new(vm);
		ucv_object_add(entry, "md5", ucv_string_new(hex));
		ucv_object_add(entry, "lastchanged", unix_to_datetime_new(now));
		ucv_object_add(state, e->d_name, entry);
	}

	closedir(dir);

	json = ucv_to_jsonstring(vm, state);
	file_write_atomic(ucv_string_get(path_arg), json, strlen(json), 0644);
	free(json);
	ucv_put(now);
	ucv_put(state);

	return NULL;
}

/**
 * Returns when the rendered UCI of a config last changed.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: UCI config name)
 * @return       ISO 8601 time, or null before the first apply after boot
 *               or for an unknown config
 */
uc_value_t *
uc_ubbf_uci_last_changed(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *name = uc_fn_arg(0);
	uc_value_t *state, *changed;

	if (ucv_type(name) != UC_STRING)
		return NULL;

	state = json_file_load_object(vm, UCI_TRACK_PATH);
	changed = ucv_get(ucv_object_get(ucv_object_get(state, ucv_string_get(name), NULL),
					 "lastchanged", NULL));
	ucv_put(state);

	return changed;
}
