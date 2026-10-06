/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include <libubox/blobmsg_json.h>

#include "config.h"
#include "filter.h"
#include "input.h"
#include "listen.h"
#include "output.h"
#include "template.h"

struct log_source {
	int id;
	bool kernel;
	bool system;
	struct listener *listener;
	struct listener *unix_listener;
};

struct log_template {
	int id;
	char *expression;
	bool escape;
};

struct log_action {
	int id;
	int *sources;
	size_t source_count;
	struct log_filter **filters;
	size_t filter_count;
	struct log_template *template;
	bool structured;
	struct output *file;
	struct output *remote;
	char error[128];
};

struct log_config {
	struct log_source *sources;
	size_t source_count;
	struct log_filter *filters;
	size_t filter_count;
	struct log_template *templates;
	size_t template_count;
	struct log_action *actions;
	size_t action_count;
};

enum {
	CFG_SOURCES,
	CFG_FILTERS,
	CFG_TEMPLATES,
	CFG_ACTIONS,
	__CFG_MAX
};

static const struct blobmsg_policy config_policy[__CFG_MAX] = {
	[CFG_SOURCES] = { .name = "sources", .type = BLOBMSG_TYPE_TABLE },
	[CFG_FILTERS] = { .name = "filters", .type = BLOBMSG_TYPE_TABLE },
	[CFG_TEMPLATES] = { .name = "templates", .type = BLOBMSG_TYPE_TABLE },
	[CFG_ACTIONS] = { .name = "actions", .type = BLOBMSG_TYPE_ARRAY },
};

enum {
	SRC_KERNEL,
	SRC_SYSTEM,
	SRC_NETWORK,
	SRC_UNIX,
	__SRC_MAX
};

static const struct blobmsg_policy source_policy[__SRC_MAX] = {
	[SRC_KERNEL] = { .name = "kernel", .type = BLOBMSG_TYPE_BOOL },
	[SRC_SYSTEM] = { .name = "system", .type = BLOBMSG_TYPE_BOOL },
	[SRC_NETWORK] = { .name = "network", .type = BLOBMSG_TYPE_TABLE },
	[SRC_UNIX] = { .name = "unix", .type = BLOBMSG_TYPE_TABLE },
};

enum {
	UNIX_PATH,
	UNIX_DEFAULT_PRI,
	__UNIX_MAX
};

static const struct blobmsg_policy unix_policy[__UNIX_MAX] = {
	[UNIX_PATH] = { .name = "path", .type = BLOBMSG_TYPE_STRING },
	[UNIX_DEFAULT_PRI] = { .name = "default_pri", .type = BLOBMSG_CAST_INT64 },
};

/* The network listener of a source and the remote of an action share
 * their field names. */
enum {
	NET_PROTO,
	NET_ADDRESS,
	NET_PORT,
	NET_DEFAULT_PRI,
	NET_CERT,
	NET_CA_DIR,
	NET_PEER_VERIFY,
	__NET_MAX
};

static const struct blobmsg_policy net_policy[__NET_MAX] = {
	[NET_PROTO] = { .name = "proto", .type = BLOBMSG_TYPE_STRING },
	[NET_ADDRESS] = { .name = "address", .type = BLOBMSG_TYPE_STRING },
	[NET_PORT] = { .name = "port", .type = BLOBMSG_CAST_INT64 },
	[NET_DEFAULT_PRI] = { .name = "default_pri", .type = BLOBMSG_CAST_INT64 },
	[NET_CERT] = { .name = "cert", .type = BLOBMSG_TYPE_STRING },
	[NET_CA_DIR] = { .name = "ca_dir", .type = BLOBMSG_TYPE_STRING },
	[NET_PEER_VERIFY] = { .name = "peer_verify", .type = BLOBMSG_TYPE_BOOL },
};

enum {
	FLT_FACILITIES,
	FLT_SEVERITIES,
	FLT_PATTERN,
	FLT_ACTION,
	__FLT_MAX
};

static const struct blobmsg_policy filter_policy[__FLT_MAX] = {
	[FLT_FACILITIES] = { .name = "facilities", .type = BLOBMSG_CAST_INT64 },
	[FLT_SEVERITIES] = { .name = "severities", .type = BLOBMSG_CAST_INT64 },
	[FLT_PATTERN] = { .name = "pattern", .type = BLOBMSG_TYPE_STRING },
	[FLT_ACTION] = { .name = "action", .type = BLOBMSG_TYPE_STRING },
};

