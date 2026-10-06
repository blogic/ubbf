/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

#ifndef UBBF_LOGD_INPUT_H
#define UBBF_LOGD_INPUT_H

#include <libubox/blobmsg.h>
#include <libubus.h>

void input_start(struct ubus_context *ctx);
void input_stop(void);
void input_replay(void);
void input_status_add(struct blob_buf *b, const char *name);

#endif
