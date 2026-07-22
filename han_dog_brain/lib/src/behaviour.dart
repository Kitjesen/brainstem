import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:logging/logging.dart';
import 'package:onnx_runtime/onnx_runtime.dart';
import 'package:skinny_dog_algebra/skinny_dog_algebra.dart';
import 'package:vector_math/vector_math.dart';

import 'sensor.dart';
import 'memory.dart';
import 'common.dart';
import 'gesture.dart';
import 'observation_builder.dart';

final _log = Logger('han_dog_brain.behaviour');

double _defaultBodyHeightCommand() => 0.35;

abstract class Behaviour {
  final StreamController<void> clock;
  final ImuService imu;
  final JointService joint;
  final Memory<History> memory;
  final double Function() bodyHeightCommandProvider;
  const Behaviour({
    required this.clock,
    required this.imu,
    required this.joint,
    required this.memory,
    this.bodyHeightCommandProvider = _defaultBodyHeightCommand,
  });

  Stream<void> get ts => clock.stream;

  /// action 字段用 memory.latestAction（= 上一帧 nextAction），和 legacy 一致。
  History next({required Command command, required JointsMatrix nextAction}) =>
      History(
        gyroscope: imu.gyroscope,
        projectedGravity: imu.projectedGravity,
        command: command,
        bodyHeightCommand: bodyHeightCommandForHistory,
        jointPosition: joint.position,
        jointVelocity: joint.velocity,
        action: memory.latestAction,
        nextAction: nextAction,
      );

  double get bodyHeightCommandForHistory => bodyHeightCommandProvider();
}

class Idle extends Behaviour {
  /// 推理回调：每帧跑 ONNX（给 obs 的 action 字段保持活跃）。
  /// 返回 real action（已 scale + offset）。
  JointsMatrix Function()? inferAction;

  Idle({
    required super.clock,
    required super.imu,
    required super.joint,
    required super.memory,
    super.bodyHeightCommandProvider,
    this.inferAction,
  });

  Stream<History> get doing => ts.map((_) {
    inferAction?.call();
    // 物理目标：保持上一帧的 nextAction（standingPose）
    return next(command: .idle(), nextAction: memory.latestAction);
  });
}

class SitDown extends Behaviour {
  final JointsMatrix sittingPose;

  final int counts;
  const SitDown({
    required super.clock,
    required super.imu,
    required super.joint,
    required super.memory,
    super.bodyHeightCommandProvider,
    required this.sittingPose,
    required this.counts,
  });

  Stream<History> get doing async* {
    final steps = counts;
    int i = 0;
    final currentPose = joint.position;
    await for (final _ in ts) {
      final t = steps == 0 ? 1.0 : (i / steps).clamp(0.0, 1.0);
      final nextAction = JointsMatrix.lerp(
        currentPose,
        sittingPose,
        t,
      ).discardFoot();
      yield next(command: .sitDown(), nextAction: nextAction);
      if (i >= steps) break; // t=1.0 帧已发出，立即结束，不再等下一个 tick
      i++;
    }
  }
}

class StandUp extends Behaviour {
  final JointsMatrix standingPose;

  final int counts;
  const StandUp({
    required super.clock,
    required super.imu,
    required super.joint,
    required super.memory,
    super.bodyHeightCommandProvider,
    required this.standingPose,
    required this.counts,
  });

  Stream<History> get doing async* {
    final steps = counts;
    int i = 0;
    final currentPose = joint.position;
    await for (final _ in ts) {
      final t = steps == 0 ? 1.0 : (i / steps).clamp(0.0, 1.0);
      final nextAction = JointsMatrix.lerp(
        currentPose,
        standingPose,
        t,
      ).discardFoot();
      yield next(command: .standUp(), nextAction: nextAction);
      if (i >= steps) break; // t=1.0 帧已发出，立即结束，不再等下一个 tick
      i++;
    }
  }
}

/// 关键帧动作播放器：按顺序遍历关键帧列表，
/// 每个关键帧做线性插值，全部播完后流结束。
class Gesture extends Behaviour {
  final GestureDefinition definition;

  const Gesture({
    required super.clock,
    required super.imu,
    required super.joint,
    required super.memory,
    super.bodyHeightCommandProvider,
    required this.definition,
  });

  Stream<History> get doing async* {
    JointsMatrix currentPose = joint.position;
    for (final keyframe in definition.keyframes) {
      final steps = keyframe.counts;
      int i = 0;
      await for (final _ in ts) {
        final t = steps == 0 ? 1.0 : (i / steps).clamp(0.0, 1.0);
        final nextAction = JointsMatrix.lerp(
          currentPose,
          keyframe.targetPose,
          t,
        ).discardFoot();
        yield next(
          command: Command.gesture(definition.name),
          nextAction: nextAction,
        );
        if (i >= steps) break;
        i++;
      }
      currentPose = keyframe.targetPose;
    }
  }
}

