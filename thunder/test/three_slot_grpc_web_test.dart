import 'dart:async';
import 'dart:io';

import 'package:brainstem_api/brainstem_api.dart' as proto;
import 'package:grpc/grpc.dart';
import 'package:mocktail/mocktail.dart';
import 'package:robo_device_proto/robo_device_proto.dart';
import 'package:skinny_dog_algebra/skinny_dog_algebra.dart';
import 'package:test/test.dart';
import 'package:thunder/src/web_control_runtime.dart';
import 'package:thunder/thunder.dart';
import 'package:thunder_brain/thunder_brain.dart';
import 'package:vector_math/vector_math.dart';

import 'grpc_operator_slots_test.dart' as grpc_fixture;
import 'web_control_runtime_test.dart' as web_fixture;

void main() {
  setUpAll(() {
    registerFallbackValue(JointsMatrix.zero());
    registerFallbackValue(
      StandardObservationBuilder(standingPose: JointsMatrix.zero()),
    );
    registerFallbackValue(GestureLibrary(standingPose: JointsMatrix.zero()));
  });

  for (final configured in [false, true]) {
    test(
      'App gRPC and web catalog: high platform ${configured ? "assigned" : "empty"}',
      () async {
        final brain = grpc_fixture.MockBrain();
        final m = grpc_fixture.MockM();
        final call = grpc_fixture.MockCall();
        final subscription = const Stream<History>.empty().listen((_) {});
        final state = Grounded(subscription);
        var busy = false;
        final prepared = <String?>[];
        when(() => m.state).thenReturn(state);
        when(() => m.isHandlingEvent).thenReturn(false);
        when(() => m.isClosed).thenReturn(false);
        when(() => m.commandVersion).thenReturn(0);
        when(() => m.profileSwitchInProgress).thenAnswer((_) => busy);
        when(
          () => m.profileSwitchInProgress = any(),
        ).thenAnswer((i) => busy = i.positionalArguments[0] as bool);
        when(() => call.remoteAddress).thenReturn(InternetAddress.loopbackIPv4);
        when(() => call.clientCertificate).thenReturn(null);
        when(() => call.isCanceled).thenReturn(false);
        when(() => call.isTimedOut).thenReturn(false);
        when(() => brain.gestureLibrary = any()).thenReturn(null);
        when(
          () => brain.switchProfile(
            observationBuilder: any(named: 'observationBuilder'),
            standingPose: any(named: 'standingPose'),
            sittingPose: any(named: 'sittingPose'),
            modelPath: any(named: 'modelPath'),
            standUpCounts: any(named: 'standUpCounts'),
            sitDownCounts: any(named: 'sitDownCounts'),
            forceZeroWheelOnStop: any(named: 'forceZeroWheelOnStop'),
            canCommit: any(named: 'canCommit'),
            preparedProfile: any(named: 'preparedProfile'),
          ),
        ).thenAnswer((i) async {
          prepared.add(i.namedArguments[#preparedProfile] as String?);
        });
        final slots = OperatorModeSlots.fromJson({
          'flat': 'w5',
          'stairs': 'cts',
          if (configured) 'high_platform': 'platform_model',
        });
        final profiles = {
          'w5': grpc_fixture.profile('w5', 80),
          'cts': grpc_fixture.profile('cts', 90),
          'platform_model': grpc_fixture.profile('platform_model', 100),
          'archive': grpc_fixture.profile('archive', 110),
        };
        final manager = ProfileManager(
          profiles: profiles,
          brain: brain,
          initial: 'w5',
          operatorSlots: slots,
        );
        final server = UnifiedCmsServer(
          brain: brain,
          m: m,
          mode: CmsMode.hardware,
        )..profileManager = manager;
        addTearDown(() async {
          await server.dispose();
          await subscription.cancel();
        });

        final joint = web_fixture.MockJoint();
        final imu = web_fixture.MockImu();
        final arbiter = web_fixture.MockArbiter();
        final dog = web_fixture.MockDog();
        when(
          () => joint.reportStream,
        ).thenAnswer((_) => const Stream<(int, RSStateReport)>.empty());
        when(() => joint.latestReport(any())).thenReturn(null);
        when(() => joint.latestReportAt(any())).thenReturn(null);
        when(() => joint.canZeroWriteImmediately).thenReturn(false);
        when(() => imu.isStale).thenReturn(false);
        when(() => imu.gyroscope).thenReturn(Vector3.zero());
        when(() => imu.projectedGravity).thenReturn(Vector3(0, 0, -1));
        when(() => arbiter.state).thenReturn(state);
        when(() => arbiter.isHandlingEvent).thenReturn(false);
        when(() => arbiter.profileSwitchInProgress).thenReturn(false);
        when(() => brain.histories).thenReturn([]);
        final runtime = WebControlRuntime(
          brain: brain,
          joint: joint,
          imu: imu,
          arbiter: arbiter,
          controlDog: dog,
          profileManager: manager,
          slots: slots,
          profiles: profiles,
          interlock: MotorEnableInterlock()..permit(),
          motorOutputEnabled: () => false,
          allowMotorEnable: true,
        );
        addTearDown(runtime.dispose);

        final expectedNames = ['w5', 'cts', if (configured) 'platform_model'];
        final expectedDescriptions = [
          'flat: w5',
          'stairs: cts',
          if (configured) 'high_platform: platform_model',
        ];
        final catalog = await server.getProfile(call, proto.Empty());
        expect(catalog.current, 'w5');
        expect(catalog.currentDescription, 'w5');
        expect(catalog.available, expectedNames);
        expect(catalog.descriptions, expectedDescriptions);
        expect(catalog.activeModeId, 'flat');
        final locomotion = catalog.modeCapabilities
            .where(
              (mode) =>
                  mode.kind ==
                  proto.RobotModeKind.ROBOT_MODE_KIND_LOCOMOTION_PROFILE,
            )
            .toList();
        expect(locomotion.map((mode) => mode.id), [
          'flat',
          'stairs',
          if (configured) 'high_platform',
        ]);
        expect(locomotion.map((mode) => mode.profileId), expectedNames);
        expect(runtime.snapshot()['slots'], {
          'flat': 'w5',
          'stairs': 'cts',
          if (configured) 'high_platform': 'platform_model',
        });
        expect(runtime.snapshot()['model_slot'], 'flat');

        if (configured) {
          final selected = await server.switchProfile(
            call,
            proto.ProfileRequest(name: 'high_platform'),
          );
          expect(selected.current, 'platform_model');
          expect(selected.activeModeId, 'high_platform');
          expect(selected.currentDescription, 'platform_model');
          expect(selected.available, expectedNames);
          expect(selected.descriptions, expectedDescriptions);
          expect(prepared, ['platform_model']);
          expect(runtime.snapshot()['model_slot'], 'high_platform');
          expect(runtime.snapshot()['model_profile'], 'platform_model');
        } else {
          await expectLater(
            server.switchProfile(
              call,
              proto.ProfileRequest(name: 'high_platform'),
            ),
            throwsA(
              isA<GrpcError>().having(
                (e) => e.code,
                'code',
                StatusCode.invalidArgument,
              ),
            ),
          );
          await expectLater(
            runtime.selectSlot('high_platform'),
            throwsA(
              isA<StateError>().having(
                (e) => e.message,
                'message',
                contains('unassigned'),
              ),
            ),
          );
          expect(prepared, isEmpty);
          expect(manager.currentName, 'w5');
          expect(runtime.snapshot()['model_slot'], 'flat');
          verifyNever(() => dog.requestProfileSwitch());
        }
      },
    );
  }
}
