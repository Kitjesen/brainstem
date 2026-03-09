import 'dart:async';

import 'package:skinny_dog_algebra/skinny_dog_algebra.dart';

import 'common.dart';
import 'memory.dart';
import 'sensor.dart';
import 'behaviour.dart';
import 'gesture.dart';
import 'observation_builder.dart';

class Brain {
  final Memory<History> memory;
  final ImuService imu;
  final JointService joint;
  JointsMatrix get standingPose => walk.observationBuilder.standingPose;
  Idle idle;
  SitDown sitDown;
  StandUp standUp;
  Walk walk;
  final StreamController<void> clock;
  Stream<void> get ts => clock.stream;

  /// 动作库（可选）。设置后可通过 [createGesture] 创建动作行为。
  GestureLibrary? gestureLibrary;

  Brain.shareMemory({
    required int historySize,
    required this.imu,
    required this.joint,
    required this.clock,
    required int standUpCounts,
    required int sitDownCounts,
    required ObservationBuilder observationBuilder,
    required JointsMatrix sittingPose,
    required this.memory,
  }) : idle = .new(clock: clock, imu: imu, joint: joint, memory: memory),
       sitDown = .new(
         clock: clock,
         imu: imu,
         joint: joint,
         memory: memory,
         sittingPose: sittingPose,
         counts: sitDownCounts,
       ),
       standUp = .new(
         clock: clock,
         imu: imu,
         joint: joint,
         memory: memory,
         standingPose: observationBuilder.standingPose,
         counts: standUpCounts,
       ),
       walk = .new(
         observationBuilder: observationBuilder,
         imu: imu,
         joint: joint,
         clock: clock,
         memory: memory,
       );

  factory Brain({
    int historySize = 1,
    required ImuService imu,
    required JointService joint,
    required StreamController<void> clock,
    int standUpCounts = 150,
    int sitDownCounts = 150,
    required JointsMatrix standingPose,
    required JointsMatrix sittingPose,
    ObservationBuilder? observationBuilder,
    double imuGyroscopeScale = 0.25,
    (double, double, double, double) jointVelocityScale = (
      0.05,
      0.05,
      0.05,
      0.05,
    ),
    (double, double, double, double) actionScale = (0.125, 0.25, 0.25, 5.0),
    History? initialHistory,
  }) {
    final builder = observationBuilder ??
        StandardObservationBuilder(
          standingPose: standingPose,
          imuGyroscopeScale: imuGyroscopeScale,
          jointVelocityScale: jointVelocityScale,
          actionScale: actionScale,
        );
    return .shareMemory(
      historySize: historySize,
      imu: imu,
      joint: joint,
      clock: clock,
      standUpCounts: standUpCounts,
      sitDownCounts: sitDownCounts,
      observationBuilder: builder,
      sittingPose: sittingPose,
      memory: .new(
        historySize: historySize,
        initial:
            initialHistory ??
            .new(
              gyroscope: imu.initialGyroscope,
              projectedGravity: imu.initialProjectedGravity,
              command: .idle(),
              jointPosition: joint.initialPosition,
              jointVelocity: joint.initialVelocity,
              action: .zero(),
              nextAction: .zero(),
            ),
      ),
    );
  }

  /// 根据名称从动作库创建一个 [Gesture] 行为。
  /// 如果动作库未设置或名称不存在，返回 null。
  Gesture? createGesture(String name) {
    final definition = gestureLibrary?.get(name);
    if (definition == null) return null;
    return Gesture(
      clock: clock,
      imu: imu,
      joint: joint,
      memory: memory,
      definition: definition,
    );
  }

  List<History> get histories => memory.histories;
  Stream<JointsMatrix> get nextActionStream => memory.nextActionStream;

  // ─── Facade（服务层只与 Brain 交互，不穿透到内部）──────────

  /// ONNX 模型是否已加载完成。
  bool get isModelLoaded => walk.isModelLoaded;

  /// 最近一次推理耗时（微秒）。用于监控控制循环性能。
  int get lastInferenceUs => walk.lastInferenceUs;

  /// 推理历史流：每产生一帧新 [History] 即推送。
  Stream<History> get historyStream => memory.nextStream;

  /// 触发一次时钟脉冲，等待并返回该帧的推理结果。
  /// 先订阅再触发，保证不漏事件。
  /// [timeout] 默认 2 秒；超时抛 [TimeoutException]（防止 ONNX 异常导致调用方永久挂起）。
  Future<History> tick({Duration timeout = const Duration(seconds: 2)}) {
    if (clock.isClosed) {
      return Future<History>.error(StateError('Clock is closed'));
    }
    final next = memory.next.timeout(timeout);
    clock.add(null);
    return next;
  }

  Future<void> loadModel(String path, {String? inputName}) =>
      walk.loadModel(path, inputName: inputName);

  /// 切换策略。必须在 FSM Grounded 状态下调用（由调用方保证）。
  /// 保留 memory/imu/joint/clock，替换 Walk/StandUp/SitDown 行为并重新加载模型。
  /// 若模型加载失败，自动回滚到旧行为实例，保证 Brain 始终处于可用状态。
  Future<void> switchProfile({
    required JointsMatrix standingPose,
    required JointsMatrix sittingPose,
    required String modelPath,
    int standUpCounts = 150,
    int sitDownCounts = 150,
    ObservationBuilder? observationBuilder,
    double imuGyroscopeScale = 0.25,
    (double, double, double, double) jointVelocityScale = (
      0.05,
      0.05,
      0.05,
      0.05,
    ),
    (double, double, double, double) actionScale = (0.125, 0.25, 0.25, 5.0),
    String? inputName,
  }) async {
    final builder = observationBuilder ??
        StandardObservationBuilder(
          standingPose: standingPose,
          imuGyroscopeScale: imuGyroscopeScale,
          jointVelocityScale: jointVelocityScale,
          actionScale: actionScale,
        );
    final newStandUp = StandUp(
      clock: clock,
      imu: imu,
      joint: joint,
      memory: memory,
      standingPose: standingPose,
      counts: standUpCounts,
    );
    final newSitDown = SitDown(
      clock: clock,
      imu: imu,
      joint: joint,
      memory: memory,
      sittingPose: sittingPose,
      counts: sitDownCounts,
    );
    final newWalk = Walk(
      observationBuilder: builder,
      imu: imu,
      joint: joint,
      clock: clock,
      memory: memory,
    );

    try {
      await newWalk.loadModel(modelPath, inputName: inputName);
    } catch (_) {
      newWalk.dispose();
      rethrow;
    }

    // 模型加载成功，安全替换旧实例
    walk.dispose();
    walk = newWalk;
    standUp = newStandUp;
    sitDown = newSitDown;

    // 清除旧策略的观测历史帧，防止新模型推理时读到不兼容的历史数据。
    // 使用当前传感器读数初始化，比 initialGyroscope/initialProjectedGravity
    // 更贴近机器人实际状态（此时 FSM 处于 Grounded，关节已稳定）。
    memory.reset(History(
      gyroscope: imu.gyroscope,
      projectedGravity: imu.projectedGravity,
      command: Command.idle(),
      jointPosition: joint.position,
      jointVelocity: joint.velocity,
      action: JointsMatrix.zero(),
      nextAction: JointsMatrix.zero(),
    ));
  }

  void dispose() {
    walk.dispose();
    memory.dispose();
  }
}
