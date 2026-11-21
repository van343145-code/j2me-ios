#include "jvm_bridge.h"
#include "jvm.h"
#include "jvm_util.h"
#include "garbage.h"
#include "j2me_render.h"
#include "j2me_input.h"
#include "j2me_ui.h"
#include "j2me_audio.h"
#include "j2me_micro3d_gl.h"
#include "m3g/j2me_m3g.h"
#include "decade_proxy_tunnel.h"
#include <stdio.h>
#include <string.h>
#include <stdatomic.h>
#include <pthread.h>

#include <stdlib.h>
#include <strings.h>
#include <ctype.h>
#include <unistd.h>
#if defined(__APPLE__) || defined(__MACH__)
#include <mach/mach.h>
#include <malloc/malloc.h>
#endif

#define MAX_TAB_PROXIES 64
#define MAX_SERVER_RULES 32

typedef struct {
    char tab_prefix[64];
    int type; // 0=SOCKS5, 1=HTTP, -1=DIRECT
    char host[128];
    int port;
    char user[64];
    char pass[64];
} TabProxyRule;

typedef struct {
    char old_ip[128];
    char new_ip[128];
    int port;
} ServerRedirectRule;

typedef struct {
    int type; // 0=SOCKS5, 1=HTTP, -1=DIRECT
    char host[256];
    int port;
    char user[128];
    char pass[128];
} SlotProxy;

typedef struct {
    MiniJVM *jvm;
    void *retiring_jvm;
    int initializing;
    int executing;
    atomic_int stop_requested;
    atomic_int is_running;
    char jar_path[1024];
    char save_root[1024];
    SlotProxy proxy;
    TabProxyRule tab_proxies[MAX_TAB_PROXIES];
    int tab_proxy_count;
} SlotSessionNative;

static SlotSessionNative g_slots[JVM_BRIDGE_MAX_SLOTS];
static atomic_int g_focused_slot = 0;
static pthread_mutex_t g_slots_lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_mutex_t g_init_lock = PTHREAD_MUTEX_INITIALIZER;

/* Server Destination Override ("Thay IP Phiên Bản") */
static int g_server_override_enabled = 0;
static char g_server_override_host[128] = {0};
static int g_server_override_port = 0;
static ServerRedirectRule g_server_rules[MAX_SERVER_RULES];
static int g_server_rules_count = 0;
static pthread_mutex_t g_server_override_lock = PTHREAD_MUTEX_INITIALIZER;

/* 3D supersampling scale — shared by M3G (reads directly) and MC3D (via system property) */
int g_render_3d_scale = 1;

void jvm_bridge_set_focused_slot(int slot) {
    if (slot >= 0 && slot < JVM_BRIDGE_MAX_SLOTS) {
        atomic_store(&g_focused_slot, slot);
        printf("[JVM Bridge] Switched focused slot to %d\n", slot);
    }
}

int jvm_bridge_get_focused_slot(void) {
    return atomic_load(&g_focused_slot);
}

int jvm_bridge_find_jvm_slot(void *jvm_ptr) {
    if (!jvm_ptr) return -1;
    pthread_mutex_lock(&g_slots_lock);
    for (int i = 0; i < JVM_BRIDGE_MAX_SLOTS; i++) {
        if (g_slots[i].jvm == jvm_ptr || g_slots[i].retiring_jvm == jvm_ptr) {
            pthread_mutex_unlock(&g_slots_lock);
            return i;
        }
    }
    pthread_mutex_unlock(&g_slots_lock);
    return -1;
}

int jvm_bridge_get_jvm_slot(void *jvm_ptr) {
    int slot = jvm_bridge_find_jvm_slot(jvm_ptr);
    return slot < 0 ? 0 : slot;
}

static void finish_slot_initialization(int slot) {
    pthread_mutex_lock(&g_slots_lock);
    g_slots[slot].initializing = 0;
    pthread_mutex_unlock(&g_slots_lock);
    pthread_mutex_unlock(&g_init_lock);
}

