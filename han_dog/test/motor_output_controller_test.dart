import 'dart:async';

import 'package:han_dog/han_dog.dart';
import 'package:han_dog_brain/han_dog_brain.dart';
import 'package:skinny_dog_algebra/skinny_dog_algebra.dart';
import 'package:test/test.dart';

class _RecordingMotor implements MotorService {
  var enableCalls = 0;
  var disableCalls = 0;
  var lastClearErrors = false;
  void Function()? onEnable;

  @override
  Future<void> disable({bool clearErrors = false}) async {
    disableCalls++;
    lastClearErrors = clearErrors;
  }

  @override
  Future<void> enable() async {
    enableCalls++;
    onEnable?.call();
  }

  @override
  void sendAction(JointsMatrix action) {}
}

class _PendingDisableMotor extends _RecordingMotor {
  final disableCompleter = Completer<void>();

  @override
  Future<void> disable({bool clearErrors = false}) {
    disableCalls++;
    lastClearErrors = clearErrors;
    return disableCompleter.future;
  }
}

class _FailingEnableMotor extends _RecordingMotor {
  @override
  Future<void> enable() async {
    enableCalls++;
    throw StateError('enable frame failed after transmission started');
  }
}

class _FailingDisableMotor extends _RecordingMotor {
  @override
  Future<void> disable({bool clearErrors = false}) async {
    disableCalls++;
    lastClearErrors = clearErrors;
    throw StateError('disable frame was not confirmed');
  }
}

void main() {
  test(
    'emergency disable closes the output gate and clears motor errors',
    () async {
      final motor = _RecordingMotor();
      final output = MotorOutputController(motor: motor);

      expect(await output.enable(ControlSource.yunzhuo), isNull);
      expect(output.isEnabled, isTrue);

      await output.disable(clearErrors: true);

      expect(output.isEnabled, isFalse);
      expect(motor.disableCalls, 1);
      expect(motor.lastClearErrors, isTrue);
    },
  );

  test(
    'a disable during asynchronous preparation supersedes Enable before its frame',
    () async {
      final motor = _RecordingMotor();
      final prepared = Completer<void>();
      final output = MotorOutputController(
        motor: motor,
        prepareForEnable: () => prepared.future,
      );

      final enable = output.enable(ControlSource.yunzhuo);
      await Future<void>.delayed(Duration.zero);
      final disable = output.disable();
      expect(output.isEnabled, isFalse);
      prepared.complete();

      expect(await enable, 'motor enable superseded by a later request');
      await disable;

      expect(motor.enableCalls, 0);
      expect(motor.disableCalls, 1);
      expect(output.isEnabled, isFalse);
    },
  );

  test('a failed Enable sends a best-effort physical Disable', () async {
    final motor = _FailingEnableMotor();
    final output = MotorOutputController(motor: motor);

    await expectLater(
      output.enable(ControlSource.yunzhuo),
      throwsA(isA<StateError>()),
    );

    expect(output.isEnabled, isFalse);
    expect(motor.enableCalls, 1);
    expect(motor.disableCalls, 1);
  });

  test('a latched safety inhibit blocks every later Enable', () async {
    final motor = _RecordingMotor();
    final output = MotorOutputController(motor: motor);

    output.inhibitEnables('low-voltage lockout');

    expect(await output.enable(ControlSource.yunzhuo), 'low-voltage lockout');
    expect(motor.enableCalls, 0);
  });

  test('notifies consumers when the output gate changes', () async {
    final motor = _RecordingMotor();
    final changes = <bool>[];
    final output = MotorOutputController(
      motor: motor,
      onOutputChanged: changes.add,
    );

    expect(await output.enable(ControlSource.yunzhuo), isNull);
    await output.disable();

    expect(changes, <bool>[true, false]);
  });

  test('a notification failure cannot prevent physical disable', () async {
    final motor = _RecordingMotor();
    var failNotifications = false;
    final output = MotorOutputController(
      motor: motor,
      onOutputChanged: (_) {
        if (failNotifications) throw StateError('observer failed');
      },
    );
    expect(await output.enable(ControlSource.yunzhuo), isNull);
    failNotifications = true;

    await output.disable();

    expect(output.isEnabled, isFalse);
    expect(motor.disableCalls, 1);
  });

  test('prepares a current-position hold before enabling torque', () async {
    final events = <String>[];
    final motor = _RecordingMotor()..onEnable = () => events.add('enable');
    final output = MotorOutputController(
      motor: motor,
      prepareForEnable: () async {
        events.add('hold');
      },
    );

    expect(await output.enable(ControlSource.yunzhuo), isNull);

    expect(events, <String>['hold', 'enable']);
  });

  test('rechecks safety after an asynchronous enable preparation', () async {
    final motor = _RecordingMotor();
    final prepared = Completer<void>();
    String? rejection;
    final output = MotorOutputController(
      motor: motor,
      enableBlockReason: () => rejection,
      prepareForEnable: () => prepared.future,
    );

    final enable = output.enable(ControlSource.yunzhuo);
    await Future<void>.delayed(Duration.zero);
    rejection = 'joint feedback became unsafe';
    prepared.complete();

    expect(await enable, 'joint feedback became unsafe');
    expect(motor.enableCalls, 0);
    expect(output.isEnabled, isFalse);
  });

  test('maintenance waits for a pending physical disable', () async {
    final motor = _PendingDisableMotor();
    final output = MotorOutputController(motor: motor);
    expect(await output.enable(ControlSource.yunzhuo), isNull);

    final disable = output.disable();
    var maintenanceRan = false;
    final maintenance = output.runWhileDisabled(() async {
      maintenanceRan = true;
    });
    await Future<void>.delayed(Duration.zero);
    expect(maintenanceRan, isFalse);

    motor.disableCompleter.complete();
    await disable;
    await maintenance;

    expect(maintenanceRan, isTrue);
    expect(motor.disableCalls, 2);
  });

  test(
    'maintenance never runs when physical Disable cannot be confirmed',
    () async {
      final motor = _FailingDisableMotor();
      final output = MotorOutputController(motor: motor);
      expect(await output.enable(ControlSource.yunzhuo), isNull);

      await expectLater(output.disable(), throwsA(isA<StateError>()));
      var maintenanceRan = false;

      await expectLater(
        output.runWhileDisabled(() async {
          maintenanceRan = true;
        }),
        throwsA(isA<StateError>()),
      );

      expect(maintenanceRan, isFalse);
      expect(output.isEnabled, isFalse);
      expect(motor.disableCalls, 2);
      expect(
        await output.enable(ControlSource.yunzhuo),
        'motor output is not confirmed disabled',
      );
      expect(motor.enableCalls, 1);
    },
  );
}
