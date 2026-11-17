import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:brainstem_api/brainstem_api.dart' as proto;
import 'package:grpc/grpc.dart';

import 'package:thunder/thunder.dart';
import 'package:thunder_brain/thunder_brain.dart';
import 'package:mocktail/mocktail.dart';
import 'package:skinny_dog_algebra/skinny_dog_algebra.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

class MockImu extends Mock implements ImuService {}

class MockJoint extends Mock implements JointService {}

class MockSlotFsm extends Mock implements M {}

class MockSlotCall extends Mock implements ServiceCall {}

void main() {
  final fixtureDir = Platform.environment['R2_TEST_FIXTURE_DIR'];
  final models = [
    Platform.environment['R2_W5_MODEL'],
    Platform.environment['R2_CTS_MODEL'],
  ];
  final ready = fixtureDir != null && models.every((m) => m != null);
  for (final thirdCache in [false]) {
    test(
      'real ONNX cached switching resets history; synthetic third cache=$thirdCache',
      () async {
        final configuredSlots = await OperatorModeSlots.load(
          Platform.environment['R2_OPERATOR_MODES'] ??
              'thunder/config/operator_modes.json',
        );
        // This is only a cache-lifecycle fixture, not a trained platform policy.
        const thirdName = '__test_only_third_cache__';
        final slots = thirdCache
            ? OperatorModeSlots.fromJson({
                'flat': configuredSlots.flat,
                'stairs': configuredSlots.stairs,
                'platform': thirdName,
              })
            : configuredSlots;
        final profiles = [
          for (final name in slots.profileNames)
            RobotProfile.fromJson(
              (jsonDecode(
                      File(
                        '$fixtureDir/${name == thirdName ? slots.flat : name}.json',
                      ).readAsStringSync(),
                    )
                    as Map<String, dynamic>)
                ..['name'] = name
                ..['modelPath'] = 'must-not-be-opened.onnx',
            ),
        ];
        slots.validateProfiles({
          for (final profile in profiles) profile.name: profile,
        });
        final imu = MockImu();
        final joint = MockJoint();
        final clock = StreamController<void>.broadcast();
        final pose = profiles[0].standingPose;
        when(() => imu.gyroscope).thenReturn(Vector3.zero());
        when(() => imu.initialGyroscope).thenReturn(Vector3.zero());
        when(() => imu.projectedGravity).thenReturn(Vector3(0, 0, -1));
        when(() => imu.initialProjectedGravity).thenReturn(Vector3(0, 0, -1));
        when(() => joint.position).thenReturn(pose);
        when(() => joint.initialPosition).thenReturn(pose);
        when(() => joint.velocity).thenReturn(JointsMatrix.zero());
        when(() => joint.initialVelocity).thenReturn(JointsMatrix.zero());
        final brain = Brain(
          imu: imu,
          joint: joint,
          clock: clock,
          standingPose: pose,
          sittingPose: profiles[0].sittingPose,
          observationBuilder: profiles[0].toObservationBuilder(),
          forceZeroWheelOnStop: false,
        );
        final startup = Stopwatch()..start();
        StreamSubscription<History>? sub;
        try {
          await brain.loadModel(models[0]!);
          final originalFlat = brain.walk;
          brain.retainCurrentProfile(profiles[0].name);
          for (var i = 1; i < profiles.length; i++) {
            await brain.prepareProfile(
              profiles[i].name,
              modelPath: models[i == 1 ? 1 : 0]!,
              observationBuilder: profiles[i].toObservationBuilder(),
              forceZeroWheelOnStop: false,
            );
          }
          final preloadUs = startup.elapsedMicroseconds;
          final manager = ProfileManager(
            profiles: {for (final p in profiles) p.name: p},
            brain: brain,
            initial: profiles.first.name,
            operatorSlots: slots,
          );
          final fsm = MockSlotFsm();
          var switching = false;
          when(() => fsm.isHandlingEvent).thenReturn(false);
          when(() => fsm.isClosed).thenReturn(false);
          when(() => fsm.commandVersion).thenReturn(0);
          when(() => fsm.profileSwitchInProgress).thenAnswer((_) => switching);
          when(
            () => fsm.profileSwitchInProgress = any(),
          ).thenAnswer((i) => switching = i.positionalArguments.first as bool);
          final rpc =
              UnifiedCmsServer(brain: brain, m: fsm, mode: CmsMode.hardware)
                ..profileManager = manager
                ..criticalMotorFaultProvider = (() => false);
          final call = MockSlotCall();
          when(
            () => call.remoteAddress,
          ).thenReturn(InternetAddress.loopbackIPv4);
          when(() => call.clientCertificate).thenReturn(null);
          when(() => call.isCanceled).thenReturn(false);
          when(() => call.isTimedOut).thenReturn(false);
          addTearDown(rpc.dispose);
          brain.memory.add(History.zero().copyWith(nextAction: pose));
          final switchUs = <int>[];
          final inferenceUs = <String, List<int>>{};
          final firstObservations = <int, List<double>>{};
          for (var round = 0; round < (thirdCache ? 12 : 10); round++) {
            final index = (round + 1) % profiles.length;
            final p = profiles[index];
            sub = brain.idle.doing.listen(brain.memory.add);
            when(() => fsm.state).thenReturn(Standing(sub));
            final timer = Stopwatch()..start();
            expect(
              (await rpc.switchProfile(
                call,
                proto.ProfileRequest(name: p.name),
              )).current,
              p.name,
            );
            switchUs.add(timer.elapsedMicroseconds);
            if (index == 0) expect(identical(brain.walk, originalFlat), isTrue);
            for (var frame = 0; frame < 5; frame++) {
              expect(
                (await brain.tick()).nextAction.values,
                orderedEquals(pose.values),
              );
            }
            await sub.cancel();
            sub = brain.walk.doing(Vector3(0.3, 0, 0)).listen(brain.memory.add);
            await brain.tick();
            final single = index == 1
                ? brain.walk.lastSingleObservation!
                : brain.walk.lastObservation!;
            expect(single.skip(37), everyElement(0.0));
            if (firstObservations.containsKey(index)) {
              expect(single, orderedEquals(firstObservations[index]!));
            } else {
              firstObservations[index] = List.of(single);
            }
            for (var frame = 0; frame < 30; frame++) {
              final h = await brain.tick();
              expect(h.nextAction.values.every((v) => v.isFinite), isTrue);
              expect(brain.lastInferenceUs, greaterThan(0));
              inferenceUs
                  .putIfAbsent(p.name, () => [])
                  .add(brain.lastInferenceUs);
            }
            await sub.cancel();
            sub = null;
            brain.memory.add(History.zero().copyWith(nextAction: pose));
          }
          brain.memory.add(History.zero());
          sub = brain.idle.doing.listen(brain.memory.add);
          await brain.switchProfile(
            standingPose: pose,
            sittingPose: profiles[1].sittingPose,
            modelPath: 'must-not-be-opened.onnx',
            observationBuilder: profiles[1].toObservationBuilder(),
            preparedProfile: profiles[1].name,
            canCommit: () => true,
          );
          for (var frame = 0; frame < 5; frame++) {
            expect((await brain.tick()).nextAction.values, everyElement(0.0));
          }
          await sub.cancel();
          sub = null;
          brain.memory.add(History.zero().copyWith(nextAction: pose));
          final previous = brain.walk;
          await expectLater(
            brain.switchProfile(
              standingPose: pose,
              sittingPose: profiles[1].sittingPose,
              modelPath: models[1]!,
              observationBuilder: profiles[1].toObservationBuilder(),
              preparedProfile: profiles[1].name,
              canCommit: () => false,
            ),
            throwsStateError,
          );
          expect(identical(brain.walk, previous), isTrue);
          expect(brain.memory.latestAction.values, orderedEquals(pose.values));
          switchUs.sort();
          final inferenceSummary = <String, Map<String, int>>{};
          for (final entry in inferenceUs.entries) {
            final values = entry.value..sort();
            inferenceSummary[entry.key] = {
              'samples': values.length,
              'p50_us': values[values.length ~/ 2],
              'p99_us': values[(values.length * 0.99).ceil() - 1],
              'max_us': values.last,
              'over_20ms': values.where((v) => v > 20000).length,
            };
          }
          print(
            jsonEncode({
              'platform': Platform.operatingSystem,
              'preload_us': preloadUs,
              'prepared_switch_us': switchUs,
              'inference_us': inferenceSummary,
              'cold_file_io_on_switch': false,
              'motion_commands_sent': false,
              'cached_profiles': profiles.length,
              'third_cache_is_test_fixture_not_platform_acceptance': thirdCache,
            }),
          );
        } finally {
          await sub?.cancel();
          brain.dispose();
          await clock.close();
        }
      },
      skip: !ready,
    );
  }
}
