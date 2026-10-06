/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

#include <arpa/inet.h>
#include <errno.h>
#include <netinet/in.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <sys/utsname.h>
#include <syslog.h>
#include <unistd.h>

#include <libubox/ulog.h>
#include <libubox/usock.h>
#include <libubox/ustream.h>

#include "config.h"
#include "frame.h"
#include "listen.h"
#include "msg.h"
#include "tls.h"

#define CLIENTS_MAX		16
#define BIND_RETRY_MS		5000
#define SOCKET_DIR		"/var/run/ubbf-syslog/"

struct listen_client {
	struct list_head list;
	struct listener *l;
	struct ustream_fd stream;
	struct ustream_ssl ssl;
	bool tls;
	bool rejected;
	struct uloop_timeout close_timer;
	char sender[INET6_ADDRSTRLEN];
	char buf[FRAME_BUF_SIZE];
	size_t len;
};

static LIST_HEAD(listeners);
static struct log_msg frame_msg;

static const char *const proto_names[] = {
	[LISTEN_UDP] = "udp",
	[LISTEN_TCP] = "tcp",
	[LISTEN_TLS] = "tls",
	[LISTEN_UNIX] = "unix",
};

/* A frame from the Unix socket is a local one, so its host is this
 * device, as for the messages of the logd ring. The peer address does not
 * tell: a sender with an unbound socket has none. */
static void
sender_format(const struct listener *l, const struct sockaddr_storage *ss,
	      char *out, size_t size)
{
	const struct sockaddr_in6 *sin6 = (const void *)ss;
	const struct sockaddr_in *sin = (const void *)ss;
	struct utsname un;

	if (l->proto == LISTEN_UNIX)
		snprintf(out, size, "%s", uname(&un) ? "" : un.nodename);
	else if (ss->ss_family == AF_INET)
		inet_ntop(AF_INET, &sin->sin_addr, out, size);
	else if (IN6_IS_ADDR_V4MAPPED(&sin6->sin6_addr))
		inet_ntop(AF_INET, &sin6->sin6_addr.s6_addr[12], out, size);
	else
		inet_ntop(AF_INET6, &sin6->sin6_addr, out, size);
}

/* Each source of the listener gets the frame, parsed with its own default
 * priority. */
static void
frame_deliver(struct listener *l, const char *frame, size_t len, const char *sender)
{
	time_t now = time(NULL);
	size_t i;

	if (!len)
		return;

	l->received++;

	for (i = 0; i < l->source_count; i++) {
		msg_from_frame(&frame_msg, frame, len, l->sources[i].default_pri, sender, now);
		config_dispatch(&frame_msg, l->sources[i].id);
	}
}

static void
udp_read_cb(struct uloop_fd *u, unsigned int events)
{
	struct listener *l = container_of(u, struct listener, fd);
	char buf[FRAME_BUF_SIZE], sender[INET6_ADDRSTRLEN];
	struct sockaddr_storage ss;
	socklen_t sl;
	ssize_t n;

	while (true) {
		sl = sizeof(ss);
		n = recvfrom(u->fd, buf, sizeof(buf), 0, (struct sockaddr *)&ss, &sl);

		if (n < 0) {
			if (errno == EINTR)
				continue;

			return;
		}

		sender_format(l, &ss, sender, sizeof(sender));
		frame_deliver(l, buf, n, sender);
	}
}

static void
client_frames_process(struct listen_client *c, bool flush)
{
	size_t off = 0, used, len;
	const char *frame;

	while (off < c->len &&
	       (used = frame_next(c->buf + off, c->len - off, flush, &frame, &len)) > 0) {
		frame_deliver(c->l, frame, len, c->sender);
		off += used;
	}

	memmove(c->buf, c->buf + off, c->len - off);
	c->len -= off;
}

static void
client_free(struct listen_client *c)
{
	list_del(&c->list);
	c->l->client_count--;
	uloop_timeout_cancel(&c->close_timer);

	if (c->tls)
		ustream_free(&c->ssl.stream);

	ustream_free(&c->stream.stream);
	close(c->stream.fd.fd);
	free(c);
}

