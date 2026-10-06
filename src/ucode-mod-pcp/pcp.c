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

struct pcp_module_ctx {
	pcp_ctx_t *pcp;
	uc_vm_t *vm;
	uc_value_t *flow_change_cb;
};

struct pcp_module_flow {
	pcp_flow_t *flow;
	struct pcp_module_ctx *ctx;
};

static void
pcp_flow_resource_free(void *ptr)
{
	struct pcp_module_flow *mf = ptr;

	if (mf->flow)
		pcp_delete_flow(mf->flow);
	free(mf);
}

static void
pcp_ctx_resource_free(void *ptr)
{
	struct pcp_module_ctx *mc = ptr;

	if (mc->pcp)
		pcp_terminate(mc->pcp, 1);
	ucv_put(mc->flow_change_cb);
	free(mc);
}

static int
addr_resolve(const char *host, uint16_t port, struct sockaddr_storage *ss)
{
	struct addrinfo hints = {
		.ai_family = AF_UNSPEC,
		.ai_socktype = SOCK_DGRAM,
		.ai_flags = AI_V4MAPPED | AI_ADDRCONFIG,
	};
	struct addrinfo *res;
	char port_str[8];

	snprintf(port_str, sizeof(port_str), "%u", port);

	if (getaddrinfo(host, port_str, &hints, &res) != 0)
		return -1;

	memcpy(ss, res->ai_addr, res->ai_addrlen);
	freeaddrinfo(res);

	return 0;
}

/* pcp.create([autodiscovery]) -> context */
static uc_value_t *
uc_pcp_create(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *auto_arg = uc_fn_arg(0);
	uint8_t autodiscovery = DISABLE_AUTODISCOVERY;
	struct pcp_module_ctx *mc;

	if (auto_arg && ucv_is_truish(auto_arg))
		autodiscovery = ENABLE_AUTODISCOVERY;

	mc = calloc(1, sizeof(*mc));
	if (!mc)
		return NULL;

	mc->pcp = pcp_init(autodiscovery, NULL);
	if (!mc->pcp) {
		free(mc);
		return NULL;
	}

	mc->vm = vm;

	return ucv_resource_create(vm, PCP_CTX_TYPE, mc);
}

/* ctx.add_server(address, [version]) -> server_id or null */
static uc_value_t *
uc_pcp_add_server(uc_vm_t *vm, size_t nargs)
{
	struct pcp_module_ctx *mc = uc_fn_thisval(PCP_CTX_TYPE);
	uc_value_t *addr_arg = uc_fn_arg(0);
	uc_value_t *ver_arg = uc_fn_arg(1);
	struct sockaddr_storage ss;
	uint8_t version = 2;
	const char *addr;
	int id;

	if (!mc || !mc->pcp)
		return NULL;

	if (ucv_type(addr_arg) != UC_STRING)
		return NULL;

	addr = ucv_string_get(addr_arg);

	if (ver_arg && ucv_type(ver_arg) == UC_INTEGER)
		version = (uint8_t)ucv_int64_get(ver_arg);

	if (addr_resolve(addr, 5351, &ss) != 0)
		return NULL;

	id = pcp_add_server(mc->pcp, (struct sockaddr *)&ss, version);
	if (id < 0)
		return NULL;

	return ucv_int64_new(id);
}

