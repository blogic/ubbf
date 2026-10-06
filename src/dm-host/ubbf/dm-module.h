/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

#ifndef UBBF_DM_MODULE_H
#define UBBF_DM_MODULE_H

#include <stdbool.h>
#include <stdint.h>
#include <libubox/blobmsg.h>

/*
 * A native data model module: a shared object that dm-host loads in a
 * process of its own. obuspa talks to dm-host over a ubus channel, so a
 * fault in the module ends that process and not the data model.
 */

#define UBBF_DM_API		2

/* Return values of the handlers. Negative values are USP_ERR_* codes. */
#define UBBF_DM_OK		0
#define UBBF_DM_ABSENT		1
#define UBBF_DM_DEFERRED	2

/* ubbf_dm_object.max_instances of a table that never holds a row. */
#define UBBF_DM_NO_ROWS		-1

/** One get request for an object of the module. */
struct ubbf_dm_req {
	const char *pattern;		/* "Device.USB.Port.{i}" */
	const char *path;		/* "Device.USB.Port.2" */
	int64_t instance;		/* last {i} of the path, 0 for none */
	struct blob_attr *config;	/* stored row, NULL for none */
	struct blob_attr *parent;	/* stored parent row, NULL for none */
	struct blob_attr *needs;	/* subtrees named in ubbf_dm_module.needs */
	struct blob_buf *out;		/* the handler adds the parameters */
};

/** One operation request. An async operation keeps it until completion. */
struct ubbf_dm_op {
	const char *path;		/* the operation pattern */
	struct blob_attr *input;
	const char *command_key;
	struct blob_attr *instances;	/* array of the {i} of the path */
	struct blob_buf *out;		/* output arguments */
	void *priv;			/* free for the module */
};

/**
 * Get handler.
 *
 * @return UBBF_DM_OK with the parameters in req->out, UBBF_DM_ABSENT when
 *         the object does not exist, or a negative USP_ERR_* code
 */
typedef int (*ubbf_dm_get_fn)(struct ubbf_dm_req *req);

/**
 * Operation handler.
 *
 * @return UBBF_DM_OK with the output in op->out, a negative USP_ERR_* code,
 *         or, for an async operation, UBBF_DM_DEFERRED and a later call of
 *         ubbf_dm_op_complete()
 */
typedef int (*ubbf_dm_op_fn)(struct ubbf_dm_op *op);

struct ubbf_dm_object {
	const char *pattern;
	const char *schema;		/* key in schema-<name>.so, NULL for none */
	const char *since;		/* TR-181 version gate, NULL for none */
	const char *until;
	bool not_addable;
	int max_instances;		/* 0: no limit, or UBBF_DM_NO_ROWS */
	ubbf_dm_get_fn get;		/* NULL for an object without a handler */
};

struct ubbf_dm_operation {
	const char *path;		/* "Device.USB.USBHosts.Host.{i}.Reset()" */
	bool async;
	ubbf_dm_op_fn handler;
	unsigned int timeout;		/* async: seconds to complete, 0 for 60 */
};

struct ubbf_dm_module {
	int api;			/* UBBF_DM_API */
	const char *name;
	const char *const *needs;	/* NULL-terminated config paths, or NULL */
	const struct ubbf_dm_object *objects;		/* ends with a NULL pattern */
	const struct ubbf_dm_operation *operations;	/* ends with a NULL path, or NULL */
	int (*init)(void);		/* runs inside uloop; non-zero ends dm-host */
	void (*commit)(struct blob_attr *config);
	void (*abort)(struct blob_attr *config);
};

/* The one symbol dm-host looks up in a module. */
extern const struct ubbf_dm_module ubbf_dm_module;

/* Services of dm-host for the module. */
void ubbf_dm_op_complete(struct ubbf_dm_op *op, int err, const char *msg);
void ubbf_dm_event(const char *path, struct blob_attr *args);
void ubbf_dm_log(int prio, const char *fmt, ...)
	__attribute__((format(printf, 2, 3)));

/**
 * Returns a string member of a table.
 *
 * @return the value, or "" when the table or the member is missing
 */
const char *ubbf_dm_str(struct blob_attr *table, const char *name);

/**
 * Returns a member of a table of any type.
 *
 * @return the member, or NULL
 */
struct blob_attr *ubbf_dm_member(struct blob_attr *table, const char *name);

/**
 * Returns a table member of a table, such as a subtree of `needs`.
 *
 * @return the member, or NULL
 */
struct blob_attr *ubbf_dm_table(struct blob_attr *table, const char *name);

#endif