static void
client_close_cb(struct uloop_timeout *t)
{
	client_free(container_of(t, struct listen_client, close_timer));
}

/* Stream callbacks must not free the stream, so the close is deferred. */
static void
client_close(struct listen_client *c)
{
	client_frames_process(c, true);
	uloop_timeout_set(&c->close_timer, 0);
}

static void
client_read(struct listen_client *c, struct ustream *s)
{
	size_t take;
	char *data;
	int len;

	while ((data = ustream_get_read_buf(s, &len)) && len > 0) {
		if (c->rejected) {
			ustream_consume(s, len);
			continue;
		}

		take = sizeof(c->buf) - c->len;

		if ((size_t)len < take)
			take = len;

		memcpy(c->buf + c->len, data, take);
		c->len += take;
		ustream_consume(s, take);
		client_frames_process(c, false);
	}
}

static void
tcp_read_cb(struct ustream *s, int bytes)
{
	client_read(container_of(s, struct listen_client, stream.stream), s);
}

static void
ssl_read_cb(struct ustream *s, int bytes)
{
	client_read(container_of(s, struct listen_client, ssl.stream), s);
}

static void
tcp_state_cb(struct ustream *s)
{
	if (s->eof || s->write_error)
		client_close(container_of(s, struct listen_client, stream.stream));
}

static void
ssl_state_cb(struct ustream *s)
{
	if (s->eof || s->write_error)
		client_close(container_of(s, struct listen_client, ssl.stream));
}

static void
ssl_error_cb(struct ustream_ssl *ssl, int error, const char *str)
{
	client_close(container_of(ssl, struct listen_client, ssl));
}

static void
ssl_verify_error_cb(struct ustream_ssl *ssl, int error, const char *str)
{
	struct listen_client *c = container_of(ssl, struct listen_client, ssl);

	if (!c->l->peer_verify)
		return;

	ssl->stream.eof = true;
	client_close(c);
}

/* The openssl and wolfssl backends report no verify error for a client
 * that sends no certificate, so the handshake ends without one. ustream-ssl
 * reads on after this callback; the client drops that data. */
static void
ssl_connected_cb(struct ustream_ssl *ssl)
{
	struct listen_client *c = container_of(ssl, struct listen_client, ssl);

	if (!c->l->peer_verify || ssl->valid_cert || ssl->valid_cn)
		return;

	c->rejected = true;
	c->len = 0;
	ssl->stream.eof = true;
	uloop_timeout_set(&c->close_timer, 0);
}

static void
client_new(struct listener *l, int fd, const struct sockaddr_storage *ss)
{
	struct listen_client *c;

	if (l->client_count >= CLIENTS_MAX)
		client_free(list_first_entry(&l->clients, struct listen_client, list));

	c = calloc(1, sizeof(*c));

	if (!c) {
		close(fd);
		return;
	}

	c->l = l;
	c->close_timer.cb = client_close_cb;
	sender_format(l, ss, c->sender, sizeof(c->sender));
	list_add_tail(&c->list, &l->clients);
	l->client_count++;

	c->stream.stream.notify_read = tcp_read_cb;
	c->stream.stream.notify_state = tcp_state_cb;
	ustream_fd_init(&c->stream, fd);

	if (l->proto != LISTEN_TLS)
		return;

	c->tls = true;
	c->ssl.notify_connected = ssl_connected_cb;
	c->ssl.notify_error = ssl_error_cb;
	c->ssl.notify_verify_error = ssl_verify_error_cb;
	c->ssl.stream.notify_read = ssl_read_cb;
	c->ssl.stream.notify_state = ssl_state_cb;
	tls_ops()->init(&c->ssl, &c->stream.stream, l->ssl_ctx, true);
}

