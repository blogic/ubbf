/*
 * dnsprobe - one-shot nslookup-style CLI and long-running DNS watchdog
 *
 * CLI mode (backward-compatible with ucentral-tools' dnsprobe):
 *   dnsprobe -u <fqdn> -s <server> [-6]
 *   returns 0 on successful resolution, non-zero otherwise.
 *
 * Daemon mode:
 *   dnsprobe -D
 *   reads /etc/config/dnsprobe, periodically resolves each configured
 *   FQDN against the interface's DHCP-assigned resolvers, counts
 *   consecutive failures, fires a trigger action on threshold. Exposes
 *   a ubus object named `dnsprobe`.
 *
 * Resolver core forked from ucentral-tools' dnsprobe.c which itself
 * derives from nslookup_lede (Jo-Philipp Wich, 2017).
 */

#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <getopt.h>
#include <net/if.h>
#include <netdb.h>
#include <netinet/in.h>
#include <poll.h>
#include <resolv.h>
#include <signal.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <time.h>
#include <unistd.h>

#include <libubox/list.h>
#include <libubox/blob.h>
#include <libubox/blobmsg.h>
#include <libubox/blobmsg_json.h>
#include <libubox/ulog.h>
#include <libubox/uloop.h>
#include <libubox/utils.h>
#include <libubus.h>
#include <uci.h>

#define ENABLE_FEATURE_IPV6 1

typedef struct len_and_sockaddr {
	socklen_t len;
	union {
		struct sockaddr sa;
		struct sockaddr_in sin;
#if ENABLE_FEATURE_IPV6
		struct sockaddr_in6 sin6;
#endif
	} u;
} len_and_sockaddr;

struct ns {
	const char *name;
	len_and_sockaddr addr;
	int failures;
	int replies;
};

struct query {
	const char *name;
	size_t qlen, rlen;
	unsigned char query[512], reply[512];
	unsigned long latency;
	int rcode, n_ns;
};

static const char *rcodes[] = {
	"NOERROR", "FORMERR", "SERVFAIL", "NXDOMAIN",
	"NOTIMP",  "REFUSED", "YXDOMAIN", "YXRRSET",
	"NXRRSET", "NOTAUTH", "NOTZONE",  "RESERVED11",
	"RESERVED12", "RESERVED13", "RESERVED14", "RESERVED15",
	"BADVERS"
};

static unsigned int default_port = 53;
static unsigned int default_retry = 1;
static unsigned int default_timeout = 2;

static int parse_nsaddr(const char *addrstr_in, len_and_sockaddr *lsa)
{
	char buf[INET6_ADDRSTRLEN + 32];
	char *eptr, *hash;
	char ifname[IFNAMSIZ];
	unsigned int port = default_port;
	unsigned int scope = 0;

	/* parse_nsaddr mutates its input; work on a copy */
	snprintf(buf, sizeof(buf), "%s", addrstr_in);

	hash = strchr(buf, '#');
	if (hash) {
		*hash++ = '\0';
		port = strtoul(hash, &eptr, 10);
		if (eptr == hash || *eptr != '\0' || port > 65535) {
			errno = EINVAL;
			return -1;
		}
	}

	hash = strchr(buf, '%');
	if (hash) {
		for (eptr = ++hash; *eptr != '\0' && *eptr != '#'; eptr++) {
			if ((eptr - hash) >= IFNAMSIZ) {
				errno = ENODEV;
				return -1;
			}
			ifname[eptr - hash] = *eptr;
		}
		ifname[eptr - hash] = '\0';
		scope = if_nametoindex(ifname);
		if (scope == 0) {
			errno = ENODEV;
			return -1;
		}
	}

#if ENABLE_FEATURE_IPV6
	if (inet_pton(AF_INET6, buf, &lsa->u.sin6.sin6_addr)) {
		lsa->u.sin6.sin6_family = AF_INET6;
		lsa->u.sin6.sin6_port = htons(port);
		lsa->u.sin6.sin6_scope_id = scope;
		lsa->len = sizeof(lsa->u.sin6);
		return 0;
	}
#endif

	if (!scope && inet_pton(AF_INET, buf, &lsa->u.sin.sin_addr)) {
		lsa->u.sin.sin_family = AF_INET;
		lsa->u.sin.sin_port = htons(port);
		lsa->len = sizeof(lsa->u.sin);
		return 0;
	}

	errno = EINVAL;
	return -1;
}