enum {
	TPL_EXPRESSION,
	TPL_ESCAPE,
	__TPL_MAX
};

static const struct blobmsg_policy template_policy[__TPL_MAX] = {
	[TPL_EXPRESSION] = { .name = "expression", .type = BLOBMSG_TYPE_STRING },
	[TPL_ESCAPE] = { .name = "escape", .type = BLOBMSG_TYPE_BOOL },
};

enum {
	ACT_ID,
	ACT_SOURCES,
	ACT_FILTERS,
	ACT_TEMPLATE,
	ACT_STRUCTURED,
	ACT_FILE,
	ACT_REMOTE,
	__ACT_MAX
};

static const struct blobmsg_policy action_policy[__ACT_MAX] = {
	[ACT_ID] = { .name = "id", .type = BLOBMSG_CAST_INT64 },
	[ACT_SOURCES] = { .name = "sources", .type = BLOBMSG_TYPE_ARRAY },
	[ACT_FILTERS] = { .name = "filters", .type = BLOBMSG_TYPE_ARRAY },
	[ACT_TEMPLATE] = { .name = "template", .type = BLOBMSG_CAST_INT64 },
	[ACT_STRUCTURED] = { .name = "structured", .type = BLOBMSG_TYPE_BOOL },
	[ACT_FILE] = { .name = "file", .type = BLOBMSG_TYPE_STRING },
	[ACT_REMOTE] = { .name = "remote", .type = BLOBMSG_TYPE_TABLE },
};

static struct log_config *config;
static const char *config_path = CONFIG_PATH_DEFAULT;
static struct blob_buf config_buf;
static char line[LINE_MAX_SIZE];

static int64_t
attr_int(struct blob_attr *attr, int64_t def)
{
	return attr ? blobmsg_cast_s64(attr) : def;
}

static bool
attr_bool(struct blob_attr *attr, bool def)
{
	return attr ? blobmsg_get_bool(attr) : def;
}

static const char *
attr_str(struct blob_attr *attr)
{
	const char *s = attr ? blobmsg_get_string(attr) : NULL;

	return (s && *s) ? s : NULL;
}

static int
attr_name_id(struct blob_attr *attr)
{
	return atoi(blobmsg_name(attr));
}

static size_t
attr_count(struct blob_attr *attr)
{
	struct blob_attr *cur;
	size_t count = 0;
	size_t rem;

	if (!attr)
		return 0;

	blobmsg_for_each_attr(cur, attr, rem)
		count++;

	return count;
}

static struct log_source *
source_find(struct log_config *cfg, int id)
{
	size_t i;

	for (i = 0; i < cfg->source_count; i++)
		if (cfg->sources[i].id == id)
			return &cfg->sources[i];

	return NULL;
}

static struct log_filter *
filter_find(struct log_config *cfg, int id)
{
	size_t i;

	for (i = 0; i < cfg->filter_count; i++)
		if (cfg->filters[i].id == id)
			return &cfg->filters[i];

	return NULL;
}

static struct log_template *
template_find(struct log_config *cfg, int id)
{
	size_t i;

	for (i = 0; i < cfg->template_count; i++)
		if (cfg->templates[i].id == id)
			return &cfg->templates[i];

	return NULL;
}

static void
action_error(struct log_action *a, const char *fmt, int value)
{
	if (!a->error[0])
		snprintf(a->error, sizeof(a->error), fmt, value);
}

static struct listener *
source_listener_parse(struct blob_attr *attr, int source_id)
{
	struct blob_attr *tb[__NET_MAX];
	const char *proto_name;
	enum listen_proto proto;

	blobmsg_parse_attr(net_policy, __NET_MAX, tb, attr);
	proto_name = attr_str(tb[NET_PROTO]);

	if (!proto_name || !strcmp(proto_name, "udp"))
		proto = LISTEN_UDP;
	else if (!strcmp(proto_name, "tcp"))
		proto = LISTEN_TCP;
	else if (!strcmp(proto_name, "tls"))
		proto = LISTEN_TLS;
	else
		return NULL;

	return listener_get(proto, attr_int(tb[NET_PORT], 1099), NULL,
			    attr_str(tb[NET_CERT]), attr_str(tb[NET_CA_DIR]),
			    attr_bool(tb[NET_PEER_VERIFY], false), source_id,
			    attr_int(tb[NET_DEFAULT_PRI], MSG_PRI_DEFAULT));
}

