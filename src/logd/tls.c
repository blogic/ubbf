/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

#include <dirent.h>
#include <dlfcn.h>
#include <stdio.h>
#include <sys/stat.h>

#include "tls.h"

#define CA_BUNDLE_FILE	"ca-certificates.crt"

/* Loaded at run time, the way uclient and uhttpd do it, so the image picks
 * the TLS backend and a device without one still forwards UDP and TCP. A
 * failed load is tried again, so a backend installed later is found. */
const struct ustream_ssl_ops *
tls_ops(void)
{
	static const struct ustream_ssl_ops *ops;
	void *dlh;

	if (ops)
		return ops;

	dlh = dlopen("libustream-ssl.so", RTLD_LAZY | RTLD_LOCAL);

	if (dlh)
		ops = dlsym(dlh, "ustream_ssl_ops");

	return ops;
}

/* A CA store holds every CA in its own file, again in a hash link to that
 * file, and again in ca-certificates.crt. Links are skipped, and the bundle
 * file alone is loaded when the directory has one. */
static int
tls_ca_dir_add(const struct ustream_ssl_ops *ops, struct ustream_ssl_ctx *ctx,
	       const char *dir)
{
	char path[512];
	struct dirent *e;
	struct stat st;
	int added = 0;
	DIR *d;

	snprintf(path, sizeof(path), "%s/" CA_BUNDLE_FILE, dir);

	if (!lstat(path, &st) && S_ISREG(st.st_mode))
		return !ops->context_add_ca_crt_file(ctx, path);

	d = opendir(dir);

	if (!d)
		return 0;

	while ((e = readdir(d)) != NULL) {
		if (e->d_name[0] == '.')
			continue;

		snprintf(path, sizeof(path), "%s/%s", dir, e->d_name);

		if (lstat(path, &st) || !S_ISREG(st.st_mode))
			continue;

		if (!ops->context_add_ca_crt_file(ctx, path))
			added++;
	}

	closedir(d);

	return added;
}

struct ustream_ssl_ctx *
tls_ctx_new(bool server, const char *cert, const char *ca_dir, bool peer_verify,
	    char *error, size_t error_len)
{
	const struct ustream_ssl_ops *ops = tls_ops();
	struct ustream_ssl_ctx *ctx;

	if (!ops) {
		snprintf(error, error_len, "tls unavailable");
		return NULL;
	}

	ctx = ops->context_new(server);

	if (!ctx) {
		snprintf(error, error_len, "tls context failed");
		return NULL;
	}

	/* The TR-181 Certificate is one PEM holding the certificate and its key. */
	if (cert && (ops->context_set_crt_file(ctx, cert) || ops->context_set_key_file(ctx, cert))) {
		snprintf(error, error_len, "cannot load certificate %s", cert);
		ops->context_free(ctx);
		return NULL;
	}

	if (ca_dir && !tls_ca_dir_add(ops, ctx, ca_dir))
		snprintf(error, error_len, "no CA certificate in %s", ca_dir);

	if (server && peer_verify)
		ops->context_set_require_validation(ctx, true);

	return ctx;
}

void
tls_ctx_free(struct ustream_ssl_ctx *ctx)
{
	if (ctx)
		tls_ops()->context_free(ctx);
}