int jvm_bridge_init_slot(int slot, const char *res_root, const char *save_root, const char *midlet_jar,
                         int screen_width, int screen_height, int render_3d_scale,
                         int fps_limit) {
    if (slot < 0 || slot >= JVM_BRIDGE_MAX_SLOTS) {
        printf("[JVM Bridge] ERROR: Invalid slot index %d\n", slot);
        return -1;
    }

    pthread_mutex_lock(&g_slots_lock);
    if (g_slots[slot].jvm || g_slots[slot].initializing || g_slots[slot].retiring_jvm) {
        printf("[JVM Bridge] Slot %d is in use\n", slot);
        pthread_mutex_unlock(&g_slots_lock);
        return -1;
    }
    g_slots[slot].initializing = 1;
    atomic_store(&g_slots[slot].stop_requested, 0);
    pthread_mutex_unlock(&g_slots_lock);

    // One JVM initializes at a time without blocking input, rendering or stop requests.
    pthread_mutex_lock(&g_init_lock);
    if (jvm_bridge_is_slot_stop_requested(slot)) {
        finish_slot_initialization(slot);
        return -4;
    }

    char bootclasspath[1024];
    snprintf(bootclasspath, sizeof(bootclasspath), "%s/minijvm_rt.jar", res_root);

    char classpath[4096];
    snprintf(classpath, sizeof(classpath), "%s/j2me_api.jar:%s", res_root, midlet_jar);

    printf("[JVM Bridge] Slot %d initializing with classpath: %s\n", slot, classpath);

    MiniJVM *jvm = jvm_create();
    if (!jvm) {
        printf("[JVM Bridge] ERROR: jvm_create() failed for slot %d\n", slot);
        finish_slot_initialization(slot);
        return -2;
    }

    jvm->jdwp_enable = 0;
    jvm->jdwp_suspend_on_start = 0;
    jvm->max_heap_size = 32 * 1024 * 1024;
    jvm->garbage_collect_period_ms = 4000;
    jvm->heap_overload_percent = 50;

    s32 ret = jvm_init(jvm, (c8 *)bootclasspath, (c8 *)classpath);
    if (ret) {
        printf("[JVM Bridge] ERROR: jvm_init() failed for slot %d (code %d)\n", slot, ret);
        jvm_destroy(jvm);
        finish_slot_initialization(slot);
        return -3;
    }

    // Register native methods for this slot's JVM instance
    j2me_render_reg_natives(jvm);
    j2me_input_reg_natives(jvm);
    j2me_ui_reg_natives(jvm);
    j2me_audio_reg_natives(jvm);
    j2me_micro3d_gl_reg_natives(jvm);
    j2me_m3g_reg_natives(jvm);

    // System properties (Standard J2ME MIDP 2.0 + CLDC 1.1 + JSR-75 FileConnection + MMAPI)
    sys_properties_set_c(jvm, "os.name", "iOS");
    sys_properties_set_c(jvm, "app.save.root", (c8 *)save_root);
    sys_properties_set_c(jvm, "microedition.platform", "NokiaN73/2.0");
    sys_properties_set_c(jvm, "microedition.encoding", "UTF-8");
    sys_properties_set_c(jvm, "microedition.locale", "vi-VN");
    sys_properties_set_c(jvm, "microedition.profiles", "MIDP-2.0");
    sys_properties_set_c(jvm, "microedition.configuration", "CLDC-1.1");
    sys_properties_set_c(jvm, "microedition.io.file.FileConnection.version", "1.0");
    sys_properties_set_c(jvm, "microedition.media.version", "1.1");
    sys_properties_set_c(jvm, "microedition.m3g.version", "1.1");
    sys_properties_set_c(jvm, "supports.mixing", "true");
    sys_properties_set_c(jvm, "supports.audio.capture", "false");
    sys_properties_set_c(jvm, "supports.video.capture", "false");
    sys_properties_set_c(jvm, "supports.recording", "false");

    char fileconn_dir[1152];
    snprintf(fileconn_dir, sizeof(fileconn_dir), "file://%s/", save_root);
    sys_properties_set_c(jvm, "fileconn.dir.memorycard", fileconn_dir);
    sys_properties_set_c(jvm, "fileconn.dir.photos", fileconn_dir);
    sys_properties_set_c(jvm, "fileconn.dir.videos", fileconn_dir);
    sys_properties_set_c(jvm, "fileconn.dir.tones", fileconn_dir);
    sys_properties_set_c(jvm, "fileconn.dir.music", fileconn_dir);
    sys_properties_set_c(jvm, "fileconn.dir.roots.names", "MemoryCard");

    char inst_str[16];
    snprintf(inst_str, sizeof(inst_str), "%d", slot + 1);
    sys_properties_set_c(jvm, "com.nokia.mid.cmdline.instance", inst_str);

    char sw[16], sh[16];
    snprintf(sw, sizeof(sw), "%d", screen_width);
    snprintf(sh, sizeof(sh), "%d", screen_height);
    sys_properties_set_c(jvm, "j2me.screen.width", sw);
    sys_properties_set_c(jvm, "j2me.screen.height", sh);

    g_render_3d_scale = render_3d_scale > 0 ? render_3d_scale : 1;
    char ss[8];
    snprintf(ss, sizeof(ss), "%d", g_render_3d_scale);
    sys_properties_set_c(jvm, "micro3d.v3.fbo.scale", ss);

    if (fps_limit > 0) {
        char fl[8];
        snprintf(fl, sizeof(fl), "%d", fps_limit);
        sys_properties_set_c(jvm, "j2me.fps.limit", fl);
    }

    pthread_mutex_lock(&g_slots_lock);
    g_slots[slot].jvm = jvm;
    atomic_store(&g_slots[slot].is_running, 1);
    snprintf(g_slots[slot].jar_path, sizeof(g_slots[slot].jar_path), "%s", midlet_jar);
    snprintf(g_slots[slot].save_root, sizeof(g_slots[slot].save_root), "%s", save_root);

    pthread_mutex_unlock(&g_slots_lock);
    finish_slot_initialization(slot);
    printf("[JVM Bridge] Slot %d JVM initialized successfully\n", slot);
    return 0;
}

