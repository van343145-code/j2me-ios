//
// j2me_input.c — Thread-safe input event bridge between iOS and miniJVM
//
// The touch UI and virtual keyboard may submit events on separate threads.
//

#include "j2me_input.h"
#include "jvm_bridge.h"
#include "jvm.h"
#include "jvm_util.h"
#include <stdio.h>
#include <pthread.h>

// ============================================================
// Ring buffer
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
    enqueue_event(type, x, y, 0);
}

void j2me_input_post_key(int type, int keyCode) {
    enqueue_event(type, 0, 0, keyCode);
}

// ============================================================
// Native method: NativeBridge.pollInputEvent() → int[] or null
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

    // Create int[4] array
    Utf8String *type_name = utf8_create_c("[I");
    Instance *arr = jarray_create_by_type_index(runtime, 4, DATATYPE_INT);
    if (!arr) {
        utf8_destroy(type_name);
        env->push_ref(runtime->stack, NULL);
        return RUNTIME_STATUS_NORMAL;
    }
    utf8_destroy(type_name);

    // Fill array
    s32 *body = (s32 *)arr->arr_body;
    body[0] = evt.type;
    body[1] = evt.x;
    body[2] = evt.y;
    body[3] = evt.keyCode;

    env->push_ref(runtime->stack, arr);
    return RUNTIME_STATUS_NORMAL;
}

// ============================================================
// Native method: NativeBridge.isStopRequested() → boolean
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
    pthread_mutex_unlock(&g_input_lock);
    printf("[J2ME Input] Ring buffer reset\n");
}

// ============================================================
// Native method table
// ============================================================

#define CLS "javax/microedition/lcdui/NativeBridge"

static java_native_method j2me_input_methods[] = {
    {CLS, "pollInputEvent", "()[I", n_pollInputEvent},
    {CLS, "isStopRequested", "()Z", n_isStopRequested},
};

#undef CLS

void j2me_input_reg_natives(MiniJVM *jvm) {
    native_reg_lib(jvm, j2me_input_methods,
                   sizeof(j2me_input_methods) / sizeof(java_native_method));
    printf("[J2ME Input] Registered %lu native methods\n",
           sizeof(j2me_input_methods) / sizeof(java_native_method));
}
