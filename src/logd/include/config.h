/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

#ifndef UBBF_LOGD_CONFIG_H
#define UBBF_LOGD_CONFIG_H

#include <stdbool.h>

#include <libubox/blobmsg.h>

#include "msg.h"

#define SOURCE_LOCAL		(-1)
#define CONFIG_PATH_DEFAULT	"/var/run/ubbf-logd/config.json"

void config_init(const char *path);
bool config_reload(struct blob_buf *report);
void config_dispatch(const struct log_msg *msg, int source_id);
void config_status_add(struct blob_buf *b);
void config_free(void);

#endif
