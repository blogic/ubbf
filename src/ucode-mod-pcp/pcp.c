/* SPDX-License-Identifier: GPL-2.0-only */

/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

#include <ucode/module.h>

#include <pcpnatpmp/pcpnatpmp.h>

#include <arpa/inet.h>
#include <netdb.h>
#include <stdlib.h>
#include <string.h>

#define PCP_CTX_TYPE  "pcp.context"
#define PCP_FLOW_TYPE "pcp.flow"

enum {
	CTX_SLOT_FLOW_CB,
	CTX_SLOT_MAX
};

struct pcp_module_flow;

struct pcp_module_ctx {
	pcp_ctx_t *pcp;
	uc_vm_t *vm;
	/* not a counted reference: the callback runs only inside pulse(),
	 * while the script holds the context */
	uc_value_t *obj;
	struct pcp_module_flow *flows;
	int64_t next_flow_id;
};

/* The library frees every flow of a context in pcp_terminate(), so the
 * context keeps a list of its flow resources and detaches them first. */
struct pcp_module_flow {
	pcp_flow_t *flow;
	struct pcp_module_ctx *ctx;
	struct pcp_module_flow *prev, *next;
	int64_t id;
};

static void
flow_detach(struct pcp_module_flow *mf)
{
	struct pcp_module_ctx *mc = mf->ctx;

	if (!mc)
		return;

	if (mf->prev)
		mf->prev->next = mf->next;
	else
		mc->flows = mf->next;

	if (mf->next)
		mf->next->prev = mf->prev;

	mf->prev = mf->next = NULL;
	mf->ctx = NULL;
}

static void
ctx_terminate(struct pcp_module_ctx *mc, int close_flows)
{
	if (!mc->pcp)
		return;

	while (mc->flows) {
		mc->flows->flow = NULL;
		flow_detach(mc->flows);
	}

	pcp_terminate(mc->pcp, close_flows);
	free(mc->pcp);
	mc->pcp = NULL;
}

static void
pcp_flow_resource_free(void *ptr)
{
	struct pcp_module_flow *mf = ptr;

	if (mf->flow)
		pcp_delete_flow(mf->flow);
	flow_detach(mf);
	free(mf);
}

static void
pcp_ctx_resource_free(void *ptr)
{
	ctx_terminate(ptr, 1);
}

/*
 * Parses a numeric address. TR-181 types these parameters as IPAddress,
 * so a host name is refused instead of being resolved.
 */
static int
addr_parse(const char *host, uint16_t port, struct sockaddr_storage *ss)
{
	struct sockaddr_in6 *sin6 = (struct sockaddr_in6 *)ss;
	struct sockaddr_in *sin = (struct sockaddr_in *)ss;

	memset(ss, 0, sizeof(*ss));

	if (inet_pton(AF_INET, host, &sin->sin_addr) == 1) {
		sin->sin_family = AF_INET;
		sin->sin_port = htons(port);
		return AF_INET;
	}

	if (inet_pton(AF_INET6, host, &sin6->sin6_addr) == 1) {
		sin6->sin6_family = AF_INET6;
		sin6->sin6_port = htons(port);
		return AF_INET6;
	}

	return -1;
}

static int
opt_addr(uc_value_t *opts, const char *ip_key, const char *port_key,
	 struct sockaddr_storage *ss)
{
	uc_value_t *ip = ucv_object_get(opts, ip_key, NULL);
	uc_value_t *port = port_key ? ucv_object_get(opts, port_key, NULL) : NULL;
	uint16_t port_val = 0;

	if (ucv_type(port) == UC_INTEGER)
		port_val = (uint16_t)ucv_int64_get(port);

	if (ucv_type(ip) == UC_STRING && ucv_string_length(ip) > 0)
		return addr_parse(ucv_string_get(ip), port_val, ss);

	if (!port_val)
		return 0;

	/* a port without an address: the address part stays unspecified */
	return addr_parse("::", port_val, ss);
}

