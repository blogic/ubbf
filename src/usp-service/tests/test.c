/* SPDX-License-Identifier: GPL-2.0-only */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "../uds-transport.c"
#include "../usp-protocol.h"

static int failures;

#define CHECK(_cond) do {							\
	if (!(_cond)) {								\
		fprintf(stderr, "%s:%d: check failed: %s\n",			\
			__FILE__, __LINE__, #_cond);				\
		failures++;							\
	}									\
} while (0)

#define CHECK_STR(_a, _b) do {							\
	const char *_x = (_a), *_y = (_b);					\
	if (!_x || strcmp(_x, _y)) {						\
		fprintf(stderr, "%s:%d: \"%s\" != \"%s\"\n",			\
			__FILE__, __LINE__, _x ? _x : "(null)", _y);		\
		failures++;							\
	}									\
} while (0)

/* The Add and Delete responses decode to what was built, on the success
 * and the failure branch. */
static void
test_add_delete_resp(void)
{
	Usp__Msg *msg;
	uint8_t *buf;
	size_t len;

	buf = usp_msg_add_resp("m1", "Device.X.", "Device.X.3.", 0, NULL, &len);
	msg = usp__msg__unpack(NULL, len, buf);
	CHECK(msg && msg->body->response->add_resp->n_created_obj_results == 1);
	if (msg)
		CHECK_STR(msg->body->response->add_resp->created_obj_results[0]
			  ->oper_status->oper_success->instantiated_path, "Device.X.3.");
	usp__msg__free_unpacked(msg, NULL);
	free(buf);

	buf = usp_msg_add_resp("m2", "Device.X.", NULL, 7004, "no", &len);
	msg = usp__msg__unpack(NULL, len, buf);
	CHECK(msg && msg->body->response->add_resp->created_obj_results[0]
	      ->oper_status->oper_failure->err_code == 7004);
	if (msg)
		CHECK_STR(msg->body->response->add_resp->created_obj_results[0]
			  ->oper_status->oper_failure->err_msg, "no");
	usp__msg__free_unpacked(msg, NULL);
	free(buf);

	buf = usp_msg_delete_resp("m3", "Device.X.3.", 0, NULL, &len);
	msg = usp__msg__unpack(NULL, len, buf);
	CHECK(msg && msg->body->response->delete_resp->deleted_obj_results[0]
	      ->oper_status->oper_success->n_affected_paths == 1);
	if (msg)
		CHECK_STR(msg->body->response->delete_resp->deleted_obj_results[0]
			  ->oper_status->oper_success->affected_paths[0], "Device.X.3.");
	usp__msg__free_unpacked(msg, NULL);
	free(buf);

	buf = usp_msg_delete_resp("m4", "Device.X.3.", 7016, "gone", &len);
	msg = usp__msg__unpack(NULL, len, buf);
	CHECK(msg && msg->body->response->delete_resp->deleted_obj_results[0]
	      ->oper_status->oper_failure->err_code == 7016);
	if (msg)
		CHECK_STR(msg->body->response->delete_resp->deleted_obj_results[0]
			  ->oper_status->oper_failure->err_msg, "gone");
	usp__msg__free_unpacked(msg, NULL);
	free(buf);
}

static int handshakes, records, disconnects;

static void on_handshake(struct uds_conn *conn, const char *eid) { handshakes++; }
static void on_record(struct uds_conn *conn, const uint8_t *data, size_t len) { records++; }
static void on_disconnect(struct uds_conn *conn) { disconnects++; }

static const struct uds_ops ops = {
	.on_handshake = on_handshake,
	.on_record = on_record,
	.on_disconnect = on_disconnect,
};

static void
tlv_put(uint8_t *p, uint8_t type, uint32_t len)
{
	uint32_t n = htonl(len);

	p[0] = type;
	memcpy(p + 1, &n, 4);
}

/* Feeds one payload to process_tlv(); the payload sits in a buffer of its
 * exact size, so ASan reports any read past it. */
static void
tlv_feed(const uint8_t *data, size_t len)
{
	struct uds_conn conn;
	uint8_t *payload = malloc(len);

	memcpy(payload, data, len);
	uds_conn_init(&conn, "/nonexistent", "test", &ops);
	conn.handshake_complete = true;
	handshakes = records = disconnects = 0;
	process_tlv(&conn, payload, len);
	uds_conn_free(&conn);
	free(payload);
}

static void
test_tlv_lengths(void)
{
	uint8_t p[32];

	tlv_put(p, UDS_FRAME_HANDSHAKE, 3);
	memcpy(p + 5, "eid", 3);
	tlv_put(p + 8, UDS_FRAME_USP_RECORD, 2);
	tlv_feed(p, 15);
	CHECK(handshakes == 1 && records == 1 && disconnects == 0);

	tlv_put(p, UDS_FRAME_HANDSHAKE, 0xffffffff);
	tlv_feed(p, 8);
	CHECK(handshakes == 0 && disconnects == 1);

	/* 5 + 0xfffffffb wraps to 0 in 32 bits: no progress before the fix */
	tlv_put(p, 9, 0xfffffffb);
	tlv_feed(p, 8);
	CHECK(disconnects == 1);

	tlv_put(p, UDS_FRAME_USP_RECORD, 4);
	tlv_feed(p, 8);
	CHECK(records == 0 && disconnects == 1);

	tlv_put(p, UDS_FRAME_USP_RECORD, 0);
	tlv_feed(p, 4);
	CHECK(records == 0 && disconnects == 0);
}

int
main(void)
{
	test_add_delete_resp();
	test_tlv_lengths();

	if (failures) {
		fprintf(stderr, "%d check(s) failed\n", failures);
		return 1;
	}

	printf("all checks passed\n");
	return 0;
}
