#include <stdlib.h>
#include <string.h>

#include <ucode/module.h>
#include <ucode/lib.h>
#include <ucode/types.h>

#include "uds-transport.h"
#include "usp-protocol.h"

enum {
	SLOT_ON_CONNECT,
	SLOT_ON_GET,
	SLOT_ON_SET,
	SLOT_ON_ADD,
	SLOT_ON_DELETE,
	SLOT_ON_GET_SUPPORTED_DM,
	SLOT_ON_OPERATE,
	SLOT_ON_GET_INSTANCES,
	SLOT_ON_DISCONNECT,
	SLOT_ON_ERROR,
	SLOT_MAX,
};

typedef struct {
	uc_vm_t *vm;
	uc_value_t *res_obj;
	struct uds_conn conn;
} usp_service_t;

static uc_value_t *
invoke_callback(usp_service_t *svc, int slot, int nargs, ...)
{
	uc_value_t *cb = ucv_resource_value_get(svc->res_obj, slot);
	va_list ap;
	int i;

	if (!cb || !ucv_is_callable(cb)) {
		va_start(ap, nargs);
		for (i = 0; i < nargs; i++)
			ucv_put(va_arg(ap, uc_value_t *));
		va_end(ap);
		return NULL;
	}

	uc_vm_stack_push(svc->vm, ucv_get(svc->res_obj));
	uc_vm_stack_push(svc->vm, ucv_get(cb));

	va_start(ap, nargs);
	for (i = 0; i < nargs; i++)
		uc_vm_stack_push(svc->vm, va_arg(ap, uc_value_t *));
	va_end(ap);

	if (uc_vm_call(svc->vm, true, nargs) != EXCEPTION_NONE)
		return NULL;

	return uc_vm_stack_pop(svc->vm);
}

static void
send_record(usp_service_t *svc, const uint8_t *msg_buf, size_t msg_len)
{
	uint8_t *record;
	size_t record_len;

	record = usp_record_wrap(svc->conn.endpoint_id,
				 svc->conn.peer_endpoint_id ? svc->conn.peer_endpoint_id : "",
				 msg_buf, msg_len, &record_len);
	if (!record)
		return;

	uds_queue_record(&svc->conn, record, record_len);
	free(record);
}

static void
handle_get(usp_service_t *svc, Usp__Msg *msg, Usp__Get *get)
{
	uc_value_t *paths, *rv;
	const char **param_paths = NULL;
	const char **param_values = NULL;
	size_t n_params = 0;
	uint8_t *resp;
	size_t resp_len;

	paths = ucv_array_new(svc->vm);
	for (size_t i = 0; i < get->n_param_paths; i++)
		ucv_array_push(paths, ucv_string_new(get->param_paths[i]));

	rv = invoke_callback(svc, SLOT_ON_GET, 1, paths);
	if (!rv || ucv_type(rv) != UC_OBJECT)
		goto send_empty;

	n_params = ucv_object_length(rv);
	if (n_params == 0)
		goto send_empty;

	param_paths = calloc(n_params, sizeof(char *));
	param_values = calloc(n_params, sizeof(char *));
	if (!param_paths || !param_values)
		goto send_empty;

	size_t idx = 0;

	ucv_object_foreach(rv, key, val) {
		param_paths[idx] = key;
		param_values[idx] = ucv_string_get(val) ? ucv_string_get(val) : "";
		idx++;
	}

	resp = usp_msg_get_resp(msg->header->msg_id,
				param_paths, param_values,
				idx, &resp_len);
	if (resp) {
		send_record(svc, resp, resp_len);
		free(resp);
	}

	free(param_paths);
	free(param_values);
	ucv_put(rv);
	return;

send_empty:
	free(param_paths);
	free(param_values);
	ucv_put(rv);

	resp = usp_msg_get_resp(msg->header->msg_id, NULL, NULL, 0, &resp_len);
	if (resp) {
		send_record(svc, resp, resp_len);
		free(resp);
	}
}

