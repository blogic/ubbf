/*
 * igmp_querier.c: IGMPv2 Querier (WAN-side upstream router simulator)
 *
 * Sends IGMP Membership Queries on the WAN interface to keep the CPE's
 * IGMP proxy alive.  The CPE must respond within MaxRespTime with
 * Membership Reports for every active group, otherwise it will stop
 * forwarding that stream.
 *
 * Supports:
 *   - General Query  (dst=224.0.0.1, group=0.0.0.0): periodic
 *   - Group-Specific Query (dst=<group>, group=<group>): on demand
 *
 * Build:  gcc -O2 -o igmp_querier igmp_querier.c
 * Usage:  igmp_querier <iface> [query_interval_s] [max_resp_time_ds]
 *   e.g.  igmp_querier eth0.30 10 10
 *              (query every 10s, CPE must reply within 1.0s)
 *
 * NOTE: requires root (raw socket).
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <unistd.h>
#include <signal.h>
#include <time.h>
#include <errno.h>
#include <arpa/inet.h>
#include <netinet/in.h>
#include <netinet/ip.h>
#include <sys/socket.h>
#include <sys/ioctl.h>
#include <net/if.h>
#include <linux/if_ether.h>
#include <linux/if_packet.h>

/*
 * IGMPv2 packet structure (RFC 2236)
 *   type=0x11  Membership Query
 *   type=0x16  Membership Report
 *   type=0x17  Leave Group
 */
typedef struct __attribute__((packed)) {
    uint8_t  type;
    uint8_t  max_resp_time;   /* in units of 0.1 second */
    uint16_t checksum;
    uint32_t group_addr;      /* 0.0.0.0 for general query */
} igmp_hdr_t;

/*
 * IP header with Router Alert option (required for IGMP, RFC 2113)
 * Options field: 0x94 0x04 0x00 0x00  (Router Alert, length=4)
 */
typedef struct __attribute__((packed)) {
    uint8_t  ver_ihl;         /* 0x46 = version 4, IHL=6 (with options) */
    uint8_t  tos;
    uint16_t tot_len;
    uint16_t id;
    uint16_t frag_off;
    uint8_t  ttl;
    uint8_t  protocol;        /* 2 = IGMP */
    uint16_t check;
    uint32_t saddr;
    uint32_t daddr;
    uint8_t  opt[4];          /* Router Alert */
} ip_hdr_ra_t;

typedef struct __attribute__((packed)) {
    ip_hdr_ra_t ip;
    igmp_hdr_t  igmp;
} query_pkt_t;

static volatile int g_running = 1;
static void on_signal(int s) { (void)s; g_running = 0; }

static uint16_t checksum(const void *buf, size_t len)
{
    const uint16_t *p = buf;
    uint32_t sum = 0;
    for (; len > 1; len -= 2) sum += *p++;
    if (len) sum += *(const uint8_t *)p;
    while (sum >> 16) sum = (sum & 0xffff) + (sum >> 16);
    return (uint16_t)~sum;
}

static int get_iface_ip(const char *iface, uint32_t *ip_out)
{
    int s = socket(AF_INET, SOCK_DGRAM, 0);
    struct ifreq ifr;
    memset(&ifr, 0, sizeof(ifr));
    strncpy(ifr.ifr_name, iface, IFNAMSIZ - 1);
    if (ioctl(s, SIOCGIFADDR, &ifr) < 0) {
        perror("SIOCGIFADDR"); close(s); return -1;
    }
    close(s);
    *ip_out = ((struct sockaddr_in *)&ifr.ifr_addr)->sin_addr.s_addr;
    return 0;
}

/*
 * Build and send one IGMP v2 query.
 *   group = 0.0.0.0       -> General Query, dst=224.0.0.1
 *   group = 239.x.x.x     -> Group-Specific Query, dst=group
 */
