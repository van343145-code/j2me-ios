//! JVM Bytecode Interpreter with Method Invocation, Fields, Arrays, and Native Dispatch

use std::sync::Arc;
use crate::classfile::{ClassFile, Constant};
use crate::frame::Frame;
use crate::heap::{ArrayData, Heap, HeapEntry};
use crate::loader::ClassLoader;
use crate::native::{NativeDispatcher, NativeResult};
use crate::value::Value;

pub enum InterpResult {
    Continue,
    Return(Option<Value>),
    Exception(usize),
}

pub struct Interpreter<'a> {
    pub heap: &'a mut Heap,
    pub loader: &'a mut ClassLoader,
}

pub fn parse_method_params_count(desc: &str) -> (usize, bool) {
    let mut count = 0;
    let mut chars = desc.chars();
    if chars.next() != Some('(') {
        return (0, false);
    }
    while let Some(c) = chars.next() {
        if c == ')' {
            break;
        }
        match c {
            'B' | 'C' | 'D' | 'F' | 'I' | 'J' | 'S' | 'Z' => count += 1,
            'L' => {
                for ch in chars.by_ref() {
                    if ch == ';' {
                        break;
                    }
                }
                count += 1;
            }
            '[' => {
                for ch in chars.by_ref() {
                    if ch != '[' {
                        if ch == 'L' {
                            for sub in chars.by_ref() {
                                if sub == ';' {
                                    break;
                                }
                            }
                        }
                        break;
                    }
                }
                count += 1;
            }
            _ => {}
        }
    }
    let has_return = chars.next() != Some('V');
    (count, has_return)
}

impl<'a> Interpreter<'a> {
    pub fn new(heap: &'a mut Heap, loader: &'a mut ClassLoader) -> Self {
        Self { heap, loader }
    }