static void
handle_set(usp_service_t *svc, Usp__Msg *msg, Usp__Set *set)
{
	uc_value_t *params, *rv;
	uint8_t *resp;
	size_t resp_len;

	params = ucv_object_new(svc->vm);

	for (size_t i = 0; i < set->n_update_objs; i++) {
		Usp__Set__UpdateObject *obj = set->update_objs[i];

		for (size_t j = 0; j < obj->n_param_settings; j++) {
			Usp__Set__UpdateParamSetting *ps = obj->param_settings[j];
			char path[512];

			snprintf(path, sizeof(path), "%s%s",
				 obj->obj_path, ps->param);
			ucv_object_add(params, path,
				       ucv_string_new(ps->value));
		}
	}

	rv = invoke_callback(svc, SLOT_ON_SET, 1, params);

	if (rv && ucv_type(rv) == UC_OBJECT) {
		uc_value_t *err_code_v = ucv_object_get(rv, "err_code", NULL);
		uc_value_t *err_msg_v = ucv_object_get(rv, "err_msg", NULL);

		if (err_code_v) {
			resp = usp_msg_error(msg->header->msg_id,
					     ucv_int64_get(err_code_v),
					     ucv_string_get(err_msg_v),
					     &resp_len);
			if (resp) {
				send_record(svc, resp, resp_len);
				free(resp);
			}
			ucv_put(rv);
			return;
		}
	}

	ucv_put(rv);

	resp = usp_msg_set_resp(msg->header->msg_id, &resp_len);
	if (resp) {
		send_record(svc, resp, resp_len);
		free(resp);
	}
}

static void
handle_add(usp_service_t *svc, Usp__Msg *msg, Usp__Add *add)
{
	uint8_t *resp;
	size_t resp_len;

	for (size_t i = 0; i < add->n_create_objs; i++) {
		Usp__Add__CreateObject *cobj = add->create_objs[i];
		uc_value_t *params, *rv;

		params = ucv_object_new(svc->vm);
		for (size_t j = 0; j < cobj->n_param_settings; j++) {
			Usp__Add__CreateParamSetting *ps =
				cobj->param_settings[j];
			ucv_object_add(params, ps->param,
				       ucv_string_new(ps->value));
		}

		rv = invoke_callback(svc, SLOT_ON_ADD, 2,
				     ucv_string_new(cobj->obj_path), params);

		if (rv && ucv_type(rv) == UC_INTEGER) {
			char created[512];
			int instance = ucv_int64_get(rv);

			snprintf(created, sizeof(created), "%s%d.",
				 cobj->obj_path, instance);
			resp = usp_msg_add_resp(msg->header->msg_id,
						cobj->obj_path, created,
						0, NULL, &resp_len);
		} else if (rv && ucv_type(rv) == UC_OBJECT) {
			uc_value_t *ec = ucv_object_get(rv, "err_code", NULL);
			uc_value_t *em = ucv_object_get(rv, "err_msg", NULL);

			resp = usp_msg_add_resp(msg->header->msg_id,
						cobj->obj_path, NULL,
						ec ? ucv_int64_get(ec) : 7004,
						ucv_string_get(em),
						&resp_len);
		} else {
			resp = usp_msg_add_resp(msg->header->msg_id,
						cobj->obj_path, NULL,
						7004, "Internal error",
						&resp_len);
		}

		ucv_put(rv);

		if (resp) {
			send_record(svc, resp, resp_len);
			free(resp);
		}
	}
}

static void
handle_delete(usp_service_t *svc, Usp__Msg *msg, Usp__Delete *del)
{
	uint8_t *resp;
	size_t resp_len;

	for (size_t i = 0; i < del->n_obj_paths; i++) {
		uc_value_t *rv;

		rv = invoke_callback(svc, SLOT_ON_DELETE, 1,
				     ucv_string_new(del->obj_paths[i]));

		if (rv && ucv_is_truish(rv)) {
			resp = usp_msg_delete_resp(msg->header->msg_id,
						   del->obj_paths[i],
						   0, NULL, &resp_len);
		} else if (rv && ucv_type(rv) == UC_OBJECT) {
			uc_value_t *ec = ucv_object_get(rv, "err_code", NULL);
			uc_value_t *em = ucv_object_get(rv, "err_msg", NULL);

			resp = usp_msg_delete_resp(msg->header->msg_id,
						   del->obj_paths[i],
						   ec ? ucv_int64_get(ec) : 7008,
						   ucv_string_get(em),
						   &resp_len);
		} else {
			resp = usp_msg_delete_resp(msg->header->msg_id,
						   del->obj_paths[i],
						   7008, "Delete failed",
						   &resp_len);
		}

		ucv_put(rv);

		if (resp) {
			send_record(svc, resp, resp_len);
			free(resp);
		}
	}
}

