/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

#include <ctype.h>
#include <stdio.h>
#include <string.h>

#include "msg.h"

/* The names syslog-ng uses, so templates written for it keep their output. */
static const char *const facility_names[] = {
	"kern", "user", "mail", "daemon", "auth", "syslog", "lpr", "news",
	"uucp", "cron", "authpriv", "ftp", "ntp", "security", "console",
	"solaris-cron", "local0", "local1", "local2", "local3", "local4",
	"local5", "local6", "local7"
};

static const char *const level_names[] = {
	"emerg", "alert", "crit", "err", "warning", "notice", "info", "debug"
};

static const char *const month_names[] = {
	"Jan", "Feb", "Mar", "Apr", "May", "Jun",
	"Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
};

const char *
msg_facility_name(int pri)
{
	unsigned int facility = (unsigned int)pri >> 3;

	if (facility >= sizeof(facility_names) / sizeof(facility_names[0]))
		return "unknown";

	return facility_names[facility];
}

const char *
msg_level_name(int pri)
{
	return level_names[pri & 7];
}

/* A control character becomes '#' and its three-digit octal code, as
 * rsyslog writes it, so that a newline in a received frame cannot start a
 * second record at the collector. */
static void
field_copy(char *dst, size_t size, const char *src, size_t len)
{
	unsigned char c;
	size_t i, n = 0;

	for (i = 0; i < len; i++) {
		c = src[i];

		if (c >= 0x20 && c != 0x7f) {
			if (n + 1 >= size)
				break;

			dst[n++] = c;
			continue;
		}

		if (n + 4 >= size)
			break;

		snprintf(dst + n, 5, "#%03o", c);
		n += 4;
	}

	dst[n] = 0;
}

static void
field_set(char *dst, size_t size, const char *src)
{
	field_copy(dst, size, src, strlen(src));
}

static void
field_set_nil(char *dst, size_t size, const char *src)
{
	if (!strcmp(src, "-"))
		dst[0] = 0;
	else
		field_set(dst, size, src);
}

/* RFC 3164 TAG, "PROGRAM[PID]: " or "PROGRAM: ". Returns the start of the
 * message text; without a valid tag that is the input itself. */
static const char *
tag_parse(struct log_msg *msg, const char *p)
{
	const char *s = p, *pid = NULL, *pid_end = NULL;
	size_t program_len;

	while (*s && *s != '[' && *s != ':' && *s != ' ')
		s++;

	program_len = s - p;

	if (!program_len || program_len >= MSG_PROGRAM_MAX)
		return p;

	if (*s == '[') {
		pid = s + 1;
		pid_end = strchr(pid, ']');

		if (!pid_end || pid_end - pid >= MSG_PID_MAX)
			return p;

		s = pid_end + 1;
	}

	if (*s != ':')
		return p;

	field_copy(msg->program, sizeof(msg->program), p, program_len);

	if (pid)
		field_copy(msg->pid, sizeof(msg->pid), pid, pid_end - pid);

	s++;

	if (*s == ' ')
		s++;

	return s;
}

void
msg_from_local(struct log_msg *msg, int pri, bool kernel, time_t time,
	       const char *line, const char *host)
{
	const char *text = line;

	msg->pri = pri;
	msg->time = time;
	msg->kernel = kernel;
	msg->program[0] = 0;
	msg->pid[0] = 0;
	field_set(msg->host, sizeof(msg->host), host);

	if (kernel)
		field_set(msg->program, sizeof(msg->program), "kernel");
	else
		text = tag_parse(msg, line);

	field_set(msg->text, sizeof(msg->text), text);
}

static char *
pri_parse(char *p, int *pri)
{
	int value = 0, digits = 0;

	if (*p != '<')
		return NULL;

	for (p++; isdigit((unsigned char)*p) && digits < 3; p++, digits++)
		value = value * 10 + (*p - '0');

	if (!digits || *p != '>' || value > 191)
		return NULL;

	*pri = value;

	return p + 1;
}

static bool
digits_get(const char *p, int count, int *value)
{
	int i;

	*value = 0;

	for (i = 0; i < count; i++) {
		if (!isdigit((unsigned char)p[i]))
			return false;

		*value = *value * 10 + (p[i] - '0');
	}

	return true;
}

/* "Mmm dd hh:mm:ss", the day padded with a space. The year is not in the
 * frame, so a date more than a day ahead belongs to the previous year. */
