/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

#include "ubbf.h"
#include <ctype.h>
#include <unistd.h>
#include <arpa/inet.h>
#include <sys/socket.h>
#include <sys/ioctl.h>
#include <net/if.h>
#include <netinet/ether.h>
#include <netpacket/packet.h>

#define WOL_ETHER_TYPE  0x0842

/**
 * Parses a colon-separated MAC string into 6 bytes. Returns 0 on success.
 */
static int
wol_parse_mac(const char *s, uint8_t out[6])
{
	unsigned int b[6];
	if (sscanf(s, "%x:%x:%x:%x:%x:%x",
		   &b[0], &b[1], &b[2], &b[3], &b[4], &b[5]) != 6)
		return -1;
	for (int i = 0; i < 6; i++) {
		if (b[i] > 0xff)
			return -1;
		out[i] = (uint8_t)b[i];
	}
	return 0;
}

/**
 * Parses `XX:XX:XX:XX:XX:XX`, `XX-XX-XX-XX-XX-XX`, or bare hex into up to
 * `max` bytes. Returns the number of bytes parsed, or -1 on error.
 */
static int
wol_parse_password(const char *s, uint8_t *out, int max)
{
	int n = 0;
	while (*s && n < max) {
		if (*s == ':' || *s == '-') {
			s++;
			continue;
		}
		if (!isxdigit((unsigned char)s[0]) || !isxdigit((unsigned char)s[1]))
			return -1;
		char pair[3] = { s[0], s[1], 0 };
		out[n++] = (uint8_t)strtoul(pair, NULL, 16);
		s += 2;
	}
	return (*s || (n != 4 && n != 6)) ? -1 : n;
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
 * Password input accepts bare hex, colon-separated, or dash-separated
 * byte sequences. A null/empty password omits the SecureOn field.
 *
 * Requires `CAP_NET_RAW`. On non-Linux or sandboxed systems without the
 * capability the socket creation fails and the function returns false.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (2-3 expected: iface, mac, optional password)
 * @return       boolean true on successful send, false otherwise
 */
uc_value_t *
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
		return ucv_boolean_new(false);

	iface = ucv_string_get(iface_val);
	mac_str = ucv_string_get(mac_val);

	if (wol_parse_mac(mac_str, target_mac) != 0)
		return ucv_boolean_new(false);

	if (ucv_type(pass_val) == UC_STRING) {
		const char *p = ucv_string_get(pass_val);
		if (p && *p) {
			pass_len = wol_parse_password(p, password, 6);
			if (pass_len < 0)
				return ucv_boolean_new(false);
		}
	}

	sk = socket(AF_PACKET, SOCK_RAW, htons(WOL_ETHER_TYPE));
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