/// Builds a fixed-size policy history in chronological order.
///
/// The oldest stored frame is evicted and [current] is appended.
Float64List assembleObservationHistory({
  required ObservationBuilder observationBuilder,
  required List<History> histories,
  required History current,
}) {
  if (histories.isEmpty) {
    throw ArgumentError.value(histories, 'histories', 'must not be empty');
  }
  final historySize = histories.length;
  final tensorSize = observationBuilder.tensorSize;
  final result = Float64List(historySize * tensorSize);
  for (
    var destinationFrame = 0;
    destinationFrame < historySize;
    destinationFrame++
  ) {
    final history = destinationFrame == historySize - 1
        ? current
        : histories[destinationFrame + 1];
    final row = observationBuilder.build(history);
    if (row.length != tensorSize) {
      throw StateError(
        'ObservationBuilder returned ${row.length} values, expected $tensorSize',
      );
    }
    result.setRange(
      destinationFrame * tensorSize,
      (destinationFrame + 1) * tensorSize,
      row,
    );
  }
  return result;
}

class Walk extends Behaviour {
  final ObservationBuilder observationBuilder;

  /// 当前行走方向向量。可在两帧之间直接更新，无需加锁——
  /// Dart 单 Isolate 模型保证同一 Isolate 内的读写是顺序执行的。
  Vector3 direction = .zero();

  /// [debug] Latest flattened ONNX input for parity validation.
  Float64List? lastObservation;

  final double minBodyHeightCommand;
  final double maxBodyHeightCommand;
  double _bodyHeightCommand;

  Walk({
    required this.observationBuilder,
    required super.imu,
    required super.joint,
    required super.memory,
    required super.clock,
    this.minBodyHeightCommand = 0.20,
    this.maxBodyHeightCommand = 0.54,
    double bodyHeightCommand = 0.35,
  }) : _bodyHeightCommand = normalizeBodyHeightCommand(
         value: bodyHeightCommand,
         minimum: minBodyHeightCommand,
         maximum: maxBodyHeightCommand,
       );

  static double normalizeBodyHeightCommand({
    required double value,
    required double minimum,
    required double maximum,
  }) {
    if (!minimum.isFinite || !maximum.isFinite || minimum > maximum) {
      throw ArgumentError(
        'Body-height bounds must be finite and minimum <= maximum '
        '(got $minimum..$maximum)',
      );
    }
    if (!value.isFinite) {
      throw ArgumentError.value(value, 'bodyHeightCommand', 'must be finite');
    }
    return value.clamp(minimum, maximum).toDouble();
  }

  double get bodyHeightCommand => _bodyHeightCommand;

  set bodyHeightCommand(double value) {
    _bodyHeightCommand = normalizeBodyHeightCommand(
      value: value,
      minimum: minBodyHeightCommand,
      maximum: maxBodyHeightCommand,
    );
  }

  @override
  double get bodyHeightCommandForHistory => bodyHeightCommand;

  OnnxEnv? _env;
  InferenceSession? _session;
  String inputName = 'obs';

  bool get isModelLoaded => _session != null;

  /// 最近一次 ONNX 推理耗时（微秒）。未推理时为 0。
  int lastInferenceUs = 0;

  bool _disposed = false;

  JointsMatrix get standingPose => observationBuilder.standingPose;

