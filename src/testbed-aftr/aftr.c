/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

/*
 * testbed-aftr: minimal DS-Lite AFTR simulator for the ubbf testbed.
 *
 * Bridges an AF_INET6 SOCK_RAW IPPROTO_IPIP socket with a pre-existing
 * TUN device so that IPv4-in-IPv6 encapsulated packets from the B4
 * (DUT) are delivered to the local IPv4 stack, and locally-generated
 * IPv4 replies routed onto the TUN are encapsulated back toward the
 * B4. The B4 address is learned from the outer IPv6 source of the
 * most recent decapsulated packet; good enough for a single-DUT
 * testbed.
 *
 * Usage: testbed-aftr <tun-ifname> <aftr-ipv6>
 *
 * The TUN device must already exist (create with `ip tuntap add
 * mode tun dev <name>`) and be configured before starting. The
 * raw socket is bound to <aftr-ipv6> so the kernel uses that as
 * the outer IPv6 source of encapsulated replies, matching the
 * peeraddr the B4 configured on its ip6tnl device.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <unistd.h>
#include <fcntl.h>
#include <signal.h>
#include <poll.h>
#include <arpa/inet.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <linux/if.h>
#include <linux/if_tun.h>
#include <netinet/in.h>

#define BUF_SIZE 2048

static volatile sig_atomic_t stop;

static void
on_signal(int s)
{
	(void)s;
	stop = 1;
}

static int
tun_attach(const char *name)
{
	struct ifreq ifr;
	int fd;

	fd = open("/dev/net/tun", O_RDWR);
	if (fd < 0) {
		perror("open /dev/net/tun");
		return -1;
	}

	memset(&ifr, 0, sizeof(ifr));
	strncpy(ifr.ifr_name, name, IFNAMSIZ - 1);
	ifr.ifr_flags = IFF_TUN | IFF_NO_PI;
	if (ioctl(fd, TUNSETIFF, &ifr) < 0) {
		perror("TUNSETIFF");
		close(fd);
		return -1;
	}

	return fd;
}

int
main(int argc, char **argv)
{
	unsigned char buf[BUF_SIZE];
	struct sockaddr_in6 aftr_addr;
	struct in6_addr b4;
	int have_b4 = 0;
	int tun, raw;

	if (argc != 3) {
		fprintf(stderr, "usage: %s <tun-ifname> <aftr-ipv6>\n", argv[0]);
		return 2;
	}

	memset(&aftr_addr, 0, sizeof(aftr_addr));
	aftr_addr.sin6_family = AF_INET6;
	if (inet_pton(AF_INET6, argv[2], &aftr_addr.sin6_addr) != 1) {
		fprintf(stderr, "invalid AFTR IPv6 address: %s\n", argv[2]);
		return 2;
	}

	signal(SIGTERM, on_signal);
	signal(SIGINT, on_signal);

	tun = tun_attach(argv[1]);
	if (tun < 0)
		return 1;

	raw = socket(AF_INET6, SOCK_RAW, IPPROTO_IPIP);
	if (raw < 0) {
		perror("socket AF_INET6 IPPROTO_IPIP");
		close(tun);
		return 1;
	}

	if (bind(raw, (struct sockaddr *)&aftr_addr, sizeof(aftr_addr)) < 0) {
		perror("bind raw");
		close(raw);
		close(tun);
		return 1;
	}

	memset(&b4, 0, sizeof(b4));

	while (!stop) {
		struct pollfd pfds[2];

		pfds[0].fd = raw;
		pfds[0].events = POLLIN;
		pfds[0].revents = 0;
		pfds[1].fd = tun;
		pfds[1].events = POLLIN;
		pfds[1].revents = 0;

		if (poll(pfds, 2, -1) < 0) {
			if (errno == EINTR)
				continue;
			perror("poll");
			break;
		}

		if (pfds[0].revents & POLLIN) {
			struct sockaddr_in6 src;
			socklen_t slen = sizeof(src);
			ssize_t n = recvfrom(raw, buf, sizeof(buf), 0,
			                     (struct sockaddr *)&src, &slen);
			if (n < 0) {
				if (errno == EINTR)
					continue;
				perror("recvfrom raw");
				break;
			}
			if (n > 0) {
				b4 = src.sin6_addr;
				have_b4 = 1;
				if (write(tun, buf, n) < 0 && errno != EINTR) {
					perror("write tun");
					break;
				}
			}
		}

		if (pfds[1].revents & POLLIN) {
			ssize_t n = read(tun, buf, sizeof(buf));
			if (n < 0) {
				if (errno == EINTR)
					continue;
				perror("read tun");
				break;
			}
			if (n > 0 && have_b4) {
				struct sockaddr_in6 dst;
				memset(&dst, 0, sizeof(dst));
				dst.sin6_family = AF_INET6;
				dst.sin6_addr = b4;
				if (sendto(raw, buf, n, 0,
				           (struct sockaddr *)&dst, sizeof(dst)) < 0
				    && errno != EINTR)
					perror("sendto raw");
			}
		}
	}

	close(raw);
	close(tun);
	return 0;
}
