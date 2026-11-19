pub mod c_api;
pub mod classfile;
pub mod frame;
pub mod heap;
pub mod interp;
pub mod jar;
pub mod loader;
pub mod native;
pub mod session;
pub mod value;

#[cfg(test)]
mod tests {
    use super::classfile::ClassFile;
    use super::frame::Frame;
    use super::heap::Heap;
    use super::interp::{Interpreter, InterpResult};
    use super::jar::JarArchive;
    use super::value::Value;

    #[test]
    fn test_parse_sample_class() {
        let class_bytes = include_bytes!("../../../brain/8d33758f-efbb-457c-859f-cfdf2811a7a0/scratch/gtt_classes/gtt/vm/Net.class");
        let cf = ClassFile::parse(class_bytes).expect("Failed to parse Net.class");
        println!("Parsed class: {}", cf.this_class);
        assert_eq!(cf.this_class, "gtt/vm/Net");
        assert_eq!(cf.super_class.as_deref(), Some("java/lang/Object"));
        assert!(cf.methods.iter().any(|m| m.name == "connect"));
        assert!(cf.methods.iter().any(|m| m.name == "read"));
        assert!(cf.methods.iter().any(|m| m.name == "write"));
    }

    #[test]
    fn test_jar_loading() {
        let jar_bytes = include_bytes!("../midp_runtime.jar");
        let mut jar = JarArchive::from_bytes(jar_bytes.to_vec()).expect("Failed to open midp_runtime.jar");
        let net_class_data = jar.read_file("gtt/vm/Net.class").expect("Net.class not found in JAR");
        let cf = ClassFile::parse(&net_class_data).expect("Failed to parse extracted Net.class");
        assert_eq!(cf.this_class, "gtt/vm/Net");
    }

    #[test]
    fn test_interp_sum_loop() {
        use std::sync::Arc;
        let bytecode: [u8; 22] = [
            0x03,       // iconst_0
            0x3B,       // istore_0 (sum = 0)
            0x04,       // iconst_1
            0x3C,       // istore_1 (i = 1)
            // Loop (offset 4):
            0x1B,       // 4: iload_1
            0x10, 0x0A, // 5: bipush 10
            0xA3, 0x00, 0x0D, // 7: if_icmpgt Exit (7 + 13 = 20)
            0x1A,       // 10: iload_0
            0x1B,       // 11: iload_1
            0x60,       // 12: iadd
            0x3B,       // 13: istore_0 (sum += i)
            0x84, 0x01, 0x01, // 14: iinc 1, 1 (i++)
            0xA7, 0xFF, 0xF3, // 17: goto Loop (17 - 13 = 4)
            // Exit (offset 20):
            0x1A,       // iload_0
            0xAC,       // ireturn
        ];

        let mut heap = Heap::new();
        let mut loader = super::loader::ClassLoader::new();
        let dummy_class = Arc::new(ClassFile {
            minor_version: 0,
            major_version: 50,
            constant_pool: vec![],
            access_flags: 0,
            this_class: "Test".into(),
            super_class: None,
            interfaces: vec![],
            fields: vec![],
            methods: vec![],
        });

        let mut frame = Frame::new(4, 8);
        let mut interp = Interpreter::new(&mut heap, &mut loader);
        let res = interp.execute(&dummy_class, &mut frame, &bytecode);

        match res {
            InterpResult::Return(Some(val)) => {
                assert_eq!(val, Value::Int(55));
            }
            _ => panic!("Expected return value 55"),
        }
    }

    #[test]
    fn test_native_midp_dispatch() {
        use std::sync::Arc;
        use super::classfile::Constant;
        super::native::midp::init_midp(240, 320);

        // Constant pool containing MethodRef to gtt/vm/Midp.screenWidth:()I
        // #1 = Class "gtt/vm/Midp"
        // #2 = Utf8 "gtt/vm/Midp"
        // #3 = NameAndType "screenWidth", "()I"
        // #4 = Utf8 "screenWidth"
        // #5 = Utf8 "()I"
        // #6 = MethodRef #1, #3
        let cp = vec![
            Constant::Placeholder,
            Constant::Class { name_index: 2 },
            Constant::Utf8("gtt/vm/Midp".into()),
            Constant::NameAndType { name_index: 4, descriptor_index: 5 },
            Constant::Utf8("screenWidth".into()),
            Constant::Utf8("()I".into()),
            Constant::MethodRef { class_index: 1, name_and_type_index: 3 },
        ];

        let test_class = Arc::new(ClassFile {
            minor_version: 0,
            major_version: 50,
            constant_pool: cp,
            access_flags: 0,
            this_class: "TestNative".into(),
            super_class: None,
            interfaces: vec![],
            fields: vec![],
            methods: vec![],
        });

        // Bytecode: invokestatic #6, ireturn
        let bytecode: [u8; 4] = [
            0xB8, 0x00, 0x06, // invokestatic #6
            0xAC,             // ireturn
        ];

        let mut heap = Heap::new();
        let mut loader = super::loader::ClassLoader::new();
        let mut frame = Frame::new(2, 4);
        let mut interp = Interpreter::new(&mut heap, &mut loader);

        let res = interp.execute(&test_class, &mut frame, &bytecode);
        match res {
            InterpResult::Return(Some(val)) => {
                assert_eq!(val, Value::Int(240));
                println!("Successfully invoked native gtt/vm/Midp.screenWidth() -> 240!");
            }
            _ => panic!("Expected return 240"),
        }
    }

    #[test]
    fn test_j2me_session_lifecycle() {
        let mut session = super::session::J2meSession::new("test_rms", 240, 320);
        let runtime_bytes = include_bytes!("../midp_runtime.jar").to_vec();
        assert!(session.load_runtime_jar(runtime_bytes).is_ok());

        assert!(!session.is_sleeping());
        session.set_sleeping(true);
        assert!(session.is_sleeping());
        session.set_sleeping(false);
        assert!(!session.is_sleeping());

        let frame = session.get_screen_frame();
        assert_eq!(frame.len(), 240 * 320);
    }
}
