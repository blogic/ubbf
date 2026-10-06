// SPDX-License-Identifier: GPL-2.0-or-later
/*
 * PPPoE passthrough relay (eBPF TC ingress classifier).
 *
 * Two SCHED_CLS programs attached at TC ingress:
 *   pppoe_lan_in - ingress on LAN bridge, frames originating from LAN clients
 *   pppoe_wan_in - ingress on WAN ethernet, frames arriving from the BRAS
 *
 * Sessions are admitted at PADS (server-Success) time and recorded in a
 * shared HASH map keyed by {LAN client MAC, PPPoE session ID}. A PADS is
 * admitted only for a client that sent a PADR within PADR_WINDOW_NS, and
 * never with session ID 0, which RFC 2516 uses for an error PADS. Session
 * frames whose key isn't in the map are dropped (LAN side) or passed up
 * to the host stack (WAN side - that's the RG's own session). MaxSessions
 * is enforced against session_count in the config map; once the cap is
 * reached new PADS frames are dropped at the kernel.
 *
 * Userspace expires idle sessions and rewrites session_count from the
 * number of map entries on every poll, so the count cannot drift.
 */
#define KBUILD_MODNAME "pppoe-relay"
#include <uapi/linux/bpf.h>
#include <uapi/linux/if_ether.h>
#include <uapi/linux/pkt_cls.h>
#include <bpf/bpf_helpers.h>
#include <bpf/bpf_endian.h>

#define PPPOE_DISC	0x8863
#define PPPOE_SESS	0x8864

#define PADI_CODE	0x09
#define PADO_CODE	0x07
#define PADR_CODE	0x19
#define PADS_CODE	0x65
#define PADT_CODE	0xa7

#define ETH_P_8021Q	0x8100

#define PADR_WINDOW_NS	(10ULL * 1000000000ULL)

struct pppoe_hdr {
	__u8 ver_type;
	__u8 code;
	__be16 session_id;
	__be16 length;
} __attribute__((packed));

struct vlan_hdr {
	__be16 tci;
	__be16 inner_proto;
} __attribute__((packed));

struct session_key {
	__u8 mac[6];
	__be16 session_id;
} __attribute__((packed));

struct session_state {
	__u64 start_ns;
	__u64 last_ns;
};

struct relay_config {
	__u32 lan_ifindex;
	__u32 wan_ifindex;
	__u32 max_sessions;
	__u32 session_count;
	__u32 enabled;
	__u8 wan_mac[6];
	__u8 _pad[2];
} __attribute__((packed));

static __always_inline int mac_equal(const __u8 *a, const __u8 *b)
{
	return a[0] == b[0] && a[1] == b[1] && a[2] == b[2] &&
	       a[3] == b[3] && a[4] == b[4] && a[5] == b[5];
}

struct {
	__uint(type, BPF_MAP_TYPE_HASH);
	__type(key, struct session_key);
	__type(value, struct session_state);
	__uint(max_entries, 256);
	__uint(map_flags, BPF_F_NO_PREALLOC);
} sessions SEC(".maps");

struct {
	__uint(type, BPF_MAP_TYPE_ARRAY);
	__type(key, __u32);
	__type(value, struct relay_config);
	__uint(max_entries, 1);
} config SEC(".maps");

struct mac_key {
	__u8 mac[6];
} __attribute__((packed));

/* LAN client MAC -> time of its last PADR. */
struct {
	__uint(type, BPF_MAP_TYPE_LRU_HASH);
	__type(key, struct mac_key);
	__type(value, __u64);
	__uint(max_entries, 256);
} padr_seen SEC(".maps");

static __always_inline struct relay_config *cfg_get(void)
{
	__u32 k = 0;
	return bpf_map_lookup_elem(&config, &k);
}

/*
 * Takes a slot for a new session; false when MaxSessions are open. The add
 * and the check are one atomic step, so parallel PADS frames cannot both
 * take the last slot.
 */
static __always_inline int session_slot_take(struct relay_config *cfg)
{
	if (__sync_fetch_and_add(&cfg->session_count, 1) < cfg->max_sessions)
		return 1;

	__sync_fetch_and_sub(&cfg->session_count, 1);
	return 0;
}

/*
 * Gives a slot back without going below zero: userspace rewrites the count
 * from the map, so it can be lower than the slots that BPF still holds.
 */
static __always_inline void session_slot_put(struct relay_config *cfg)
{
	for (int i = 0; i < 4; i++) {
		__u32 n = cfg->session_count;

		if (!n || __sync_val_compare_and_swap(&cfg->session_count, n, n - 1) == n)
			return;
	}
}

static __always_inline void session_remove(struct relay_config *cfg,
					   struct session_key *key)
{
	if (bpf_map_delete_elem(&sessions, key) == 0)
		session_slot_put(cfg);
}

/* A PADS may open a session only for a client that asked for one. */
static __always_inline int padr_recent(struct mac_key *mk, __u64 now)
{
	__u64 *seen = bpf_map_lookup_elem(&padr_seen, mk);

	return seen && now - *seen < PADR_WINDOW_NS;
}

/*
 * Locates the PPPoE header in the frame, transparently stepping over an
 * optional inline 802.1Q VLAN tag. The WAN-side ingress on a VLAN
 * sub-interface (e.g. eth0.7) only strips its own VLAN; any inner tag
 * pushed by the LAN-side VLAN-aware bridge stays in the packet bytes,
 * so we have to peek past it to find PPPoE_DISC / PPPOE_SESS.
 */