int jvm_bridge_run_midlet_slot(int slot, const char *midlet_jar_path) {
    if (slot < 0 || slot >= JVM_BRIDGE_MAX_SLOTS) return -1;
    pthread_mutex_lock(&g_slots_lock);
    MiniJVM *jvm = g_slots[slot].jvm;
    if (jvm_bridge_is_slot_stop_requested(slot)) {
        pthread_mutex_unlock(&g_slots_lock);
        return 0;
    }
    if (!jvm || g_slots[slot].executing) {
        pthread_mutex_unlock(&g_slots_lock);
        printf("[JVM Bridge] ERROR: Slot %d not ready to run\n", slot);
        return -1;
    }
    g_slots[slot].executing = 1;
    pthread_mutex_unlock(&g_slots_lock);

    printf("[JVM Bridge] Slot %d executing MIDlet from: %s\n", slot, midlet_jar_path);

    ArrayList *java_para = arraylist_create(0);
    arraylist_push_back(java_para, (void *)midlet_jar_path);

    s32 ret = call_main(jvm, (c8 *)"javax/microedition/shell/MIDletRunner", java_para);
    arraylist_destroy(java_para);

    pthread_mutex_lock(&g_slots_lock);
    g_slots[slot].executing = 0;
    atomic_store(&g_slots[slot].is_running, 0);
    pthread_mutex_unlock(&g_slots_lock);
    printf("[JVM Bridge] Slot %d MIDlet finished with code %d\n", slot, ret);
    return ret;
}