static int send_query(int sock, uint32_t src_ip,
                      uint32_t group_ip, uint8_t max_resp_ds)
{
    query_pkt_t pkt;
    memset(&pkt, 0, sizeof(pkt));

    uint32_t dst_ip = group_ip
                    ? group_ip
                    : htonl(0xE0000001U);   /* 224.0.0.1 all-hosts */

    /* IP header */
    pkt.ip.ver_ihl   = 0x46;               /* IPv4, IHL=6 (5+option word) */
    pkt.ip.tos       = 0xC0;               /* DSCP CS6 (network control) */
    pkt.ip.tot_len   = htons(sizeof(pkt));
    pkt.ip.id        = htons((uint16_t)rand());
    pkt.ip.frag_off  = 0;
    pkt.ip.ttl       = 1;
    pkt.ip.protocol  = IPPROTO_IGMP;
    pkt.ip.saddr     = src_ip;
    pkt.ip.daddr     = dst_ip;
    pkt.ip.opt[0]    = 0x94;               /* Router Alert option type */
    pkt.ip.opt[1]    = 0x04;               /* option length */
    pkt.ip.opt[2]    = 0x00;
    pkt.ip.opt[3]    = 0x00;
    pkt.ip.check     = checksum(&pkt.ip, sizeof(pkt.ip));

    /* IGMP */
    pkt.igmp.type          = 0x11;         /* Membership Query */
    pkt.igmp.max_resp_time = max_resp_ds;
    pkt.igmp.group_addr    = group_ip;
    pkt.igmp.checksum      = checksum(&pkt.igmp, sizeof(pkt.igmp));

    struct sockaddr_in dst = {
        .sin_family      = AF_INET,
        .sin_addr.s_addr = dst_ip,
    };

    ssize_t n = sendto(sock, &pkt, sizeof(pkt), 0,
                       (struct sockaddr *)&dst, sizeof(dst));
    return n == sizeof(pkt) ? 0 : -1;
}

int main(int argc, char *argv[])
{
    if (argc < 2) {
        fprintf(stderr,
            "Usage: %s <iface> [query_interval_s] [max_resp_time_ds]\n"
            "  query_interval_s  : seconds between General Queries (default 10)\n"
            "  max_resp_time_ds  : max response time in 0.1s units (default 10 = 1.0s)\n"
            "  e.g. %s eth0.30 10 10\n", argv[0], argv[0]);
        return 1;
    }

    const char *iface      = argv[1];
    int interval_s         = argc > 2 ? atoi(argv[2]) : 10;
    uint8_t max_resp_ds    = argc > 3 ? (uint8_t)atoi(argv[3]) : 10;

    uint32_t src_ip = 0;
    if (get_iface_ip(iface, &src_ip) < 0) {
        fprintf(stderr, "Cannot determine IP for %s\n", iface);
        return 1;
    }

    char src_str[INET_ADDRSTRLEN];
    inet_ntop(AF_INET, &src_ip, src_str, sizeof(src_str));

    /* Raw socket with IP_HDRINCL */
    int sock = socket(AF_INET, SOCK_RAW, IPPROTO_RAW);
    if (sock < 0) {
        perror("socket(SOCK_RAW): need root");
        return 1;
    }

    int on = 1;
    setsockopt(sock, IPPROTO_IP, IP_HDRINCL, &on, sizeof(on));
    setsockopt(sock, SOL_SOCKET, SO_BINDTODEVICE, iface, strlen(iface) + 1);

    signal(SIGINT,  on_signal);
    signal(SIGTERM, on_signal);

    printf("[querier] iface=%s src=%s interval=%ds max_resp=%.1fs\n",
           iface, src_str, interval_s, max_resp_ds / 10.0);
    printf("[querier] Sending IGMPv2 General Queries, Ctrl-C to stop\n");

    uint64_t query_num = 0;

    while (g_running) {
        struct timespec now;
        clock_gettime(CLOCK_REALTIME, &now);
        char tbuf[32];
        struct tm *tm = localtime(&now.tv_sec);
        strftime(tbuf, sizeof(tbuf), "%H:%M:%S", tm);

        if (send_query(sock, src_ip, 0, max_resp_ds) == 0) {
            printf("[querier] %s  TX General Query #%llu  (maxRespTime=%.1fs)\n",
                   tbuf, (unsigned long long)++query_num, max_resp_ds / 10.0);
        } else {
            perror("[querier] sendto failed");
        }

        /* Sleep in 100ms chunks so SIGINT is responsive */
        for (int i = 0; i < interval_s * 10 && g_running; i++)
            usleep(100000);
    }

    printf("[querier] Sent %llu General Queries total\n",
           (unsigned long long)query_num);
    close(sock);
    return 0;
}
