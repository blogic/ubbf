/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

/*
 * Lookups in the registered model by path and pattern, shared by the
 * readers and the writers.
 */

#include "dm-priv.h"

/**
 * Finds the last `{i}` of a pattern before a segment index.
 *
 * @param pattern  pattern segments
 * @param before   index to search below
 * @return         the index of the `{i}`, or -1 when there is none
 */
int
pattern_inst_before(char **pattern, int before)
{
	while (--before >= 0)
		if (!strcmp(pattern[before], "{i}"))
			return before;

	return -1;
}

/**
 * Joins path segments into their schema pattern, `{i}` in place of each
 * instance number.
 *
 * @param parts  path segments
 * @param cnt    number of segments
 * @return       new string that the caller frees, or NULL when `cnt` is
 *               not positive
 */
static char *
parts_pattern_join(char **parts, int cnt)
{
	char **pat_parts, *pattern;

	if (cnt <= 0)
		return NULL;

	pat_parts = xcalloc(cnt, sizeof(*pat_parts));
	for (int i = 0; i < cnt; i++)
		pat_parts[i] = key_is_instance(parts[i]) ? (char *)"{i}" : parts[i];

	pattern = path_join(pat_parts, 0, cnt);
	free(pat_parts);

	return pattern;
}

/**
 * Returns the model entry for the first `cnt` segments of a path.
 *
 * @param model  registered model object
 * @param parts  path segments
 * @param cnt    number of segments to use
 * @return       the entry, or NULL when the model has none
 */
uc_value_t *
model_entry_for_parts(uc_value_t *model, char **parts, int cnt)
{
	char *pattern = parts_pattern_join(parts, cnt);
	uc_value_t *entry = pattern ? ucv_object_get(model, pattern, NULL) : NULL;

	free(pattern);

	return entry;
}

/**
 * Returns the model entry of the rows below an object pattern.
 *
 * @param model    registered model object
 * @param pattern  schema pattern of the object
 * @return         the entry of `<pattern>.{i}`, or NULL
 */
uc_value_t *
table_row_entry(uc_value_t *model, const char *pattern)
{
	uc_value_t *entry;
	char *row;

	xasprintf(&row, "%s.{i}", pattern);
	entry = ucv_object_get(model, row, NULL);
	free(row);

	return entry;
}

/**
 * Folds a resolved path into its schema pattern.
 *
 * @param path  resolved path, with or without a trailing dot
 * @return      new string that the caller frees, or NULL when the path is
 *              empty or invalid
 */
char *
path_to_pattern(const char *path)
{
	char *buf = xstrdup(path), *parts[PATH_PARTS_MAX], *pattern;

	pattern = parts_pattern_join(parts, path_split(buf, parts, PATH_PARTS_MAX, 0));
	free(buf);

	return pattern;
}