static void
handle_get_supported_dm(usp_service_t *svc, Usp__Msg *msg,
			Usp__GetSupportedDM *gsdm)
{
	uc_value_t *paths, *rv;
	uint8_t *resp;
	size_t resp_len;

	paths = ucv_array_new(svc->vm);
	for (size_t i = 0; i < gsdm->n_obj_paths; i++)
		ucv_array_push(paths, ucv_string_new(gsdm->obj_paths[i]));

	rv = invoke_callback(svc, SLOT_ON_GET_SUPPORTED_DM, 1, paths);

	if (!rv || ucv_type(rv) != UC_OBJECT) {
		ucv_put(rv);
		resp = usp_msg_error(msg->header->msg_id, 7000,
				     "GetSupportedDM failed", &resp_len);
		if (resp) {
			send_record(svc, resp, resp_len);
			free(resp);
		}
		return;
	}

	resp = usp_msg_get_supported_dm_resp(msg->header->msg_id, rv, &resp_len);
	ucv_put(rv);

	if (resp) {
		send_record(svc, resp, resp_len);
		free(resp);
	}
}

static void
handle_operate(usp_service_t *svc, Usp__Msg *msg, Usp__Operate *oper)
{
	uc_value_t *input, *rv;
	uint8_t *resp;
	size_t resp_len;

	input = ucv_object_new(svc->vm);
	for (size_t i = 0; i < oper->n_input_args; i++) {
		Usp__Operate__InputArgsEntry *arg = oper->input_args[i];
		ucv_object_add(input, arg->key, ucv_string_new(arg->value));
	}

	rv = invoke_callback(svc, SLOT_ON_OPERATE, 3,
			     ucv_string_new(oper->command),
			     ucv_string_new(oper->command_key ? oper->command_key : ""),
			     input);

	if (rv && ucv_type(rv) == UC_OBJECT) {
		uc_value_t *err_code_v = ucv_object_get(rv, "err_code", NULL);

		if (err_code_v) {
			uc_value_t *err_msg_v = ucv_object_get(rv, "err_msg", NULL);

			resp = usp_msg_error(msg->header->msg_id,
					     ucv_int64_get(err_code_v),
					     ucv_string_get(err_msg_v),
					     &resp_len);
			ucv_put(rv);
			if (resp) {
				send_record(svc, resp, resp_len);
				free(resp);
			}
			return;
		}

		uc_value_t *output = ucv_object_get(rv, "output", NULL);
		const char **out_keys = NULL;
		const char **out_vals = NULL;
		size_t n_out = 0;

		if (output && ucv_type(output) == UC_OBJECT) {
			n_out = ucv_object_length(output);
			if (n_out > 0) {
				out_keys = calloc(n_out, sizeof(char *));
				out_vals = calloc(n_out, sizeof(char *));
				size_t oi = 0;
				ucv_object_foreach(output, key, val) {
					out_keys[oi] = key;
					out_vals[oi] = ucv_string_get(val) ? ucv_string_get(val) : "";
					oi++;
				}
			}
		}

		uc_value_t *req_path_v = ucv_object_get(rv, "req_obj_path", NULL);
		const char *req_path = ucv_string_get(req_path_v);

		resp = usp_msg_operate_resp(msg->header->msg_id,
					    oper->command,
					    out_keys, out_vals, n_out,
					    req_path, &resp_len);
		free(out_keys);
		free(out_vals);
	} else {
		resp = usp_msg_operate_resp(msg->header->msg_id,
					    oper->command,
					    NULL, NULL, 0, NULL, &resp_len);
	}

	ucv_put(rv);

	if (resp) {
		send_record(svc, resp, resp_len);
		free(resp);
	}
}

