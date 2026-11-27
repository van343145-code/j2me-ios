//
// j2me_ui.m — Native UI bridge for J2ME LCDUI Forms/Lists/Alerts
//
// Java classes serialize their state via sequential native calls.
// Native side accumulates data and creates UIKit views on main thread.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#include "j2me_ui.h"
#include "j2me_input.h"
#include "jvm_bridge.h"
#include "jvm.h"
#include "jvm_util.h"
#include <stdio.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>
#include <os/lock.h>

// ============================================================
// Form builder state — accumulated by Java calls, flushed on show
// ============================================================

#define MAX_FORM_ITEMS 64
#define MAX_COMMANDS 8

typedef struct {
    int type;           // 0=string, 1=textfield, 2=choice, 3=image, 4=spacer, 5=gauge
    char label[256];
    char text[8192];
    int intParam1;      // appearance/maxSize/choiceType
    int intParam2;      // constraints
} FormItem;

typedef struct {
    char label[128];
    int type;           // Command.SCREEN, BACK, OK, EXIT, etc.
    int priority;
    int id;             // sequential ID for event matching
} FormCommand;

typedef struct {
    char form_title[256];
    FormItem form_items[MAX_FORM_ITEMS];
    int form_item_count;
    FormCommand form_commands[MAX_COMMANDS];
    int form_command_count;
    int form_type;
    char list_items[MAX_FORM_ITEMS][256];
    int list_items_running[MAX_FORM_ITEMS];
    int list_item_count;
    int list_type;
    char alert_text[1024];
    int alert_timeout;
    char textbox_text[8192];
    int action;
} ScreenState;

// Java constructs one screen at a time per JVM. UIKit only sees complete screens.
static ScreenState *g_builders[JVM_BRIDGE_MAX_SLOTS];
static ScreenState *g_screens[JVM_BRIDGE_MAX_SLOTS];
static ScreenState g_empty_screen;
static atomic_int g_revisions[JVM_BRIDGE_MAX_SLOTS];
static atomic_int g_generations[JVM_BRIDGE_MAX_SLOTS];
static os_unfair_lock g_screen_lock = OS_UNFAIR_LOCK_INIT;
static j2me_ui_callback g_ui_callback = NULL;

static ScreenState *screen_for_slot(int slot) {
    ScreenState *screen = g_screens[slot];
    return screen != NULL ? screen : &g_empty_screen;
}

static ScreenState *focused_screen(void) {
    return screen_for_slot(jvm_bridge_get_focused_slot());
}

static ScreenState *builder_for_slot(int slot) {
    if (slot < 0 || slot >= JVM_BRIDGE_MAX_SLOTS) return NULL;
    if (!g_builders[slot]) g_builders[slot] = calloc(1, sizeof(ScreenState));
    return g_builders[slot];
}

int j2me_ui_screen_revision(int slot) {
    return slot >= 0 && slot < JVM_BRIDGE_MAX_SLOTS ? atomic_load(&g_revisions[slot]) : 0;
}

void j2me_ui_restore_focused_screen(void) {
    ScreenState *screen = focused_screen();
    if (g_ui_callback) {
        int action = screen->action ? screen->action : J2ME_UI_ACTION_SHOW_CANVAS;
        g_ui_callback(action, screen->form_title);
    }
}

static void publish_screen(int slot, ScreenState *builder, int action) {
    ScreenState *snapshot = malloc(sizeof(ScreenState));
    if (!snapshot) return;
    *snapshot = *builder;
    snapshot->action = action;
    int generation = atomic_load(&g_generations[slot]);
    dispatch_async(dispatch_get_main_queue(), ^{
        if (generation != atomic_load(&g_generations[slot])) {
            free(snapshot);
            return;
        }
        os_unfair_lock_lock(&g_screen_lock);
        ScreenState *old = g_screens[slot];
        g_screens[slot] = snapshot;
        atomic_fetch_add(&g_revisions[slot], 1);
        os_unfair_lock_unlock(&g_screen_lock);
        free(old);
        if (slot == jvm_bridge_get_focused_slot()) j2me_ui_restore_focused_screen();
    });
}