void jvm_bridge_destroy_slot(int slot) {
    if (slot < 0 || slot >= JVM_BRIDGE_MAX_SLOTS) return;

    pthread_mutex_lock(&g_slots_lock);
    if (g_slots[slot].executing || g_slots[slot].initializing) {
        atomic_store(&g_slots[slot].stop_requested, 1);
        pthread_mutex_unlock(&g_slots_lock);
        return;
    }
    MiniJVM *jvm = g_slots[slot].jvm;
    if (jvm) {
        // Native callbacks can still arrive while the JVM threads are joining.
        g_slots[slot].retiring_jvm = jvm;
        g_slots[slot].jvm = NULL;
        atomic_store(&g_slots[slot].is_running, 0);
        atomic_store(&g_slots[slot].stop_requested, 1);
        pthread_mutex_unlock(&g_slots_lock);

        printf("[JVM Bridge] Destroying slot %d JVM\n", slot);
        decade_proxy_disconnect_slot_sockets(slot);

        if (jvm->collector) {
            jvm->collector->exit_flag = 1;
        }
        thread_stop_all(jvm);
        jvm_destroy(jvm);
        j2me_ui_reset_slot(slot);
        pthread_mutex_lock(&g_slots_lock);
        g_slots[slot].retiring_jvm = NULL;
        pthread_mutex_unlock(&g_slots_lock);
        return;
    }
    pthread_mutex_unlock(&g_slots_lock);
}

void jvm_bridge_destroy_all(void) {
    printf("[JVM Bridge] Destroying all slots\n");
    j2me_render_stop();

    for (int i = 0; i < JVM_BRIDGE_MAX_SLOTS; i++) {
        jvm_bridge_destroy_slot(i);
    }

    j2me_input_reset();
    j2me_audio_stop_all();
    j2me_micro3d_gl_cleanup();
    j2me_m3g_cleanup();
    j2me_render_cleanup();
    atomic_store(&g_focused_slot, 0);
}

void jvm_bridge_request_stop_slot(int slot) {
    if (slot >= 0 && slot < JVM_BRIDGE_MAX_SLOTS) {
        atomic_store(&g_slots[slot].stop_requested, 1);
        printf("[JVM Bridge] Stop requested for slot %d\n", slot);
    }
}

void jvm_bridge_request_stop_all(void) {
    printf("[JVM Bridge] Requesting stop for ALL slots\n");
    for (int i = 0; i < JVM_BRIDGE_MAX_SLOTS; i++) {
        atomic_store(&g_slots[i].stop_requested, 1);
        pthread_mutex_lock(&g_slots_lock);
        MiniJVM *jvm = g_slots[i].jvm;
        if (jvm && jvm->collector) {
            jvm->collector->exit_flag = 1;
        }
        pthread_mutex_unlock(&g_slots_lock);
    }
}

int jvm_bridge_is_slot_stop_requested(int slot) {
    if (slot >= 0 && slot < JVM_BRIDGE_MAX_SLOTS) {
        return atomic_load(&g_slots[slot].stop_requested);
    }
    return 0;
}

int jvm_bridge_is_slot_running(int slot) {
    if (slot >= 0 && slot < JVM_BRIDGE_MAX_SLOTS) {
        return atomic_load(&g_slots[slot].is_running);
    }
    return 0;
}

void jvm_bridge_set_slot_proxy(int slot, int type, const char *host, int port, const char *user, const char *pass) {
    if (slot < 0 || slot >= JVM_BRIDGE_MAX_SLOTS) return;
    pthread_mutex_lock(&g_slots_lock);
    g_slots[slot].proxy.type = type;
    if (host) {
        snprintf(g_slots[slot].proxy.host, sizeof(g_slots[slot].proxy.host), "%s", host);
    } else {
        g_slots[slot].proxy.host[0] = '\0';
    }
    g_slots[slot].proxy.port = port;
    if (user) {
        snprintf(g_slots[slot].proxy.user, sizeof(g_slots[slot].proxy.user), "%s", user);
    } else {
        g_slots[slot].proxy.user[0] = '\0';
    }
    if (pass) {
        snprintf(g_slots[slot].proxy.pass, sizeof(g_slots[slot].proxy.pass), "%s", pass);
    } else {
        g_slots[slot].proxy.pass[0] = '\0';
    }
    pthread_mutex_unlock(&g_slots_lock);
    printf("[JVM Bridge] Slot %d proxy set: type=%d %s:%d (user=%s)\n",
           slot, type, host ? host : "direct", port, user ? user : "none");
}

