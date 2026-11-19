import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../engine/engine_bridge.dart';
import 'virtual_pad.dart';

class GameScreen extends StatefulWidget {
  final J2meEngineBridge engine;
  final String title;

  const GameScreen({
    super.key,
    required this.engine,
    required this.title,
  });

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with WidgetsBindingObserver {
  Timer? _renderTimer;
  ui.Image? _currentFrame;
  bool _isBackground = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startRenderLoop(const Duration(milliseconds: 16)); // ~60 FPS
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      // Background / Lock Screen: kích hoạt cơ chế triệt tiêu đồ hoạ
      _isBackground = true;
      widget.engine.setSleeping(true);
      _startRenderLoop(const Duration(milliseconds: 450)); // Throttled ~2 FPS
    } else if (state == AppLifecycleState.resumed) {
      // Foreground: phục hồi 60 FPS
      _isBackground = false;
      widget.engine.setSleeping(false);
      _startRenderLoop(const Duration(milliseconds: 16));
    }
  }

  void _startRenderLoop(Duration interval) {
    _renderTimer?.cancel();
    _renderTimer = Timer.periodic(interval, (_) => _fetchFrame());
  }

  Future<void> _fetchFrame() async {
    // If backgrounded, skip frame updates to save battery and bypass GPU flushes
    if (_isBackground) return;

    final pixels = widget.engine.copyFrame();
    if (pixels.isEmpty) return;

    // Convert ARGB pixels to RGBA bytes for ui.decodeImageFromPixels
    final rgbaBytes = Uint8List(widget.engine.width * widget.engine.height * 4);
    final byteData = rgbaBytes.buffer.asByteData();

    for (int i = 0; i < pixels.length; i++) {
      final p = pixels[i];
      final a = (p >> 24) & 0xFF;
      final r = (p >> 16) & 0xFF;
      final g = (p >> 8) & 0xFF;
      final b = p & 0xFF;

      final off = i * 4;
      byteData.setUint8(off, r);
      byteData.setUint8(off + 1, g);
      byteData.setUint8(off + 2, b);
      byteData.setUint8(off + 3, a);
    }

    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgbaBytes,
      widget.engine.width,
      widget.engine.height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );

    final img = await completer.future;
    if (mounted) {
      setState(() {
        _currentFrame?.dispose();
        _currentFrame = img;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _renderTimer?.cancel();
    _currentFrame?.dispose();
    widget.engine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Colors.grey[900],
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {},
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Screen area
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: widget.engine.width / widget.engine.height,
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[800]!, width: 2),
                      color: Colors.black,
                    ),
                    child: _currentFrame == null
                        ? const Center(
                            child: CircularProgressIndicator(color: Colors.amber),
                          )
                        : CustomPaint(
                            painter: FramePainter(_currentFrame!),
                          ),
                  ),
                ),
              ),
            ),

            // Controls
            VirtualKeypad(
              onKey: (keyCode, isDown) {
                widget.engine.sendKey(keyCode, isDown);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class FramePainter extends CustomPainter {
  final ui.Image frame;

  FramePainter(this.frame);

  @override
  void paint(Canvas canvas, Size size) {
    final src = Rect.fromLTWH(0, 0, frame.width.toDouble(), frame.height.toDouble());
    final dst = Rect.fromLTWH(0, 0, size.width, size.height);
    final paint = Paint()..filterQuality = FilterQuality.none; // Pixel-perfect nearest neighbor
    canvas.drawImageRect(frame, src, dst, paint);
  }

  @override
  bool shouldRepaint(covariant FramePainter oldDelegate) {
    return oldDelegate.frame != frame;
  }
}