void j2me_ui_reset_slot(int slot) {
    if (slot < 0 || slot >= JVM_BRIDGE_MAX_SLOTS) return;
    int generation = atomic_fetch_add(&g_generations[slot], 1) + 1;
    free(g_builders[slot]);
    g_builders[slot] = NULL;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (generation != atomic_load(&g_generations[slot])) return;
        os_unfair_lock_lock(&g_screen_lock);
        ScreenState *old = g_screens[slot];
        g_screens[slot] = NULL;
        atomic_fetch_add(&g_revisions[slot], 1);
        os_unfair_lock_unlock(&g_screen_lock);
        free(old);
    });
}

void j2me_ui_set_textbox_text(const char *text) {
    os_unfair_lock_lock(&g_screen_lock);
    if (text) {
        strncpy(focused_screen()->textbox_text, text, sizeof(focused_screen()->textbox_text) - 1);
        focused_screen()->textbox_text[sizeof(focused_screen()->textbox_text) - 1] = '\0';
    } else {
        focused_screen()->textbox_text[0] = '\0';
    }
    os_unfair_lock_unlock(&g_screen_lock);
}

const char *j2me_ui_get_textbox_text(void) {
    return focused_screen()->textbox_text;
}

void j2me_ui_set_callback(j2me_ui_callback callback) {
    g_ui_callback = callback;
}

// ============================================================
// Public getters for Swift side
// ============================================================

const char *j2me_ui_get_form_title(void) { return focused_screen()->form_title; }
int j2me_ui_get_form_item_count(void) { return focused_screen()->form_item_count; }
int j2me_ui_get_form_item_type(int index) { return index >= 0 && index < focused_screen()->form_item_count ? focused_screen()->form_items[index].type : -1; }
const char *j2me_ui_get_form_item_label(int index) { return index >= 0 && index < focused_screen()->form_item_count ? focused_screen()->form_items[index].label : ""; }
const char *j2me_ui_get_form_item_text(int index) { return index >= 0 && index < focused_screen()->form_item_count ? focused_screen()->form_items[index].text : ""; }
int j2me_ui_get_form_item_param1(int index) { return index >= 0 && index < focused_screen()->form_item_count ? focused_screen()->form_items[index].intParam1 : 0; }
int j2me_ui_get_form_item_param2(int index) { return index >= 0 && index < focused_screen()->form_item_count ? focused_screen()->form_items[index].intParam2 : 0; }

int j2me_ui_get_command_count(void) { return focused_screen()->form_command_count; }
const char *j2me_ui_get_command_label(int index) { return index >= 0 && index < focused_screen()->form_command_count ? focused_screen()->form_commands[index].label : ""; }
int j2me_ui_get_command_type(int index) { return index >= 0 && index < focused_screen()->form_command_count ? focused_screen()->form_commands[index].type : 0; }
int j2me_ui_get_command_id(int index) { return index >= 0 && index < focused_screen()->form_command_count ? focused_screen()->form_commands[index].id : -1; }

int j2me_ui_get_list_item_count(void) { return focused_screen()->list_item_count; }
const char *j2me_ui_get_list_item(int index) { return index >= 0 && index < focused_screen()->list_item_count ? focused_screen()->list_items[index] : ""; }
int j2me_ui_get_list_type(void) { return focused_screen()->list_type; }

const char *j2me_ui_get_alert_text(void) { return focused_screen()->alert_text; }
int j2me_ui_get_alert_timeout(void) { return focused_screen()->alert_timeout; }

void j2me_ui_set_form_item_text(int index, const char *text) {
    if (index >= 0 && index < focused_screen()->form_item_count && text) {
        os_unfair_lock_lock(&g_screen_lock);
        strncpy(focused_screen()->form_items[index].text, text, sizeof(focused_screen()->form_items[index].text) - 1);
        focused_screen()->form_items[index].text[sizeof(focused_screen()->form_items[index].text) - 1] = '\0';
        os_unfair_lock_unlock(&g_screen_lock);
    }
}

// ============================================================
// Native methods — called from Java to build UI
// ============================================================

