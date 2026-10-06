/* SPDX-License-Identifier: GPL-2.0-only */

#define main dnsprobe_main
#include "../dnsprobe.c"
#undef main

static int failures;

#define CHECK(_cond) do {							\
	if (!(_cond)) {								\
		fprintf(stderr, "%s:%d: check failed: %s\n",			\
			__FILE__, __LINE__, #_cond);				\
		failures++;							\
	}									\
} while (0)

static void
test_parse_nsaddr(void)
{
	len_and_sockaddr a;
	char scope[32];

	CHECK(parse_nsaddr("192.0.2.1", &a) == 0 && a.u.sa.sa_family == AF_INET);
	CHECK(parse_nsaddr("fe80::1%lo", &a) == 0 && a.u.sin6.sin6_scope_id == if_nametoindex("lo"));
	CHECK(parse_nsaddr("fe80::1%lo#5353", &a) == 0 && ntohs(a.u.sin6.sin6_port) == 5353);
	CHECK(parse_nsaddr("fe80::1%", &a) < 0);
	CHECK(parse_nsaddr("fe80::1%nosuchif0", &a) < 0);
	CHECK(parse_nsaddr("192.0.2.1%lo", &a) < 0);

	/* IFNAMSIZ - 1, IFNAMSIZ and IFNAMSIZ + 1 characters; ASan reports
	 * a write past ifname[] */
	for (int len = IFNAMSIZ - 1; len <= IFNAMSIZ + 1; len++) {
		char addr[64];

		memset(scope, 'x', len);
		scope[len] = '\0';
		snprintf(addr, sizeof(addr), "fe80::1%%%s", scope);
		CHECK(parse_nsaddr(addr, &a) < 0);
	}
}

static int
udp_socket(int family, const char *addr, len_and_sockaddr *out)
{
	len_and_sockaddr a = {};
	int fd = socket(family, SOCK_DGRAM, 0);

	if (family == AF_INET) {
		a.u.sin.sin_family = AF_INET;
		inet_pton(AF_INET, addr, &a.u.sin.sin_addr);
		a.len = sizeof(a.u.sin);
	} else {
		int zero = 0;

		setsockopt(fd, IPPROTO_IPV6, IPV6_V6ONLY, &zero, sizeof(zero));
		a.u.sin6.sin6_family = AF_INET6;
		inet_pton(AF_INET6, addr, &a.u.sin6.sin6_addr);
		a.len = sizeof(a.u.sin6);
	}

	bind(fd, &a.u.sa, a.len);
	getsockname(fd, &a.u.sa, &a.len);
	if (out)
		*out = a;
	return fd;
}

/* Receives the query a server got, as the reply it would send. */
static int
query_take(int server_fd, unsigned char *buf, int rcode)
{
	struct pollfd pfd = { .fd = server_fd, .events = POLLIN };
	int n;

	if (poll(&pfd, 1, 1000) != 1)
		return -1;

	n = recv(server_fd, buf, 512, 0);
	if (n >= HFIXEDSZ) {
		buf[2] |= 0x80;
		buf[3] = (buf[3] & 0xf0) | rcode;
	}
	return n;
}

static struct probe *
probe_make(void)
{
	struct probe *p = probe_new("t");

	p->host = strdup("example.com");
	p->interface = strdup("wan");
	p->fail_threshold = 100;
	return p;
}

static void
test_replies(void)
{
	len_and_sockaddr srv, wrong;
	unsigned char r[512], other[512];
	int srv_fd = udp_socket(AF_INET, "127.0.0.1", &srv);
	struct probe *p = probe_make();
	int n;

	probe_fd = udp_socket(AF_INET, "127.0.0.1", NULL);
	probe_fd_family = AF_INET;

	probe_send_query(p, T_A, &srv);
	CHECK(p->n_queries == 1 && p->in_flight == 1);
	n = query_take(srv_fd, r, ns_r_noerror);
	CHECK(n >= HFIXEDSZ);

	wrong = srv;
	wrong.u.sin.sin_port = htons(ntohs(srv.u.sin.sin_port) + 1);
	probe_reply_handle(r, n, &wrong.u.sa);
	CHECK(p->in_flight == 1);

	probe_reply_handle(r, 4, &srv.u.sa);
	CHECK(p->in_flight == 1);

	r[2] &= ~0x80;
	probe_reply_handle(r, n, &srv.u.sa);
	CHECK(p->in_flight == 1);
	r[2] |= 0x80;

	int on = res_mkquery(QUERY, "other.example", C_IN, T_A, NULL, 0, NULL, other, sizeof(other));
	memcpy(other, r, 2);
	other[2] |= 0x80;
	probe_reply_handle(other, on, &srv.u.sa);
	CHECK(p->in_flight == 1);

	r[1] ^= 1;
	probe_reply_handle(r, n, &srv.u.sa);
	CHECK(p->in_flight == 1);
	r[1] ^= 1;

	probe_reply_handle(r, n, &srv.u.sa);
	CHECK(p->in_flight == 0 && p->status == STATUS_OK);

	/* A negative reply settles its query once: with two queries out,
	 * a repeat of the first does not count as the second */
	p->in_flight = 0;
	p->n_queries = 0;
	probe_send_query(p, T_A, &srv);
	probe_send_query(p, T_A, &srv);
	n = query_take(srv_fd, r, ns_r_servfail);
	query_take(srv_fd, other, ns_r_servfail);
	probe_reply_handle(r, n, &srv.u.sa);
	CHECK(p->in_flight == 1 && p->consecutive_failures == 0);
	probe_reply_handle(r, n, &srv.u.sa);
	CHECK(p->in_flight == 1 && p->consecutive_failures == 0);

	/* The IPv4 fallback socket sends IPv4 queries and skips IPv6 servers */
	len_and_sockaddr v6;
	parse_nsaddr("::1", &v6);
	p->in_flight = 0;
	p->n_queries = 0;
	probe_send_query(p, T_A, &v6);
	CHECK(p->n_queries == 0);

	close(probe_fd);

	/* On the dual-stack socket an IPv4 server is reached through a
	 * v4-mapped address, and its reply comes back as one */
	probe_fd = udp_socket(AF_INET6, "::", NULL);
	probe_fd_family = AF_INET6;
	probe_send_query(p, T_A, &srv);
	CHECK(p->n_queries == 1);
	n = query_take(srv_fd, r, ns_r_noerror);
	CHECK(n >= HFIXEDSZ);
	len_and_sockaddr mapped = srv;
	to_v4_mapped(&mapped);
	probe_reply_handle(r, n, &mapped.u.sa);
	CHECK(p->in_flight == 0 && p->status == STATUS_OK);

	close(probe_fd);
	close(srv_fd);
	probe_free(p);
}

int
main(void)
{
	test_parse_nsaddr();
	test_replies();

	if (failures) {
		fprintf(stderr, "%d check(s) failed\n", failures);
		return 1;
	}

	printf("all checks passed\n");
	return 0;
}
