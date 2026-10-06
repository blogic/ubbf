#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <time.h>

#include "usp-protocol.h"

static unsigned int msg_id_counter;

char *
usp_msg_id_generate(void)
{
	char buf[64];

	snprintf(buf, sizeof(buf), "ubbf-%u-%u",
		 (unsigned)time(NULL), msg_id_counter++);

	return strdup(buf);
}

uint8_t *
usp_record_wrap(const char *from_id, const char *to_id,
		const uint8_t *msg_buf, size_t msg_len,
		size_t *out_len)
{
	UspRecord__Record rec = USP_RECORD__RECORD__INIT;
	UspRecord__NoSessionContextRecord nosess =
		USP_RECORD__NO_SESSION_CONTEXT_RECORD__INIT;
	uint8_t *buf;
	size_t len;

	nosess.payload.data = (uint8_t *)msg_buf;
	nosess.payload.len = msg_len;

	rec.version = (char *)USP_RECORD_VERSION;
	rec.from_id = (char *)from_id;
	rec.to_id = (char *)to_id;
	rec.payload_security = USP_RECORD__RECORD__PAYLOAD_SECURITY__PLAINTEXT;
	rec.record_type_case =
		USP_RECORD__RECORD__RECORD_TYPE_NO_SESSION_CONTEXT;
	rec.no_session_context = &nosess;

	len = usp_record__record__get_packed_size(&rec);
	buf = malloc(len);
	if (!buf)
		return NULL;

	usp_record__record__pack(&rec, buf);
	*out_len = len;

	return buf;
}

uint8_t *
usp_record_wrap_connect(const char *from_id, const char *to_id,
			size_t *out_len)
{
	UspRecord__Record rec = USP_RECORD__RECORD__INIT;
	UspRecord__UDSConnectRecord uds_connect =
		USP_RECORD__UDSCONNECT_RECORD__INIT;
	uint8_t *buf;
	size_t len;

	rec.version = (char *)USP_RECORD_VERSION;
	rec.from_id = (char *)from_id;
	rec.to_id = (char *)to_id;
	rec.payload_security = USP_RECORD__RECORD__PAYLOAD_SECURITY__PLAINTEXT;
	rec.record_type_case = USP_RECORD__RECORD__RECORD_TYPE_UDS_CONNECT;
	rec.uds_connect = &uds_connect;

	len = usp_record__record__get_packed_size(&rec);
	buf = malloc(len);
	if (!buf)
		return NULL;

	usp_record__record__pack(&rec, buf);
	*out_len = len;

	return buf;
}

uint8_t *
usp_record_wrap_disconnect(const char *from_id, const char *to_id,
			   const char *reason, uint32_t reason_code,
			   size_t *out_len)
{
	UspRecord__Record rec = USP_RECORD__RECORD__INIT;
	UspRecord__DisconnectRecord disc =
		USP_RECORD__DISCONNECT_RECORD__INIT;
	uint8_t *buf;
	size_t len;

	disc.reason = (char *)(reason ? reason : "");
	disc.reason_code = reason_code;

	rec.version = (char *)USP_RECORD_VERSION;
	rec.from_id = (char *)from_id;
	rec.to_id = (char *)to_id;
	rec.payload_security = USP_RECORD__RECORD__PAYLOAD_SECURITY__PLAINTEXT;
	rec.record_type_case = USP_RECORD__RECORD__RECORD_TYPE_DISCONNECT;
	rec.disconnect = &disc;

	len = usp_record__record__get_packed_size(&rec);
	buf = malloc(len);
	if (!buf)
		return NULL;

	usp_record__record__pack(&rec, buf);
	*out_len = len;

	return buf;
}

uint8_t *
usp_msg_build(const char *msg_id, Usp__Header__MsgType msg_type,
	      Usp__Body *body, size_t *out_len)
{
	Usp__Msg msg = USP__MSG__INIT;
	Usp__Header header = USP__HEADER__INIT;
	uint8_t *buf;
	size_t len;

	header.msg_id = (char *)msg_id;
	header.msg_type = msg_type;
	msg.header = &header;
	msg.body = body;

	len = usp__msg__get_packed_size(&msg);
	buf = malloc(len);
	if (!buf)
		return NULL;

	usp__msg__pack(&msg, buf);
	*out_len = len;

	return buf;
}

