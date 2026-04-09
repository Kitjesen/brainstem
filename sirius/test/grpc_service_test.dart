import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:grpc/grpc.dart';
import 'package:brainstem_api/brainstem_api.dart' hide Duration;
import 'package:protobuf/well_known_types/google/protobuf/duration.pb.dart'
    as pb;
import 'package:sirius/services/grpc_service.dart';

class _FakeCmsService extends RobotControlServiceBase {
  _FakeCmsService({required this.initialState});

  final CmsState initialState;
  final StreamController<CmsState> stateCtrl = StreamController.broadcast();
  final StreamController<History> historyCtrl = StreamController.broadcast();
  final StreamController<Imu> imuCtrl = StreamController.broadcast();
  final StreamController<Joint> jointCtrl = StreamController.broadcast();

  @override
  Future<Empty> disable(ServiceCall call, Empty request) async => Empty();

  @override
  Future<Empty> enable(ServiceCall call, Empty request) async => Empty();

  @override
  Future<CmsState> getCmsState(ServiceCall call, Empty request) async =>
      initialState;

  @override
  Future<Params> getParams(ServiceCall call, Empty request) async => Params(
    robot: RobotModel(
      type: RobotType.MINI,
      initialJointPosition: Matrix4(values: List<double>.filled(16, 0)),
    ),
  );

  @override
  Future<ProfileInfo> getProfile(ServiceCall call, Empty request) async =>
      ProfileInfo(
        current: 'mini',
        available: ['mini'],
        descriptions: ['default'],
        currentDescription: 'default',
      );

  @override
  Future<Timestamp> getStartTime(ServiceCall call, Empty request) async =>
      Timestamp.fromDateTime(DateTime.utc(2026, 3, 10, 8));

  @override
  Stream<History> listenHistory(ServiceCall call, Empty request) =>
      historyCtrl.stream;

  @override
  Stream<Imu> listenImu(ServiceCall call, Empty request) => imuCtrl.stream;

  @override
  Stream<Joint> listenJoint(ServiceCall call, Empty request) =>
      jointCtrl.stream;

  @override
  Stream<CmsState> listenCmsState(ServiceCall call, Empty request) async* {
    yield initialState;
    yield* stateCtrl.stream;
  }

  @override
  Future<Empty> sitDown(ServiceCall call, Empty request) async => Empty();

  @override
  Future<Empty> step(ServiceCall call, SimState request) async => Empty();

  @override
  Future<Empty> standUp(ServiceCall call, Empty request) async => Empty();

  @override
  Future<ProfileInfo> switchProfile(
    ServiceCall call,
    ProfileRequest request,
  ) async => ProfileInfo(
    current: request.name,
    available: ['mini', request.name],
    descriptions: ['default', 'alternate'],
    currentDescription: 'alternate',
  );

  @override
  Future<History> tick(ServiceCall call, Empty request) async => History(
    gyroscope: Vector3(x: 0, y: 0, z: 0),
    projectedGravity: Vector3(x: 0, y: 0, z: -1),
    command: Command(idle: Empty()),
    jointPosition: Matrix4(values: List<double>.filled(16, 0)),
    jointVelocity: Matrix4(values: List<double>.filled(16, 0)),
    action: Matrix4(values: List<double>.filled(16, 0)),
    nextAction: Matrix4(values: List<double>.filled(16, 0)),
    timestamp: pb.Duration(),
    kp: Matrix4(values: List<double>.filled(16, 0)),
    kd: Matrix4(values: List<double>.filled(16, 0)),
  );

  @override
  Future<Empty> walk(ServiceCall call, Vector3 request) async => Empty();
}

void main() {
  test('GrpcService uses authoritative CMS state stream', () async {
    final service = _FakeCmsService(
      initialState: CmsState(kind: CmsStateKind.CMS_STATE_KIND_GROUNDED),
    );
    final server = Server.create(services: [service]);
    await server.serve(port: 0);

    final grpc = GrpcService();
    await grpc.connect('127.0.0.1', server.port!);

    service.historyCtrl.add(
      History(
        gyroscope: Vector3(x: 0, y: 0, z: 0),
        projectedGravity: Vector3(x: 0, y: 0, z: -1),
        command: Command(idle: Empty()),
        jointPosition: Matrix4(values: List<double>.filled(16, 0)),
        jointVelocity: Matrix4(values: List<double>.filled(16, 0)),
        action: Matrix4(values: List<double>.filled(16, 0)),
        nextAction: Matrix4(values: List<double>.filled(16, 0)),
        timestamp: pb.Duration(),
        kp: Matrix4(values: List<double>.filled(16, 0)),
        kd: Matrix4(values: List<double>.filled(16, 0)),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(grpc.connected, isTrue);
    expect(grpc.cmsState, 'Grounded');

    service.stateCtrl.add(
      CmsState(
        kind: CmsStateKind.CMS_STATE_KIND_TRANSITIONING,
        transition: CmsTransitionKind.CMS_TRANSITION_KIND_SIT_DOWN,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(grpc.cmsState, 'SitDown');

    grpc.disconnect();
    grpc.dispose();
    await server.shutdown();
    await service.stateCtrl.close();
    await service.historyCtrl.close();
    await service.imuCtrl.close();
    await service.jointCtrl.close();
  });
}
