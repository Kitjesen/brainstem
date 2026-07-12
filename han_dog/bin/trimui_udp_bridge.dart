import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:grpc/grpc.dart';
import 'package:brainstem_api/brainstem_api.dart' as proto;

const _defaultListenPort = 13146;
const _defaultGrpcHost = '127.0.0.1';
const _defaultGrpcPort = 13145;
// TrimUI UI drawing and Wi-Fi scheduling can occasionally exceed sub-second gaps.
const _heartbeatTimeout = Duration(milliseconds: 3000);
const _statePollInterval = Duration(milliseconds: 100);
const _standWaitTimeout = Duration(seconds: 5);
const _sitWaitTimeout = Duration(seconds: 8);
const _walkStopEpsilon = 0.001;
const _telemetryInterval = Duration(milliseconds: 500);
const _voltageInterval = Duration(seconds: 2);
const _enableJointLimitRad = 3.14;
const _enableJointNames = [
  'FR Hip',
  'FR Thigh',
  'FR Calf',
  'FL Hip',
  'FL Thigh',
  'FL Calf',
  'RR Hip',
  'RR Thigh',
  'RR Calf',
  'RL Hip',
  'RL Thigh',
  'RL Calf',
  'FR Foot',
  'FL Foot',
  'RR Foot',
  'RL Foot',
];

