/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

#include <errno.h>
#include <fcntl.h>
#include <netdb.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <signal.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/uio.h>
#include <syslog.h>
#include <unistd.h>

#include <libubox/ulog.h>
#include <libubox/utils.h>

#include "output.h"
#include "tls.h"

#define QUEUE_LINES_MAX		1000
#define QUEUE_BYTES_MAX		(256 * 1024)
#define STREAM_PENDING_MAX	(256 * 1024)
#define RETRY_MIN_MS		1000
#define RETRY_MAX_MS		30000
#define CONNECT_TIMEOUT_MS	10000
#define KEEPALIVE_IDLE_S	60
#define KEEPALIVE_INTVL_S	10
#define KEEPALIVE_COUNT		3
#define LOG_DIR			"/var/log/"

struct queued_line {
	struct list_head list;
	size_t len;
	char data[];
};

struct inflight_line {
	struct list_head list;
	size_t len;
};

struct resolve_result {
	int ok;
	socklen_t len;
	struct sockaddr_storage addr;
};

static LIST_HEAD(outputs);

static const char *const state_names[] = {
	[OUTPUT_CONNECTING] = "connecting",
	[OUTPUT_CONNECTED] = "connected",
	[OUTPUT_UNREACHABLE] = "unreachable",
	[OUTPUT_ERROR] = "error",
};

static const char *const type_names[] = {
	[OUTPUT_FILE] = "file",
	[OUTPUT_UDP] = "udp",
	[OUTPUT_TCP] = "tcp",
	[OUTPUT_TLS] = "tls",
};

static void output_connect(struct output *o);

static char *
str_dup_opt(const char *s)
{
	return s ? strdup(s) : NULL;
}

static void
output_error_set(struct output *o, const char *fmt, ...)
{
	va_list ap;

	va_start(ap, fmt);
	vsnprintf(o->error, sizeof(o->error), fmt, ap);
	va_end(ap);
}

static bool
output_is_stream(struct output *o)
{
	return o->type == OUTPUT_TCP || o->type == OUTPUT_TLS;
}

static void
retry_schedule(struct output *o)
{
	uloop_timeout_set(&o->retry, o->retry_delay);
	o->retry_delay *= 2;

	if (o->retry_delay > RETRY_MAX_MS)
		o->retry_delay = RETRY_MAX_MS;
}

static void
queue_drop_oldest(struct output *o)
{
	struct queued_line *q = list_first_entry(&o->queue, struct queued_line, list);

	o->queue_lines--;
	o->queue_bytes -= q->len;
	o->dropped++;
	list_del(&q->list);
	free(q);
}

static void
queue_push(struct output *o, const char *line, size_t len)
{
	struct queued_line *q;

	if (len > QUEUE_BYTES_MAX) {
		o->dropped++;
		return;
	}

	while (o->queue_lines >= QUEUE_LINES_MAX || o->queue_bytes + len > QUEUE_BYTES_MAX)
		queue_drop_oldest(o);

	q = malloc(sizeof(*q) + len);

	if (!q) {
		o->dropped++;
		return;
	}

	memcpy(q->data, line, len);
	q->len = len;
	list_add_tail(&q->list, &o->queue);
	o->queue_lines++;
	o->queue_bytes += len;
}

static void
queue_free(struct output *o)
{
	while (!list_empty(&o->queue))
		queue_drop_oldest(o);
}

static size_t
stream_buffered(struct output *o)
{
	size_t bytes = 0;

	if (o->stream_active)
		bytes += o->stream.stream.w.data_bytes;

	if (o->ssl_active)
		bytes += o->ssl.stream.w.data_bytes;

	return bytes;
}

/* A line counts as sent once the stream buffers no longer hold any of it.
 * For TLS the buffer of the connection holds ciphertext, which is longer
 * than the line, so a line counts as sent late rather than early. */
static void
inflight_settle(struct output *o)
{
	size_t buffered = stream_buffered(o);
	struct inflight_line *l;

	while (!list_empty(&o->inflight)) {
		l = list_first_entry(&o->inflight, struct inflight_line, list);

		if (o->inflight_bytes - l->len < buffered)
			break;

		o->inflight_bytes -= l->len;
		o->sent++;
		list_del(&l->list);
		free(l);
	}
}

