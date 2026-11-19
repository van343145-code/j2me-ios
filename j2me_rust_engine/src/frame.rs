//! JVM Stack Frame (Locals and Operand Stack)

use crate::value::Value;

#[derive(Debug)]
pub struct Frame {
    pub locals: Vec<Value>,
    pub stack: Vec<Value>,
    pub pc: usize,
}

impl Frame {
    pub fn new(max_locals: usize, max_stack: usize) -> Self {
        Self {
            locals: vec![Value::null(); max_locals],
            stack: Vec::with_capacity(max_stack),
            pc: 0,
        }
    }

    #[inline]
    pub fn push(&mut self, val: Value) {
        self.stack.push(val);
    }

    #[inline]
    pub fn pop(&mut self) -> Value {
        self.stack.pop().expect("Operand stack underflow")
    }

    #[inline]
    pub fn peek(&self) -> &Value {
        self.stack.last().expect("Operand stack is empty")
    }

    #[inline]
    pub fn load_local(&self, idx: usize) -> Value {
        self.locals[idx]
    }

    #[inline]
    pub fn store_local(&mut self, idx: usize, val: Value) {
        if idx >= self.locals.len() {
            self.locals.resize(idx + 1, Value::null());
        }
        self.locals[idx] = val;
    }
}
