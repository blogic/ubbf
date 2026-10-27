/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

/*
 * Link modes, MDI-X state and the IEEE 802.3 MAC and RMON statistics of a
 * port, read with the ethtool generic netlink family
 * (include/uapi/linux/ethtool_netlink.h).
 */

#include "ubbf.h"
#include "bindings.h"

#include <linux/ethtool.h>
#include <linux/ethtool_netlink.h>
#include <netlink/msg.h>
#include <netlink/attr.h>
#include <netlink/netlink.h>
#include <netlink/socket.h>
#include <netlink/handlers.h>
#include <netlink/genl/genl.h>
#include <netlink/genl/ctrl.h>

/* ETHTOOL_STATS_* group ids */
#define STATS_GROUP_ETH_MAC	1
#define STATS_GROUP_RMON	3

static struct nl_sock *ethtool_sock;
static int ethtool_family = -1;

/**
 * The ethtool socket, opened on first use; NULL while the family cannot
 * be resolved, for example on a kernel without ethtool netlink. A failed
 * attempt is tried again on the next call.
 */
static struct nl_sock *
ethtool_socket(void)
{
	if (ethtool_family >= 0)
		return ethtool_sock;

	if (!ethtool_sock) {
		ethtool_sock = nl_socket_alloc();
		if (!ethtool_sock)
			return NULL;

		if (genl_connect(ethtool_sock) != 0) {
			nl_socket_free(ethtool_sock);
			ethtool_sock = NULL;
			return NULL;
		}
	}

	ethtool_family = genl_ctrl_resolve(ethtool_sock, ETHTOOL_GENL_NAME);

	return ethtool_family >= 0 ? ethtool_sock : NULL;
}

/* The attributes point into the reply buffer, which lives only during
 * the callback, so parse() builds the result there. */
struct ethtool_reply {
	uc_vm_t *vm;
	uc_value_t *out;
	void (*parse)(struct ethtool_reply *, struct nlmsghdr *);
};

static int
reply_cb(struct nl_msg *msg, void *arg)
{
	struct ethtool_reply *reply = arg;

	reply->parse(reply, nlmsg_hdr(msg));

	return NL_OK;
}

/**
 * Sends an ethtool request for a device and parses the reply.
 *
 * @param extra  adds the attributes after the header, or NULL
 * @return       false when the device or the request fails
 */
static bool
ethtool_request(uint8_t cmd, uint16_t header_attr, const char *ifname,
		void (*extra)(struct nl_msg *), struct ethtool_reply *reply)
{
	struct nl_sock *sock = ethtool_socket();
	struct nlattr *header;
	struct nl_msg *msg;
	bool ok = false;

	if (!sock)
		return false;

	msg = nlmsg_alloc();
	if (!msg)
		return false;

	if (!genlmsg_put(msg, NL_AUTO_PID, NL_AUTO_SEQ, ethtool_family, 0, 0,
			 cmd, ETHTOOL_GENL_VERSION))
		goto out;

	header = nla_nest_start(msg, header_attr);
	if (!header || nla_put_string(msg, ETHTOOL_A_HEADER_DEV_NAME, ifname))
		goto out;
	nla_nest_end(msg, header);

	if (extra)
		extra(msg);

	ok = nl_request_run(sock, msg, reply_cb, reply);

out:
	nlmsg_free(msg);

	return ok;
}

/**
 * The names of a verbose bitset as a comma-separated list of link modes,
 * the names with "base" only. With value_only set, only the bits
 * with the value flag count: the bitset `ours` of a linkmodes reply has
 * mask=supported and the value flag on the advertised bits, the bitset
 * `peer` has no mask and lists the set bits (net/ethtool/linkmodes.c).
 */
static uc_value_t *
link_modes_new(struct nlattr *bitset, bool value_only)
{
	struct nlattr *tb[ETHTOOL_A_BITSET_MAX + 1];
	struct nlattr *bit[ETHTOOL_A_BITSET_BIT_MAX + 1];
	uc_stringbuf_t *sb = ucv_stringbuf_new();
	struct nlattr *pos;
	const char *name;
	int rem;

	if (bitset && !nla_parse_nested(tb, ETHTOOL_A_BITSET_MAX, bitset, NULL) &&
	    tb[ETHTOOL_A_BITSET_BITS]) {
		nla_for_each_nested(pos, tb[ETHTOOL_A_BITSET_BITS], rem) {
			if (nla_type(pos) != ETHTOOL_A_BITSET_BITS_BIT ||
			    nla_parse_nested(bit, ETHTOOL_A_BITSET_BIT_MAX, pos, NULL) ||
			    !bit[ETHTOOL_A_BITSET_BIT_NAME] ||
			    (value_only && !bit[ETHTOOL_A_BITSET_BIT_VALUE]))
				continue;

			name = nla_get_string(bit[ETHTOOL_A_BITSET_BIT_NAME]);
			if (!strstr(name, "base"))
				continue;

			if (sb->bpos)
				ucv_stringbuf_addstr(sb, ",", 1);
			ucv_stringbuf_addstr(sb, name, strlen(name));
		}
	}

	return ucv_stringbuf_finish(sb);
}

