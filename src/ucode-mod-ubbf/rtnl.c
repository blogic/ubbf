/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

/*
 * Kernel state that netifd does not report, read with route netlink
 * dumps: the IPv6 link-local addresses and the on-link prefixes learned
 * from Router Advertisements, the IPv6 neighbours and the bridge FDB.
 */

#include "ubbf.h"
#include "bindings.h"

#include <arpa/inet.h>
#include <net/if.h>
#include <linux/rtnetlink.h>
#include <netlink/msg.h>
#include <netlink/attr.h>
#include <netlink/netlink.h>
#include <netlink/socket.h>
#include <netlink/handlers.h>

/* Linux routing protocol identifier for kernel-installed RA on-link prefixes */
#define RTPROT_RA	9

/* rta_expires counts USER_HZ ticks, 100 per second as iproute2 reads it */
#define USER_HZ		100

/* The neighbour states that `ip neigh show` lists by default, less
 * INCOMPLETE and FAILED, which have no usable link-layer address
 * (do_show_or_flush() in iproute2 ip/ipneigh.c). */
#define NUD_LISTED	(NUD_REACHABLE | NUD_STALE | NUD_DELAY | NUD_PROBE | NUD_PERMANENT)

struct rtnl_dump {
	uc_vm_t *vm;
	uc_value_t *out;
	unsigned int ifindex;
};

/**
 * Sends a dump request with the given family header and calls cb for each
 * message of the reply.
 *
 * @return  false when the netlink socket or the request fails
 */
static bool
rtnl_dump(int type, void *hdr, size_t hdrlen, nl_recvmsg_msg_cb_t cb, void *ctx)
{
	struct nl_sock *sock = nl_socket_alloc();
	struct nl_msg *msg = NULL;
	bool ok = false;

	if (!sock || nl_connect(sock, NETLINK_ROUTE))
		goto out;

	msg = nlmsg_alloc_simple(type, NLM_F_DUMP);
	if (!msg || nlmsg_append(msg, hdr, hdrlen, NLMSG_ALIGNTO))
		goto out;

	ok = nl_request_run(sock, msg, cb, ctx);

out:
	nlmsg_free(msg);
	nl_socket_free(sock);

	return ok;
}

static uc_value_t *
ipv6_string_new(const void *addr)
{
	char buf[INET6_ADDRSTRLEN];

	return ucv_string_new(inet_ntop(AF_INET6, addr, buf, sizeof(buf)));
}

static int
link_local_cb(struct nl_msg *msg, void *arg)
{
	struct nlmsghdr *nlh = nlmsg_hdr(msg);
	struct ifaddrmsg *ifa = nlmsg_data(nlh);
	struct rtnl_dump *dump = arg;
	struct nlattr *tb[IFA_MAX + 1];
	uc_value_t *row;

	if (nlmsg_parse(nlh, sizeof(*ifa), tb, IFA_MAX, NULL) ||
	    ifa->ifa_family != AF_INET6 || ifa->ifa_scope != RT_SCOPE_LINK ||
	    ifa->ifa_index != dump->ifindex || !tb[IFA_ADDRESS] ||
	    nla_len(tb[IFA_ADDRESS]) != 16)
		return NL_OK;

	row = ucv_object_new(dump->vm);
	ucv_object_add(row, "address", ipv6_string_new(nla_data(tb[IFA_ADDRESS])));
	ucv_object_add(row, "mask", ucv_int64_new(ifa->ifa_prefixlen));
	ucv_array_push(dump->out, row);

	return NL_OK;
}

/**
 * Lists the kernel IPv6 link-local addresses of a device.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: device name)
 * @return       array of `{ address, mask }`, for ipv6_addr_to_object()
 *               with the "forever" flag; empty on failure
 */
uc_value_t *
uc_ubbf_link_local_addresses_get(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *dev = uc_fn_arg(0);
	struct rtnl_dump dump = { .vm = vm, .out = ucv_array_new(vm) };
	struct ifaddrmsg ifa = { .ifa_family = AF_INET6 };

	if (ucv_type(dev) != UC_STRING)
		return dump.out;

	dump.ifindex = if_nametoindex(ucv_string_get(dev));
	if (dump.ifindex)
		rtnl_dump(RTM_GETADDR, &ifa, sizeof(ifa), link_local_cb, &dump);

	return dump.out;
}

/**
 * The lifetime of an RA prefix route in seconds, at least 1, as a number
 * with a fraction when the ticks are not whole seconds.
 */
