//! Class Loader and Registry

use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use crate::classfile::{ClassFile, MethodInfo};
use crate::jar::JarArchive;
use crate::value::Value;

pub struct ClassLoader {
    pub classes: HashMap<String, Arc<ClassFile>>,
    pub static_fields: HashMap<String, HashMap<String, Value>>,
    jars: Vec<Arc<Mutex<JarArchive>>>,
}

impl ClassLoader {
    pub fn new() -> Self {
        Self {
            classes: HashMap::new(),
            static_fields: HashMap::new(),
            jars: Vec::new(),
        }
    }

    pub fn add_jar(&mut self, jar: JarArchive) {
        self.jars.push(Arc::new(Mutex::new(jar)));
    }

    pub fn load_class(&mut self, class_name: &str) -> Option<Arc<ClassFile>> {
        let normalized = class_name.replace('.', "/");
        if let Some(cf) = self.classes.get(&normalized) {
            return Some(Arc::clone(cf));
        }

        // Search in loaded JARs
        let file_path = format!("{}.class", normalized);
        for jar_arc in &self.jars {
            let mut jar = jar_arc.lock().unwrap();
            if let Some(bytes) = jar.read_file(&file_path) {
                if let Ok(cf) = ClassFile::parse(&bytes) {
                    let cf_arc = Arc::new(cf);
                    self.classes.insert(normalized.clone(), Arc::clone(&cf_arc));
                    return Some(cf_arc);
                }
            }
        }

        None
    }

    pub fn resolve_method(&mut self, class_name: &str, method_name: &str, desc: &str) -> Option<(Arc<ClassFile>, MethodInfo)> {
        let mut cur_name = class_name.to_string();
        loop {
            if let Some(cf) = self.load_class(&cur_name) {
                if let Some(m) = cf.methods.iter().find(|m| m.name == method_name && m.descriptor == desc).cloned() {
                    return Some((cf, m));
                }
                if let Some(super_name) = &cf.super_class {
                    cur_name = super_name.clone();
                } else {
                    break;
                }
            } else {
                break;
            }
        }
        None
    }

    pub fn get_static(&self, class_name: &str, field_name: &str) -> Value {
        self.static_fields
            .get(class_name)
            .and_then(|f| f.get(field_name))
            .copied()
            .unwrap_or(Value::Int(0))
    }

    pub fn put_static(&mut self, class_name: &str, field_name: &str, val: Value) {
        self.static_fields
            .entry(class_name.to_string())
            .or_default()
            .insert(field_name.to_string(), val);
    }
}
