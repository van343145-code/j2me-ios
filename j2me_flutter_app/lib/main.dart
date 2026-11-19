import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'engine/engine_bridge.dart';
import 'ui/game_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const J2meApp());
}

class J2meApp extends StatelessWidget {
  const J2meApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'J2ME Rust Player',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF121212),
        primaryColor: Colors.amber,
        colorScheme: const ColorScheme.dark(
          primary: Colors.amber,
          secondary: Colors.amberAccent,
        ),
      ),
      home: const GameSelectScreen(),
    );
  }
}

class GameSelectScreen extends StatefulWidget {
  const GameSelectScreen({super.key});

  @override
  State<GameSelectScreen> createState() => _GameSelectScreenState();
}

class _GameSelectScreenState extends State<GameSelectScreen> {
  bool _isLoading = false;
  String _status = "Chọn file JAR để chơi";

  Future<void> _pickAndLaunchJar() async {
    setState(() {
      _isLoading = true;
      _status = "Đang chọn file...";
    });

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jar'],
      );

      if (result == null || result.files.single.path == null) {
        setState(() {
          _isLoading = false;
          _status = "Đã huỷ chọn file";
        });
        return;
      }

      final jarPath = result.files.single.path!;
      final jarName = result.files.single.name;
      final jarBytes = await File(jarPath).readAsBytes();

      setState(() => _status = "Đang nạp MIDP Runtime...");

      // 1. Storage dir in App Documents
      final appDocDir = await getApplicationDocumentsDirectory();
      final storageDir = "${appDocDir.path}/rms_data";
      await Directory(storageDir).create(recursive: true);

      // 2. Initialize Engine Session
      final engine = J2meEngineBridge(storageDir: storageDir);

      // 3. Load midp_runtime.jar asset
      final runtimeAsset = await rootBundle.load('assets/midp_runtime.jar');
      final runtimeBytes = runtimeAsset.buffer.asUint8List();
      final loadedRuntime = engine.loadRuntime(runtimeBytes);
      if (!loadedRuntime) {
        throw Exception("Không thể nạp midp_runtime.jar");
      }

      // 4. Load game JAR
      setState(() => _status = "Đang nạp $jarName...");
      final mainClass = engine.loadJar(jarBytes);
      if (mainClass == null) {
        throw Exception("Không tìm thấy MIDlet-1 trong MANIFEST.MF");
      }

      // 5. Start MIDlet
      setState(() => _status = "Đang khởi động $mainClass...");
      final started = engine.start();
      if (!started) {
        throw Exception("Khởi động MIDlet thất bại");
      }

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => GameScreen(
            engine: engine,
            title: jarName.replaceAll('.jar', ''),
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Lỗi: $e"),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _status = "Chọn file JAR để chơi";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("J2ME Rust Player"),
        centerTitle: true,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.sports_esports_rounded,
                size: 96,
                color: Colors.amber,
              ),
              const SizedBox(height: 24),
              const Text(
                "Trình giả lập J2ME Core Rust",
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "Kiến trúc thuần Rust + Flutter siêu nhẹ, tiết kiệm pin, treo ngầm không bị ngắt kết nối",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey[400]),
              ),
              const SizedBox(height: 36),
              if (_isLoading)
                Column(
                  children: [
                    const CircularProgressIndicator(color: Colors.amber),
                    const SizedBox(height: 16),
                    Text(_status, style: const TextStyle(color: Colors.white70)),
                  ],
                )
              else
                ElevatedButton.icon(
                  onPressed: _pickAndLaunchJar,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.folder_open),
                  label: const Text(
                    "MỞ FILE GAME (.JAR)",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
