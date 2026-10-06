/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "template.h"

struct line {
	char *buf;
	size_t len;
	size_t size;
};

static void
line_add(struct line *l, const char *s, size_t len)
{
	if (len > l->size - 1 - l->len)
		len = l->size - 1 - l->len;

	memcpy(l->buf + l->len, s, len);
	l->len += len;
	l->buf[l->len] = 0;
}

static void
line_puts(struct line *l, const char *s)
{
	line_add(l, s, strlen(s));
}

static void
line_puts_nil(struct line *l, const char *s)
{
	line_puts(l, *s ? s : "-");
}

static void
line_escaped(struct line *l, const char *s)
{
	for (; *s; s++) {
		if (*s == '\'' || *s == '"' || *s == '\\')
			line_add(l, "\\", 1);

		line_add(l, s, 1);
	}
}

static void
date_add(struct line *l, time_t t)
{
	char buf[32];
	struct tm tm;

	localtime_r(&t, &tm);
	strftime(buf, sizeof(buf), "%b %e %H:%M:%S", &tm);
	line_puts(l, buf);
}

static void
isodate_add(struct line *l, time_t t)
{
	char buf[48];
	struct tm tm;
	long offset;
	size_t n;

	localtime_r(&t, &tm);
	n = strftime(buf, sizeof(buf), "%Y-%m-%dT%H:%M:%S", &tm);
	offset = tm.tm_gmtoff;
	snprintf(buf + n, sizeof(buf) - n, "%c%02ld:%02ld",
		 offset < 0 ? '-' : '+', labs(offset) / 3600, labs(offset) % 3600 / 60);
	line_puts(l, buf);
}

static void
msghdr_add(struct line *l, const struct log_msg *msg)
{
	if (!msg->program[0])
		return;

	line_puts(l, msg->program);

	if (msg->pid[0]) {
		line_add(l, "[", 1);
		line_puts(l, msg->pid);
		line_add(l, "]", 1);
	}

	line_add(l, ": ", 2);
}

static bool
macro_add(struct line *l, const char *name, size_t len,
	  const struct log_msg *msg, bool escape)
{
	char num[16];

#define MACRO_IS(_name) (len == sizeof(_name) - 1 && !memcmp(name, _name, len))

	if (MACRO_IS("PRI")) {
		snprintf(num, sizeof(num), "%d", msg->pri);
		line_puts(l, num);
	}
	else if (MACRO_IS("FACILITY")) {
		line_puts(l, msg_facility_name(msg->pri));
	}
	else if (MACRO_IS("LEVEL") || MACRO_IS("SEVERITY")) {
		line_puts(l, msg_level_name(msg->pri));
	}
	else if (MACRO_IS("DATE")) {
		date_add(l, msg->time);
	}
	else if (MACRO_IS("ISODATE")) {
		isodate_add(l, msg->time);
	}
	else if (MACRO_IS("HOST")) {
		line_puts(l, msg->host);
	}
	else if (MACRO_IS("PROGRAM")) {
		line_puts(l, msg->program);
	}
	else if (MACRO_IS("PID")) {
		line_puts(l, msg->pid);
	}
	else if (MACRO_IS("MSGHDR")) {
		msghdr_add(l, msg);
	}
	else if (MACRO_IS("MSG") || MACRO_IS("MESSAGE")) {
		if (escape)
			line_escaped(l, msg->text);
		else
			line_puts(l, msg->text);
	}
	else {
		return false;
	}

#undef MACRO_IS

	return true;
}

static size_t
macro_name_len(const char *p)
{
	size_t len = 0;

	while ((p[len] >= 'A' && p[len] <= 'Z') || p[len] == '_')
		len++;

	return len;
}

/* "$NAME" and "${NAME}". Anything that is not a known macro, including a
 * lone '$', is copied as it is. */
size_t
template_render(const char *expr, bool escape, const struct log_msg *msg,
		char *out, size_t size)
{
	struct line l = { .buf = out, .size = size };
	const char *p = expr, *dollar, *name, *next;
	size_t len;

	out[0] = 0;

	while (*p) {
		dollar = strchr(p, '$');

		if (!dollar) {
			line_puts(&l, p);
			break;
		}

		line_add(&l, p, dollar - p);

		if (dollar[1] == '{') {
			name = dollar + 2;
			next = strchr(name, '}');
			len = next ? (size_t)(next - name) : 0;

			if (next)
				next++;
		}
		else {
			name = dollar + 1;
			len = macro_name_len(name);
			next = name + len;
		}

		if (len && macro_add(&l, name, len, msg, escape)) {
			p = next;
		}
		else {
			line_add(&l, "$", 1);
			p = dollar + 1;
		}
	}

	return l.len;
}

size_t
format_file(const struct log_msg *msg, char *out, size_t size)
{
	return template_render("$DATE $HOST $MSGHDR$MSG", false, msg, out, size);
}

size_t
format_rfc3164(const struct log_msg *msg, char *out, size_t size)
{
	return template_render("<$PRI>$DATE $HOST $MSGHDR$MSG", false, msg, out, size);
}

size_t
format_rfc5424(const struct log_msg *msg, char *out, size_t size)
{
	struct line l = { .buf = out, .size = size };
	char pri[16];

	out[0] = 0;
	snprintf(pri, sizeof(pri), "<%d>1 ", msg->pri);
	line_puts(&l, pri);
	isodate_add(&l, msg->time);
	line_add(&l, " ", 1);
	line_puts_nil(&l, msg->host);
	line_add(&l, " ", 1);
	line_puts_nil(&l, msg->program);
	line_add(&l, " ", 1);
	line_puts_nil(&l, msg->pid);
	line_add(&l, " - - ", 5);
	line_puts(&l, msg->text);

	return l.len;
}