void main(List<String> args) async {
  final listenPort = _intArg(args, '--listen-port', _defaultListenPort);
  final grpcHost = _stringArg(args, '--grpc-host', _defaultGrpcHost);
  final grpcPort = _intArg(args, '--grpc-port', _defaultGrpcPort);
  final dryRun = _boolArg(args, '--dry-run', false);

  final socket = await RawDatagramSocket.bind(
    InternetAddress.anyIPv4,
    listenPort,
  );
  print(
    'TrimUI UDP bridge listening on 0.0.0.0:$listenPort '
    '-> gRPC $grpcHost:$grpcPort dryRun=$dryRun',
  );

  final channel = dryRun
      ? null
      : ClientChannel(
          grpcHost,
          port: grpcPort,
          options: const ChannelOptions(
            credentials: ChannelCredentials.insecure(),
          ),
        );
  final client = channel == null ? null : proto.RobotControlClient(channel);

  var remoteEnabled = false;
  var failSafeRunning = false;
  var safeExitRunning = false;
  var lastWalkAt = DateTime.fromMillisecondsSinceEpoch(0);
  var lastWalkX = 0.0;
  var lastWalkY = 0.0;
  var lastWalkZ = 0.0;
  var lastTelemetryAt = DateTime.fromMillisecondsSinceEpoch(0);
  var lastVoltageAt = DateTime.fromMillisecondsSinceEpoch(0);
  var cachedVoltages = <double>[];
  Map<String, Object?>? telemetry;
  var dryState = proto.CmsState(
    kind: proto.CmsStateKind.CMS_STATE_KIND_GROUNDED,
  );
  InternetAddress? lastRemoteAddress;
  int? lastRemotePort;
  Timer? timeoutTimer;

  void sendAck(
    InternetAddress address,
    int port, {
    String event = 'ack',
    String? reason,
    bool resetEnabled = false,
  }) {
    final ack = <String, Object?>{
      'cmd': 'ack',
      'event': event,
      'enabled': remoteEnabled,
      'failsafe': failSafeRunning,
      'resetEnabled': resetEnabled || !remoteEnabled,
      't': DateTime.now().millisecondsSinceEpoch / 1000.0,
    };
    if (reason != null) ack['reason'] = reason;
    final currentTelemetry = telemetry;
    if (currentTelemetry != null) ack['telemetry'] = currentTelemetry;
    socket.send(utf8.encode(jsonEncode(ack)), address, port);
  }

  Future<void> refreshTelemetry({bool force = false}) async {
    final now = DateTime.now();
    if (!force && now.difference(lastTelemetryAt) < _telemetryInterval) {
      return;
    }
    lastTelemetryAt = now;

    if (dryRun) {
      final nextTelemetry = <String, Object?>{
        'state': _stateName(dryState),
        'jointsRad': List<double>.filled(16, 0.0),
        'jointDeg': List<double>.filled(16, 0.0),
        'jointVelocity': List<double>.filled(16, 0.0),
        'online': List<bool>.filled(16, true),
        'status': List<int>.filled(16, 0),
        'temperature': List<double>.filled(16, 0.0),
        'voltage': List<double>.filled(16, 0.0),
        'busVoltageMin': null,
        'busVoltageAvg': null,
        'updatedAt': DateTime.now().millisecondsSinceEpoch / 1000.0,
      };
      final enableBlockReason = _enableBlockReason(nextTelemetry);
      nextTelemetry['canEnable'] = enableBlockReason == null;
      nextTelemetry['enableBlockReason'] = enableBlockReason;
      telemetry = nextTelemetry;
      return;
    }

    try {
      final state = await _getState(false, client, 'telemetry state');
      final motorStatus = await client!
          .getMotorStatus(proto.Empty())
          .timeout(const Duration(milliseconds: 500));

      if (force || now.difference(lastVoltageAt) >= _voltageInterval) {
        try {
          final voltage = await client
              .getVoltage(proto.Empty())
              .timeout(const Duration(milliseconds: 1200));
          cachedVoltages = voltage.values.map((v) => v.toDouble()).toList();
          lastVoltageAt = now;
        } catch (error) {
          print('[fail] telemetry voltage: $error');
        }
      }

      final positions = List<double>.filled(16, 0.0);
      final velocities = List<double>.filled(16, 0.0);
      final online = List<bool>.filled(16, false);
      final status = List<int>.filled(16, 0);
      final temperature = List<double>.filled(16, 0.0);
      for (final motor in motorStatus.motors) {
        final id = motor.id;
        if (id < 0 || id >= 16) continue;
        positions[id] = motor.position.toDouble();
        velocities[id] = motor.velocity.toDouble();
        online[id] = motor.online;
        status[id] = motor.statusCode;
        temperature[id] = motor.temperature.toDouble();
      }
      final validVoltages = cachedVoltages.where((v) => v > 0.0).toList();
      final busMin = validVoltages.isEmpty
          ? null
          : validVoltages.reduce((a, b) => a < b ? a : b);
      final busAvg = validVoltages.isEmpty
          ? null
          : validVoltages.reduce((a, b) => a + b) / validVoltages.length;
      final nextTelemetry = <String, Object?>{
        'state': _stateName(state),
        'jointsRad': positions,
        'jointDeg': positions
            .map((v) => v * 180.0 / 3.141592653589793)
            .toList(),
        'jointVelocity': velocities,
        'online': online,
        'status': status,
        'temperature': temperature,
        'voltage': cachedVoltages,
        'busVoltageMin': busMin,
        'busVoltageAvg': busAvg,
        'updatedAt': DateTime.now().millisecondsSinceEpoch / 1000.0,
      };
      final enableBlockReason = _enableBlockReason(nextTelemetry);
      nextTelemetry['canEnable'] = enableBlockReason == null;
      nextTelemetry['enableBlockReason'] = enableBlockReason;
      telemetry = nextTelemetry;
    } catch (error) {
      telemetry = null;
      print('[fail] telemetry: $error');
    }
  }

  Future<void> remoteLostFailSafe() async {
    if (!remoteEnabled || failSafeRunning) return;
    failSafeRunning = true;
    remoteEnabled = false;
    lastWalkX = 0.0;
    lastWalkY = 0.0;
    lastWalkZ = 0.0;
    dryState = proto.CmsState(kind: proto.CmsStateKind.CMS_STATE_KIND_GROUNDED);
    final address = lastRemoteAddress;
    final port = lastRemotePort;
    print('remote heartbeat timeout: stop -> standup -> sitdown -> disable');
    if (address != null && port != null) {
      sendAck(address, port, event: 'remote_timeout', resetEnabled: true);
    }

    await _call(dryRun, 'failsafe walk zero', () {
      return client!.walk(proto.Vector3(x: 0, y: 0, z: 0));
    });
    await _call(dryRun, 'failsafe standup', () {
      return client!.standUp(proto.Empty());
    });
    await _waitForState(
      dryRun,
      client,
      {proto.CmsStateKind.CMS_STATE_KIND_STANDING},
      'standing',
      _standWaitTimeout,
    );
    await _call(dryRun, 'failsafe sitdown', () {
      return client!.sitDown(proto.Empty());
    });
    await _waitForState(
      dryRun,
      client,
      {proto.CmsStateKind.CMS_STATE_KIND_GROUNDED},
      'grounded',
      _sitWaitTimeout,
    );
    await _call(dryRun, 'failsafe disable', () {
      return client!.disable(proto.Empty());
    });

    failSafeRunning = false;
    if (address != null && port != null) {
      sendAck(address, port, event: 'failsafe_done', resetEnabled: true);
    }
  }

  void armTimeout() {
    timeoutTimer?.cancel();
    if (!remoteEnabled || failSafeRunning) return;
    timeoutTimer = Timer(_heartbeatTimeout, () {
      unawaited(remoteLostFailSafe());
    });
  }

  Future<void> runSafeExit(InternetAddress address, int port) async {
    if (safeExitRunning || failSafeRunning) {
      sendAck(
        address,
        port,
        event: 'safe_exit_ignored',
        reason: safeExitRunning ? 'safe_exit' : 'failsafe',
        resetEnabled: true,
      );
      return;
    }

    safeExitRunning = true;
    failSafeRunning = true;
    timeoutTimer?.cancel();
    sendAck(address, port, event: 'safe_exit_started');

    var ok = true;
    var disabled = false;
    final wasMoving = _isMoving(lastWalkX, lastWalkY, lastWalkZ);
    var state = dryRun
        ? dryState
        : await _getState(dryRun, client, 'safe exit precheck');
    print(
      'safe exit: moving=$wasMoving state=${_stateName(state)} '
      'velocity=($lastWalkX, $lastWalkY, $lastWalkZ)',
    );

    if (wasMoving) {
      ok = await _call(dryRun, 'safe exit walk zero', () {
        return client!.walk(proto.Vector3(x: 0, y: 0, z: 0));
      });
      if (ok) {
        lastWalkX = 0.0;
        lastWalkY = 0.0;
        lastWalkZ = 0.0;
      }

      if (ok) {
        ok = await _call(dryRun, 'safe exit standup', () {
          return client!.standUp(proto.Empty());
        });
      }
      if (ok) {
        dryState = proto.CmsState(
          kind: proto.CmsStateKind.CMS_STATE_KIND_STANDING,
        );
        ok = await _waitForState(
          dryRun,
          client,
          {proto.CmsStateKind.CMS_STATE_KIND_STANDING},
          'safe exit standing',
          _standWaitTimeout,
        );
      }

      if (ok) {
        ok = await _call(dryRun, 'safe exit sitdown', () {
          return client!.sitDown(proto.Empty());
        });
      }
      if (ok) {
        dryState = proto.CmsState(
          kind: proto.CmsStateKind.CMS_STATE_KIND_GROUNDED,
        );
        ok = await _waitForState(
          dryRun,
          client,
          {proto.CmsStateKind.CMS_STATE_KIND_GROUNDED},
          'safe exit grounded',
          _sitWaitTimeout,
        );
      }
    } else if (_isGrounded(state)) {
      print('safe exit: already grounded, disabling directly');
    } else {
      if (_isSitDownTransition(state)) {
        ok = await _waitForState(
          dryRun,
          client,
          {proto.CmsStateKind.CMS_STATE_KIND_GROUNDED},
          'safe exit grounded',
          _sitWaitTimeout,
        );
      } else {
        if (_isStandUpTransition(state)) {
          ok = await _waitForState(
            dryRun,
            client,
            {proto.CmsStateKind.CMS_STATE_KIND_STANDING},
            'safe exit standing',
            _standWaitTimeout,
          );
        }
        if (ok) {
          ok = await _call(dryRun, 'safe exit sitdown', () {
            return client!.sitDown(proto.Empty());
          });
        }
        if (ok) {
          dryState = proto.CmsState(
            kind: proto.CmsStateKind.CMS_STATE_KIND_GROUNDED,
          );
          ok = await _waitForState(
            dryRun,
            client,
            {proto.CmsStateKind.CMS_STATE_KIND_GROUNDED},
            'safe exit grounded',
            _sitWaitTimeout,
          );
        }
      }
    }

    if (ok) {
      disabled = await _call(dryRun, 'safe exit disable', () {
        return client!.disable(proto.Empty());
      });
    }
    if (disabled) {
      remoteEnabled = false;
      lastWalkX = 0.0;
      lastWalkY = 0.0;
      lastWalkZ = 0.0;
      dryState = proto.CmsState(
        kind: proto.CmsStateKind.CMS_STATE_KIND_GROUNDED,
      );
    }

    safeExitRunning = false;
    failSafeRunning = false;
    await refreshTelemetry(force: true);
    sendAck(
      address,
      port,
      event: disabled ? 'safe_exit_done' : 'safe_exit_failed',
      resetEnabled: disabled,
    );
    if (remoteEnabled) armTimeout();
  }

  Future<void> handle(
    Map<String, dynamic> msg,
    InternetAddress address,
    int port,
  ) async {
    lastRemoteAddress = address;
    lastRemotePort = port;
    final cmd = msg['cmd'];
    if (cmd == 'hello' || cmd == 'heartbeat') {
      await refreshTelemetry();
    }
    switch (cmd) {
      case 'hello':
        print('hello from ${address.address}: $msg');
        sendAck(address, port, event: 'hello');
      case 'heartbeat':
        sendAck(address, port, event: 'heartbeat');
      case 'walk':
        if (!remoteEnabled || failSafeRunning) {
          sendAck(
            address,
            port,
            event: 'walk_ignored',
            reason: failSafeRunning ? 'failsafe' : 'disabled',
            resetEnabled: true,
          );
          return;
        }
        final now = DateTime.now();
        if (now.difference(lastWalkAt) < const Duration(milliseconds: 30)) {
          armTimeout();
          return;
        }
        lastWalkAt = now;
        final x = _doubleValue(msg['x']);
        final y = _doubleValue(msg['y']);
        final z = _doubleValue(msg['z']);
        final state = dryRun
            ? dryState
            : await _getState(dryRun, client, 'walk precheck');
        if (!_canWalk(state)) {
          sendAck(
            address,
            port,
            event: 'walk_blocked',
            reason: _stateReason(state),
          );
          return;
        }
        final ok = await _call(dryRun, 'walk($x, $y, $z)', () {
          return client!.walk(proto.Vector3(x: x, y: y, z: z));
        });
        if (ok) {
          lastWalkX = x;
          lastWalkY = y;
          lastWalkZ = z;
          if (_isMoving(x, y, z)) {
            dryState = proto.CmsState(
              kind: proto.CmsStateKind.CMS_STATE_KIND_WALKING,
            );
          }
        }
        await refreshTelemetry(force: true);
        sendAck(address, port, event: ok ? 'walk' : 'walk_failed');
      case 'standup':
        if (!remoteEnabled || failSafeRunning) {
          sendAck(
            address,
            port,
            event: 'standup_ignored',
            reason: failSafeRunning ? 'failsafe' : 'disabled',
            resetEnabled: true,
          );
          return;
        }
        final state = dryRun
            ? dryState
            : await _getState(dryRun, client, 'standup precheck');
        if (!_canStandUp(state)) {
          sendAck(
            address,
            port,
            event: 'standup_blocked',
            reason: _stateReason(state),
          );
          return;
        }
        final ok = await _call(
          dryRun,
          'standup',
          () => client!.standUp(proto.Empty()),
        );
        if (ok) {
          lastWalkX = 0.0;
          lastWalkY = 0.0;
          lastWalkZ = 0.0;
          dryState = proto.CmsState(
            kind: proto.CmsStateKind.CMS_STATE_KIND_STANDING,
          );
        }
        await refreshTelemetry(force: true);
        sendAck(address, port, event: ok ? 'standup' : 'standup_failed');
      case 'sitdown':
        if (!remoteEnabled || failSafeRunning) {
          sendAck(
            address,
            port,
            event: 'sitdown_ignored',
            reason: failSafeRunning ? 'failsafe' : 'disabled',
            resetEnabled: true,
          );
          return;
        }
        final state = dryRun
            ? dryState
            : await _getState(dryRun, client, 'sitdown precheck');
        if (!_canSitDown(state, lastWalkX, lastWalkY, lastWalkZ)) {
          sendAck(
            address,
            port,
            event: 'sitdown_blocked',
            reason: _isMoving(lastWalkX, lastWalkY, lastWalkZ)
                ? 'moving'
                : _stateReason(state),
          );
          return;
        }
        final ok = await _call(
          dryRun,
          'sitdown',
          () => client!.sitDown(proto.Empty()),
        );
        if (ok) {
          lastWalkX = 0.0;
          lastWalkY = 0.0;
          lastWalkZ = 0.0;
          dryState = proto.CmsState(
            kind: proto.CmsStateKind.CMS_STATE_KIND_GROUNDED,
          );
        }
        await refreshTelemetry(force: true);
        sendAck(address, port, event: ok ? 'sitdown' : 'sitdown_failed');
      case 'enable':
        if (failSafeRunning) {
          sendAck(
            address,
            port,
            event: 'enable_ignored',
            reason: 'failsafe',
            resetEnabled: true,
          );
          return;
        }
        await refreshTelemetry(force: true);
        final blockReason = _enableBlockReason(telemetry);
        if (blockReason != null) {
          remoteEnabled = false;
          print('[blocked] enable: $blockReason');
          sendAck(
            address,
            port,
            event: 'enable_blocked',
            reason: blockReason,
            resetEnabled: true,
          );
          return;
        }
        final ok = await _call(
          dryRun,
          'enable',
          () => client!.enable(proto.Empty()),
        );
        remoteEnabled = ok;
        await refreshTelemetry(force: true);
        sendAck(address, port, event: ok ? 'enabled' : 'enable_failed');
      case 'disable':
        final ok = await _call(
          dryRun,
          'disable',
          () => client!.disable(proto.Empty()),
        );
        if (ok) {
          remoteEnabled = false;
          lastWalkX = 0.0;
          lastWalkY = 0.0;
          lastWalkZ = 0.0;
          dryState = proto.CmsState(
            kind: proto.CmsStateKind.CMS_STATE_KIND_GROUNDED,
          );
        }
        await refreshTelemetry(force: true);
        sendAck(address, port, event: ok ? 'disabled' : 'disable_failed');
      case 'safe_exit':
        await runSafeExit(address, port);
      case 'calibrate':
        if (remoteEnabled || failSafeRunning) {
          sendAck(
            address,
            port,
            event: 'calibrate_ignored',
            reason: failSafeRunning ? 'failsafe' : 'enabled',
          );
          return;
        }
        final ok = await _call(dryRun, 'calibrate', () async {
          final dynamic dynamicClient = client!;
          await dynamicClient.setZero(proto.Empty());
        });
        sendAck(address, port, event: ok ? 'calibrate' : 'calibrate_failed');
      default:
        print('unknown command from ${address.address}: $msg');
        sendAck(address, port, event: 'unknown');
    }
    armTimeout();
  }

  ProcessSignal.sigint.watch().listen((_) async {
    print('Shutting down TrimUI UDP bridge');
    timeoutTimer?.cancel();
    socket.close();
    await channel?.shutdown();
    exit(0);
  });

  await for (final event in socket) {
    if (event != RawSocketEvent.read) continue;
    Datagram? datagram;
    while ((datagram = socket.receive()) != null) {
      try {
        final packet = datagram!;
        final text = utf8.decode(packet.data);
        final msg = jsonDecode(text) as Map<String, dynamic>;
        unawaited(handle(msg, packet.address, packet.port));
      } catch (error) {
        print('bad packet: $error');
      }
    }
  }
}