Usp__Msg *
usp_record_extract_msg(const uint8_t *record_buf, size_t record_len)
{
	UspRecord__Record *rec;
	Usp__Msg *msg = NULL;

	rec = usp_record__record__unpack(NULL, record_len, record_buf);
	if (!rec)
		return NULL;

	if (rec->record_type_case !=
	    USP_RECORD__RECORD__RECORD_TYPE_NO_SESSION_CONTEXT ||
	    !rec->no_session_context ||
	    rec->no_session_context->payload.len == 0)
		goto out;

	msg = usp__msg__unpack(NULL,
			       rec->no_session_context->payload.len,
			       rec->no_session_context->payload.data);

out:
	usp_record__record__free_unpacked(rec, NULL);
	return msg;
}

void
usp_msg_free(Usp__Msg *msg)
{
	if (msg)
		usp__msg__free_unpacked(msg, NULL);
}

uint8_t *
usp_msg_register(const char *msg_id, char **paths, size_t n_paths,
		 size_t *out_len)
{
	Usp__Body body = USP__BODY__INIT;
	Usp__Request request = USP__REQUEST__INIT;
	Usp__Register reg = USP__REGISTER__INIT;
	Usp__Register__RegistrationPath **reg_paths;

	reg_paths = calloc(n_paths, sizeof(*reg_paths));
	if (!reg_paths)
		return NULL;

	Usp__Register__RegistrationPath *path_storage =
		calloc(n_paths, sizeof(*path_storage));
	if (!path_storage) {
		free(reg_paths);
		return NULL;
	}

	for (size_t i = 0; i < n_paths; i++) {
		usp__register__registration_path__init(&path_storage[i]);
		path_storage[i].path = paths[i];
		reg_paths[i] = &path_storage[i];
	}

	reg.allow_partial = true;
	reg.n_reg_paths = n_paths;
	reg.reg_paths = reg_paths;

	request.req_type_case = USP__REQUEST__REQ_TYPE_REGISTER;
	request.register_ = &reg;

	body.msg_body_case = USP__BODY__MSG_BODY_REQUEST;
	body.request = &request;

	uint8_t *buf = usp_msg_build(msg_id,
				     USP__HEADER__MSG_TYPE__REGISTER,
				     &body, out_len);

	free(path_storage);
	free(reg_paths);

	return buf;
}

uint8_t *
usp_msg_deregister(const char *msg_id, char **paths, size_t n_paths,
		   size_t *out_len)
{
	Usp__Body body = USP__BODY__INIT;
	Usp__Request request = USP__REQUEST__INIT;
	Usp__Deregister dereg = USP__DEREGISTER__INIT;

	dereg.n_paths = n_paths;
	dereg.paths = paths;

	request.req_type_case = USP__REQUEST__REQ_TYPE_DEREGISTER;
	request.deregister = &dereg;

	body.msg_body_case = USP__BODY__MSG_BODY_REQUEST;
	body.request = &request;

	return usp_msg_build(msg_id, USP__HEADER__MSG_TYPE__DEREGISTER,
			     &body, out_len);
}

uint8_t *
usp_msg_get_resp(const char *msg_id,
		 const char **param_paths, const char **param_values,
		 size_t n_params, size_t *out_len)
{
	Usp__Body body = USP__BODY__INIT;
	Usp__Response response = USP__RESPONSE__INIT;
	Usp__GetResp get_resp = USP__GET_RESP__INIT;
	uint8_t *result = NULL;

	Usp__GetResp__ResolvedPathResult__ResultParamsEntry **entries = NULL;
	Usp__GetResp__ResolvedPathResult__ResultParamsEntry *entry_storage = NULL;
	Usp__GetResp__ResolvedPathResult resolved =
		USP__GET_RESP__RESOLVED_PATH_RESULT__INIT;
	Usp__GetResp__ResolvedPathResult *resolved_ptr = &resolved;
	Usp__GetResp__RequestedPathResult req_result =
		USP__GET_RESP__REQUESTED_PATH_RESULT__INIT;
	Usp__GetResp__RequestedPathResult *req_result_ptr = &req_result;

	if (n_params > 0) {
		entries = calloc(n_params, sizeof(*entries));
		entry_storage = calloc(n_params, sizeof(*entry_storage));
		if (!entries || !entry_storage)
			goto out;

		for (size_t i = 0; i < n_params; i++) {
			usp__get_resp__resolved_path_result__result_params_entry__init(
				&entry_storage[i]);
			entry_storage[i].key = (char *)param_paths[i];
			entry_storage[i].value = (char *)param_values[i];
			entries[i] = &entry_storage[i];
		}
	}

	resolved.resolved_path = "";
	resolved.n_result_params = n_params;
	resolved.result_params = entries;

	req_result.requested_path = "";
	req_result.n_resolved_path_results = 1;
	req_result.resolved_path_results = &resolved_ptr;

	get_resp.n_req_path_results = 1;
	get_resp.req_path_results = &req_result_ptr;

	response.resp_type_case = USP__RESPONSE__RESP_TYPE_GET_RESP;
	response.get_resp = &get_resp;

	body.msg_body_case = USP__BODY__MSG_BODY_RESPONSE;
	body.response = &response;

	result = usp_msg_build(msg_id, USP__HEADER__MSG_TYPE__GET_RESP,
			       &body, out_len);

out:
	free(entries);
	free(entry_storage);
	return result;
}

