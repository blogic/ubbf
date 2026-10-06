/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

/*
 * dm-host runs one native data model module in a process of its own. obuspa
 * starts it with the module path as its argument and a ubus channel on
 * DM_HOST_FD, and talks blobmsg to it: describe, get, operate, commit and
 * abort. Requests the other way (event, log, complete) need no reply.
 */

#include <dirent.h>
#include <dlfcn.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <syslog.h>
#include <unistd.h>

#include <libubox/uloop.h>
#include <libubus.h>

#include "ubbf/dm-module.h"

#define DM_HOST_FD		3

static struct ubus_context ctx;
static const struct ubbf_dm_module *mod;

/* An operation the module completes later. */
struct dm_op_pending {
	struct ubbf_dm_op op;
	uint32_t id;
	struct blob_buf out;
	struct blob_attr *msg;
};

/* Async operations report back with a message of their own rather than
 * with a deferred reply, which would be bound by the channel timeout of the
 * get requests. */
static uint32_t op_next_id = 1;

/**
 * Closes every descriptor above the channel. obuspa's own descriptors are
 * not all close-on-exec, and the module must not hold them.
 */
static void
fds_close_above_channel(void)
{
	DIR *dir = opendir("/proc/self/fd");
	struct dirent *e;

	if (!dir)
		return;

	while ((e = readdir(dir)) != NULL) {
		int fd = atoi(e->d_name);

		if (fd > DM_HOST_FD && fd != dirfd(dir))
			close(fd);
	}

	closedir(dir);
}

const char *
ubbf_dm_str(struct blob_attr *table, const char *name)
{
	struct blob_attr *cur;
	size_t rem;

	if (!table)
		return "";

	blobmsg_for_each_attr(cur, table, rem) {
		if (blobmsg_type(cur) == BLOBMSG_TYPE_STRING && !strcmp(blobmsg_name(cur), name))
			return blobmsg_get_string(cur);
	}

	return "";
}

struct blob_attr *
ubbf_dm_member(struct blob_attr *table, const char *name)
{
	struct blob_attr *cur;
	size_t rem;

	if (!table)
		return NULL;

	blobmsg_for_each_attr(cur, table, rem) {
		if (!strcmp(blobmsg_name(cur), name))
			return cur;
	}

	return NULL;
}

struct blob_attr *
ubbf_dm_table(struct blob_attr *table, const char *name)
{
	struct blob_attr *cur;
	size_t rem;

	if (!table)
		return NULL;

	blobmsg_for_each_attr(cur, table, rem) {
		if (blobmsg_type(cur) == BLOBMSG_TYPE_TABLE && !strcmp(blobmsg_name(cur), name))
			return cur;
	}

	return NULL;
}

/**
 * Sends a request to obuspa that needs no reply.
 */
static void
parent_notify(const char *method, struct blob_buf *b)
{
	struct ubus_request req;

	if (ubus_invoke_async(&ctx, 0, method, b->head, &req))
		return;

	ubus_abort_request(&ctx, &req);
}

void
ubbf_dm_event(const char *path, struct blob_attr *args)
{
	struct blob_buf b = {};

	blobmsg_buf_init(&b);
	blobmsg_add_string(&b, "path", path);
	if (args)
		blobmsg_add_field(&b, BLOBMSG_TYPE_TABLE, "args", blobmsg_data(args), blobmsg_data_len(args));
	parent_notify("event", &b);
	blob_buf_free(&b);
}

void
ubbf_dm_log(int prio, const char *fmt, ...)
{
	struct blob_buf b = {};
	va_list ap;

	blobmsg_buf_init(&b);
	blobmsg_add_u32(&b, "prio", prio);
	va_start(ap, fmt);
	blobmsg_vprintf(&b, "msg", fmt, ap);
	va_end(ap);
	parent_notify("log", &b);
	blob_buf_free(&b);
}

/**
 * Adds the object and operation tables of the module to a reply.
 */
static void
describe_build(struct blob_buf *b)
{
	const struct ubbf_dm_object *obj;
	const struct ubbf_dm_operation *op;
	void *list, *entry;

	blobmsg_add_u32(b, "api", UBBF_DM_API);
	blobmsg_add_string(b, "name", mod->name);

	list = blobmsg_open_array(b, "needs");
	for (const char *const *n = mod->needs; n && *n; n++)
		blobmsg_add_string(b, NULL, *n);
	blobmsg_close_array(b, list);

	list = blobmsg_open_array(b, "objects");
	for (obj = mod->objects; obj && obj->pattern; obj++) {
		entry = blobmsg_open_table(b, NULL);
		blobmsg_add_string(b, "pattern", obj->pattern);
		if (obj->schema)
			blobmsg_add_string(b, "schema", obj->schema);
		if (obj->since)
			blobmsg_add_string(b, "since", obj->since);
		if (obj->until)
			blobmsg_add_string(b, "until", obj->until);
		blobmsg_add_u8(b, "addable", !obj->not_addable);
		if (obj->max_instances)
			blobmsg_add_u32(b, "max_instances",
					obj->max_instances == UBBF_DM_NO_ROWS ? 0 : (uint32_t)obj->max_instances);
		blobmsg_add_u8(b, "get", obj->get != NULL);
		blobmsg_close_table(b, entry);
	}
	blobmsg_close_array(b, list);

	list = blobmsg_open_array(b, "operations");
	for (op = mod->operations; op && op->path; op++) {
		entry = blobmsg_open_table(b, NULL);
		blobmsg_add_string(b, "path", op->path);
		blobmsg_add_u8(b, "async", op->async);
		if (op->timeout)
			blobmsg_add_u32(b, "timeout", op->timeout);
		blobmsg_close_table(b, entry);
	}
	blobmsg_close_array(b, list);
}

