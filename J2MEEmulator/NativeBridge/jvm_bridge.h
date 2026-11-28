#ifndef JVM_BRIDGE_H
#define JVM_BRIDGE_H

#ifdef __cplusplus
extern "C" {
#endif

#define JVM_BRIDGE_MAX_SLOTS 32

/// 3D supersampling scale factor (shared by M3G and MascotCapsule).
/// Set by jvm_bridge_init, read by j2me_m3g_jni.c and MC3D via system property.
extern int g_render_3d_scale;

// ============================================================
// Multi-slot JVM lifecycle
// ============================================================

/// Initialize a slot from 0 through JVM_BRIDGE_MAX_SLOTS - 1.
int jvm_bridge_init_slot(int slot, const char *res_root, const char *save_root, const char *midlet_jar,
                         int screen_width, int screen_height, int render_3d_scale,
                         int fps_limit);

/// Run a MIDlet in a specific slot session via MIDletRunner.
int jvm_bridge_run_midlet_slot(int slot, const char *midlet_jar_path);

/// Free a stopped slot. If it is still initializing or running, request stop first.
void jvm_bridge_destroy_slot(int slot);

/// Destroy all active slot sessions.
void jvm_bridge_destroy_all(void);

// ============================================================
// Slot focus & identification
// ============================================================

/// Set the currently focused slot (which receives input and renders to main screen).
void jvm_bridge_set_focused_slot(int slot);

/// Get the currently focused slot index.
int jvm_bridge_get_focused_slot(void);

/// Determine which slot index owns the given MiniJVM pointer.
int jvm_bridge_get_jvm_slot(void *jvm_ptr);
int jvm_bridge_find_jvm_slot(void *jvm_ptr);
int jvm_bridge_get_active_slot_count(void);
int jvm_bridge_is_jvm_visible(void *jvm_ptr);
void jvm_bridge_adjust_native_heap(int slot, void *expected_jvm, long long delta);

// ============================================================
// Slot control & status
// ============================================================

/// Request graceful MIDlet stop for a slot.
void jvm_bridge_request_stop_slot(int slot);

/// Request graceful MIDlet stop for all slots.
void jvm_bridge_request_stop_all(void);

/// Check if stop has been requested for a slot.
int jvm_bridge_is_slot_stop_requested(int slot);

/// Check if a slot is currently active and running.
int jvm_bridge_is_slot_running(int slot);

// ============================================================
// Per-slot & Per-tab proxy configuration (SOCKS5 / HTTP)
// ============================================================

/// Configure screen default proxy for a slot.
/// @param type 0 = SOCKS5, 1 = HTTP CONNECT, -1 = DIRECT (no proxy)
void jvm_bridge_set_slot_proxy(int slot, int type, const char *host, int port, const char *user, const char *pass);

/// Get configured screen default proxy for a slot. Returns 1 if proxy is active, 0 if direct.
int jvm_bridge_get_slot_proxy(int slot, int *out_type, char *out_host, int host_len, int *out_port, char *out_user, int user_len, char *out_pass, int pass_len);

/// Configure tab-specific proxy for an internal game tab (prefix e.g. "a", "b", "1").
void jvm_bridge_set_tab_proxy(int slot, const char *tab_prefix, int type, const char *host, int port, const char *user, const char *pass);

/// Get tab-specific proxy. Returns 1 if found, 0 if not configured.
int jvm_bridge_get_tab_proxy(int slot, const char *tab_prefix, int *out_type, char *out_host, int host_len, int *out_port, char *out_user, int user_len, char *out_pass, int pass_len);

/// Clear all tab-specific proxies for a slot.
void jvm_bridge_clear_tab_proxies(int slot);

/// Forcibly disconnect active network sockets for a slot (to reconnect over new proxy).
void jvm_bridge_disconnect_slot_sockets(int slot);

/// Re-apply keepalive & Voice QoS options across all active game sockets.
void jvm_bridge_refresh_all_sockets(void);

// ============================================================
// Server Destination Override ("Thay IP Phiên Bản")
// ============================================================

/// Set global server destination override (changes game server target IP & Port).
void jvm_bridge_set_server_override(int enabled, const char *host, int port);

/// Add a specific server redirection rule (e.g. old_ip: "27.0.14.73" -> new_ip: "103.179.188.45", port: 14444).
void jvm_bridge_add_server_redirect_rule(const char *old_ip, const char *new_ip, int port);

/// Clear all specific server redirection rules.
void jvm_bridge_clear_server_redirect_rules(void);

/// Resolve effective destination host and port. Returns 1 if redirected, 0 if unchanged.
int jvm_bridge_resolve_server_destination(const char *in_host, const char *in_port, char *out_host, int out_host_len, char *out_port, int out_port_len);

// ============================================================
// Backward compatibility wrappers (default to slot 0)
// ============================================================

int jvm_bridge_init(const char *res_root, const char *save_root, const char *midlet_jar,
                    int screen_width, int screen_height, int render_3d_scale,
                    int fps_limit);

int jvm_bridge_run_midlet(const char *midlet_jar_path);

void jvm_bridge_destroy(void);

void jvm_bridge_set_save_root(const char *save_root);

void jvm_bridge_request_stop(void);

int jvm_bridge_is_stop_requested(void);

/// Trigger immediate full MiniJVM GC across all slots, purge render dead shells,
/// and return freed malloc heap pages back to iOS kernel (prevents Jetsam kills during long AFK).
void jvm_bridge_clean_ram(void);

/// Query current physical RAM footprint of this process in kilobytes (KB).
long long jvm_bridge_get_used_ram_kb(void);

/// Query current CPU usage percentage of this process (0.0 - 100.0 * cores).
double jvm_bridge_get_cpu_usage_percent(void);

/// Record/query first abnormal jthread_waitTime spin/error event for Flight Recorder diagnostics.
void jvm_bridge_record_wait_diag(const char *caller_cls, const char *caller_method, long long waitms, int wret, int save_count, int reason_code);
void jvm_bridge_copy_wait_diag(char *out_buf, int out_len);

#ifdef __cplusplus
}
#endif

#endif /* JVM_BRIDGE_H */