static void
inflight_add(struct output *o, size_t len)
{
	struct inflight_line *l = malloc(sizeof(*l));

	if (!l) {
		o->sent++;
		return;
	}

	l->len = len;
	list_add_tail(&l->list, &o->inflight);
	o->inflight_bytes += len;
	inflight_settle(o);
}

/* Lines still in the stream buffers when the connection goes are lost. */
static void
inflight_drop(struct output *o)
{
	struct inflight_line *l, *tmp;

	list_for_each_entry_safe(l, tmp, &o->inflight, list) {
		o->dropped++;
		list_del(&l->list);
		free(l);
	}

	o->inflight_bytes = 0;
}

/* TLS uses the octet counting of RFC 5425, "MSG-LEN SP SYSLOG-MSG"; TCP ends
 * each line with a newline, as RFC 6587 allows. */
static void
stream_send(struct output *o, const char *line, size_t len)
{
	bool newline = !len || line[len - 1] != '\n';
	char hdr[24];
	int n;

	if (o->out->w.data_bytes > STREAM_PENDING_MAX) {
		o->dropped++;
		return;
	}

	if (o->type == OUTPUT_TLS) {
		n = snprintf(hdr, sizeof(hdr), "%zu ", len);
		ustream_write(o->out, hdr, n, true);
		ustream_write(o->out, line, len, false);
		inflight_add(o, n + len);
		return;
	}

	ustream_write(o->out, line, len, newline);

	if (newline)
		ustream_write(o->out, "\n", 1, false);

	inflight_add(o, len + newline);
}

static void
queue_flush(struct output *o)
{
	struct queued_line *q;

	while (!list_empty(&o->queue)) {
		q = list_first_entry(&o->queue, struct queued_line, list);
		list_del(&q->list);
		o->queue_lines--;
		o->queue_bytes -= q->len;
		stream_send(o, q->data, q->len);
		free(q);
	}
}

static void
resolve_stop(struct output *o)
{
	if (o->resolve_fd.registered)
		uloop_fd_delete(&o->resolve_fd);

	if (o->resolve_fd.fd >= 0) {
		close(o->resolve_fd.fd);
		o->resolve_fd.fd = -1;
	}

	if (o->resolver.pending) {
		kill(o->resolver.pid, SIGKILL);
		uloop_process_delete(&o->resolver);
	}
}

static void
stream_teardown(struct output *o)
{
	resolve_stop(o);

	if (o->connect_fd.registered)
		uloop_fd_delete(&o->connect_fd);

	uloop_timeout_cancel(&o->connect_timeout);
	inflight_drop(o);

	if (o->ssl_active) {
		ustream_free(&o->ssl.stream);
		o->ssl_active = false;
	}

	if (o->stream_active) {
		ustream_free(&o->stream.stream);
		close(o->stream.fd.fd);
		o->stream_active = false;
	}

	if (o->fd >= 0) {
		close(o->fd);
		o->fd = -1;
	}

	o->out = NULL;
}

/* Callbacks of the stream must not free it, so the teardown runs from the
 * retry timer; it then waits for the backoff and connects again. */
static void
output_fail(struct output *o, const char *fmt, ...)
{
	va_list ap;

	va_start(ap, fmt);
	vsnprintf(o->error, sizeof(o->error), fmt, ap);
	va_end(ap);

	if (o->state != OUTPUT_UNREACHABLE)
		ULOG_WARN("%s %s:%s unreachable: %s\n", type_names[o->type], o->host, o->port, o->error);

	o->state = OUTPUT_UNREACHABLE;
	o->out = NULL;
	o->closing = true;
	uloop_timeout_set(&o->retry, 0);
}

static void
output_retry_cb(struct uloop_timeout *t)
{
	struct output *o = container_of(t, struct output, retry);

	if (o->closing) {
		o->closing = false;
		stream_teardown(o);
		retry_schedule(o);
		return;
	}

	output_connect(o);
}

static void
output_connected(struct output *o)
{
	if (o->state != OUTPUT_CONNECTED)
		ULOG_INFO("%s %s:%s connected\n", type_names[o->type], o->host, o->port);

	uloop_timeout_cancel(&o->connect_timeout);
	o->state = OUTPUT_CONNECTED;
	o->error[0] = 0;
	o->retry_delay = RETRY_MIN_MS;

	if (output_is_stream(o))
		queue_flush(o);
}