static const struct ubbf_dm_object *
object_find(const char *pattern)
{
	for (const struct ubbf_dm_object *obj = mod->objects; obj && obj->pattern; obj++)
		if (!strcmp(obj->pattern, pattern))
			return obj;

	return NULL;
}

static const struct ubbf_dm_operation *
operation_find(const char *path)
{
	for (const struct ubbf_dm_operation *op = mod->operations; op && op->path; op++)
		if (!strcmp(op->path, path))
			return op;

	return NULL;
}

enum {
	GET_PATTERN,
	GET_PATH,
	GET_INSTANCE,
	GET_CONFIG,
	GET_PARENT,
	GET_NEEDS,
	__GET_MAX
};

static const struct blobmsg_policy get_policy[__GET_MAX] = {
	[GET_PATTERN] = { "pattern", BLOBMSG_TYPE_STRING },
	[GET_PATH] = { "path", BLOBMSG_TYPE_STRING },
	[GET_INSTANCE] = { "instance", BLOBMSG_TYPE_UNSPEC },
	[GET_CONFIG] = { "config", BLOBMSG_TYPE_TABLE },
	[GET_PARENT] = { "parent", BLOBMSG_TYPE_TABLE },
	[GET_NEEDS] = { "needs", BLOBMSG_TYPE_TABLE },
};

/**
 * Runs the get handler of an object. A missing object is UBUS_STATUS_NOT_FOUND,
 * which obuspa reads as null.
 */
static int
get_handle(struct ubus_request_data *ureq, struct blob_attr *msg)
{
	struct blob_attr *tb[__GET_MAX];
	const struct ubbf_dm_object *obj;
	struct blob_buf out = {};
	struct ubbf_dm_req req = {};
	int rv;

	blobmsg_parse(get_policy, __GET_MAX, tb, blob_data(msg), blob_len(msg));
	if (!tb[GET_PATTERN] || !tb[GET_PATH])
		return UBUS_STATUS_INVALID_ARGUMENT;

	obj = object_find(blobmsg_get_string(tb[GET_PATTERN]));
	if (!obj || !obj->get)
		return UBUS_STATUS_METHOD_NOT_FOUND;

	blobmsg_buf_init(&out);
	req.pattern = obj->pattern;
	req.path = blobmsg_get_string(tb[GET_PATH]);
	req.instance = tb[GET_INSTANCE] ? blobmsg_cast_s64(tb[GET_INSTANCE]) : 0;
	req.config = tb[GET_CONFIG];
	req.parent = tb[GET_PARENT];
	req.needs = tb[GET_NEEDS];
	req.out = &out;

	rv = obj->get(&req);
	if (rv == UBBF_DM_OK)
		ubus_send_reply(&ctx, ureq, out.head);

	blob_buf_free(&out);

	return (rv == UBBF_DM_OK) ? UBUS_STATUS_OK : UBUS_STATUS_NOT_FOUND;
}

/**
 * Adds the outcome of an operation to a reply: the output on success, the
 * USP_ERR_* code and message otherwise.
 */
static void
op_reply_build(struct blob_buf *b, struct blob_buf *out, int err, const char *msg)
{
	blobmsg_buf_init(b);
	blobmsg_add_u32(b, "err", (uint32_t)(err < 0 ? -err : err));
	if (msg)
		blobmsg_add_string(b, "msg", msg);
	blobmsg_add_field(b, BLOBMSG_TYPE_TABLE, "output", blob_data(out->head), blob_len(out->head));
}

void
ubbf_dm_op_complete(struct ubbf_dm_op *op, int err, const char *msg)
{
	struct dm_op_pending *p = container_of(op, struct dm_op_pending, op);
	struct blob_buf b = {};

	op_reply_build(&b, &p->out, err, msg);
	blobmsg_add_u32(&b, "id", p->id);
	parent_notify("complete", &b);

	blob_buf_free(&b);
	blob_buf_free(&p->out);
	free(p->msg);
	free(p);
}

enum {
	OP_PATH,
	OP_INPUT,
	OP_COMMAND_KEY,
	OP_INSTANCES,
	__OP_MAX
};

