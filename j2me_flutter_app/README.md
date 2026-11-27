# J2ME Flutter App (`j2me_flutter_app`)

Giao diện người dùng hiện đại, đa nền tảng (iOS, macOS, Android, Windows) cho `j2me_rust_engine`.
Được thiết kế theo đúng kiến trúc của app **"Chơi Game Tuổi Thơ"** (Flutter + Rust core).

---

## 1. Tính năng nổi bật

- **Full Touch & Virtual Keypad**:
  - Cụm D-pad định hướng 4 chiều + nút OK/Fire ở giữa.
  - Phím chức năng mềm LSK, RSK, CLR.
  - Bàn phím số chuẩn Nokia (1-9, *, 0, #) hỗ trợ game RPG / Avatar / Ninja School.
  - Rung phản hồi cảm ứng (Haptic Feedback).
- **Treo máy nền tiết kiệm pin tối đa**:
  - Tự động nhận diện `AppLifecycleState` khi khoá màn hình hoặc chuyển app.
  - Kích hoạt `engine.setSleeping(true)` và hạ chu kỳ render từ 16ms (60 FPS) xuống 450ms (~2 FPS).
- **Mở bất kỳ file game `.jar` nào**:
  - Hỗ trợ chọn file `.jar` từ bộ nhớ máy hoặc Files app.
  - Tự động giải mã manifest `MIDlet-1` và khởi chạy game tức thì.

---

## 2. Hướng dẫn cài đặt & Build

### Yêu cầu:
- Flutter SDK `>= 3.0.0`
- Rust toolchain (`cargo`, `rustc`)

### Chạy trên máy Desktop (Windows / macOS):
1. Copy thư viện Rust đã build vào thư mục app:
   - Trên Windows: copy `../j2me_rust_engine/target/release/j2me_rust_engine.dll` vào thư mục gốc hoặc `build/windows/runner/Release/`
   - Trên macOS: copy `../j2me_rust_engine/target/release/libj2me_rust_engine.dylib`
2. Chạy ứng dụng:
   ```bash
   flutter pub get
   flutter run
   ```

### Build cho iOS (iPhone / iPad):
1. Build thư viện tĩnh Rust cho iOS:
   ```bash
   cd ../j2me_rust_engine
   cargo build --target aarch64-apple-ios --release
   ```
2. Thêm file `libj2me_rust_engine.a` và header `include/j2me_engine.h` vào Xcode project của Flutter (`ios/Runner`).
3. Chạy `flutter build ipa` hoặc mở file `ios/Runner.xcworkspace` trong Xcode để ký và cài lên iPhone.
