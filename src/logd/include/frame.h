/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

#ifndef UBBF_LOGD_FRAME_H
#define UBBF_LOGD_FRAME_H

#include <stdbool.h>
#include <stddef.h>

#define FRAME_BUF_SIZE		8192
#define FRAME_LINE_MAX		2048

size_t frame_next(const char *buf, size_t len, bool flush,
		  const char **frame, size_t *frame_len);

#endif
