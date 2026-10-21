import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:logging/logging.dart';
import 'package:onnx_runtime/onnx_runtime.dart';
import 'package:onnx_runtime/ffi/bindings.g.dart' show ONNXTensorElementDataType;
import 'package:skinny_dog_algebra/skinny_dog_algebra.dart';
import 'package:vector_math/vector_math.dart';

import 'sensor.dart';
import 'memory.dart';
import 'common.dart';
import 'gesture.dart';
import 'observation_builder.dart';
import 'cts_policy_state.dart';

final _log = Logger('han_dog_brain.behaviour');

// Thunder V4 joint limits from thunder_v4_mujoco.xml, with a 0.02 rad
// software margin on every finite leg limit. Wheel targets match the training
// limit of 12*pi rad/s, which remains below the RS02 protocol limit of 44 rad/s.
const _deployActionMin = <double>[
  -0.39,
  -3.12,
  0.02,
  -0.39,
  0.02,
  -3.12,
  -0.39,
  0.02,
  -3.12,
  -0.39,
  -3.12,
  -3.12,
  -37.69911184307752,
  -37.69911184307752,
  -37.69911184307752,
  -37.69911184307752,
];
const _deployActionMax = <double>[
  0.39,
  -0.02,
  3.12,
  0.39,
  3.12,
  -0.02,
  0.39,
  3.12,
  3.12,
  0.39,
  -0.02,
  3.12,
  37.69911184307752,
  37.69911184307752,
  37.69911184307752,
  37.69911184307752,
];

/// Final software safety envelope before an action reaches the motor layer.
JointsMatrix clampDeployAction(
  JointsMatrix action, {
  JointsMatrix? lowerLimits,
  JointsMatrix? upperLimits,
}) {
  final values = List<double>.from(action.values);
  final profileMin = lowerLimits?.values;
  final profileMax = upperLimits?.values;
  for (var i = 0; i < values.length; i++) {
    final minimum = profileMin == null
        ? _deployActionMin[i]
        : profileMin[i].clamp(_deployActionMin[i], _deployActionMax[i]);
    final maximum = profileMax == null
        ? _deployActionMax[i]
        : profileMax[i].clamp(_deployActionMin[i], _deployActionMax[i]);
    if (minimum > maximum) {
      throw StateError(
        'Invalid action limits at index $i: lower=$minimum upper=$maximum',
      );
    }
    values[i] = values[i].clamp(minimum, maximum).toDouble();
  }
  return JointsMatrix.fromList(values);
}