static uc_value_t *
ra_lifetime_new(int32_t ticks)
{
	if (ticks < USER_HZ)
		return ucv_int64_new(1);

	if (ticks % USER_HZ)
		return ucv_double_new((double)ticks / USER_HZ);

	return ucv_int64_new(ticks / USER_HZ);
}

static int
ra_prefix_cb(struct nl_msg *msg, void *arg)
{
	struct nlmsghdr *nlh = nlmsg_hdr(msg);
	struct rtmsg *rtm = nlmsg_data(nlh);
	struct rtnl_dump *dump = arg;
	struct nlattr *tb[RTA_MAX + 1];
	struct rta_cacheinfo *ci;
	uc_value_t *row;

	if (nlmsg_parse(nlh, sizeof(*rtm), tb, RTA_MAX, NULL) ||
	    rtm->rtm_family != AF_INET6 || rtm->rtm_protocol != RTPROT_RA ||
	    !tb[RTA_OIF] || nla_get_u32(tb[RTA_OIF]) != dump->ifindex ||
	    !tb[RTA_DST] || nla_len(tb[RTA_DST]) != 16)
		return NL_OK;

	row = ucv_object_new(dump->vm);
	ucv_object_add(row, "address", ipv6_string_new(nla_data(tb[RTA_DST])));
	ucv_object_add(row, "mask", ucv_int64_new(rtm->rtm_dst_len));

	/* rta_expires 0 is a route without expiry, an infinite lifetime */
	ci = tb[RTA_CACHEINFO] && nla_len(tb[RTA_CACHEINFO]) >= (int)sizeof(*ci)
		? nla_data(tb[RTA_CACHEINFO]) : NULL;
	if (ci && ci->rta_expires > 0) {
		ucv_object_add(row, "preferred", ra_lifetime_new(ci->rta_expires));
		ucv_object_add(row, "valid", ra_lifetime_new(ci->rta_expires));
	}

	ucv_array_push(dump->out, row);

	return NL_OK;
}

/**
 * The RA prefixes of a device, see ra_prefixes_get().
 *
 * @param vm   ucode VM context
 * @param dev  device name value
 * @return     new array, empty on failure
 */
uc_value_t *
ra_prefixes_new(uc_vm_t *vm, uc_value_t *dev)
{
	struct rtnl_dump dump = { .vm = vm, .out = ucv_array_new(vm) };
	struct rtmsg rtm = { .rtm_family = AF_INET6 };

	if (ucv_type(dev) != UC_STRING)
		return dump.out;

	dump.ifindex = if_nametoindex(ucv_string_get(dev));
	if (dump.ifindex)
		rtnl_dump(RTM_GETROUTE, &rtm, sizeof(rtm), ra_prefix_cb, &dump);

	return dump.out;
}

/**
 * Lists the IPv6 on-link prefixes learned from Router Advertisements on a
 * device: the prefix routes that the kernel installs with protocol
 * RTPROT_RA for a Prefix Information option with L=1.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: device name)
 * @return       array of `{ address, mask, preferred?, valid? }` in the
 *               netifd prefix shape, for ipv6_prefix_to_object(); empty on
 *               failure
 */
uc_value_t *
uc_ubbf_ra_prefixes_get(uc_vm_t *vm, size_t nargs)
{
	return ra_prefixes_new(vm, uc_fn_arg(0));
}

