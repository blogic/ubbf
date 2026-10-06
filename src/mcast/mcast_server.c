/*
 * mcast_server.c: Multicast IPTV stream simulator (WAN-side source)
 *
 * Sends UDP multicast packets with sequence numbers + timestamps to one or
 * more groups simultaneously, simulating multiple IPTV channels.
 *
 * Build:  gcc -O2 -o mcast_server mcast_server.c
 * Usage:  mcast_server <iface> <group1[,group2,...]> <port> [pps_per_stream]
 * e.g.:   mcast_server eth0.30 239.1.1.1,239.1.1.2,239.1.1.3 5000 50
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <unistd.h>
#include <signal.h>
#include <time.h>
#include <endian.h>
#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <net/if.h>

#define MAX_GROUPS      32
#define PKT_PAYLOAD     1316    /* 7 × 188-byte MPEG-TS packets */
#define DEFAULT_PPS     50      /* packets/sec per stream ≈ 500 Kbps */

/* Packet header embedded at the start of every UDP payload */
typedef struct __attribute__((packed)) {
    uint64_t seq;               /* big-endian sequence number */
    uint64_t timestamp_us;      /* big-endian monotonic microseconds */
    uint32_t stream_id;         /* which group index */
    char     group[16];         /* dotted-quad group address */
} pkt_hdr_t;

typedef struct {
    char     group[INET_ADDRSTRLEN];
    int      sock;
    uint64_t tx_count;
    struct   sockaddr_in dst;
} stream_t;

static volatile int g_running = 1;

static void on_signal(int s) { (void)s; g_running = 0; }

static uint64_t mono_us(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000000ULL + (uint64_t)ts.tv_nsec / 1000ULL;
}

static int stream_open(stream_t *st, const char *iface, int port)
{
    int s = socket(AF_INET, SOCK_DGRAM, 0);
    if (s < 0) { perror("socket"); return -1; }

    /* Bind outgoing multicast to specific interface */
    struct ip_mreqn mreqn = {0};
    mreqn.imr_ifindex = (int)if_nametoindex(iface);
    if (!mreqn.imr_ifindex) {
        fprintf(stderr, "Unknown interface: %s\n", iface);
        close(s); return -1;
    }
    if (setsockopt(s, IPPROTO_IP, IP_MULTICAST_IF, &mreqn, sizeof(mreqn)) < 0) {
        perror("IP_MULTICAST_IF"); close(s); return -1;
    }

    int ttl = 10;
    setsockopt(s, IPPROTO_IP, IP_MULTICAST_TTL, &ttl, sizeof(ttl));
    int loop = 0;  /* don't receive our own traffic */
    setsockopt(s, IPPROTO_IP, IP_MULTICAST_LOOP, &loop, sizeof(loop));

    memset(&st->dst, 0, sizeof(st->dst));
    st->dst.sin_family = AF_INET;
    st->dst.sin_port   = htons(port);
    inet_pton(AF_INET, st->group, &st->dst.sin_addr);

    st->sock     = s;
    st->tx_count = 0;
    return 0;
}

int main(int argc, char *argv[])
{
    if (argc < 4) {
        fprintf(stderr,
            "Usage: %s <iface> <group1[,group2,...]> <port> [pps_per_stream]\n"
            "  e.g. %s eth0.30 239.1.1.1,239.1.1.2 5000 50\n",
            argv[0], argv[0]);
        return 1;
    }

    const char *iface = argv[1];
    int port = atoi(argv[3]);
    int pps  = argc > 4 ? atoi(argv[4]) : DEFAULT_PPS;
    int interval_us = 1000000 / pps;

    stream_t streams[MAX_GROUPS];
    int nstreams = 0;

    /* Parse comma-separated groups */
    char gbuf[1024];
    strncpy(gbuf, argv[2], sizeof(gbuf) - 1);
    for (char *tok = strtok(gbuf, ","); tok && nstreams < MAX_GROUPS;
         tok = strtok(NULL, ","))
    {
        strncpy(streams[nstreams].group, tok, INET_ADDRSTRLEN - 1);
        if (stream_open(&streams[nstreams], iface, port) < 0) return 1;
        nstreams++;
    }

    printf("[server] iface=%s  groups=%d  port=%d  pps=%d  pkt_size=%zu\n",
           iface, nstreams, port, pps,
           sizeof(pkt_hdr_t) + PKT_PAYLOAD - sizeof(((pkt_hdr_t*)0)->group) + 16);

    signal(SIGINT,  on_signal);
    signal(SIGTERM, on_signal);

    uint8_t  buf[sizeof(pkt_hdr_t) + PKT_PAYLOAD];
    pkt_hdr_t *hdr = (pkt_hdr_t *)buf;
    /* Fill payload with 0x47 (MPEG-TS sync byte) for realism */
    memset(buf + sizeof(pkt_hdr_t), 0x47, PKT_PAYLOAD);

    uint64_t next_tx = mono_us();

    while (g_running) {
        uint64_t now = mono_us();
        if (now < next_tx) {
            usleep(next_tx - now);
            continue;
        }
        next_tx += interval_us;

        for (int i = 0; i < nstreams; i++) {
            hdr->seq        = htobe64(streams[i].tx_count);
            hdr->timestamp_us = htobe64(mono_us());
            hdr->stream_id  = htonl((uint32_t)i);
            strncpy(hdr->group, streams[i].group, sizeof(hdr->group) - 1);

            ssize_t n = sendto(streams[i].sock, buf, sizeof(buf), 0,
                               (struct sockaddr *)&streams[i].dst,
                               sizeof(streams[i].dst));
            if (n > 0) streams[i].tx_count++;
        }
    }

    printf("\n[server] TX summary:\n");
    for (int i = 0; i < nstreams; i++) {
        printf("  [%d] %s : %llu pkts\n", i, streams[i].group,
               (unsigned long long)streams[i].tx_count);
        close(streams[i].sock);
    }
    return 0;
}
