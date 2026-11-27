#ifndef J2ME_ENGINE_H
#define J2ME_ENGINE_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void J2meSession;

// Lifecycle
J2meSession* j2me_engine_create(const char* storage_path, int32_t width, int32_t height);
int32_t j2me_engine_load_runtime(J2meSession* engine, const uint8_t* data, size_t len);
char* j2me_engine_load_jar(J2meSession* engine, const uint8_t* data, size_t len);
void j2me_engine_free_string(char* s);
int32_t j2me_engine_start(J2meSession* engine);
void j2me_engine_destroy(J2meSession* engine);

// Background / Sleep control (Triệt tiêu render nền)
void j2me_engine_set_sleeping(J2meSession* engine, bool sleeping);
bool j2me_engine_is_sleeping(J2meSession* engine);

// Input
void j2me_engine_send_key(J2meSession* engine, int32_t key_code, bool is_down);
void j2me_engine_send_pointer(J2meSession* engine, int32_t action, int32_t x, int32_t y);

// Framebuffer rendering
int32_t j2me_engine_copy_frame(J2meSession* engine, uint32_t* out_buffer, size_t max_len);

#ifdef __cplusplus
}
#endif

#endif // J2ME_ENGINE_H
