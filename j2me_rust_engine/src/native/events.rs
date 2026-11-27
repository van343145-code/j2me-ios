//! Native Input Event Queue for gtt/vm/Events

use std::collections::VecDeque;
use std::sync::Mutex;

#[derive(Debug, Clone, Copy)]
pub struct InputEvent {
    pub event_type: i32,
    pub p1: i32,
    pub p2: i32,
    pub p3: i32,
}

pub struct EventQueue {
    queue: Mutex<VecDeque<InputEvent>>,
}

impl Default for EventQueue {
    fn default() -> Self {
        Self::new()
    }
}

impl EventQueue {
    pub fn new() -> Self {
        Self {
            queue: Mutex::new(VecDeque::with_capacity(64)),
        }
    }

    pub fn post(&self, event_type: i32, p1: i32, p2: i32, p3: i32) {
        let mut q = self.queue.lock().unwrap();
        q.push_back(InputEvent {
            event_type,
            p1,
            p2,
            p3,
        });
    }

    pub fn post_key_down(&self, key_code: i32) {
        self.post(3, key_code, 0, 0);
    }

    pub fn post_key_up(&self, key_code: i32) {
        self.post(4, key_code, 0, 0);
    }

    pub fn post_pointer_down(&self, x: i32, y: i32) {
        self.post(0, x, y, 0);
    }

    pub fn post_pointer_up(&self, x: i32, y: i32) {
        self.post(2, x, y, 0);
    }

    pub fn next(&self, out: &mut [i32]) -> bool {
        let mut q = self.queue.lock().unwrap();
        if let Some(ev) = q.pop_front() {
            if out.len() >= 4 {
                out[0] = ev.event_type;
                out[1] = ev.p1;
                out[2] = ev.p2;
                out[3] = ev.p3;
            }
            true
        } else {
            false
        }
    }
}

pub static GLOBAL_EVENTS: Mutex<Option<EventQueue>> = Mutex::new(None);

pub fn init_events() {
    let mut g = GLOBAL_EVENTS.lock().unwrap();
    *g = Some(EventQueue::new());
}

pub fn poll_event(out: &mut [i32]) -> bool {
    let g = GLOBAL_EVENTS.lock().unwrap();
    if let Some(eq) = g.as_ref() {
        eq.next(out)
    } else {
        false
    }
}

pub fn post_event(event_type: i32, p1: i32, p2: i32) {
    let g = GLOBAL_EVENTS.lock().unwrap();
    if let Some(eq) = g.as_ref() {
        eq.post(event_type, p1, p2, 0);
    }
}
