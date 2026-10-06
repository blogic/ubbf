/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

/* Linked into ubbf.so and into the native libraries of the modules. */

#include "util.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/**
 * Reads a small text file and returns its trimmed content as a heap string.
 *
 * Reads at most 8191 bytes from `path`, strips trailing newlines, carriage
 * returns and spaces, and trims leading whitespace. The caller owns the
 * returned pointer and must `free()` it.
 *
 * @param path  filesystem path to read
 * @return      newly allocated trimmed string, or NULL on open or empty read
 */
char *
sysfs_read_file(const char *path)
{
	FILE *fp;
	char buf[8192];
	size_t n;
	char *end;

	fp = fopen(path, "r");
	if (!fp)
		return NULL;

	n = fread(buf, 1, sizeof(buf) - 1, fp);
	fclose(fp);

	if (n == 0)
		return NULL;

	buf[n] = '\0';

	end = buf + n - 1;
	while (end >= buf && (*end == '\n' || *end == '\r' || *end == ' '))
		*end-- = '\0';

	char *start = buf;
	while (*start == ' ' || *start == '\t')
		start++;

	return strdup(start);
}

/**
 * Converts a hex character to its numeric value, or -1 on invalid.
 */
int
hex_nibble(char c)
{
	if (c >= '0' && c <= '9') return c - '0';
	if (c >= 'a' && c <= 'f') return c - 'a' + 10;
	if (c >= 'A' && c <= 'F') return c - 'A' + 10;
	return -1;
}

/**
 * Parses exactly `n` hex byte pairs, separated by `sep` (or adjacent when
 * `sep` is 0), with nothing before or after them.
 *
 * @param s    input string
 * @param sep  separator between the pairs, or 0 for none
 * @param out  receives `n` bytes
 * @param n    number of bytes to parse
 * @return     0 on success, -1 when `s` has another form
 */
int
hex_bytes_parse(const char *s, char sep, uint8_t *out, size_t n)
{
	for (size_t i = 0; i < n; i++) {
		int hi, lo;

		if (i > 0 && sep && *s++ != sep)
			return -1;

		hi = hex_nibble(s[0]);
		lo = (hi < 0) ? -1 : hex_nibble(s[1]);
		if (lo < 0)
			return -1;

		out[i] = (uint8_t)((hi << 4) | lo);
		s += 2;
	}

	return *s ? -1 : 0;
}

/**
 * Builds a TR-181 Alias from a free-form name.
 *
 * Replaces every character outside `[A-Za-z0-9_-]` with `_` and prefixes
 * the result with `cpe-`. The result is cut to fit `buf`; 65 bytes hold
 * the 64 characters of the TR-181 Alias type. Two names that differ only
 * in replaced characters or after that length get the same Alias. An
 * empty name gives an empty Alias.
 */
void
alias_from_name(const char *name, char *buf, size_t len)
{
	size_t j = 0;

	if (len == 0)
		return;

	buf[0] = '\0';
	if (!name || !*name || len < 5)
		return;

	memcpy(buf, "cpe-", 4);
	j = 4;

	for (const char *p = name; *p && j < len - 1; p++) {
		char c = *p;

		if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
		    (c >= '0' && c <= '9') || c == '_' || c == '-')
			buf[j++] = c;
		else
			buf[j++] = '_';
	}

	buf[j] = '\0';
}
