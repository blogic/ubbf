#ifndef USP_PROTOCOL_H
#define USP_PROTOCOL_H

#include <stdint.h>
#include <stddef.h>

#include <ucode/types.h>

#include "usp-record.pb-c.h"
#include "usp-msg.pb-c.h"
#include "uds-transport.h"

#define USP_RECORD_VERSION	"1.3"

uint8_t *usp_record_wrap(const char *from_id, const char *to_id,
			  const uint8_t *msg_buf, size_t msg_len,
			  size_t *out_len);

uint8_t *usp_record_wrap_connect(const char *from_id, const char *to_id,
				 size_t *out_len);

uint8_t *usp_record_wrap_disconnect(const char *from_id, const char *to_id,
				    const char *reason, uint32_t reason_code,
				    size_t *out_len);

uint8_t *usp_msg_build(const char *msg_id, Usp__Header__MsgType msg_type,
			Usp__Body *body, size_t *out_len);

Usp__Msg *usp_record_extract_msg(const uint8_t *record_buf, size_t record_len);
void usp_msg_free(Usp__Msg *msg);

uint8_t *usp_msg_register(const char *msg_id, char **paths, size_t n_paths,
			   size_t *out_len);

uint8_t *usp_msg_deregister(const char *msg_id, char **paths, size_t n_paths,
			     size_t *out_len);

uint8_t *usp_msg_get_resp(const char *msg_id,
			   const char **param_paths, const char **param_values,
			   size_t n_params, size_t *out_len);

uint8_t *usp_msg_set_resp(const char *msg_id, size_t *out_len);

uint8_t *usp_msg_add_resp(const char *msg_id, const char *requested_path,
			   const char *created_path, uint32_t err_code,
			   const char *err_msg, size_t *out_len);

uint8_t *usp_msg_delete_resp(const char *msg_id, const char *requested_path,
			      uint32_t err_code, const char *err_msg,
			      size_t *out_len);

uint8_t *usp_msg_operate_resp(const char *msg_id, const char *command,
			      const char **out_keys, const char **out_vals,
			      size_t n_out, const char *req_obj_path,
			      size_t *out_len);

struct get_instances_result {
	const char *requested_path;
	const char **instance_paths;
	size_t n_instances;
};

uint8_t *usp_msg_get_instances_resp(const char *msg_id,
				    const struct get_instances_result *results,
				    size_t n_results, size_t *out_len);

uint8_t *usp_msg_get_supported_dm_resp(const char *msg_id,
					uc_value_t *schema,
					size_t *out_len);

uint8_t *usp_msg_notify_event(const char *msg_id, const char *event_name,
			      const char **keys, const char **vals,
			      size_t n_params, size_t *out_len);

uint8_t *usp_msg_notify_oper_complete(const char *msg_id,
				      const char *command,
				      const char *command_key,
				      uint32_t err_code,
				      const char *err_msg,
				      const char **out_keys,
				      const char **out_vals,
				      size_t n_out, size_t *out_len);

uint8_t *usp_msg_error(const char *msg_id, uint32_t err_code,
			const char *err_msg, size_t *out_len);

char *usp_msg_id_generate(void);

#endif