static uc_value_t *
addr_string(const struct in6_addr *addr)
{
	char buf[INET6_ADDRSTRLEN];

	if (IN6_IS_ADDR_V4MAPPED(addr)) {
		if (!inet_ntop(AF_INET, &addr->s6_addr[12], buf, sizeof(buf)))
			return NULL;
	}
	else if (!inet_ntop(AF_INET6, addr, buf, sizeof(buf))) {
		return NULL;
	}

	return ucv_string_new(buf);
}

static const char *
flow_state_name(pcp_fstate_e state)
{
	switch (state) {
	case pcp_state_processing:
		return "processing";
	case pcp_state_succeeded:
		return "succeeded";
	case pcp_state_partial_result:
		return "partial";
	case pcp_state_short_lifetime_error:
		return "short_lifetime";
	case pcp_state_failed:
	default:
		return "failed";
	}
}

static uc_value_t *
flow_info_object(uc_vm_t *vm, pcp_flow_t *flow)
{
	pcp_flow_info_t *fi;
	uc_value_t *obj;
	size_t cnt = 0;

	fi = pcp_flow_get_info(flow, &cnt);
	if (!fi)
		return NULL;

	if (cnt == 0) {
		free(fi);
		return NULL;
	}

	obj = ucv_object_new(vm);
	ucv_object_add(obj, "state", ucv_string_new(flow_state_name(fi->result)));
	ucv_object_add(obj, "result_code", ucv_int64_new(fi->pcp_result_code));
	ucv_object_add(obj, "external_ip", addr_string(&fi->ext_ip));
	ucv_object_add(obj, "external_port", ucv_int64_new(ntohs(fi->ext_port)));
	ucv_object_add(obj, "lifetime_end", ucv_int64_new(fi->recv_lifetime_end));
	ucv_object_add(obj, "protocol", ucv_int64_new(fi->protocol));
	ucv_object_add(obj, "internal_port", ucv_int64_new(ntohs(fi->int_port)));

	free(fi);

	return obj;
}

/* pcp.create([autodiscovery]) -> context */
static uc_value_t *
uc_pcp_create(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *auto_arg = uc_fn_arg(0);
	uint8_t autodiscovery = DISABLE_AUTODISCOVERY;
	struct pcp_module_ctx *mc;
	pcp_ctx_t *pcp;
	uc_value_t *obj;

	if (auto_arg && ucv_is_truish(auto_arg))
		autodiscovery = ENABLE_AUTODISCOVERY;

	pcp = pcp_init(autodiscovery, NULL);
	if (!pcp)
		return NULL;

	obj = ucv_resource_create_ex(vm, PCP_CTX_TYPE, (void **)&mc,
				     CTX_SLOT_MAX, sizeof(*mc));
	if (!obj) {
		pcp_terminate(pcp, 0);
		free(pcp);
		return NULL;
	}

	mc->pcp = pcp;
	mc->vm = vm;
	mc->obj = obj;

	return obj;
}

/*
 * ctx.add_server(name_or_address, [version])
 *   -> { id, address, additional } or { error: "resolve" | "network" }
 *
 * Each address the name resolves to is tried in order; the library refuses
 * an address that has no route.
 */
