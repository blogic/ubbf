/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

#ifndef UBBF_LOGD_FILTER_H
#define UBBF_LOGD_FILTER_H

#include <regex.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "msg.h"

#define FILTER_SEVERITIES_ALL	0xff

enum filter_action {
	FILTER_LOG,
	FILTER_BLOCK,
	FILTER_STOP,
};

enum filter_verdict {
	FILTER_SKIP,
	FILTER_DELIVER,
	FILTER_HALT,
};

struct log_filter {
	int id;
	uint32_t facilities;
	uint32_t severities;
	enum filter_action action;
	bool has_pattern;
	bool invalid;
	regex_t pattern;
};

int filter_init(struct log_filter *f, int id, uint32_t facilities, uint32_t severities,
		const char *pattern, enum filter_action action);
void filter_free(struct log_filter *f);
bool filter_match(const struct log_filter *f, const struct log_msg *msg);
enum filter_verdict filter_chain_eval(struct log_filter *const *filters, size_t count,
				      const struct log_msg *msg);

#endif
