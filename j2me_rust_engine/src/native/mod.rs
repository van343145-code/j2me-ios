pub mod events;
pub mod graphics;
pub mod midp;
pub mod net;
pub mod storage;
pub mod system;

use crate::heap::Heap;
use crate::value::Value;

pub enum NativeResult {
    Void,
    Value(Value),
    Exception(String),
}

pub struct NativeDispatcher;

impl NativeDispatcher {
    pub fn dispatch(
        class_name: &str,
        method_name: &str,
        _method_desc: &str,
        args: &[Value],
        heap: &mut Heap,
    ) -> Option<NativeResult> {
        match (class_name, method_name) {
            // === gtt/vm/Midp ===
            ("gtt/vm/Midp", "screenWidth") => {
                let (w, _) = midp::get_screen_size();
                Some(NativeResult::Value(Value::Int(w)))
            }
            ("gtt/vm/Midp", "screenHeight") => {
                let (_, h) = midp::get_screen_size();
                Some(NativeResult::Value(Value::Int(h)))
            }
            ("gtt/vm/Midp", "sleeping") => {
                Some(NativeResult::Value(Value::Int(if midp::is_sleeping() { 1 } else { 0 })))
            }
            ("gtt/vm/Midp", "flush") => {
                // flush([III)V
                if let (Some(Value::Ref(Some(arr_id))), Some(Value::Int(w)), Some(Value::Int(h))) =
                    (args.get(0), args.get(1), args.get(2))
                {
                    if let Some(pixels) = heap.get_int_array_mut(*arr_id) {
                        midp::flush_screen(pixels, *w, *h);
                    }
                }
                Some(NativeResult::Void)
            }
            ("gtt/vm/Midp", "notifyDestroyed") => {
                Some(NativeResult::Void)
            }
            ("gtt/vm/Midp", "handlesSizeChange") => {
                Some(NativeResult::Value(Value::Int(1)))
            }
            ("gtt/vm/Midp", "darkUi") => {
                Some(NativeResult::Value(Value::Int(1)))
            }
            ("gtt/vm/Midp", "getAppProperty") => {
                Some(NativeResult::Value(Value::Ref(None)))
            }

            // === gtt/vm/Events ===
            ("gtt/vm/Events", "next") => {
                // next([I)V
                if let Some(Value::Ref(Some(arr_id))) = args.get(0) {
                    if let Some(out_arr) = heap.get_int_array_mut(*arr_id) {
                        events::poll_event(out_arr);
                    }
                }
                Some(NativeResult::Void)
            }
            ("gtt/vm/Events", "post") => {
                // post(III)V
                if let (Some(Value::Int(kind)), Some(Value::Int(p1)), Some(Value::Int(p2))) =
                    (args.get(0), args.get(1), args.get(2))
                {
                    events::post_event(*kind, *p1, *p2);
                }
                Some(NativeResult::Void)
            }

            // === gtt/vm/Net ===
            ("gtt/vm/Net", "connect") => {
                // connect(String, int) -> int (handle)
                if let (Some(Value::Ref(Some(str_id))), Some(Value::Int(port))) = (args.get(0), args.get(1)) {
                    let host = heap.get_string(*str_id).unwrap_or_default();
                    match net::connect_socket(&host, *port as u16) {
                        Ok(handle) => Some(NativeResult::Value(Value::Int(handle))),
                        Err(e) => Some(NativeResult::Exception(format!("java/io/IOException: {}", e))),
                    }
                } else {
                    Some(NativeResult::Value(Value::Int(-1)))
                }
            }
            ("gtt/vm/Net", "read") => {
                // read(handle, byte[], off, len) -> int
                if let (Some(Value::Int(handle)), Some(Value::Ref(Some(arr_id))), Some(Value::Int(off)), Some(Value::Int(len))) =
                    (args.get(0), args.get(1), args.get(2), args.get(3))
                {
                    if let Some(buf) = heap.get_byte_array_mut(*arr_id) {
                        let start = *off as usize;
                        let end = start + (*len as usize);
                        if start <= end && end <= buf.len() {
                            let mut temp_u8 = vec![0u8; end - start];
                            match net::read_socket(*handle, &mut temp_u8) {
                                Ok(n) => {
                                    for (i, &b) in temp_u8[..n as usize].iter().enumerate() {
                                        buf[start + i] = b as i8;
                                    }
                                    Some(NativeResult::Value(Value::Int(n)))
                                }
                                Err(e) => Some(NativeResult::Exception(format!("java/io/IOException: {}", e))),
                            }
                        } else {
                            Some(NativeResult::Value(Value::Int(-1)))
                        }
                    } else {
                        Some(NativeResult::Value(Value::Int(-1)))
                    }
                } else {
                    Some(NativeResult::Value(Value::Int(-1)))
                }
            }
            ("gtt/vm/Net", "write") => {
                // write(handle, byte[], off, len) -> int
                if let (Some(Value::Int(handle)), Some(Value::Ref(Some(arr_id))), Some(Value::Int(off)), Some(Value::Int(len))) =
                    (args.get(0), args.get(1), args.get(2), args.get(3))
                {
                    if let Some(buf) = heap.get_byte_array(*arr_id) {
                        let start = *off as usize;
                        let end = start + (*len as usize);
                        if start <= end && end <= buf.len() {
                            let temp_u8: Vec<u8> = buf[start..end].iter().map(|&b| b as u8).collect();
                            match net::write_socket(*handle, &temp_u8) {
                                Ok(n) => Some(NativeResult::Value(Value::Int(n))),
                                Err(e) => Some(NativeResult::Exception(format!("java/io/IOException: {}", e))),
                            }
                        } else {
                            Some(NativeResult::Value(Value::Int(-1)))
                        }
                    } else {
                        Some(NativeResult::Value(Value::Int(-1)))
                    }
                } else {
                    Some(NativeResult::Value(Value::Int(-1)))
                }
            }
            ("gtt/vm/Net", "close") => {
                if let Some(Value::Int(handle)) = args.get(0) {
                    net::close_socket(*handle);
                }
                Some(NativeResult::Void)
            }

            // === gtt/vm/Storage ===
            ("gtt/vm/Storage", "load") => {
                if let Some(Value::Ref(Some(str_id))) = args.get(0) {
                    let name = heap.get_string(*str_id).unwrap_or_default();
                    let g = storage::GLOBAL_STORAGE.lock().unwrap();
                    if let Some(mgr) = g.as_ref() {
                        if let Some(bytes) = mgr.load(&name) {
                            let r = heap.alloc_byte_array(bytes);
                            return Some(NativeResult::Value(Value::Ref(Some(r))));
                        }
                    }
                }
                Some(NativeResult::Value(Value::Ref(None)))
            }
            ("gtt/vm/Storage", "save") => {
                if let (Some(Value::Ref(Some(str_id))), Some(Value::Ref(Some(data_id)))) = (args.get(0), args.get(1)) {
                    let name = heap.get_string(*str_id).unwrap_or_default();
                    if let Some(bytes) = heap.get_byte_array(*data_id) {
                        let u8_bytes: Vec<u8> = bytes.iter().map(|&b| b as u8).collect();
                        let g = storage::GLOBAL_STORAGE.lock().unwrap();
                        if let Some(mgr) = g.as_ref() {
                            mgr.save(&name, &u8_bytes);
                        }
                    }
                }
                Some(NativeResult::Void)
            }
            ("gtt/vm/Storage", "delete") => {
                if let Some(Value::Ref(Some(str_id))) = args.get(0) {
                    let name = heap.get_string(*str_id).unwrap_or_default();
                    let g = storage::GLOBAL_STORAGE.lock().unwrap();
                    let res = g.as_ref().map(|mgr| mgr.delete(&name)).unwrap_or(false);
                    Some(NativeResult::Value(Value::Int(if res { 1 } else { 0 })))
                } else {
                    Some(NativeResult::Value(Value::Int(0)))
                }
            }

            // === java/lang/System ===
            ("java/lang/System", "currentTimeMillis") => {
                Some(NativeResult::Value(Value::Long(system::current_time_millis())))
            }
            ("java/lang/System", "nanoTime") => {
                Some(NativeResult::Value(Value::Long(system::nano_time())))
            }
            ("java/lang/System", "identityHashCode") => {
                if let Some(Value::Ref(Some(r))) = args.get(0) {
                    Some(NativeResult::Value(Value::Int(*r as i32)))
                } else {
                    Some(NativeResult::Value(Value::Int(0)))
                }
            }

            // === java/lang/Float & Double ===
            ("java/lang/Float", "floatToIntBits") => {
                if let Some(Value::Float(f)) = args.get(0) {
                    Some(NativeResult::Value(Value::Int(system::float_to_int_bits(*f))))
                } else {
                    Some(NativeResult::Value(Value::Int(0)))
                }
            }
            ("java/lang/Float", "intBitsToFloat") => {
                if let Some(Value::Int(i)) = args.get(0) {
                    Some(NativeResult::Value(Value::Float(system::int_bits_to_float(*i))))
                } else {
                    Some(NativeResult::Value(Value::Float(0.0)))
                }
            }
            ("java/lang/Double", "doubleToLongBits") => {
                if let Some(Value::Double(d)) = args.get(0) {
                    Some(NativeResult::Value(Value::Long(system::double_to_long_bits(*d))))
                } else {
                    Some(NativeResult::Value(Value::Long(0)))
                }
            }
            ("java/lang/Double", "longBitsToDouble") => {
                if let Some(Value::Long(l)) = args.get(0) {
                    Some(NativeResult::Value(Value::Double(system::long_bits_to_double(*l))))
                } else {
                    Some(NativeResult::Value(Value::Double(0.0)))
                }
            }

            // === javax/microedition/lcdui/Image ===
            ("javax/microedition/lcdui/Image", "decode") => {
                // decode([BII[I)[I
                if let (Some(Value::Ref(Some(bytes_id))), Some(Value::Int(off)), Some(Value::Int(len)), Some(Value::Ref(Some(dims_id)))) =
                    (args.get(0), args.get(1), args.get(2), args.get(3))
                {
                    if let Some(buf) = heap.get_byte_array(*bytes_id) {
                        let start = *off as usize;
                        let end = start + (*len as usize);
                        if start <= end && end <= buf.len() {
                            let temp_u8: Vec<u8> = buf[start..end].iter().map(|&b| b as u8).collect();
                            if let Some((w, h, pixels)) = graphics::decode_image(&temp_u8) {
                                if let Some(dims) = heap.get_int_array_mut(*dims_id) {
                                    if dims.len() >= 2 {
                                        dims[0] = w;
                                        dims[1] = h;
                                    }
                                }
                                let pix_ref = heap.alloc_int_array(pixels);
                                return Some(NativeResult::Value(Value::Ref(Some(pix_ref))));
                            }
                        }
                    }
                }
                Some(NativeResult::Value(Value::Ref(None)))
            }

            // === javax/microedition/lcdui/Graphics ===
            ("javax/microedition/lcdui/Graphics", "fill") => {
                if let (
                    Some(Value::Ref(Some(arr_id))),
                    Some(Value::Int(stride)),
                    Some(Value::Int(cx)),
                    Some(Value::Int(cy)),
                    Some(Value::Int(cw)),
                    Some(Value::Int(ch)),
                    Some(Value::Int(x)),
                    Some(Value::Int(y)),
                    Some(Value::Int(w)),
                    Some(Value::Int(h)),
                    Some(Value::Int(col)),
                ) = (
                    args.get(0),
                    args.get(1),
                    args.get(2),
                    args.get(3),
                    args.get(4),
                    args.get(5),
                    args.get(6),
                    args.get(7),
                    args.get(8),
                    args.get(9),
                    args.get(10),
                ) {
                    if let Some(pixels) = heap.get_int_array_mut(*arr_id) {
                        graphics::fill_rect(pixels, *stride, *cx, *cy, *cw, *ch, *x, *y, *w, *h, *col);
                    }
                }
                Some(NativeResult::Void)
            }
            ("javax/microedition/lcdui/Graphics", "line") => {
                if let (
                    Some(Value::Ref(Some(arr_id))),
                    Some(Value::Int(stride)),
                    Some(Value::Int(cx)),
                    Some(Value::Int(cy)),
                    Some(Value::Int(cw)),
                    Some(Value::Int(ch)),
                    Some(Value::Int(x1)),
                    Some(Value::Int(y1)),
                    Some(Value::Int(x2)),
                    Some(Value::Int(y2)),
                    Some(Value::Int(col)),
                ) = (
                    args.get(0),
                    args.get(1),
                    args.get(2),
                    args.get(3),
                    args.get(4),
                    args.get(5),
                    args.get(6),
                    args.get(7),
                    args.get(8),
                    args.get(9),
                    args.get(10),
                ) {
                    if let Some(pixels) = heap.get_int_array_mut(*arr_id) {
                        graphics::draw_line(pixels, *stride, *cx, *cy, *cw, *ch, *x1, *y1, *x2, *y2, *col);
                    }
                }
                Some(NativeResult::Void)
            }

            _ => None,
        }
    }
}
