/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

#ifndef UBBF_LOGD_TEMPLATE_H
#define UBBF_LOGD_TEMPLATE_H

#include <stdbool.h>
#include <stddef.h>

#include "msg.h"

#define LINE_MAX_SIZE		(MSG_TEXT_MAX + 1024)

size_t template_render(const char *expr, bool escape, const struct log_msg *msg,
		       char *out, size_t size);
size_t format_file(const struct log_msg *msg, char *out, size_t size);
size_t format_rfc3164(const struct log_msg *msg, char *out, size_t size);
size_t format_rfc5424(const struct log_msg *msg, char *out, size_t size);

#endif
