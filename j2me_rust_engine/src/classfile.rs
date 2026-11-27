//! Java .class file parser according to JVM Specification Chapter 4.
//! Supports CLDC 1.1 / Java 1.1 - Java 8 class formats.

use std::fmt;

#[derive(Debug, Clone)]
pub enum Constant {
    Utf8(String),
    Integer(i32),
    Float(f32),
    Long(i64),
    Double(f64),
    Class { name_index: u16 },
    StringRef { string_index: u16 },
    FieldRef { class_index: u16, name_and_type_index: u16 },
    MethodRef { class_index: u16, name_and_type_index: u16 },
    InterfaceMethodRef { class_index: u16, name_and_type_index: u16 },
    NameAndType { name_index: u16, descriptor_index: u16 },
    MethodHandle { reference_kind: u8, reference_index: u16 },
    MethodType { descriptor_index: u16 },
    Dynamic { bootstrap_method_attr_index: u16, name_and_type_index: u16 },
    InvokeDynamic { bootstrap_method_attr_index: u16, name_and_type_index: u16 },
    Module { name_index: u16 },
    Package { name_index: u16 },
    Placeholder, // Used for second slot of Long/Double
}

#[derive(Debug, Clone)]
pub struct ExceptionHandler {
    pub start_pc: u16,
    pub end_pc: u16,
    pub handler_pc: u16,
    pub catch_type: u16, // 0 means any/finally
}

#[derive(Debug, Clone)]
pub struct CodeAttribute {
    pub max_stack: u16,
    pub max_locals: u16,
    pub code: Vec<u8>,
    pub exception_table: Vec<ExceptionHandler>,
}

#[derive(Debug, Clone)]
pub struct AttributeInfo {
    pub name: String,
    pub data: Vec<u8>,
}

#[derive(Debug, Clone)]
pub struct FieldInfo {
    pub access_flags: u16,
    pub name: String,
    pub descriptor: String,
    pub constant_value: Option<Constant>,
}

#[derive(Debug, Clone)]
pub struct MethodInfo {
    pub access_flags: u16,
    pub name: String,
    pub descriptor: String,
    pub code: Option<CodeAttribute>,
}

#[derive(Debug, Clone)]
pub struct ClassFile {
    pub minor_version: u16,
    pub major_version: u16,
    pub constant_pool: Vec<Constant>,
    pub access_flags: u16,
    pub this_class: String,
    pub super_class: Option<String>,
    pub interfaces: Vec<String>,
    pub fields: Vec<FieldInfo>,
    pub methods: Vec<MethodInfo>,
}

#[derive(Debug)]
pub enum ClassParseError {
    UnexpectedEof,
    InvalidMagic(u32),
    UnsupportedConstantTag(u8),
    InvalidUtf8,
    InvalidIndex(u16),
}

impl fmt::Display for ClassParseError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::UnexpectedEof => write!(f, "Unexpected EOF while parsing classfile"),
            Self::InvalidMagic(m) => write!(f, "Invalid class magic: 0x{:08X}", m),
            Self::UnsupportedConstantTag(t) => write!(f, "Unsupported constant pool tag: {}", t),
            Self::InvalidUtf8 => write!(f, "Invalid UTF-8 in Utf8 constant"),
            Self::InvalidIndex(idx) => write!(f, "Invalid constant pool index: {}", idx),
        }
    }
}

impl std::error::Error for ClassParseError {}

struct ByteReader<'a> {
    data: &'a [u8],
    offset: usize,
}

impl<'a> ByteReader<'a> {
    fn new(data: &'a [u8]) -> Self {
        Self { data, offset: 0 }
    }

    fn read_u8(&mut self) -> Result<u8, ClassParseError> {
        if self.offset < self.data.len() {
            let b = self.data[self.offset];
            self.offset += 1;
            Ok(b)
        } else {
            Err(ClassParseError::UnexpectedEof)
        }
    }

    fn read_u16(&mut self) -> Result<u16, ClassParseError> {
        if self.offset + 2 <= self.data.len() {
            let val = u16::from_be_bytes([self.data[self.offset], self.data[self.offset + 1]]);
            self.offset += 2;
            Ok(val)
        } else {
            Err(ClassParseError::UnexpectedEof)
        }
    }

