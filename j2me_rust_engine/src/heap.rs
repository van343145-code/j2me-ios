//! JVM Heap (Object, Array, and String storage)

use std::collections::HashMap;
use crate::value::Value;

#[derive(Debug, Clone)]
pub struct JavaObject {
    pub class_name: String,
    pub fields: HashMap<String, Value>,
}

#[derive(Debug, Clone)]
pub enum ArrayData {
    Boolean(Vec<bool>),
    Byte(Vec<i8>),
    Char(Vec<u16>),
    Short(Vec<i16>),
    Int(Vec<i32>),
    Long(Vec<i64>),
    Float(Vec<f32>),
    Double(Vec<f64>),
    Ref(Vec<Option<usize>>),
}

impl ArrayData {
    pub fn len(&self) -> usize {
        match self {
            Self::Boolean(v) => v.len(),
            Self::Byte(v) => v.len(),
            Self::Char(v) => v.len(),
            Self::Short(v) => v.len(),
            Self::Int(v) => v.len(),
            Self::Long(v) => v.len(),
            Self::Float(v) => v.len(),
            Self::Double(v) => v.len(),
            Self::Ref(v) => v.len(),
        }
    }

    pub fn is_empty(&self) -> bool {
        self.len() == 0
    }
}

#[derive(Debug, Clone)]
pub enum HeapEntry {
    Object(JavaObject),
    Array(ArrayData),
    String(String),
}

pub struct Heap {
    entries: Vec<Option<HeapEntry>>,
    free_slots: Vec<usize>,
}

impl Heap {
    pub fn new() -> Self {
        Self {
            entries: Vec::with_capacity(1024),
            free_slots: Vec::new(),
        }
    }

    pub fn alloc_object(&mut self, class_name: String) -> usize {
        let obj = JavaObject {
            class_name,
            fields: HashMap::new(),
        };
        self.insert_entry(HeapEntry::Object(obj))
    }

    pub fn alloc_array(&mut self, data: ArrayData) -> usize {
        self.insert_entry(HeapEntry::Array(data))
    }

    pub fn alloc_string(&mut self, s: String) -> usize {
        self.insert_entry(HeapEntry::String(s))
    }

    pub fn alloc_int_array(&mut self, v: Vec<i32>) -> usize {
        self.alloc_array(ArrayData::Int(v))
    }

    pub fn alloc_byte_array(&mut self, v: Vec<u8>) -> usize {
        let i8_vec: Vec<i8> = v.into_iter().map(|b| b as i8).collect();
        self.alloc_array(ArrayData::Byte(i8_vec))
    }

    pub fn get(&self, id: usize) -> Option<&HeapEntry> {
        self.entries.get(id).and_then(|e| e.as_ref())
    }

    pub fn get_mut(&mut self, id: usize) -> Option<&mut HeapEntry> {
        self.entries.get_mut(id).and_then(|e| e.as_mut())
    }

    pub fn get_string(&self, id: usize) -> Option<String> {
        match self.get(id) {
            Some(HeapEntry::String(s)) => Some(s.clone()),
            _ => None,
        }
    }

    pub fn get_int_array_mut(&mut self, id: usize) -> Option<&mut Vec<i32>> {
        match self.get_mut(id) {
            Some(HeapEntry::Array(ArrayData::Int(v))) => Some(v),
            _ => None,
        }
    }

    pub fn get_byte_array_mut(&mut self, id: usize) -> Option<&mut Vec<i8>> {
        match self.get_mut(id) {
            Some(HeapEntry::Array(ArrayData::Byte(v))) => Some(v),
            _ => None,
        }
    }

    pub fn get_byte_array(&self, id: usize) -> Option<&Vec<i8>> {
        match self.get(id) {
            Some(HeapEntry::Array(ArrayData::Byte(v))) => Some(v),
            _ => None,
        }
    }

    pub fn free(&mut self, id: usize) {
        if let Some(entry) = self.entries.get_mut(id) {
            *entry = None;
            self.free_slots.push(id);
        }
    }

    fn insert_entry(&mut self, entry: HeapEntry) -> usize {
        if let Some(slot) = self.free_slots.pop() {
            self.entries[slot] = Some(entry);
            slot
        } else {
            let id = self.entries.len();
            self.entries.push(Some(entry));
            id
        }
    }
}