Future<bool> _call(
  bool dryRun,
  String label,
  Future<void> Function() call,
) async {
  if (dryRun) {
    print('[dry-run] $label');
    return true;
  }
  try {
    await call().timeout(const Duration(milliseconds: 500));
    print('[ok] $label');
    return true;
  } catch (error) {
    print('[fail] $label: $error');
    return false;
  }
}

Future<proto.CmsState?> _getState(
  bool dryRun,
  proto.RobotControlClient? client,
  String label,
) async {
  if (dryRun) return null;
  try {
    return await client!
        .getCmsState(proto.Empty())
        .timeout(const Duration(milliseconds: 500));
  } catch (error) {
    print('[fail] getCmsState for $label: $error');
    return null;
  }
}

bool _canStandUp(proto.CmsState? state) {
  if (state == null) return true;
  return state.kind == proto.CmsStateKind.CMS_STATE_KIND_GROUNDED ||
      state.kind == proto.CmsStateKind.CMS_STATE_KIND_WALKING;
}

bool _canWalk(proto.CmsState? state) {
  if (state == null) return true;
  return state.kind == proto.CmsStateKind.CMS_STATE_KIND_STANDING ||
      state.kind == proto.CmsStateKind.CMS_STATE_KIND_WALKING;
}

String? _enableBlockReason(Map<String, Object?>? telemetry) {
  if (telemetry == null) return 'telemetry unavailable';

  final online = _listValue(telemetry['online']);
  final status = _listValue(telemetry['status']);
  final jointsRad = _listValue(telemetry['jointsRad']);
  final velocity = _listValue(telemetry['jointVelocity']);
  if (online == null ||
      status == null ||
      jointsRad == null ||
      velocity == null) {
    return 'telemetry missing motor fields';
  }
  if (online.length < 16 ||
      status.length < 16 ||
      jointsRad.length < 16 ||
      velocity.length < 16) {
    return 'telemetry has incomplete motor fields';
  }

  final offline = <String>[];
  final unsafe = <String>[];
  for (var i = 0; i < 16; i++) {
    final name = _enableJointNames[i];
    if (online[i] != true) {
      offline.add(name);
      continue;
    }
    final statusCode = _intValue(status[i]);
    if (statusCode == 1 || statusCode == 3) {
      unsafe.add('$name status=$statusCode');
    }
    final pos = _nullableDoubleValue(jointsRad[i]);
    final vel = _nullableDoubleValue(velocity[i]);
    if (i < 12 && (pos == null || pos.abs() > _enableJointLimitRad)) {
      unsafe.add('$name position=${pos?.toStringAsFixed(3) ?? "nan"}rad');
    }
    if (vel == null) {
      unsafe.add('$name velocity=nan');
    }
  }

  if (offline.isNotEmpty) return 'offline joints: ${offline.join(", ")}';
  if (unsafe.isNotEmpty) return 'unsafe joints: ${unsafe.join("; ")}';
  return null;
}