static unsigned long mtime_ms(void)
{
	struct timespec ts;
	clock_gettime(CLOCK_MONOTONIC, &ts);
	return (unsigned long)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

#if ENABLE_FEATURE_IPV6
static void to_v4_mapped(len_and_sockaddr *a)
{
	if (a->u.sa.sa_family != AF_INET)
		return;
	uint32_t v4 = a->u.sin.sin_addr.s_addr;
	uint16_t port = a->u.sin.sin_port;
	memset(&a->u.sin6, 0, sizeof(a->u.sin6));
	a->u.sin6.sin6_family = AF_INET6;
	a->u.sin6.sin6_port = port;
	memcpy(a->u.sin6.sin6_addr.s6_addr, "\0\0\0\0\0\0\0\0\0\0\xff\xff", 12);
	memcpy(a->u.sin6.sin6_addr.s6_addr + 12, &v4, 4);
	a->len = sizeof(a->u.sin6);
}
#endif

/* =========================================================================
 * CLI mode (one-shot, preserves upstream dnsprobe CLI behaviour)
 * ========================================================================= */

static int parse_reply_cli(const unsigned char *msg, size_t len)
{
	ns_msg handle;
	ns_rr rr;
	int i, n, rdlen;
	char astr[INET6_ADDRSTRLEN], dname[MAXDNAME];
	const unsigned char *cp;

	if (ns_initparse(msg, len, &handle) != 0)
		return -1;

	for (i = 0; i < ns_msg_count(handle, ns_s_an); i++) {
		if (ns_parserr(&handle, ns_s_an, i, &rr) != 0)
			return -1;

		rdlen = ns_rr_rdlen(rr);

		switch (ns_rr_type(rr)) {
		case ns_t_a:
			if (rdlen != 4) return -1;
			inet_ntop(AF_INET, ns_rr_rdata(rr), astr, sizeof(astr));
			printf("Name:\t%s\nAddress: %s\n", ns_rr_name(rr), astr);
			break;
#if ENABLE_FEATURE_IPV6
		case ns_t_aaaa:
			if (rdlen != 16) return -1;
			inet_ntop(AF_INET6, ns_rr_rdata(rr), astr, sizeof(astr));
			printf("%s\thas AAAA address %s\n", ns_rr_name(rr), astr);
			break;
#endif
		case ns_t_cname:
			if (ns_name_uncompress(ns_msg_base(handle), ns_msg_end(handle),
					       ns_rr_rdata(rr), dname, sizeof(dname)) < 0)
				return -1;
			printf("%s\tcanonical name = %s\n", ns_rr_name(rr), dname);
			break;
		default:
			(void)n; (void)cp;
			break;
		}
	}
	return i;
}

static int send_queries_cli(struct ns *ns, int n_ns, struct query *queries, int n_queries)
{
	int fd;
	unsigned long timeout = default_timeout * 1000;
	unsigned long retry_interval;
	int servfail_retry = 0;
	len_and_sockaddr from = {};
#if ENABLE_FEATURE_IPV6
	int one = 1;
#endif
	int recvlen = 0;
	int n_replies = 0;
	struct pollfd pfd;
	unsigned long t0, t1, t2;
	int nn, qn, next_query = 0;

	from.u.sa.sa_family = AF_INET;
	from.len = sizeof(from.u.sin);

#if ENABLE_FEATURE_IPV6
	for (nn = 0; nn < n_ns; nn++) {
		if (ns[nn].addr.u.sa.sa_family == AF_INET6) {
			from.u.sa.sa_family = AF_INET6;
			from.len = sizeof(from.u.sin6);
			break;
		}
	}
#endif

	fd = socket(from.u.sa.sa_family, SOCK_DGRAM | SOCK_CLOEXEC | SOCK_NONBLOCK, 0);
#if ENABLE_FEATURE_IPV6
	if (fd < 0 && from.u.sa.sa_family == AF_INET6 && errno == EAFNOSUPPORT) {
		fd = socket(AF_INET, SOCK_DGRAM | SOCK_CLOEXEC | SOCK_NONBLOCK, 0);
		from.u.sa.sa_family = AF_INET;
	}
#endif
	if (fd < 0)
		return -1;

	if (bind(fd, &from.u.sa, from.len) < 0) {
		close(fd);
		return -1;
	}

#if ENABLE_FEATURE_IPV6
	if (from.u.sa.sa_family == AF_INET6) {
		setsockopt(fd, IPPROTO_IPV6, IPV6_V6ONLY, &one, sizeof(one));
		for (nn = 0; nn < n_ns; nn++)
			to_v4_mapped(&ns[nn].addr);
	}
#endif

	pfd.fd = fd;
	pfd.events = POLLIN;
	retry_interval = timeout / default_retry;
	t0 = t2 = mtime_ms();
	t1 = t2 - retry_interval;

	for (; t2 - t0 < timeout; t2 = mtime_ms()) {
		if (t2 - t1 >= retry_interval) {
			for (qn = 0; qn < n_queries; qn++) {
				if (queries[qn].rlen) continue;
				for (nn = 0; nn < n_ns; nn++)
					sendto(fd, queries[qn].query, queries[qn].qlen,
					       MSG_NOSIGNAL, &ns[nn].addr.u.sa, ns[nn].addr.len);
			}
			t1 = t2;
			servfail_retry = 2 * n_queries;
		}

		if (poll(&pfd, 1, t1 + retry_interval - t2) <= 0)
			continue;

		while (1) {
			socklen_t slen = from.len;
			recvlen = recvfrom(fd, queries[next_query].reply,
					   sizeof(queries[next_query].reply), 0,
					   &from.u.sa, &slen);
			if (recvlen < 0) break;
			if (recvlen < 4) continue;

			for (nn = 0; nn < n_ns; nn++)
				if (memcmp(&from.u.sa, &ns[nn].addr.u.sa, from.len) == 0)
					break;
			if (nn >= n_ns) continue;

			for (qn = next_query; qn < n_queries; qn++)
				if (!memcmp(queries[next_query].reply, queries[qn].query, 2))
					break;
			if (qn >= n_queries || queries[qn].rlen) continue;

			queries[qn].rcode = queries[next_query].reply[3] & 15;
			queries[qn].latency = mtime_ms() - t0;
			queries[qn].n_ns = nn;
			ns[nn].replies++;

			switch (queries[qn].rcode) {
			case 0:
			case 3:
				break;
			case 2:
				if (servfail_retry && servfail_retry--) {
					ns[nn].failures++;
					sendto(fd, queries[qn].query, queries[qn].qlen,
					       MSG_NOSIGNAL, &ns[nn].addr.u.sa,
					       ns[nn].addr.len);
				}
				/* fall through */
			default:
				continue;
			}

			n_replies++;
			queries[qn].rlen = recvlen;

			if (qn == next_query) {
				while (next_query < n_queries) {
					if (!queries[next_query].rlen) break;
					next_query++;
				}
			} else {
				memcpy(queries[qn].reply, queries[next_query].reply, recvlen);
			}

			if (next_query >= n_queries) {
				close(fd);
				return n_replies;
			}
		}
	}

	close(fd);
	return n_replies;
}

static int cli_main(const char *url, const char *server, int v6)
{
	struct ns *ns = NULL;
	struct query *queries = NULL;
	int n_ns = 0, n_queries = 0;
	int rc = 1, c = 0;

	ulog_open(ULOG_SYSLOG | ULOG_STDIO, LOG_DAEMON, "dnsprobe");
	ULOG_INFO("probe %s via %s %s\n", url, server, v6 ? "ipv6" : "");

	queries = realloc(queries, sizeof(*queries) * (n_queries + 1));
	memset(&queries[n_queries], 0, sizeof(*queries));
	ssize_t qlen = res_mkquery(QUERY, url, C_IN, v6 ? T_AAAA : T_A, NULL, 0, NULL,
				   queries[n_queries].query, sizeof(queries[n_queries].query));
	if (qlen < 0) goto out;
	queries[n_queries].qlen = qlen;
	queries[n_queries].name = url;
	n_queries++;

	ns = realloc(ns, sizeof(*ns) * (n_ns + 1));
	memset(&ns[n_ns], 0, sizeof(*ns));
	ns[n_ns].name = server;
	if (parse_nsaddr(server, &ns[n_ns].addr) != 0) {
		fprintf(stderr, "Invalid server address: %s\n", server);
		goto out;
	}
	n_ns++;

	rc = send_queries_cli(ns, 1, queries, n_queries);
	if (rc <= 0) {
		fprintf(stderr, "Failed to send queries: %s\n", strerror(errno));
		rc = -1;
		goto out;
	}

	if (queries[0].rcode != 0) {
		printf("** server can't find %s: %s\n", queries[0].name, rcodes[queries[0].rcode]);
		rc = 1;
		goto out;
	}

	if (queries[0].rlen)
		c = parse_reply_cli(queries[0].reply, queries[0].rlen);

	if (c == 0) {
		printf("*** Can't find %s: No answer\n", queries[0].name);
		rc = 1;
	} else if (c < 0) {
		printf("*** Can't find %s: Parse error\n", queries[0].name);
		rc = 1;
	} else {
		rc = 0;
	}

out:
	free(ns);
	free(queries);
	return rc;
}

/* =========================================================================
 * Daemon mode
 * ========================================================================= */

enum probe_status {
	STATUS_DISABLED = 0,
	STATUS_OK,
	STATUS_FAILING,
	STATUS_TRIGGERED
};

enum probe_family {
	FAMILY_IPV4 = 0,
	FAMILY_IPV6,
	FAMILY_BOTH
};

static const char *status_names[] = { "Disabled", "OK", "Failing", "Triggered" };

struct probe {
	struct list_head list;

	char *name;
	char *interface;
	char *host;
	unsigned int interval;
	unsigned int timeout;
	unsigned int fail_threshold;
	unsigned int cooldown;
	enum probe_family family;

	enum probe_status status;
	unsigned int consecutive_failures;
	time_t last_trigger_time;
	time_t last_success_time;
	time_t last_failure_time;

	struct uloop_timeout interval_timer;
	struct uloop_timeout query_timeout;
	int in_flight;
	int fail_this_tick;
	uint16_t qid_v4;
	uint16_t qid_v6;

	unsigned int gen;   /* reload marker */
};

static LIST_HEAD(probes);
static struct uci_context *uci_ctx;
static struct ubus_context *ubus_ctx;
static int probe_fd = -1;
static struct uloop_fd probe_ufd;
static struct blob_buf bb;

static void probe_handle_outcome(struct probe *p, int ok);
static void probe_load_all(void);

static uint16_t random_qid(void)
{
	static unsigned int seeded;
	if (!seeded) {
		seeded = 1;
		srand((unsigned int)(time(NULL) ^ getpid()));
	}
	return (uint16_t)(rand() & 0xffff);
}

static const char *fmt_time(time_t t)
{
	static char buf[32];
	struct tm tm;

	if (t == 0)
		return "0001-01-01T00:00:00Z";

	gmtime_r(&t, &tm);
	strftime(buf, sizeof(buf), "%Y-%m-%dT%H:%M:%SZ", &tm);
	return buf;
}

static struct probe *probe_find(const char *name)
{
	struct probe *p;
	list_for_each_entry(p, &probes, list)
		if (!strcmp(p->name, name))
			return p;
	return NULL;
}

static void probe_timer_tick_cb(struct uloop_timeout *t);
static void probe_timer_timeout_cb(struct uloop_timeout *t);

static struct probe *probe_new(const char *name)
{
	struct probe *p = calloc(1, sizeof(*p));
	if (!p) return NULL;
	p->name = strdup(name);
	p->status = STATUS_DISABLED;
	p->interval_timer.cb = probe_timer_tick_cb;
	p->query_timeout.cb = probe_timer_timeout_cb;
	list_add_tail(&p->list, &probes);
	return p;
}

static void probe_free(struct probe *p)
{
	uloop_timeout_cancel(&p->interval_timer);
	uloop_timeout_cancel(&p->query_timeout);
	list_del(&p->list);
	free(p->name);
	free(p->interface);
	free(p->host);
	free(p);
}

static void probe_event_emit(struct probe *p, const char *event)
{
	char topic[64];

	if (!ubus_ctx) return;
	blob_buf_init(&bb, 0);
	blobmsg_add_string(&bb, "interface", p->interface);
	blobmsg_add_string(&bb, "host", p->host);
	blobmsg_add_u32(&bb, "consecutive_failures", p->consecutive_failures);
	snprintf(topic, sizeof(topic), "dnsprobe.%s", event);
	ubus_send_event(ubus_ctx, topic, bb.head);
}

static void probe_trigger(struct probe *p)
{
	char obj[80];
	uint32_t id;
	int rc;

	p->last_trigger_time = time(NULL);
	p->status = STATUS_TRIGGERED;
	probe_event_emit(p, "trigger");

	if (!ubus_ctx) {
		ULOG_ERR("probe %s: threshold reached on iface %s host %s "
			 "(%u failures); no ubus connection to trigger restart\n",
			 p->name, p->interface, p->host,
			 p->consecutive_failures);
		return;
	}

	snprintf(obj, sizeof(obj), "network.interface.%s", p->interface);
	if (ubus_lookup_id(ubus_ctx, obj, &id) != 0) {
		ULOG_ERR("probe %s: threshold reached on iface %s host %s "
			 "(%u failures); %s not registered with ubus\n",
			 p->name, p->interface, p->host,
			 p->consecutive_failures, obj);
		return;
	}

	blob_buf_init(&bb, 0);
	rc = ubus_invoke(ubus_ctx, id, "restart", bb.head, NULL, NULL, 1000);
	if (rc == UBUS_STATUS_METHOD_NOT_FOUND) {
		ULOG_ERR("probe %s: threshold reached on iface %s host %s "
			 "(%u failures); %s has no restart method "
			 "(netifd too old?)\n",
			 p->name, p->interface, p->host,
			 p->consecutive_failures, obj);
		return;
	}
	if (rc != 0) {
		ULOG_ERR("probe %s: restart on %s returned %d\n",
			 p->name, obj, rc);
		return;
	}
	ULOG_ERR("probe %s: restart invoked on %s "
		 "(%u consecutive failures for host %s)\n",
		 p->name, obj, p->consecutive_failures, p->host);
}

/* ---- netifd DNS server lookup (synchronous ubus invoke) ---- */

struct dns_collect {
	len_and_sockaddr *servers;
	int n_servers;
	enum probe_family family;
};

static void dns_collect_add_array(struct dns_collect *c, struct blob_attr *arr)
{
	struct blob_attr *cur;
	int rem;
	len_and_sockaddr a;

	blobmsg_for_each_attr(cur, arr, rem) {
		if (blobmsg_type(cur) != BLOBMSG_TYPE_STRING)
			continue;
		memset(&a, 0, sizeof(a));
		if (parse_nsaddr(blobmsg_get_string(cur), &a) != 0)
			continue;
		if (c->family == FAMILY_IPV4 && a.u.sa.sa_family != AF_INET) continue;
		if (c->family == FAMILY_IPV6 && a.u.sa.sa_family != AF_INET6) continue;

		c->servers = realloc(c->servers, sizeof(*c->servers) * (c->n_servers + 1));
		c->servers[c->n_servers++] = a;
	}
}

static void netifd_status_cb(struct ubus_request *req, int type, struct blob_attr *msg)
{
	struct dns_collect *c = req->priv;
	enum { S_UP, S_DNS4, S_DNS6, S_MAX };
	static const struct blobmsg_policy p[] = {
		[S_UP]   = { .name = "up",          .type = BLOBMSG_TYPE_BOOL },
		[S_DNS4] = { .name = "dns-server",  .type = BLOBMSG_TYPE_ARRAY },
		[S_DNS6] = { .name = "ipv6-dns",    .type = BLOBMSG_TYPE_ARRAY },
	};
	struct blob_attr *tb[S_MAX];

	blobmsg_parse(p, S_MAX, tb, blob_data(msg), blob_len(msg));

	if (!tb[S_UP] || !blobmsg_get_bool(tb[S_UP]))
		return;
	if (tb[S_DNS4])
		dns_collect_add_array(c, tb[S_DNS4]);
	if (tb[S_DNS6])
		dns_collect_add_array(c, tb[S_DNS6]);
}

static int netifd_dns_servers_for(const char *iface, enum probe_family family,
				  struct dns_collect *out)
{
	char obj[80];
	uint32_t id;

	if (!ubus_ctx) return -1;
	snprintf(obj, sizeof(obj), "network.interface.%s", iface);
	if (ubus_lookup_id(ubus_ctx, obj, &id) != 0)
		return -1;

	out->family = family;
	blob_buf_init(&bb, 0);
	return ubus_invoke(ubus_ctx, id, "status", bb.head,
			   netifd_status_cb, out, 1000);
}

/* ---- socket + recv path ---- */

static void probe_socket_recv(struct uloop_fd *u, unsigned int events)
{
	unsigned char buf[512];
	struct sockaddr_storage sa;

	for (;;) {
		socklen_t slen = sizeof(sa);
		ssize_t n = recvfrom(u->fd, buf, sizeof(buf), 0,
				     (struct sockaddr *)&sa, &slen);
		if (n < 0) break;
		if (n < 4) continue;

		uint16_t qid = (buf[0] << 8) | buf[1];
		int rcode = buf[3] & 0x0f;
		/* accept NOERROR and NXDOMAIN as "server reachable" */
		int good = (rcode == 0 || rcode == 3);

		struct probe *p;
		list_for_each_entry(p, &probes, list) {
			if (!p->in_flight) continue;
			if (qid != p->qid_v4 && qid != p->qid_v6) continue;
			p->in_flight--;
			if (good) {
				uloop_timeout_cancel(&p->query_timeout);
				p->in_flight = 0;
				probe_handle_outcome(p, 1);
			} else {
				p->fail_this_tick++;
				if (p->in_flight == 0) {
					uloop_timeout_cancel(&p->query_timeout);
					probe_handle_outcome(p, 0);
				}
			}
			break;
		}
	}
}

static void probe_send_query(struct probe *p, int type, uint16_t qid,
			     const len_and_sockaddr *server)
{
	unsigned char q[512];
	ssize_t qlen;
	len_and_sockaddr target = *server;

	qlen = res_mkquery(QUERY, p->host, C_IN, type, NULL, 0, NULL, q, sizeof(q));
	if (qlen < 0) return;

	q[0] = (qid >> 8) & 0xff;
	q[1] = qid & 0xff;

#if ENABLE_FEATURE_IPV6
	to_v4_mapped(&target);
#endif

	if (sendto(probe_fd, q, qlen, MSG_NOSIGNAL,
		   &target.u.sa, target.len) < 0) {
		ULOG_WARN("probe %s: sendto %s failed: %s\n",
			  p->name, p->host, strerror(errno));
		return;
	}
	p->in_flight++;
}

static void probe_timer_timeout_cb(struct uloop_timeout *t)
{
	struct probe *p = container_of(t, struct probe, query_timeout);

	if (p->in_flight == 0) return;
	p->in_flight = 0;
	probe_handle_outcome(p, 0);
}

static void probe_handle_outcome(struct probe *p, int ok)
{
	time_t now = time(NULL);

	if (ok) {
		p->last_success_time = now;
		if (p->consecutive_failures > 0 || p->status != STATUS_OK)
			ULOG_INFO("probe %s: iface %s host %s recovered\n",
				  p->name, p->interface, p->host);
		p->consecutive_failures = 0;
		p->status = STATUS_OK;
		return;
	}

	p->last_failure_time = now;
	p->consecutive_failures++;
	ULOG_WARN("probe %s: iface %s host %s failure (%u/%u)\n",
		  p->name, p->interface, p->host,
		  p->consecutive_failures, p->fail_threshold);

	if (p->consecutive_failures >= p->fail_threshold) {
		if (p->cooldown == 0 ||
		    (now - p->last_trigger_time) >= (time_t)p->cooldown) {
			probe_trigger(p);
			p->consecutive_failures = 0;
		} else {
			p->status = STATUS_FAILING;
		}
	} else {
		p->status = STATUS_FAILING;
	}
}

static void probe_timer_tick_cb(struct uloop_timeout *t)
{
	struct probe *p = container_of(t, struct probe, interval_timer);
	struct dns_collect dns = {};
	int i, want_v4, want_v6;

	/* rearm next tick first so re-entrancy is safe */
	uloop_timeout_set(&p->interval_timer, p->interval * 1000);

	p->fail_this_tick = 0;
	p->in_flight = 0;
	p->qid_v4 = random_qid();
	p->qid_v6 = random_qid();
	if (p->qid_v6 == p->qid_v4)
		p->qid_v6 ^= 0x8000;

	if (netifd_dns_servers_for(p->interface, p->family, &dns) < 0 ||
	    dns.n_servers == 0) {
		free(dns.servers);
		probe_handle_outcome(p, 0);
		return;
	}

	want_v4 = (p->family == FAMILY_IPV4 || p->family == FAMILY_BOTH);
	want_v6 = (p->family == FAMILY_IPV6 || p->family == FAMILY_BOTH);

	for (i = 0; i < dns.n_servers; i++) {
		if (want_v4) probe_send_query(p, T_A,    p->qid_v4, &dns.servers[i]);
		if (want_v6) probe_send_query(p, T_AAAA, p->qid_v6, &dns.servers[i]);
	}
	free(dns.servers);

	if (p->in_flight == 0) {
		probe_handle_outcome(p, 0);
		return;
	}

	uloop_timeout_set(&p->query_timeout, p->timeout * 1000);
}

/* ---- libuci load ---- */

static enum probe_family parse_family(const char *s)
{
	if (!s) return FAMILY_IPV4;
	if (!strcasecmp(s, "ipv6")) return FAMILY_IPV6;
	if (!strcasecmp(s, "both")) return FAMILY_BOTH;
	return FAMILY_IPV4;
}

static unsigned int parse_uint_default(const char *s, unsigned int dflt)
{
	if (!s) return dflt;
	char *end;
	unsigned long v = strtoul(s, &end, 10);
	if (end == s) return dflt;
	return (unsigned int)v;
}

static void probe_load_all(void)
{
	struct uci_package *pkg = NULL;
	struct probe *p, *np;

	if (!uci_ctx)
		uci_ctx = uci_alloc_context();
	if (!uci_ctx) return;

	list_for_each_entry(p, &probes, list)
		p->gen = 0;

	if (uci_load(uci_ctx, "dnsprobe", &pkg) != UCI_OK) {
		ULOG_INFO("no /etc/config/dnsprobe or parse error\n");
	} else {
		struct uci_element *e;

		uci_foreach_element(&pkg->sections, e) {
			struct uci_section *s = uci_to_section(e);
			if (strcmp(s->type, "probe") != 0) continue;

			const char *iface = uci_lookup_option_string(uci_ctx, s, "interface");
			const char *host  = uci_lookup_option_string(uci_ctx, s, "host");
			if (!iface || !host) continue;

			const char *interval_s = uci_lookup_option_string(uci_ctx, s, "interval");
			const char *timeout_s  = uci_lookup_option_string(uci_ctx, s, "timeout");
			const char *ft_s       = uci_lookup_option_string(uci_ctx, s, "fail_threshold");
			const char *cd_s       = uci_lookup_option_string(uci_ctx, s, "cooldown");
			const char *fam_s      = uci_lookup_option_string(uci_ctx, s, "family");

			struct probe *p2 = probe_find(e->name);
			if (!p2) {
				p2 = probe_new(e->name);
				if (!p2) continue;
			}

			free(p2->interface); p2->interface = strdup(iface);
			free(p2->host);      p2->host      = strdup(host);
			p2->interval        = parse_uint_default(interval_s, 60);
			p2->timeout         = parse_uint_default(timeout_s, 5);
			p2->fail_threshold  = parse_uint_default(ft_s, 3);
			p2->cooldown        = parse_uint_default(cd_s, 300);
			p2->family          = parse_family(fam_s);
			if (p2->interval == 0)       p2->interval = 60;
			if (p2->timeout == 0)        p2->timeout = 5;
			if (p2->fail_threshold == 0) p2->fail_threshold = 3;
			p2->gen = 1;
			if (p2->status == STATUS_DISABLED)
				p2->status = STATUS_OK;

			uloop_timeout_set(&p2->interval_timer, 1000);
		}
		uci_unload(uci_ctx, pkg);
	}

	list_for_each_entry_safe(p, np, &probes, list)
		if (p->gen == 0)
			probe_free(p);
}

/* ---- ubus interface ---- */

enum { F_INTERFACE, __F_MAX };
static const struct blobmsg_policy probe_filter_policy[] = {
	[F_INTERFACE] = { "interface", BLOBMSG_TYPE_STRING },
};

static void add_probe_to_reply(struct blob_buf *buf, const struct probe *p)
{
	void *t = blobmsg_open_table(buf, NULL);
	blobmsg_add_string(buf, "interface", p->interface);
	blobmsg_add_string(buf, "host", p->host);
	blobmsg_add_string(buf, "status", status_names[p->status]);
	blobmsg_add_u32(buf, "consecutive_failures", p->consecutive_failures);
	blobmsg_add_string(buf, "last_trigger_time", fmt_time(p->last_trigger_time));
	blobmsg_close_table(buf, t);
}

static int ubus_status_method(struct ubus_context *ctx, struct ubus_object *obj,
			      struct ubus_request_data *req, const char *method,
			      struct blob_attr *msg)
{
	struct blob_attr *tb[__F_MAX];
	const char *filter = NULL;
	struct probe *p;
	void *arr;

	blobmsg_parse(probe_filter_policy, __F_MAX, tb,
		      blob_data(msg), blob_len(msg));
	if (tb[F_INTERFACE])
		filter = blobmsg_get_string(tb[F_INTERFACE]);

	blob_buf_init(&bb, 0);
	arr = blobmsg_open_array(&bb, "probes");
	list_for_each_entry(p, &probes, list) {
		if (filter && strcmp(p->interface, filter) != 0) continue;
		add_probe_to_reply(&bb, p);
	}
	blobmsg_close_array(&bb, arr);

	return ubus_send_reply(ctx, req, bb.head);
}

static int ubus_reload_method(struct ubus_context *ctx, struct ubus_object *obj,
			      struct ubus_request_data *req, const char *method,
			      struct blob_attr *msg)
{
	probe_load_all();
	return 0;
}

static int ubus_reset_method(struct ubus_context *ctx, struct ubus_object *obj,
			     struct ubus_request_data *req, const char *method,
			     struct blob_attr *msg)
{
	struct blob_attr *tb[__F_MAX];
	const char *filter = NULL;
	struct probe *p;

	blobmsg_parse(probe_filter_policy, __F_MAX, tb,
		      blob_data(msg), blob_len(msg));
	if (tb[F_INTERFACE])
		filter = blobmsg_get_string(tb[F_INTERFACE]);

	list_for_each_entry(p, &probes, list) {
		if (filter && strcmp(p->interface, filter) != 0) continue;
		p->consecutive_failures = 0;
		p->last_trigger_time = 0;
		if (p->status == STATUS_FAILING || p->status == STATUS_TRIGGERED)
			p->status = STATUS_OK;
	}
	return 0;
}

static const struct ubus_method dnsprobe_methods[] = {
	UBUS_METHOD("status", ubus_status_method, probe_filter_policy),
	UBUS_METHOD_NOARG("reload", ubus_reload_method),
	UBUS_METHOD("reset", ubus_reset_method, probe_filter_policy),
};

static struct ubus_object_type dnsprobe_type =
	UBUS_OBJECT_TYPE("dnsprobe", dnsprobe_methods);

static struct ubus_object dnsprobe_obj = {
	.name = "dnsprobe",
	.type = &dnsprobe_type,
	.methods = dnsprobe_methods,
	.n_methods = ARRAY_SIZE(dnsprobe_methods),
};

/* ---- signals ---- */

static void sighup_handler(int sig)
{
	(void)sig;
	probe_load_all();
}

static void sigterm_handler(int sig)
{
	(void)sig;
	uloop_end();
}

/* ---- daemon main ---- */

static int open_probe_socket(void)
{
	int fd, zero = 0;
	struct sockaddr_in6 any6 = {
		.sin6_family = AF_INET6,
		.sin6_addr = IN6ADDR_ANY_INIT,
	};

	fd = socket(AF_INET6, SOCK_DGRAM | SOCK_CLOEXEC | SOCK_NONBLOCK, 0);
	if (fd < 0) {
		/* v6 unavailable, fall back to v4 only */
		fd = socket(AF_INET, SOCK_DGRAM | SOCK_CLOEXEC | SOCK_NONBLOCK, 0);
		if (fd < 0) return -1;
		struct sockaddr_in any4 = { .sin_family = AF_INET };
		if (bind(fd, (struct sockaddr *)&any4, sizeof(any4)) < 0) {
			close(fd);
			return -1;
		}
		return fd;
	}

	setsockopt(fd, IPPROTO_IPV6, IPV6_V6ONLY, &zero, sizeof(zero));
	if (bind(fd, (struct sockaddr *)&any6, sizeof(any6)) < 0) {
		close(fd);
		return -1;
	}
	return fd;
}

static int daemon_main(void)
{
	ulog_open(ULOG_SYSLOG | ULOG_STDIO, LOG_DAEMON, "dnsprobe");

	uloop_init();

	probe_fd = open_probe_socket();
	if (probe_fd < 0) {
		ULOG_ERR("cannot open UDP socket: %s\n", strerror(errno));
		return 1;
	}
	probe_ufd.fd = probe_fd;
	probe_ufd.cb = probe_socket_recv;
	uloop_fd_add(&probe_ufd, ULOOP_READ);

	ubus_ctx = ubus_connect(NULL);
	if (!ubus_ctx) {
		ULOG_ERR("cannot connect to ubus\n");
		return 1;
	}
	ubus_add_uloop(ubus_ctx);
	if (ubus_add_object(ubus_ctx, &dnsprobe_obj))
		ULOG_ERR("cannot register ubus object\n");

	signal(SIGHUP, sighup_handler);
	signal(SIGTERM, sigterm_handler);
	signal(SIGINT, sigterm_handler);
	signal(SIGPIPE, SIG_IGN);

	probe_load_all();

	uloop_run();

	if (ubus_ctx) {
		ubus_free(ubus_ctx);
		ubus_ctx = NULL;
	}
	if (uci_ctx) {
		uci_free_context(uci_ctx);
		uci_ctx = NULL;
	}
	close(probe_fd);
	probe_fd = -1;
	uloop_done();
	return 0;
}

/* =========================================================================
 * main() dispatch
 * ========================================================================= */

static void print_usage(void)
{
	fprintf(stderr,
		"Usage: dnsprobe [-D | -u <fqdn> -s <server> [-6]]\n"
		"  -D           run as daemon using /etc/config/dnsprobe\n"
		"  -u <fqdn>    one-shot query target\n"
		"  -s <server>  DNS server to query\n"
		"  -6           query AAAA instead of A\n");
}

int main(int argc, char **argv)
{
	const char *url = "telecominfraproject.com";
	const char *server = "127.0.0.1";
	int v6 = 0;
	int daemon_mode = 0;
	int opt;

	while ((opt = getopt(argc, argv, "Du:s:6h")) != -1) {
		switch (opt) {
		case 'D': daemon_mode = 1; break;
		case 'u': url = optarg; break;
		case 's': server = optarg; break;
		case '6': v6 = 1; break;
		case 'h': print_usage(); return 0;
		default:  print_usage(); return 1;
		}
	}

	if (daemon_mode)
		return daemon_main();
	return cli_main(url, server, v6);
}
