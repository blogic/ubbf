/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

#include <ucode/module.h>

#include <stdint.h>
#include <string.h>
#include <unistd.h>
#include <arpa/inet.h>
#include <sys/socket.h>
#include <sys/ioctl.h>
#include <net/if.h>
#include <netinet/ether.h>
#include <netpacket/packet.h>

#include "util.h"

#define WOL_ETHER_TYPE  0x0842

/**
 * Parses a SecureOn password of 4 or 6 bytes: bare hex (`aabbccdd`), or
 * hex pairs that one `:` or one `-` separates throughout
 * (`aa:bb:cc:dd:ee:ff`, `aa-bb-cc-dd`).
 *
 * @return the number of bytes, or -1 when `s` has another form
 */
static int
wol_parse_password(const char *s, uint8_t out[6])
{
	size_t len = strlen(s);
	char sep = (len == 11 || len == 17) ? s[2] : 0;
	size_t n = sep ? (len + 1) / 3 : len / 2;

	if (sep && sep != ':' && sep != '-')
		return -1;
	if (!sep && len != 8 && len != 12)
		return -1;

	return hex_bytes_parse(s, sep, out, n) ? -1 : (int)n;
}

/**
 * Sends a Wake-on-LAN magic packet over a raw Ethernet socket.
 *
 * Builds a standard WoL payload: 6 bytes of `0xFF` followed by sixteen
 * repetitions of the target MAC and an optional SecureOn password
 * (4 or 6 hex bytes). The frame uses EtherType 0x0842 and is sent to the
 * broadcast address on the named interface via `AF_PACKET`/`SOCK_RAW`,
 * replacing the historical `etherwake` shell-out.
 *
 * The MAC must have the form `XX:XX:XX:XX:XX:XX`. The password is
 * described at `wol_parse_password()`; a null or empty password omits the
 * SecureOn field.
 *
 * Requires `CAP_NET_RAW`. On non-Linux or sandboxed systems without the
 * capability the socket creation fails and the function returns false.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (2-3 expected: iface, mac, optional password)
 * @return       true on a successful send, false when the send failed,
 *               null when an argument is invalid
 */
static uc_value_t *
uc_ubbf_wol_send(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *iface_val = uc_fn_arg(0);
	uc_value_t *mac_val = uc_fn_arg(1);
	uc_value_t *pass_val = uc_fn_arg(2);
	const char *iface, *mac_str;
	uint8_t target_mac[6];
	uint8_t password[6];
	int pass_len = 0;
	uint8_t frame[14 + 6 + 16 * 6 + 6];
	size_t frame_len;
	struct ifreq ifr;
	struct sockaddr_ll sll;
	int sk, ifindex;

	if (ucv_type(iface_val) != UC_STRING || ucv_type(mac_val) != UC_STRING)
		return NULL;

	iface = ucv_string_get(iface_val);
	mac_str = ucv_string_get(mac_val);

	if (hex_bytes_parse(mac_str, ':', target_mac, 6) != 0)
		return NULL;

	if (ucv_type(pass_val) == UC_STRING) {
		const char *p = ucv_string_get(pass_val);
		if (p && *p) {
			pass_len = wol_parse_password(p, password);
			if (pass_len < 0)
				return NULL;
		}
	}

	/* Protocol 0: the socket only sends, so the kernel must not queue
	 * inbound frames on it. The frame header carries the EtherType. */
	sk = socket(AF_PACKET, SOCK_RAW, 0);
	if (sk < 0)
		return ucv_boolean_new(false);

	memset(&ifr, 0, sizeof(ifr));
	strncpy(ifr.ifr_name, iface, IFNAMSIZ - 1);
	if (ioctl(sk, SIOCGIFINDEX, &ifr) < 0) {
		close(sk);
		return ucv_boolean_new(false);
	}
	ifindex = ifr.ifr_ifindex;

	if (ioctl(sk, SIOCGIFHWADDR, &ifr) < 0) {
		close(sk);
		return ucv_boolean_new(false);
	}

	/* Destination: broadcast. Source: iface MAC. EtherType: WoL. */
	memset(frame, 0xff, 6);
	memcpy(frame + 6, ifr.ifr_hwaddr.sa_data, 6);
	frame[12] = (WOL_ETHER_TYPE >> 8) & 0xff;
	frame[13] = WOL_ETHER_TYPE & 0xff;

	/* Payload: 6x FF sync, 16x target MAC. */
	memset(frame + 14, 0xff, 6);
	for (int i = 0; i < 16; i++)
		memcpy(frame + 14 + 6 + i * 6, target_mac, 6);

	frame_len = 14 + 6 + 16 * 6;
	if (pass_len > 0) {
		memcpy(frame + frame_len, password, pass_len);
		frame_len += pass_len;
	}

	memset(&sll, 0, sizeof(sll));
	sll.sll_family = AF_PACKET;
	sll.sll_protocol = htons(WOL_ETHER_TYPE);
	sll.sll_ifindex = ifindex;
	sll.sll_halen = 6;
	memset(sll.sll_addr, 0xff, 6);

	ssize_t n = sendto(sk, frame, frame_len, 0,
			   (struct sockaddr *)&sll, sizeof(sll));
	close(sk);

	return ucv_boolean_new(n == (ssize_t)frame_len);
}

static const uc_function_list_t wol_fns[] = {
	{ "send",               uc_ubbf_wol_send },
};

void
uc_module_init(uc_vm_t *vm, uc_value_t *scope)
{
	uc_function_list_register(scope, wol_fns);
}