List<Object?>? _listValue(Object? value) {
  if (value is List) return value.cast<Object?>();
  return null;
}

int _intValue(Object? value) {
  if (value is int) return value;
  if (value is num && value.isFinite) return value.toInt();
  return -1;
}

double? _nullableDoubleValue(Object? value) {
  if (value is num && value.isFinite) return value.toDouble();
  return null;
}

bool _canSitDown(proto.CmsState? state, double x, double y, double z) {
  if (_isMoving(x, y, z)) return false;
  if (state == null) return true;
  if (state.kind == proto.CmsStateKind.CMS_STATE_KIND_STANDING ||
      state.kind == proto.CmsStateKind.CMS_STATE_KIND_WALKING) {
    return true;
  }
  return state.kind == proto.CmsStateKind.CMS_STATE_KIND_TRANSITIONING &&
      state.transition == proto.CmsTransitionKind.CMS_TRANSITION_KIND_STAND_UP;
}

bool _isMoving(double x, double y, double z) {
  return x.abs() > _walkStopEpsilon ||
      y.abs() > _walkStopEpsilon ||
      z.abs() > _walkStopEpsilon;
}

bool _isGrounded(proto.CmsState? state) {
  return state?.kind == proto.CmsStateKind.CMS_STATE_KIND_GROUNDED;
}

