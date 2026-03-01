import 'package:han_dog_brain/han_dog_brain.dart';
import 'package:logging/logging.dart';
import 'package:skinny_dog_algebra/skinny_dog_algebra.dart';
import 'package:vector_math/vector_math.dart';

final _log = Logger('han_dog.sim_sensor');

/// 仿真传感器服务 —— 同时实现 [ImuService]、[JointService]、[SimStateInjector]。
///
/// 在 MuJoCo 仿真模式下由 [CmsServer.step] 通过 [SimStateInjector] 接口注入每帧数据，
/// 控制器读取时看到的就是最新注入的仿真状态。
///
/// 用法：
/// ```dart
/// final sim = SimSensorService(standingPose: standingPose);
/// final brain = Brain(imu: sim, joint: sim, ...);
/// final server = CmsServer(m: m, brain: brain, simInjector: sim);
/// ```
class SimSensorService implements ImuService, JointService, SimStateInjector {
  // ─── ImuService ──────────────────────────────────────────────

  @override
  Vector3 gyroscope = Vector3.zero();

  /// 最近一次注入的四元数（实现 SimStateInjector.quaternion）。
  @override
  Quaternion quaternion = Quaternion.identity();

  @override
  Vector3 get projectedGravity {
    final g = Vector3(0.0, 0.0, -1.0);
    quaternion.rotate(g);
    return g;
  }

  @override
  final Vector3 initialGyroscope = Vector3.zero();

  @override
  final Vector3 initialProjectedGravity = Vector3(0.0, 0.0, -1.0);

  // ─── JointService ────────────────────────────────────────────

  @override
  JointsMatrix position;

  @override
  JointsMatrix velocity;

  /// 最近一次注入的力矩（不属于 JointService 接口，仅供 gRPC 流使用）。
  JointsMatrix torque;

  @override
  final JointsMatrix initialPosition;

  @override
  final JointsMatrix initialVelocity;

  int _droppedFrames = 0;

  /// 累计丢弃帧数（含 NaN/Inf 的注入帧）。
  int get droppedFrames => _droppedFrames;

  SimSensorService({required JointsMatrix standingPose})
      : position = standingPose,
        velocity = JointsMatrix.zero(),
        torque = JointsMatrix.zero(),
        initialPosition = standingPose,
        initialVelocity = JointsMatrix.zero();

  // ─── SimStateInjector ────────────────────────────────────────

  @override
  void injectSim({
    required Vector3 gyroscope,
    required Quaternion quaternion,
    required JointsMatrix position,
    required JointsMatrix velocity,
    JointsMatrix? torque,
  }) {
    final bad = _checkNonFinite(
      gyroscope: gyroscope,
      quaternion: quaternion,
      position: position,
      velocity: velocity,
      torque: torque,
    );
    if (bad != null) {
      _droppedFrames++;
      _log.warning('injectSim: discarding frame — $bad (total dropped: $_droppedFrames)');
      return;
    }
    this.gyroscope = gyroscope;
    this.quaternion = quaternion;
    this.position = position;
    this.velocity = velocity;
    this.torque = torque ?? JointsMatrix.zero();
  }
}

/// 返回首个含 NaN/Inf 的字段名，全部有限则返回 null。
String? _checkNonFinite({
  required Vector3 gyroscope,
  required Quaternion quaternion,
  required JointsMatrix position,
  required JointsMatrix velocity,
  JointsMatrix? torque,
}) {
  if (!gyroscope.x.isFinite) return 'gyroscope.x';
  if (!gyroscope.y.isFinite) return 'gyroscope.y';
  if (!gyroscope.z.isFinite) return 'gyroscope.z';
  if (!quaternion.x.isFinite) return 'quaternion.x';
  if (!quaternion.y.isFinite) return 'quaternion.y';
  if (!quaternion.z.isFinite) return 'quaternion.z';
  if (!quaternion.w.isFinite) return 'quaternion.w';
  if (position.hasNonFinite) return 'position';
  if (velocity.hasNonFinite) return 'velocity';
  if (torque != null && torque.hasNonFinite) return 'torque';
  return null;
}

