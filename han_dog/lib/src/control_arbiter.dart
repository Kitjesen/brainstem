import 'dart:async';

import 'package:han_dog_brain/han_dog_brain.dart';
import 'package:logging/logging.dart';

/// 控制源标识
enum ControlSource { yunzhuo, grpc }

/// 控制权仲裁器
///
/// 多个控制端（YUNZHUO 遥控器、gRPC 客户端）共享一个 CMS，
/// 但同一时刻只有一个控制源可以发送运动命令。
///
/// 规则：
/// - YUNZHUO（物理手持）**永远可以抢占**——人在机器人旁边，安全最高
/// - gRPC（远程）只能在 YUNZHUO 不活跃时获取控制权
/// - 控制源超时不发命令 → 自动释放，回到 [none]
/// - Fault / Init 等安全命令**绕过仲裁**，永远通过
final _log = Logger('han_dog.arbiter');

class ControlArbiter {
  final M _m;
  final Duration timeout;

  ControlSource? _owner;
  Timer? _releaseTimer;
  final _ownerController = StreamController<ControlSource?>.broadcast();

  ControlArbiter(this._m, {this.timeout = const Duration(seconds: 3)});

  // ─── 只读访问 ─────────────────────────────────────────

  /// 当前控制权拥有者，null 表示无人控制
  ControlSource? get owner => _owner;

  /// 控制权变更流
  Stream<ControlSource?> get ownerStream => _ownerController.stream;

  /// CMS 当前状态（透传）
  S get state => _m.state;

  /// CMS 状态流（透传），用于 kp/kd 监听等
  Stream<S> get stateStream => _m.stream;

  // ─── 命令发送 ─────────────────────────────────────────

  /// 发送运动命令（walk / standUp / sitDown）。
  ///
  /// 返回 true 表示命令被接受并转发给 CMS，
  /// 返回 false 表示被拒绝（更高优先级的控制源正在使用）。
  bool command(A action, ControlSource source) {
    if (!_canAcquire(source)) {
      return false;
    }
    _acquire(source);
    _m.add(action);
    return true;
  }

  /// 安全命令：Fault，永远通过，不受仲裁限制。
  void fault(String reason) => _m.add(A.fault(reason));

  /// 初始化命令，不受仲裁限制。
  void init() => _m.add(const A.init());

  /// 主动释放控制权（例如 gRPC 客户端断开时）。
  void release(ControlSource source) {
    if (_owner == source) {
      _doRelease();
    }
  }

  // ─── 内部 ───────────────────────────────────────────

  bool _canAcquire(ControlSource source) {
    if (_owner == null) return true; // 无人控制 → 谁都可以
    if (_owner == source) return true; // 同一来源 → 继续
    if (source == ControlSource.yunzhuo) return true; // YUNZHUO 永远抢占
    return false; // gRPC 不能抢占 YUNZHUO
  }

  void _acquire(ControlSource source) {
    final changed = _owner != source;
    _owner = source;
    if (changed) {
      _log.info('Control acquired by $source');
      _ownerController.add(source);
    }
    _releaseTimer?.cancel();
    _releaseTimer = Timer(timeout, _doRelease);
  }

  void _doRelease() {
    if (_owner != null) {
      _log.info('Control released (was $_owner)');
      _owner = null;
      _releaseTimer?.cancel();
      _ownerController.add(null);
    }
  }

  void dispose() {
    _releaseTimer?.cancel();
    _ownerController.close();
  }
}