bool _isStandUpTransition(proto.CmsState? state) {
  return state?.kind == proto.CmsStateKind.CMS_STATE_KIND_TRANSITIONING &&
      state?.transition == proto.CmsTransitionKind.CMS_TRANSITION_KIND_STAND_UP;
}

bool _isSitDownTransition(proto.CmsState? state) {
  return state?.kind == proto.CmsStateKind.CMS_STATE_KIND_TRANSITIONING &&
      state?.transition == proto.CmsTransitionKind.CMS_TRANSITION_KIND_SIT_DOWN;
}

String _stateReason(proto.CmsState? state) {
  if (state == null) return 'unknown';
  if (state.kind == proto.CmsStateKind.CMS_STATE_KIND_TRANSITIONING) {
    return switch (state.transition) {
      proto.CmsTransitionKind.CMS_TRANSITION_KIND_STAND_UP => 'standup',
      proto.CmsTransitionKind.CMS_TRANSITION_KIND_SIT_DOWN => 'sitdown',
      proto.CmsTransitionKind.CMS_TRANSITION_KIND_GESTURE => 'gesture',
      _ => 'transition',
    };
  }
  return switch (state.kind) {
    proto.CmsStateKind.CMS_STATE_KIND_ZERO => 'zero',
    proto.CmsStateKind.CMS_STATE_KIND_GROUNDED => 'grounded',
    proto.CmsStateKind.CMS_STATE_KIND_STANDING => 'standing',
    proto.CmsStateKind.CMS_STATE_KIND_WALKING => 'walking',
    _ => 'state',
  };
}