static uc_value_t *
uc_pcp_add_server(uc_vm_t *vm, size_t nargs)
{
	struct pcp_module_ctx *mc = uc_fn_thisval(PCP_CTX_TYPE);
	uc_value_t *addr_arg = uc_fn_arg(0);
	uc_value_t *ver_arg = uc_fn_arg(1);
	/* no AI_ADDRCONFIG: before the WAN has an address it would refuse
	 * every name, and a missing route is reported as a network failure */
	struct addrinfo hints = {
		.ai_family = AF_UNSPEC,
		.ai_socktype = SOCK_DGRAM,
	};
	struct addrinfo *res, *ai;
	uc_value_t *result, *additional;
	char buf[INET6_ADDRSTRLEN];
	uint8_t version = 2;
	int id = -1;

	if (!mc || !mc->pcp || ucv_type(addr_arg) != UC_STRING)
		return NULL;

	if (ucv_type(ver_arg) == UC_INTEGER)
		version = (uint8_t)ucv_int64_get(ver_arg);

	result = ucv_object_new(vm);

	if (getaddrinfo(ucv_string_get(addr_arg), "5351", &hints, &res) != 0) {
		ucv_object_add(result, "error", ucv_string_new("resolve"));
		return result;
	}

	additional = ucv_array_new(vm);

	for (ai = res; ai; ai = ai->ai_next) {
		const void *sa_addr = (ai->ai_family == AF_INET)
			? (const void *)&((struct sockaddr_in *)ai->ai_addr)->sin_addr
			: (const void *)&((struct sockaddr_in6 *)ai->ai_addr)->sin6_addr;

		if (!inet_ntop(ai->ai_family, sa_addr, buf, sizeof(buf)))
			continue;

		if (id >= 0) {
			ucv_array_push(additional, ucv_string_new(buf));
			continue;
		}

		id = pcp_add_server(mc->pcp, ai->ai_addr, version);
		if (id >= 0)
			ucv_object_add(result, "address", ucv_string_new(buf));
	}

	freeaddrinfo(res);

	if (id < 0) {
		ucv_put(additional);
		ucv_object_add(result, "error", ucv_string_new("network"));
		return result;
	}

	ucv_object_add(result, "id", ucv_int64_new(id));
	ucv_object_add(result, "additional", additional);

	return result;
}

/* ctx.server_status(id) -> { state, version } */
static uc_value_t *
uc_pcp_server_status(uc_vm_t *vm, size_t nargs)
{
	struct pcp_module_ctx *mc = uc_fn_thisval(PCP_CTX_TYPE);
	uc_value_t *id_arg = uc_fn_arg(0);
	pcp_server_status_e status;
	const char *name;
	uc_value_t *obj;
	uint8_t version;

	if (!mc || !mc->pcp || ucv_type(id_arg) != UC_INTEGER)
		return NULL;

	if (pcp_get_server_status(mc->pcp, (int)ucv_int64_get(id_arg),
				  &status, &version) != PCP_ERR_SUCCESS)
		return NULL;

	switch (status) {
	case pcp_server_working:
		name = "working";
		break;
	case pcp_server_not_working:
		name = "not_working";
		break;
	default:
		name = "connecting";
		break;
	}

	obj = ucv_object_new(vm);
	ucv_object_add(obj, "state", ucv_string_new(name));
	ucv_object_add(obj, "version", ucv_int64_new(version));

	return obj;
}

static int
flow_filters_set(pcp_flow_t *flow, uc_value_t *filters)
{
	size_t i;

	for (i = 0; i < ucv_array_length(filters); i++) {
		uc_value_t *f = ucv_array_get(filters, i);
		uc_value_t *prefix = ucv_object_get(f, "prefix", NULL);
		struct sockaddr_storage ss;

		if (ucv_type(prefix) != UC_INTEGER ||
		    opt_addr(f, "ip", "port", &ss) <= 0)
			return -1;

		if (pcp_flow_set_filter_opt(flow, (struct sockaddr *)&ss,
					    (uint8_t)ucv_int64_get(prefix)) != PCP_ERR_SUCCESS)
			return -1;
	}

	return 0;
}

/*
 * ctx.new_flow({ internal_port, protocol, lifetime, [filters],
 *                [third_party], [suggested_ip], [suggested_port],
 *                [remote_ip], [remote_port] }) -> flow
 *
 * With remote_ip the library sends PEER instead of MAP. A filter is
 * { ip, prefix, port } with the prefix in the wire form of RFC 6887
 * section 13.3 (96 + n for an IPv4 address).
 */
