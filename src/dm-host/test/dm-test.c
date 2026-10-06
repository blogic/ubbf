/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

/*
 * Test module for dm-host and the loader in datamodel.uc. Not installed.
 */

#include <signal.h>
#include <stdlib.h>
#include <unistd.h>

#include <libubox/uloop.h>

#include "ubbf/dm-module.h"

static struct uloop_timeout later_timer;
static struct ubbf_dm_op *later_op;
static struct uloop_timeout slow_timer;
static struct ubbf_dm_op *slow_op;

static int
root_get(struct ubbf_dm_req *req)
{
	struct blob_attr *eth = ubbf_dm_table(req->needs, "Device.Ethernet.Interface");

	blobmsg_add_string(req->out, "Value", "hello");
	blobmsg_add_string(req->out, "Name", ubbf_dm_str(req->config, "Name"));
	blobmsg_add_string(req->out, "Needs", eth ? "yes" : "no");
	return UBBF_DM_OK;
}

static int
item_get(struct ubbf_dm_req *req)
{
	if (req->instance < 1 || req->instance > 2)
		return UBBF_DM_ABSENT;

	blobmsg_printf(req->out, "Index", "%lld", (long long)req->instance);
	return UBBF_DM_OK;
}

static int
echo_op(struct ubbf_dm_op *op)
{
	blobmsg_add_string(op->out, "Text", ubbf_dm_str(op->input, "Text"));
	ubbf_dm_log(6, "echo %s", ubbf_dm_str(op->input, "Text"));
	return UBBF_DM_OK;
}

static int
fail_op(struct ubbf_dm_op *op)
{
	return -7022;
}

static int
crash_op(struct ubbf_dm_op *op)
{
	raise(SIGSEGV);
	return UBBF_DM_OK;
}

static int
hang_op(struct ubbf_dm_op *op)
{
	for (;;)
		pause();
	return UBBF_DM_OK;
}

static void
later_done(struct uloop_timeout *t)
{
	blobmsg_add_string(later_op->out, "Result", "done");
	ubbf_dm_op_complete(later_op, 0, NULL);
	later_op = NULL;
}

static int
later_op_start(struct ubbf_dm_op *op)
{
	later_op = op;
	later_timer.cb = later_done;
	uloop_timeout_set(&later_timer, 100);
	return UBBF_DM_DEFERRED;
}

/* Completes after its 1 s deadline has passed. */
static void
slow_done(struct uloop_timeout *t)
{
	ubbf_dm_op_complete(slow_op, 0, NULL);
	slow_op = NULL;
}

static int
slow_op_start(struct ubbf_dm_op *op)
{
	slow_op = op;
	slow_timer.cb = slow_done;
	uloop_timeout_set(&slow_timer, 1500);
	return UBBF_DM_DEFERRED;
}

static const struct ubbf_dm_object objects[] = {
	{ .pattern = "Device.X_UBBF_DMTest", .get = root_get },
	{ .pattern = "Device.X_UBBF_DMTest.Item" },
	{ .pattern = "Device.X_UBBF_DMTest.Item.{i}", .get = item_get, .not_addable = true, .since = "2.20" },
	{ .pattern = NULL }
};

static const struct ubbf_dm_operation operations[] = {
	{ "Device.X_UBBF_DMTest.Echo()", false, echo_op },
	{ "Device.X_UBBF_DMTest.Fail()", false, fail_op },
	{ "Device.X_UBBF_DMTest.Crash()", false, crash_op },
	{ "Device.X_UBBF_DMTest.Hang()", false, hang_op },
	{ "Device.X_UBBF_DMTest.Later()", true, later_op_start },
	{ "Device.X_UBBF_DMTest.Slow()", true, slow_op_start, 1 },
	{ NULL }
};

static const char *const needs[] = { "Device.Ethernet.Interface", NULL };

const struct ubbf_dm_module ubbf_dm_module = {
	.api = UBBF_DM_API,
	.name = "dmtest",
	.needs = needs,
	.objects = objects,
	.operations = operations,
};
