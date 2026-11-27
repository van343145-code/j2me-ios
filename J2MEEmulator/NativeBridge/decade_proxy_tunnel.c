#include "decade_proxy_tunnel.h"
#include "jvm_bridge.h"
#include "jvm.h"
#include "jvm_util.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <fcntl.h>
#include <unistd.h>
#include <pthread.h>

#define MAX_SLOT_SOCKETS 64

static int g_slot_sockets[JVM_BRIDGE_MAX_SLOTS][MAX_SLOT_SOCKETS];
static int g_slot_socket_counts[JVM_BRIDGE_MAX_SLOTS] = {0};
static pthread_mutex_t g_sock_lock = PTHREAD_MUTEX_INITIALIZER;

void decade_network_optimize_socket(int fd) {
    if (fd < 0) return;

    // 1. TCP_NODELAY: Disable Nagle algorithm for lowest upstream latency (mạng up phản hồi siêu mượt)
    int nodelay = 1;
    setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, (const void *)&nodelay, sizeof(nodelay));

    // 2. SO_NOSIGPIPE on Apple/Darwin: Prevent process termination on broken pipe
#if defined(SO_NOSIGPIPE)
    int nosigpipe = 1;
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, (const void *)&nosigpipe, sizeof(nosigpipe));
#endif

    // 3. Keep-alive probes: Maintain NAT bindings in 4G/5G/Wi-Fi when idle or in background
    int keepalive = 1;
    setsockopt(fd, SOL_SOCKET, SO_KEEPALIVE, (const void *)&keepalive, sizeof(keepalive));

#if defined(__APPLE__) || defined(__MACH__)
    // Clean iOS-friendly TCP keepalive matching carrier NAT & Wi-Fi sleep timers without aggressive radio churn
    int keepidle = 20;
    setsockopt(fd, IPPROTO_TCP, TCP_KEEPALIVE, (const void *)&keepidle, sizeof(keepidle));

    // Repeat probe every 10 seconds if unacknowledged
    int keepintvl = 10;
    setsockopt(fd, IPPROTO_TCP, TCP_KEEPINTVL, (const void *)&keepintvl, sizeof(keepintvl));

    // Drop only after 12 unacknowledged probes (~140s tolerance for temporary cellular/Wi-Fi handovers)
    int keepcnt = 12;
    setsockopt(fd, IPPROTO_TCP, TCP_KEEPCNT, (const void *)&keepcnt, sizeof(keepcnt));
#endif

    // 4. Increase socket buffer sizes to 128KB for smooth data throughput
    int bufsize = 131072;
    setsockopt(fd, SOL_SOCKET, SO_SNDBUF, (const void *)&bufsize, sizeof(bufsize));
    setsockopt(fd, SOL_SOCKET, SO_RCVBUF, (const void *)&bufsize, sizeof(bufsize));
}

