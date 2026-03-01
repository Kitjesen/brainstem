import 'dart:async' show TimeoutException;

import 'package:grpc/grpc.dart';
import 'package:han_dog_brain/han_dog_brain.dart';
import 'package:han_dog_message/han_dog_message.dart' as proto;
import 'package:logging/logging.dart';
import 'package:vector_math/vector_math.dart' show Quaternion;

import '../app/profile_manager.dart';
import '../control_arbiter.dart';
import 'gain_manager.dart';
import 'proto_convert.dart';

final _log = Logger('han_dog.server');

/// 运行模式。
enum CmsMode {
  /// 纯仿真: Tick/Step 由外部驱动（MuJoCo），无 ControlArbiter。
  simulation,

  /// 真实硬件: 50Hz Timer 驱动，有 ControlArbiter。
  hardware,
}

/// 统一 gRPC 服务，取代原来的 CmsServer / SimDogServer / RealDogServer。
///
/// 通过 [CmsMode] 和可选依赖注入控制行为：
///
/// | 参数 | simulation | hardware |
/// |------|-----------|----------|
/// | [arbiter] | null | 必须 |
/// | [simInjector] | 必须 | null |
/// | [motor] | 可选 | 可选 |
/// | [gains] | 推荐 | 推荐 |
/// | [imuStreamFactory] | null (clock 驱动) | 必须 |
/// | [jointStreamFactory] | null (clock 驱动) | 必须 |
class UnifiedCmsServer extends proto.CmsServiceBase {
  final Brain _brain;
  final M _m;
  final CmsMode mode;
  final ControlArbiter? arbiter;
  final SimStateInjector? simInjector;
  final MotorService? motor;
  final GainManager? gains;
  final proto.RobotType robotType;

  /// 策略管理器（可选，由外部注入）。
  ProfileManager? profileManager;

  /// 硬件模式：由外部提供 IMU 数据流。
  final Stream<proto.Imu> Function()? imuStreamFactory;

  /// 硬件模式：由外部提供关节数据流。
  final Stream<proto.Joint> Function()? jointStreamFactory;

  final DateTime _startTime = DateTime.now();

  /// 仿真模式 listenImu 用的默认四元数。
  static final _identityQ = Quaternion.identity();

  /// 广播流缓存：支持多客户端。
  late final _historyBroadcast = _brain.historyStream.asBroadcastStream();

  UnifiedCmsServer({
    required Brain brain,
    required M m,
    this.mode = CmsMode.simulation,
    this.arbiter,
    this.simInjector,
    this.motor,
    this.gains,
    this.robotType = proto.RobotType.MINI,
    this.imuStreamFactory,
    this.jointStreamFactory,
  })  : _brain = brain,
        _m = m;

  proto.Duration _elapsed() =>
      proto.Duration.fromDart(DateTime.now().difference(_startTime));

  // ═══════════════════════════════════════════════════════════
  //  生命周期
  // ═══════════════════════════════════════════════════════════

  @override
  Future<proto.Empty> enable(ServiceCall call, proto.Empty request) async {
    await motor?.enable();
    _log.info('Motors enabled');
    return proto.Empty();
  }

  @override
  Future<proto.Empty> disable(ServiceCall call, proto.Empty request) async {
    await motor?.disable();
    _log.info('Motors disabled');
    return proto.Empty();
  }

  // ═══════════════════════════════════════════════════════════
  //  运动指令（有 arbiter → 仲裁，无 arbiter → 直接操作 M）
  // ═══════════════════════════════════════════════════════════

  void _dispatch(A action) {
    final a = arbiter;
    if (a != null) {
      if (!a.command(action, ControlSource.grpc)) {
        throw GrpcError.failedPrecondition(
          'Control rejected: ${a.owner} has priority',
        );
      }
    } else {
      _m.add(action);
    }
    gains?.applyCommand(action);
  }

  @override
  Future<proto.Empty> walk(ServiceCall call, proto.Vector3 request) async {
    if (!request.x.isFinite || !request.y.isFinite || !request.z.isFinite) {
      throw GrpcError.invalidArgument(
        'Walk direction contains NaN or Inf',
      );
    }
    _dispatch(A.walk(request.toVM()));
    return proto.Empty();
  }

  @override
  Future<proto.Empty> standUp(ServiceCall call, proto.Empty request) async {
    _dispatch(const A.standUp());
    _log.info('StandUp command received');
    return proto.Empty();
  }

  @override
  Future<proto.Empty> sitDown(ServiceCall call, proto.Empty request) async {
    _dispatch(const A.sitDown());
    _log.info('SitDown command received');
    return proto.Empty();
  }

  // ═══════════════════════════════════════════════════════════
  //  动作 SDK（Gesture）
  // ═══════════════════════════════════════════════════════════