static const struct blobmsg_policy op_policy[__OP_MAX] = {
	[OP_PATH] = { "path", BLOBMSG_TYPE_STRING },
	[OP_INPUT] = { "input", BLOBMSG_TYPE_TABLE },
	[OP_COMMAND_KEY] = { "command_key", BLOBMSG_TYPE_STRING },
	[OP_INSTANCES] = { "instances", BLOBMSG_TYPE_ARRAY },
};

/**
 * Runs an operation. The request data is copied, because an async
 * operation outlives the message it came in.
 */
static int
operate_handle(struct ubus_request_data *ureq, struct blob_attr *msg)
{
	struct blob_attr *tb[__OP_MAX];
	const struct ubbf_dm_operation *def;
	struct dm_op_pending *p;
	struct blob_buf b = {};
	int rv;

	p = calloc(1, sizeof(*p));
	if (!p)
		return UBUS_STATUS_UNKNOWN_ERROR;

	p->msg = blob_memdup(msg);
	if (!p->msg) {
		free(p);
		return UBUS_STATUS_UNKNOWN_ERROR;
	}

	blobmsg_parse(op_policy, __OP_MAX, tb, blob_data(p->msg), blob_len(p->msg));
	def = tb[OP_PATH] ? operation_find(blobmsg_get_string(tb[OP_PATH])) : NULL;
	if (!def) {
		free(p->msg);
		free(p);
		return UBUS_STATUS_METHOD_NOT_FOUND;
	}

	blobmsg_buf_init(&p->out);
	p->op.path = def->path;
	p->op.input = tb[OP_INPUT];
	p->op.command_key = tb[OP_COMMAND_KEY] ? blobmsg_get_string(tb[OP_COMMAND_KEY]) : "";
	p->op.instances = tb[OP_INSTANCES];
	p->op.out = &p->out;

	p->id = op_next_id++;

	rv = def->handler(&p->op);
	if (def->async && rv == UBBF_DM_DEFERRED) {
		blobmsg_buf_init(&b);
		blobmsg_add_u32(&b, "id", p->id);
		ubus_send_reply(&ctx, ureq, b.head);
		blob_buf_free(&b);
		return UBUS_STATUS_OK;
	}

	op_reply_build(&b, &p->out, rv, NULL);
	ubus_send_reply(&ctx, ureq, b.head);
	blob_buf_free(&b);
	blob_buf_free(&p->out);
	free(p->msg);
	free(p);

	return UBUS_STATUS_OK;
}

/**
 * Hands the module subtree after a commit or an abort to the module.
 */
static int
hook_handle(void (*hook)(struct blob_attr *), struct blob_attr *msg)
{
	struct blob_attr *config = ubbf_dm_table(msg, "config");

	if (hook)
		hook(config);

	return UBUS_STATUS_OK;
}

static int
channel_request(struct ubus_context *uctx, struct ubus_object *obj,
		struct ubus_request_data *req, const char *method,
		struct blob_attr *msg)
{
	struct blob_buf b = {};

	if (!method)
		return UBUS_STATUS_INVALID_COMMAND;

	if (!strcmp(method, "describe")) {
		blobmsg_buf_init(&b);
		describe_build(&b);
		ubus_send_reply(uctx, req, b.head);
		blob_buf_free(&b);
		return UBUS_STATUS_OK;
	}

	if (!strcmp(method, "get"))
		return get_handle(req, msg);
	if (!strcmp(method, "operate"))
		return operate_handle(req, msg);
	if (!strcmp(method, "commit"))
		return hook_handle(mod->commit, msg);
	if (!strcmp(method, "abort"))
		return hook_handle(mod->abort, msg);

	return UBUS_STATUS_METHOD_NOT_FOUND;
}

static void
channel_lost(struct ubus_context *uctx)
{
	uloop_end();
}

int
main(int argc, char **argv)
{
	void *handle;

	if (argc != 2) {
		fprintf(stderr, "usage: %s <module.so>\n", argv[0]);
		return 1;
	}

	fds_close_above_channel();
	openlog("dm-host", LOG_PID, LOG_DAEMON);

	handle = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
	if (!handle) {
		syslog(LOG_ERR, "%s: %s", argv[1], dlerror());
		return 1;
	}

	mod = dlsym(handle, "ubbf_dm_module");
	if (!mod || mod->api != UBBF_DM_API) {
		syslog(LOG_ERR, "%s: no ubbf_dm_module of API %d", argv[1], UBBF_DM_API);
		return 1;
	}

	uloop_init();

	if (ubus_channel_connect(&ctx, DM_HOST_FD, channel_request)) {
		syslog(LOG_ERR, "%s: no channel on fd %d", argv[1], DM_HOST_FD);
		return 1;
	}

	ctx.connection_lost = channel_lost;
	ubus_add_uloop(&ctx);

	if (mod->init && mod->init()) {
		syslog(LOG_ERR, "%s: init failed", argv[1]);
		return 1;
	}

	uloop_run();
	uloop_done();

	return 0;
}
