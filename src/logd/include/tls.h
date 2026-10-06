/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

#ifndef UBBF_LOGD_TLS_H
#define UBBF_LOGD_TLS_H

#include <stdbool.h>
#include <stddef.h>

#include <libubox/ustream-ssl.h>

const struct ustream_ssl_ops *tls_ops(void);
struct ustream_ssl_ctx *tls_ctx_new(bool server, const char *cert, const char *ca_dir,
				    bool peer_verify, char *error, size_t error_len);
void tls_ctx_free(struct ustream_ssl_ctx *ctx);

#endif
