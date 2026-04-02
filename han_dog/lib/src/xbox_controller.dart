// Xbox 手柄驱动：读取 Linux /dev/input/js* 设备，提供和 RealController 兼容的流接口。
//
// 事件格式 (struct js_event, 8 bytes):
//   uint32 time    — 毫秒时间戳
//   int16  value   — 轴: -32767~32767, 按钮: 0/1
//   uint8  type    — 0x01=按钮, 0x02=轴, 0x80=初始状态
//   uint8  number  — 轴/按钮编号
//
// Xbox One 标准映射:
//   轴0=左摇杆X, 轴1=左摇杆Y, 轴2=LT, 轴3=右摇杆X, 轴4=右摇杆Y, 轴5=RT
//   按钮0=A, 1=B, 2=X, 3=Y, 4=LB, 5=RB, 6=Back, 7=Start, 8=LS, 9=RS

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:rxdart/rxdart.dart';
import 'package:vector_math/vector_math.dart';

import 'gamepad.dart';

final _log = Logger('han_dog.xbox');

/// Xbox 手柄配置（可从 JSON 加载）。
class XboxConfig {
  final double deadzone;

  // 轴映射
  final int axisLeftX;
  final int axisLeftY;
  final int axisRightX;
  final int axisRightY;
  final int axisLT;
  final int axisRT;

  // 按钮映射
  final int btnA;
  final int btnB;
  final int btnX;
  final int btnY;
  final int btnLB;
  final int btnRB;
  final int btnBack;
  final int btnStart;

  // 动作映射
  final double vxScale;
  final double vyScale;
  final double vyawScale;
  final double ltMultiplier;
  final double rtMultiplier;
  final double ltThreshold;
  final double rtThreshold;

  // 摇杆方向
  final bool leftYInvert;
  final bool rightXInvert;
  final bool vyNegate;

  const XboxConfig({
    this.deadzone = 0.08,
    this.axisLeftX = 0,
    this.axisLeftY = 1,
    this.axisRightX = 3,
    this.axisRightY = 4,
    this.axisLT = 2,
    this.axisRT = 5,
    this.btnA = 0,
    this.btnB = 1,
    this.btnX = 2,
    this.btnY = 3,
    this.btnLB = 4,
    this.btnRB = 5,
    this.btnBack = 6,
    this.btnStart = 7,
    this.vxScale = 1.0,
    this.vyScale = 1.0,
    this.vyawScale = 1.0,
    this.ltMultiplier = 0.5,
    this.rtMultiplier = 1.5,
    this.ltThreshold = 0.3,
    this.rtThreshold = 0.3,
    this.leftYInvert = true,
    this.rightXInvert = true,
    this.vyNegate = false,
  });

  factory XboxConfig.fromJson(Map<String, dynamic> json) {
    final axes = json['axes'] as Map<String, dynamic>? ?? {};
    final buttons = json['buttons'] as Map<String, dynamic>? ?? {};
    final speed = json['speed'] as Map<String, dynamic>? ?? {};
    final stick = json['stick'] as Map<String, dynamic>? ?? {};
    return XboxConfig(
      deadzone: (json['deadzone'] as num?)?.toDouble() ?? 0.08,
      axisLeftX: axes['left_stick_x'] as int? ?? 0,
      axisLeftY: axes['left_stick_y'] as int? ?? 1,
      axisRightX: axes['right_stick_x'] as int? ?? 3,
      axisRightY: axes['right_stick_y'] as int? ?? 4,
      axisLT: axes['lt'] as int? ?? 2,
      axisRT: axes['rt'] as int? ?? 5,
      btnA: buttons['a'] as int? ?? 0,
      btnB: buttons['b'] as int? ?? 1,
      btnX: buttons['x'] as int? ?? 2,
      btnY: buttons['y'] as int? ?? 3,
      btnLB: buttons['lb'] as int? ?? 4,
      btnRB: buttons['rb'] as int? ?? 5,
      btnBack: buttons['back'] as int? ?? 6,
      btnStart: buttons['start'] as int? ?? 7,
      vxScale: (speed['vx_scale'] as num?)?.toDouble() ?? 1.0,
      vyScale: (speed['vy_scale'] as num?)?.toDouble() ?? 1.0,
      vyawScale: (speed['vyaw_scale'] as num?)?.toDouble() ?? 1.0,
      ltMultiplier: (speed['lt_multiplier'] as num?)?.toDouble() ?? 0.5,
      rtMultiplier: (speed['rt_multiplier'] as num?)?.toDouble() ?? 1.5,
      ltThreshold: (speed['lt_threshold'] as num?)?.toDouble() ?? 0.3,
      rtThreshold: (speed['rt_threshold'] as num?)?.toDouble() ?? 0.3,
      leftYInvert: stick['left_y_invert'] as bool? ?? true,
      rightXInvert: stick['right_x_invert'] as bool? ?? true,
      vyNegate: stick['vy_from_lx_negate'] as bool? ?? false,
    );
  }

  static Future<XboxConfig> loadFromFile(String path) async {
    final json = jsonDecode(await File(path).readAsString());
    return XboxConfig.fromJson(json as Map<String, dynamic>);
  }
}

/// Linux joystick 事件。
class JsEvent {
  final int time;
  final int value;
  final int type;
  final int number;

  JsEvent(this.time, this.value, this.type, this.number);

  bool get isButton => type & 0x01 != 0;
  bool get isAxis => type & 0x02 != 0;
  bool get isInit => type & 0x80 != 0;
}

