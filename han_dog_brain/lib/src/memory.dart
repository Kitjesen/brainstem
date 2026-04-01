import 'package:logging/logging.dart';
import 'package:rxdart/rxdart.dart';
import 'package:skinny_dog_algebra/skinny_dog_algebra.dart';

import 'common.dart';

final _log = Logger('han_dog_brain.memory');

class Memory<T> {
  final int historySize;
  final ReplaySubject<T> controller;
  bool _disposed = false;

  List<T>? _cachedHistories;
  List<T> get histories => _cachedHistories ??= controller.values.toList();

  // 这个会放入存储的 n 个历史记录
  Stream<T> get historyStream => controller.stream;
  T get latest => histories.last;
  Stream<T> get nextStream => controller.stream.skip(historySize);
  Future<T> get next => controller.stream.skip(historySize).first;

  void add(T h) {
    _cachedHistories = null;
    controller.add(h);
  }

  /// 清空历史缓冲区并重新填充 [historySize] 帧初始值。
  ///
  /// 用于策略切换后清除旧模型的观测历史，防止新模型推理时
  /// 收到与新策略不兼容的历史帧。
  void reset(T initial) {
    _cachedHistories = null;
    for (var i = 0; i < historySize; i++) {
      controller.add(initial);
    }
    _log.fine('Memory reset ($historySize frames)');
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _log.fine('Memory disposed (historySize=$historySize)');
    controller.close();
  }

  Memory({required this.historySize, required T initial})
    : controller = ReplaySubject<T>(maxSize: historySize) {
    if (historySize < 1) {
      throw ArgumentError.value(historySize, 'historySize', 'must be at least 1');
    }
    for (var i = 0; i < historySize; i++) {
      controller.add(initial);
    }
  }
}

extension MemoryHistoryExtension on Memory<History> {
  JointsMatrix get latestAction => latest.nextAction;
  Stream<JointsMatrix> get nextActionStream =>
      nextStream.map((h) => h.nextAction);
}

/// 策略输出追踪：独立于 History.nextAction（物理目标）。
/// 让 obs 里的 last_action 始终反映真实 ONNX 输出，
/// 即使 Idle/StandUp 阶段物理目标是 standingPose/插值。
class PolicyActionTracker {
  JointsMatrix _action = JointsMatrix.zero();
  JointsMatrix get action => _action;
  set action(JointsMatrix value) => _action = value;
}