static s32 n_formBegin(Runtime *runtime, JClass *clazz) {
    int slot = jvm_bridge_find_jvm_slot(runtime->jvm);
    ScreenState *builder = builder_for_slot(slot);
    if (!builder) return RUNTIME_STATUS_NORMAL;

    JniEnv *env = runtime->jnienv;
    Instance *jtitle = env->localvar_getRefer(runtime->localvar, 0);
    s32 type = env->localvar_getInt(runtime->localvar, 1);

    builder->form_item_count = 0;
    builder->form_command_count = 0;
    builder->list_item_count = 0;
    builder->form_type = type;
    builder->textbox_text[0] = '\0';

    if (jtitle) {
        Utf8String *ustr = utf8_create();
        env->jstring_2_utf8(jtitle, ustr, runtime);
        strncpy(builder->form_title, utf8_cstr(ustr), sizeof(builder->form_title) - 1);
        utf8_destroy(ustr);
    } else {
        builder->form_title[0] = '\0';
    }
    return RUNTIME_STATUS_NORMAL;
}

static s32 n_formAddStringItem(Runtime *runtime, JClass *clazz) {
    int slot = jvm_bridge_find_jvm_slot(runtime->jvm);
    ScreenState *builder = builder_for_slot(slot);
    if (!builder) return RUNTIME_STATUS_NORMAL;

    JniEnv *env = runtime->jnienv;
    Instance *jlabel = env->localvar_getRefer(runtime->localvar, 0);
    Instance *jtext = env->localvar_getRefer(runtime->localvar, 1);
    s32 appearance = env->localvar_getInt(runtime->localvar, 2);

    if (builder->form_item_count >= MAX_FORM_ITEMS) return RUNTIME_STATUS_NORMAL;
    FormItem *item = &builder->form_items[builder->form_item_count++];
    item->type = 0; // string
    item->intParam1 = appearance;
    item->label[0] = '\0';
    item->text[0] = '\0';

    if (jlabel) {
        Utf8String *u = utf8_create();
        env->jstring_2_utf8(jlabel, u, runtime);
        strncpy(item->label, utf8_cstr(u), sizeof(item->label) - 1);
        utf8_destroy(u);
    }
    if (jtext) {
        Utf8String *u = utf8_create();
        env->jstring_2_utf8(jtext, u, runtime);
        strncpy(item->text, utf8_cstr(u), sizeof(item->text) - 1);
        if (builder->form_type == 3) { // TextBox: seed builder->textbox_text
            strncpy(builder->textbox_text, utf8_cstr(u), sizeof(builder->textbox_text) - 1);
            builder->textbox_text[sizeof(builder->textbox_text) - 1] = '\0';
        }
        utf8_destroy(u);
    }
    return RUNTIME_STATUS_NORMAL;
}

static s32 n_formAddChoiceGroup(Runtime *runtime, JClass *clazz) {
    int slot = jvm_bridge_find_jvm_slot(runtime->jvm);
    ScreenState *builder = builder_for_slot(slot);
    if (!builder) return RUNTIME_STATUS_NORMAL;

    JniEnv *env = runtime->jnienv;
    Instance *jlabel = env->localvar_getRefer(runtime->localvar, 0);
    Instance *jtext = env->localvar_getRefer(runtime->localvar, 1);
    s32 choiceType = env->localvar_getInt(runtime->localvar, 2);

    if (builder->form_item_count >= MAX_FORM_ITEMS) return RUNTIME_STATUS_NORMAL;
    FormItem *item = &builder->form_items[builder->form_item_count++];
    item->type = 2; // 2 = ChoiceGroup
    item->intParam1 = choiceType;
    item->intParam2 = choiceType;
    item->label[0] = '\0';
    item->text[0] = '\0';

    if (jlabel) {
        Utf8String *u = utf8_create();
        env->jstring_2_utf8(jlabel, u, runtime);
        strncpy(item->label, utf8_cstr(u), sizeof(item->label) - 1);
        utf8_destroy(u);
    }
    if (jtext) {
        Utf8String *u = utf8_create();
        env->jstring_2_utf8(jtext, u, runtime);
        strncpy(item->text, utf8_cstr(u), sizeof(item->text) - 1);
        utf8_destroy(u);
    }
    return RUNTIME_STATUS_NORMAL;
}

