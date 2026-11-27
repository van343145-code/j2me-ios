import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';

// Native function typedefs
typedef J2meCreateNative = ffi.Pointer<ffi.Void> Function(
    ffi.Pointer<Utf8> storagePath, ffi.Int32 width, ffi.Int32 height);
typedef J2meCreateDart = ffi.Pointer<ffi.Void> Function(
    ffi.Pointer<Utf8> storagePath, int width, int height);

typedef J2meLoadRuntimeNative = ffi.Int32 Function(
    ffi.Pointer<ffi.Void> engine, ffi.Pointer<ffi.Uint8> data, ffi.Size len);
typedef J2meLoadRuntimeDart = int Function(
    ffi.Pointer<ffi.Void> engine, ffi.Pointer<ffi.Uint8> data, int len);

typedef J2meLoadJarNative = ffi.Pointer<Utf8> Function(
    ffi.Pointer<ffi.Void> engine, ffi.Pointer<ffi.Uint8> data, ffi.Size len);
typedef J2meLoadJarDart = ffi.Pointer<Utf8> Function(
    ffi.Pointer<ffi.Void> engine, ffi.Pointer<ffi.Uint8> data, int len);

typedef J2meFreeStringNative = ffi.Void Function(ffi.Pointer<Utf8> str);
typedef J2meFreeStringDart = void Function(ffi.Pointer<Utf8> str);

typedef J2meStartNative = ffi.Int32 Function(ffi.Pointer<ffi.Void> engine);
typedef J2meStartDart = int Function(ffi.Pointer<ffi.Void> engine);

typedef J2meDestroyNative = ffi.Void Function(ffi.Pointer<ffi.Void> engine);
typedef J2meDestroyDart = void Function(ffi.Pointer<ffi.Void> engine);

typedef J2meSetSleepingNative = ffi.Void Function(
    ffi.Pointer<ffi.Void> engine, ffi.Bool sleeping);
typedef J2meSetSleepingDart = void Function(
    ffi.Pointer<ffi.Void> engine, bool sleeping);

typedef J2meIsSleepingNative = ffi.Bool Function(ffi.Pointer<ffi.Void> engine);
typedef J2meIsSleepingDart = bool Function(ffi.Pointer<ffi.Void> engine);

typedef J2meSendKeyNative = ffi.Void Function(
    ffi.Pointer<ffi.Void> engine, ffi.Int32 keyCode, ffi.Bool isDown);
typedef J2meSendKeyDart = void Function(
    ffi.Pointer<ffi.Void> engine, int keyCode, bool isDown);

typedef J2meSendPointerNative = ffi.Void Function(
    ffi.Pointer<ffi.Void> engine, ffi.Int32 action, ffi.Int32 x, ffi.Int32 y);
typedef J2meSendPointerDart = void Function(
    ffi.Pointer<ffi.Void> engine, int action, int x, int y);

typedef J2meCopyFrameNative = ffi.Int32 Function(ffi.Pointer<ffi.Void> engine,
    ffi.Pointer<ffi.Uint32> outBuffer, ffi.Size maxLen);
typedef J2meCopyFrameDart = int Function(ffi.Pointer<ffi.Void> engine,
    ffi.Pointer<ffi.Uint32> outBuffer, int maxLen);

class J2meEngineBridge {
  static late final ffi.DynamicLibrary _dylib;
  static bool _initialized = false;

  static late final J2meCreateDart _create;
  static late final J2meLoadRuntimeDart _loadRuntime;
  static late final J2meLoadJarDart _loadJar;
  static late final J2meFreeStringDart _freeString;
  static late final J2meStartDart _start;
  static late final J2meDestroyDart _destroy;
  static late final J2meSetSleepingDart _setSleeping;
  static late final J2meIsSleepingDart _isSleeping;
  static late final J2meSendKeyDart _sendKey;
  static late final J2meSendPointerDart _sendPointer;
  static late final J2meCopyFrameDart _copyFrame;

