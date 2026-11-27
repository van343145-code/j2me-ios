# J2ME Rust Engine (`j2me_rust_engine`)

Bộ lõi giả lập J2ME MIDP 2.0 viết hoàn toàn bằng **Rust**, kế thừa toàn bộ kiến trúc hiệu năng cao và cơ chế giữ kết nối ngầm/tiết kiệm pin từ phiên bản **"Chơi Game Tuổi Thơ"**.

---

## 1. Kiến trúc hệ thống

```
+-------------------------------------------------------+
|                Flutter / Native UI Shell              |
+-------------------------------------------------------+
                           |
                           | C FFI (dart:ffi / Swift)
                           v
+-------------------------------------------------------+
|             j2me_rust_engine (Rust Core)              |
|                                                       |
|  * classfile.rs : JVM Class Binary Parser             |
|  * loader.rs    : Multi-JAR Loader & Method Resolver  |
|  * interp.rs    : JVM Bytecode Execution Loop         |
|  * heap.rs      : Object & Array Heap Manager         |
|  * native/      : MIDP & CLDC Native Dispatcher       |
|    - midp.rs    : Display buffer & Throttled Sleep    |
|    - net.rs     : BSD Socket (TCP_NODELAY, Keepalive) |
|    - storage.rs : RMS Persistent Storage (.rms files) |
|    - graphics.rs: Software Rasterizer & Image Decoder |
|    - events.rs  : Touch & Keypad Event Queue          |
|    - system.rs  : System Time & Math Intrinsics       |
+-------------------------------------------------------+
                           ^
                           | Java Bytecode Calls
+-------------------------------------------------------+
|         midp_runtime.jar (401 MIDP/Nokia classes)     |
+-------------------------------------------------------+
```

---

## 2. Điểm đặc biệt: Cơ chế Treo Ngầm Không Ngắt Kết Nối

1. **Triệt tiêu render khi ẩn ứng dụng (`sleeping`)**:
   Khi app xuống background hoặc tắt màn hình, hàm `j2me_engine_set_sleeping(engine, true)` được gọi:
   - Trong `native/midp.rs`: `flush_screen()` lập tức `return` mà không copy pixel buffer.
   - Trong `interp.rs`: Bỏ qua các lệnh flush GPU.
   - Throttling loop từ 60 FPS (16ms) xuống còn 2 FPS (450ms).
   - CPU tụt về $<0.5\%$, iOS/Android không thể kill app do vượt hạn mức CPU.
2. **Socket TCP Keepalive & High Priority**:
   - `native/net.rs` thiết lập `TCP_NODELAY` + Keepalive probe mỗi 10 giây.
   - Socket I/O non-blocking giúp thread mạng không bị freeze/deadlock.

---

## 3. Cách Build Rust Core

### Build cho Windows:
```bash
cargo build --release
# Tạo ra target/release/j2me_rust_engine.dll và j2me_rust_engine.lib
```

### Build cho iOS (Static Library `.a` hoặc XCFramework):
```bash
# Thêm target iOS
rustup target add aarch64-apple-ios x86_64-apple-ios aarch64-apple-ios-sim

# Build staticlib cho iPhone thực tế
cargo build --target aarch64-apple-ios --release
```

### Build cho macOS:
```bash
cargo build --target aarch64-apple-darwin --release
# Tạo ra libj2me_rust_engine.dylib
```

### Build cho Android:
```bash
cargo build --target aarch64-linux-android --release
# Tạo ra libj2me_rust_engine.so
```

---

## 4. Kiểm tra Unit Test
```bash
cargo test -- --nocapture
```
Hiện tại toàn bộ 5 test suites (Class parsing, JAR extraction, Interpreter arithmetic loop, Native dispatch, Session lifecycle) đều chạy thành công 100%.