    fn read_u32(&mut self) -> Result<u32, ClassParseError> {
        if self.offset + 4 <= self.data.len() {
            let val = u32::from_be_bytes([
                self.data[self.offset],
                self.data[self.offset + 1],
                self.data[self.offset + 2],
                self.data[self.offset + 3],
            ]);
            self.offset += 4;
            Ok(val)
        } else {
            Err(ClassParseError::UnexpectedEof)
        }
    }

    fn read_bytes(&mut self, len: usize) -> Result<&'a [u8], ClassParseError> {
        if self.offset + len <= self.data.len() {
            let slice = &self.data[self.offset..self.offset + len];
            self.offset += len;
            Ok(slice)
        } else {
            Err(ClassParseError::UnexpectedEof)
        }
    }
}

impl ClassFile {
    pub fn parse(bytes: &[u8]) -> Result<Self, ClassParseError> {
        let mut reader = ByteReader::new(bytes);

        // 1. Magic
        let magic = reader.read_u32()?;
        if magic != 0xCAFEBABE {
            return Err(ClassParseError::InvalidMagic(magic));
        }

        let minor_version = reader.read_u16()?;
        let major_version = reader.read_u16()?;

        // 2. Constant Pool (1-based indexing, slot 0 is dummy)
        let cp_count = reader.read_u16()? as usize;
        let mut cp = Vec::with_capacity(cp_count);
        cp.push(Constant::Placeholder); // index 0

        let mut i = 1;
        while i < cp_count {
            let tag = reader.read_u8()?;
            match tag {
                1 => {
                    // CONSTANT_Utf8
                    let len = reader.read_u16()? as usize;
                    let raw = reader.read_bytes(len)?;
                    let s = String::from_utf8_lossy(raw).into_owned();
                    cp.push(Constant::Utf8(s));
                    i += 1;
                }
                3 => {
                    // CONSTANT_Integer
                    let val = reader.read_u32()? as i32;
                    cp.push(Constant::Integer(val));
                    i += 1;
                }
                4 => {
                    // CONSTANT_Float
                    let bits = reader.read_u32()?;
                    cp.push(Constant::Float(f32::from_bits(bits)));
                    i += 1;
                }
                5 => {
                    // CONSTANT_Long (takes two slots!)
                    let hi = reader.read_u32()? as u64;
                    let lo = reader.read_u32()? as u64;
                    let val = ((hi << 32) | lo) as i64;
                    cp.push(Constant::Long(val));
                    cp.push(Constant::Placeholder);
                    i += 2;
                }
                6 => {
                    // CONSTANT_Double (takes two slots!)
                    let hi = reader.read_u32()? as u64;
                    let lo = reader.read_u32()? as u64;
                    let bits = (hi << 32) | lo;
                    cp.push(Constant::Double(f64::from_bits(bits)));
                    cp.push(Constant::Placeholder);
                    i += 2;
                }
                7 => {
                    // CONSTANT_Class
                    let name_index = reader.read_u16()?;
                    cp.push(Constant::Class { name_index });
                    i += 1;
                }
                8 => {
                    // CONSTANT_String
                    let string_index = reader.read_u16()?;
                    cp.push(Constant::StringRef { string_index });
                    i += 1;
                }
                9 => {
                    // CONSTANT_Fieldref
                    let class_index = reader.read_u16()?;
                    let name_and_type_index = reader.read_u16()?;
                    cp.push(Constant::FieldRef { class_index, name_and_type_index });
                    i += 1;
                }
                10 => {
                    // CONSTANT_Methodref
                    let class_index = reader.read_u16()?;
                    let name_and_type_index = reader.read_u16()?;
                    cp.push(Constant::MethodRef { class_index, name_and_type_index });
                    i += 1;
                }
                11 => {
                    // CONSTANT_InterfaceMethodref
                    let class_index = reader.read_u16()?;
                    let name_and_type_index = reader.read_u16()?;
                    cp.push(Constant::InterfaceMethodRef { class_index, name_and_type_index });
                    i += 1;
                }
                12 => {
                    // CONSTANT_NameAndType
                    let name_index = reader.read_u16()?;
                    let descriptor_index = reader.read_u16()?;
                    cp.push(Constant::NameAndType { name_index, descriptor_index });
                    i += 1;
                }
                15 => {
                    // CONSTANT_MethodHandle
                    let reference_kind = reader.read_u8()?;
                    let reference_index = reader.read_u16()?;
                    cp.push(Constant::MethodHandle { reference_kind, reference_index });
                    i += 1;
                }
                16 => {
                    // CONSTANT_MethodType
                    let descriptor_index = reader.read_u16()?;
                    cp.push(Constant::MethodType { descriptor_index });
                    i += 1;
                }
                17 => {
                    // CONSTANT_Dynamic
                    let bootstrap_method_attr_index = reader.read_u16()?;
                    let name_and_type_index = reader.read_u16()?;
                    cp.push(Constant::Dynamic { bootstrap_method_attr_index, name_and_type_index });
                    i += 1;
                }
                18 => {
                    // CONSTANT_InvokeDynamic
                    let bootstrap_method_attr_index = reader.read_u16()?;
                    let name_and_type_index = reader.read_u16()?;
                    cp.push(Constant::InvokeDynamic { bootstrap_method_attr_index, name_and_type_index });
                    i += 1;
                }
                19 => {
                    // CONSTANT_Module
                    let name_index = reader.read_u16()?;
                    cp.push(Constant::Module { name_index });
                    i += 1;
                }
                20 => {
                    // CONSTANT_Package
                    let name_index = reader.read_u16()?;
                    cp.push(Constant::Package { name_index });
                    i += 1;
                }
                _ => return Err(ClassParseError::UnsupportedConstantTag(tag)),
            }
        }

        let access_flags = reader.read_u16()?;
        let this_class_idx = reader.read_u16()?;
        let this_class = Self::resolve_class_name(&cp, this_class_idx)?;

        let super_class_idx = reader.read_u16()?;
        let super_class = if super_class_idx == 0 {
            None
        } else {
            Some(Self::resolve_class_name(&cp, super_class_idx)?)
        };

        // Interfaces
        let if_count = reader.read_u16()? as usize;
        let mut interfaces = Vec::with_capacity(if_count);
        for _ in 0..if_count {
            let if_idx = reader.read_u16()?;
            interfaces.push(Self::resolve_class_name(&cp, if_idx)?);
        }

        // Fields
        let fields_count = reader.read_u16()? as usize;
        let mut fields = Vec::with_capacity(fields_count);
        for _ in 0..fields_count {
            let f_flags = reader.read_u16()?;
            let f_name_idx = reader.read_u16()?;
            let f_desc_idx = reader.read_u16()?;
            let f_attrs_count = reader.read_u16()? as usize;

            let f_name = Self::resolve_utf8(&cp, f_name_idx)?;
            let f_desc = Self::resolve_utf8(&cp, f_desc_idx)?;

            let mut constant_value = None;
            for _ in 0..f_attrs_count {
                let attr_name_idx = reader.read_u16()?;
                let attr_len = reader.read_u32()? as usize;
                let attr_name = Self::resolve_utf8(&cp, attr_name_idx)?;
                if attr_name == "ConstantValue" && attr_len == 2 {
                    let cv_idx = reader.read_u16()?;
                    constant_value = cp.get(cv_idx as usize).cloned();
                } else {
                    let _ = reader.read_bytes(attr_len)?;
                }
            }
            fields.push(FieldInfo {
                access_flags: f_flags,
                name: f_name,
                descriptor: f_desc,
                constant_value,
            });
        }

        // Methods
        let methods_count = reader.read_u16()? as usize;
        let mut methods = Vec::with_capacity(methods_count);
        for _ in 0..methods_count {
            let m_flags = reader.read_u16()?;
            let m_name_idx = reader.read_u16()?;
            let m_desc_idx = reader.read_u16()?;
            let m_attrs_count = reader.read_u16()? as usize;

            let m_name = Self::resolve_utf8(&cp, m_name_idx)?;
            let m_desc = Self::resolve_utf8(&cp, m_desc_idx)?;

            let mut code = None;
            for _ in 0..m_attrs_count {
                let attr_name_idx = reader.read_u16()?;
                let attr_len = reader.read_u32()? as usize;
                let attr_name = Self::resolve_utf8(&cp, attr_name_idx)?;
                if attr_name == "Code" {
                    let max_stack = reader.read_u16()?;
                    let max_locals = reader.read_u16()?;
                    let code_len = reader.read_u32()? as usize;
                    let bytecode = reader.read_bytes(code_len)?.to_vec();

                    let ex_count = reader.read_u16()? as usize;
                    let mut exception_table = Vec::with_capacity(ex_count);
                    for _ in 0..ex_count {
                        exception_table.push(ExceptionHandler {
                            start_pc: reader.read_u16()?,
                            end_pc: reader.read_u16()?,
                            handler_pc: reader.read_u16()?,
                            catch_type: reader.read_u16()?,
                        });
                    }

                    // Code attributes (LineNumberTable, etc.)
                    let sub_attr_count = reader.read_u16()? as usize;
                    for _ in 0..sub_attr_count {
                        let _sub_name_idx = reader.read_u16()?;
                        let sub_len = reader.read_u32()? as usize;
                        let _ = reader.read_bytes(sub_len)?;
                    }

                    code = Some(CodeAttribute {
                        max_stack,
                        max_locals,
                        code: bytecode,
                        exception_table,
                    });
                } else {
                    let _ = reader.read_bytes(attr_len)?;
                }
            }
            methods.push(MethodInfo {
                access_flags: m_flags,
                name: m_name,
                descriptor: m_desc,
                code,
            });
        }

        Ok(Self {
            minor_version,
            major_version,
            constant_pool: cp,
            access_flags,
            this_class,
            super_class,
            interfaces,
            fields,
            methods,
        })
    }