static void
stream_read_cb(struct ustream *s, int bytes)
{
	int len;

	while (ustream_get_read_buf(s, &len) && len > 0)
		ustream_consume(s, len);
}

static void
stream_write_cb(struct ustream *s, int bytes)
{
	inflight_settle(container_of(s, struct output, stream.stream));
}

static void
tcp_state_cb(struct ustream *s)
{
	struct output *o = container_of(s, struct output, stream.stream);

	if (s->eof || s->write_error)
		output_fail(o, "connection closed");
}

static void
ssl_state_cb(struct ustream *s)
{
	struct output *o = container_of(s, struct output, ssl.stream);

	if (s->eof || s->write_error)
		output_fail(o, "connection closed");
}

static void
ssl_connected_cb(struct ustream_ssl *ssl)
{
	struct output *o = container_of(ssl, struct output, ssl);

	if (o->peer_verify && !ssl->valid_cn) {
		output_fail(o, "certificate does not match %s", o->host);
		return;
	}

	output_connected(o);
}

static void
ssl_error_cb(struct ustream_ssl *ssl, int error, const char *str)
{
	struct output *o = container_of(ssl, struct output, ssl);

	output_fail(o, "tls: %s", str);
}

/* ustream-ssl reports a failed verification and goes on; setting eof is its
 * documented way to stop the connection before data is written. */
static void
ssl_verify_error_cb(struct ustream_ssl *ssl, int error, const char *str)
{
	struct output *o = container_of(ssl, struct output, ssl);

	if (!o->peer_verify)
		return;

	ssl->stream.eof = true;
	output_fail(o, "tls: %s", str);
}

static void
stream_start(struct output *o, int fd)
{
	const struct ustream_ssl_ops *ops = tls_ops();

	memset(&o->stream, 0, sizeof(o->stream));
	o->stream.stream.notify_read = stream_read_cb;
	o->stream.stream.notify_write = stream_write_cb;
	o->stream.stream.notify_state = tcp_state_cb;
	ustream_fd_init(&o->stream, fd);
	o->stream_active = true;

	if (o->type == OUTPUT_TCP) {
		o->out = &o->stream.stream;
		output_connected(o);
		return;
	}

	memset(&o->ssl, 0, sizeof(o->ssl));
	o->ssl.notify_connected = ssl_connected_cb;
	o->ssl.notify_error = ssl_error_cb;
	o->ssl.notify_verify_error = ssl_verify_error_cb;
	o->ssl.stream.notify_read = stream_read_cb;
	o->ssl.stream.notify_state = ssl_state_cb;
	o->ssl_active = true;
	ops->init(&o->ssl, &o->stream.stream, o->ssl_ctx, false);
	ops->set_peer_cn(&o->ssl, o->host);
	o->out = &o->ssl.stream;
}

static void
connect_cb(struct uloop_fd *fd, unsigned int events)
{
	struct output *o = container_of(fd, struct output, connect_fd);
	socklen_t len = sizeof(int);
	int err = 0;

	uloop_fd_delete(fd);

	if (getsockopt(fd->fd, SOL_SOCKET, SO_ERROR, &err, &len) || err) {
		output_fail(o, "connect: %s", strerror(err ? err : errno));
		return;
	}

	o->fd = -1;
	stream_start(o, fd->fd);
}

static void
connect_timeout_cb(struct uloop_timeout *t)
{
	struct output *o = container_of(t, struct output, connect_timeout);

	output_fail(o, o->resolver.pending ? "cannot resolve %s: timeout" : "connect: timeout",
		    o->host);
}

/* A peer that goes away without a FIN is found after about 90 s instead of
 * the two hours of the kernel default, before the queue fills. */
static void
keepalive_set(int fd)
{
	int on = 1, idle = KEEPALIVE_IDLE_S, intvl = KEEPALIVE_INTVL_S, count = KEEPALIVE_COUNT;

	setsockopt(fd, SOL_SOCKET, SO_KEEPALIVE, &on, sizeof(on));
	setsockopt(fd, IPPROTO_TCP, TCP_KEEPIDLE, &idle, sizeof(idle));
	setsockopt(fd, IPPROTO_TCP, TCP_KEEPINTVL, &intvl, sizeof(intvl));
	setsockopt(fd, IPPROTO_TCP, TCP_KEEPCNT, &count, sizeof(count));
}

