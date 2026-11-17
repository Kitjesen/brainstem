import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:thunder/src/app/local_controller.dart';
import 'package:thunder/src/gamepad.dart';
import 'package:thunder/src/real_controller.dart';

class _Gamepad extends Mock implements Gamepad {}

class _Receiver extends Mock implements RealController {}

void main() {
  test('observation gate applies only to a present serial receiver', () {
    final receiver = _Receiver();
    final otherController = _Gamepad();
    expect(isReceiverObservation(receiver, observeOnly: true), isTrue);
    expect(isReceiverObservation(receiver, observeOnly: false), isFalse);
    expect(isReceiverObservation(otherController, observeOnly: true), isFalse);
    expect(isReceiverObservation(null, observeOnly: true), isFalse);
  });

  test('hot-plugged receiver remains observed on successive scans', () {
    final receiver = _Receiver();
    final candidates = <LocalControllerCandidate Function()>[
      () => (controller: receiver, open: () => true),
    ];
    final initial = openLocalController(current: null, candidates: const []);
    expect(isReceiverObservation(initial, observeOnly: true), isFalse);
    final attached = openLocalController(
      current: initial,
      candidates: candidates,
    );
    expect(isReceiverObservation(attached, observeOnly: true), isTrue);
    final retained = openLocalController(
      current: attached,
      candidates: candidates,
    );
    expect(identical(retained, attached), isTrue);
    expect(isReceiverObservation(retained, observeOnly: true), isTrue);
  });

  test('hot-plug is allowed only while grounded, disabled and idle', () {
    bool allowed({
      bool grounded = true,
      bool enabled = false,
      bool enabling = false,
      bool calibrating = false,
      bool recovering = false,
      bool healthy = true,
    }) => canAttachLocalController(
      grounded: grounded,
      motorOutputEnabled: enabled,
      motorEnablePending: enabling,
      calibrationPending: calibrating,
      recoverySelected: recovering,
      healthy: healthy,
    );

    expect(allowed(), isTrue);
    expect(allowed(grounded: false), isFalse);
    expect(allowed(enabled: true), isFalse);
    expect(allowed(enabling: true), isFalse);
    expect(allowed(calibrating: true), isFalse);
    expect(allowed(recovering: true), isFalse);
    expect(allowed(healthy: false), isFalse);
  });

  test('receiver appearing after startup is selected before Xbox', () {
    final receiver = _Gamepad();
    final xbox = _Gamepad();
    var receiverPresent = false;
    final opened = <String>[];
    LocalControllerCandidate receiverCandidate() => (
      controller: receiver,
      open: () {
        opened.add('receiver');
        return true;
      },
    );
    LocalControllerCandidate xboxCandidate() => (
      controller: xbox,
      open: () {
        opened.add('xbox');
        return false;
      },
    );
    Iterable<LocalControllerCandidate Function()> candidates() => [
      if (receiverPresent) receiverCandidate,
      xboxCandidate,
    ];

    Gamepad? current = openLocalController(
      current: null,
      candidates: candidates(),
    );
    expect(current, isNull);
    verify(xbox.dispose).called(1);
    receiverPresent = true;
    current = openLocalController(current: current, candidates: candidates());
    expect(identical(current, receiver), isTrue);
    expect(opened, ['xbox', 'receiver']);
    verifyNever(receiver.dispose);
  });

  test('failed receiver is disposed before opening Xbox', () {
    final receiver = _Gamepad();
    final xbox = _Gamepad();
    final steps = <String>[];
    when(receiver.dispose).thenAnswer((_) => steps.add('dispose receiver'));

    final current = openLocalController(
      current: null,
      candidates: [
        () => (
          controller: receiver,
          open: () {
            steps.add('open receiver');
            return false;
          },
        ),
        () => (
          controller: xbox,
          open: () {
            steps.add('open xbox');
            return true;
          },
        ),
      ],
    );

    expect(identical(current, xbox), isTrue);
    expect(steps, ['open receiver', 'dispose receiver', 'open xbox']);
    verifyNever(xbox.dispose);
  });

  test('existing controller is retained without creating another input', () {
    final existing = _Gamepad();
    var creations = 0;
    final current = openLocalController(
      current: existing,
      candidates: [
        () {
          ++creations;
          return (controller: _Gamepad(), open: () => true);
        },
      ],
    );

    expect(identical(current, existing), isTrue);
    expect(creations, 0);
    verifyNever(existing.dispose);
  });

  test('successive scans open only once', () {
    final receiver = _Gamepad();
    var opens = 0;
    final candidates = <LocalControllerCandidate Function()>[
      () => (
        controller: receiver,
        open: () {
          ++opens;
          return true;
        },
      ),
    ];
    final first = openLocalController(current: null, candidates: candidates);
    final second = openLocalController(current: first, candidates: candidates);

    expect(identical(first, second), isTrue);
    expect(opens, 1);
    verifyNever(receiver.dispose);
  });

  test('throwing open disposes its candidate before propagating failure', () {
    final receiver = _Gamepad();
    expect(
      () => openLocalController(
        current: null,
        candidates: [
          () => (
            controller: receiver,
            open: () => throw StateError('open failed'),
          ),
        ],
      ),
      throwsStateError,
    );
    verify(receiver.dispose).called(1);
  });
}