int jvm_bridge_get_slot_proxy(int slot, int *out_type, char *out_host, int host_len, int *out_port, char *out_user, int user_len, char *out_pass, int pass_len) {
    if (slot < 0 || slot >= JVM_BRIDGE_MAX_SLOTS) return 0;
    pthread_mutex_lock(&g_slots_lock);
    if (g_slots[slot].proxy.type < 0 || g_slots[slot].proxy.port <= 0 || g_slots[slot].proxy.host[0] == '\0') {
        pthread_mutex_unlock(&g_slots_lock);
        return 0;
    }
    if (out_type) *out_type = g_slots[slot].proxy.type;
    if (out_port) *out_port = g_slots[slot].proxy.port;
    if (out_host && host_len > 0) snprintf(out_host, host_len, "%s", g_slots[slot].proxy.host);
    if (out_user && user_len > 0) snprintf(out_user, user_len, "%s", g_slots[slot].proxy.user);
    if (out_pass && pass_len > 0) snprintf(out_pass, pass_len, "%s", g_slots[slot].proxy.pass);
    pthread_mutex_unlock(&g_slots_lock);
    return 1;
}

void jvm_bridge_disconnect_slot_sockets(int slot) {
    decade_proxy_disconnect_slot_sockets(slot);
}

// ============================================================
// Per-Tab Proxy Routing Implementation
// ============================================================

void jvm_bridge_set_tab_proxy(int slot, const char *tab_prefix, int type, const char *host, int port, const char *user, const char *pass) {
    if (slot < 0 || slot >= JVM_BRIDGE_MAX_SLOTS || !tab_prefix || tab_prefix[0] == '\0') return;
    pthread_mutex_lock(&g_slots_lock);

    // Look for existing tab rule
    int target_idx = -1;
    for (int i = 0; i < g_slots[slot].tab_proxy_count; i++) {
        if (strcasecmp(g_slots[slot].tab_proxies[i].tab_prefix, tab_prefix) == 0) {
            target_idx = i;
            break;
        }
    }

    if (target_idx < 0) {
        if (g_slots[slot].tab_proxy_count < MAX_TAB_PROXIES) {
            target_idx = g_slots[slot].tab_proxy_count++;
        } else {
            pthread_mutex_unlock(&g_slots_lock);
            printf("[JVM Bridge] WARNING: Tab proxy list full for slot %d\n", slot);
            return;
        }
    }

    TabProxyRule *r = &g_slots[slot].tab_proxies[target_idx];
    snprintf(r->tab_prefix, sizeof(r->tab_prefix), "%s", tab_prefix);
    r->type = type;
    if (host) snprintf(r->host, sizeof(r->host), "%s", host); else r->host[0] = '\0';
    r->port = port;
    if (user) snprintf(r->user, sizeof(r->user), "%s", user); else r->user[0] = '\0';
    if (pass) snprintf(r->pass, sizeof(r->pass), "%s", pass); else r->pass[0] = '\0';

    pthread_mutex_unlock(&g_slots_lock);
    printf("[JVM Bridge] Slot %d Tab '%s' proxy set: type=%d %s:%d\n", slot, tab_prefix, type, host ? host : "direct", port);
}

