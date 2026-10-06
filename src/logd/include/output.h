/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

#ifndef UBBF_LOGD_OUTPUT_H
#define UBBF_LOGD_OUTPUT_H

#include <stdbool.h>
#include <stdint.h>
#include <sys/socket.h>
#include <sys/types.h>

#include <libubox/blobmsg.h>
#include <libubox/list.h>
#include <libubox/uloop.h>
#include <libubox/ustream.h>
#include <libubox/ustream-ssl.h>

enum output_type {
	OUTPUT_FILE,
	OUTPUT_UDP,
	OUTPUT_TCP,
	OUTPUT_TLS,
};

enum output_state {
	OUTPUT_CONNECTING,
	OUTPUT_CONNECTED,
	OUTPUT_UNREACHABLE,
	OUTPUT_ERROR,
};

struct output {
	struct list_head list;
	char *key;
	bool used;
	bool started;

	enum output_type type;
	char *path;
	char *host;
	char *port;
	char *cert;
	char *ca_dir;
	bool peer_verify;

	enum output_state state;
	char error[128];
	uint64_t sent;
	uint64_t dropped;

	int fd;
	dev_t dev;
	ino_t ino;

	struct sockaddr_storage addr;
	socklen_t addr_len;
	struct uloop_fd resolve_fd;
	struct uloop_process resolver;

	struct ustream_ssl_ctx *ssl_ctx;
	struct uloop_fd connect_fd;
	struct uloop_timeout connect_timeout;
	struct uloop_timeout retry;
	int retry_delay;
	bool closing;
	bool stream_active;
	bool ssl_active;
	struct ustream_fd stream;
	struct ustream_ssl ssl;
	struct ustream *out;

	struct list_head queue;
	size_t queue_lines;
	size_t queue_bytes;

	struct list_head inflight;
	size_t inflight_bytes;
};

struct output *output_get(enum output_type type, const char *path, const char *host,
			  int port, const char *cert, const char *ca_dir, bool peer_verify);
void output_mark_unused(void);
void output_sweep(void);
void output_free_all(void);
void output_write(struct output *o, const char *line, size_t len);
void output_status_add(struct output *o, struct blob_buf *b, const char *name);

#endif