static void
mac_format(const uint8_t *mac, char *buf, size_t len)
{
	snprintf(buf, len, "%02X:%02X:%02X:%02X:%02X:%02X",
		 mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
}

/* 01:00:5e is the IPv4 multicast prefix (RFC 1112), 33:33 the IPv6 one
 * (RFC 2464) */
static bool
mac_is_ip_multicast(const uint8_t *mac)
{
	return (mac[0] == 0x01 && mac[1] == 0x00 && mac[2] == 0x5e) ||
	       (mac[0] == 0x33 && mac[1] == 0x33);
}

static int
fdb_cb(struct nl_msg *msg, void *arg)
{
	struct nlmsghdr *nlh = nlmsg_hdr(msg);
	struct ndmsg *ndm = nlmsg_data(nlh);
	struct rtnl_dump *dump = arg;
	struct nlattr *tb[NDA_MAX + 1];
	char dev[IF_NAMESIZE], mac[18];
	const uint8_t *lladdr;

	if (nlmsg_parse(nlh, sizeof(*ndm), tb, NDA_MAX, NULL) ||
	    ndm->ndm_family != AF_BRIDGE || (ndm->ndm_state & NUD_PERMANENT) ||
	    !tb[NDA_LLADDR] || nla_len(tb[NDA_LLADDR]) != 6 ||
	    !if_indextoname(ndm->ndm_ifindex, dev))
		return NL_OK;

	lladdr = nla_data(tb[NDA_LLADDR]);
	if (mac_is_ip_multicast(lladdr))
		return NL_OK;

	mac_format(lladdr, mac, sizeof(mac));
	ucv_object_add(dump->out, mac, ucv_string_new(dev));

	return NL_OK;
}

/**
 * Returns the bridge forwarding database as a MAC-to-port map, the entries
 * that `bridge fdb show` lists less the permanent ones and the IPv4 and
 * IPv6 multicast MACs.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (none expected)
 * @return       object keyed by uppercase MAC mapping to the port name;
 *               empty on failure
 */
uc_value_t *
uc_ubbf_bridge_fdb_parse(uc_vm_t *vm, size_t nargs)
{
	struct rtnl_dump dump = { .vm = vm, .out = ucv_object_new(vm) };
	struct ndmsg ndm = { .ndm_family = AF_BRIDGE };

	rtnl_dump(RTM_GETNEIGH, &ndm, sizeof(ndm), fdb_cb, &dump);

	return dump.out;
}

static bool
neigh_listed(const struct ndmsg *ndm)
{
	if (ndm->ndm_state & NUD_LISTED)
		return true;

	return (ndm->ndm_flags & NTF_EXT_LEARNED) &&
	       !(ndm->ndm_state & (NUD_INCOMPLETE | NUD_FAILED));
}

static void
string_push_unique(uc_value_t *arr, const char *s)
{
	uc_value_t *v;

	for (size_t i = 0; i < ucv_array_length(arr); i++) {
		v = ucv_array_get(arr, i);
		if (ucv_type(v) == UC_STRING && !strcmp(ucv_string_get(v), s))
			return;
	}

	ucv_array_push(arr, ucv_string_new(s));
}

static int
ipv6_neigh_cb(struct nl_msg *msg, void *arg)
{
	static const uint8_t zero[6];
	struct nlmsghdr *nlh = nlmsg_hdr(msg);
	struct ndmsg *ndm = nlmsg_data(nlh);
	struct rtnl_dump *dump = arg;
	struct nlattr *tb[NDA_MAX + 1];
	char addr[INET6_ADDRSTRLEN], mac[18];
	uc_value_t *addrs;

	if (nlmsg_parse(nlh, sizeof(*ndm), tb, NDA_MAX, NULL) ||
	    ndm->ndm_family != AF_INET6 || !neigh_listed(ndm) ||
	    !tb[NDA_DST] || nla_len(tb[NDA_DST]) != 16 ||
	    !tb[NDA_LLADDR] || nla_len(tb[NDA_LLADDR]) != 6)
		return NL_OK;

	/* every IPv6 host has a link-local address, which says nothing about
	 * the IPv6 connectivity of the host */
	if (IN6_IS_ADDR_LINKLOCAL(nla_data(tb[NDA_DST])) ||
	    !memcmp(nla_data(tb[NDA_LLADDR]), zero, sizeof(zero)))
		return NL_OK;

	inet_ntop(AF_INET6, nla_data(tb[NDA_DST]), addr, sizeof(addr));
	mac_format(nla_data(tb[NDA_LLADDR]), mac, sizeof(mac));

	addrs = ucv_object_get(dump->out, mac, NULL);
	if (!addrs) {
		addrs = ucv_array_new(dump->vm);
		ucv_object_add(dump->out, mac, addrs);
	}

	string_push_unique(addrs, addr);

	return NL_OK;
}

/**
 * Returns the IPv6 neighbour table as a MAC-to-address-list map. The
 * entries without a resolved link-layer address, the link-local addresses
 * and the all-zero MAC are skipped; an address on more than one device
 * shows once.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (none expected)
 * @return       object keyed by uppercase MAC mapping to an array of IPv6
 *               addresses; empty on failure
 */
uc_value_t *
uc_ubbf_ipv6_neigh_parse(uc_vm_t *vm, size_t nargs)
{
	struct rtnl_dump dump = { .vm = vm, .out = ucv_object_new(vm) };
	struct ndmsg ndm = { .ndm_family = AF_INET6 };

	rtnl_dump(RTM_GETNEIGH, &ndm, sizeof(ndm), ipv6_neigh_cb, &dump);

	return dump.out;
}