static struct listener *
source_unix_parse(struct blob_attr *attr, int source_id)
{
	struct blob_attr *tb[__UNIX_MAX];
	const char *path;

	blobmsg_parse_attr(unix_policy, __UNIX_MAX, tb, attr);
	path = attr_str(tb[UNIX_PATH]);

	if (!path)
		return NULL;

	return listener_get(LISTEN_UNIX, 0, path, NULL, NULL, false, source_id,
			    attr_int(tb[UNIX_DEFAULT_PRI], MSG_PRI_DEFAULT));
}

static void
sources_parse(struct log_config *cfg, struct blob_attr *attr)
{
	struct blob_attr *tb[__SRC_MAX], *cur;
	struct log_source *src;
	size_t rem;

	cfg->sources = calloc(attr_count(attr) + 1, sizeof(*cfg->sources));

	if (!attr || !cfg->sources)
		return;

	blobmsg_for_each_attr(cur, attr, rem) {
		blobmsg_parse_attr(source_policy, __SRC_MAX, tb, cur);
		src = &cfg->sources[cfg->source_count++];
		src->id = attr_name_id(cur);
		src->kernel = attr_bool(tb[SRC_KERNEL], false);
		src->system = attr_bool(tb[SRC_SYSTEM], false);

		if (tb[SRC_NETWORK])
			src->listener = source_listener_parse(tb[SRC_NETWORK], src->id);

		if (tb[SRC_UNIX])
			src->unix_listener = source_unix_parse(tb[SRC_UNIX], src->id);
	}
}

static enum filter_action
filter_action_parse(const char *name)
{
	if (name && !strcmp(name, "block"))
		return FILTER_BLOCK;

	if (name && !strcmp(name, "stop"))
		return FILTER_STOP;

	return FILTER_LOG;
}

static void
filters_parse(struct log_config *cfg, struct blob_attr *attr)
{
	struct blob_attr *tb[__FLT_MAX], *cur;
	size_t rem;

	cfg->filters = calloc(attr_count(attr) + 1, sizeof(*cfg->filters));

	if (!attr || !cfg->filters)
		return;

	blobmsg_for_each_attr(cur, attr, rem) {
		blobmsg_parse_attr(filter_policy, __FLT_MAX, tb, cur);
		filter_init(&cfg->filters[cfg->filter_count++], attr_name_id(cur),
			    attr_int(tb[FLT_FACILITIES], 0),
			    attr_int(tb[FLT_SEVERITIES], FILTER_SEVERITIES_ALL),
			    attr_str(tb[FLT_PATTERN]),
			    filter_action_parse(attr_str(tb[FLT_ACTION])));
	}
}

static void
templates_parse(struct log_config *cfg, struct blob_attr *attr)
{
	struct blob_attr *tb[__TPL_MAX], *cur;
	struct log_template *t;
	const char *expression;
	char *copy;
	size_t rem;

	cfg->templates = calloc(attr_count(attr) + 1, sizeof(*cfg->templates));

	if (!attr || !cfg->templates)
		return;

	blobmsg_for_each_attr(cur, attr, rem) {
		blobmsg_parse_attr(template_policy, __TPL_MAX, tb, cur);
		expression = attr_str(tb[TPL_EXPRESSION]);

		copy = expression ? strdup(expression) : NULL;
		if (!copy)
			continue;

		t = &cfg->templates[cfg->template_count++];
		t->id = attr_name_id(cur);
		t->expression = copy;
		t->escape = attr_bool(tb[TPL_ESCAPE], false);
	}
}

static struct output *
action_remote_parse(struct log_action *a, struct blob_attr *attr)
{
	struct blob_attr *tb[__NET_MAX];
	const char *proto_name, *address;
	enum output_type type;

	blobmsg_parse_attr(net_policy, __NET_MAX, tb, attr);
	proto_name = attr_str(tb[NET_PROTO]);
	address = attr_str(tb[NET_ADDRESS]);

	if (!address) {
		action_error(a, "remote of action %d has no address", a->id);
		return NULL;
	}

	if (!proto_name || !strcmp(proto_name, "udp"))
		type = OUTPUT_UDP;
	else if (!strcmp(proto_name, "tcp"))
		type = OUTPUT_TCP;
	else if (!strcmp(proto_name, "tls"))
		type = OUTPUT_TLS;
	else {
		action_error(a, "unknown protocol in action %d", a->id);
		return NULL;
	}

	return output_get(type, NULL, address, attr_int(tb[NET_PORT], 514),
			  attr_str(tb[NET_CERT]), attr_str(tb[NET_CA_DIR]),
			  attr_bool(tb[NET_PEER_VERIFY], false));
}

