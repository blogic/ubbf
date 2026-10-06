/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

#ifndef UBBF_LOGD_LISTEN_H
#define UBBF_LOGD_LISTEN_H

#include <stdbool.h>
#include <stdint.h>

#include <libubox/blobmsg.h>
#include <libubox/list.h>
#include <libubox/uloop.h>
#include <libubox/ustream-ssl.h>

enum listen_proto {
	LISTEN_UDP,
	LISTEN_TCP,
	LISTEN_TLS,
	LISTEN_UNIX,
};

struct listener_source {
	int id;
	int default_pri;
};

struct listener {
	struct list_head list;
	char *key;
	bool used;
	bool started;

	enum listen_proto proto;
	int port;
	char *path;
	char *cert;
	char *ca_dir;
	bool peer_verify;

	struct listener_source *sources;
	size_t source_count;

	struct uloop_fd fd;
	struct uloop_timeout retry;
	struct ustream_ssl_ctx *ssl_ctx;
	struct list_head clients;
	int client_count;

	uint64_t received;
	char error[128];
};

struct listener *listener_get(enum listen_proto proto, int port, const char *path,
			      const char *cert, const char *ca_dir, bool peer_verify,
			      int source_id, int default_pri);
void listener_mark_unused(void);
void listener_sweep(void);
void listener_free_all(void);
void listener_status_add(struct listener *l, struct blob_buf *b, const char *name);

#endif