static const char b64_table[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

static void base64_encode(const unsigned char *src, size_t len, char *out) {
    size_t i = 0, j = 0;
    for (; i < len; i += 3) {
        unsigned int val = (src[i] << 16);
        if (i + 1 < len) val |= (src[i + 1] << 8);
        if (i + 2 < len) val |= src[i + 2];

        out[j++] = b64_table[(val >> 18) & 0x3F];
        out[j++] = b64_table[(val >> 12) & 0x3F];
        out[j++] = (i + 1 < len) ? b64_table[(val >> 6) & 0x3F] : '=';
        out[j++] = (i + 2 < len) ? b64_table[val & 0x3F] : '=';
    }
    out[j] = '\0';
}

void decade_proxy_track_socket(int slot, int fd) {
    if (slot < 0 || slot >= JVM_BRIDGE_MAX_SLOTS || fd < 0) return;
    decade_network_optimize_socket(fd);
    pthread_mutex_lock(&g_sock_lock);
    int count = g_slot_socket_counts[slot];
    if (count < MAX_SLOT_SOCKETS) {
        g_slot_sockets[slot][count] = fd;
        g_slot_socket_counts[slot] = count + 1;
    }
    pthread_mutex_unlock(&g_sock_lock);
}

void decade_proxy_untrack_socket(int slot, int fd) {
    if (slot < 0 || slot >= JVM_BRIDGE_MAX_SLOTS || fd < 0) return;
    pthread_mutex_lock(&g_sock_lock);
    int count = g_slot_socket_counts[slot];
    for (int i = 0; i < count; i++) {
        if (g_slot_sockets[slot][i] == fd) {
            g_slot_sockets[slot][i] = g_slot_sockets[slot][count - 1];
            g_slot_socket_counts[slot] = count - 1;
            break;
        }
    }
    pthread_mutex_unlock(&g_sock_lock);
}

void decade_proxy_disconnect_slot_sockets(int slot) {
    if (slot < 0 || slot >= JVM_BRIDGE_MAX_SLOTS) return;
    pthread_mutex_lock(&g_sock_lock);
    int count = g_slot_socket_counts[slot];
    printf("[ProxyTunnel] Disconnecting %d active sockets for slot %d\n", count, slot);
    for (int i = 0; i < count; i++) {
        int fd = g_slot_sockets[slot][i];
        if (fd >= 0) {
            shutdown(fd, SHUT_RDWR);
            close(fd);
        }
    }
    g_slot_socket_counts[slot] = 0;
    pthread_mutex_unlock(&g_sock_lock);
}

int decade_proxy_connect(void *runtime_or_jvm, mbedtls_net_context *ctx, const char *target_host, const char *target_port, int proto) {
    // 1. Resolve server destination override ("Thay IP Phiên Bản") FIRST
    char eff_host[256] = {0};
    char eff_port[16] = {0};
    jvm_bridge_resolve_server_destination(target_host, target_port, eff_host, sizeof(eff_host), eff_port, sizeof(eff_port));

    // 2. Extract slot and tab prefix from Runtime or MiniJVM
    int slot = 0;
    char tab_prefix[64] = {0};

    Runtime *runtime = (Runtime *)runtime_or_jvm;
    if (runtime && runtime->jvm) {
        slot = jvm_bridge_get_jvm_slot(runtime->jvm);

        // Walk call stack to extract game class prefix (TabResolver matching APK 1:1)
        Runtime *r = runtime;
        while (r) {
            if (r->clazz && r->clazz->name) {
                const char *cname = utf8_cstr(r->clazz->name);
                if (cname &&
                    strncmp(cname, "java/", 5) != 0 &&
                    strncmp(cname, "javax/", 6) != 0 &&
                    strncmp(cname, "org/microemu/", 13) != 0 &&
                    strncmp(cname, "org/mini/", 9) != 0 &&
                    strncmp(cname, "com/sun/", 8) != 0) {

                    // e.g. "a/bs" -> prefix is "a"
                    // "b/GameScr" -> prefix is "b"
                    const char *slash = strchr(cname, '/');
                    if (slash) {
                        int len = (int)(slash - cname);
                        if (len > 0 && len < (int)sizeof(tab_prefix)) {
                            strncpy(tab_prefix, cname, len);
                            tab_prefix[len] = '\0';
                        }
                    } else {
                        // Class in default package, e.g. "bs"
                        strncpy(tab_prefix, cname, sizeof(tab_prefix) - 1);
                    }
                    break;
                }
            }
            r = r->parent;
        }
    } else {
        slot = jvm_bridge_get_jvm_slot(runtime_or_jvm);
    }

    int ptype = DECADE_PROXY_TYPE_DIRECT;
    char phost[256] = {0};
    int pport = 0;
    char puser[128] = {0};
    char ppass[128] = {0};

    // Priority 1: Check for Tab-specific proxy
    int has_proxy = 0;
    if (tab_prefix[0] != '\0') {
        has_proxy = jvm_bridge_get_tab_proxy(slot, tab_prefix, &ptype, phost, sizeof(phost), &pport, puser, sizeof(puser), ppass, sizeof(ppass));
        if (has_proxy) {
            printf("[ProxyTunnel] Slot %d, Tab prefix '%s' -> using TAB PROXY %s:%d (type=%d)\n",
                   slot, tab_prefix, phost, pport, ptype);
        }
    }

    // Priority 2: Fallback to Screen default proxy
    if (!has_proxy) {
        has_proxy = jvm_bridge_get_slot_proxy(slot, &ptype, phost, sizeof(phost), &pport, puser, sizeof(puser), ppass, sizeof(ppass));
        if (has_proxy) {
            printf("[ProxyTunnel] Slot %d, Tab prefix '%s' -> fallback to SCREEN PROXY %s:%d (type=%d)\n",
                   slot, tab_prefix, phost, pport, ptype);
        }
    }

    if (!has_proxy || ptype < 0 || pport <= 0 || phost[0] == '\0') {
        // Direct connection without proxy to eff_host:eff_port
        printf("[ProxyTunnel] Slot %d, Tab prefix '%s' -> DIRECT CONNECT to %s:%s\n", slot, tab_prefix, eff_host, eff_port);
        int ret = mbedtls_net_connect(ctx, eff_host, eff_port, proto);
        if (ret == 0 && ctx->fd >= 0) {
            decade_proxy_track_socket(slot, ctx->fd);
        }
        return ret;
    }

    printf("[ProxyTunnel] Slot %d, Tab '%s' routing to %s:%s via proxy %s:%d (type=%d)\n",
           slot, tab_prefix, eff_host, eff_port, phost, pport, ptype);

    char pport_str[16];
    snprintf(pport_str, sizeof(pport_str), "%d", pport);
    int ret = mbedtls_net_connect(ctx, phost, pport_str, proto);
    if (ret != 0) {
        printf("[ProxyTunnel] ERROR: Failed to connect to proxy %s:%d (code %d)\n", phost, pport, ret);
        return ret;
    }

    // Set connection timeout on socket for handshake
    struct timeval tv = {10, 0};
    setsockopt(ctx->fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
    setsockopt(ctx->fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));

    if (ptype == DECADE_PROXY_TYPE_SOCKS5) {
        // --- SOCKS5 Handshake ---
        unsigned char greeting[4];
        int glen = 0;
        greeting[glen++] = 0x05;
        if (puser[0] != '\0') {
            greeting[glen++] = 0x02; // 2 methods: NO_AUTH(0x00), USER_PASS(0x02)
            greeting[glen++] = 0x00;
            greeting[glen++] = 0x02;
        } else {
            greeting[glen++] = 0x01; // 1 method: NO_AUTH(0x00)
            greeting[glen++] = 0x00;
        }

        if (send(ctx->fd, greeting, glen, 0) != glen) {
            mbedtls_net_free(ctx);
            return -1;
        }

        unsigned char gresp[2];
        if (recv(ctx->fd, gresp, 2, MSG_WAITALL) != 2 || gresp[0] != 0x05) {
            mbedtls_net_free(ctx);
            return -2;
        }

        if (gresp[1] == 0x02) {
            // Username / Password authentication RFC 1929
            unsigned char auth[512];
            int apos = 0;
            int ulen = (int)strlen(puser);
            int plen = (int)strlen(ppass);
            auth[apos++] = 0x01; // subnegotiation version
            auth[apos++] = (unsigned char)ulen;
            memcpy(auth + apos, puser, ulen); apos += ulen;
            auth[apos++] = (unsigned char)plen;
            memcpy(auth + apos, ppass, plen); apos += plen;

            if (send(ctx->fd, auth, apos, 0) != apos) {
                mbedtls_net_free(ctx);
                return -3;
            }
            unsigned char aresp[2];
            if (recv(ctx->fd, aresp, 2, MSG_WAITALL) != 2 || aresp[1] != 0x00) {
                printf("[ProxyTunnel] SOCKS5 auth failed for proxy %s:%d\n", phost, pport);
                mbedtls_net_free(ctx);
                return -4;
            }
        } else if (gresp[1] != 0x00) {
            printf("[ProxyTunnel] SOCKS5 unsupported auth method: 0x%02x\n", gresp[1]);
            mbedtls_net_free(ctx);
            return -5;
        }

        // Send SOCKS5 CONNECT command (domain name address type 0x03)
        unsigned char cmd[512];
        int cpos = 0;
        cmd[cpos++] = 0x05; // VER
        cmd[cpos++] = 0x01; // CMD: CONNECT
        cmd[cpos++] = 0x00; // RSV
        cmd[cpos++] = 0x03; // ATYP: DOMAINNAME
        int dlen = (int)strlen(eff_host);
        if (dlen > 255) dlen = 255;
        cmd[cpos++] = (unsigned char)dlen;
        memcpy(cmd + cpos, eff_host, dlen); cpos += dlen;
        int tport = atoi(eff_port);
        cmd[cpos++] = (unsigned char)((tport >> 8) & 0xFF);
        cmd[cpos++] = (unsigned char)(tport & 0xFF);

        if (send(ctx->fd, cmd, cpos, 0) != cpos) {
            mbedtls_net_free(ctx);
            return -6;
        }

        unsigned char cresp[4];
        if (recv(ctx->fd, cresp, 4, MSG_WAITALL) != 4 || cresp[0] != 0x05 || cresp[1] != 0x00) {
            printf("[ProxyTunnel] SOCKS5 connect rejected, rep=0x%02x\n", cresp[1]);
            mbedtls_net_free(ctx);
            return -7;
        }

        // Drain the BND.ADDR and BND.PORT bytes
        if (cresp[3] == 0x01) { // IPv4
            unsigned char buf[6]; recv(ctx->fd, buf, 6, MSG_WAITALL);
        } else if (cresp[3] == 0x03) { // Domain
            unsigned char len = 0; recv(ctx->fd, &len, 1, 0);
            unsigned char buf[260]; recv(ctx->fd, buf, len + 2, MSG_WAITALL);
        } else if (cresp[3] == 0x04) { // IPv6
            unsigned char buf[18]; recv(ctx->fd, buf, 18, MSG_WAITALL);
        }

        // Reset timeouts back to default
        struct timeval zero_tv = {0, 0};
        setsockopt(ctx->fd, SOL_SOCKET, SO_RCVTIMEO, &zero_tv, sizeof(zero_tv));
        setsockopt(ctx->fd, SOL_SOCKET, SO_SNDTIMEO, &zero_tv, sizeof(zero_tv));

        decade_proxy_track_socket(slot, ctx->fd);
        printf("[ProxyTunnel] SOCKS5 tunnel established successfully to %s:%s\n", eff_host, eff_port);
        return 0;

    } else if (ptype == DECADE_PROXY_TYPE_HTTP) {
        // --- HTTP CONNECT Handshake ---
        char req[1024];
        if (puser[0] != '\0') {
            char auth_raw[256];
            snprintf(auth_raw, sizeof(auth_raw), "%s:%s", puser, ppass);
            char auth_b64[512];
            base64_encode((unsigned char *)auth_raw, strlen(auth_raw), auth_b64);
            snprintf(req, sizeof(req),
                     "CONNECT %s:%s HTTP/1.1\r\n"
                     "Host: %s:%s\r\n"
                     "Proxy-Authorization: Basic %s\r\n"
                     "Proxy-Connection: keep-alive\r\n\r\n",
                     eff_host, eff_port, eff_host, eff_port, auth_b64);
        } else {
            snprintf(req, sizeof(req),
                     "CONNECT %s:%s HTTP/1.1\r\n"
                     "Host: %s:%s\r\n"
                     "Proxy-Connection: keep-alive\r\n\r\n",
                     eff_host, eff_port, eff_host, eff_port);
        }

        int req_len = (int)strlen(req);
        if (send(ctx->fd, req, req_len, 0) != req_len) {
            mbedtls_net_free(ctx);
            return -8;
        }

        char resp[1024];
        int total = 0;
        while (total < (int)sizeof(resp) - 1) {
            int n = (int)recv(ctx->fd, resp + total, 1, 0);
            if (n <= 0) break;
            total += n;
            resp[total] = '\0';
            if (strstr(resp, "\r\n\r\n") != NULL) break;
        }

        if (strstr(resp, " 200 ") != NULL || strstr(resp, " 200\r\n") != NULL) {
            struct timeval zero_tv = {0, 0};
            setsockopt(ctx->fd, SOL_SOCKET, SO_RCVTIMEO, &zero_tv, sizeof(zero_tv));
            setsockopt(ctx->fd, SOL_SOCKET, SO_SNDTIMEO, &zero_tv, sizeof(zero_tv));

            decade_proxy_track_socket(slot, ctx->fd);
            printf("[ProxyTunnel] HTTP CONNECT tunnel established to %s:%s\n", eff_host, eff_port);
            return 0;
        }

        printf("[ProxyTunnel] HTTP CONNECT failed: %s\n", resp);
        mbedtls_net_free(ctx);
        return -9;
    }

    return -10;
}