static s32 n_formAddTextField(Runtime *runtime, JClass *clazz) {
    int slot = jvm_bridge_find_jvm_slot(runtime->jvm);
    ScreenState *builder = builder_for_slot(slot);
    if (!builder) return RUNTIME_STATUS_NORMAL;

    JniEnv *env = runtime->jnienv;
    Instance *jlabel = env->localvar_getRefer(runtime->localvar, 0);
    Instance *jtext = env->localvar_getRefer(runtime->localvar, 1);
    s32 maxSize = env->localvar_getInt(runtime->localvar, 2);
    s32 constraints = env->localvar_getInt(runtime->localvar, 3);

    if (builder->form_item_count >= MAX_FORM_ITEMS) return RUNTIME_STATUS_NORMAL;
    FormItem *item = &builder->form_items[builder->form_item_count++];
    item->intParam1 = maxSize;
    item->intParam2 = constraints;
    item->label[0] = '\0';
    item->text[0] = '\0';

    if (jlabel) {
        Utf8String *u = utf8_create();
        env->jstring_2_utf8(jlabel, u, runtime);
        strncpy(item->label, utf8_cstr(u), sizeof(item->label) - 1);
        utf8_destroy(u);
    }
    if (jtext) {
        Utf8String *u = utf8_create();
        env->jstring_2_utf8(jtext, u, runtime);
        strncpy(item->text, utf8_cstr(u), sizeof(item->text) - 1);
        if (builder->form_type == 3) { // TextBox: seed builder->textbox_text
            strncpy(builder->textbox_text, utf8_cstr(u), sizeof(builder->textbox_text) - 1);
            builder->textbox_text[sizeof(builder->textbox_text) - 1] = '\0';
        }
        utf8_destroy(u);
    }

    item->type = 1; // ChoiceGroup uses its own native method.

    return RUNTIME_STATUS_NORMAL;
}

static s32 n_formAddCommand(Runtime *runtime, JClass *clazz) {
    int slot = jvm_bridge_find_jvm_slot(runtime->jvm);
    ScreenState *builder = builder_for_slot(slot);
    if (!builder) return RUNTIME_STATUS_NORMAL;

    JniEnv *env = runtime->jnienv;
    Instance *jlabel = env->localvar_getRefer(runtime->localvar, 0);
    s32 cmdType = env->localvar_getInt(runtime->localvar, 1);
    s32 priority = env->localvar_getInt(runtime->localvar, 2);
    s32 cmdId = env->localvar_getInt(runtime->localvar, 3);

    if (builder->form_command_count >= MAX_COMMANDS) return RUNTIME_STATUS_NORMAL;
    FormCommand *cmd = &builder->form_commands[builder->form_command_count++];
    cmd->type = cmdType;
    cmd->priority = priority;
    cmd->id = cmdId;
    cmd->label[0] = '\0';

    if (jlabel) {
        Utf8String *u = utf8_create();
        env->jstring_2_utf8(jlabel, u, runtime);
        strncpy(cmd->label, utf8_cstr(u), sizeof(cmd->label) - 1);
        utf8_destroy(u);
    }
    return RUNTIME_STATUS_NORMAL;
}

static s32 n_formShow(Runtime *runtime, JClass *clazz) {
    int slot = jvm_bridge_find_jvm_slot(runtime->jvm);
    ScreenState *builder = builder_for_slot(slot);
    if (!builder) return RUNTIME_STATUS_NORMAL;
    int action;
    switch (builder->form_type) {
        case 1: action = J2ME_UI_ACTION_SHOW_LIST; break;
        case 2: action = J2ME_UI_ACTION_SHOW_ALERT; break;
        case 3: action = J2ME_UI_ACTION_SHOW_TEXTBOX; break;
        default: action = J2ME_UI_ACTION_SHOW_FORM; break;
    }
    publish_screen(slot, builder, action);
    return RUNTIME_STATUS_NORMAL;
}

