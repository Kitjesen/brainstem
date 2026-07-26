import 'package:han_dog/han_dog.dart';
import 'package:skinny_dog_algebra/skinny_dog_algebra.dart';
import 'package:test/test.dart';

final startAction = JointsMatrix.fromList(
  List<double>.generate(16, (index) => index / 10),
);
final policyAction = JointsMatrix.fromList(
  List<double>.generate(16, (index) => 1.5 - index / 20),
);
final standKp = JointsMatrix.fromList(List<double>.filled(16, 200));
final standKd = JointsMatrix.fromList(List<double>.filled(16, 8));
final inferKp = JointsMatrix.fromList(List<double>.filled(16, 100));
final inferKd = JointsMatrix.fromList(List<double>.filled(16, 15));

BodyHeightHandover buildHandover() => BodyHeightHandover(
  standUpKp: standKp,
  standUpKd: standKd,
  inferKp: inferKp,
  inferKd: inferKd,
);

MotorActionDispatcher buildDispatcher(
  BodyHeightHandover handover,
  List<JointsMatrix> sent,
) => MotorActionDispatcher(
  handover: handover,
  gateAction: (desired, measured) => desired,
  sendAction: (desired) {
    sent.add(desired);
    return true;
  },
  setGains: (_, _) {},
);

void main() {
  test('disabled and Grounded outputs never advance the handover', () {
    final handover = buildHandover()
      ..requestFrom(startAction)
      ..begin();
    final sent = <JointsMatrix>[];
    final dispatcher = buildDispatcher(handover, sent);

    expect(
      dispatcher.dispatch(
        outputEnabled: false,
        grounded: false,
        policyAction: policyAction,
        measuredPosition: startAction,
      ),
      isFalse,
    );
    expect(handover.preview(policyAction).frameIndex, 0);
    expect(sent, isEmpty);

    expect(
      dispatcher.dispatch(
        outputEnabled: true,
        grounded: true,
        policyAction: policyAction,
        measuredPosition: startAction,
      ),
      isTrue,
    );
    expect(handover.preview(policyAction).frameIndex, 0);
    expect(sent.single.values, startAction.discardFoot().values);
  });

  test('frame 100 is sent before command blocking is released', () {
    final handover = buildHandover()
      ..requestFrom(startAction)
      ..begin();
    final sent = <JointsMatrix>[];
    final dispatcher = buildDispatcher(handover, sent);

    for (var sample = 0; sample <= BodyHeightHandover.intervalCount; sample++) {
      expect(handover.blocksControllerCommands, isTrue);
      dispatcher.dispatch(
        outputEnabled: true,
        grounded: false,
        policyAction: policyAction,
        measuredPosition: startAction,
      );
    }

    expect(sent, hasLength(101));
    expect(sent.first.values, startAction.discardFoot().values);
    expect(sent.last.values, policyAction.values);
    expect(handover.blocksControllerCommands, isFalse);
  });

  for (final failingStage in ['gain', 'gate', 'send']) {
    test('$failingStage failure does not advance frame 0', () {
      final handover = buildHandover()
        ..requestFrom(startAction)
        ..begin();
      final events = <String>[];
      final dispatcher = MotorActionDispatcher(
        handover: handover,
        gateAction: (desired, measured) {
          events.add('gate');
          if (failingStage == 'gate') throw StateError('gate failed');
          return desired;
        },
        sendAction: (desired) {
          events.add('send');
          if (failingStage == 'send') throw StateError('send failed');
          return true;
        },
        setGains: (_, _) {
          events.add('gain');
          if (failingStage == 'gain') throw StateError('gain failed');
        },
      );

      expect(
        () => dispatcher.dispatch(
          outputEnabled: true,
          grounded: false,
          policyAction: policyAction,
          measuredPosition: startAction,
        ),
        throwsStateError,
      );
      expect(handover.preview(policyAction).frameIndex, 0);
      expect(events, switch (failingStage) {
        'gain' => ['gain'],
        'gate' => ['gain', 'gate'],
        _ => ['gain', 'gate', 'send'],
      });
    });
  }

  test('normal output without a handover still gates before sending', () {
    final events = <String>[];
    final dispatcher = MotorActionDispatcher(
      handover: null,
      gateAction: (desired, measured) {
        events.add('gate');
        return desired;
      },
      sendAction: (_) {
        events.add('send');
        return true;
      },
      setGains: (_, _) => events.add('gain'),
    );

    expect(
      dispatcher.dispatch(
        outputEnabled: true,
        grounded: false,
        policyAction: policyAction,
        measuredPosition: startAction,
      ),
      isTrue,
    );
    expect(events, ['gate', 'send']);
  });

  test('silently rejected output does not advance the handover', () {
    final handover = buildHandover()
      ..requestFrom(startAction)
      ..begin();
    final dispatcher = MotorActionDispatcher(
      handover: handover,
      gateAction: (desired, measured) => desired,
      sendAction: (_) => false,
      setGains: (_, _) {},
    );

    expect(
      dispatcher.dispatch(
        outputEnabled: true,
        grounded: false,
        policyAction: policyAction,
        measuredPosition: startAction,
      ),
      isFalse,
    );
    expect(handover.preview(policyAction).frameIndex, 0);
  });
}