static void
action_filters_parse(struct log_config *cfg, struct log_action *a, struct blob_attr *attr)
{
	struct log_filter *f;
	struct blob_attr *cur;
	size_t rem;
	int id;

	a->filters = calloc(attr_count(attr) + 1, sizeof(*a->filters));

	if (!attr || !a->filters)
		return;

	blobmsg_for_each_attr(cur, attr, rem) {
		id = blobmsg_cast_s64(cur);
		f = filter_find(cfg, id);

		if (!f) {
			action_error(a, "unknown filter %d", id);
			continue;
		}

		if (f->invalid)
			action_error(a, "invalid pattern in filter %d", id);

		a->filters[a->filter_count++] = f;
	}
}

static void
action_sources_parse(struct log_action *a, struct blob_attr *attr)
{
	struct blob_attr *cur;
	size_t rem;

	a->sources = calloc(attr_count(attr) + 1, sizeof(*a->sources));

	if (!attr || !a->sources)
		return;

	blobmsg_for_each_attr(cur, attr, rem)
		a->sources[a->source_count++] = blobmsg_cast_s64(cur);
}

static void
actions_parse(struct log_config *cfg, struct blob_attr *attr)
{
	struct blob_attr *tb[__ACT_MAX], *cur;
	struct log_action *a;
	const char *file;
	size_t rem;
	int id;

	cfg->actions = calloc(attr_count(attr) + 1, sizeof(*cfg->actions));

	if (!attr || !cfg->actions)
		return;

	blobmsg_for_each_attr(cur, attr, rem) {
		blobmsg_parse_attr(action_policy, __ACT_MAX, tb, cur);
		a = &cfg->actions[cfg->action_count++];
		a->id = attr_int(tb[ACT_ID], 0);
		a->structured = attr_bool(tb[ACT_STRUCTURED], false);
		action_sources_parse(a, tb[ACT_SOURCES]);
		action_filters_parse(cfg, a, tb[ACT_FILTERS]);

		if (tb[ACT_TEMPLATE]) {
			id = blobmsg_cast_s64(tb[ACT_TEMPLATE]);
			a->template = template_find(cfg, id);

			if (!a->template)
				action_error(a, "unknown template %d", id);
		}

		file = attr_str(tb[ACT_FILE]);

		if (file)
			a->file = output_get(OUTPUT_FILE, file, NULL, 0, NULL, NULL, false);

		if (tb[ACT_REMOTE])
			a->remote = action_remote_parse(a, tb[ACT_REMOTE]);
	}
}

static void
config_destroy(struct log_config *cfg)
{
	size_t i;

	if (!cfg)
		return;

	for (i = 0; i < cfg->filter_count; i++)
		filter_free(&cfg->filters[i]);

	for (i = 0; i < cfg->template_count; i++)
		free(cfg->templates[i].expression);

	for (i = 0; i < cfg->action_count; i++) {
		free(cfg->actions[i].sources);
		free(cfg->actions[i].filters);
	}

	free(cfg->sources);
	free(cfg->filters);
	free(cfg->templates);
	free(cfg->actions);
	free(cfg);
}

static void
config_report(struct log_config *cfg, struct blob_buf *report)
{
	char id[16];
	size_t i;
	void *t;

	if (!report)
		return;

	t = blobmsg_open_table(report, "actions");

	for (i = 0; i < cfg->action_count; i++) {
		snprintf(id, sizeof(id), "%d", cfg->actions[i].id);
		blobmsg_add_string(report, id, cfg->actions[i].error[0] ? cfg->actions[i].error : "ok");
	}

	blobmsg_close_table(report, t);
}

void
config_init(const char *path)
{
	if (path)
		config_path = path;
}

/* A missing file means no actions. A file that is not valid JSON keeps the
 * running configuration. Outputs and listeners that stay are reused, so
 * their connections and queues survive the reload. */