static void
socket_open(struct output *o)
{
	int type = o->type == OUTPUT_UDP ? SOCK_DGRAM : SOCK_STREAM;
	int fd;

	fd = socket(o->addr.ss_family, type | SOCK_NONBLOCK | SOCK_CLOEXEC, 0);

	if (fd < 0) {
		output_fail(o, "socket: %s", strerror(errno));
		return;
	}

	if (type == SOCK_STREAM)
		keepalive_set(fd);

	if (connect(fd, (struct sockaddr *)&o->addr, o->addr_len) && errno != EINPROGRESS) {
		close(fd);
		output_fail(o, "connect: %s", strerror(errno));
		return;
	}

	o->fd = fd;

	if (o->type == OUTPUT_UDP) {
		output_connected(o);
		return;
	}

	o->connect_fd.fd = fd;
	o->connect_fd.cb = connect_cb;
	uloop_fd_add(&o->connect_fd, ULOOP_WRITE | ULOOP_EDGE_TRIGGER);
}

static void
resolve_result_set(struct output *o, const struct addrinfo *ai)
{
	memcpy(&o->addr, ai->ai_addr, ai->ai_addrlen);
	o->addr_len = ai->ai_addrlen;
}

static void
resolve_read_cb(struct uloop_fd *fd, unsigned int events)
{
	struct output *o = container_of(fd, struct output, resolve_fd);
	struct resolve_result r;
	ssize_t n;

	n = read(fd->fd, &r, sizeof(r));
	resolve_stop(o);

	if (n != sizeof(r) || !r.ok || r.len > sizeof(o->addr)) {
		output_fail(o, "cannot resolve %s", o->host);
		return;
	}

	memcpy(&o->addr, &r.addr, r.len);
	o->addr_len = r.len;
	socket_open(o);
}

static void
resolver_exit_cb(struct uloop_process *p, int ret)
{
}

static void
resolve_child(struct output *o, int fd, const struct addrinfo *hints)
{
	struct resolve_result r = { 0 };
	struct addrinfo *res;

	if (!getaddrinfo(o->host, o->port, hints, &res)) {
		r.ok = 1;
		r.len = res->ai_addrlen;
		memcpy(&r.addr, res->ai_addr, res->ai_addrlen);
	}

	_exit(write(fd, &r, sizeof(r)) == sizeof(r) ? 0 : 1);
}

/* getaddrinfo() blocks for the resolver timeout when a name server does not
 * answer, so a host name is resolved in a child process; the event loop goes
 * on serving the listeners and the logd input meanwhile. */
static void
resolve_start(struct output *o)
{
	struct addrinfo hints = {
		.ai_socktype = o->type == OUTPUT_UDP ? SOCK_DGRAM : SOCK_STREAM,
		.ai_flags = AI_NUMERICHOST | AI_NUMERICSERV,
	};
	struct addrinfo *res;
	int fds[2];
	pid_t pid;

	uloop_timeout_set(&o->connect_timeout, CONNECT_TIMEOUT_MS);

	if (!getaddrinfo(o->host, o->port, &hints, &res)) {
		resolve_result_set(o, res);
		freeaddrinfo(res);
		socket_open(o);
		return;
	}

	hints.ai_flags = AI_NUMERICSERV;

	if (pipe2(fds, O_CLOEXEC)) {
		output_fail(o, "pipe: %s", strerror(errno));
		return;
	}

	pid = fork();

	if (pid < 0) {
		close(fds[0]);
		close(fds[1]);
		output_fail(o, "fork: %s", strerror(errno));
		return;
	}

	if (!pid) {
		close(fds[0]);
		resolve_child(o, fds[1], &hints);
	}

	close(fds[1]);
	o->resolve_fd.fd = fds[0];
	o->resolve_fd.cb = resolve_read_cb;
	uloop_fd_add(&o->resolve_fd, ULOOP_READ);
	o->resolver.pid = pid;
	o->resolver.cb = resolver_exit_cb;
	uloop_process_add(&o->resolver);
}

