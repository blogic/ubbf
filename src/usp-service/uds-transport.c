#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <fcntl.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <arpa/inet.h>

#include "uds-transport.h"

static void uds_fd_cb(struct uloop_fd *ufd, unsigned int events);
static void uds_reconnect_cb(struct uloop_timeout *t);
static void uds_handshake_timeout_cb(struct uloop_timeout *t);

static void
tx_queue_flush(struct uds_conn *conn)
{
	struct uds_tx_item *item, *tmp;

	list_for_each_entry_safe(item, tmp, &conn->tx_queue, list) {
		list_del(&item->list);
		free(item->buf);
		free(item);
	}

	free(conn->tx_buf);
	conn->tx_buf = NULL;
	conn->tx_buf_len = 0;
	conn->tx_pos = 0;
}

static void
rx_state_reset(struct uds_conn *conn)
{
	conn->rx_state = UDS_RX_SYNC;
	conn->sync_pos = 0;
	conn->len_pos = 0;
	conn->payload_len = 0;
	conn->payload_pos = 0;
	free(conn->rx_buf);
	conn->rx_buf = NULL;
}

static void
schedule_reconnect(struct uds_conn *conn)
{
	int delay;

	if (conn->reconnect_timer.pending)
		return;

	delay = UDS_RECONNECT_MIN +
		(rand() % (UDS_RECONNECT_MAX - UDS_RECONNECT_MIN + 1));
	uloop_timeout_set(&conn->reconnect_timer, delay * 1000);
}

void
uds_disconnect(struct uds_conn *conn)
{
	uloop_timeout_cancel(&conn->handshake_timer);

	if (conn->ufd.registered)
		uloop_fd_delete(&conn->ufd);

	if (conn->fd >= 0) {
		close(conn->fd);
		conn->fd = -1;
	}

	conn->handshake_complete = false;
	free(conn->peer_endpoint_id);
	conn->peer_endpoint_id = NULL;

	tx_queue_flush(conn);
	rx_state_reset(conn);
}

static void
handle_disconnect(struct uds_conn *conn, bool reconnect)
{
	uds_disconnect(conn);

	if (conn->ops && conn->ops->on_disconnect)
		conn->ops->on_disconnect(conn);

	if (reconnect)
		schedule_reconnect(conn);
}

static int
socket_set_nonblock(int fd)
{
	int flags = fcntl(fd, F_GETFL, 0);

	if (flags < 0)
		return -1;

	return fcntl(fd, F_SETFL, flags | O_NONBLOCK);
}

