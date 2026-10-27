/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

/*
 * The request and reply exchange that rtnl.c and ethtool.c share.
 */

#include "ubbf.h"

#include <netlink/msg.h>
#include <netlink/netlink.h>
#include <netlink/socket.h>
#include <netlink/handlers.h>

static int
done_cb(struct nl_msg *msg, void *arg)
{
	*(int *)arg = 0;

	return NL_STOP;
}

static int
error_cb(struct sockaddr_nl *nla, struct nlmsgerr *err, void *arg)
{
	*(int *)arg = err->error ? err->error : -1;

	return NL_STOP;
}

/**
 * Sends a request and calls `valid` for each message of the reply. The
 * exchange ends at the ACK of a plain request or at the NLMSG_DONE of a
 * dump, so the next request on the same socket does not read a reply
 * that belongs to this one.
 *
 * @param sock   connected netlink socket
 * @param msg    the request, borrowed
 * @param valid  called for each reply message
 * @param ctx    passed to `valid`
 * @return       false when the send fails or the kernel reports an error
 */
bool
nl_request_run(struct nl_sock *sock, struct nl_msg *msg,
	       int (*valid)(struct nl_msg *, void *), void *ctx)
{
	struct nl_cb *cb;
	int status = 1;

	if (nl_send_auto_complete(sock, msg) < 0)
		return false;

	nl_socket_modify_cb(sock, NL_CB_VALID, NL_CB_CUSTOM, valid, ctx);
	nl_socket_modify_cb(sock, NL_CB_ACK, NL_CB_CUSTOM, done_cb, &status);
	nl_socket_modify_cb(sock, NL_CB_FINISH, NL_CB_CUSTOM, done_cb, &status);
	cb = nl_socket_get_cb(sock);
	nl_cb_err(cb, NL_CB_CUSTOM, error_cb, &status);
	nl_cb_put(cb);

	while (status > 0)
		if (nl_recvmsgs_default(sock) < 0 && status > 0)
			status = -1;

	return status == 0;
}