    pub fn resolve_utf8(cp: &[Constant], idx: u16) -> Result<String, ClassParseError> {
        match cp.get(idx as usize) {
            Some(Constant::Utf8(s)) => Ok(s.clone()),
            _ => Err(ClassParseError::InvalidIndex(idx)),
        }
    }

    pub fn resolve_class_name(cp: &[Constant], idx: u16) -> Result<String, ClassParseError> {
        match cp.get(idx as usize) {
            Some(Constant::Class { name_index }) => Self::resolve_utf8(cp, *name_index),
            _ => Err(ClassParseError::InvalidIndex(idx)),
        }
    }

    pub fn resolve_name_and_type(cp: &[Constant], idx: u16) -> Result<(String, String), ClassParseError> {
        match cp.get(idx as usize) {
            Some(Constant::NameAndType { name_index, descriptor_index }) => {
                let name = Self::resolve_utf8(cp, *name_index)?;
                let desc = Self::resolve_utf8(cp, *descriptor_index)?;
                Ok((name, desc))
            }
            _ => Err(ClassParseError::InvalidIndex(idx)),
        }
    }

    pub fn resolve_field_ref(cp: &[Constant], idx: u16) -> Result<(String, String, String), ClassParseError> {
        match cp.get(idx as usize) {
            Some(Constant::FieldRef { class_index, name_and_type_index }) => {
                let class_name = Self::resolve_class_name(cp, *class_index)?;
                let (name, desc) = Self::resolve_name_and_type(cp, *name_and_type_index)?;
                Ok((class_name, name, desc))
            }
            _ => Err(ClassParseError::InvalidIndex(idx)),
        }
    }

    pub fn resolve_method_ref(cp: &[Constant], idx: u16) -> Result<(String, String, String), ClassParseError> {
        match cp.get(idx as usize) {
            Some(Constant::MethodRef { class_index, name_and_type_index })
            | Some(Constant::InterfaceMethodRef { class_index, name_and_type_index }) => {
                let class_name = Self::resolve_class_name(cp, *class_index)?;
                let (name, desc) = Self::resolve_name_and_type(cp, *name_and_type_index)?;
                Ok((class_name, name, desc))
            }
            _ => Err(ClassParseError::InvalidIndex(idx)),
        }
    }
}
