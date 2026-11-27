//
// j2me_input.c — Event-driven, thread-safe input bridge between iOS and miniJVM
//
// Uses pthread_cond_timedwait so Display.runEventLoop() sleeps at 0% CPU when idle
// and wakes with 0ms latency the instant a touch, key, repaint, or stop event arrives.
//

#include "j2me_input.h"
#include "jvm_bridge.h"
#include "jvm.h"
#include "jvm_util.h"
#include <stdio.h>
#include <pthread.h>
#include <sys/time.h>
#include <errno.h>

// ============================================================
// Ring buffer + condition variable
// ============================================================

#define INPUT_QUEUE_SIZE 1024
#define INPUT_QUEUE_MASK (INPUT_QUEUE_SIZE - 1)

typedef struct {
    int type;
    int x, y;
    int keyCode;
    int slot;
} InputEvent;

static InputEvent g_queue[INPUT_QUEUE_SIZE];
static int g_write_pos;
static int g_read_pos;
static pthread_mutex_t g_input_lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t g_input_cond = PTHREAD_COND_INITIALIZER;

static int g_canvas_width = 240;
static int g_canvas_height = 320;

void j2me_input_set_canvas_size(int width, int height) {
    g_canvas_width = width;
    g_canvas_height = height;
}

static void enqueue_event(int type, int x, int y, int keyCode) {
    int slot = jvm_bridge_get_focused_slot();
    pthread_mutex_lock(&g_input_lock);
    int next = (g_write_pos + 1) & INPUT_QUEUE_MASK;
    if (next != g_read_pos) {
        g_queue[g_write_pos] = (InputEvent){type, x, y, keyCode, slot};
        g_write_pos = next;
    }
    pthread_cond_broadcast(&g_input_cond);
    pthread_mutex_unlock(&g_input_lock);
}

static int dequeue_event(int slot, InputEvent *out) {
    int found = 0;
    pthread_mutex_lock(&g_input_lock);
    if (slot == jvm_bridge_get_focused_slot()) {
        while (g_read_pos != g_write_pos) {
            InputEvent event = g_queue[g_read_pos];
            g_read_pos = (g_read_pos + 1) & INPUT_QUEUE_MASK;
            if (event.slot == slot) {
                *out = event;
                found = 1;
                break;
            }
        }
    }
    pthread_mutex_unlock(&g_input_lock);
    return found;
}

// ============================================================
// Public API (called from Swift/main thread)
// ============================================================

void j2me_input_post_touch(int type, int x, int y) {
    if (type < J2ME_INPUT_POINTER_PRESSED || type > J2ME_INPUT_POINTER_RELEASED) {
        return;
    }
    enqueue_event(type, x, y, 0);
}

void j2me_input_post_key(int type, int keyCode) {
    // Safety guard: NEVER allow pointer event types (0..2) via post_key.
    // Previously j2me_input_post_key(0, 0) injected a fake pointerPressed(0, 0)
    // that auto-opened the in-game inventory on every resume/launch!
    if (type <= J2ME_INPUT_POINTER_RELEASED) {
        enqueue_event(J2ME_INPUT_FORCE_REPAINT, 0, 0, 0);
        return;
    }
    enqueue_event(type, 0, 0, keyCode);
}

void j2me_input_post_repaint(void) {
    enqueue_event(J2ME_INPUT_FORCE_REPAINT, 0, 0, 0);
}

void j2me_input_wake_all(void) {
    pthread_mutex_lock(&g_input_lock);
    pthread_cond_broadcast(&g_input_cond);
    pthread_mutex_unlock(&g_input_lock);
}

// ============================================================
// Native method: NativeBridge.pollInputEvent() -> int[] or null
// Returns int[4]: {type, x, y, keyCode}
// ============================================================

