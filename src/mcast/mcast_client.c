/*
 * mcast_client.c: IPTV STB simulator (LAN-side client)
 *
 * Joins a multicast group (triggering an IGMP Join on the CPE), receives
 * stream packets, tracks loss/reorder, then leaves (triggering IGMP Leave).
 * Commands are read from stdin so the test suite can drive it via a pipe.
 *
 * Build:  gcc -O2 -o mcast_client mcast_client.c
 * Usage:  mcast_client <iface> <port>
 *
 * Stdin commands (one per line):
 *   join <group>            join multicast group
 *   leave <group>           leave multicast group
 *   stats                   print per-group stats
 *   reset                   reset counters
 *   quit                    leave all + exit
 */

#include <stdio.h>
#include <endian.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <unistd.h>
#include <signal.h>
#include <fcntl.h>
#include <errno.h>
#include <time.h>
#include <pthread.h>
#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <sys/select.h>
#include <net/if.h>

#define MAX_SUBSCRIPTIONS   32
#define BUF_SIZE            2048
#define LOSS_WINDOW         1000   /* track loss over last N expected */

/* Must match mcast_server.c */
typedef struct __attribute__((packed)) {
    uint64_t seq;
    uint64_t timestamp_us;
    uint32_t stream_id;
    char     group[16];
} pkt_hdr_t;

typedef struct {
    char     group[INET_ADDRSTRLEN];
    int      active;
    struct   ip_mreqn mreq;

    /* stats */
    uint64_t rx_count;
    uint64_t loss_count;
    uint64_t reorder_count;
    uint64_t last_seq;
    int      first_pkt;

    /* latency (microseconds) */
    int64_t  min_lat_us;
    int64_t  max_lat_us;
    int64_t  sum_lat_us;
} subscription_t;

static subscription_t g_subs[MAX_SUBSCRIPTIONS];
static int            g_nsubs = 0;
static int            g_sock  = -1;
static pthread_mutex_t g_lock = PTHREAD_MUTEX_INITIALIZER;
static volatile int   g_running = 1;
static const char    *g_iface;
static int            g_port;

static void on_signal(int s) { (void)s; g_running = 0; }

static uint64_t mono_us(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000000ULL + (uint64_t)ts.tv_nsec / 1000ULL;
}

static subscription_t *find_sub(const char *group)
{
    for (int i = 0; i < g_nsubs; i++)
        if (strcmp(g_subs[i].group, group) == 0)
            return &g_subs[i];
    return NULL;
}

static int cmd_join(const char *group)
{
    pthread_mutex_lock(&g_lock);

    subscription_t *sub = find_sub(group);
    if (sub && sub->active) {
        printf("[client] Already joined %s\n", group);
        pthread_mutex_unlock(&g_lock);
        return 0;
    }
    if (!sub) {
        if (g_nsubs >= MAX_SUBSCRIPTIONS) {
            printf("[client] ERROR: max subscriptions reached\n");
            pthread_mutex_unlock(&g_lock);
            return -1;
        }
        sub = &g_subs[g_nsubs++];
        memset(sub, 0, sizeof(*sub));
        strncpy(sub->group, group, INET_ADDRSTRLEN - 1);
        sub->first_pkt  = 1;
        sub->min_lat_us = INT64_MAX;
    }

    memset(&sub->mreq, 0, sizeof(sub->mreq));
    inet_pton(AF_INET, group, &sub->mreq.imr_multiaddr);
    sub->mreq.imr_ifindex = (int)if_nametoindex(g_iface);

    if (setsockopt(g_sock, IPPROTO_IP, IP_ADD_MEMBERSHIP,
                   &sub->mreq, sizeof(sub->mreq)) < 0) {
        perror("IP_ADD_MEMBERSHIP");
        pthread_mutex_unlock(&g_lock);
        return -1;
    }

    sub->active = 1;
    printf("[client] JOIN  %s  (IGMP Membership Report sent)\n", group);

    pthread_mutex_unlock(&g_lock);
    return 0;
}

static int cmd_leave(const char *group)
{
    pthread_mutex_lock(&g_lock);

    subscription_t *sub = find_sub(group);
    if (!sub || !sub->active) {
        printf("[client] Not joined: %s\n", group);
        pthread_mutex_unlock(&g_lock);
        return 0;
    }

    if (setsockopt(g_sock, IPPROTO_IP, IP_DROP_MEMBERSHIP,
                   &sub->mreq, sizeof(sub->mreq)) < 0) {
        perror("IP_DROP_MEMBERSHIP");
    }

    sub->active = 0;
    printf("[client] LEAVE %s  (IGMP Leave Group sent)\n", group);

    pthread_mutex_unlock(&g_lock);
    return 0;
}

static void cmd_stats(void)
{
    pthread_mutex_lock(&g_lock);
    printf("\n[client] ===== Stats =====\n");
    for (int i = 0; i < g_nsubs; i++) {
        subscription_t *s = &g_subs[i];
        double loss_pct = 0.0;
        uint64_t expected = s->rx_count + s->loss_count;
        if (expected > 0) loss_pct = 100.0 * s->loss_count / expected;
        printf("  [%s] state=%-8s rx=%llu loss=%llu(%.1f%%) reorder=%llu "
               "lat_min=%lld lat_max=%lld lat_avg=%lld us\n",
               s->group,
               s->active ? "JOINED" : "LEFT",
               (unsigned long long)s->rx_count,
               (unsigned long long)s->loss_count,
               loss_pct,
               (unsigned long long)s->reorder_count,
               (long long)(s->rx_count ? s->min_lat_us : 0),
               (long long)s->max_lat_us,
               (long long)(s->rx_count ? s->sum_lat_us / (int64_t)s->rx_count : 0));
    }
    printf("[client] =================\n\n");
    pthread_mutex_unlock(&g_lock);
}

