//! J2ME Session Orchestrator
//! Coordinates Heap, ClassLoader, Bytecode Execution, and Native Subsystems

use std::path::Path;
use crate::frame::Frame;
use crate::heap::Heap;
use crate::interp::Interpreter;
use crate::jar::JarArchive;
use crate::loader::ClassLoader;
use crate::native::{events, midp, net, storage};
use crate::value::Value;

pub struct J2meSession {
    pub heap: Heap,
    pub loader: ClassLoader,
    pub main_class_name: Option<String>,
    pub midlet_ref: Option<usize>,
    pub width: i32,
    pub height: i32,
    pub is_running: bool,
}

impl J2meSession {
    pub fn new<P: AsRef<Path>>(storage_root: P, width: i32, height: i32) -> Self {
        midp::init_midp(width, height);
        events::init_events();
        net::init_net();
        storage::init_storage(storage_root);

        Self {
            heap: Heap::new(),
            loader: ClassLoader::new(),
            main_class_name: None,
            midlet_ref: None,
            width,
            height,
            is_running: false,
        }
    }

    pub fn load_runtime_jar(&mut self, jar_bytes: Vec<u8>) -> Result<(), String> {
        let jar = JarArchive::from_bytes(jar_bytes).map_err(|e| format!("{:?}", e))?;
        self.loader.add_jar(jar);
        Ok(())
    }

    pub fn load_game_jar(&mut self, jar_bytes: Vec<u8>) -> Result<String, String> {
        let jar = JarArchive::from_bytes(jar_bytes).map_err(|e| format!("{:?}", e))?;
        let manifest_midlet = jar.manifest.as_ref().and_then(|m| m.midlet_main_class());
        self.loader.add_jar(jar);

        if let Some(cls) = manifest_midlet {
            let normalized = cls.replace('.', "/");
            self.main_class_name = Some(normalized.clone());
            Ok(normalized)
        } else {
            Err("No MIDlet-1 entry found in MANIFEST.MF".into())
        }
    }

    pub fn start(&mut self) -> Result<(), String> {
        let main_cls = match &self.main_class_name {
            Some(c) => c.clone(),
            None => return Err("No main MIDlet class specified".into()),
        };

        // 1. Allocate MIDlet instance
        let midlet_id = self.heap.alloc_object(main_cls.clone());
        self.midlet_ref = Some(midlet_id);

        // 2. Load MIDlet class
        let cf = self.loader.load_class(&main_cls)
            .ok_or_else(|| format!("Class not found: {}", main_cls))?;

        // 3. Call <init>()
        if let Some((_, init_method)) = self.loader.resolve_method(&main_cls, "<init>", "()V") {
            if let Some(code_attr) = &init_method.code {
                let mut frame = Frame::new(code_attr.max_locals as usize, code_attr.max_stack as usize);
                frame.store_local(0, Value::Ref(Some(midlet_id)));
                let mut interp = Interpreter::new(&mut self.heap, &mut self.loader);
                let _ = interp.execute(&cf, &mut frame, &code_attr.code);
            }
        }

        // 4. Call startApp()
        if let Some((_, start_method)) = self.loader.resolve_method(&main_cls, "startApp", "()V") {
            if let Some(code_attr) = &start_method.code {
                let mut frame = Frame::new(code_attr.max_locals as usize, code_attr.max_stack as usize);
                frame.store_local(0, Value::Ref(Some(midlet_id)));
                let mut interp = Interpreter::new(&mut self.heap, &mut self.loader);
                let _ = interp.execute(&cf, &mut frame, &code_attr.code);
            }
        }

        self.is_running = true;
        Ok(())
    }

    pub fn set_sleeping(&self, sleeping: bool) {
        midp::set_sleeping(sleeping);
    }

    pub fn is_sleeping(&self) -> bool {
        midp::is_sleeping()
    }

    pub fn send_key(&self, key_code: i32, is_down: bool) {
        if is_down {
            events::post_event(3, key_code, 0); // Event 3 = KEY_PRESSED
        } else {
            events::post_event(4, key_code, 0); // Event 4 = KEY_RELEASED
        }
    }

    pub fn send_pointer(&self, action: i32, x: i32, y: i32) {
        // action: 0 = PRESSED, 1 = DRAGGED, 2 = RELEASED
        events::post_event(action, x, y);
    }

    pub fn get_screen_frame(&self) -> Vec<u32> {
        let g = midp::GLOBAL_MIDP.lock().unwrap();
        if let Some(s) = g.as_ref() {
            s.get_frame()
        } else {
            vec![0xFF000000; (self.width * self.height) as usize]
        }
    }
}