static uc_value_t *
uc_pcp_new_flow(uc_vm_t *vm, size_t nargs)
{
	struct pcp_module_ctx *mc = uc_fn_thisval(PCP_CTX_TYPE);
	uc_value_t *opts = uc_fn_arg(0);
	uc_value_t *port_v, *proto_v, *lt_v, *filters;
	struct sockaddr_in6 src = { .sin6_family = AF_INET6 };
	struct sockaddr_storage ext, dst, tp;
	int has_ext, has_dst, has_tp;
	struct pcp_module_flow *mf;
	uc_value_t *obj;
	uint32_t lifetime;

	if (!mc || !mc->pcp || ucv_type(opts) != UC_OBJECT)
		return NULL;

	port_v = ucv_object_get(opts, "internal_port", NULL);
	proto_v = ucv_object_get(opts, "protocol", NULL);
	lt_v = ucv_object_get(opts, "lifetime", NULL);
	filters = ucv_object_get(opts, "filters", NULL);

	if (ucv_type(port_v) != UC_INTEGER || ucv_type(proto_v) != UC_INTEGER ||
	    ucv_type(lt_v) != UC_INTEGER)
		return NULL;

	if (filters && ucv_type(filters) != UC_ARRAY)
		return NULL;

	has_ext = opt_addr(opts, "suggested_ip", "suggested_port", &ext);
	has_dst = opt_addr(opts, "remote_ip", "remote_port", &dst);
	has_tp = opt_addr(opts, "third_party", NULL, &tp);
	if (has_ext < 0 || has_dst < 0 || has_tp < 0)
		return NULL;

	/* TR-181 Lifetime 0 is a permanent mapping; in PCP 0 deletes it */
	lifetime = (uint32_t)ucv_int64_get(lt_v);
	if (lifetime == 0)
		lifetime = UINT32_MAX;

	src.sin6_port = htons((uint16_t)ucv_int64_get(port_v));

	mf = calloc(1, sizeof(*mf));
	if (!mf)
		return NULL;

	obj = ucv_resource_create(vm, PCP_FLOW_TYPE, mf);
	if (!obj) {
		free(mf);
		return NULL;
	}

	mf->flow = pcp_new_flow(mc->pcp, (struct sockaddr *)&src,
				has_dst ? (struct sockaddr *)&dst : NULL,
				has_ext ? (struct sockaddr *)&ext : NULL,
				(uint8_t)ucv_int64_get(proto_v), lifetime, mf);
	if (!mf->flow) {
		ucv_put(obj);
		return NULL;
	}

	mf->ctx = mc;
	mf->id = ++mc->next_flow_id;
	mf->next = mc->flows;
	if (mc->flows)
		mc->flows->prev = mf;
	mc->flows = mf;

	if (filters && flow_filters_set(mf->flow, filters) != 0) {
		ucv_put(obj);
		return NULL;
	}

	if (has_tp)
		pcp_flow_set_3rd_party_opt(mf->flow, (struct sockaddr *)&tp);

	return obj;
}

static void
flow_change_notify_cb(pcp_flow_t *f, struct sockaddr *src_addr,
		      struct sockaddr *ext_addr, pcp_fstate_e state,
		      void *cb_arg)
{
	struct pcp_module_ctx *mc = cb_arg;
	struct pcp_module_flow *mf = pcp_flow_get_user_data(f);
	uc_value_t *fn, *info;

	if (!mc || !mf)
		return;

	fn = ucv_resource_value_get(mc->obj, CTX_SLOT_FLOW_CB);
	if (!ucv_is_callable(fn))
		return;

	info = flow_info_object(mc->vm, f);
	if (!info)
		return;

	uc_vm_stack_push(mc->vm, ucv_get(fn));
	uc_vm_stack_push(mc->vm, ucv_int64_new(mf->id));
	uc_vm_stack_push(mc->vm, info);

	if (uc_vm_call(mc->vm, false, 2) == EXCEPTION_NONE)
		ucv_put(uc_vm_stack_pop(mc->vm));
}

/* ctx.set_flow_change_cb(fn), fn(flow_id, info) */
static uc_value_t *
uc_pcp_set_flow_change_cb(uc_vm_t *vm, size_t nargs)
{
	struct pcp_module_ctx *mc = uc_fn_thisval(PCP_CTX_TYPE);
	uc_value_t *fn = uc_fn_arg(0);

	if (!mc || !mc->pcp || !ucv_is_callable(fn))
		return NULL;

	ucv_resource_value_set(mc->obj, CTX_SLOT_FLOW_CB, ucv_get(fn));
	pcp_set_flow_change_cb(mc->pcp, flow_change_notify_cb, mc);

	return ucv_boolean_new(true);
}