static const char *
mdix_name(uint8_t mdix, bool ctrl)
{
	/* ETH_TP_MDI_*; the state has no AUTO, an unset control autoselects */
	switch (mdix) {
	case ETH_TP_MDI:
		return "MDI";
	case ETH_TP_MDI_X:
		return "MDIX";
	default:
		return ctrl ? "Auto" : "Unknown";
	}
}

static void
linkmodes_parse(struct ethtool_reply *reply, struct nlmsghdr *nlh)
{
	struct nlattr *tb[ETHTOOL_A_LINKMODES_MAX + 1];
	uint8_t duplex;

	if (genlmsg_parse(nlh, 0, tb, ETHTOOL_A_LINKMODES_MAX, NULL))
		return;

	ucv_object_add(reply->out, "SupportedLinkModes", link_modes_new(tb[ETHTOOL_A_LINKMODES_OURS], false));
	ucv_object_add(reply->out, "AdvertisedLinkModes", link_modes_new(tb[ETHTOOL_A_LINKMODES_OURS], true));
	ucv_object_add(reply->out, "LinkPartnerAdvertisedLinkModes", link_modes_new(tb[ETHTOOL_A_LINKMODES_PEER], false));

	if (!tb[ETHTOOL_A_LINKMODES_DUPLEX])
		return;

	duplex = nla_get_u8(tb[ETHTOOL_A_LINKMODES_DUPLEX]);
	ucv_object_add(reply->out, "CurrentDuplexMode", ucv_string_new(
		duplex == DUPLEX_FULL ? "Full" : duplex == DUPLEX_HALF ? "Half" : "Unknown"));
}

static void
linkinfo_parse(struct ethtool_reply *reply, struct nlmsghdr *nlh)
{
	struct nlattr *tb[ETHTOOL_A_LINKINFO_MAX + 1];

	if (genlmsg_parse(nlh, 0, tb, ETHTOOL_A_LINKINFO_MAX, NULL))
		return;

	if (tb[ETHTOOL_A_LINKINFO_TP_MDIX])
		ucv_object_add(reply->out, "CurrentMDIX", ucv_string_new(
			mdix_name(nla_get_u8(tb[ETHTOOL_A_LINKINFO_TP_MDIX]), false)));

	if (tb[ETHTOOL_A_LINKINFO_TP_MDIX_CTRL])
		ucv_object_add(reply->out, "MDIX", ucv_string_new(
			mdix_name(nla_get_u8(tb[ETHTOOL_A_LINKINFO_TP_MDIX_CTRL]), true)));
}

/**
 * Reads the link modes and the MDI-X state of a port.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: device name)
 * @return       `{ SupportedLinkModes, AdvertisedLinkModes,
 *               LinkPartnerAdvertisedLinkModes, CurrentDuplexMode,
 *               CurrentMDIX, MDIX }`, each present when the driver reports
 *               it
 */
uc_value_t *
uc_ubbf_ethtool_properties_get(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *dev = uc_fn_arg(0);
	struct ethtool_reply reply = { .vm = vm, .out = ucv_object_new(vm) };

	if (ucv_type(dev) != UC_STRING)
		return reply.out;

	reply.parse = linkmodes_parse;
	ethtool_request(ETHTOOL_MSG_LINKMODES_GET, ETHTOOL_A_LINKMODES_HEADER,
			ucv_string_get(dev), NULL, &reply);

	reply.parse = linkinfo_parse;
	ethtool_request(ETHTOOL_MSG_LINKINFO_GET, ETHTOOL_A_LINKINFO_HEADER,
			ucv_string_get(dev), NULL, &reply);

	return reply.out;
}

static void
stats_groups_add(struct nl_msg *msg)
{
	static const char *const groups[] = { "eth-mac", "rmon" };
	struct nlattr *set, *bits, *bit;

	set = nla_nest_start(msg, ETHTOOL_A_STATS_GROUPS);
	nla_put_flag(msg, ETHTOOL_A_BITSET_NOMASK);
	bits = nla_nest_start(msg, ETHTOOL_A_BITSET_BITS);

	for (size_t i = 0; i < ARRAY_SIZE(groups); i++) {
		bit = nla_nest_start(msg, ETHTOOL_A_BITSET_BITS_BIT);
		nla_put_string(msg, ETHTOOL_A_BITSET_BIT_NAME, groups[i]);
		nla_nest_end(msg, bit);
	}

	nla_nest_end(msg, bits);
	nla_nest_end(msg, set);
}

static uc_value_t *
u64_new(struct nlattr *attr)
{
	return ucv_uint64_new(nla_get_u64(attr));
}

