use std::time::{SystemTime, UNIX_EPOCH, Instant};
use std::sync::LazyLock;

static START_TIME: LazyLock<Instant> = LazyLock::new(Instant::now);

pub fn current_time_millis() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0)
}

pub fn nano_time() -> i64 {
    START_TIME.elapsed().as_nanos() as i64
}

pub fn get_system_property(key: &str) -> Option<&'static str> {
    match key {
        "microedition.platform" => Some("j2me-rust/1.0"),
        "microedition.configuration" => Some("CLDC-1.1"),
        "microedition.profiles" => Some("MIDP-2.0"),
        "microedition.locale" => Some("vi-VN"),
        "microedition.encoding" => Some("UTF-8"),
        _ => None,
    }
}

pub fn float_to_int_bits(f: f32) -> i32 {
    f.to_bits() as i32
}

pub fn int_bits_to_float(i: i32) -> f32 {
    f32::from_bits(i as u32)
}

pub fn double_to_long_bits(d: f64) -> i64 {
    d.to_bits() as i64
}

pub fn long_bits_to_double(l: i64) -> f64 {
    f64::from_bits(l as u64)
}

// Math functions
pub fn math_sin(d: f64) -> f64 { d.sin() }
pub fn math_cos(d: f64) -> f64 { d.cos() }
pub fn math_tan(d: f64) -> f64 { d.tan() }
pub fn math_asin(d: f64) -> f64 { d.asin() }
pub fn math_acos(d: f64) -> f64 { d.acos() }
pub fn math_atan(d: f64) -> f64 { d.atan() }
pub fn math_atan2(y: f64, x: f64) -> f64 { y.atan2(x) }
pub fn math_sqrt(d: f64) -> f64 { d.sqrt() }
pub fn math_exp(d: f64) -> f64 { d.exp() }
pub fn math_log(d: f64) -> f64 { d.ln() }
pub fn math_pow(a: f64, b: f64) -> f64 { a.powf(b) }
pub fn math_floor(d: f64) -> f64 { d.floor() }
pub fn math_ceil(d: f64) -> f64 { d.ceil() }
pub fn math_rint(d: f64) -> f64 { d.round() }

// Character functions
pub fn char_to_lower(c: u16) -> u16 {
    if let Some(ch) = char::from_u32(c as u32) {
        ch.to_lowercase().next().map(|c| c as u16).unwrap_or(c)
    } else {
        c
    }
}

pub fn char_to_upper(c: u16) -> u16 {
    if let Some(ch) = char::from_u32(c as u32) {
        ch.to_uppercase().next().map(|c| c as u16).unwrap_or(c)
    } else {
        c
    }
}

pub fn char_is_letter(c: u16) -> bool {
    if let Some(ch) = char::from_u32(c as u32) {
        ch.is_alphabetic()
    } else {
        false
    }
}