static s32 n_showCanvas(Runtime *runtime, JClass *clazz) {
    int slot = jvm_bridge_find_jvm_slot(runtime->jvm);
    ScreenState *builder = builder_for_slot(slot);
    if (builder) publish_screen(slot, builder, J2ME_UI_ACTION_SHOW_CANVAS);
    return RUNTIME_STATUS_NORMAL;
}

static s32 n_listAddItem(Runtime *runtime, JClass *clazz) {
    int slot = jvm_bridge_find_jvm_slot(runtime->jvm);
    ScreenState *builder = builder_for_slot(slot);
    if (!builder) return RUNTIME_STATUS_NORMAL;

    JniEnv *env = runtime->jnienv;
    Instance *jtext = env->localvar_getRefer(runtime->localvar, 0);
    s32 isRunning = env->localvar_getInt(runtime->localvar, 1);

    if (builder->list_item_count >= MAX_FORM_ITEMS) return RUNTIME_STATUS_NORMAL;
    builder->list_items[builder->list_item_count][0] = '\0';
    if (jtext) {
        Utf8String *u = utf8_create();
        env->jstring_2_utf8(jtext, u, runtime);
        strncpy(builder->list_items[builder->list_item_count], utf8_cstr(u), 255);
        utf8_destroy(u);
    }
    builder->list_items_running[builder->list_item_count] = (isRunning != 0) ? 1 : 0;
    builder->list_item_count++;
    return RUNTIME_STATUS_NORMAL;
}

int j2me_ui_is_list_item_running(int index) {
    ScreenState *screen = focused_screen();
    return index >= 0 && index < screen->list_item_count && screen->list_items_running[index];
}

static s32 n_setListType(Runtime *runtime, JClass *clazz) {
    int slot = jvm_bridge_find_jvm_slot(runtime->jvm);
    ScreenState *builder = builder_for_slot(slot);
    if (!builder) return RUNTIME_STATUS_NORMAL;

    JniEnv *env = runtime->jnienv;
    builder->list_type = env->localvar_getInt(runtime->localvar, 0);
    return RUNTIME_STATUS_NORMAL;
}

static s32 n_setAlertText(Runtime *runtime, JClass *clazz) {
    int slot = jvm_bridge_find_jvm_slot(runtime->jvm);
    ScreenState *builder = builder_for_slot(slot);
    if (!builder) return RUNTIME_STATUS_NORMAL;

    JniEnv *env = runtime->jnienv;
    Instance *jtext = env->localvar_getRefer(runtime->localvar, 0);
    s32 timeout = env->localvar_getInt(runtime->localvar, 1);
    builder->alert_timeout = timeout;
    builder->alert_text[0] = '\0';
    if (jtext) {
        Utf8String *u = utf8_create();
        env->jstring_2_utf8(jtext, u, runtime);
        strncpy(builder->alert_text, utf8_cstr(u), sizeof(builder->alert_text) - 1);
        utf8_destroy(u);
    }
    return RUNTIME_STATUS_NORMAL;
}

// --- platformRequest: open URL in system browser ---