/**
 * Adds the counters of a statistics group: each counter is a nest of its
 * own with one attribute, whose type is the counter index
 * (stat_put() in net/ethtool/stats.c).
 */
static void
group_stats_add(uc_value_t *stats, struct nlattr *nest)
{
	struct nlattr *pos;
	char key[12];
	int rem;

	nla_for_each_nested(pos, nest, rem) {
		if (nla_len(pos) != sizeof(uint64_t))
			continue;

		snprintf(key, sizeof(key), "%d", nla_type(pos));
		ucv_object_add(stats, key, u64_new(pos));
	}
}

static void
group_hist_add(uc_vm_t *vm, uc_value_t *hist, struct nlattr *nest)
{
	struct nlattr *tb[ETHTOOL_A_STATS_GRP_MAX + 1];
	uc_value_t *bucket;

	if (nla_parse_nested(tb, ETHTOOL_A_STATS_GRP_MAX, nest, NULL) ||
	    !tb[ETHTOOL_A_STATS_GRP_HIST_BKT_LOW] || !tb[ETHTOOL_A_STATS_GRP_HIST_BKT_HI] ||
	    !tb[ETHTOOL_A_STATS_GRP_HIST_VAL])
		return;

	bucket = ucv_object_new(vm);
	ucv_object_add(bucket, "low", ucv_int64_new(nla_get_u32(tb[ETHTOOL_A_STATS_GRP_HIST_BKT_LOW])));
	ucv_object_add(bucket, "high", ucv_int64_new(nla_get_u32(tb[ETHTOOL_A_STATS_GRP_HIST_BKT_HI])));
	ucv_object_add(bucket, "value", u64_new(tb[ETHTOOL_A_STATS_GRP_HIST_VAL]));
	ucv_array_push(hist, bucket);
}

static void
stats_group_parse(struct ethtool_reply *reply, struct nlattr *grp)
{
	uc_value_t *stats = NULL, *hist = NULL;
	struct nlattr *pos, *id = NULL;
	int rem;

	nla_for_each_nested(pos, grp, rem)
		if (nla_type(pos) == ETHTOOL_A_STATS_GRP_ID)
			id = pos;

	if (!id)
		return;

	switch (nla_get_u32(id)) {
	case STATS_GROUP_ETH_MAC:
		stats = ucv_object_new(reply->vm);
		ucv_object_add(reply->out, "mac", stats);
		break;

	case STATS_GROUP_RMON:
		stats = ucv_object_new(reply->vm);
		hist = ucv_array_new(reply->vm);
		ucv_object_add(reply->out, "rmon", stats);
		ucv_object_add(reply->out, "hist_rx", hist);
		break;

	default:
		return;
	}

	nla_for_each_nested(pos, grp, rem) {
		if (nla_type(pos) == ETHTOOL_A_STATS_GRP_STAT)
			group_stats_add(stats, pos);
		else if (hist && nla_type(pos) == ETHTOOL_A_STATS_GRP_HIST_RX)
			group_hist_add(reply->vm, hist, pos);
	}
}

static void
stats_parse(struct ethtool_reply *reply, struct nlmsghdr *nlh)
{
	struct genlmsghdr *gnlh = nlmsg_data(nlh);
	struct nlattr *pos;
	int rem;

	nla_for_each_attr(pos, genlmsg_attrdata(gnlh, 0), genlmsg_attrlen(gnlh, 0), rem)
		if (nla_type(pos) == ETHTOOL_A_STATS_GRP)
			stats_group_parse(reply, pos);
}

/**
 * Reads the IEEE 802.3 MAC and the RMON statistics of a port. A counter
 * that the driver does not fill is absent (ETHTOOL_STAT_NOT_SET in
 * net/ethtool/stats.c).
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: device name)
 * @return       `{ mac, rmon, hist_rx }`: each counter keyed by its
 *               ETHTOOL_A_STATS_ETH_MAC_* or ETHTOOL_A_STATS_RMON_* index,
 *               and hist_rx, the receive buckets `{ low, high, value }`;
 *               null when the request fails
 */
uc_value_t *
uc_ubbf_ethtool_stats_get(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *dev = uc_fn_arg(0);
	struct ethtool_reply reply = { .vm = vm, .parse = stats_parse };

	if (ucv_type(dev) != UC_STRING || !*ucv_string_get(dev))
		return NULL;

	reply.out = ucv_object_new(vm);
	ucv_object_add(reply.out, "mac", ucv_object_new(vm));
	ucv_object_add(reply.out, "rmon", ucv_object_new(vm));
	ucv_object_add(reply.out, "hist_rx", ucv_array_new(vm));

	if (!ethtool_request(ETHTOOL_MSG_STATS_GET, ETHTOOL_A_STATS_HEADER,
			     ucv_string_get(dev), stats_groups_add, &reply)) {
		ucv_put(reply.out);
		return NULL;
	}

	return reply.out;
}
