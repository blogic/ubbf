/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

#include <ctype.h>
#include <string.h>

#include "frame.h"

/* RFC 6587 octet counting ("LEN SP FRAME"), recognised by a leading digit,
 * since a syslog frame starts with '<'. Returns the bytes consumed, 0 while
 * the frame is incomplete. */
static size_t
frame_octet_count(const char *buf, size_t len, bool flush,
		  const char **frame, size_t *frame_len)
{
	size_t i, count = 0;

	for (i = 0; i < len && i < 5 && isdigit((unsigned char)buf[i]); i++)
		count = count * 10 + (buf[i] - '0');

	if (i == len)
		return flush ? (size_t)-1 : 0;

	if (buf[i] != ' ' || count > FRAME_BUF_SIZE - 8)
		return (size_t)-1;

	if (len - i - 1 < count)
		return flush ? (size_t)-1 : 0;

	*frame = buf + i + 1;
	*frame_len = count;

	return i + 1 + count;
}

/* Newline framing. A line that outgrows FRAME_LINE_MAX, or the rest of the
 * buffer on flush, is passed on as a frame of its own so the buffer never
 * stalls. */
size_t
frame_next(const char *buf, size_t len, bool flush,
	   const char **frame, size_t *frame_len)
{
	const char *nl;
	size_t used;

	if (!len)
		return 0;

	if (isdigit((unsigned char)buf[0])) {
		used = frame_octet_count(buf, len, flush, frame, frame_len);

		if (used != (size_t)-1)
			return used;
	}

	nl = memchr(buf, '\n', len);

	if (nl && nl - buf <= FRAME_LINE_MAX) {
		*frame = buf;
		*frame_len = nl - buf;

		return *frame_len + 1;
	}

	if (!flush && len < FRAME_LINE_MAX && !nl)
		return 0;

	*frame = buf;
	*frame_len = len > FRAME_LINE_MAX ? FRAME_LINE_MAX : len;

	return *frame_len;
}
