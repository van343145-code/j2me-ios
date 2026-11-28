#ifndef J2ME_RENDER_H
#define J2ME_RENDER_H

#include "jvm.h"

#ifdef __cplusplus
extern "C" {
#endif

/// Register all J2ME rendering native methods with the JVM.
void j2me_render_reg_natives(MiniJVM *jvm);

/// Callback type for pixel flush — called when a frame is ready to display.
/// @param cgImage A CGImageRef containing the rendered frame. Caller must CFRelease.
/// @param width   Image width
/// @param height  Image height
typedef void (*j2me_flush_callback)(void *cgImage, int width, int height);

/// Per-slot flush callback — receives slot index so Swift can update tab thumbnails.
typedef void (*j2me_slot_flush_callback)(int slot, void *cgImage, int width, int height);

/// Set the callback for receiving rendered frames.
void j2me_render_set_flush_callback(j2me_flush_callback callback);

/// Set the per-slot flush callback.
void j2me_render_set_slot_flush_callback(j2me_slot_flush_callback callback);

/// Signal render subsystem to stop (all acquire calls return NULL).
/// Must be called before cleanup to protect against zombie threads.
void j2me_render_stop(void);

/// Clean up all render resources. Call between game sessions (after j2me_render_stop).
void j2me_render_cleanup(void);

/// Enable/disable background low-CPU mode (skips screen CG rasterization & CGImage flush
/// while keeping JVM logic, offscreen Image operations, and network sockets running 100%).
void j2me_render_set_background(int is_bg);

/// Query whether the app is currently in background low-CPU render bypass mode.
int j2me_render_is_background(void);

/// Enable/disable multi-slot split-view rendering (when 0, non-focused tabs skip screen CG draws & flushes).
void j2me_render_set_split_view(int active);

/// Query whether multi-slot split-view rendering is active.
int j2me_render_is_split_view_active(void);

/// Set live runtime FPS limit (0 = unlimited, default 30). Takes effect immediately.
void j2me_render_set_fps_limit(int fps);

/// Get current live runtime FPS limit.
int j2me_render_get_fps_limit(void);

/// Immediately free all queued dead RenderContext/RenderImage shells.
void j2me_render_purge_dead_shells(void);

/// Dynamically requests an unlimited background assertion (BKSProcessAssertion/RBSAssertion)
/// from iOS RunningBoard to prevent app suspension when screen is turned off.
void decade_acquire_unlimited_background_assertion(void);

/// Releases the unlimited background assertion when keepalive is turned off.
void decade_release_unlimited_background_assertion(void);

#ifdef __cplusplus
}
#endif

#endif /* J2ME_RENDER_H */