static void
tcp_accept_cb(struct uloop_fd *u, unsigned int events)
{
	struct listener *l = container_of(u, struct listener, fd);
	struct sockaddr_storage ss;
	socklen_t sl;
	int fd;

	while (true) {
		sl = sizeof(ss);
		fd = accept4(u->fd, (struct sockaddr *)&ss, &sl, SOCK_NONBLOCK | SOCK_CLOEXEC);

		if (fd < 0) {
			if (errno == EINTR)
				continue;

			return;
		}

		client_new(l, fd, &ss);
	}
}

/* "::" takes IPv4 as well unless the system set bindv6only; a host
 * without IPv6 falls back to 0.0.0.0. */
/* The path comes from a controller and ubbf-logd runs as root, so only one
 * file directly in SOCKET_DIR is used, which the jail mounts writable. */
static bool
unix_path_valid(const char *path)
{
	const char *name = path + strlen(SOCKET_DIR);

	if (strncmp(path, SOCKET_DIR, strlen(SOCKET_DIR)) || !*name || strchr(name, '/'))
		return false;

	if (!strcmp(name, ".") || !strcmp(name, ".."))
		return false;

	return strlen(path) < sizeof(((struct sockaddr_un *)0)->sun_path);
}

/* A socket file left by an earlier run would make the bind fail. Only a
 * socket is removed, never another kind of file. Local programs of any
 * user send to it, as to /dev/log. */
static int
unix_listener_open(struct listener *l)
{
	struct stat st;
	int fd;

	if (!unix_path_valid(l->path)) {
		errno = EINVAL;
		return -1;
	}

	if (!lstat(l->path, &st) && S_ISSOCK(st.st_mode))
		unlink(l->path);

	fd = usock(USOCK_UNIX | USOCK_UDP | USOCK_SERVER | USOCK_NONBLOCK, l->path, NULL);

	if (fd >= 0)
		chmod(l->path, 0666);

	return fd;
}

static void
listener_start(struct listener *l)
{
	int type = (l->proto == LISTEN_UDP ? USOCK_UDP : USOCK_TCP) | USOCK_SERVER | USOCK_NONBLOCK;
	char port[8];
	int fd;

	if (l->proto == LISTEN_UNIX) {
		fd = unix_listener_open(l);

		if (fd < 0) {
			snprintf(l->error, sizeof(l->error), "bind unix %s: %s", l->path,
				 errno == EINVAL ? "not a file name in " SOCKET_DIR : strerror(errno));
			ULOG_ERR("%s\n", l->error);
			uloop_timeout_set(&l->retry, BIND_RETRY_MS);
			return;
		}

		l->error[0] = 0;
		l->fd.fd = fd;
		l->fd.cb = udp_read_cb;
		uloop_fd_add(&l->fd, ULOOP_READ);
		return;
	}

	if (l->proto == LISTEN_TLS && !l->ssl_ctx) {
		l->ssl_ctx = tls_ctx_new(true, l->cert, l->ca_dir, l->peer_verify,
					 l->error, sizeof(l->error));

		if (!l->ssl_ctx) {
			ULOG_ERR("tls/%d: %s\n", l->port, l->error);
			uloop_timeout_set(&l->retry, BIND_RETRY_MS);
			return;
		}
	}

	snprintf(port, sizeof(port), "%d", l->port);
	fd = usock(type, "::", port);

	if (fd < 0)
		fd = usock(type, "0.0.0.0", port);

	if (fd < 0) {
		snprintf(l->error, sizeof(l->error), "bind %s/%d: %s",
			 proto_names[l->proto], l->port, strerror(errno));
		ULOG_ERR("%s\n", l->error);
		uloop_timeout_set(&l->retry, BIND_RETRY_MS);
		return;
	}

	l->fd.fd = fd;
	l->fd.cb = l->proto == LISTEN_UDP ? udp_read_cb : tcp_accept_cb;
	uloop_fd_add(&l->fd, ULOOP_READ);
}

static void
listener_retry_cb(struct uloop_timeout *t)
{
	listener_start(container_of(t, struct listener, retry));
}