/* ctx.new_flow(internal_port, protocol, lifetime, [opts]) -> flow */
static uc_value_t *
uc_pcp_new_flow(uc_vm_t *vm, size_t nargs)
{
	struct pcp_module_ctx *mc = uc_fn_thisval(PCP_CTX_TYPE);
	uc_value_t *port_arg = uc_fn_arg(0);
	uc_value_t *proto_arg = uc_fn_arg(1);
	uc_value_t *lt_arg = uc_fn_arg(2);
	uc_value_t *opts_arg = uc_fn_arg(3);
	struct sockaddr_in6 src = { .sin6_family = AF_INET6 };
	struct pcp_module_flow *mf;
	uint32_t lifetime;
	uint16_t port;
	uint8_t proto;

	if (!mc || !mc->pcp)
		return NULL;

	if (ucv_type(port_arg) != UC_INTEGER ||
	    ucv_type(proto_arg) != UC_INTEGER ||
	    ucv_type(lt_arg) != UC_INTEGER)
		return NULL;

	port = (uint16_t)ucv_int64_get(port_arg);
	proto = (uint8_t)ucv_int64_get(proto_arg);
	lifetime = (uint32_t)ucv_int64_get(lt_arg);

	if (lifetime == 0)
		lifetime = UINT32_MAX;

	src.sin6_port = htons(port);

	mf = calloc(1, sizeof(*mf));
	if (!mf)
		return NULL;

	mf->ctx = mc;
	mf->flow = pcp_new_flow(mc->pcp, (struct sockaddr *)&src,
				NULL, NULL, proto, lifetime, mf);
	if (!mf->flow) {
		free(mf);
		return NULL;
	}

	if (opts_arg && ucv_type(opts_arg) == UC_OBJECT) {
		uc_value_t *filter_ip = ucv_object_get(opts_arg, "filter_ip", NULL);
		uc_value_t *filter_prefix = ucv_object_get(opts_arg, "filter_prefix", NULL);
		uc_value_t *third_party = ucv_object_get(opts_arg, "third_party", NULL);
		uc_value_t *prefer_failure = ucv_object_get(opts_arg, "prefer_failure", NULL);

		if (filter_ip && ucv_type(filter_ip) == UC_STRING) {
			struct sockaddr_storage fss;
			uint8_t prefix = 128;

			if (filter_prefix && ucv_type(filter_prefix) == UC_INTEGER)
				prefix = (uint8_t)ucv_int64_get(filter_prefix);

			if (addr_resolve(ucv_string_get(filter_ip), 0, &fss) == 0)
				pcp_flow_set_filter_opt(mf->flow,
							(struct sockaddr *)&fss, prefix);
		}

		if (third_party && ucv_type(third_party) == UC_STRING) {
			struct sockaddr_storage tss;

			if (addr_resolve(ucv_string_get(third_party), 0, &tss) == 0)
				pcp_flow_set_3rd_party_opt(mf->flow,
							   (struct sockaddr *)&tss);
		}

		if (prefer_failure && ucv_is_truish(prefer_failure))
			pcp_flow_set_prefer_failure_opt(mf->flow);
	}

	return ucv_resource_create(vm, PCP_FLOW_TYPE, mf);
}

static void
flow_change_notify_cb(pcp_flow_t *f, struct sockaddr *src_addr,
		      struct sockaddr *ext_addr, pcp_fstate_e state,
		      void *cb_arg)
{
	struct pcp_module_ctx *mc = cb_arg;
	uc_value_t *info, *fn;
	pcp_flow_info_t *fi;
	char buf[INET6_ADDRSTRLEN];
	size_t cnt = 0;

	(void)src_addr;
	(void)ext_addr;

	if (!mc || !mc->flow_change_cb)
		return;

	fn = mc->flow_change_cb;

	fi = pcp_flow_get_info(f, &cnt);
	if (!fi || cnt == 0)
		return;

	info = ucv_object_new(mc->vm);

	switch (fi->result) {
	case pcp_state_succeeded:
		ucv_object_add(info, "status", ucv_string_new("Enabled"));
		break;
	case pcp_state_processing:
		ucv_object_add(info, "status", ucv_string_new("Processing"));
		break;
	case pcp_state_failed:
		ucv_object_add(info, "status", ucv_string_new("Error"));
		break;
	default:
		ucv_object_add(info, "status", ucv_string_new("Error"));
		break;
	}

	ucv_object_add(info, "result_code",
		       ucv_int64_new(fi->pcp_result_code));

	if (inet_ntop(AF_INET6, &fi->ext_ip, buf, sizeof(buf)))
		ucv_object_add(info, "external_ip", ucv_string_new(buf));

	ucv_object_add(info, "external_port",
		       ucv_int64_new(ntohs(fi->ext_port)));

	struct pcp_module_flow *mf = pcp_flow_get_user_data(f);
	uc_value_t *flow_ref = NULL;

	if (mf)
		flow_ref = ucv_resource_create(mc->vm, PCP_FLOW_TYPE, mf);

	uc_vm_stack_push(mc->vm, ucv_get(fn));
	uc_vm_stack_push(mc->vm, flow_ref ? ucv_get(flow_ref) : ucv_boolean_new(false));
	uc_vm_stack_push(mc->vm, info);

	uc_vm_call(mc->vm, false, 2);
	ucv_put(uc_vm_stack_pop(mc->vm));

	free(fi);
}

/* ctx.set_flow_change_cb(fn) */
static uc_value_t *
uc_pcp_set_flow_change_cb(uc_vm_t *vm, size_t nargs)
{
	struct pcp_module_ctx *mc = uc_fn_thisval(PCP_CTX_TYPE);
	uc_value_t *fn = uc_fn_arg(0);

	if (!mc || !mc->pcp)
		return NULL;

	if (!fn || !ucv_is_callable(fn))
		return NULL;

	ucv_put(mc->flow_change_cb);
	mc->flow_change_cb = ucv_get(fn);

	pcp_set_flow_change_cb(mc->pcp, flow_change_notify_cb, mc);

	return ucv_boolean_new(true);
}