/// Smoothly transfers control from the fixed standing action to ONNX output.
JointsMatrix blendWalkEntryAction(
  JointsMatrix entryAction,
  JointsMatrix policyAction,
  int frame, {
  int frames = 25,
}) {
  if (frames <= 0 || frame >= frames) return policyAction;
  final linear = (frame / frames).clamp(0.0, 1.0);
  final smooth = linear * linear * (3.0 - 2.0 * linear);
  return JointsMatrix.lerp(entryAction, policyAction, smooth);
}

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

  /// action 字段用 memory.latestAction（= 上一帧 nextAction），和 legacy 一致。
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
  /// 推理回调：每帧跑 ONNX（给 obs 的 action 字段保持活跃）。
  /// 返回 real action（已 scale + offset）。
  JointsMatrix Function()? inferAction;

  Idle({
    required super.clock,
    required super.imu,
    required super.joint,
    required super.memory,
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
  final bool forceZeroWheelOnStop;
  bool forceWheelStop = false;

  /// 当前行走方向向量。可在两帧之间直接更新，无需加锁——
  /// Dart 单 Isolate 模型保证同一 Isolate 内的读写是顺序执行的。
  Vector3 direction = .zero();

  /// [debug] 最近一帧 ONNX 输入（285 维），供外部对比验证。
  Float64List? lastObservation;
  Float64List? lastSingleObservation;
  CtsPolicyState? _ctsState;

  Walk({
    required this.observationBuilder,
    this.forceZeroWheelOnStop = true,
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
  int lastControlUs = 0;

  bool _disposed = false;

  JointsMatrix get standingPose => observationBuilder.standingPose;

  bool get _isCts => observationBuilder is ThunderCtsObservationBuilder;

  JointsMatrix _inferCts(CtsPolicyState state, History sample) {
    final single = Float64List.fromList(observationBuilder.build(
      sample.copyWith(action: toRealAction(state.lastRawAction)),
    ));
    final history = state.append(single);
    final policy = clampAction(state.decode(_run(history, single: single)));
    lastObservation = history;
    lastSingleObservation = single;
    return policy;
  }

  Stream<History> _doingCts() {
    // Reset on each Walk entry; warm-up and previous modes are not history.
    final state = CtsPolicyState(observationBuilder as ThunderCtsObservationBuilder);
    _ctsState = state;
    final entry = clampAction(memory.latestAction).discardFoot();
    var previousApplied = entry;
    var frame = 0;
    return ts.map((_) {
      final timer = Stopwatch()..start();
      final sample = next(command: .walk(direction), nextAction: .zero());
      final policy = _inferCts(state, sample);
      final zeroCommand = direction.x.abs() < 1e-6 &&
          direction.y.abs() < 1e-6 && direction.z.abs() < 1e-6;
      final target = (forceWheelStop || (zeroCommand && forceZeroWheelOnStop))
          ? policy.discardFoot() : policy;
      // Retain entry blending without exceeding the CTS slew bound.
      var applied = clampAction(CtsPolicyState.limitLegDelta(previousApplied,
          blendWalkEntryAction(entry, target, frame++)));
      if (forceWheelStop) applied = applied.discardFoot();
      previousApplied = applied;
      lastControlUs = timer.elapsedMicroseconds;
      return sample.copyWith(nextAction: applied);
    });
  }

  bool get _zeroCommandWheelHistory =>
      observationBuilder is ThunderFlatObservationBuilder &&
      (observationBuilder as ThunderFlatObservationBuilder).zeroCommandWheelHistory;

  Future<void> loadModel(String path, {String? inputName}) async {
    if (inputName != null) {
      this.inputName = inputName;
    }
    try {
      final modelBytes = await File(path).readAsBytes();
      _session?.dispose();
      final session = InferenceSession.create(_env, modelBytes,
          _isCts ? const SessionOptions(intraOpNumThreads: 1, interOpNumThreads: 1) : null);
      // CTS requires two exact inputs, not just a different history size.
      if (_isCts) {
        final expected = [('history', 530), ('single_obs', 53)];
        if (session.inputCounts != 2 || session.outputCounts != 1) {
          session.dispose();
          throw StateError('CTS requires two inputs and one output');
        }
        for (var i = 0; i < 2; i++) {
          final info = session.getInputInfo(i).info;
          final dims = info.dimensions;
          if (session.getInputName(i) != expected[i].$1 ||
              dims.length != 2 || dims[0] != 1 || dims[1] != expected[i].$2 ||
              info.tensorElementType != ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT) {
            session.dispose();
            throw StateError('Invalid CTS input ${expected[i].$1}: $dims');
          }
        }
      } else if (session.inputCounts != 1) {
        session.dispose();
        throw StateError('Legacy observation layout requires a single input');
      }
      // Legacy history remains frame-major; CTS owns its exact history buffer.
      final inputInfo = session.getInputInfo(0).info;
      if (!_isCts && inputInfo.dimensions.length >= 2) {
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
      if (_isCts && (session.getOutputName(0) != 'actions' ||
          outputInfo.dimensions.length != 2 || outputInfo.dimensions[0] != 1 ||
          outputInfo.dimensions[1] != 16 ||
          outputInfo.tensorElementType != ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT)) {
        session.dispose();
        throw StateError('Invalid CTS output contract');
      }
      if (outputInfo.dimensions.length >= 2) {
        final actionDim = outputInfo.dimensions[1];
        if (actionDim != -1 && actionDim != 16) {
          session.dispose();
          throw StateError('ONNX output dim=$actionDim, expected 16');
        }
      }
      _session = session;
      if (observationBuilder is ThunderFlatClippedObservationBuilder ||
          _zeroCommandWheelHistory) {
        // Pay the first-run allocation cost before this model can control motors.
        // This is a nominal standing observation, with raw previous actions zero.
        final warmSingle = Float64List(53)..[5] = -1.0;
        final warmObservation = _isCts
            ? CtsPolicyState(observationBuilder as ThunderCtsObservationBuilder).append(warmSingle)
            : Float64List(memory.historySize * observationBuilder.tensorSize);
        if (!_isCts) {
          for (var frame = 0; frame < memory.historySize; frame++) {
            warmObservation[frame * observationBuilder.tensorSize + 5] = -1.0;
          }
        }
        try {
          for (var i = 0; i < 3; i++) {
            _run(warmObservation, single: _isCts ? warmSingle : null);
          }
          _log.info(
            'Model warmed before motor control; last inference ${lastInferenceUs}us',
          );
          if (_isCts) {
            // Warm Dart observation/target code too, without motor/clock output.
            final state = CtsPolicyState(observationBuilder as ThunderCtsObservationBuilder);
            final sample = History(gyroscope: Vector3.zero(),
                projectedGravity: Vector3(0, 0, -1), command: const Command.idle(),
                jointPosition: standingPose, jointVelocity: JointsMatrix.zero(),
                action: standingPose, nextAction: standingPose);
            for (var i = 0; i < 64; i++) {
              _inferCts(state, sample);
            }
            _ctsState = null;
            lastObservation = null;
            lastSingleObservation = null;
            _log.info('CTS contract: history[1,530] term-major/oldest-first, '
                'single_obs[1,53], first-frame padding, raw action history, '
                'leg target rate=12rad/s at 50Hz');
          }
        } catch (_) {
          session.dispose();
          _session = null;
          rethrow;
        }
      }
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

  JointsMatrix clampAction(JointsMatrix action) => clampDeployAction(
    action,
    lowerLimits: observationBuilder.actionLowerLimits,
    upperLimits: observationBuilder.actionUpperLimits,
  );

  JointsMatrix toRealAction(JointsMatrix action) =>
      action * observationBuilder.actionScale + observationBuilder.standingPose;

  JointsMatrix fromRealAction(JointsMatrix action) =>
      (action - observationBuilder.standingPose) /
      observationBuilder.actionScale;

  Stream<History> doing(Vector3 direction) {
    this.direction = direction;
    if (_isCts) return _doingCts();
    final entryAction = clampAction(memory.latestAction).discardFoot();
    var entryFrame = 0;
    final historySize = memory.historySize;
    final tensorSize = observationBuilder.tensorSize;
    final rawActionHistory = memory.histories.map((h) => h.action).toList();
    // Pre-allocate aligned buffer — Float64List guarantees 8-byte alignment,
    // preventing ARM64 Bus Error (SIGBUS) in ONNX Runtime native code.
    final observationBuffer = Float64List(historySize * tensorSize);
    return ts.map((_) {
      final holdNext = next(
        command: .walk(this.direction),
        nextAction: .zero(),
      );
      // history 拼接: [t-3, t-2, t-1, t-0] + [t-now] = 连续5帧
      // 跳过 histories[0]（最老帧），和 legacy skip(1) 一致
      final histories = memory.histories;
      for (int i = 1; i < historySize; i++) {
        final row = observationBuilder.build(
          histories[i].copyWith(action: rawActionHistory[i]),
        );
        final offset = (i - 1) * tensorSize;
        for (int j = 0; j < tensorSize; j++) {
          observationBuffer[offset + j] = row[j];
        }
      }
      final lastRow = observationBuilder.build(
        holdNext.copyWith(action: rawActionHistory.last),
      );
      final lastOffset = (historySize - 1) * tensorSize;
      for (int j = 0; j < tensorSize; j++) {
        observationBuffer[lastOffset + j] = lastRow[j];
      }
      final rawPolicyAction = toRealAction(_run(observationBuffer));
      final policyAction = clampAction(rawPolicyAction);
      final zeroCommand =
          this.direction.x.abs() < 1e-6 &&
          this.direction.y.abs() < 1e-6 &&
          this.direction.z.abs() < 1e-6;
      // Store this frame's override for the NEXT observation. Do not mask
      // history using the next command, or include target clipping/blending.
      rawActionHistory
        ..removeAt(0)
        ..add(_zeroCommandWheelHistory && zeroCommand
            ? rawPolicyAction.discardFoot()
            : rawPolicyAction);
      // 普通松杆由 profile 决定轮速；异常停车始终归零，不改原始动作历史。
      final targetAction = (forceWheelStop || (zeroCommand && forceZeroWheelOnStop))
          ? policyAction.discardFoot()
          : policyAction;
      // Standing uses a fixed pose and different PD gains. Blend the first
      // 0.5 s (25 frames at 50 Hz) so entering Walking cannot step directly
      // from that pose to an unrelated ONNX gait phase.
      final nextAction = clampAction(
        blendWalkEntryAction(entryAction, targetAction, entryFrame++),
      );
      // debug: 保存 285 维 obs buffer 供外部对比
      lastObservation = Float64List.fromList(observationBuffer);
      return holdNext.copyWith(nextAction: nextAction);
    });
  }

  /// 单次推理（供 Idle 调用）：构建 obs → ONNX → 返回 real action。
  /// 和 doing() 共享同一套 obs 构建逻辑，保证 last_action 和训练一致。
  JointsMatrix inferOnce() {
    if (_isCts) {
      final state = _ctsState ??= CtsPolicyState(
          observationBuilder as ThunderCtsObservationBuilder);
      final sample = next(command: .idle(), nextAction: .zero());
      final policy = _inferCts(state, sample);
      return forceWheelStop || forceZeroWheelOnStop ? policy.discardFoot() : policy;
    }
    final historySize = memory.historySize;
    final tensorSize = observationBuilder.tensorSize;
    final buf = Float64List(historySize * tensorSize);
    final holdNext = next(command: .idle(), nextAction: .zero());
    final histories = memory.histories;
    for (int i = 0; i < historySize - 1; i++) {
      final row = observationBuilder.build(histories[i]);
      final offset = i * tensorSize;
      for (int j = 0; j < tensorSize; j++) {
        buf[offset + j] = row[j];
      }
    }
    final lastRow = observationBuilder.build(holdNext);
    final lastOffset = (historySize - 1) * tensorSize;
    for (int j = 0; j < tensorSize; j++) {
      buf[lastOffset + j] = lastRow[j];
    }
    final result = clampAction(toRealAction(_run(buf)));
    return result;
  }

  /// broadcast 流：允许多个订阅者（如监控 UI 和测试）同时监听每帧观测向量，
  /// 无需协调谁先谁后。
  final _observationController = StreamController<List<double>>.broadcast();
  Stream<List<double>> get observationStream => _observationController.stream;

  JointsMatrix _run(List<double> obs, {Float64List? single}) {
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
      final (_, outputValues) = session.run(single == null ? {
        inputName: OnnxFloat(value: obs, shape: [1, obs.length]),
      } : {
        'history': OnnxFloat(value: obs, shape: [1, 530]),
        'single_obs': OnnxFloat(value: single, shape: [1, 53]),
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
