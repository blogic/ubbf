/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

#ifndef UBBF_LOGD_MSG_H
#define UBBF_LOGD_MSG_H

#include <stdbool.h>
#include <stddef.h>
#include <time.h>

#define MSG_TEXT_MAX		2048
#define MSG_HOST_MAX		256
#define MSG_PROGRAM_MAX		64
#define MSG_PID_MAX		16

#define MSG_PRI_DEFAULT		13

struct log_msg {
	int pri;
	time_t time;
	bool kernel;
	char host[MSG_HOST_MAX];
	char program[MSG_PROGRAM_MAX];
	char pid[MSG_PID_MAX];
	char text[MSG_TEXT_MAX];
};

void msg_from_local(struct log_msg *msg, int pri, bool kernel, time_t time,
		    const char *line, const char *host);
void msg_from_frame(struct log_msg *msg, const char *frame, size_t len,
		    int default_pri, const char *sender, time_t now);

const char *msg_facility_name(int pri);
const char *msg_level_name(int pri);

#endif