/* Only a path below /var/log is written: the path comes from a controller,
 * and ubbf-logd runs as root. */
static bool
file_path_valid(const char *path)
{
	const char *p = path + strlen(LOG_DIR);
	size_t len;

	if (strncmp(path, LOG_DIR, strlen(LOG_DIR)) || !*p)
		return false;

	for (; *p; p += len + (p[len] == '/')) {
		len = strcspn(p, "/");

		if (!len || (len == 1 && p[0] == '.') || (len == 2 && !strncmp(p, "..", 2)))
			return false;
	}

	return true;
}

static void
file_fail(struct output *o, enum output_state state)
{
	o->state = state;

	if (o->fd >= 0)
		close(o->fd);

	o->fd = -1;
}

static bool
file_open(struct output *o)
{
	char dir[512];
	struct stat st;
	char *slash;

	if (!file_path_valid(o->path)) {
		output_error_set(o, "path is not below " LOG_DIR);
		o->state = OUTPUT_ERROR;
		return false;
	}

	snprintf(dir, sizeof(dir), "%s", o->path);
	slash = strrchr(dir, '/');
	*slash = 0;
	mkdir_p(dir, 0755);

	o->fd = open(o->path, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC | O_NOFOLLOW, 0600);

	if (o->fd < 0) {
		output_error_set(o, "open: %s", strerror(errno));
		file_fail(o, OUTPUT_UNREACHABLE);
		return false;
	}

	if (fstat(o->fd, &st)) {
		output_error_set(o, "stat: %s", strerror(errno));
		file_fail(o, OUTPUT_UNREACHABLE);
		return false;
	}

	if (!S_ISREG(st.st_mode)) {
		output_error_set(o, "not a regular file");
		file_fail(o, OUTPUT_ERROR);
		return false;
	}

	o->dev = st.st_dev;
	o->ino = st.st_ino;
	o->state = OUTPUT_CONNECTED;
	o->error[0] = 0;

	return true;
}

/* A file rotated or removed by someone else is opened again by path. */
static void
file_write(struct output *o, const char *line, size_t len, bool newline)
{
	struct iovec iov[2] = {
		{ .iov_base = (void *)line, .iov_len = len },
		{ .iov_base = "\n", .iov_len = 1 },
	};
	struct stat st;
	ssize_t want = len + newline;

	if (o->fd >= 0 && (lstat(o->path, &st) || st.st_ino != o->ino || st.st_dev != o->dev)) {
		close(o->fd);
		o->fd = -1;
	}

	if (o->fd < 0 && !file_open(o)) {
		o->dropped++;
		return;
	}

	if (writev(o->fd, iov, newline ? 2 : 1) != want) {
		output_error_set(o, "write: %s", strerror(errno));
		o->dropped++;
		return;
	}

	o->sent++;
}

static void
udp_write(struct output *o, const char *line, size_t len)
{
	if (o->fd < 0 || o->state != OUTPUT_CONNECTED) {
		o->dropped++;
		return;
	}

	if (send(o->fd, line, len, 0) < 0) {
		output_error_set(o, "send: %s", strerror(errno));
		o->dropped++;
		return;
	}

	o->sent++;
}

static void
output_connect(struct output *o)
{
	switch (o->type) {
	case OUTPUT_FILE:
		file_open(o);
		return;

	case OUTPUT_TLS:
		if (!o->ssl_ctx) {
			o->ssl_ctx = tls_ctx_new(false, o->cert, o->ca_dir, o->peer_verify,
						 o->error, sizeof(o->error));

			if (!o->ssl_ctx) {
				ULOG_WARN("tls %s:%s: %s\n", o->host, o->port, o->error);
				o->state = OUTPUT_ERROR;
				retry_schedule(o);
				return;
			}
		}
		break;

	case OUTPUT_UDP:
	case OUTPUT_TCP:
		break;
	}

	if (o->state != OUTPUT_UNREACHABLE)
		o->state = OUTPUT_CONNECTING;

	resolve_start(o);
}

