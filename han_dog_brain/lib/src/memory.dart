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
    : controller = ReplaySubject<T>(maxSize: historySize),
      assert(historySize > 0, 'historySize must be at least 1') {
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
