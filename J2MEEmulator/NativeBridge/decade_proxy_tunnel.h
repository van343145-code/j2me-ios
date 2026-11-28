#ifndef DECADE_PROXY_TUNNEL_H
#define DECADE_PROXY_TUNNEL_H

#include "../minijvm/utils/https/mbedtls/include/mbedtls/net_sockets.h"

#ifdef __cplusplus
extern "C" {
#endif

#define DECADE_PROXY_TYPE_DIRECT -1
#define DECADE_PROXY_TYPE_SOCKS5 0
#define DECADE_PROXY_TYPE_HTTP   1

/// Connect a socket context to target host:port, tunneling through slot's proxy if configured.
/// Returns 0 on success, negative error code on failure.
int decade_proxy_connect(void *jvm, mbedtls_net_context *ctx, const char *target_host, const char *target_port, int proto);

/// Track an active socket descriptor for a slot.
void decade_proxy_track_socket(int slot, int fd);

/// Untrack a socket descriptor.
void decade_proxy_untrack_socket(int slot, int fd);

/// Disconnect all active sockets for a slot.
void decade_proxy_disconnect_slot_sockets(int slot);

/// Optimize a socket descriptor with low-latency TCP_NODELAY, keep-alive probes,
/// SO_NOSIGPIPE, Voice QoS traffic class and high-throughput buffer sizes.
void decade_network_optimize_socket(int fd);

/// Re-apply keepalive & Voice QoS options across all currently tracked live sockets
/// (e.g. on screen lock or Wi-Fi/5G handover).
void decade_proxy_refresh_all_sockets(void);

#ifdef __cplusplus
}
#endif

#endif /* DECADE_PROXY_TUNNEL_H */
