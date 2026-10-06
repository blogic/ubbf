/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

#include <syslog.h>

#include <libubox/ulog.h>
#include <libubus.h>

#include "config.h"
#include "input.h"
#include "ubus.h"

static struct ubus_auto_conn conn;
static struct blob_buf b;

/* Failures go in the reply, not in the status: with an error status,
 * ucode and other callers drop the reply data. */
static int
reload_handler(struct ubus_context *ctx, struct ubus_object *obj,
	       struct ubus_request_data *req, const char *method,
	       struct blob_attr *msg)
{
	bool ok;

	blob_buf_init(&b, 0);
	ok = config_reload(&b);
	blobmsg_add_u8(&b, "success", ok);
	ubus_send_reply(ctx, req, b.head);

	return UBUS_STATUS_OK;
}

static int
status_handler(struct ubus_context *ctx, struct ubus_object *obj,
	       struct ubus_request_data *req, const char *method,
	       struct blob_attr *msg)
{
	blob_buf_init(&b, 0);
	config_status_add(&b);
	ubus_send_reply(ctx, req, b.head);

	return UBUS_STATUS_OK;
}

static const struct ubus_method logd_methods[] = {
	UBUS_METHOD_NOARG("reload", reload_handler),
	UBUS_METHOD_NOARG("status", status_handler),
};

static struct ubus_object_type logd_object_type =
	UBUS_OBJECT_TYPE("ubbf-logd", logd_methods);

static struct ubus_object logd_object = {
	.name = "ubbf-logd",
	.type = &logd_object_type,
	.methods = logd_methods,
	.n_methods = ARRAY_SIZE(logd_methods),
};

static void
connect_cb(struct ubus_context *ctx)
{
	if (ubus_add_object(ctx, &logd_object))
		ULOG_ERR("unable to publish ubus object ubbf-logd\n");

	input_start(ctx);
}

void
logd_ubus_init(void)
{
	conn.cb = connect_cb;
	ubus_auto_connect(&conn);
}

void
logd_ubus_done(void)
{
	input_stop();
	ubus_auto_shutdown(&conn);
	blob_buf_free(&b);
}