/// Xbox 手柄控制器 — 读取 /dev/input/js* 提供和 RealController 兼容的流接口。
///
/// 使用方式和 RealController 一样：
/// ```dart
/// final xbox = XboxController('/dev/input/js0');
/// if (!xbox.open()) { ... }
/// // 然后传给 RealControlDog 使用 direction/standup/sitdown/enabled 流
/// ```
class XboxController implements Gamepad {
  final String devicePath;
  final XboxConfig config;

  StreamSubscription<List<int>>? _fileSub;
  Timer? _tickTimer;
  bool _disposed = false;

  // 内部状态
  final Map<int, double> _axes = {};
  final Map<int, bool> _buttons = {};
  final _buf = BytesBuilder();

  // 广播流
  final _stateController = StreamController<void>.broadcast();

  XboxController(this.devicePath, {this.config = const XboxConfig()});

  // ── 打开/关闭 ─────────────────────────────────────────────

  bool open() {
    final file = File(devicePath);
    if (!file.existsSync()) {
      _log.severe('Xbox controller not found: $devicePath');
      return false;
    }
    try {
      // 异步流读取 — 不阻塞 Dart event loop
      _fileSub = file.openRead().listen(
        _onData,
        onError: (Object e) {
          _log.severe('Xbox read error: $e');
        },
        onDone: () {
          _log.warning('Xbox device stream closed');
        },
      );
    } catch (e) {
      _log.severe('Xbox controller open failed: $devicePath — $e');
      return false;
    }
    _log.info('Xbox controller opened: $devicePath');
    // 50Hz tick 驱动下游流
    _tickTimer = Timer.periodic(const Duration(milliseconds: 20), (_) {
      if (!_disposed) _stateController.add(null);
    });
    return true;
  }

  void _onData(List<int> chunk) {
    _buf.add(chunk);
    // 每个 js_event = 8 bytes
    while (_buf.length >= 8) {
      final bytes = _buf.takeBytes();
      var offset = 0;
      while (offset + 8 <= bytes.length) {
        final bd = ByteData.sublistView(Uint8List.fromList(bytes), offset, offset + 8);
        final event = JsEvent(
          bd.getUint32(0, Endian.little),
          bd.getInt16(4, Endian.little),
          bd.getUint8(6),
          bd.getUint8(7),
        );
        if (event.isAxis) {
          _axes[event.number] = event.value / 32767.0;
        } else if (event.isButton) {
          _buttons[event.number] = event.value != 0;
        }
        offset += 8;
      }
      // 剩余不足 8 字节放回 buffer
      if (offset < bytes.length) {
        _buf.add(bytes.sublist(offset));
      }
      break;
    }
  }

  double _axis(int idx) => _axes[idx] ?? 0.0;
  bool _btn(int idx) => _buttons[idx] ?? false;

  double _dz(double val) => val.abs() < config.deadzone ? 0.0 : val;

  double get _speedScale {
    final lt = (_axis(config.axisLT) + 1) / 2;
    final rt = (_axis(config.axisRT) + 1) / 2;
    if (lt > config.ltThreshold) return config.ltMultiplier;
    if (rt > config.rtThreshold) return config.rtMultiplier;
    return 1.0;
  }

  // ── 和 RealController 兼容的流接口 ─────────────────────────

  /// 行走方向流：(x=前后, y=左右, z=旋转)
  Stream<Vector3> get direction => _stateController.stream.map((_) {
        var ly = _dz(_axis(config.axisLeftY));
        if (config.leftYInvert) ly = -ly;

        var lx = _dz(_axis(config.axisLeftX));
        if (config.vyNegate) lx = -lx;

        var rx = _dz(_axis(config.axisRightX));
        if (config.rightXInvert) rx = -rx;

        final scale = _speedScale;
        return Vector3(
          ly * scale * config.vxScale,
          lx * scale * config.vyScale,
          rx * scale * config.vyawScale,
        );
      });

  /// StandUp: A 按钮按下
  Stream<bool> get standup => _stateController.stream
      .map((_) => _btn(config.btnA))
      .distinct()
      .pairwise()
      .where((p) => !p[0] && p[1])
      .map((_) => true);

  /// SitDown: X 按钮按下
  Stream<bool> get sitdown => _stateController.stream
      .map((_) => _btn(config.btnX))
      .distinct()
      .pairwise()
      .where((p) => !p[0] && p[1])
      .map((_) => true);

  /// Enable/Disable: Y 按钮切换
  Stream<bool> get enabled {
    var _enabled = false;
    return _stateController.stream
        .map((_) => _btn(config.btnY))
        .distinct()
        .pairwise()
        .where((p) => !p[0] && p[1])
        .map((_) {
      _enabled = !_enabled;
      return _enabled;
    });
  }

  /// Idle (StandUp): RB 按钮
  Stream<bool> get idle => _stateController.stream
      .map((_) => _btn(config.btnRB))
      .distinct()
      .pairwise()
      .where((p) => !p[0] && p[1])
      .map((_) => true);

  /// 红键 (紧急停止): B 按钮
  Stream<bool> get red => _stateController.stream
      .map((_) => _btn(config.btnB))
      .distinct()
      .pairwise()
      .where((p) => !p[0] && p[1])
      .map((_) => true);

  /// 标零: Back 按钮
  Stream<void> get calibrate => _stateController.stream
      .map((_) => _btn(config.btnBack))
      .distinct()
      .pairwise()
      .where((p) => !p[0] && p[1])
      .map((_) {});

  /// 策略切换: Start 按钮
  Stream<void> get switchProfile => _stateController.stream
      .map((_) => _btn(config.btnStart))
      .distinct()
      .pairwise()
      .where((p) => !p[0] && p[1])
      .map((_) {});

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _tickTimer?.cancel();
    _fileSub?.cancel();
    _stateController.close();
    _log.info('Xbox controller disposed: $devicePath');
  }
}