static s32 n_pollInputEvent(Runtime *runtime, JClass *clazz) {
    JniEnv *env = runtime->jnienv;

    // Only the currently focused slot consumes input events from the UI
    int slot = jvm_bridge_find_jvm_slot(runtime->jvm);
    if (slot != jvm_bridge_get_focused_slot()) {
        env->push_ref(runtime->stack, NULL);
        return RUNTIME_STATUS_NORMAL;
    }

    InputEvent evt;
    if (!dequeue_event(slot, &evt)) {
        env->push_ref(runtime->stack, NULL);
        return RUNTIME_STATUS_NORMAL;
    }

    Instance *arr = jarray_create_by_type_index(runtime, 4, DATATYPE_INT);
    if (!arr) {
        env->push_ref(runtime->stack, NULL);
        return RUNTIME_STATUS_NORMAL;
    }

    s32 *body = (s32 *)arr->arr_body;
    body[0] = evt.type;
    body[1] = evt.x;
    body[2] = evt.y;
    body[3] = evt.keyCode;

    env->push_ref(runtime->stack, arr);
    return RUNTIME_STATUS_NORMAL;
}

// ============================================================
// Native method: NativeBridge.waitForInput(int timeoutMs)
// Blocks cleanly in the kernel until an event arrives, stop is requested,
// or timeoutMs expires — marks thread as THREAD_STATUS_WAIT so miniJVM GC
// never stalls waiting for this thread!
// ============================================================

static s32 n_waitForInput(Runtime *runtime, JClass *clazz) {
    JniEnv *env = runtime->jnienv;
    s32 timeoutMs = env->localvar_getInt(runtime->localvar, 0);
    if (timeoutMs <= 0) return RUNTIME_STATUS_NORMAL;
    if (timeoutMs > 1000) timeoutMs = 1000;

    int slot = jvm_bridge_find_jvm_slot(runtime->jvm);
    if (slot >= 0 && jvm_bridge_is_slot_stop_requested(slot)) {
        return RUNTIME_STATUS_NORMAL;
    }

    jthread_block_enter(runtime);
    pthread_mutex_lock(&g_input_lock);
    int hasPending = (slot == jvm_bridge_get_focused_slot() && g_read_pos != g_write_pos);
    if (!hasPending && !(slot >= 0 && jvm_bridge_is_slot_stop_requested(slot))) {
        struct timeval tv;
        gettimeofday(&tv, NULL);
        long long total_usec = (long long)tv.tv_usec + (long long)timeoutMs * 1000LL;
        struct timespec ts;
        ts.tv_sec = tv.tv_sec + (time_t)(total_usec / 1000000LL);
        ts.tv_nsec = (long)((total_usec % 1000000LL) * 1000LL);
        pthread_cond_timedwait(&g_input_cond, &g_input_lock, &ts);
    }
    pthread_mutex_unlock(&g_input_lock);
    jthread_block_exit(runtime);

    return RUNTIME_STATUS_NORMAL;
}

// ============================================================
// Native method: NativeBridge.isStopRequested() -> boolean
// ============================================================

static s32 n_isStopRequested(Runtime *runtime, JClass *clazz) {
    int slot = jvm_bridge_get_jvm_slot(runtime->jvm);
    push_int(runtime->stack, jvm_bridge_is_slot_stop_requested(slot) ? 1 : 0);
    return RUNTIME_STATUS_NORMAL;
}

// ============================================================
// Reset (call between game sessions)
// ============================================================

void j2me_input_reset(void) {
    pthread_mutex_lock(&g_input_lock);
    g_write_pos = 0;
    g_read_pos = 0;
    pthread_cond_broadcast(&g_input_cond);
    pthread_mutex_unlock(&g_input_lock);
    printf("[J2ME Input] Ring buffer reset\n");
}

// ============================================================
// Native method table
// ============================================================

#define CLS "javax/microedition/lcdui/NativeBridge"

static java_native_method j2me_input_methods[] = {
    {CLS, "pollInputEvent", "()[I", n_pollInputEvent},
    {CLS, "waitForInput",   "(I)V", n_waitForInput},
    {CLS, "isStopRequested", "()Z", n_isStopRequested},
};

#undef CLS

void j2me_input_reg_natives(MiniJVM *jvm) {
    native_reg_lib(jvm, j2me_input_methods,
                   sizeof(j2me_input_methods) / sizeof(java_native_method));
    printf("[J2ME Input] Registered %lu native methods\n",
           sizeof(j2me_input_methods) / sizeof(java_native_method));
}