bool
config_reload(struct blob_buf *report)
{
	struct blob_attr *tb[__CFG_MAX];
	struct log_config *cfg, *old;
	bool had_actions;

	blob_buf_init(&config_buf, 0);

	if (!access(config_path, F_OK) && !blobmsg_add_json_from_file(&config_buf, config_path)) {
		if (report)
			blobmsg_add_string(report, "error", "config is not valid JSON");

		return false;
	}

	cfg = calloc(1, sizeof(*cfg));

	if (!cfg)
		return false;

	blobmsg_parse(config_policy, __CFG_MAX, tb, blob_data(config_buf.head),
		      blob_len(config_buf.head));

	output_mark_unused();
	listener_mark_unused();

	sources_parse(cfg, tb[CFG_SOURCES]);
	filters_parse(cfg, tb[CFG_FILTERS]);
	templates_parse(cfg, tb[CFG_TEMPLATES]);
	actions_parse(cfg, tb[CFG_ACTIONS]);

	old = config;
	had_actions = old && old->action_count;
	config = cfg;
	config_destroy(old);

	output_sweep();
	listener_sweep();
	config_report(cfg, report);
	blob_buf_free(&config_buf);

	/* At boot the daemon reads the ring before the first apply writes the
	 * config, and drops it; read it again for the first actions. */
	if (!had_actions && cfg->action_count)
		input_replay();

	return true;
}

static bool
action_source_match(struct log_action *a, const struct log_msg *msg, int source_id)
{
	struct log_source *src;
	size_t i;

	for (i = 0; i < a->source_count; i++) {
		src = source_find(config, a->sources[i]);

		if (!src)
			continue;

		if (source_id != SOURCE_LOCAL) {
			if (src->id == source_id)
				return true;

			continue;
		}

		if ((src->kernel && msg->kernel) || (src->system && !msg->kernel))
			return true;
	}

	return false;
}

static size_t
action_line_render(struct log_action *a, const struct log_msg *msg, bool remote)
{
	if (a->template)
		return template_render(a->template->expression, a->template->escape,
				       msg, line, sizeof(line));

	if (!remote)
		return format_file(msg, line, sizeof(line));

	if (a->structured)
		return format_rfc5424(msg, line, sizeof(line));

	return format_rfc3164(msg, line, sizeof(line));
}

void
config_dispatch(const struct log_msg *msg, int source_id)
{
	struct log_action *a;
	size_t i, len;

	if (!config)
		return;

	for (i = 0; i < config->action_count; i++) {
		a = &config->actions[i];

		if (!action_source_match(a, msg, source_id))
			continue;

		switch (filter_chain_eval(a->filters, a->filter_count, msg)) {
		case FILTER_HALT:
			return;

		case FILTER_SKIP:
			continue;

		case FILTER_DELIVER:
			break;
		}

		if (a->remote) {
			len = action_line_render(a, msg, true);
			output_write(a->remote, line, len);
		}

		if (a->file) {
			len = action_line_render(a, msg, false);
			output_write(a->file, line, len);
		}
	}
}

void
config_status_add(struct blob_buf *b)
{
	struct log_action *a;
	char id[16];
	void *t, *at;
	size_t i;

	input_status_add(b, "input");

	if (!config)
		return;

	t = blobmsg_open_table(b, "actions");

	for (i = 0; i < config->action_count; i++) {
		a = &config->actions[i];
		snprintf(id, sizeof(id), "%d", a->id);
		at = blobmsg_open_table(b, id);

		if (a->file)
			output_status_add(a->file, b, "file");

		if (a->remote)
			output_status_add(a->remote, b, "remote");

		if (a->error[0])
			blobmsg_add_string(b, "error", a->error);

		blobmsg_close_table(b, at);
	}

	blobmsg_close_table(b, t);

	t = blobmsg_open_table(b, "listeners");

	for (i = 0; i < config->source_count; i++) {
		if (config->sources[i].listener) {
			snprintf(id, sizeof(id), "%d", config->sources[i].id);
			listener_status_add(config->sources[i].listener, b, id);
		}

		if (config->sources[i].unix_listener) {
			snprintf(id, sizeof(id), "%d-unix", config->sources[i].id);
			listener_status_add(config->sources[i].unix_listener, b, id);
		}
	}

	blobmsg_close_table(b, t);
}

void
config_free(void)
{
	config_destroy(config);
	config = NULL;
	listener_free_all();
	output_free_all();
}
