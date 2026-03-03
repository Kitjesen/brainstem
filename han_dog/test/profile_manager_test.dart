import 'dart:async';
import 'dart:io';

import 'package:han_dog/han_dog.dart';
import 'package:han_dog_brain/han_dog_brain.dart';
import 'package:mocktail/mocktail.dart';
import 'package:skinny_dog_algebra/skinny_dog_algebra.dart';
import 'package:test/test.dart';

class MockBrain extends Mock implements Brain {}

class MockGainManager extends Mock implements GainManager {}

class MockRealControlDog extends Mock implements RealControlDog {}

final _pose1 = JointsMatrix.fromList(List.filled(16, 1.0));
final _pose2 = JointsMatrix.fromList(List.filled(16, 2.0));
final _kp1 = JointsMatrix.fromList(List.filled(16, 10.0));
final _kd1 = JointsMatrix.fromList(List.filled(16, 20.0));
final _kp2 = JointsMatrix.fromList(List.filled(16, 30.0));
final _kd2 = JointsMatrix.fromList(List.filled(16, 40.0));

RobotProfile _profile(String name, JointsMatrix pose, JointsMatrix kp,
        JointsMatrix kd) =>
    RobotProfile(
      name: name,
      modelPath: 'model/$name.onnx',
      standingPose: pose,
      sittingPose: JointsMatrix.zero(),
      inferKp: kp,
      inferKd: kd,
      standUpKp: kp,
      standUpKd: kd,
      sitDownKp: kp,
      sitDownKd: kd,
    );