    pub fn execute(&mut self, current_class: &Arc<ClassFile>, frame: &mut Frame, code: &[u8]) -> InterpResult {
        while frame.pc < code.len() {
            let opcode = code[frame.pc];
            frame.pc += 1;

            match opcode {
                // nop
                0x00 => {}

                // aconst_null
                0x01 => frame.push(Value::null()),

                // iconst_m1 .. iconst_5
                0x02 => frame.push(Value::Int(-1)),
                0x03 => frame.push(Value::Int(0)),
                0x04 => frame.push(Value::Int(1)),
                0x05 => frame.push(Value::Int(2)),
                0x06 => frame.push(Value::Int(3)),
                0x07 => frame.push(Value::Int(4)),
                0x08 => frame.push(Value::Int(5)),

                // lconst_0, lconst_1
                0x09 => frame.push(Value::Long(0)),
                0x0A => frame.push(Value::Long(1)),

                // fconst_0 .. fconst_2
                0x0B => frame.push(Value::Float(0.0)),
                0x0C => frame.push(Value::Float(1.0)),
                0x0D => frame.push(Value::Float(2.0)),

                // dconst_0, dconst_1
                0x0E => frame.push(Value::Double(0.0)),
                0x0F => frame.push(Value::Double(1.0)),

                // bipush
                0x10 => {
                    let byte = code[frame.pc] as i8;
                    frame.pc += 1;
                    frame.push(Value::Int(byte as i32));
                }

                // sipush
                0x11 => {
                    let val = i16::from_be_bytes([code[frame.pc], code[frame.pc + 1]]);
                    frame.pc += 2;
                    frame.push(Value::Int(val as i32));
                }

                // ldc
                0x12 => {
                    let idx = code[frame.pc] as usize;
                    frame.pc += 1;
                    self.push_constant(current_class, frame, idx);
                }

                // ldc_w
                0x13 => {
                    let idx = u16::from_be_bytes([code[frame.pc], code[frame.pc + 1]]) as usize;
                    frame.pc += 2;
                    self.push_constant(current_class, frame, idx);
                }

                // ldc2_w
                0x14 => {
                    let idx = u16::from_be_bytes([code[frame.pc], code[frame.pc + 1]]) as usize;
                    frame.pc += 2;
                    self.push_constant(current_class, frame, idx);
                }

                // iload
                0x15 => {
                    let idx = code[frame.pc] as usize;
                    frame.pc += 1;
                    frame.push(frame.load_local(idx));
                }

                // lload
                0x16 => {
                    let idx = code[frame.pc] as usize;
                    frame.pc += 1;
                    frame.push(frame.load_local(idx));
                }

                // fload
                0x17 => {
                    let idx = code[frame.pc] as usize;
                    frame.pc += 1;
                    frame.push(frame.load_local(idx));
                }

                // dload
                0x18 => {
                    let idx = code[frame.pc] as usize;
                    frame.pc += 1;
                    frame.push(frame.load_local(idx));
                }

                // aload
                0x19 => {
                    let idx = code[frame.pc] as usize;
                    frame.pc += 1;
                    frame.push(frame.load_local(idx));
                }

                // iload_0 .. iload_3
                0x1A => frame.push(frame.load_local(0)),
                0x1B => frame.push(frame.load_local(1)),
                0x1C => frame.push(frame.load_local(2)),
                0x1D => frame.push(frame.load_local(3)),

                // lload_0 .. lload_3
                0x1E => frame.push(frame.load_local(0)),
                0x1F => frame.push(frame.load_local(1)),
                0x20 => frame.push(frame.load_local(2)),
                0x21 => frame.push(frame.load_local(3)),

                // fload_0 .. fload_3
                0x22 => frame.push(frame.load_local(0)),
                0x23 => frame.push(frame.load_local(1)),
                0x24 => frame.push(frame.load_local(2)),
                0x25 => frame.push(frame.load_local(3)),

                // dload_0 .. dload_3
                0x26 => frame.push(frame.load_local(0)),
                0x27 => frame.push(frame.load_local(1)),
                0x28 => frame.push(frame.load_local(2)),
                0x29 => frame.push(frame.load_local(3)),

                // aload_0 .. aload_3
                0x2A => frame.push(frame.load_local(0)),
                0x2B => frame.push(frame.load_local(1)),
                0x2C => frame.push(frame.load_local(2)),
                0x2D => frame.push(frame.load_local(3)),

                // iaload
                0x2E => {
                    let idx = frame.pop().as_int() as usize;
                    let arr_ref = frame.pop().as_ref().expect("NullPointerException");
                    if let Some(arr) = self.heap.get_int_array_mut(arr_ref) {
                        frame.push(Value::Int(arr[idx]));
                    }
                }

                // baload
                0x33 => {
                    let idx = frame.pop().as_int() as usize;
                    let arr_ref = frame.pop().as_ref().expect("NullPointerException");
                    if let Some(arr) = self.heap.get_byte_array(arr_ref) {
                        frame.push(Value::Int(arr[idx] as i32));
                    }
                }

                // caload
                0x34 => {
                    let idx = frame.pop().as_int() as usize;
                    let arr_ref = frame.pop().as_ref().expect("NullPointerException");
                    if let Some(HeapEntry::Array(ArrayData::Char(arr))) = self.heap.get(arr_ref) {
                        frame.push(Value::Int(arr[idx] as i32));
                    }
                }

                // saload
                0x35 => {
                    let idx = frame.pop().as_int() as usize;
                    let arr_ref = frame.pop().as_ref().expect("NullPointerException");
                    if let Some(HeapEntry::Array(ArrayData::Short(arr))) = self.heap.get(arr_ref) {
                        frame.push(Value::Int(arr[idx] as i32));
                    }
                }

                // aaload
                0x32 => {
                    let idx = frame.pop().as_int() as usize;
                    let arr_ref = frame.pop().as_ref().expect("NullPointerException");
                    if let Some(HeapEntry::Array(ArrayData::Ref(arr))) = self.heap.get(arr_ref) {
                        frame.push(Value::Ref(arr[idx]));
                    }
                }

                // istore
                0x36 => {
                    let idx = code[frame.pc] as usize;
                    frame.pc += 1;
                    let val = frame.pop();
                    frame.store_local(idx, val);
                }

                // lstore
                0x37 => {
                    let idx = code[frame.pc] as usize;
                    frame.pc += 1;
                    let val = frame.pop();
                    frame.store_local(idx, val);
                }

                // astore
                0x3A => {
                    let idx = code[frame.pc] as usize;
                    frame.pc += 1;
                    let val = frame.pop();
                    frame.store_local(idx, val);
                }

                // istore_0 .. istore_3
                0x3B => { let v = frame.pop(); frame.store_local(0, v); }
                0x3C => { let v = frame.pop(); frame.store_local(1, v); }
                0x3D => { let v = frame.pop(); frame.store_local(2, v); }
                0x3E => { let v = frame.pop(); frame.store_local(3, v); }

                // lstore_0 .. lstore_3
                0x3F => { let v = frame.pop(); frame.store_local(0, v); }
                0x40 => { let v = frame.pop(); frame.store_local(1, v); }
                0x41 => { let v = frame.pop(); frame.store_local(2, v); }
                0x42 => { let v = frame.pop(); frame.store_local(3, v); }

                // astore_0 .. astore_3
                0x4B => { let v = frame.pop(); frame.store_local(0, v); }
                0x4C => { let v = frame.pop(); frame.store_local(1, v); }
                0x4D => { let v = frame.pop(); frame.store_local(2, v); }
                0x4E => { let v = frame.pop(); frame.store_local(3, v); }

                // iastore
                0x4F => {
                    let val = frame.pop().as_int();
                    let idx = frame.pop().as_int() as usize;
                    let arr_ref = frame.pop().as_ref().expect("NullPointerException");
                    if let Some(arr) = self.heap.get_int_array_mut(arr_ref) {
                        arr[idx] = val;
                    }
                }

                // bastore
                0x54 => {
                    let val = frame.pop().as_int() as i8;
                    let idx = frame.pop().as_int() as usize;
                    let arr_ref = frame.pop().as_ref().expect("NullPointerException");
                    if let Some(arr) = self.heap.get_byte_array_mut(arr_ref) {
                        arr[idx] = val;
                    }
                }

                // aastore
                0x53 => {
                    let val = frame.pop().as_ref();
                    let idx = frame.pop().as_int() as usize;
                    let arr_ref = frame.pop().as_ref().expect("NullPointerException");
                    if let Some(HeapEntry::Array(ArrayData::Ref(arr))) = self.heap.get_mut(arr_ref) {
                        arr[idx] = val;
                    }
                }

                // pop
                0x57 => { let _ = frame.pop(); }

                // pop2
                0x58 => { let _ = frame.pop(); let _ = frame.pop(); }

                // dup
                0x59 => {
                    let top = *frame.peek();
                    frame.push(top);
                }

                // dup_x1
                0x5A => {
                    let v1 = frame.pop();
                    let v2 = frame.pop();
                    frame.push(v1);
                    frame.push(v2);
                    frame.push(v1);
                }

                // swap
                0x5F => {
                    let v1 = frame.pop();
                    let v2 = frame.pop();
                    frame.push(v1);
                    frame.push(v2);
                }

                // iadd
                0x60 => {
                    let b = frame.pop().as_int();
                    let a = frame.pop().as_int();
                    frame.push(Value::Int(a.wrapping_add(b)));
                }

                // isub
                0x64 => {
                    let b = frame.pop().as_int();
                    let a = frame.pop().as_int();
                    frame.push(Value::Int(a.wrapping_sub(b)));
                }

                // imul
                0x68 => {
                    let b = frame.pop().as_int();
                    let a = frame.pop().as_int();
                    frame.push(Value::Int(a.wrapping_mul(b)));
                }

                // idiv
                0x6C => {
                    let b = frame.pop().as_int();
                    let a = frame.pop().as_int();
                    if b == 0 {
                        panic!("ArithmeticException: / by zero");
                    }
                    frame.push(Value::Int(a.wrapping_div(b)));
                }

                // irem
                0x70 => {
                    let b = frame.pop().as_int();
                    let a = frame.pop().as_int();
                    if b == 0 {
                        panic!("ArithmeticException: / by zero");
                    }
                    frame.push(Value::Int(a.wrapping_rem(b)));
                }

                // ineg
                0x74 => {
                    let a = frame.pop().as_int();
                    frame.push(Value::Int(-a));
                }

                // ishl
                0x78 => {
                    let b = frame.pop().as_int() & 0x1F;
                    let a = frame.pop().as_int();
                    frame.push(Value::Int(a << b));
                }

                // ishr
                0x7A => {
                    let b = frame.pop().as_int() & 0x1F;
                    let a = frame.pop().as_int();
                    frame.push(Value::Int(a >> b));
                }

                // iushr
                0x7C => {
                    let b = frame.pop().as_int() & 0x1F;
                    let a = frame.pop().as_int() as u32;
                    frame.push(Value::Int((a >> b) as i32));
                }

                // iand
                0x7E => {
                    let b = frame.pop().as_int();
                    let a = frame.pop().as_int();
                    frame.push(Value::Int(a & b));
                }

                // ior
                0x80 => {
                    let b = frame.pop().as_int();
                    let a = frame.pop().as_int();
                    frame.push(Value::Int(a | b));
                }

                // ixor
                0x82 => {
                    let b = frame.pop().as_int();
                    let a = frame.pop().as_int();
                    frame.push(Value::Int(a ^ b));
                }

                // iinc
                0x84 => {
                    let idx = code[frame.pc] as usize;
                    let const_val = code[frame.pc + 1] as i8 as i32;
                    frame.pc += 2;
                    let cur = frame.load_local(idx).as_int();
                    frame.store_local(idx, Value::Int(cur.wrapping_add(const_val)));
                }

                // i2b
                0x91 => {
                    let val = frame.pop().as_int() as i8 as i32;
                    frame.push(Value::Int(val));
                }

                // i2c
                0x92 => {
                    let val = frame.pop().as_int() as u16 as i32;
                    frame.push(Value::Int(val));
                }

                // i2s
                0x93 => {
                    let val = frame.pop().as_int() as i16 as i32;
                    frame.push(Value::Int(val));
                }

                // ifeq .. ifle
                0x99..=0x9E => {
                    let op_pc = (frame.pc - 1) as isize;
                    let offset = i16::from_be_bytes([code[frame.pc], code[frame.pc + 1]]) as isize;
                    frame.pc += 2;
                    let val = frame.pop().as_int();
                    let cond = match opcode {
                        0x99 => val == 0,
                        0x9A => val != 0,
                        0x9B => val < 0,
                        0x9C => val >= 0,
                        0x9D => val > 0,
                        0x9E => val <= 0,
                        _ => unreachable!(),
                    };
                    if cond {
                        frame.pc = (op_pc + offset) as usize;
                    }
                }

                // if_icmpeq .. if_icmple
                0x9F..=0xA4 => {
                    let op_pc = (frame.pc - 1) as isize;
                    let offset = i16::from_be_bytes([code[frame.pc], code[frame.pc + 1]]) as isize;
                    frame.pc += 2;
                    let b = frame.pop().as_int();
                    let a = frame.pop().as_int();
                    let cond = match opcode {
                        0x9F => a == b,
                        0xA0 => a != b,
                        0xA1 => a < b,
                        0xA2 => a >= b,
                        0xA3 => a > b,
                        0xA4 => a <= b,
                        _ => unreachable!(),
                    };
                    if cond {
                        frame.pc = (op_pc + offset) as usize;
                    }
                }

                // goto
                0xA7 => {
                    let op_pc = (frame.pc - 1) as isize;
                    let offset = i16::from_be_bytes([code[frame.pc], code[frame.pc + 1]]) as isize;
                    frame.pc = (op_pc + offset) as usize;
                }

                // ireturn, areturn, lreturn, freturn, dreturn
                0xAC | 0xAD | 0xAE | 0xAF | 0xB0 => {
                    return InterpResult::Return(Some(frame.pop()));
                }

                // return
                0xB1 => return InterpResult::Return(None),

                // getstatic
                0xB2 => {
                    let cp_idx = u16::from_be_bytes([code[frame.pc], code[frame.pc + 1]]);
                    frame.pc += 2;
                    let (cls_name, field_name, _) = ClassFile::resolve_field_ref(&current_class.constant_pool, cp_idx)
                        .expect("Field resolution failed");
                    let val = self.loader.get_static(&cls_name, &field_name);
                    frame.push(val);
                }

                // putstatic
                0xB3 => {
                    let cp_idx = u16::from_be_bytes([code[frame.pc], code[frame.pc + 1]]);
                    frame.pc += 2;
                    let (cls_name, field_name, _) = ClassFile::resolve_field_ref(&current_class.constant_pool, cp_idx)
                        .expect("Field resolution failed");
                    let val = frame.pop();
                    self.loader.put_static(&cls_name, &field_name, val);
                }

                // getfield
                0xB4 => {
                    let cp_idx = u16::from_be_bytes([code[frame.pc], code[frame.pc + 1]]);
                    frame.pc += 2;
                    let (_, field_name, _) = ClassFile::resolve_field_ref(&current_class.constant_pool, cp_idx)
                        .expect("Field resolution failed");
                    let obj_ref = frame.pop().as_ref().expect("NullPointerException");
                    if let Some(HeapEntry::Object(obj)) = self.heap.get(obj_ref) {
                        let val = obj.fields.get(&field_name).copied().unwrap_or(Value::Int(0));
                        frame.push(val);
                    } else {
                        frame.push(Value::Int(0));
                    }
                }

                // putfield
                0xB5 => {
                    let cp_idx = u16::from_be_bytes([code[frame.pc], code[frame.pc + 1]]);
                    frame.pc += 2;
                    let (_, field_name, _) = ClassFile::resolve_field_ref(&current_class.constant_pool, cp_idx)
                        .expect("Field resolution failed");
                    let val = frame.pop();
                    let obj_ref = frame.pop().as_ref().expect("NullPointerException");
                    if let Some(HeapEntry::Object(obj)) = self.heap.get_mut(obj_ref) {
                        obj.fields.insert(field_name, val);
                    }
                }

                // invokevirtual (0xB6), invokespecial (0xB7), invokestatic (0xB8)
                0xB6..=0xB8 => {
                    let cp_idx = u16::from_be_bytes([code[frame.pc], code[frame.pc + 1]]);
                    frame.pc += 2;
                    let (cls_name, m_name, m_desc) = ClassFile::resolve_method_ref(&current_class.constant_pool, cp_idx)
                        .expect("Method resolution failed");
                    let (param_count, has_return) = parse_method_params_count(&m_desc);

                    let mut args = Vec::with_capacity(param_count + 1);
                    for _ in 0..param_count {
                        args.push(frame.pop());
                    }
                    args.reverse();

                    // invokevirtual / invokespecial also take `this`
                    if opcode != 0xB8 {
                        let this_ref = frame.pop();
                        args.insert(0, this_ref);
                    }

                    // Check NativeDispatcher first
                    if let Some(native_res) = NativeDispatcher::dispatch(&cls_name, &m_name, &m_desc, &args, self.heap) {
                        match native_res {
                            NativeResult::Void => {}
                            NativeResult::Value(v) => frame.push(v),
                            NativeResult::Exception(e) => panic!("Java Exception in native: {}", e),
                        }
                    } else {
                        // Resolve Java method and execute in child frame
                        if let Some((target_class, target_method)) = self.loader.resolve_method(&cls_name, &m_name, &m_desc) {
                            if let Some(code_attr) = &target_method.code {
                                let mut child_frame = Frame::new(code_attr.max_locals as usize, code_attr.max_stack as usize);
                                for (i, arg) in args.into_iter().enumerate() {
                                    child_frame.store_local(i, arg);
                                }
                                let res = self.execute(&target_class, &mut child_frame, &code_attr.code);
                                if let InterpResult::Return(Some(ret_val)) = res {
                                    if has_return {
                                        frame.push(ret_val);
                                    }
                                }
                            }
                        }
                    }
                }

                // new
                0xBB => {
                    let cp_idx = u16::from_be_bytes([code[frame.pc], code[frame.pc + 1]]);
                    frame.pc += 2;
                    let cls_name = ClassFile::resolve_class_name(&current_class.constant_pool, cp_idx)
                        .expect("Class resolution failed");
                    let obj_id = self.heap.alloc_object(cls_name);
                    frame.push(Value::Ref(Some(obj_id)));
                }

                // newarray
                0xBC => {
                    let atype = code[frame.pc];
                    frame.pc += 1;
                    let count = frame.pop().as_int() as usize;
                    let data = match atype {
                        4 => ArrayData::Boolean(vec![false; count]),
                        5 => ArrayData::Char(vec![0; count]),
                        6 => ArrayData::Float(vec![0.0; count]),
                        7 => ArrayData::Double(vec![0.0; count]),
                        8 => ArrayData::Byte(vec![0; count]),
                        9 => ArrayData::Short(vec![0; count]),
                        10 => ArrayData::Int(vec![0; count]),
                        11 => ArrayData::Long(vec![0; count]),
                        _ => panic!("Invalid array type {}", atype),
                    };
                    let arr_id = self.heap.alloc_array(data);
                    frame.push(Value::Ref(Some(arr_id)));
                }

                // anewarray
                0xBD => {
                    let _cp_idx = u16::from_be_bytes([code[frame.pc], code[frame.pc + 1]]);
                    frame.pc += 2;
                    let count = frame.pop().as_int() as usize;
                    let arr_id = self.heap.alloc_array(ArrayData::Ref(vec![None; count]));
                    frame.push(Value::Ref(Some(arr_id)));
                }

                // arraylength
                0xBE => {
                    let arr_ref = frame.pop().as_ref().expect("NullPointerException");
                    let len = match self.heap.get(arr_ref) {
                        Some(HeapEntry::Array(arr)) => arr.len(),
                        _ => panic!("Expected array"),
                    };
                    frame.push(Value::Int(len as i32));
                }

                // ifnull, ifnonnull
                0xC6 | 0xC7 => {
                    let offset = i16::from_be_bytes([code[frame.pc], code[frame.pc + 1]]) as isize;
                    frame.pc += 2;
                    let val = frame.pop();
                    let is_null = val.is_null();
                    let cond = if opcode == 0xC6 { is_null } else { !is_null };
                    if cond {
                        frame.pc = ((frame.pc as isize) - 3 + offset) as usize;
                    }
                }

                _ => unimplemented!("Opcode 0x{:02X} not implemented yet", opcode),
            }
        }

        InterpResult::Return(None)
    }

    fn push_constant(&mut self, current_class: &ClassFile, frame: &mut Frame, idx: usize) {
        match &current_class.constant_pool[idx] {
            Constant::Integer(v) => frame.push(Value::Int(*v)),
            Constant::Float(v) => frame.push(Value::Float(*v)),
            Constant::Long(v) => frame.push(Value::Long(*v)),
            Constant::Double(v) => frame.push(Value::Double(*v)),
            Constant::StringRef { string_index } => {
                let s = ClassFile::resolve_utf8(&current_class.constant_pool, *string_index).unwrap();
                let ref_id = self.heap.alloc_string(s);
                frame.push(Value::Ref(Some(ref_id)));
            }
            _ => panic!("Unsupported constant in ldc at index {}", idx),
        }
    }
}