/* ctx.pulse() -> next timeout in ms, or null on error */
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
	int close_flows = 1;

	if (!mc || !mc->pcp)
		return NULL;

	if (close_arg && !ucv_is_truish(close_arg))
		close_flows = 0;

	pcp_terminate(mc->pcp, close_flows);
	mc->pcp = NULL;

	return ucv_boolean_new(true);
}

/* flow.info() -> { status, result_code, external_ip, external_port } */
static uc_value_t *
uc_pcp_flow_info(uc_vm_t *vm, size_t nargs)
{
	struct pcp_module_flow *mf = uc_fn_thisval(PCP_FLOW_TYPE);
	pcp_flow_info_t *fi;
	uc_value_t *obj;
	char buf[INET6_ADDRSTRLEN];
	size_t cnt = 0;

	if (!mf || !mf->flow)
		return NULL;

	fi = pcp_flow_get_info(mf->flow, &cnt);
	if (!fi || cnt == 0)
		return NULL;

	obj = ucv_object_new(vm);

	switch (fi->result) {
	case pcp_state_succeeded:
		ucv_object_add(obj, "status", ucv_string_new("Enabled"));
		break;
	case pcp_state_processing:
		ucv_object_add(obj, "status", ucv_string_new("Processing"));
		break;
	case pcp_state_short_lifetime_error:
		ucv_object_add(obj, "status", ucv_string_new("Error_ShortLifetime"));
		break;
	case pcp_state_failed:
		ucv_object_add(obj, "status", ucv_string_new("Error"));
		break;
	default:
		ucv_object_add(obj, "status", ucv_string_new("Error"));
		break;
	}

	ucv_object_add(obj, "result_code", ucv_int64_new(fi->pcp_result_code));

	if (inet_ntop(AF_INET6, &fi->ext_ip, buf, sizeof(buf)))
		ucv_object_add(obj, "external_ip", ucv_string_new(buf));

	ucv_object_add(obj, "external_port", ucv_int64_new(ntohs(fi->ext_port)));
	ucv_object_add(obj, "protocol", ucv_int64_new(fi->protocol));

	if (inet_ntop(AF_INET6, &fi->int_ip, buf, sizeof(buf)))
		ucv_object_add(obj, "internal_ip", ucv_string_new(buf));

	ucv_object_add(obj, "internal_port", ucv_int64_new(ntohs(fi->int_port)));

	free(fi);

	return obj;
}

/* flow.close() - send lifetime=0 */
static uc_value_t *
uc_pcp_flow_close(uc_vm_t *vm, size_t nargs)
{
	struct pcp_module_flow *mf = uc_fn_thisval(PCP_FLOW_TYPE);

	if (!mf || !mf->flow)
		return NULL;

	pcp_close_flow(mf->flow);

	return ucv_boolean_new(true);
}

/* flow.delete() - free memory */
static uc_value_t *
uc_pcp_flow_delete(uc_vm_t *vm, size_t nargs)
{
	struct pcp_module_flow *mf = uc_fn_thisval(PCP_FLOW_TYPE);

	if (!mf || !mf->flow)
		return NULL;

	pcp_delete_flow(mf->flow);
	mf->flow = NULL;

	return ucv_boolean_new(true);
}

static const uc_function_list_t module_fns[] = {
	{ "create",	uc_pcp_create },
};

static const uc_function_list_t ctx_methods[] = {
	{ "add_server",		uc_pcp_add_server },
	{ "new_flow",		uc_pcp_new_flow },
	{ "set_flow_change_cb",	uc_pcp_set_flow_change_cb },
	{ "pulse",		uc_pcp_pulse },
	{ "socket",		uc_pcp_socket },
	{ "close",		uc_pcp_close },
};

static const uc_function_list_t flow_methods[] = {
	{ "info",	uc_pcp_flow_info },
	{ "close",	uc_pcp_flow_close },
	{ "delete",	uc_pcp_flow_delete },
};

void
uc_module_init(uc_vm_t *vm, uc_value_t *scope)
{
	uc_type_declare(vm, PCP_CTX_TYPE, ctx_methods, pcp_ctx_resource_free);
	uc_type_declare(vm, PCP_FLOW_TYPE, flow_methods, pcp_flow_resource_free);
	uc_function_list_register(scope, module_fns);
}