/* Two Source rows with the same listener parameters share one socket. */
static void
listener_source_add(struct listener *l, int source_id, int default_pri)
{
	struct listener_source *sources;

	sources = realloc(l->sources, (l->source_count + 1) * sizeof(*sources));

	if (!sources)
		return;

	l->sources = sources;
	l->sources[l->source_count].id = source_id;
	l->sources[l->source_count].default_pri = default_pri;
	l->source_count++;
}

struct listener *
listener_get(enum listen_proto proto, int port, const char *path, const char *cert,
	     const char *ca_dir, bool peer_verify, int source_id, int default_pri)
{
	char key[4096];
	struct listener *l;

	snprintf(key, sizeof(key), "%d|%d|%s|%s|%s|%d", proto, port, path ? path : "",
		 cert ? cert : "", ca_dir ? ca_dir : "", peer_verify);

	list_for_each_entry(l, &listeners, list)
		if (!strcmp(l->key, key))
			goto found;

	l = calloc(1, sizeof(*l));

	if (!l)
		return NULL;

	l->key = strdup(key);
	l->proto = proto;
	l->port = port;
	l->path = path ? strdup(path) : NULL;
	l->cert = cert ? strdup(cert) : NULL;
	l->ca_dir = ca_dir ? strdup(ca_dir) : NULL;
	if (!l->key || (path && !l->path) || (cert && !l->cert) || (ca_dir && !l->ca_dir)) {
		free(l->key);
		free(l->path);
		free(l->cert);
		free(l->ca_dir);
		free(l);
		return NULL;
	}
	l->peer_verify = peer_verify;
	l->fd.fd = -1;
	l->retry.cb = listener_retry_cb;
	INIT_LIST_HEAD(&l->clients);
	list_add_tail(&l->list, &listeners);

found:
	l->used = true;
	listener_source_add(l, source_id, default_pri);

	return l;
}

static void
listener_free(struct listener *l)
{
	while (!list_empty(&l->clients))
		client_free(list_first_entry(&l->clients, struct listen_client, list));

	list_del(&l->list);
	uloop_timeout_cancel(&l->retry);

	if (l->fd.registered)
		uloop_fd_delete(&l->fd);

	if (l->fd.fd >= 0) {
		close(l->fd.fd);

		if (l->proto == LISTEN_UNIX)
			unlink(l->path);
	}

	tls_ctx_free(l->ssl_ctx);
	free(l->sources);
	free(l->key);
	free(l->path);
	free(l->cert);
	free(l->ca_dir);
	free(l);
}

void
listener_mark_unused(void)
{
	struct listener *l;

	list_for_each_entry(l, &listeners, list) {
		l->used = false;
		l->source_count = 0;
	}
}

/* Removed listeners close before new ones bind, so a listener whose TLS
 * settings changed can take the same port again. A kept listener that is
 * not bound tries again at once, for example after its certificate file
 * came back. */
void
listener_sweep(void)
{
	struct listener *l, *tmp;

	list_for_each_entry_safe(l, tmp, &listeners, list)
		if (!l->used)
			listener_free(l);

	list_for_each_entry(l, &listeners, list) {
		if (l->started) {
			if (!l->fd.registered)
				uloop_timeout_set(&l->retry, 0);

			continue;
		}

		l->started = true;
		listener_start(l);
	}
}

void
listener_free_all(void)
{
	struct listener *l, *tmp;

	list_for_each_entry_safe(l, tmp, &listeners, list)
		listener_free(l);
}

void
listener_status_add(struct listener *l, struct blob_buf *b, const char *name)
{
	void *t = blobmsg_open_table(b, name);

	blobmsg_add_string(b, "proto", proto_names[l->proto]);

	if (l->proto == LISTEN_UNIX)
		blobmsg_add_string(b, "path", l->path);
	else
		blobmsg_add_u32(b, "port", l->port);

	blobmsg_add_u8(b, "bound", l->fd.registered);
	blobmsg_add_u32(b, "clients", l->client_count);
	blobmsg_add_u64(b, "received", l->received);

	if (l->error[0])
		blobmsg_add_string(b, "error", l->error);

	blobmsg_close_table(b, t);
}
