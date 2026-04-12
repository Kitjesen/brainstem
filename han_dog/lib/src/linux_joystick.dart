// Linux Joystick FFI — 直接用 open/read/ioctl 系统调用读 /dev/input/js*。
//
// 非阻塞模式：O_NONBLOCK + Timer 轮询，不卡 Dart event loop。
// 替代 File.openRead()（会 EOF）和 Process('cat')（额外进程开销）。

import 'dart:async';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:logging/logging.dart';

final _log = Logger('han_dog.linux_joystick');

// ── Linux syscall 常量 ──────────────────────────────────────

const int _O_RDONLY = 0;
const int _O_NONBLOCK = 2048; // 0x800
const int _EAGAIN = 11;
const int _EWOULDBLOCK = 11;

// struct js_event { uint32 time; int16 value; uint8 type; uint8 number; }
const int _JS_EVENT_SIZE = 8;
const int _JS_EVENT_BUTTON = 0x01;
const int _JS_EVENT_AXIS = 0x02;
const int _JS_EVENT_INIT = 0x80;

// ── FFI bindings ────────────────────────────────────────────

typedef _OpenNative = Int32 Function(Pointer<Utf8> path, Int32 flags);
typedef _OpenDart = int Function(Pointer<Utf8> path, int flags);

typedef _ReadNative = Int64 Function(Int32 fd, Pointer<Uint8> buf, Int64 count);
typedef _ReadDart = int Function(int fd, Pointer<Uint8> buf, int count);

typedef _CloseNative = Int32 Function(Int32 fd);
typedef _CloseDart = int Function(int fd);

typedef _ErrnoLocationNative = Pointer<Int32> Function();
typedef _ErrnoLocationDart = Pointer<Int32> Function();

final _libc = DynamicLibrary.open('libc.so.6');
final _open = _libc.lookupFunction<_OpenNative, _OpenDart>('open');
final _read = _libc.lookupFunction<_ReadNative, _ReadDart>('read');
final _close = _libc.lookupFunction<_CloseNative, _CloseDart>('close');
final _errnoLocation = _libc.lookupFunction<_ErrnoLocationNative, _ErrnoLocationDart>('__errno_location');

int get _errno => _errnoLocation().value;

// ── Joystick Event ──────────────────────────────────────────

class JsEvent {
  final int time;
  final int value;
  final int type;
  final int number;

  JsEvent(this.time, this.value, this.type, this.number);

  bool get isButton => type & _JS_EVENT_BUTTON != 0;
  bool get isAxis => type & _JS_EVENT_AXIS != 0;
  bool get isInit => type & _JS_EVENT_INIT != 0;

  @override
  String toString() =>
      'JsEvent(type=${isButton ? "BTN" : isAxis ? "AXIS" : "?"}${isInit ? "+INIT" : ""}, '
      'num=$number, val=$value)';
}

// ── LinuxJoystick ───────────────────────────────────────────

/// 直接通过 FFI 读取 Linux joystick 设备。
///
/// 非阻塞模式 + Timer 轮询（5ms），零外部进程依赖。
/// ```dart
/// final js = LinuxJoystick('/dev/input/js0');
/// if (!js.open()) return;
/// js.eventStream.listen((event) => print(event));
/// // ...
/// js.dispose();
/// ```
class LinuxJoystick {
  final String devicePath;
  int _fd = -1;
  Timer? _pollTimer;
  bool _disposed = false;

  final _eventController = StreamController<JsEvent>.broadcast();
  final Pointer<Uint8> _buf = calloc<Uint8>(_JS_EVENT_SIZE * 32); // 一次最多读 32 个事件

  LinuxJoystick(this.devicePath);

  /// 事件流（按钮 + 轴，不含 init 事件）。
  Stream<JsEvent> get eventStream => _eventController.stream;

  /// 打开设备（非阻塞模式）。
  bool open() {
    final pathPtr = devicePath.toNativeUtf8();
    _fd = _open(pathPtr, _O_RDONLY | _O_NONBLOCK);
    calloc.free(pathPtr);

    if (_fd < 0) {
      _log.severe('open($devicePath) failed: errno=$_errno');
      return false;
    }
    _log.info('LinuxJoystick opened: $devicePath (fd=$_fd)');

    // 5ms 轮询（200Hz）— 足够捕捉所有按钮事件
    _pollTimer = Timer.periodic(const Duration(milliseconds: 5), (_) => _poll());
    return true;
  }

  /// fd 失效时关闭设备并触发 onDone，让上层感知断联。
  void _handleDisconnect() {
    _pollTimer?.cancel();
    _pollTimer = null;
    if (_fd >= 0) {
      _close(_fd);
      _fd = -1;
    }
    if (!_eventController.isClosed) {
      _eventController.close();
    }
  }

  void _poll() {
    if (_fd < 0 || _disposed) return;

    // 非阻塞读：一次尽量多读
    while (true) {
      final n = _read(_fd, _buf, _JS_EVENT_SIZE * 32);
      if (n < _JS_EVENT_SIZE) {
        // EAGAIN = 没有新数据，正常
        if (n < 0 && _errno != _EAGAIN && _errno != _EWOULDBLOCK) {
          _log.warning('read error: errno=$_errno — device disconnected');
          _handleDisconnect();
        }
        break;
      }

      final count = n ~/ _JS_EVENT_SIZE;
      final bd = ByteData.sublistView(_buf.asTypedList(n));

      for (var i = 0; i < count; i++) {
        final offset = i * _JS_EVENT_SIZE;
        final event = JsEvent(
          bd.getUint32(offset, Endian.little),
          bd.getInt16(offset + 4, Endian.little),
          bd.getUint8(offset + 6),
          bd.getUint8(offset + 7),
        );

        // 跳过 init 事件
        if (!event.isInit) {
          _eventController.add(event);
        }
      }
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _pollTimer?.cancel();
    if (_fd >= 0) {
      _close(_fd);
      _fd = -1;
    }
    if (!_eventController.isClosed) {
      _eventController.close();
    }
    calloc.free(_buf);
    _log.info('LinuxJoystick disposed: $devicePath');
  }
}