static void cmd_reset(void)
{
    pthread_mutex_lock(&g_lock);
    for (int i = 0; i < g_nsubs; i++) {
        g_subs[i].rx_count    = 0;
        g_subs[i].loss_count  = 0;
        g_subs[i].reorder_count = 0;
        g_subs[i].first_pkt   = 1;
        g_subs[i].min_lat_us  = INT64_MAX;
        g_subs[i].max_lat_us  = 0;
        g_subs[i].sum_lat_us  = 0;
    }
    printf("[client] Counters reset\n");
    pthread_mutex_unlock(&g_lock);
}

/* Receive thread */
static void *rx_thread(void *arg)
{
    (void)arg;
    uint8_t buf[BUF_SIZE];
    struct sockaddr_in src;
    socklen_t srclen = sizeof(src);

    while (g_running) {
        fd_set rfds;
        FD_ZERO(&rfds);
        FD_SET(g_sock, &rfds);
        struct timeval tv = { .tv_sec = 0, .tv_usec = 100000 };

        if (select(g_sock + 1, &rfds, NULL, NULL, &tv) <= 0)
            continue;

        ssize_t n = recvfrom(g_sock, buf, sizeof(buf), 0,
                             (struct sockaddr *)&src, &srclen);
        if (n < (ssize_t)sizeof(pkt_hdr_t)) continue;

        pkt_hdr_t *hdr = (pkt_hdr_t *)buf;
        uint64_t seq       = be64toh(hdr->seq);
        uint64_t tx_ts     = be64toh(hdr->timestamp_us);
        uint64_t rx_ts     = mono_us();
        int64_t  lat       = (int64_t)(rx_ts - tx_ts);
        char     grp[16];
        strncpy(grp, hdr->group, sizeof(grp) - 1);
        grp[sizeof(grp) - 1] = '\0';

        pthread_mutex_lock(&g_lock);
        subscription_t *sub = find_sub(grp);
        if (sub && sub->active) {
            sub->rx_count++;
            if (sub->first_pkt) {
                sub->last_seq  = seq;
                sub->first_pkt = 0;
            } else {
                int64_t delta = (int64_t)(seq - sub->last_seq);
                if (delta > 1)
                    sub->loss_count += (uint64_t)(delta - 1);
                else if (delta <= 0)
                    sub->reorder_count++;
                sub->last_seq = seq;
            }
            if (lat > 0) {
                if (lat < sub->min_lat_us) sub->min_lat_us = lat;
                if (lat > sub->max_lat_us) sub->max_lat_us = lat;
                sub->sum_lat_us += lat;
            }
        }
        pthread_mutex_unlock(&g_lock);
    }
    return NULL;
}

int main(int argc, char *argv[])
{
    if (argc < 3) {
        fprintf(stderr, "Usage: %s <iface> <port>\n", argv[0]);
        return 1;
    }

    g_iface = argv[1];
    g_port  = atoi(argv[2]);

    /* Create a single UDP socket bound to the multicast port */
    g_sock = socket(AF_INET, SOCK_DGRAM, 0);
    if (g_sock < 0) { perror("socket"); return 1; }

    int reuse = 1;
    setsockopt(g_sock, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse));
    setsockopt(g_sock, SOL_SOCKET, SO_REUSEPORT, &reuse, sizeof(reuse));

    /* Bind to the interface */
    setsockopt(g_sock, SOL_SOCKET, SO_BINDTODEVICE, g_iface, strlen(g_iface) + 1);

    struct sockaddr_in local = {
        .sin_family      = AF_INET,
        .sin_port        = htons(g_port),
        .sin_addr.s_addr = INADDR_ANY,
    };
    if (bind(g_sock, (struct sockaddr *)&local, sizeof(local)) < 0) {
        perror("bind"); return 1;
    }

    signal(SIGINT,  on_signal);
    signal(SIGTERM, on_signal);

    pthread_t rx_tid;
    pthread_create(&rx_tid, NULL, rx_thread, NULL);

    printf("[client] Ready on %s port %d\n", g_iface, g_port);
    printf("[client] Commands: join <group> | leave <group> | stats | reset | quit\n");

    /* Command loop on stdin */
    char line[256];
    while (g_running && fgets(line, sizeof(line), stdin)) {
        /* Strip newline */
        line[strcspn(line, "\r\n")] = '\0';

        char cmd[64], arg[64];
        int n = sscanf(line, "%63s %63s", cmd, arg);
        if (n < 1) continue;

        if      (strcmp(cmd, "join")  == 0 && n == 2) cmd_join(arg);
        else if (strcmp(cmd, "leave") == 0 && n == 2) cmd_leave(arg);
        else if (strcmp(cmd, "stats") == 0)            cmd_stats();
        else if (strcmp(cmd, "reset") == 0)            cmd_reset();
        else if (strcmp(cmd, "quit")  == 0)            { g_running = 0; break; }
        else printf("[client] Unknown command: %s\n", cmd);
    }

    /* Leave all active subscriptions */
    for (int i = 0; i < g_nsubs; i++)
        if (g_subs[i].active) cmd_leave(g_subs[i].group);

    g_running = 0;
    pthread_join(rx_tid, NULL);
    cmd_stats();
    close(g_sock);
    return 0;
}