/* ctx.pulse() -> milliseconds to the next timeout, 0 for none */
static uc_value_t *
uc_pcp_pulse(uc_vm_t *vm, size_t nargs)
{
	struct pcp_module_ctx *mc = uc_fn_thisval(PCP_CTX_TYPE);
	struct timeval tv = { 0, 0 };

	if (!mc || !mc->pcp)
		return NULL;

	pcp_pulse(mc->pcp, &tv);

	return ucv_int64_new((int64_t)(tv.tv_sec * 1000 + tv.tv_usec / 1000));
}

/* ctx.socket() -> fd number */
static uc_value_t *
uc_pcp_socket(uc_vm_t *vm, size_t nargs)
{
	struct pcp_module_ctx *mc = uc_fn_thisval(PCP_CTX_TYPE);

	if (!mc || !mc->pcp)
		return NULL;

	return ucv_int64_new(pcp_get_socket(mc->pcp));
}

/* ctx.close([close_flows]) */
static uc_value_t *
uc_pcp_close(uc_vm_t *vm, size_t nargs)
{
	struct pcp_module_ctx *mc = uc_fn_thisval(PCP_CTX_TYPE);
	uc_value_t *close_arg = uc_fn_arg(0);

	if (!mc || !mc->pcp)
		return NULL;

	ctx_terminate(mc, !(close_arg && !ucv_is_truish(close_arg)));

	return ucv_boolean_new(true);
}

/* flow.id() -> the id that the flow change callback receives */
static uc_value_t *
uc_pcp_flow_id(uc_vm_t *vm, size_t nargs)
{
	struct pcp_module_flow *mf = uc_fn_thisval(PCP_FLOW_TYPE);

	if (!mf)
		return NULL;

	return ucv_int64_new(mf->id);
}

/* flow.info() -> { state, result_code, external_ip, external_port, ... } */
static uc_value_t *
uc_pcp_flow_info(uc_vm_t *vm, size_t nargs)
{
	struct pcp_module_flow *mf = uc_fn_thisval(PCP_FLOW_TYPE);

	if (!mf || !mf->flow)
		return NULL;

	return flow_info_object(vm, mf->flow);
}

/* flow.close() - sends lifetime 0 and frees the flow */
static uc_value_t *
uc_pcp_flow_close(uc_vm_t *vm, size_t nargs)
{
	struct pcp_module_flow *mf = uc_fn_thisval(PCP_FLOW_TYPE);

	if (!mf || !mf->flow)
		return NULL;

	pcp_close_flow(mf->flow);
	pcp_delete_flow(mf->flow);
	mf->flow = NULL;
	flow_detach(mf);

	return ucv_boolean_new(true);
}

static const uc_function_list_t module_fns[] = {
	{ "create",	uc_pcp_create },
};

static const uc_function_list_t ctx_methods[] = {
	{ "add_server",		uc_pcp_add_server },
	{ "server_status",	uc_pcp_server_status },
	{ "new_flow",		uc_pcp_new_flow },
	{ "set_flow_change_cb",	uc_pcp_set_flow_change_cb },
	{ "pulse",		uc_pcp_pulse },
	{ "socket",		uc_pcp_socket },
	{ "close",		uc_pcp_close },
};

static const uc_function_list_t flow_methods[] = {
	{ "id",		uc_pcp_flow_id },
	{ "info",	uc_pcp_flow_info },
	{ "close",	uc_pcp_flow_close },
};

void
uc_module_init(uc_vm_t *vm, uc_value_t *scope)
{
	uc_type_declare(vm, PCP_CTX_TYPE, ctx_methods, pcp_ctx_resource_free);
	uc_type_declare(vm, PCP_FLOW_TYPE, flow_methods, pcp_flow_resource_free);
	uc_function_list_register(scope, module_fns);
}