String _stateName(proto.CmsState? state) {
  if (state == null) return 'unknown';
  if (state.kind == proto.CmsStateKind.CMS_STATE_KIND_TRANSITIONING) {
    return switch (state.transition) {
      proto.CmsTransitionKind.CMS_TRANSITION_KIND_STAND_UP => 'standup',
      proto.CmsTransitionKind.CMS_TRANSITION_KIND_SIT_DOWN => 'sitdown',
      proto.CmsTransitionKind.CMS_TRANSITION_KIND_GESTURE => 'gesture',
      _ => 'transition',
    };
  }
  return switch (state.kind) {
    proto.CmsStateKind.CMS_STATE_KIND_ZERO => 'zero',
    proto.CmsStateKind.CMS_STATE_KIND_GROUNDED => 'grounded',
    proto.CmsStateKind.CMS_STATE_KIND_STANDING => 'standing',
    proto.CmsStateKind.CMS_STATE_KIND_WALKING => 'walking',
    _ => 'state',
  };
}

Future<bool> _waitForState(
  bool dryRun,
  proto.RobotControlClient? client,
  Set<proto.CmsStateKind> accepted,
  String label,
  Duration timeout,
) async {
  if (dryRun) {
    print('[dry-run] wait for $label');
    return true;
  }
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    try {
      final state = await client!
          .getCmsState(proto.Empty())
          .timeout(const Duration(milliseconds: 500));
      if (accepted.contains(state.kind)) {
        print('[ok] reached $label');
        return true;
      }
    } catch (error) {
      print('[fail] getCmsState while waiting for $label: $error');
    }
    await Future<void>.delayed(_statePollInterval);
  }
  print('[timeout] wait for $label');
  return false;
}

double _doubleValue(Object? value) {
  if (value is num && value.isFinite) return value.toDouble();
  return 0;
}

int _intArg(List<String> args, String name, int fallback) {
  final prefix = '$name=';
  for (final arg in args) {
    if (arg.startsWith(prefix)) {
      return int.tryParse(arg.substring(prefix.length)) ?? fallback;
    }
  }
  return fallback;
}

String _stringArg(List<String> args, String name, String fallback) {
  final prefix = '$name=';
  for (final arg in args) {
    if (arg.startsWith(prefix)) {
      final value = arg.substring(prefix.length);
      if (value.isNotEmpty) return value;
    }
  }
  return fallback;
}

bool _boolArg(List<String> args, String name, bool fallback) {
  final prefix = '$name=';
  for (final arg in args) {
    if (arg == name) return true;
    if (arg.startsWith(prefix)) {
      final value = arg.substring(prefix.length).toLowerCase();
      return value == 'true' || value == '1' || value == 'yes';
    }
  }
  return fallback;
}