void main() {
  late MockBrain brain;
  late MockGainManager gains;
  late MockRealControlDog controlDog;
  late Map<String, RobotProfile> profiles;

  setUpAll(() {
    registerFallbackValue(JointsMatrix.zero());
    registerFallbackValue(GestureLibrary(standingPose: JointsMatrix.zero()));
    registerFallbackValue(
        StandardObservationBuilder(standingPose: JointsMatrix.zero()));
  });

  setUp(() {
    brain = MockBrain();
    gains = MockGainManager();
    controlDog = MockRealControlDog();

    profiles = {
      'alpha': _profile('alpha', _pose1, _kp1, _kd1),
      'beta': _profile('beta', _pose2, _kp2, _kd2),
    };

    when(() => brain.switchProfile(
          observationBuilder: any(named: 'observationBuilder'),
          standingPose: any(named: 'standingPose'),
          sittingPose: any(named: 'sittingPose'),
          modelPath: any(named: 'modelPath'),
          standUpCounts: any(named: 'standUpCounts'),
          sitDownCounts: any(named: 'sitDownCounts'),
        )).thenAnswer((_) async {});

    when(() => brain.gestureLibrary = any()).thenReturn(null);

    when(() => gains.switchGains(
          inferKp: any(named: 'inferKp'),
          inferKd: any(named: 'inferKd'),
          standUpKp: any(named: 'standUpKp'),
          standUpKd: any(named: 'standUpKd'),
          sitDownKp: any(named: 'sitDownKp'),
          sitDownKd: any(named: 'sitDownKd'),
        )).thenReturn(null);

    when(() => controlDog.switchGains(
          inferKp: any(named: 'inferKp'),
          inferKd: any(named: 'inferKd'),
          standUpKp: any(named: 'standUpKp'),
          standUpKd: any(named: 'standUpKd'),
          sitDownKp: any(named: 'sitDownKp'),
          sitDownKd: any(named: 'sitDownKd'),
        )).thenReturn(null);
  });

  test('initial state', () {
    final pm = ProfileManager(
      profiles: profiles,
      brain: brain,
      initial: 'alpha',
    );
    expect(pm.currentName, 'alpha');
    expect(pm.names, ['alpha', 'beta']);
  });

  test('switchTo calls brain.switchProfile and updates currentName', () async {
    final pm = ProfileManager(
      profiles: profiles,
      brain: brain,
      gains: gains,
      controlDog: controlDog,
      initial: 'alpha',
    );

    await pm.switchTo('beta');

    expect(pm.currentName, 'beta');
    verify(() => brain.switchProfile(
          observationBuilder: any(named: 'observationBuilder'),
          standingPose: any(named: 'standingPose'),
          sittingPose: any(named: 'sittingPose'),
          modelPath: 'model/beta.onnx',
          standUpCounts: 150,
          sitDownCounts: 150,
        )).called(1);
  });

  test('switchTo updates GainManager gains', () async {
    final pm = ProfileManager(
      profiles: profiles,
      brain: brain,
      gains: gains,
      initial: 'alpha',
    );

    await pm.switchTo('beta');

    verify(() => gains.switchGains(
          inferKp: _kp2,
          inferKd: _kd2,
          standUpKp: _kp2,
          standUpKd: _kd2,
          sitDownKp: _kp2,
          sitDownKd: _kd2,
        )).called(1);
  });

  test('switchTo updates RealControlDog gains', () async {
    final pm = ProfileManager(
      profiles: profiles,
      brain: brain,
      controlDog: controlDog,
      initial: 'alpha',
    );

    await pm.switchTo('beta');

    verify(() => controlDog.switchGains(
          inferKp: _kp2,
          inferKd: _kd2,
          standUpKp: _kp2,
          standUpKd: _kd2,
          sitDownKp: _kp2,
          sitDownKd: _kd2,
        )).called(1);
  });

  test('switchTo same profile is a no-op', () async {
    final pm = ProfileManager(
      profiles: profiles,
      brain: brain,
      gains: gains,
      controlDog: controlDog,
      initial: 'alpha',
    );

    await pm.switchTo('alpha');

    verifyNever(() => brain.switchProfile(
          observationBuilder: any(named: 'observationBuilder'),
          standingPose: any(named: 'standingPose'),
          sittingPose: any(named: 'sittingPose'),
          modelPath: any(named: 'modelPath'),
          standUpCounts: any(named: 'standUpCounts'),
          sitDownCounts: any(named: 'sitDownCounts'),
        ));
  });

  test('switchTo unknown profile throws ArgumentError', () {
    final pm = ProfileManager(
      profiles: profiles,
      brain: brain,
      initial: 'alpha',
    );

    expect(() => pm.switchTo('unknown'), throwsArgumentError);
  });

  test('toggle cycles through profiles', () async {
    final pm = ProfileManager(
      profiles: profiles,
      brain: brain,
      gains: gains,
      controlDog: controlDog,
      initial: 'alpha',
    );

    await pm.toggle();
    expect(pm.currentName, 'beta');

    await pm.toggle();
    expect(pm.currentName, 'alpha');
  });

  test('switchTo brain failure rolls back gains and keeps currentName', () async {
    when(() => brain.switchProfile(
          observationBuilder: any(named: 'observationBuilder'),
          standingPose: any(named: 'standingPose'),
          sittingPose: any(named: 'sittingPose'),
          modelPath: any(named: 'modelPath'),
          standUpCounts: any(named: 'standUpCounts'),
          sitDownCounts: any(named: 'sitDownCounts'),
        )).thenThrow(Exception('model file not found'));

    final pm = ProfileManager(
      profiles: profiles,
      brain: brain,
      gains: gains,
      controlDog: controlDog,
      initial: 'alpha',
    );

    await expectLater(() => pm.switchTo('beta'), throwsException);

    // Name must not change — partial switch was rolled back
    expect(pm.currentName, 'alpha');

    // Gains must be rolled back to alpha
    verify(() => gains.switchGains(
          inferKp: _kp1,
          inferKd: _kd1,
          standUpKp: _kp1,
          standUpKd: _kd1,
          sitDownKp: _kp1,
          sitDownKd: _kd1,
        )).called(1);
  });

  test('switchTo while already switching throws StateError', () async {
    // brain.switchProfile hangs until we release the completer
    final completer = Completer<void>();
    when(() => brain.switchProfile(
          observationBuilder: any(named: 'observationBuilder'),
          standingPose: any(named: 'standingPose'),
          sittingPose: any(named: 'sittingPose'),
          modelPath: any(named: 'modelPath'),
          standUpCounts: any(named: 'standUpCounts'),
          sitDownCounts: any(named: 'sitDownCounts'),
        )).thenAnswer((_) => completer.future);

    final pm = ProfileManager(
      profiles: profiles,
      brain: brain,
      initial: 'alpha',
    );

    // Start first switch (will hang)
    final firstSwitch = pm.switchTo('beta');

    // Concurrent second switch → StateError
    await expectLater(() => pm.switchTo('beta'), throwsStateError);

    // Unblock first switch
    completer.complete();
    await firstSwitch;
  });

  test('toggle with single profile is a no-op', () async {
    final pm = ProfileManager(
      profiles: {'only': profiles['alpha']!},
      brain: brain,
      initial: 'only',
    );

    await pm.toggle();
    expect(pm.currentName, 'only');
  });

  group('reload', () {
    /// 写入一条最小合法 profile JSON 文件到 [dir]/[name].json。
    Future<void> writeProfileJson(Directory dir, String name) async {
      const zeros16 = '[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]';
      final json = '{'
          '"name":"$name","modelPath":"$name.onnx",'
          '"standingPose":$zeros16,"sittingPose":$zeros16,'
          '"inferKp":$zeros16,"inferKd":$zeros16,'
          '"standUpKp":$zeros16,"standUpKd":$zeros16,'
          '"sitDownKp":$zeros16,"sitDownKd":$zeros16'
          '}';
      await File('${dir.path}/$name.json').writeAsString(json);
    }

    test('reload adds profiles newly added to disk', () async {
      final dir = await Directory.systemTemp.createTemp('pm_test_');
      try {
        await writeProfileJson(dir, 'alpha');
        await writeProfileJson(dir, 'beta');

        final pm = ProfileManager(
          profiles: {'alpha': profiles['alpha']!},
          brain: brain,
          initial: 'alpha',
        );
        expect(pm.names, ['alpha']);

        await pm.reload(dir.path);
        expect(pm.names, containsAll(['alpha', 'beta']));
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('reload removes profiles deleted from disk, never removes current', () async {
      final dir = await Directory.systemTemp.createTemp('pm_test_');
      try {
        // Disk only has alpha and beta — gamma was deleted
        await writeProfileJson(dir, 'alpha');
        await writeProfileJson(dir, 'beta');

        final pm = ProfileManager(
          profiles: {
            'alpha': profiles['alpha']!,
            'beta': profiles['beta']!,
            'gamma': _profile('gamma', _pose1, _kp1, _kd1),
          },
          brain: brain,
          initial: 'alpha',
        );
        expect(pm.names, containsAll(['alpha', 'beta', 'gamma']));

        await pm.reload(dir.path);

        expect(pm.names, isNot(contains('gamma'))); // 磁盘上已删除
        expect(pm.names, containsAll(['alpha', 'beta']));
        expect(pm.currentName, 'alpha'); // 当前策略不受影响
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('reload does not remove current profile even if absent from disk', () async {
      final dir = await Directory.systemTemp.createTemp('pm_test_');
      try {
        // Disk only has beta — alpha (current) is absent
        await writeProfileJson(dir, 'beta');

        final pm = ProfileManager(
          profiles: {'alpha': profiles['alpha']!, 'beta': profiles['beta']!},
          brain: brain,
          initial: 'alpha',
        );

        await pm.reload(dir.path);

        // alpha is current → 即使磁盘上不存在也不能移除
        expect(pm.names, contains('alpha'));
        expect(pm.currentName, 'alpha');
      } finally {
        await dir.delete(recursive: true);
      }
    });
  });
}