uint8_t *
usp_msg_set_resp(const char *msg_id, size_t *out_len)
{
	Usp__Body body = USP__BODY__INIT;
	Usp__Response response = USP__RESPONSE__INIT;
	Usp__SetResp set_resp = USP__SET_RESP__INIT;

	response.resp_type_case = USP__RESPONSE__RESP_TYPE_SET_RESP;
	response.set_resp = &set_resp;

	body.msg_body_case = USP__BODY__MSG_BODY_RESPONSE;
	body.response = &response;

	return usp_msg_build(msg_id, USP__HEADER__MSG_TYPE__SET_RESP,
			     &body, out_len);
}

uint8_t *
usp_msg_add_resp(const char *msg_id, const char *requested_path,
		 const char *created_path, uint32_t err_code,
		 const char *err_msg, size_t *out_len)
{
	Usp__Body body = USP__BODY__INIT;
	Usp__Response response = USP__RESPONSE__INIT;
	Usp__AddResp add_resp = USP__ADD_RESP__INIT;
	Usp__AddResp__CreatedObjectResult obj_result =
		USP__ADD_RESP__CREATED_OBJECT_RESULT__INIT;
	Usp__AddResp__CreatedObjectResult *obj_result_ptr = &obj_result;
	Usp__AddResp__CreatedObjectResult__OperationStatus oper_status =
		USP__ADD_RESP__CREATED_OBJECT_RESULT__OPERATION_STATUS__INIT;

	obj_result.requested_path = (char *)requested_path;
	obj_result.oper_status = &oper_status;

	if (err_code == 0) {
		Usp__AddResp__CreatedObjectResult__OperationStatus__OperationSuccess
			success = USP__ADD_RESP__CREATED_OBJECT_RESULT__OPERATION_STATUS__OPERATION_SUCCESS__INIT;

		success.instantiated_path = (char *)created_path;
		success.n_unique_keys = 0;
		success.n_param_errs = 0;

		oper_status.oper_status_case =
			USP__ADD_RESP__CREATED_OBJECT_RESULT__OPERATION_STATUS__OPER_STATUS_OPER_SUCCESS;
		oper_status.oper_success = &success;
	} else {
		Usp__AddResp__CreatedObjectResult__OperationStatus__OperationFailure
			failure = USP__ADD_RESP__CREATED_OBJECT_RESULT__OPERATION_STATUS__OPERATION_FAILURE__INIT;

		failure.err_code = err_code;
		failure.err_msg = (char *)(err_msg ? err_msg : "");

		oper_status.oper_status_case =
			USP__ADD_RESP__CREATED_OBJECT_RESULT__OPERATION_STATUS__OPER_STATUS_OPER_FAILURE;
		oper_status.oper_failure = &failure;
	}

	add_resp.n_created_obj_results = 1;
	add_resp.created_obj_results = &obj_result_ptr;

	response.resp_type_case = USP__RESPONSE__RESP_TYPE_ADD_RESP;
	response.add_resp = &add_resp;

	body.msg_body_case = USP__BODY__MSG_BODY_RESPONSE;
	body.response = &response;

	return usp_msg_build(msg_id, USP__HEADER__MSG_TYPE__ADD_RESP,
			     &body, out_len);
}