  /// 触发一个命名动作（鞠躬、点头、扭动等）。
  /// 机器人必须处于 Standing 状态。
  /// 暂无对应 proto RPC，通过 Dart SDK 直接调用。
  void gesture(String name) {
    final library = _brain.gestureLibrary;
    if (library == null || !library.contains(name)) {
      throw GrpcError.notFound('Unknown gesture: $name');
    }
    _dispatch(A.gesture(name));
    _log.info('Gesture command received: $name');
  }

  /// 获取可用动作列表。
  List<String> get gestureNames =>
      _brain.gestureLibrary?.names ?? const [];

  // ═══════════════════════════════════════════════════════════
  //  策略切换
  // ═══════════════════════════════════════════════════════════

  @override
  Future<proto.ProfileInfo> getProfile(
      ServiceCall call, proto.Empty request) async {
    final pm = profileManager;
    if (pm == null) throw GrpcError.unimplemented('Profiles not configured');
    return proto.ProfileInfo(
      current: pm.currentName,
      available: pm.names,
      descriptions: pm.descriptions,
      currentDescription: pm.currentDescription,
    );
  }

  @override
  Future<proto.ProfileInfo> switchProfile(
      ServiceCall call, proto.ProfileRequest request) async {
    final pm = profileManager;
    if (pm == null) throw GrpcError.unimplemented('Profiles not configured');
    if (_m.state is! Grounded) {
      throw GrpcError.failedPrecondition('Must be in Grounded state');
    }
    await pm.switchTo(request.name);
    _log.info('Profile switched to: ${pm.currentName}');
    return proto.ProfileInfo(
      current: pm.currentName,
      available: pm.names,
      descriptions: pm.descriptions,
      currentDescription: pm.currentDescription,
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  仿真接口（仅 simulation 模式可用）
  // ═══════════════════════════════════════════════════════════

  @override
  Future<proto.History> tick(ServiceCall call, proto.Empty request) async {
    if (mode == CmsMode.hardware) {
      throw GrpcError.failedPrecondition(
        'Tick is not available in hardware mode',
      );
    }
    if (!_brain.isModelLoaded) {
      throw GrpcError.failedPrecondition('Model not loaded');
    }
    try {
      final h = await _brain.tick();
      _log.finest('tick: inferenceUs=${_brain.lastInferenceUs}');
      return h.toProto(
        timestamp: _elapsed(),
        kp: gains?.kp,
        kd: gains?.kd,
      );
    } on TimeoutException {
      throw GrpcError.deadlineExceeded('Inference timed out');
    } on StateError catch (e) {
      throw GrpcError.internal(e.message);
    } catch (e, st) {
      _log.severe('tick: unexpected inference error', e, st);
      throw GrpcError.internal('Inference error: $e');
    }
  }

  @override
  Future<proto.Empty> step(ServiceCall call, proto.SimState request) async {
    final injector = simInjector;
    if (injector == null) {
      throw GrpcError.failedPrecondition(
        'Step is only available in simulation mode',
      );
    }
    request.injectInto(injector);
    return proto.Empty();
  }

  // ═══════════════════════════════════════════════════════════
  //  元数据
  // ═══════════════════════════════════════════════════════════

  @override
  Future<proto.Timestamp> getStartTime(
      ServiceCall call, proto.Empty request) async {
    return proto.Timestamp.fromDateTime(_startTime.toUtc());
  }

  @override
  Future<proto.Params> getParams(
      ServiceCall call, proto.Empty request) async {
    return proto.Params(
      robot: proto.RobotModel(
        type: robotType,
        initialJointPosition:
            proto.Matrix4(values: _brain.standingPose.values),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  流式监听
  // ═══════════════════════════════════════════════════════════

  @override
  Stream<proto.History> listenHistory(
      ServiceCall call, proto.Empty request) {
    return _historyBroadcast.map(
      (h) => h.toProto(
        timestamp: _elapsed(),
        kp: gains?.kp,
        kd: gains?.kd,
      ),
    );
  }

  @override
  Stream<proto.Imu> listenImu(
      ServiceCall call, proto.Empty request) {
    // 硬件模式：使用外部注入的硬件数据流
    final factory = imuStreamFactory;
    if (factory != null) return factory();

    // 仿真模式：时钟驱动，读取 ImuService 当前状态
    return _brain.ts.map((_) => imuSnapshot(
          _brain.imu,
          quaternion: simInjector?.quaternion ?? _identityQ,
          timestamp: _elapsed(),
        ));
  }

  @override
  Stream<proto.Joint> listenJoint(
      ServiceCall call, proto.Empty request) {
    // 硬件模式：使用外部注入的硬件数据流
    final factory = jointStreamFactory;
    if (factory != null) return factory();

    // 仿真模式：时钟驱动，读取 JointService 当前状态
    return _brain.ts.map((_) => jointSnapshot(
          _brain.joint,
          timestamp: _elapsed(),
        ));
  }
}