static void
handle_get_instances(usp_service_t *svc, Usp__Msg *msg,
		     Usp__GetInstances *gi)
{
	uc_value_t *paths, *rv;
	uint8_t *resp;
	size_t resp_len;

	paths = ucv_array_new(svc->vm);
	for (size_t i = 0; i < gi->n_obj_paths; i++)
		ucv_array_push(paths, ucv_string_new(gi->obj_paths[i]));

	rv = invoke_callback(svc, SLOT_ON_GET_INSTANCES, 2,
			     paths,
			     ucv_boolean_new(gi->first_level_only));

	if (!rv || ucv_type(rv) != UC_OBJECT) {
		ucv_put(rv);
		resp = usp_msg_get_instances_resp(msg->header->msg_id,
						  NULL, 0, &resp_len);
		if (resp) {
			send_record(svc, resp, resp_len);
			free(resp);
		}
		return;
	}

	size_t n_results = ucv_object_length(rv);
	struct get_instances_result *results = NULL;

	if (n_results > 0) {
		results = calloc(n_results, sizeof(*results));
		size_t ri = 0;

		ucv_object_foreach(rv, req_path, inst_arr) {
			results[ri].requested_path = req_path;
			results[ri].instance_paths = NULL;
			results[ri].n_instances = 0;

			if (ucv_type(inst_arr) == UC_ARRAY) {
				size_t n = ucv_array_length(inst_arr);
				results[ri].instance_paths = calloc(n, sizeof(char *));
				for (size_t j = 0; j < n; j++) {
					uc_value_t *v = ucv_array_get(inst_arr, j);
					const char *s = ucv_string_get(v);
					if (s)
						results[ri].instance_paths[results[ri].n_instances++] = s;
				}
			}
			ri++;
		}
	}

	resp = usp_msg_get_instances_resp(msg->header->msg_id,
					  results, n_results, &resp_len);

	if (results) {
		for (size_t i = 0; i < n_results; i++)
			free(results[i].instance_paths);
		free(results);
	}

	ucv_put(rv);

	if (resp) {
		send_record(svc, resp, resp_len);
		free(resp);
	}
}

static void
dispatch_request(usp_service_t *svc, Usp__Msg *msg)
{
	Usp__Body *body = msg->body;
	Usp__Request *req;

	if (!body || body->msg_body_case != USP__BODY__MSG_BODY_REQUEST)
		return;

	req = body->request;
	if (!req)
		return;

	switch (req->req_type_case) {
	case USP__REQUEST__REQ_TYPE_GET:
		if (req->get)
			handle_get(svc, msg, req->get);
		break;
	case USP__REQUEST__REQ_TYPE_SET:
		if (req->set)
			handle_set(svc, msg, req->set);
		break;
	case USP__REQUEST__REQ_TYPE_ADD:
		if (req->add)
			handle_add(svc, msg, req->add);
		break;
	case USP__REQUEST__REQ_TYPE_DELETE:
		if (req->delete_)
			handle_delete(svc, msg, req->delete_);
		break;
	case USP__REQUEST__REQ_TYPE_GET_SUPPORTED_DM:
		if (req->get_supported_dm)
			handle_get_supported_dm(svc, msg, req->get_supported_dm);
		break;
	case USP__REQUEST__REQ_TYPE_OPERATE:
		if (req->operate)
			handle_operate(svc, msg, req->operate);
		break;
	case USP__REQUEST__REQ_TYPE_GET_INSTANCES:
		if (req->get_instances)
			handle_get_instances(svc, msg, req->get_instances);
		break;
	default:
		break;
	}
}

static void
on_handshake(struct uds_conn *conn, const char *endpoint_id)
{
	usp_service_t *svc = conn->priv;
	uint8_t *connect_rec;
	size_t connect_len;

	connect_rec = usp_record_wrap_connect(conn->endpoint_id,
					      endpoint_id, &connect_len);
	if (connect_rec) {
		uds_queue_record(conn, connect_rec, connect_len);
		free(connect_rec);
	}

	uc_value_t *rv = invoke_callback(svc, SLOT_ON_CONNECT, 0);
	ucv_put(rv);
}

