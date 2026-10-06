/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

#include <string.h>

#include "filter.h"

int
filter_init(struct log_filter *f, int id, uint32_t facilities, uint32_t severities,
	    const char *pattern, enum filter_action action)
{
	memset(f, 0, sizeof(*f));
	f->id = id;
	f->facilities = facilities;
	f->severities = severities;
	f->action = action;

	if (!pattern || !*pattern)
		return 0;

	if (regcomp(&f->pattern, pattern, REG_EXTENDED | REG_NOSUB)) {
		f->invalid = true;
		return -1;
	}

	f->has_pattern = true;

	return 0;
}

void
filter_free(struct log_filter *f)
{
	if (f->has_pattern)
		regfree(&f->pattern);

	f->has_pattern = false;
}

/* An invalid pattern fails closed: a Log filter passes nothing, and a Block
 * or Stop filter fires on every message of its facilities and severities,
 * because a pattern meant to hold back a line must not let it through. */
bool
filter_match(const struct log_filter *f, const struct log_msg *msg)
{
	unsigned int facility = (unsigned int)msg->pri >> 3;

	if (f->facilities && (facility > 31 || !(f->facilities & (1u << facility))))
		return false;

	if (!(f->severities & (1u << (msg->pri & 7))))
		return false;

	if (f->invalid)
		return f->action != FILTER_LOG;

	if (f->has_pattern && regexec(&f->pattern, msg->text, 0, NULL, 0))
		return false;

	return true;
}

/* Stop filters are checked first, whatever their position in the chain: the
 * syslog-ng render placed their discard paths ahead of the action's own log
 * path, and a match ends the message for every later action as well. */
enum filter_verdict
filter_chain_eval(struct log_filter *const *filters, size_t count,
		  const struct log_msg *msg)
{
	size_t i;

	for (i = 0; i < count; i++)
		if (filters[i]->action == FILTER_STOP && filter_match(filters[i], msg))
			return FILTER_HALT;

	for (i = 0; i < count; i++) {
		switch (filters[i]->action) {
		case FILTER_LOG:
			if (!filter_match(filters[i], msg))
				return FILTER_SKIP;
			break;

		case FILTER_BLOCK:
			if (filter_match(filters[i], msg))
				return FILTER_SKIP;
			break;

		case FILTER_STOP:
			break;
		}
	}

	return FILTER_DELIVER;
}
