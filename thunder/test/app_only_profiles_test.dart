import 'dart:async';
import 'package:brainstem_api/brainstem_api.dart' as proto;
import 'package:grpc/grpc.dart';
import 'package:thunder/thunder.dart';
import 'package:thunder_brain/thunder_brain.dart';
import 'package:mocktail/mocktail.dart';
import 'package:skinny_dog_algebra/skinny_dog_algebra.dart';
import 'package:test/test.dart';
import '../bin/thunder.dart' show configureAppProfiles;

class FakeBrain extends Mock implements Brain {}
class FakeJoint extends Mock implements RealJoint {}
class FakeMachine extends Mock implements M {}
class FakeCall extends Mock implements ServiceCall {}
JointsMatrix matrix(double n) => JointsMatrix.fromList(List<double>.filled(16, n));
RobotProfile profile(String name) => RobotProfile(name: name, modelPath: '$name.onnx',
  standingPose: matrix(0), sittingPose: matrix(0), inferKp: matrix(1), inferKd: matrix(2),
  standUpKp: matrix(3), standUpKd: matrix(4), sitDownKp: matrix(5), sitDownKd: matrix(6));

void main() {
  setUpAll(() => registerFallbackValue(matrix(0)));
  test('without a controller, profile RPC reports configured policy and accepted states update real gains; handover stops duplicate writes', () async {
    final brain = FakeBrain();
    final joint = FakeJoint();
    final machine = FakeMachine();
    final states = StreamController<S>(sync: true);
    final history = const Stream<History>.empty().listen((_) {});
    final values = <double>[];
    when(() => joint.kpExt = any()).thenAnswer((call) {
      final value = call.positionalArguments.single as JointsMatrix;
      values.add(value.frHip);
      return value;
    });
    when(() => joint.kdExt = any()).thenAnswer((call) => call.positionalArguments.single as JointsMatrix);
    var attached = false;
    var faults = 0;
    final wiring = configureAppProfiles(brain: brain, joint: joint,
      profiles: {'flat': profile('flat'), 'stairs': profile('stairs')}, initial: 'flat',
      operatorSlots: OperatorModeSlots.fromJson({'flat': 'flat', 'stairs': 'stairs'}),
      states: states.stream, controllerPresent: () => attached, onFault: (_) => faults++);
    final server = UnifiedCmsServer(m: machine, brain: brain)..profileManager = wiring.manager;
    final result = await server.getProfile(FakeCall(), proto.Empty());
    expect(result.current, 'flat');
    expect(result.available, ['flat', 'stairs']);
    states.add(S.transitioning(const Command.standUp(), history, null));
    states.add(S.walking(history));
    states.add(S.transitioning(const Command.sitDown(), history, null));
    expect(values, [3, 1, 5]);
    attached = true;
    states.add(S.walking(history));
    expect(values, [3, 1, 5]);
    states.addError(StateError('fixture'));
    expect(faults, 1);
    await wiring.subscription.cancel();
    await states.close();
    await history.cancel();
    verifyNever(() => joint.enable());
    verifyNever(() => joint.disable());
  });
}