static void
on_record(struct uds_conn *conn, const uint8_t *data, size_t len)
{
	usp_service_t *svc = conn->priv;
	Usp__Msg *msg;

	msg = usp_record_extract_msg(data, len);
	if (!msg)
		return;

	if (msg->header) {
		switch (msg->header->msg_type) {
		case USP__HEADER__MSG_TYPE__GET:
		case USP__HEADER__MSG_TYPE__SET:
		case USP__HEADER__MSG_TYPE__ADD:
		case USP__HEADER__MSG_TYPE__DELETE:
		case USP__HEADER__MSG_TYPE__GET_SUPPORTED_DM:
		case USP__HEADER__MSG_TYPE__OPERATE:
		case USP__HEADER__MSG_TYPE__GET_INSTANCES:
			dispatch_request(svc, msg);
			break;

		case USP__HEADER__MSG_TYPE__REGISTER_RESP:
		case USP__HEADER__MSG_TYPE__DEREGISTER_RESP:
		case USP__HEADER__MSG_TYPE__NOTIFY_RESP:
			break;

		default:
			break;
		}
	}

	usp_msg_free(msg);
}

static void
on_error(struct uds_conn *conn, const char *msg)
{
	usp_service_t *svc = conn->priv;

	uc_value_t *rv = invoke_callback(svc, SLOT_ON_ERROR, 1, ucv_string_new(msg));
	ucv_put(rv);
}

static void
on_disconnect(struct uds_conn *conn)
{
	usp_service_t *svc = conn->priv;

	uc_value_t *rv = invoke_callback(svc, SLOT_ON_DISCONNECT, 0);
	ucv_put(rv);
}

static const struct uds_ops service_ops = {
	.on_handshake = on_handshake,
	.on_record = on_record,
	.on_error = on_error,
	.on_disconnect = on_disconnect,
};

static void
service_free(void *ptr)
{
	usp_service_t *svc = ptr;

	uds_conn_free(&svc->conn);
	ucv_put(svc->res_obj);
}

static uc_value_t *
uc_usp_connect(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *config = uc_fn_arg(0);
	uc_value_t *val, *obj;
	usp_service_t *svc;
	const char *path, *endpoint_id;
	int ret;

	if (ucv_type(config) != UC_OBJECT)
		return NULL;

	val = ucv_object_get(config, "path", NULL);
	path = ucv_string_get(val);
	if (!path)
		return NULL;

	val = ucv_object_get(config, "endpoint_id", NULL);
	endpoint_id = ucv_string_get(val);
	if (!endpoint_id)
		return NULL;

	obj = ucv_resource_create_ex(vm, "usp.service", (void **)&svc,
				     SLOT_MAX, sizeof(*svc));
	if (!obj)
		return NULL;

	svc->vm = vm;
	svc->res_obj = ucv_get(obj);

	ret = uds_conn_init(&svc->conn, path, endpoint_id, &service_ops);
	if (ret < 0) {
		ucv_put(svc->res_obj);
		return NULL;
	}

	svc->conn.priv = svc;

	struct {
		const char *name;
		int slot;
	} callbacks[] = {
		{ "on_connect",		SLOT_ON_CONNECT },
		{ "on_get",		SLOT_ON_GET },
		{ "on_set",		SLOT_ON_SET },
		{ "on_add",		SLOT_ON_ADD },
		{ "on_delete",		SLOT_ON_DELETE },
		{ "on_get_supported_dm", SLOT_ON_GET_SUPPORTED_DM },
		{ "on_operate",		SLOT_ON_OPERATE },
		{ "on_get_instances",	SLOT_ON_GET_INSTANCES },
		{ "on_disconnect",	SLOT_ON_DISCONNECT },
		{ "on_error",		SLOT_ON_ERROR },
	};

	for (size_t i = 0; i < sizeof(callbacks) / sizeof(callbacks[0]); i++) {
		val = ucv_object_get(config, callbacks[i].name, NULL);
		if (val && ucv_is_callable(val))
			ucv_resource_value_set(obj, callbacks[i].slot,
					       ucv_get(val));
	}

	ucv_resource_persistent_set(obj, true);

	ret = uds_connect(&svc->conn);
	if (ret < 0)
		uloop_timeout_set(&svc->conn.reconnect_timer, 1000);

	return obj;
}

