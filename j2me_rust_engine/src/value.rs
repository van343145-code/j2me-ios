//! JVM Value Representation (Primitives and Object References)

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Value {
    Int(i32),
    Long(i64),
    Float(f32),
    Double(f64),
    /// Reference to an object slot in the Heap. None represents `null`.
    Ref(Option<usize>),
}

impl Value {
    #[inline]
    pub fn null() -> Self {
        Value::Ref(None)
    }

    #[inline]
    pub fn is_null(&self) -> bool {
        matches!(self, Value::Ref(None))
    }

    #[inline]
    pub fn as_int(&self) -> i32 {
        match self {
            Value::Int(v) => *v,
            _ => panic!("Expected Int, found {:?}", self),
        }
    }

    #[inline]
    pub fn as_long(&self) -> i64 {
        match self {
            Value::Long(v) => *v,
            _ => panic!("Expected Long, found {:?}", self),
        }
    }

    #[inline]
    pub fn as_float(&self) -> f32 {
        match self {
            Value::Float(v) => *v,
            _ => panic!("Expected Float, found {:?}", self),
        }
    }

    #[inline]
    pub fn as_double(&self) -> f64 {
        match self {
            Value::Double(v) => *v,
            _ => panic!("Expected Double, found {:?}", self),
        }
    }

    #[inline]
    pub fn as_ref(&self) -> Option<usize> {
        match self {
            Value::Ref(v) => *v,
            _ => panic!("Expected Ref, found {:?}", self),
        }
    }
}