static bool
ts_3164_parse(const char *p, time_t now, time_t *out)
{
	struct tm tm = { 0 }, now_tm;
	int mon, day, hour, min, sec;
	time_t t;

	if (strnlen(p, 15) < 15 || p[3] != ' ' || p[6] != ' ' || p[9] != ':' || p[12] != ':')
		return false;

	for (mon = 0; mon < 12; mon++)
		if (!strncmp(p, month_names[mon], 3))
			break;

	if (mon == 12)
		return false;

	if (!digits_get(p + 5, 1, &day) ||
	    !digits_get(p + 7, 2, &hour) ||
	    !digits_get(p + 10, 2, &min) ||
	    !digits_get(p + 13, 2, &sec))
		return false;

	if (p[4] != ' ') {
		int tens;

		if (!digits_get(p + 4, 1, &tens))
			return false;

		day += tens * 10;
	}

	localtime_r(&now, &now_tm);
	tm.tm_year = now_tm.tm_year;
	tm.tm_mon = mon;
	tm.tm_mday = day;
	tm.tm_hour = hour;
	tm.tm_min = min;
	tm.tm_sec = sec;
	tm.tm_isdst = -1;
	t = mktime(&tm);

	if (t > now + 86400) {
		tm.tm_year--;
		tm.tm_isdst = -1;
		t = mktime(&tm);
	}

	*out = t;

	return true;
}

/* RFC 3339 as RFC 5424 restricts it: fraction optional, "Z" or "+hh:mm". */
static bool
ts_5424_parse(const char *p, time_t *out)
{
	int year, mon, day, hour, min, sec, off_h, off_m, n, offset = 0;
	struct tm tm = { 0 };

	if (sscanf(p, "%4d-%2d-%2dT%2d:%2d:%2d%n", &year, &mon, &day, &hour, &min, &sec, &n) != 6)
		return false;

	p += n;

	if (*p == '.')
		for (p++; isdigit((unsigned char)*p); p++)
			;

	if (*p == '+' || *p == '-') {
		if (sscanf(p + 1, "%2d:%2d", &off_h, &off_m) != 2)
			return false;

		offset = (off_h * 3600 + off_m * 60) * (*p == '-' ? -1 : 1);
	}
	else if (*p != 'Z') {
		return false;
	}

	tm.tm_year = year - 1900;
	tm.tm_mon = mon - 1;
	tm.tm_mday = day;
	tm.tm_hour = hour;
	tm.tm_min = min;
	tm.tm_sec = sec;
	*out = timegm(&tm) - offset;

	return true;
}

static bool
token_is_tag(const char *p, const char *end)
{
	return end[-1] == ':' || memchr(p, '[', end - p);
}

static const char *
rfc3164_parse(struct log_msg *msg, char *p, time_t now)
{
	char *end;

	if (!ts_3164_parse(p, now, &msg->time))
		return tag_parse(msg, p);

	for (p += 15; *p == ' '; p++)
		;

	end = strchr(p, ' ');

	if (end && end > p && !token_is_tag(p, end)) {
		field_copy(msg->host, sizeof(msg->host), p, end - p);
		p = end + 1;
	}

	return tag_parse(msg, p);
}

/* "<PRI>1 TIMESTAMP HOSTNAME APP-NAME PROCID MSGID SD [MSG]"; the caller
 * already consumed "<PRI>1 ". Structured data is skipped. */
static const char *
rfc5424_parse(struct log_msg *msg, char *p, time_t now)
{
	char *field[5];
	int i;

	for (i = 0; i < 5; i++) {
		field[i] = p;
		p = strchr(p, ' ');

		if (!p)
			return "";

		*p++ = 0;
	}

	if (!ts_5424_parse(field[0], &msg->time))
		msg->time = now;

	if (strcmp(field[1], "-"))
		field_set(msg->host, sizeof(msg->host), field[1]);

	field_set_nil(msg->program, sizeof(msg->program), field[2]);
	field_set_nil(msg->pid, sizeof(msg->pid), field[3]);

	if (*p == '-') {
		p++;
	}
	else {
		while (*p == '[') {
			for (p++; *p && *p != ']'; p++)
				if (*p == '\\' && p[1])
					p++;

			if (*p)
				p++;
		}
	}

	if (*p == ' ')
		p++;

	if (!strncmp(p, "\xef\xbb\xbf", 3))
		p += 3;

	return p;
}

void
msg_from_frame(struct log_msg *msg, const char *frame, size_t len,
	       int default_pri, const char *sender, time_t now)
{
	char buf[MSG_TEXT_MAX + 512];
	const char *text;
	char *p;

	if (len >= sizeof(buf))
		len = sizeof(buf) - 1;

	memcpy(buf, frame, len);
	buf[len] = 0;
	len = strlen(buf);

	while (len && (buf[len - 1] == '\n' || buf[len - 1] == '\r'))
		buf[--len] = 0;

	msg->time = now;
	msg->kernel = false;
	msg->program[0] = 0;
	msg->pid[0] = 0;
	field_set(msg->host, sizeof(msg->host), sender);

	p = pri_parse(buf, &msg->pri);

	if (!p) {
		msg->pri = default_pri;
		text = rfc3164_parse(msg, buf, now);
	}
	else if (p[0] == '1' && p[1] == ' ') {
		text = rfc5424_parse(msg, p + 2, now);
	}
	else {
		text = rfc3164_parse(msg, p, now);
	}

	field_set(msg->text, sizeof(msg->text), text);
}