static uc_value_t *
uc_usp_register(uc_vm_t *vm, size_t nargs)
{
	usp_service_t *svc = uc_fn_thisval("usp.service");
	uc_value_t *paths_arr = uc_fn_arg(0);
	char **paths;
	size_t n_paths;
	uint8_t *msg_buf;
	size_t msg_len;
	char *msg_id;

	if (!svc || !svc->conn.handshake_complete)
		return ucv_boolean_new(false);

	if (ucv_type(paths_arr) != UC_ARRAY)
		return ucv_boolean_new(false);

	n_paths = ucv_array_length(paths_arr);
	if (n_paths == 0)
		return ucv_boolean_new(false);

	paths = calloc(n_paths, sizeof(char *));
	if (!paths)
		return ucv_boolean_new(false);

	for (size_t i = 0; i < n_paths; i++) {
		uc_value_t *v = ucv_array_get(paths_arr, i);
		const char *s = ucv_string_get(v);
		paths[i] = (char *)(s ? s : "");
	}

	msg_id = usp_msg_id_generate();
	msg_buf = usp_msg_register(msg_id, paths, n_paths, &msg_len);
	free(msg_id);
	free(paths);

	if (!msg_buf)
		return ucv_boolean_new(false);

	send_record(svc, msg_buf, msg_len);
	free(msg_buf);

	return ucv_boolean_new(true);
}

static uc_value_t *
uc_usp_deregister(uc_vm_t *vm, size_t nargs)
{
	usp_service_t *svc = uc_fn_thisval("usp.service");
	uc_value_t *paths_arr = uc_fn_arg(0);
	char **paths;
	size_t n_paths;
	uint8_t *msg_buf;
	size_t msg_len;
	char *msg_id;

	if (!svc || !svc->conn.handshake_complete)
		return ucv_boolean_new(false);

	if (ucv_type(paths_arr) != UC_ARRAY)
		return ucv_boolean_new(false);

	n_paths = ucv_array_length(paths_arr);
	paths = calloc(n_paths, sizeof(char *));
	if (!paths)
		return ucv_boolean_new(false);

	for (size_t i = 0; i < n_paths; i++) {
		uc_value_t *v = ucv_array_get(paths_arr, i);
		const char *s = ucv_string_get(v);
		paths[i] = (char *)(s ? s : "");
	}

	msg_id = usp_msg_id_generate();
	msg_buf = usp_msg_deregister(msg_id, paths, n_paths, &msg_len);
	free(msg_id);
	free(paths);

	if (!msg_buf)
		return ucv_boolean_new(false);

	send_record(svc, msg_buf, msg_len);
	free(msg_buf);

	return ucv_boolean_new(true);
}

static uc_value_t *
uc_usp_notify_event(uc_vm_t *vm, size_t nargs)
{
	usp_service_t *svc = uc_fn_thisval("usp.service");
	uc_value_t *event_name_v = uc_fn_arg(0);
	uc_value_t *params_v = uc_fn_arg(1);
	const char *event_name;
	const char **keys = NULL;
	const char **vals = NULL;
	size_t n_params = 0;
	uint8_t *msg_buf;
	size_t msg_len;
	char *msg_id;

	if (!svc || !svc->conn.handshake_complete)
		return ucv_boolean_new(false);

	event_name = ucv_string_get(event_name_v);
	if (!event_name)
		return ucv_boolean_new(false);

	if (params_v && ucv_type(params_v) == UC_OBJECT) {
		n_params = ucv_object_length(params_v);
		if (n_params > 0) {
			keys = calloc(n_params, sizeof(char *));
			vals = calloc(n_params, sizeof(char *));
			size_t i = 0;
			ucv_object_foreach(params_v, key, val) {
				keys[i] = key;
				vals[i] = ucv_string_get(val) ? ucv_string_get(val) : "";
				i++;
			}
		}
	}

	msg_id = usp_msg_id_generate();
	msg_buf = usp_msg_notify_event(msg_id, event_name,
				       keys, vals, n_params, &msg_len);
	free(msg_id);
	free(keys);
	free(vals);

	if (!msg_buf)
		return ucv_boolean_new(false);

	send_record(svc, msg_buf, msg_len);
	free(msg_buf);

	return ucv_boolean_new(true);
}