uint8_t *
usp_msg_delete_resp(const char *msg_id, const char *requested_path,
		    uint32_t err_code, const char *err_msg, size_t *out_len)
{
	Usp__Body body = USP__BODY__INIT;
	Usp__Response response = USP__RESPONSE__INIT;
	Usp__DeleteResp delete_resp = USP__DELETE_RESP__INIT;
	Usp__DeleteResp__DeletedObjectResult obj_result =
		USP__DELETE_RESP__DELETED_OBJECT_RESULT__INIT;
	Usp__DeleteResp__DeletedObjectResult *obj_result_ptr = &obj_result;
	Usp__DeleteResp__DeletedObjectResult__OperationStatus oper_status =
		USP__DELETE_RESP__DELETED_OBJECT_RESULT__OPERATION_STATUS__INIT;

	obj_result.requested_path = (char *)requested_path;
	obj_result.oper_status = &oper_status;

	if (err_code == 0) {
		Usp__DeleteResp__DeletedObjectResult__OperationStatus__OperationSuccess
			success = USP__DELETE_RESP__DELETED_OBJECT_RESULT__OPERATION_STATUS__OPERATION_SUCCESS__INIT;

		char *affected = (char *)requested_path;
		success.n_affected_paths = 1;
		success.affected_paths = &affected;

		oper_status.oper_status_case =
			USP__DELETE_RESP__DELETED_OBJECT_RESULT__OPERATION_STATUS__OPER_STATUS_OPER_SUCCESS;
		oper_status.oper_success = &success;
	} else {
		Usp__DeleteResp__DeletedObjectResult__OperationStatus__OperationFailure
			failure = USP__DELETE_RESP__DELETED_OBJECT_RESULT__OPERATION_STATUS__OPERATION_FAILURE__INIT;

		failure.err_code = err_code;
		failure.err_msg = (char *)(err_msg ? err_msg : "");

		oper_status.oper_status_case =
			USP__DELETE_RESP__DELETED_OBJECT_RESULT__OPERATION_STATUS__OPER_STATUS_OPER_FAILURE;
		oper_status.oper_failure = &failure;
	}

	delete_resp.n_deleted_obj_results = 1;
	delete_resp.deleted_obj_results = &obj_result_ptr;

	response.resp_type_case = USP__RESPONSE__RESP_TYPE_DELETE_RESP;
	response.delete_resp = &delete_resp;

	body.msg_body_case = USP__BODY__MSG_BODY_RESPONSE;
	body.response = &response;

	return usp_msg_build(msg_id, USP__HEADER__MSG_TYPE__DELETE_RESP,
			     &body, out_len);
}

uint8_t *
usp_msg_operate_resp(const char *msg_id, const char *command,
		     const char **out_keys, const char **out_vals,
		     size_t n_out, const char *req_obj_path,
		     size_t *out_len)
{
	Usp__Body body = USP__BODY__INIT;
	Usp__Response response = USP__RESPONSE__INIT;
	Usp__OperateResp oper_resp = USP__OPERATE_RESP__INIT;
	Usp__OperateResp__OperationResult op_result =
		USP__OPERATE_RESP__OPERATION_RESULT__INIT;
	Usp__OperateResp__OperationResult *op_result_ptr = &op_result;

	op_result.executed_command = (char *)command;

	if (req_obj_path) {
		Usp__OperateResp__OperationResult__OutputArgs output_args =
			USP__OPERATE_RESP__OPERATION_RESULT__OUTPUT_ARGS__INIT;

		Usp__OperateResp__OperationResult__OutputArgs__OutputArgsEntry **entries = NULL;
		Usp__OperateResp__OperationResult__OutputArgs__OutputArgsEntry *entry_storage = NULL;

		if (n_out > 0) {
			entries = calloc(n_out, sizeof(*entries));
			entry_storage = calloc(n_out, sizeof(*entry_storage));
			for (size_t i = 0; i < n_out; i++) {
				usp__operate_resp__operation_result__output_args__output_args_entry__init(&entry_storage[i]);
				entry_storage[i].key = (char *)out_keys[i];
				entry_storage[i].value = (char *)out_vals[i];
				entries[i] = &entry_storage[i];
			}
			output_args.n_output_args = n_out;
			output_args.output_args = entries;
		}

		op_result.operation_resp_case =
			USP__OPERATE_RESP__OPERATION_RESULT__OPERATION_RESP_REQ_OBJ_PATH;
		op_result.req_obj_path = (char *)req_obj_path;

		oper_resp.n_operation_results = 1;
		oper_resp.operation_results = &op_result_ptr;

		response.resp_type_case = USP__RESPONSE__RESP_TYPE_OPERATE_RESP;
		response.operate_resp = &oper_resp;

		body.msg_body_case = USP__BODY__MSG_BODY_RESPONSE;
		body.response = &response;

		uint8_t *buf = usp_msg_build(msg_id,
					     USP__HEADER__MSG_TYPE__OPERATE_RESP,
					     &body, out_len);
		free(entries);
		free(entry_storage);
		return buf;
	}

	Usp__OperateResp__OperationResult__OutputArgs output_args =
		USP__OPERATE_RESP__OPERATION_RESULT__OUTPUT_ARGS__INIT;

	Usp__OperateResp__OperationResult__OutputArgs__OutputArgsEntry **entries = NULL;
	Usp__OperateResp__OperationResult__OutputArgs__OutputArgsEntry *entry_storage = NULL;

	if (n_out > 0) {
		entries = calloc(n_out, sizeof(*entries));
		entry_storage = calloc(n_out, sizeof(*entry_storage));
		for (size_t i = 0; i < n_out; i++) {
			usp__operate_resp__operation_result__output_args__output_args_entry__init(&entry_storage[i]);
			entry_storage[i].key = (char *)out_keys[i];
			entry_storage[i].value = (char *)out_vals[i];
			entries[i] = &entry_storage[i];
		}
		output_args.n_output_args = n_out;
		output_args.output_args = entries;
	}

	op_result.operation_resp_case =
		USP__OPERATE_RESP__OPERATION_RESULT__OPERATION_RESP_REQ_OUTPUT_ARGS;
	op_result.req_output_args = &output_args;

	oper_resp.n_operation_results = 1;
	oper_resp.operation_results = &op_result_ptr;

	response.resp_type_case = USP__RESPONSE__RESP_TYPE_OPERATE_RESP;
	response.operate_resp = &oper_resp;

	body.msg_body_case = USP__BODY__MSG_BODY_RESPONSE;
	body.response = &response;

	uint8_t *buf = usp_msg_build(msg_id,
				     USP__HEADER__MSG_TYPE__OPERATE_RESP,
				     &body, out_len);
	free(entries);
	free(entry_storage);
	return buf;
}

