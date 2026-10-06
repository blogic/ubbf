/* SPDX-License-Identifier: GPL-2.0-only */

/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

#ifndef UBBF_UTIL_H
#define UBBF_UTIL_H

#include <stddef.h>
#include <stdint.h>

char *sysfs_read_file(const char *path);
int hex_nibble(char c);
int hex_bytes_parse(const char *s, char sep, uint8_t *out, size_t n);
void alias_from_name(const char *name, char *buf, size_t len);

#endif