static s32 n_platformRequest(Runtime *runtime, JClass *clazz) {
    JniEnv *env = runtime->jnienv;
    Instance *jurl = env->localvar_getRefer(runtime->localvar, 0);
    if (!jurl) return RUNTIME_STATUS_NORMAL;

    Utf8String *u = utf8_create();
    env->jstring_2_utf8(jurl, u, runtime);
    const char *urlStr = utf8_cstr(u);

    dispatch_async(dispatch_get_main_queue(), ^{
        NSURL *url = [NSURL URLWithString:[NSString stringWithUTF8String:urlStr]];
        if (url) {
            [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
        }
    });

    utf8_destroy(u);
    return RUNTIME_STATUS_NORMAL;
}

static s32 n_getTextBoxText(Runtime *runtime, JClass *clazz) {
    char text[sizeof(g_empty_screen.textbox_text)];
    int slot = jvm_bridge_find_jvm_slot(runtime->jvm);
    if (slot < 0 || slot >= JVM_BRIDGE_MAX_SLOTS) return RUNTIME_STATUS_NORMAL;
    os_unfair_lock_lock(&g_screen_lock);
    memcpy(text, screen_for_slot(slot)->textbox_text, sizeof(text));
    os_unfair_lock_unlock(&g_screen_lock);
    JniEnv *env = runtime->jnienv;
    env->push_ref(runtime->stack, env->jstring_create_cstr(text, runtime));
    return RUNTIME_STATUS_NORMAL;
}

static s32 n_setTextBoxText(Runtime *runtime, JClass *clazz) {
    ScreenState *builder = builder_for_slot(jvm_bridge_find_jvm_slot(runtime->jvm));
    if (!builder) return RUNTIME_STATUS_NORMAL;
    JniEnv *env = runtime->jnienv;
    Instance *jtext = env->localvar_getRefer(runtime->localvar, 0);
    if (jtext) {
        Utf8String *u = utf8_create();
        env->jstring_2_utf8(jtext, u, runtime);
        strncpy(builder->textbox_text, utf8_cstr(u), sizeof(builder->textbox_text) - 1);
        builder->textbox_text[sizeof(builder->textbox_text) - 1] = '\0';
        utf8_destroy(u);
    } else {
        builder->textbox_text[0] = '\0';
    }
    return RUNTIME_STATUS_NORMAL;
}

static s32 n_getFormItemText(Runtime *runtime, JClass *clazz) {
    char text[sizeof(g_empty_screen.form_items[0].text)];
    int slot = jvm_bridge_find_jvm_slot(runtime->jvm);
    int index = runtime->jnienv->localvar_getInt(runtime->localvar, 0);
    bool present = false;
    if (slot >= 0 && slot < JVM_BRIDGE_MAX_SLOTS) {
        os_unfair_lock_lock(&g_screen_lock);
        ScreenState *screen = screen_for_slot(slot);
        if (index >= 0 && index < screen->form_item_count) {
            memcpy(text, screen->form_items[index].text, sizeof(text));
            present = true;
        }
        os_unfair_lock_unlock(&g_screen_lock);
    }
    JniEnv *env = runtime->jnienv;
    env->push_ref(runtime->stack, present ? env->jstring_create_cstr(text, runtime) : NULL);
    return RUNTIME_STATUS_NORMAL;
}

// ============================================================
// Native method table
// ============================================================

#define CLS "javax/microedition/lcdui/NativeBridge"

static java_native_method j2me_ui_methods[] = {
    {CLS, "formBegin",         "(Ljava/lang/String;I)V",                          n_formBegin},
    {CLS, "formAddStringItem", "(Ljava/lang/String;Ljava/lang/String;I)V",        n_formAddStringItem},
    {CLS, "formAddTextField",  "(Ljava/lang/String;Ljava/lang/String;II)V",       n_formAddTextField},
    {CLS, "formAddChoiceGroup","(Ljava/lang/String;Ljava/lang/String;I)V",        n_formAddChoiceGroup},
    {CLS, "formAddCommand",    "(Ljava/lang/String;III)V",                        n_formAddCommand},
    {CLS, "formShow",         "()V",                                             n_formShow},
    {CLS, "showCanvas",       "()V",                                             n_showCanvas},
    {CLS, "listAddItem",      "(Ljava/lang/String;Z)V",                          n_listAddItem},
    {CLS, "setListType",      "(I)V",                                            n_setListType},
    {CLS, "setAlertText",     "(Ljava/lang/String;I)V",                          n_setAlertText},
    {CLS, "platformRequest",  "(Ljava/lang/String;)V",                           n_platformRequest},
    {CLS, "getTextBoxText",   "()Ljava/lang/String;",                            n_getTextBoxText},
    {CLS, "setTextBoxText",   "(Ljava/lang/String;)V",                           n_setTextBoxText},
    {CLS, "getFormItemText",  "(I)Ljava/lang/String;",                           n_getFormItemText},
};

#undef CLS

void j2me_ui_reg_natives(MiniJVM *jvm) {
    native_reg_lib(jvm, j2me_ui_methods,
                   sizeof(j2me_ui_methods) / sizeof(java_native_method));
    printf("[J2ME UI] Registered %lu native methods\n",
           sizeof(j2me_ui_methods) / sizeof(java_native_method));
}
