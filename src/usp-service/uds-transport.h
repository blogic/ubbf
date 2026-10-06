#ifndef UDS_TRANSPORT_H
#define UDS_TRANSPORT_H

#include <stdint.h>
#include <stdbool.h>
#include <libubox/uloop.h>
#include <libubox/list.h>

#define UDS_SYNC_BYTES		"\x5f\x55\x53\x50"
#define UDS_SYNC_LEN		4
#define UDS_LENGTH_LEN		4
#define UDS_HEADER_LEN		(UDS_SYNC_LEN + UDS_LENGTH_LEN)
#define UDS_TLV_HDR_LEN	5

#define UDS_HANDSHAKE_TIMEOUT	30
#define UDS_RECONNECT_MIN	1
#define UDS_RECONNECT_MAX	5

enum uds_frame_type {
	UDS_FRAME_HANDSHAKE	= 1,
	UDS_FRAME_ERROR		= 2,
	UDS_FRAME_USP_RECORD	= 3,
};

enum uds_rx_state {
	UDS_RX_SYNC,
	UDS_RX_LENGTH,
	UDS_RX_PAYLOAD,
};

struct uds_tx_item {
	struct list_head list;
	uint8_t *buf;
	int len;
};

struct uds_conn;

struct uds_ops {
	void (*on_handshake)(struct uds_conn *conn, const char *endpoint_id);
	void (*on_record)(struct uds_conn *conn, const uint8_t *data, size_t len);
	void (*on_error)(struct uds_conn *conn, const char *msg);
	void (*on_disconnect)(struct uds_conn *conn);
};

struct uds_conn {
	int fd;
	struct uloop_fd ufd;
	struct uloop_timeout reconnect_timer;
	struct uloop_timeout handshake_timer;

	char *socket_path;
	char *endpoint_id;
	char *peer_endpoint_id;
	bool handshake_complete;

	enum uds_rx_state rx_state;
	int sync_pos;
	int len_pos;
	uint8_t len_bytes[UDS_LENGTH_LEN];
	int payload_len;
	int payload_pos;
	uint8_t *rx_buf;

	struct list_head tx_queue;
	uint8_t *tx_buf;
	int tx_buf_len;
	int tx_pos;

	const struct uds_ops *ops;
	void *priv;
};

int uds_conn_init(struct uds_conn *conn, const char *path,
		  const char *endpoint_id, const struct uds_ops *ops);
void uds_conn_free(struct uds_conn *conn);
int uds_connect(struct uds_conn *conn);
void uds_disconnect(struct uds_conn *conn);
int uds_queue_frame(struct uds_conn *conn, enum uds_frame_type type,
		    const uint8_t *data, size_t len);
int uds_queue_handshake(struct uds_conn *conn);
int uds_queue_error(struct uds_conn *conn, const char *msg);
int uds_queue_record(struct uds_conn *conn, const uint8_t *data, size_t len);

#endif