static __always_inline int parse_pppoe(struct __sk_buff *skb,
				       struct ethhdr **eth_out,
				       struct pppoe_hdr **pppoe_out,
				       __u16 *proto_out)
{
	void *data = (void *)(long)skb->data;
	void *data_end = (void *)(long)skb->data_end;
	struct ethhdr *eth = data;

	if ((void *)(eth + 1) > data_end)
		return -1;

	__u16 proto = bpf_ntohs(eth->h_proto);
	void *l3 = eth + 1;

	if (proto == ETH_P_8021Q) {
		struct vlan_hdr *vh = l3;
		if ((void *)(vh + 1) > data_end)
			return -1;
		proto = bpf_ntohs(vh->inner_proto);
		l3 = vh + 1;
	}

	if (proto != PPPOE_DISC && proto != PPPOE_SESS)
		return -1;

	struct pppoe_hdr *pppoe = l3;
	if ((void *)(pppoe + 1) > data_end)
		return -1;

	*eth_out = eth;
	*pppoe_out = pppoe;
	*proto_out = proto;
	return 0;
}

SEC("classifier")
int pppoe_lan_in(struct __sk_buff *skb)
{
	struct ethhdr *eth;
	struct pppoe_hdr *pppoe;
	__u16 proto;

	if (parse_pppoe(skb, &eth, &pppoe, &proto) < 0)
		return TC_ACT_OK;

	struct relay_config *cfg = cfg_get();
	if (!cfg || !cfg->enabled)
		return TC_ACT_OK;

	struct session_key key = {};
	__builtin_memcpy(key.mac, eth->h_source, 6);
	key.session_id = pppoe->session_id;

	if (proto == PPPOE_DISC) {
		__u8 code = pppoe->code;

		// A LAN client sends PADI, PADR and PADT; PADO and PADS from
		// the LAN are not a client's and never go to the WAN.
		if (code != PADI_CODE && code != PADR_CODE && code != PADT_CODE)
			return TC_ACT_SHOT;

		if (code == PADR_CODE) {
			struct mac_key mk = {};
			__u64 now = bpf_ktime_get_ns();

			__builtin_memcpy(mk.mac, eth->h_source, 6);
			bpf_map_update_elem(&padr_seen, &mk, &now, BPF_ANY);
		}

		if (code == PADT_CODE)
			session_remove(cfg, &key);

		// Strip any VLAN the LAN bridge added (e.g. PVID from a
		// VLAN-aware br-lan). Without this the frame egresses the
		// WAN VLAN sub-iface double-tagged and the BRAS replies
		// with the LAN PVID still in the bytes, which the BRAS-side
		// pppd would treat as a different framing.
		bpf_skb_vlan_pop(skb);
		return bpf_redirect(cfg->wan_ifindex, 0);
	}

	struct session_state *st = bpf_map_lookup_elem(&sessions, &key);
	if (!st)
		return TC_ACT_SHOT;

	st->last_ns = bpf_ktime_get_ns();
	bpf_skb_vlan_pop(skb);
	return bpf_redirect(cfg->wan_ifindex, 0);
}

SEC("classifier")
int pppoe_wan_in(struct __sk_buff *skb)
{
	struct ethhdr *eth;
	struct pppoe_hdr *pppoe;
	__u16 proto;

	if (parse_pppoe(skb, &eth, &pppoe, &proto) < 0)
		return TC_ACT_OK;

	struct relay_config *cfg = cfg_get();
	if (!cfg || !cfg->enabled)
		return TC_ACT_OK;

	// Frames addressed to the DUT's own WAN MAC belong to the RG's
	// own PPPoE session; let the host stack handle them. Without this
	// the relay would eat PADO/PADS for the DUT's pppd and the RG's
	// own WAN dial-up never completes.
	if (mac_equal(eth->h_dest, cfg->wan_mac))
		return TC_ACT_OK;

	struct session_key key = {};
	__builtin_memcpy(key.mac, eth->h_dest, 6);
	key.session_id = pppoe->session_id;

	if (proto == PPPOE_DISC) {
		__u8 code = pppoe->code;
		if (code == PADO_CODE) {
			bpf_skb_vlan_pop(skb);
			return bpf_redirect(cfg->lan_ifindex, 0);
		}

		if (code == PADS_CODE) {
			struct mac_key mk = {};
			__u64 now = bpf_ktime_get_ns();

			// Not a PADS for a client that sent a PADR: not ours.
			__builtin_memcpy(mk.mac, eth->h_dest, 6);
			if (!padr_recent(&mk, now))
				return TC_ACT_OK;

			// Session ID 0 is an error PADS: the client hears
			// about it, but no session opens.
			if (pppoe->session_id) {
				if (!session_slot_take(cfg))
					return TC_ACT_SHOT;

				struct session_state st = {
					.start_ns = now,
					.last_ns = now
				};
				if (bpf_map_update_elem(&sessions, &key, &st, BPF_NOEXIST) != 0)
					session_slot_put(cfg);
				bpf_map_delete_elem(&padr_seen, &mk);
			}

			bpf_skb_vlan_pop(skb);
			return bpf_redirect(cfg->lan_ifindex, 0);
		}

		if (code == PADT_CODE) {
			session_remove(cfg, &key);
			bpf_skb_vlan_pop(skb);
			return bpf_redirect(cfg->lan_ifindex, 0);
		}

		return TC_ACT_OK;
	}

	// last_ns follows the client only: the server keeps sending LCP
	// echoes to a client that has vanished, and those must not keep the
	// session from expiring.
	if (!bpf_map_lookup_elem(&sessions, &key))
		return TC_ACT_OK;

	bpf_skb_vlan_pop(skb);
	return bpf_redirect(cfg->lan_ifindex, 0);
}

char _license[] SEC("license") = "GPL";