int jvm_bridge_get_tab_proxy(int slot, const char *tab_prefix, int *out_type, char *out_host, int host_len, int *out_port, char *out_user, int user_len, char *out_pass, int pass_len) {
    if (slot < 0 || slot >= JVM_BRIDGE_MAX_SLOTS || !tab_prefix || tab_prefix[0] == '\0') return 0;
    pthread_mutex_lock(&g_slots_lock);

    const TabProxyRule *found = NULL;
    for (int i = 0; i < g_slots[slot].tab_proxy_count; i++) {
        const TabProxyRule *r = &g_slots[slot].tab_proxies[i];
        if (strcasecmp(r->tab_prefix, tab_prefix) == 0) {
            found = r;
            break;
        }
    }

    // Interoperability fallback: if tab_prefix is 'a'..'z' or 'aa', check if registered as '1'..'27'
    if (!found) {
        char num_str[16] = {0};
        if (isalpha((unsigned char)tab_prefix[0]) && tab_prefix[1] == '\0') {
            snprintf(num_str, sizeof(num_str), "%d", 1 + (tolower((unsigned char)tab_prefix[0]) - 'a'));
        } else if (strcasecmp(tab_prefix, "aa") == 0) {
            snprintf(num_str, sizeof(num_str), "27");
        }
        if (num_str[0] != '\0') {
            for (int i = 0; i < g_slots[slot].tab_proxy_count; i++) {
                const TabProxyRule *r = &g_slots[slot].tab_proxies[i];
                if (strcmp(r->tab_prefix, num_str) == 0) {
                    found = r;
                    break;
                }
            }
        }
    }

    // Interoperability fallback: if tab_prefix is '1'..'27', check if registered as 'a'..'z' or 'aa'
    if (!found && isdigit((unsigned char)tab_prefix[0])) {
        int idx = atoi(tab_prefix);
        char alpha_str[4] = {0};
        if (idx >= 1 && idx <= 26) {
            alpha_str[0] = (char)('a' + (idx - 1));
            alpha_str[1] = '\0';
        } else if (idx == 27) {
            strncpy(alpha_str, "aa", sizeof(alpha_str) - 1);
        }
        if (alpha_str[0] != '\0') {
            for (int i = 0; i < g_slots[slot].tab_proxy_count; i++) {
                const TabProxyRule *r = &g_slots[slot].tab_proxies[i];
                if (strcasecmp(r->tab_prefix, alpha_str) == 0) {
                    found = r;
                    break;
                }
            }
        }
    }

    if (!found || found->type < 0 || found->port <= 0 || found->host[0] == '\0') {
        pthread_mutex_unlock(&g_slots_lock);
        return 0;
    }

    if (out_type) *out_type = found->type;
    if (out_port) *out_port = found->port;
    if (out_host && host_len > 0) snprintf(out_host, host_len, "%s", found->host);
    if (out_user && user_len > 0) snprintf(out_user, user_len, "%s", found->user);
    if (out_pass && pass_len > 0) snprintf(out_pass, pass_len, "%s", found->pass);

    pthread_mutex_unlock(&g_slots_lock);
    return 1;
}

void jvm_bridge_clear_tab_proxies(int slot) {
    if (slot < 0 || slot >= JVM_BRIDGE_MAX_SLOTS) return;
    pthread_mutex_lock(&g_slots_lock);
    g_slots[slot].tab_proxy_count = 0;
    pthread_mutex_unlock(&g_slots_lock);
    printf("[JVM Bridge] Slot %d: cleared tab proxies\n", slot);
}

// ============================================================
// Server Destination Override ("Thay IP Phiên Bản") Implementation
// ============================================================

void jvm_bridge_set_server_override(int enabled, const char *host, int port) {
    pthread_mutex_lock(&g_server_override_lock);
    g_server_override_enabled = enabled;
    if (host) {
        snprintf(g_server_override_host, sizeof(g_server_override_host), "%s", host);
    } else {
        g_server_override_host[0] = '\0';
    }
    g_server_override_port = port;
    pthread_mutex_unlock(&g_server_override_lock);
    printf("[ServerOverride] Config: enabled=%d, host=%s, port=%d\n",
           enabled, host ? host : "", port);
}