uint8_t *
usp_msg_get_instances_resp(const char *msg_id,
			   const struct get_instances_result *results,
			   size_t n_results, size_t *out_len)
{
	Usp__Body body = USP__BODY__INIT;
	Usp__Response response = USP__RESPONSE__INIT;
	Usp__GetInstancesResp gi_resp = USP__GET_INSTANCES_RESP__INIT;

	Usp__GetInstancesResp__RequestedPathResult **req_results = NULL;
	Usp__GetInstancesResp__RequestedPathResult *req_storage = NULL;

	Usp__GetInstancesResp__CurrInstance **all_insts = NULL;
	Usp__GetInstancesResp__CurrInstance *inst_storage = NULL;
	size_t total_insts = 0;

	if (n_results > 0 && results) {
		for (size_t i = 0; i < n_results; i++)
			total_insts += results[i].n_instances;

		req_results = calloc(n_results, sizeof(*req_results));
		req_storage = calloc(n_results, sizeof(*req_storage));

		if (total_insts > 0) {
			all_insts = calloc(total_insts, sizeof(*all_insts));
			inst_storage = calloc(total_insts, sizeof(*inst_storage));
		}

		size_t inst_idx = 0;
		for (size_t i = 0; i < n_results; i++) {
			usp__get_instances_resp__requested_path_result__init(&req_storage[i]);
			req_storage[i].requested_path = (char *)results[i].requested_path;

			if (results[i].n_instances > 0) {
				req_storage[i].n_curr_insts = results[i].n_instances;
				req_storage[i].curr_insts = &all_insts[inst_idx];

				for (size_t j = 0; j < results[i].n_instances; j++) {
					usp__get_instances_resp__curr_instance__init(&inst_storage[inst_idx]);
					inst_storage[inst_idx].instantiated_obj_path =
						(char *)results[i].instance_paths[j];
					all_insts[inst_idx] = &inst_storage[inst_idx];
					inst_idx++;
				}
			}

			req_results[i] = &req_storage[i];
		}
	}

	gi_resp.n_req_path_results = n_results;
	gi_resp.req_path_results = req_results;

	response.resp_type_case = USP__RESPONSE__RESP_TYPE_GET_INSTANCES_RESP;
	response.get_instances_resp = &gi_resp;

	body.msg_body_case = USP__BODY__MSG_BODY_RESPONSE;
	body.response = &response;

	uint8_t *buf = usp_msg_build(msg_id,
				     USP__HEADER__MSG_TYPE__GET_INSTANCES_RESP,
				     &body, out_len);

	free(req_results);
	free(req_storage);
	free(all_insts);
	free(inst_storage);

	return buf;
}