struct output *
output_get(enum output_type type, const char *path, const char *host, int port,
	   const char *cert, const char *ca_dir, bool peer_verify)
{
	char key[1024], port_str[8];
	struct output *o;

	snprintf(key, sizeof(key), "%d|%s|%s|%d|%s|%s|%d", type, path ? path : "",
		 host ? host : "", port, cert ? cert : "", ca_dir ? ca_dir : "", peer_verify);

	list_for_each_entry(o, &outputs, list) {
		if (!strcmp(o->key, key)) {
			o->used = true;
			return o;
		}
	}

	o = calloc(1, sizeof(*o));

	if (!o)
		return NULL;

	snprintf(port_str, sizeof(port_str), "%d", port);
	o->key = strdup(key);
	o->type = type;
	o->path = str_dup_opt(path);
	o->host = str_dup_opt(host);
	o->port = strdup(port_str);
	o->cert = str_dup_opt(cert);
	o->ca_dir = str_dup_opt(ca_dir);
	if (!o->key || !o->port || (path && !o->path) || (host && !o->host) ||
	    (cert && !o->cert) || (ca_dir && !o->ca_dir)) {
		free(o->key);
		free(o->path);
		free(o->host);
		free(o->port);
		free(o->cert);
		free(o->ca_dir);
		free(o);
		return NULL;
	}
	o->peer_verify = peer_verify;
	o->fd = -1;
	o->resolve_fd.fd = -1;
	o->used = true;
	o->state = OUTPUT_CONNECTING;
	o->retry_delay = RETRY_MIN_MS;
	o->retry.cb = output_retry_cb;
	o->connect_timeout.cb = connect_timeout_cb;
	INIT_LIST_HEAD(&o->queue);
	INIT_LIST_HEAD(&o->inflight);
	list_add_tail(&o->list, &outputs);

	return o;
}

static void
output_free(struct output *o)
{
	list_del(&o->list);
	uloop_timeout_cancel(&o->retry);
	stream_teardown(o);
	queue_free(o);
	tls_ctx_free(o->ssl_ctx);
	free(o->key);
	free(o->path);
	free(o->host);
	free(o->port);
	free(o->cert);
	free(o->ca_dir);
	free(o);
}

void
output_mark_unused(void)
{
	struct output *o;

	list_for_each_entry(o, &outputs, list)
		o->used = false;
}

/* Removed outputs go first, then the new ones start; an output kept by a
 * reload keeps its connection and its queue. A kept output whose TLS setup
 * failed tries again at once, for example after its certificate file came
 * back. */
void
output_sweep(void)
{
	struct output *o, *tmp;

	list_for_each_entry_safe(o, tmp, &outputs, list)
		if (!o->used)
			output_free(o);

	list_for_each_entry(o, &outputs, list) {
		if (o->started) {
			if (o->state == OUTPUT_ERROR && o->type != OUTPUT_FILE) {
				o->retry_delay = RETRY_MIN_MS;
				uloop_timeout_set(&o->retry, 0);
			}

			continue;
		}

		o->started = true;
		output_connect(o);
	}
}

void
output_free_all(void)
{
	struct output *o, *tmp;

	list_for_each_entry_safe(o, tmp, &outputs, list)
		output_free(o);
}

void
output_write(struct output *o, const char *line, size_t len)
{
	switch (o->type) {
	case OUTPUT_FILE:
		file_write(o, line, len, !len || line[len - 1] != '\n');
		return;

	case OUTPUT_UDP:
		udp_write(o, line, len);
		return;

	case OUTPUT_TCP:
	case OUTPUT_TLS:
		if (o->out && o->state == OUTPUT_CONNECTED)
			stream_send(o, line, len);
		else
			queue_push(o, line, len);
		return;
	}
}

void
output_status_add(struct output *o, struct blob_buf *b, const char *name)
{
	void *t = blobmsg_open_table(b, name);

	blobmsg_add_string(b, "type", type_names[o->type]);
	blobmsg_add_string(b, "state", state_names[o->state]);
	blobmsg_add_u64(b, "sent", o->sent);
	blobmsg_add_u64(b, "dropped", o->dropped);

	if (output_is_stream(o))
		blobmsg_add_u32(b, "queued", o->queue_lines);

	if (o->error[0])
		blobmsg_add_string(b, "error", o->error);

	blobmsg_close_table(b, t);
}