void jvm_bridge_add_server_redirect_rule(const char *old_ip, const char *new_ip, int port) {
    if (!old_ip || !new_ip || old_ip[0] == '\0' || new_ip[0] == '\0') return;
    pthread_mutex_lock(&g_server_override_lock);

    // Update existing rule if present
    for (int i = 0; i < g_server_rules_count; i++) {
        if (strcasecmp(g_server_rules[i].old_ip, old_ip) == 0) {
            snprintf(g_server_rules[i].new_ip, sizeof(g_server_rules[i].new_ip), "%s", new_ip);
            g_server_rules[i].port = port;
            pthread_mutex_unlock(&g_server_override_lock);
            printf("[ServerOverride] Updated rule: %s -> %s:%d\n", old_ip, new_ip, port);
            return;
        }
    }

    if (g_server_rules_count < MAX_SERVER_RULES) {
        ServerRedirectRule *r = &g_server_rules[g_server_rules_count++];
        snprintf(r->old_ip, sizeof(r->old_ip), "%s", old_ip);
        snprintf(r->new_ip, sizeof(r->new_ip), "%s", new_ip);
        r->port = port;
        printf("[ServerOverride] Added rule: %s -> %s:%d\n", old_ip, new_ip, port);
    }

    pthread_mutex_unlock(&g_server_override_lock);
}

void jvm_bridge_clear_server_redirect_rules(void) {
    pthread_mutex_lock(&g_server_override_lock);
    g_server_rules_count = 0;
    pthread_mutex_unlock(&g_server_override_lock);
}

int jvm_bridge_resolve_server_destination(const char *in_host, const char *in_port, char *out_host, int out_host_len, char *out_port, int out_port_len) {
    if (!in_host || !out_host || out_host_len <= 0) return 0;

    snprintf(out_host, out_host_len, "%s", in_host);
    if (in_port && out_port && out_port_len > 0) {
        snprintf(out_port, out_port_len, "%s", in_port);
    }

    pthread_mutex_lock(&g_server_override_lock);

    // 1. Global server override
    if (g_server_override_enabled && g_server_override_host[0] != '\0') {
        snprintf(out_host, out_host_len, "%s", g_server_override_host);
        if (g_server_override_port > 0 && out_port && out_port_len > 0) {
            snprintf(out_port, out_port_len, "%d", g_server_override_port);
        }
        pthread_mutex_unlock(&g_server_override_lock);
        printf("[ServerOverride] Redirected (Global): %s:%s -> %s:%s\n",
               in_host, in_port ? in_port : "", out_host, out_port ? out_port : "");
        return 1;
    }

    // 2. Specific redirection rules
    for (int i = 0; i < g_server_rules_count; i++) {
        if (strcasecmp(g_server_rules[i].old_ip, in_host) == 0) {
            snprintf(out_host, out_host_len, "%s", g_server_rules[i].new_ip);
            if (g_server_rules[i].port > 0 && out_port && out_port_len > 0) {
                snprintf(out_port, out_port_len, "%d", g_server_rules[i].port);
            }
            pthread_mutex_unlock(&g_server_override_lock);
            printf("[ServerOverride] Redirected (Rule): %s:%s -> %s:%s\n",
                   in_host, in_port ? in_port : "", out_host, out_port ? out_port : "");
            return 1;
        }
    }

    pthread_mutex_unlock(&g_server_override_lock);
    return 0;
}

// Backward compatibility wrappers (slot 0)
int jvm_bridge_init(const char *res_root, const char *save_root, const char *midlet_jar,
                    int screen_width, int screen_height, int render_3d_scale,
                    int fps_limit) {
    return jvm_bridge_init_slot(0, res_root, save_root, midlet_jar, screen_width, screen_height, render_3d_scale, fps_limit);
}