  static void initialize([String? customLibPath]) {
    if (_initialized) return;

    if (customLibPath != null) {
      _dylib = ffi.DynamicLibrary.open(customLibPath);
    } else if (Platform.isIOS || Platform.isMacOS) {
      _dylib = ffi.DynamicLibrary.process();
    } else if (Platform.isAndroid) {
      _dylib = ffi.DynamicLibrary.open("libj2me_rust_engine.so");
    } else if (Platform.isWindows) {
      _dylib = ffi.DynamicLibrary.open("j2me_rust_engine.dll");
    } else {
      _dylib = ffi.DynamicLibrary.open("libj2me_rust_engine.so");
    }

    _create = _dylib.lookupFunction<J2meCreateNative, J2meCreateDart>(
        'j2me_engine_create');
    _loadRuntime = _dylib.lookupFunction<J2meLoadRuntimeNative, J2meLoadRuntimeDart>(
        'j2me_engine_load_runtime');
    _loadJar = _dylib.lookupFunction<J2meLoadJarNative, J2meLoadJarDart>(
        'j2me_engine_load_jar');
    _freeString = _dylib.lookupFunction<J2meFreeStringNative, J2meFreeStringDart>(
        'j2me_engine_free_string');
    _start = _dylib.lookupFunction<J2meStartNative, J2meStartDart>(
        'j2me_engine_start');
    _destroy = _dylib.lookupFunction<J2meDestroyNative, J2meDestroyDart>(
        'j2me_engine_destroy');
    _setSleeping = _dylib.lookupFunction<J2meSetSleepingNative, J2meSetSleepingDart>(
        'j2me_engine_set_sleeping');
    _isSleeping = _dylib.lookupFunction<J2meIsSleepingNative, J2meIsSleepingDart>(
        'j2me_engine_is_sleeping');
    _sendKey = _dylib.lookupFunction<J2meSendKeyNative, J2meSendKeyDart>(
        'j2me_engine_send_key');
    _sendPointer = _dylib.lookupFunction<J2meSendPointerNative, J2meSendPointerDart>(
        'j2me_engine_send_pointer');
    _copyFrame = _dylib.lookupFunction<J2meCopyFrameNative, J2meCopyFrameDart>(
        'j2me_engine_copy_frame');

    _initialized = true;
  }

  ffi.Pointer<ffi.Void>? _handle;
  final int width;
  final int height;
  late final ffi.Pointer<ffi.Uint32> _frameBuffer;

  J2meEngineBridge({required String storageDir, this.width = 240, this.height = 320}) {
    initialize();
    final pStorage = storageDir.toNativeUtf8();
    _handle = _create(pStorage, width, height);
    calloc.free(pStorage);
    _frameBuffer = calloc<ffi.Uint32>(width * height);
  }

  bool loadRuntime(Uint8List bytes) {
    if (_handle == null) return false;
    final pData = calloc<ffi.Uint8>(bytes.length);
    pData.asTypedList(bytes.length).setAll(0, bytes);
    final res = _loadRuntime(_handle!, pData, bytes.length);
    calloc.free(pData);
    return res == 0;
  }

  String? loadJar(Uint8List bytes) {
    if (_handle == null) return null;
    final pData = calloc<ffi.Uint8>(bytes.length);
    pData.asTypedList(bytes.length).setAll(0, bytes);
    final pStr = _loadJar(_handle!, pData, bytes.length);
    calloc.free(pData);
    if (pStr == ffi.nullptr) return null;
    final res = pStr.toDartString();
    _freeString(pStr);
    return res;
  }

  bool start() {
    if (_handle == null) return false;
    return _start(_handle!) == 0;
  }

  void setSleeping(bool sleeping) {
    if (_handle != null) {
      _setSleeping(_handle!, sleeping);
    }
  }

  bool isSleeping() {
    if (_handle == null) return false;
    return _isSleeping(_handle!);
  }

  void sendKey(int keyCode, bool isDown) {
    if (_handle != null) {
      _sendKey(_handle!, keyCode, isDown);
    }
  }

  void sendPointer(int action, int x, int y) {
    if (_handle != null) {
      _sendPointer(_handle!, action, x, y);
    }
  }

  Uint32List copyFrame() {
    if (_handle == null) return Uint32List(0);
    final copied = _copyFrame(_handle!, _frameBuffer, width * height);
    if (copied <= 0) return Uint32List(0);
    return _frameBuffer.asTypedList(width * height);
  }

  void dispose() {
    if (_handle != null) {
      _destroy(_handle!);
      _handle = null;
      calloc.free(_frameBuffer);
    }
  }
}
