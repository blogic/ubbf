/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

#include <string.h>
#include <sys/utsname.h>
#include <unistd.h>

#include <libubox/ustream.h>

#include "config.h"
#include "input.h"
#include "msg.h"

#define INPUT_RETRY_MS		1000
#define LOGD_SOURCE_KLOG	0

enum {
	LOG_MSG,
	LOG_ID,
	LOG_PRIO,
	LOG_SOURCE,
	LOG_TIME,
	__LOG_MAX
};

/* The fields logd sends for each ring entry (log_fill_msg() in ubox). */
static const struct blobmsg_policy log_policy[__LOG_MAX] = {
	[LOG_MSG] = { .name = "msg", .type = BLOBMSG_TYPE_STRING },
	[LOG_ID] = { .name = "id", .type = BLOBMSG_TYPE_INT32 },
	[LOG_PRIO] = { .name = "priority", .type = BLOBMSG_TYPE_INT32 },
	[LOG_SOURCE] = { .name = "source", .type = BLOBMSG_TYPE_INT32 },
	[LOG_TIME] = { .name = "time", .type = BLOBMSG_TYPE_INT64 },
};

static struct ubus_context *ubus_ctx;
static struct ubus_request request;
static bool request_pending;
static bool request_fd;
static struct ustream_fd stream;
static bool stream_active;
static struct uloop_timeout retry;
static struct log_msg local_msg;
static struct blob_buf b;
static char pending[8192];
static char entry[sizeof(pending)] __attribute__((aligned(8)));
static size_t pending_len;
static uint32_t last_id;
static uint64_t received;

static void
entry_handle(struct blob_attr *attr)
{
	struct blob_attr *tb[__LOG_MAX];
	struct utsname un;

	blobmsg_parse(log_policy, __LOG_MAX, tb, blob_data(attr), blob_len(attr));

	if (!tb[LOG_MSG] || !tb[LOG_ID] || !tb[LOG_PRIO] || !tb[LOG_SOURCE] || !tb[LOG_TIME])
		return;

	last_id = blobmsg_get_u32(tb[LOG_ID]);
	received++;

	/* Read for every message: `bbf-test -l` renames the device while the
	 * daemon runs. */
	if (uname(&un))
		un.nodename[0] = 0;

	msg_from_local(&local_msg, blobmsg_get_u32(tb[LOG_PRIO]),
		       blobmsg_get_u32(tb[LOG_SOURCE]) == LOGD_SOURCE_KLOG,
		       blobmsg_get_u64(tb[LOG_TIME]) / 1000,
		       blobmsg_get_string(tb[LOG_MSG]), un.nodename);
	config_dispatch(&local_msg, SOURCE_LOCAL);
}

/* An entry can cross the boundary between two ustream buffers, so the
 * entries are reassembled in a buffer of their own. */
static void
entries_process(void)
{
	struct blob_attr hdr;
	size_t off = 0, entry_len;

	/* logd sends entries back to back without padding, so each one is
	 * copied to an aligned buffer before it is parsed. */
	while (pending_len - off >= sizeof(hdr)) {
		memcpy(&hdr, pending + off, sizeof(hdr));
		entry_len = blob_raw_len(&hdr);

		if (entry_len < sizeof(hdr) || entry_len > sizeof(pending)) {
			off = pending_len;
			break;
		}

		if (pending_len - off < entry_len)
			break;

		memcpy(entry, pending + off, entry_len);
		entry_handle((struct blob_attr *)entry);
		off += entry_len;
	}

	memmove(pending, pending + off, pending_len - off);
	pending_len -= off;
}

static void
stream_read_cb(struct ustream *s, int bytes)
{
	size_t take;
	char *data;
	int len;

	while ((data = ustream_get_read_buf(s, &len)) && len > 0) {
		take = sizeof(pending) - pending_len;

		if ((size_t)len < take)
			take = len;

		memcpy(pending + pending_len, data, take);
		pending_len += take;
		ustream_consume(s, take);
		entries_process();
	}
}

static void
stream_state_cb(struct ustream *s)
{
	if (s->eof || s->write_error)
		uloop_timeout_set(&retry, INPUT_RETRY_MS);
}

static void
stream_teardown(void)
{
	if (!stream_active)
		return;

	ustream_free(&stream.stream);
	close(stream.fd.fd);
	stream_active = false;
	pending_len = 0;
}

static void
request_fd_cb(struct ubus_request *req, int fd)
{
	request_fd = true;
	memset(&stream, 0, sizeof(stream));
	stream.stream.notify_read = stream_read_cb;
	stream.stream.notify_state = stream_state_cb;
	ustream_fd_init(&stream, fd);
	stream_active = true;
}

static void
request_complete_cb(struct ubus_request *req, int ret)
{
	request_pending = false;

	if (ret || !request_fd)
		uloop_timeout_set(&retry, INPUT_RETRY_MS);
}

/* "stream" without "lines" sends the whole ring and then every new entry
 * over one pipe, the call logread uses; a reload never touches it. */
static void
input_open(void)
{
	uint32_t id;

	if (!ubus_ctx || request_pending || stream_active)
		return;

	if (ubus_lookup_id(ubus_ctx, "log", &id)) {
		uloop_timeout_set(&retry, INPUT_RETRY_MS);
		return;
	}

	blob_buf_init(&b, 0);
	blobmsg_add_u8(&b, "stream", 1);
	blobmsg_add_u8(&b, "oneshot", 0);

	request_fd = false;

	if (ubus_invoke_async(ubus_ctx, id, "read", b.head, &request)) {
		uloop_timeout_set(&retry, INPUT_RETRY_MS);
		return;
	}

	request.fd_cb = request_fd_cb;
	request.complete_cb = request_complete_cb;
	request_pending = true;
	ubus_complete_request_async(ubus_ctx, &request);
}

static void
retry_cb(struct uloop_timeout *t)
{
	stream_teardown();
	input_open();
}

void
input_start(struct ubus_context *ctx)
{
	ubus_ctx = ctx;
	retry.cb = retry_cb;
	input_open();
}

/* Opens the logd stream again, so the whole ring is read once more. */
void
input_replay(void)
{
	if (!ubus_ctx)
		return;

	if (request_pending)
		ubus_abort_request(ubus_ctx, &request);

	request_pending = false;
	uloop_timeout_cancel(&retry);
	stream_teardown();
	input_open();
}

void
input_stop(void)
{
	uloop_timeout_cancel(&retry);

	if (request_pending)
		ubus_abort_request(ubus_ctx, &request);

	request_pending = false;
	stream_teardown();
	blob_buf_free(&b);
}

void
input_status_add(struct blob_buf *buf, const char *name)
{
	void *t = blobmsg_open_table(buf, name);

	blobmsg_add_u8(buf, "connected", stream_active);
	blobmsg_add_u32(buf, "last_id", last_id);
	blobmsg_add_u64(buf, "received", received);
	blobmsg_close_table(buf, t);
}
