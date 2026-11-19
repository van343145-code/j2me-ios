//! Native Display, Audio, and Lifecycle for gtt/vm/Midp

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Mutex;

pub struct MidpState {
    pub width: i32,
    pub height: i32,
    pub screen_buffer: Mutex<Vec<u32>>,
    pub is_sleeping: AtomicBool,
    pub is_dark_ui: bool,
    pub is_destroyed: AtomicBool,
}

impl MidpState {
    pub fn new(width: i32, height: i32) -> Self {
        let size = (width * height) as usize;
        Self {
            width,
            height,
            screen_buffer: Mutex::new(vec![0xFF000000; size]),
            is_sleeping: AtomicBool::new(false),
            is_dark_ui: true,
            is_destroyed: AtomicBool::new(false),
        }
    }

    pub fn set_sleeping(&self, sleeping: bool) {
        self.is_sleeping.store(sleeping, Ordering::Relaxed);
    }

    pub fn sleeping(&self) -> bool {
        self.is_sleeping.load(Ordering::Relaxed)
    }

    pub fn flush(&self, pixels: &[i32], w: i32, h: i32) {
        // If sleeping, skip buffer copying completely (Triệt tiêu render nền!)
        if self.sleeping() {
            return;
        }

        if let Ok(mut buf) = self.screen_buffer.lock() {
            if buf.len() != (w * h) as usize {
                buf.resize((w * h) as usize, 0);
            }
            // Copy pixels (converting i32 to u32 ARGB)
            for (dest, &src) in buf.iter_mut().zip(pixels.iter()) {
                *dest = src as u32;
            }
        }
    }

    pub fn get_frame(&self) -> Vec<u32> {
        self.screen_buffer.lock().unwrap().clone()
    }
}

pub static GLOBAL_MIDP: Mutex<Option<MidpState>> = Mutex::new(None);

pub fn init_midp(width: i32, height: i32) {
    let mut g = GLOBAL_MIDP.lock().unwrap();
    *g = Some(MidpState::new(width, height));
}

pub fn get_screen_size() -> (i32, i32) {
    let g = GLOBAL_MIDP.lock().unwrap();
    if let Some(state) = g.as_ref() {
        (state.width, state.height)
    } else {
        (240, 320)
    }
}

pub fn is_sleeping() -> bool {
    let g = GLOBAL_MIDP.lock().unwrap();
    g.as_ref().map(|s| s.sleeping()).unwrap_or(false)
}

pub fn set_sleeping(sleeping: bool) {
    let g = GLOBAL_MIDP.lock().unwrap();
    if let Some(s) = g.as_ref() {
        s.set_sleeping(sleeping);
    }
}

pub fn flush_screen(pixels: &[i32], w: i32, h: i32) {
    let g = GLOBAL_MIDP.lock().unwrap();
    if let Some(s) = g.as_ref() {
        s.flush(pixels, w, h);
    }
}