uint8_t *
usp_msg_get_supported_dm_resp(const char *msg_id,
			      uc_value_t *schema,
			      size_t *out_len)
{
	Usp__Body body = USP__BODY__INIT;
	Usp__Response response = USP__RESPONSE__INIT;
	Usp__GetSupportedDMResp gsdm_resp = USP__GET_SUPPORTED_DMRESP__INIT;
	Usp__GetSupportedDMResp__RequestedObjectResult req_result =
		USP__GET_SUPPORTED_DMRESP__REQUESTED_OBJECT_RESULT__INIT;
	Usp__GetSupportedDMResp__RequestedObjectResult *req_result_ptr = &req_result;

	uc_value_t *objects = ucv_object_get(schema, "objects", NULL);
	size_t n_objs = objects ? ucv_object_length(objects) : 0;

	Usp__GetSupportedDMResp__SupportedObjectResult **obj_results = NULL;
	Usp__GetSupportedDMResp__SupportedObjectResult *obj_storage = NULL;

	Usp__GetSupportedDMResp__SupportedParamResult **all_params = NULL;
	Usp__GetSupportedDMResp__SupportedParamResult *param_storage = NULL;
	Usp__GetSupportedDMResp__SupportedCommandResult **all_cmds = NULL;
	Usp__GetSupportedDMResp__SupportedCommandResult *cmd_storage = NULL;
	size_t total_params = 0;
	size_t total_cmds = 0;

	if (n_objs > 0 && objects) {
		ucv_object_foreach(objects, key, val) {
			(void)key;
			if (ucv_type(val) != UC_OBJECT)
				continue;
			ucv_object_foreach(val, pkey, pval) {
				(void)pkey;
				if (ucv_type(pval) == UC_OBJECT)
					total_cmds++;
				else
					total_params++;
			}
		}

		obj_results = calloc(n_objs, sizeof(*obj_results));
		obj_storage = calloc(n_objs, sizeof(*obj_storage));
		if (total_params > 0) {
			all_params = calloc(total_params, sizeof(*all_params));
			param_storage = calloc(total_params, sizeof(*param_storage));
		}
		if (total_cmds > 0) {
			all_cmds = calloc(total_cmds, sizeof(*all_cmds));
			cmd_storage = calloc(total_cmds, sizeof(*cmd_storage));
		}

		size_t obj_idx = 0, param_idx = 0, cmd_idx = 0;

		ucv_object_foreach(objects, obj_path, obj_schema) {
			char mi_check[512];

			if (ucv_type(obj_schema) != UC_OBJECT)
				continue;

			snprintf(mi_check, sizeof(mi_check), "%s.{i}", obj_path);
			if (ucv_object_get(objects, mi_check, NULL))
				continue;

			usp__get_supported_dmresp__supported_object_result__init(&obj_storage[obj_idx]);

			char path_buf[512];
			snprintf(path_buf, sizeof(path_buf), "%s.", obj_path);
			obj_storage[obj_idx].supported_obj_path = strdup(path_buf);

			bool is_multi = (strstr(obj_path, "{i}") != NULL);
			obj_storage[obj_idx].is_multi_instance = is_multi;
			obj_storage[obj_idx].access =
				USP__GET_SUPPORTED_DMRESP__OBJ_ACCESS_TYPE__OBJ_READ_ONLY;
			if (is_multi)
				obj_storage[obj_idx].access =
					USP__GET_SUPPORTED_DMRESP__OBJ_ACCESS_TYPE__OBJ_ADD_DELETE;

			size_t first_param = param_idx;
			size_t first_cmd = cmd_idx;

			ucv_object_foreach(obj_schema, pname, pval) {
				if (ucv_type(pval) == UC_OBJECT) {
					if (cmd_idx < total_cmds) {
						usp__get_supported_dmresp__supported_command_result__init(&cmd_storage[cmd_idx]);
						cmd_storage[cmd_idx].command_name = strdup(pname);
						cmd_storage[cmd_idx].command_type =
							USP__GET_SUPPORTED_DMRESP__CMD_TYPE__CMD_ASYNC;

						uc_value_t *type_v = ucv_object_get(pval, "type", NULL);
						if (type_v && ucv_type(type_v) == UC_STRING) {
							const char *ts = ucv_string_get(type_v);
							if (ts && !strcmp(ts, "sync"))
								cmd_storage[cmd_idx].command_type =
									USP__GET_SUPPORTED_DMRESP__CMD_TYPE__CMD_SYNC;
						}

						all_cmds[cmd_idx] = &cmd_storage[cmd_idx];
						cmd_idx++;
					}
				} else if (ucv_type(pval) == UC_INTEGER) {
					if (param_idx < total_params) {
						usp__get_supported_dmresp__supported_param_result__init(&param_storage[param_idx]);
						param_storage[param_idx].param_name = strdup(pname);

						uint64_t flags = ucv_uint64_get(pval);
						param_storage[param_idx].access =
							(flags & 0x80000000)
							? USP__GET_SUPPORTED_DMRESP__PARAM_ACCESS_TYPE__PARAM_READ_WRITE
							: USP__GET_SUPPORTED_DMRESP__PARAM_ACCESS_TYPE__PARAM_READ_ONLY;

						all_params[param_idx] = &param_storage[param_idx];
						param_idx++;
					}
				}
			}

			obj_storage[obj_idx].n_supported_params = param_idx - first_param;
			obj_storage[obj_idx].supported_params =
				(param_idx > first_param) ? &all_params[first_param] : NULL;
			obj_storage[obj_idx].n_supported_commands = cmd_idx - first_cmd;
			obj_storage[obj_idx].supported_commands =
				(cmd_idx > first_cmd) ? &all_cmds[first_cmd] : NULL;

			obj_results[obj_idx] = &obj_storage[obj_idx];
			obj_idx++;
		}

		n_objs = obj_idx;
	}

	req_result.req_obj_path = "Device.";
	req_result.err_code = 0;
	req_result.err_msg = "";
	req_result.n_supported_objs = n_objs;
	req_result.supported_objs = obj_results;

	gsdm_resp.n_req_obj_results = 1;
	gsdm_resp.req_obj_results = &req_result_ptr;

	response.resp_type_case = USP__RESPONSE__RESP_TYPE_GET_SUPPORTED_DM_RESP;
	response.get_supported_dm_resp = &gsdm_resp;

	body.msg_body_case = USP__BODY__MSG_BODY_RESPONSE;
	body.response = &response;

	uint8_t *buf = usp_msg_build(msg_id,
				     USP__HEADER__MSG_TYPE__GET_SUPPORTED_DM_RESP,
				     &body, out_len);

	for (size_t i = 0; i < n_objs && obj_storage; i++)
		free(obj_storage[i].supported_obj_path);
	for (size_t i = 0; i < total_params && param_storage; i++)
		free(param_storage[i].param_name);
	for (size_t i = 0; i < total_cmds && cmd_storage; i++)
		free(cmd_storage[i].command_name);

	free(obj_results);
	free(obj_storage);
	free(all_params);
	free(param_storage);
	free(all_cmds);
	free(cmd_storage);

	return buf;
}