  Future<void> loadModel(String path, {String? inputName}) async {
    if (inputName != null) {
      this.inputName = inputName;
    }
    InferenceSession? candidate;
    try {
      final modelBytes = await File(path).readAsBytes();
      _session?.dispose();
      _session = null;
      final env = _env ??= OnnxEnv.create(
        OrtLoggingLevel.ORT_LOGGING_LEVEL_WARNING,
        'Infer',
      );
      candidate = InferenceSession.create(env, modelBytes);
      if (candidate.inputCounts != 1) {
        throw StateError(
          'ONNX model must have exactly 1 input, got ${candidate.inputCounts}',
        );
      }
      if (candidate.outputCounts != 1) {
        throw StateError(
          'ONNX model must have exactly 1 output, got ${candidate.outputCounts}',
        );
      }
      final input = candidate.getInputInfo(0);
      final output = candidate.getOutputInfo(0);
      if (input.type.value != 1 || input.info.tensorElementType.value != 1) {
        throw StateError('ONNX input type must be a float tensor');
      }
      if (output.type.value != 1 || output.info.tensorElementType.value != 1) {
        throw StateError('ONNX output type must be a float tensor');
      }
      final inputShape = input.info.dimensions;
      final outputShape = output.info.dimensions;
      if (inputShape.length != 2) {
        throw StateError('ONNX input rank must be 2, got ${inputShape.length}');
      }
      if (outputShape.length != 2) {
        throw StateError(
          'ONNX output rank must be 2, got ${outputShape.length}',
        );
      }
      if (inputShape[0] != 1 && inputShape[0] != -1) {
        throw StateError(
          'ONNX input batch must be 1 or -1, got ${inputShape[0]}',
        );
      }
      if (outputShape[0] != 1 && outputShape[0] != -1) {
        throw StateError(
          'ONNX output batch must be 1 or -1, got ${outputShape[0]}',
        );
      }
      final expectedFeatures =
          memory.historySize * observationBuilder.tensorSize;
      if (inputShape[1] != expectedFeatures) {
        throw StateError(
          'ONNX input feature dimension must be $expectedFeatures, '
          'got ${inputShape[1]}',
        );
      }
      if (outputShape[1] != 16) {
        throw StateError(
          'ONNX output action dimension must be 16, got ${outputShape[1]}',
        );
      }
      _session = candidate;
      candidate = null;
    } catch (e, st) {
      candidate?.dispose();
      _session = null;
      _log.severe('Failed to load ONNX model from $path', e, st);
      rethrow;
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _observationController.close();
    _session?.dispose();
    _env?.dispose();
  }

  JointsMatrix clampAction(JointsMatrix action) => action; // no-op，和 legacy 一致

  JointsMatrix toRealAction(JointsMatrix action) =>
      action * observationBuilder.actionScale + observationBuilder.standingPose;

  JointsMatrix fromRealAction(JointsMatrix action) =>
      (action - observationBuilder.standingPose) /
      observationBuilder.actionScale;

  Stream<History> doing(Vector3 direction) {
    this.direction = direction;
    final historySize = memory.historySize;
    final tensorSize = observationBuilder.tensorSize;
    // Pre-allocate aligned buffer — Float64List guarantees 8-byte alignment,
    // preventing ARM64 Bus Error (SIGBUS) in ONNX Runtime native code.
    final observationBuffer = Float64List(historySize * tensorSize);
    return ts.map((_) {
      final holdNext = next(
        command: .walk(this.direction),
        nextAction: .zero(),
      );
      // Drop the oldest frame and append the current frame.
      observationBuffer.setAll(
        0,
        assembleObservationHistory(
          observationBuilder: observationBuilder,
          histories: memory.histories,
          current: holdNext,
        ),
      );
      final nextAction = clampAction(toRealAction(_run(observationBuffer)));
      // Preserve the exact policy input for cross-runtime validation.
      lastObservation = Float64List.fromList(observationBuffer);
      return holdNext.copyWith(nextAction: nextAction);
    });
  }

  /// 单次推理（供 Idle 调用）：构建 obs → ONNX → 返回 real action。
  /// 和 doing() 共享同一套 obs 构建逻辑，保证 last_action 和训练一致。
  JointsMatrix inferOnce() {
    final holdNext = next(command: .idle(), nextAction: .zero());
    final buf = assembleObservationHistory(
      observationBuilder: observationBuilder,
      histories: memory.histories,
      current: holdNext,
    );
    final result = clampAction(toRealAction(_run(buf)));
    lastObservation = Float64List.fromList(buf);
    return result;
  }

  /// broadcast 流：允许多个订阅者（如监控 UI 和测试）同时监听每帧观测向量，
  /// 无需协调谁先谁后。
  final _observationController = StreamController<List<double>>.broadcast();
  Stream<List<double>> get observationStream => _observationController.stream;

  JointsMatrix _run(List<double> obs) {
    final session = _session;
    if (session == null) {
      _log.severe('Walk._run: ONNX session is null — model not loaded');
      throw StateError('Walk: ONNX model not loaded. Call loadModel() first.');
    }
    if (!_disposed) {
      try {
        _observationController.add(List<double>.from(obs));
      } on StateError catch (_) {
        // Controller closed between _disposed check and add() during
        // profile switch; safe to ignore.
      }
    }
    final sw = Stopwatch()..start();
    try {
      final (_, outputValues) = session.run({
        inputName: OnnxFloat(value: obs, shape: [1, obs.length]),
      });
      lastInferenceUs = sw.elapsedMicroseconds;
      final rawValues = (outputValues[0] as OnnxFloat).value;
      // Safety: reject NaN/Inf before they reach motor hardware.
      // A corrupted model or numerical instability must never produce
      // invalid float commands.
      for (int i = 0; i < rawValues.length; i++) {
        if (!rawValues[i].isFinite) {
          throw StateError(
            'ONNX output[$i]=${rawValues[i]} — NaN/Inf rejected '
            '(model may be corrupted or numerically unstable)',
          );
        }
      }
      return JointsMatrix.fromList(rawValues);
    } catch (e, st) {
      _log.severe('Walk._run: ONNX inference failed', e, st);
      rethrow;
    }
  }
}