int
uds_connect(struct uds_conn *conn)
{
	struct sockaddr_un addr = { .sun_family = AF_UNIX };
	int fd;

	uds_disconnect(conn);

	fd = socket(AF_UNIX, SOCK_STREAM, 0);
	if (fd < 0)
		return -errno;

	if (socket_set_nonblock(fd) < 0)
		goto err_close;

	strncpy(addr.sun_path, conn->socket_path, sizeof(addr.sun_path) - 1);

	if (connect(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0 &&
	    errno != EINPROGRESS)
		goto err_close;

	conn->fd = fd;
	conn->ufd.fd = fd;
	conn->ufd.cb = uds_fd_cb;
	uloop_fd_add(&conn->ufd, ULOOP_READ);

	uds_queue_handshake(conn);

	conn->handshake_timer.cb = uds_handshake_timeout_cb;
	uloop_timeout_set(&conn->handshake_timer, UDS_HANDSHAKE_TIMEOUT * 1000);

	return 0;

err_close:
	close(fd);
	return -errno;
}

int
uds_conn_init(struct uds_conn *conn, const char *path,
	      const char *endpoint_id, const struct uds_ops *ops)
{
	memset(conn, 0, sizeof(*conn));

	conn->fd = -1;
	conn->socket_path = strdup(path);
	conn->endpoint_id = strdup(endpoint_id);
	conn->ops = ops;
	INIT_LIST_HEAD(&conn->tx_queue);

	conn->reconnect_timer.cb = uds_reconnect_cb;

	if (!conn->socket_path || !conn->endpoint_id) {
		uds_conn_free(conn);
		return -ENOMEM;
	}

	return 0;
}

void
uds_conn_free(struct uds_conn *conn)
{
	uds_disconnect(conn);
	uloop_timeout_cancel(&conn->reconnect_timer);
	free(conn->socket_path);
	free(conn->endpoint_id);
	conn->socket_path = NULL;
	conn->endpoint_id = NULL;
}

static uint8_t *
frame_build(enum uds_frame_type type, const uint8_t *data, size_t data_len,
	    int *out_len)
{
	int tlv_len = UDS_TLV_HDR_LEN + data_len;
	int frame_len = UDS_HEADER_LEN + tlv_len;
	uint8_t *buf, *p;
	uint32_t net_val;

	buf = malloc(frame_len);
	if (!buf)
		return NULL;

	p = buf;

	memcpy(p, UDS_SYNC_BYTES, UDS_SYNC_LEN);
	p += UDS_SYNC_LEN;

	net_val = htonl(tlv_len);
	memcpy(p, &net_val, UDS_LENGTH_LEN);
	p += UDS_LENGTH_LEN;

	*p++ = (uint8_t)type;

	net_val = htonl(data_len);
	memcpy(p, &net_val, UDS_LENGTH_LEN);
	p += UDS_LENGTH_LEN;

	if (data_len > 0)
		memcpy(p, data, data_len);

	*out_len = frame_len;
	return buf;
}

int
uds_queue_frame(struct uds_conn *conn, enum uds_frame_type type,
		const uint8_t *data, size_t len)
{
	struct uds_tx_item *item;
	int frame_len;
	uint8_t *frame;

	frame = frame_build(type, data, len, &frame_len);
	if (!frame)
		return -ENOMEM;

	item = calloc(1, sizeof(*item));
	if (!item) {
		free(frame);
		return -ENOMEM;
	}

	item->buf = frame;
	item->len = frame_len;
	list_add_tail(&item->list, &conn->tx_queue);

	if (conn->ufd.registered)
		uloop_fd_add(&conn->ufd, ULOOP_READ | ULOOP_WRITE);

	return 0;
}

int
uds_queue_handshake(struct uds_conn *conn)
{
	return uds_queue_frame(conn, UDS_FRAME_HANDSHAKE,
			       (const uint8_t *)conn->endpoint_id,
			       strlen(conn->endpoint_id));
}

int
uds_queue_error(struct uds_conn *conn, const char *msg)
{
	return uds_queue_frame(conn, UDS_FRAME_ERROR,
			       (const uint8_t *)msg, strlen(msg));
}

int
uds_queue_record(struct uds_conn *conn, const uint8_t *data, size_t len)
{
	return uds_queue_frame(conn, UDS_FRAME_USP_RECORD, data, len);
}

static void
process_tlv(struct uds_conn *conn, const uint8_t *payload, int payload_len)
{
	int offset = 0;

	while (offset + UDS_TLV_HDR_LEN <= payload_len) {
		uint8_t type = payload[offset];
		uint32_t val_len;

		memcpy(&val_len, &payload[offset + 1], 4);
		val_len = ntohl(val_len);

		if (offset + UDS_TLV_HDR_LEN + val_len > (unsigned)payload_len)
			break;

		const uint8_t *val = &payload[offset + UDS_TLV_HDR_LEN];

		switch (type) {
		case UDS_FRAME_HANDSHAKE: {
			char *eid = strndup((const char *)val, val_len);

			if (!eid)
				break;

			free(conn->peer_endpoint_id);
			conn->peer_endpoint_id = eid;
			conn->handshake_complete = true;
			uloop_timeout_cancel(&conn->handshake_timer);

			if (conn->ops && conn->ops->on_handshake)
				conn->ops->on_handshake(conn, eid);
			break;
		}
		case UDS_FRAME_ERROR: {
			char *msg = strndup((const char *)val, val_len);

			if (conn->ops && conn->ops->on_error)
				conn->ops->on_error(conn, msg ? msg : "unknown");
			free(msg);
			handle_disconnect(conn, true);
			return;
		}
		case UDS_FRAME_USP_RECORD:
			if (!conn->handshake_complete)
				break;

			if (conn->ops && conn->ops->on_record)
				conn->ops->on_record(conn, val, val_len);
			break;
		}

		offset += UDS_TLV_HDR_LEN + val_len;
	}
}

static void
rx_process(struct uds_conn *conn)
{
	uint8_t buf[4096];
	ssize_t n;

	n = recv(conn->fd, buf, sizeof(buf), 0);
	if (n <= 0) {
		handle_disconnect(conn, true);
		return;
	}

	for (ssize_t i = 0; i < n; i++) {
		switch (conn->rx_state) {
		case UDS_RX_SYNC:
			if (buf[i] == UDS_SYNC_BYTES[conn->sync_pos]) {
				conn->sync_pos++;
				if (conn->sync_pos == UDS_SYNC_LEN) {
					conn->rx_state = UDS_RX_LENGTH;
					conn->len_pos = 0;
				}
			} else {
				handle_disconnect(conn, true);
				return;
			}
			break;

		case UDS_RX_LENGTH:
			conn->len_bytes[conn->len_pos++] = buf[i];
			if (conn->len_pos == UDS_LENGTH_LEN) {
				uint32_t plen;

				memcpy(&plen, conn->len_bytes, 4);
				conn->payload_len = ntohl(plen);

				if (conn->payload_len < UDS_TLV_HDR_LEN ||
				    conn->payload_len > 1024 * 1024) {
					handle_disconnect(conn, true);
					return;
				}

				conn->rx_buf = malloc(conn->payload_len);
				if (!conn->rx_buf) {
					handle_disconnect(conn, true);
					return;
				}
				conn->payload_pos = 0;
				conn->rx_state = UDS_RX_PAYLOAD;
			}
			break;

		case UDS_RX_PAYLOAD: {
			int remaining = conn->payload_len - conn->payload_pos;
			int avail = n - i;
			int copy = (avail < remaining) ? avail : remaining;

			memcpy(conn->rx_buf + conn->payload_pos, &buf[i], copy);
			conn->payload_pos += copy;
			i += copy - 1;

			if (conn->payload_pos == conn->payload_len) {
				process_tlv(conn, conn->rx_buf, conn->payload_len);

				free(conn->rx_buf);
				conn->rx_buf = NULL;
				conn->rx_state = UDS_RX_SYNC;
				conn->sync_pos = 0;
				conn->len_pos = 0;

				if (conn->fd < 0)
					return;
			}
			break;
		}
		}
	}
}

static void
tx_process(struct uds_conn *conn)
{
	ssize_t sent;

	if (!conn->tx_buf) {
		struct uds_tx_item *item;

		if (list_empty(&conn->tx_queue)) {
			uloop_fd_add(&conn->ufd, ULOOP_READ);
			return;
		}

		item = list_first_entry(&conn->tx_queue,
					struct uds_tx_item, list);
		list_del(&item->list);

		conn->tx_buf = item->buf;
		conn->tx_buf_len = item->len;
		conn->tx_pos = 0;
		free(item);
	}

	sent = send(conn->fd, conn->tx_buf + conn->tx_pos,
		    conn->tx_buf_len - conn->tx_pos, MSG_NOSIGNAL);
	if (sent < 0) {
		if (errno == EAGAIN || errno == EWOULDBLOCK)
			return;
		handle_disconnect(conn, true);
		return;
	}

	conn->tx_pos += sent;
	if (conn->tx_pos == conn->tx_buf_len) {
		free(conn->tx_buf);
		conn->tx_buf = NULL;
		conn->tx_buf_len = 0;
		conn->tx_pos = 0;
	}
}

static void
uds_fd_cb(struct uloop_fd *ufd, unsigned int events)
{
	struct uds_conn *conn = container_of(ufd, struct uds_conn, ufd);

	if (events & ULOOP_READ)
		rx_process(conn);

	if (conn->fd >= 0 && (events & ULOOP_WRITE))
		tx_process(conn);
}

static void
uds_reconnect_cb(struct uloop_timeout *t)
{
	struct uds_conn *conn = container_of(t, struct uds_conn, reconnect_timer);

	if (uds_connect(conn) < 0)
		schedule_reconnect(conn);
}

static void
uds_handshake_timeout_cb(struct uloop_timeout *t)
{
	struct uds_conn *conn = container_of(t, struct uds_conn, handshake_timer);

	handle_disconnect(conn, true);
}