uint8_t *
usp_msg_notify_event(const char *msg_id, const char *event_name,
		     const char **keys, const char **vals,
		     size_t n_params, size_t *out_len)
{
	Usp__Body body = USP__BODY__INIT;
	Usp__Notify notify = USP__NOTIFY__INIT;
	Usp__Notify__Event event = USP__NOTIFY__EVENT__INIT;

	Usp__Notify__Event__ParamsEntry **entries = NULL;
	Usp__Notify__Event__ParamsEntry *entry_storage = NULL;

	if (n_params > 0) {
		entries = calloc(n_params, sizeof(*entries));
		entry_storage = calloc(n_params, sizeof(*entry_storage));
		for (size_t i = 0; i < n_params; i++) {
			usp__notify__event__params_entry__init(&entry_storage[i]);
			entry_storage[i].key = (char *)keys[i];
			entry_storage[i].value = (char *)vals[i];
			entries[i] = &entry_storage[i];
		}
	}

	event.obj_path = (char *)event_name;
	event.event_name = (char *)event_name;
	event.n_params = n_params;
	event.params = entries;

	notify.notification_case = USP__NOTIFY__NOTIFICATION_EVENT;
	notify.event = &event;
	notify.send_resp = false;

	Usp__Request request = USP__REQUEST__INIT;
	request.req_type_case = USP__REQUEST__REQ_TYPE_NOTIFY;
	request.notify = &notify;

	body.msg_body_case = USP__BODY__MSG_BODY_REQUEST;
	body.request = &request;

	uint8_t *buf = usp_msg_build(msg_id,
				     USP__HEADER__MSG_TYPE__NOTIFY,
				     &body, out_len);

	free(entries);
	free(entry_storage);
	return buf;
}