static uc_value_t *
uc_usp_notify_oper_complete(uc_vm_t *vm, size_t nargs)
{
	usp_service_t *svc = uc_fn_thisval("usp.service");
	uc_value_t *command_v = uc_fn_arg(0);
	uc_value_t *command_key_v = uc_fn_arg(1);
	uc_value_t *err_code_v = uc_fn_arg(2);
	uc_value_t *err_msg_v = uc_fn_arg(3);
	uc_value_t *output_v = uc_fn_arg(4);
	const char **out_keys = NULL;
	const char **out_vals = NULL;
	size_t n_out = 0;
	uint8_t *msg_buf;
	size_t msg_len;
	char *msg_id;

	if (!svc || !svc->conn.handshake_complete)
		return ucv_boolean_new(false);

	const char *command = ucv_string_get(command_v);
	const char *command_key = ucv_string_get(command_key_v);
	uint32_t err_code = ucv_type(err_code_v) == UC_INTEGER ? ucv_int64_get(err_code_v) : 0;
	const char *err_msg = ucv_string_get(err_msg_v);

	if (!command)
		return ucv_boolean_new(false);

	if (output_v && ucv_type(output_v) == UC_OBJECT) {
		n_out = ucv_object_length(output_v);
		if (n_out > 0) {
			out_keys = calloc(n_out, sizeof(char *));
			out_vals = calloc(n_out, sizeof(char *));
			size_t i = 0;
			ucv_object_foreach(output_v, key, val) {
				out_keys[i] = key;
				out_vals[i] = ucv_string_get(val) ? ucv_string_get(val) : "";
				i++;
			}
		}
	}

	msg_id = usp_msg_id_generate();
	msg_buf = usp_msg_notify_oper_complete(msg_id, command,
					       command_key ? command_key : "",
					       err_code, err_msg ? err_msg : "",
					       out_keys, out_vals, n_out,
					       &msg_len);
	free(msg_id);
	free(out_keys);
	free(out_vals);

	if (!msg_buf)
		return ucv_boolean_new(false);

	send_record(svc, msg_buf, msg_len);
	free(msg_buf);

	return ucv_boolean_new(true);
}

static uc_value_t *
uc_usp_close(uc_vm_t *vm, size_t nargs)
{
	usp_service_t *svc = uc_fn_thisval("usp.service");
	uint8_t *disc;
	size_t disc_len;

	if (!svc)
		return NULL;

	if (svc->conn.handshake_complete) {
		disc = usp_record_wrap_disconnect(
			svc->conn.endpoint_id,
			svc->conn.peer_endpoint_id ? svc->conn.peer_endpoint_id : "",
			"closing", 0, &disc_len);
		if (disc) {
			uds_queue_record(&svc->conn, disc, disc_len);
			free(disc);
		}
	}

	uds_disconnect(&svc->conn);
	uloop_timeout_cancel(&svc->conn.reconnect_timer);
	ucv_resource_persistent_set(svc->res_obj, false);

	return NULL;
}

static const uc_function_list_t module_functions[] = {
	{ "connect", uc_usp_connect },
};

static const uc_function_list_t service_methods[] = {
	{ "register",		uc_usp_register },
	{ "deregister",		uc_usp_deregister },
	{ "notify_event",	uc_usp_notify_event },
	{ "notify_oper_complete", uc_usp_notify_oper_complete },
	{ "close",		uc_usp_close },
};

void uc_module_init(uc_vm_t *vm, uc_value_t *scope)
{
	uc_type_declare(vm, "usp.service", service_methods, service_free);
	uc_function_list_register(scope, module_functions);
}
