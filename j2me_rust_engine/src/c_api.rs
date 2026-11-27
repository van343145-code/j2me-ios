//! C Foreign Function Interface (FFI)
//! Enables Flutter (dart:ffi), iOS/Swift, Android (NDK), and C/C++ embedding

use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_int};
use std::slice;
use crate::session::J2meSession;

#[unsafe(no_mangle)]
pub unsafe extern "C" fn j2me_engine_create(
    storage_path: *const c_char,
    width: c_int,
    height: c_int,
) -> *mut J2meSession {
    let path = if storage_path.is_null() {
        "rms_data".to_string()
    } else {
        unsafe {
            match CStr::from_ptr(storage_path).to_str() {
                Ok(s) => s.to_string(),
                Err(_) => "rms_data".to_string(),
            }
        }
    };

    let session = Box::new(J2meSession::new(path, width, height));
    Box::into_raw(session)
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn j2me_engine_load_runtime(
    engine: *mut J2meSession,
    data: *const u8,
    len: usize,
) -> c_int {
    if engine.is_null() || data.is_null() || len == 0 {
        return -1;
    }
    let session = unsafe { &mut *engine };
    let bytes = unsafe { slice::from_raw_parts(data, len).to_vec() };
    match session.load_runtime_jar(bytes) {
        Ok(_) => 0,
        Err(_) => -2,
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn j2me_engine_load_jar(
    engine: *mut J2meSession,
    data: *const u8,
    len: usize,
) -> *mut c_char {
    if engine.is_null() || data.is_null() || len == 0 {
        return std::ptr::null_mut();
    }
    let session = unsafe { &mut *engine };
    let bytes = unsafe { slice::from_raw_parts(data, len).to_vec() };
    match session.load_game_jar(bytes) {
        Ok(main_class) => {
            if let Ok(c_str) = CString::new(main_class) {
                c_str.into_raw()
            } else {
                std::ptr::null_mut()
            }
        }
        Err(_) => std::ptr::null_mut(),
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn j2me_engine_free_string(s: *mut c_char) {
    if !s.is_null() {
        let _ = unsafe { CString::from_raw(s) };
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn j2me_engine_start(engine: *mut J2meSession) -> c_int {
    if engine.is_null() {
        return -1;
    }
    let session = unsafe { &mut *engine };
    match session.start() {
        Ok(_) => 0,
        Err(_) => -1,
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn j2me_engine_set_sleeping(engine: *mut J2meSession, sleeping: bool) {
    if !engine.is_null() {
        let session = unsafe { &*engine };
        session.set_sleeping(sleeping);
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn j2me_engine_is_sleeping(engine: *mut J2meSession) -> bool {
    if !engine.is_null() {
        let session = unsafe { &*engine };
        session.is_sleeping()
    } else {
        false
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn j2me_engine_send_key(
    engine: *mut J2meSession,
    key_code: c_int,
    is_down: bool,
) {
    if !engine.is_null() {
        let session = unsafe { &*engine };
        session.send_key(key_code, is_down);
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn j2me_engine_send_pointer(
    engine: *mut J2meSession,
    action: c_int,
    x: c_int,
    y: c_int,
) {
    if !engine.is_null() {
        let session = unsafe { &*engine };
        session.send_pointer(action, x, y);
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn j2me_engine_copy_frame(
    engine: *mut J2meSession,
    out_buffer: *mut u32,
    max_len: usize,
) -> c_int {
    if engine.is_null() || out_buffer.is_null() {
        return -1;
    }
    let session = unsafe { &*engine };
    let frame = session.get_screen_frame();
    let copy_len = frame.len().min(max_len);
    unsafe {
        std::ptr::copy_nonoverlapping(frame.as_ptr(), out_buffer, copy_len);
    }
    copy_len as c_int
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn j2me_engine_destroy(engine: *mut J2meSession) {
    if !engine.is_null() {
        let _ = unsafe { Box::from_raw(engine) };
    }
}