uint8_t *
usp_msg_notify_oper_complete(const char *msg_id,
			     const char *command,
			     const char *command_key,
			     uint32_t err_code,
			     const char *err_msg,
			     const char **out_keys,
			     const char **out_vals,
			     size_t n_out, size_t *out_len)
{
	Usp__Body body = USP__BODY__INIT;
	Usp__Notify notify = USP__NOTIFY__INIT;
	Usp__Notify__OperationComplete oper_complete =
		USP__NOTIFY__OPERATION_COMPLETE__INIT;

	oper_complete.obj_path = (char *)command;
	oper_complete.command_name = (char *)command;
	oper_complete.command_key = (char *)command_key;

	if (err_code == 0) {
		Usp__Notify__OperationComplete__OutputArgs output_args =
			USP__NOTIFY__OPERATION_COMPLETE__OUTPUT_ARGS__INIT;

		Usp__Notify__OperationComplete__OutputArgs__OutputArgsEntry **entries = NULL;
		Usp__Notify__OperationComplete__OutputArgs__OutputArgsEntry *entry_storage = NULL;

		if (n_out > 0) {
			entries = calloc(n_out, sizeof(*entries));
			entry_storage = calloc(n_out, sizeof(*entry_storage));
			for (size_t i = 0; i < n_out; i++) {
				usp__notify__operation_complete__output_args__output_args_entry__init(&entry_storage[i]);
				entry_storage[i].key = (char *)out_keys[i];
				entry_storage[i].value = (char *)out_vals[i];
				entries[i] = &entry_storage[i];
			}
			output_args.n_output_args = n_out;
			output_args.output_args = entries;
		}

		oper_complete.operation_resp_case =
			USP__NOTIFY__OPERATION_COMPLETE__OPERATION_RESP_REQ_OUTPUT_ARGS;
		oper_complete.req_output_args = &output_args;

		notify.notification_case = USP__NOTIFY__NOTIFICATION_OPER_COMPLETE;
		notify.oper_complete = &oper_complete;
		notify.send_resp = false;

		Usp__Request request = USP__REQUEST__INIT;
		request.req_type_case = USP__REQUEST__REQ_TYPE_NOTIFY;
		request.notify = &notify;

		body.msg_body_case = USP__BODY__MSG_BODY_REQUEST;
		body.request = &request;

		uint8_t *buf = usp_msg_build(msg_id,
					     USP__HEADER__MSG_TYPE__NOTIFY,
					     &body, out_len);
		free(entries);
		free(entry_storage);
		return buf;
	}

	Usp__Notify__OperationComplete__CommandFailure failure =
		USP__NOTIFY__OPERATION_COMPLETE__COMMAND_FAILURE__INIT;

	failure.err_code = err_code;
	failure.err_msg = (char *)(err_msg ? err_msg : "");

	oper_complete.operation_resp_case =
		USP__NOTIFY__OPERATION_COMPLETE__OPERATION_RESP_CMD_FAILURE;
	oper_complete.cmd_failure = &failure;

	notify.notification_case = USP__NOTIFY__NOTIFICATION_OPER_COMPLETE;
	notify.oper_complete = &oper_complete;
	notify.send_resp = false;

	Usp__Request request = USP__REQUEST__INIT;
	request.req_type_case = USP__REQUEST__REQ_TYPE_NOTIFY;
	request.notify = &notify;

	body.msg_body_case = USP__BODY__MSG_BODY_REQUEST;
	body.request = &request;

	return usp_msg_build(msg_id, USP__HEADER__MSG_TYPE__NOTIFY,
			     &body, out_len);
}

uint8_t *
usp_msg_error(const char *msg_id, uint32_t err_code, const char *err_msg,
	      size_t *out_len)
{
	Usp__Body body = USP__BODY__INIT;
	Usp__Error error = USP__ERROR__INIT;

	error.err_code = err_code;
	error.err_msg = (char *)(err_msg ? err_msg : "");

	body.msg_body_case = USP__BODY__MSG_BODY_ERROR;
	body.error = &error;

	return usp_msg_build(msg_id, USP__HEADER__MSG_TYPE__ERROR,
			     &body, out_len);
}