int jvm_bridge_run_midlet(const char *midlet_jar_path) {
    return jvm_bridge_run_midlet_slot(0, midlet_jar_path);
}

void jvm_bridge_destroy(void) {
    jvm_bridge_destroy_all();
}

void jvm_bridge_set_save_root(const char *save_root) {
    int focused = jvm_bridge_get_focused_slot();
    pthread_mutex_lock(&g_slots_lock);
    if (g_slots[focused].jvm && save_root) {
        sys_properties_set_c(g_slots[focused].jvm, "app.save.root", (c8 *)save_root);
        printf("[JVM Bridge] Switched app.save.root for slot %d to: %s\n", focused, save_root);
    }
    pthread_mutex_unlock(&g_slots_lock);
}

void jvm_bridge_request_stop(void) {
    jvm_bridge_request_stop_slot(jvm_bridge_get_focused_slot());
}

int jvm_bridge_is_stop_requested(void) {
    return jvm_bridge_is_slot_stop_requested(jvm_bridge_get_focused_slot());
}

void jvm_bridge_clean_ram(void) {
    // 1. Trigger immediate MiniJVM GC across all running game slots
    pthread_mutex_lock(&g_slots_lock);
    for (int i = 0; i < JVM_BRIDGE_MAX_SLOTS; i++) {
        MiniJVM *jvm = g_slots[i].jvm;
        if (jvm && jvm->collector) {
            jvm->collector->lastgc = 0; // Wakes GC thread immediately
        }
    }
    pthread_mutex_unlock(&g_slots_lock);

    // 2. Purge dead CoreGraphics RenderContext/RenderImage shells
    j2me_render_purge_dead_shells();

    // 3. Return freed malloc heap pages back to iOS kernel to prevent Jetsam kills
#if defined(__APPLE__) || defined(__MACH__)
    malloc_zone_pressure_relief(NULL, 0);
#endif
}

long long jvm_bridge_get_used_ram_kb(void) {
#if defined(__APPLE__) || defined(__MACH__)
    task_vm_info_data_t vmInfo;
    mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
    kern_return_t kr = task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&vmInfo, &count);
    if (kr == KERN_SUCCESS) {
        return (long long)(vmInfo.phys_footprint / 1024);
    }
#endif
    return 0;
}

double jvm_bridge_get_cpu_usage_percent(void) {
#if defined(__APPLE__) || defined(__MACH__)
    thread_act_array_t thread_list = NULL;
    mach_msg_type_number_t thread_count = 0;
    task_t self_task = mach_task_self();
    kern_return_t kr = task_threads(self_task, &thread_list, &thread_count);
    if (kr != KERN_SUCCESS || !thread_list) {
        return 0.0;
    }

    double total_cpu = 0.0;
    for (mach_msg_type_number_t i = 0; i < thread_count; i++) {
        thread_info_data_t thinfo;
        mach_msg_type_number_t thread_info_count = THREAD_INFO_MAX;
        kr = thread_info(thread_list[i], THREAD_BASIC_INFO, (thread_info_t)thinfo, &thread_info_count);
        if (kr == KERN_SUCCESS) {
            thread_basic_info_t basic_info = (thread_basic_info_t)thinfo;
            if (!(basic_info->flags & TH_FLAGS_IDLE)) {
                total_cpu += (double)basic_info->cpu_usage / (double)TH_USAGE_SCALE * 100.0;
            }
        }
        // CRITICAL: Release Mach send right for every thread port to prevent kernel port leak!
        mach_port_deallocate(self_task, thread_list[i]);
    }

    vm_deallocate(self_task, (vm_offset_t)thread_list, thread_count * sizeof(thread_t));

    long cores = sysconf(_SC_NPROCESSORS_ONLN);
    if (cores > 1) {
        total_cpu /= (double)cores;
    }
    return total_cpu;
#else
    return 0.0;
#endif
}
