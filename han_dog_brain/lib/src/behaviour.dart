import 'dart:async';
import 'dart:io';

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

abstract class Behaviour {
  final StreamController<void> clock;
  final ImuService imu;
  final JointService joint;
  final Memory<History> memory;
  const Behaviour({
    required this.clock,
    required this.imu,
    required this.joint,
    required this.memory,
  });

  Stream<void> get ts => clock.stream;

  History next({required Command command, required JointsMatrix nextAction}) =>
      History(
        gyroscope: imu.gyroscope,
        projectedGravity: imu.projectedGravity,
        command: command,
        jointPosition: joint.position,
        jointVelocity: joint.velocity,
        action: memory.latestAction,
        nextAction: nextAction,
      );
}

class Idle extends Behaviour {
  const Idle({
    required super.clock,
    required super.imu,
    required super.joint,
    required super.memory,
  });

  Stream<History> get doing =>
      ts.map((_) => next(command: .idle(), nextAction: memory.latestAction));
}

class SitDown extends Behaviour {
  final JointsMatrix sittingPose;

  final int counts;
  const SitDown({
    required super.clock,
    required super.imu,
    required super.joint,
    required super.memory,
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

class Walk extends Behaviour {
  final ObservationBuilder observationBuilder;

  /// 当前行走方向向量。可在两帧之间直接更新，无需加锁——
  /// Dart 单 Isolate 模型保证同一 Isolate 内的读写是顺序执行的。
  Vector3 direction = .zero();

  Walk({
    required this.observationBuilder,
    required super.imu,
    required super.joint,
    required super.memory,
    required super.clock,
  });

  final _env = OnnxEnv.create(
    OrtLoggingLevel.ORT_LOGGING_LEVEL_WARNING,
    'Infer',
  );
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
    try {
      final modelBytes = await File(path).readAsBytes();
      _session?.dispose();
      final session = InferenceSession.create(_env, modelBytes);
      // Validate input shape: expect [batch, historySize * tensorSize]
      final inputInfo = session.getInputInfo(0).info;
      if (inputInfo.dimensions.length >= 2) {
        final obsDim = inputInfo.dimensions[1];
        final expectedObs = memory.historySize * observationBuilder.tensorSize;
        if (obsDim != -1 && obsDim != expectedObs) {
          session.dispose();
          throw StateError(
            'ONNX input dim=$obsDim but historySize=${memory.historySize} '
            'requires $expectedObs',
          );
        }
      }
      // Validate output shape: expect [batch, 16]
      final outputInfo = session.getOutputInfo(0).info;
      if (outputInfo.dimensions.length >= 2) {
        final actionDim = outputInfo.dimensions[1];
        if (actionDim != -1 && actionDim != 16) {
          session.dispose();
          throw StateError(
            'ONNX output dim=$actionDim, expected 16',
          );
        }
      }
      _session = session;
    } catch (e, st) {
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
    _env.dispose();
  }

  JointsMatrix clampAction(JointsMatrix action) => action.clampPerJoint(
    hipMin: -0.5, hipMax: 0.5,
    thighMin: -1.5, thighMax: 1.5,
    calfMin: -2.5, calfMax: 2.5,
    footMin: -0.5, footMax: 0.5,
  );

  JointsMatrix toRealAction(JointsMatrix action) =>
      action * observationBuilder.actionScale + observationBuilder.standingPose;

  JointsMatrix fromRealAction(JointsMatrix action) =>
      (action - observationBuilder.standingPose) / observationBuilder.actionScale;

  Stream<History> doing(Vector3 direction) {
    this.direction = direction;
    final historySize = memory.historySize;
    final tensorSize = observationBuilder.tensorSize;
    // Pre-allocate flat buffer to avoid per-frame allocation
    final observationBuffer = List<double>.filled(historySize * tensorSize, 0.0);
    return ts.map((_) {
      final holdNext = next(
        command: .walk(this.direction),
        nextAction: .zero(),
      );
      final histories = memory.histories;
      for (int i = 0; i < historySize - 1; i++) {
        final row = observationBuilder.build(histories[i]);
        final offset = i * tensorSize;
        for (int j = 0; j < tensorSize; j++) {
          observationBuffer[offset + j] = row[j];
        }
      }
      final lastRow = observationBuilder.build(holdNext);
      final lastOffset = (historySize - 1) * tensorSize;
      for (int j = 0; j < tensorSize; j++) {
        observationBuffer[lastOffset + j] = lastRow[j];
      }
      final nextAction = clampAction(toRealAction(_run(observationBuffer)));
      return holdNext.copyWith(nextAction: nextAction);
    });
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
    if (!_disposed) _observationController.add(List<double>.from(obs));
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
