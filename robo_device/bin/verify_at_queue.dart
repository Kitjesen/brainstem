import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:logging/logging.dart';
import 'package:robo_device/robo_device.dart';
import 'package:robo_device_proto/robo_device_proto.dart';

const atPath = '/dev/serial/by-id/usb-1a86_USB_Serial-if00-port0';
const spacing = Duration(milliseconds: 5);
const readKeys = [
  RSKey.mechPos,
  RSKey.mechVel,
  RSKey.iqf,
  RSKey.vbus,
  RSKey.epscanTime,
  RSKey.zeroSta,
  RSKey.runMode,
];

bool allowed(PcanMessage m) {
  if (m.type != PcanMessageType.extended ||
      m.length != 8 ||
      m.id < 0 ||
      m.id > 0x1fffffff ||
      (m.id & 255) < 1 ||
      (m.id & 255) > 4 ||
      ((m.id >> 8) & 0xffff) != 255) {
    return false;
  }
  final b = m.data;
  if (m.id >> 24 == 0x11) {
    return readKeys.any((k) => k.value == (b[0] | b[1] << 8)) &&
        b.skip(2).every((v) => v == 0);
  }
  return m.id >> 24 == 0x18 &&
      List.generate(6, (i) => b[i] == i + 1).every((v) => v) &&
      (b[6] == 0 || b[6] == 1) &&
      b[7] == 0;
}

PcanMessage message(RSEvent event) {
  final f = event.toCanFrame();
  return PcanMessage(id: f.id, type: PcanMessageType.extended, data: f.data);
}

class ProbeAt extends RobStrideAtPcan {
  ProbeAt() : super(atPath);
  void Function(PcanMessage, int)? sent;
  void Function(PcanMessage)? received;
  final watch = Stopwatch()..start();
  int opens = 0;

  @override
  PcanStatus open([PcanBaudRate baudRate = PcanBaudRate.baud1M]) {
    opens++;
    return super.open(baudRate);
  }

  @override
  PcanStatus write(PcanMessage m) {
    // Enforce at the physical exit, not only at the diagnostic call sites.
    if (!allowed(m)) throw StateError('Blocked non-diagnostic AT frame');
    final t = watch.elapsedMicroseconds;
    final result = super.write(m);
    if (result == PcanStatus.ok) sent?.call(m, t);
    return result;
  }

  @override
  (PcanMessage, PcanTimestamp, PcanStatus) read() {
    final result = super.read();
    if (result.$3 == PcanStatus.ok) received?.call(result.$1);
    return result;
  }
}

double? percentile(List<double> values, double fraction) {
  if (values.isEmpty) return null;
  final sorted = [...values]..sort();
  return sorted[(sorted.length * fraction).ceil() - 1];
}

({int queued, int? sent})? takeReply(
  Map<(int, RSKey), ({int queued, int? sent})> pending,
  int id,
  RSKey? key,
  int host,
) {
  if (host != 255 || key == null || pending[(id, key)]?.sent == null) {
    return null;
  }
  return pending.remove((id, key));
}

Map<String, Object?> feedbackContinuity(
  List<Map<String, Object?>> frames,
  int start,
  int end,
  Map<int, int> periods,
) {
  final motors = <String, Object?>{};
  var allValid = true;
  for (var id = 1; id <= 4; id++) {
    final times =
        frames
            .where((r) => r['id'] == id)
            .map((r) => r['t_us'] as int)
            .where((t) => t >= start && t <= end)
            .toList()
          ..sort();
    final points = [start, ...times, end];
    final gaps = [
      for (var i = 1; i < points.length; i++)
        (points[i] - points[i - 1]) / 1000,
    ];
    final maxGap = gaps.reduce(math.max);
    final hz = times.length * 1e6 / (end - start);
    final period = periods[id]!;
    final valid =
        period <= 20 &&
        maxGap <= math.max(50, period * 5) &&
        hz >= .9 * 1000 / period;
    allValid = allValid && valid;
    motors['$id'] = {
      'frames': times.length,
      'hz': hz,
      'max_gap_ms': maxGap,
      'valid': valid,
    };
  }
  return {'valid': allValid, 'motors': motors};
}

void selfTest() {
  for (var id = 1; id <= 4; id++) {
    for (final k in readKeys) {
      if (!allowed(message(RSEvent.get(id, key: k)))) throw StateError('Read');
    }
    for (final b in [false, true]) {
      if (!allowed(message(RSEvent.setReporting(id, enable: b)))) {
        throw StateError('Reporting');
      }
    }
    for (final e in [
      RSEvent.control(id),
      RSEvent.enable(id),
      RSEvent.disable(id),
      RSEvent.setZero(id),
      RSEvent.saveData(id),
      RSEvent.set(id, setter: RSSetter.locKp(1)),
      RSEvent.get(id, key: RSKey.locRef),
    ]) {
      if (allowed(message(e))) throw StateError('Unsafe frame accepted');
    }
  }
  for (final id in [0, 5]) {
    if (allowed(message(RSEvent.get(id, key: RSKey.mechPos)))) {
      throw StateError('Unexpected motor ID accepted');
    }
  }
  final altered = message(RSEvent.get(1, key: RSKey.mechPos));
  altered.data[7] = 1;
  if (allowed(altered)) throw StateError('Read payload not checked');
  if (allowed(message(RSEvent.get(1, hostId: 1, key: RSKey.mechPos)))) {
    throw StateError('Unexpected host ID accepted');
  }
  final pending = <(int, RSKey), ({int queued, int? sent})>{
    (1, RSKey.mechPos): (queued: 1, sent: null),
  };
  if (takeReply(pending, 1, RSKey.mechPos, 255) != null || pending.isEmpty) {
    throw StateError('Unsent request consumed');
  }
  pending[(1, RSKey.mechPos)] = (queued: 1, sent: 2);
  if (takeReply(pending, 1, RSKey.mechPos, 1) != null ||
      pending.isEmpty ||
      takeReply(pending, 1, RSKey.mechPos, 255)?.sent != 2 ||
      pending.isNotEmpty) {
    throw StateError('Reply host/sent validation');
  }
  final frames = [
    for (var id = 1; id <= 4; id++)
      for (var t = 10000; t <= 100000; t += 10000)
        <String, Object?>{'id': id, 't_us': t},
  ];
  final periods = {for (var id = 1; id <= 4; id++) id: 10};
  if (feedbackContinuity(frames, 0, 100000, periods)['valid'] != true ||
      feedbackContinuity(
            frames.where((r) => r['id'] != 4).toList(),
            0,
            100000,
            periods,
          )['valid'] !=
          false) {
    throw StateError('Feedback continuity validation');
  }
  print('Self-check passed; no hardware opened');
}

// This endpoint has no serial port: control/stop frames never reach hardware.
class DryCan extends Pcan {
  DryCan() : super(PcanChannel.nonebus);
  void Function(PcanMessage)? sent;
  @override
  PcanStatus write(PcanMessage m) {
    sent?.call(m);
    return PcanStatus.ok;
  }

  @override
  PcanStatus close() => PcanStatus.ok;
}

Future<Map<String, Object?>> dryControls() async {
  final can = DryCan();
  final c = PcanController<RSEvent, RSState>.withPcan(
    can,
    writeInterval: spacing,
  );
  final w = Stopwatch()..start();
  final generated = <String, int>{};
  final counts = <int, int>{};
  final ages = <double>[];
  var submitted = 0, peak = 0, callbacks = 0;
  String key(PcanMessage m) => '${m.id}:${m.data.join(',')}';
  can.sent = (m) {
    final id = m.id & 255;
    counts[id] = (counts[id] ?? 0) + 1;
    ages.add((w.elapsedMicroseconds - generated[key(m)]!) / 1000);
  };
  final timer = Timer.periodic(const Duration(milliseconds: 20), (t) {
    callbacks++;
    for (var id = 1; id <= 4; id++) {
      final e = RSEvent.control(id, position: t.tick * .001);
      generated[key(message(e))] = w.elapsedMicroseconds;
      c.add(e);
      submitted++;
      peak = math.max(peak, c.pendingWrites);
    }
  });
  try {
    await Future<void>.delayed(const Duration(seconds: 5));
  } finally {
    timer.cancel();
  }
  final duration = w.elapsedMicroseconds / 1e6;
  await Future<void>.delayed(const Duration(milliseconds: 80));
  final result = <String, Object?>{
    'physical_serial_opened': false,
    'duration_s': duration,
    'producer_callbacks': callbacks,
    'submitted': submitted,
    'written': ages.length,
    'per_motor_written': counts.map((k, v) => MapEntry('$k', v)),
    'wire_age_p99_ms': percentile(ages, .99),
    'wire_age_max_ms': percentile(ages, 1),
    'pending_peak': peak,
    'pending_end': c.pendingWrites,
    'failed_or_expired': c.failedWrites,
  };
  c.dispose();
  return result;
}

RSKey? getterKey(RSGetter? g) => switch (g) {
  RSGetterMechPos() => RSKey.mechPos,
  RSGetterMechVel() => RSKey.mechVel,
  RSGetterIqf() => RSKey.iqf,
  RSGetterVbus() => RSKey.vbus,
  RSGetterEpscanTime() => RSKey.epscanTime,
  RSGetterZeroSta() => RSKey.zeroSta,
  RSGetterRunMode() => RSKey.runMode,
  _ => null,
};

Object? getterValue(RSGetter? g) => switch (g) {
  RSGetterMechPos(:final value) ||
  RSGetterMechVel(:final value) ||
  RSGetterIqf(:final value) ||
  RSGetterVbus(:final value) => value,
  RSGetterEpscanTime(:final value) => value,
  RSGetterZeroSta(:final value) => value,
  RSGetterRunMode(:final value) => value.name,
  _ => null,
};

Future<void> guardHardware() async {
  if (!Platform.isLinux) throw StateError('Hardware mode requires Linux');
  final device = File(atPath).resolveSymbolicLinksSync();
  final usb = File(
    '/sys/class/tty/${device.split('/').last}/device',
  ).resolveSymbolicLinksSync();
  if (!usb.split('/').contains('3-2')) {
    throw StateError('Unexpected AT USB route');
  }
  for (final u in [
    'thunder.service',
    'brainstem.service',
    'piper-teleop.service',
  ]) {
    final p = await Process.run('systemctl', [
      'show',
      u,
      '--property=ActiveState,MainPID',
    ]);
    final lines = p.stdout.toString().split('\n');
    if (!lines.contains('ActiveState=inactive') ||
        !lines.contains('MainPID=0')) {
      throw StateError('Controller not stopped: $u ${p.stdout}');
    }
  }
  final p = await Process.run('sudo', ['-n', 'fuser', atPath]);
  if (p.exitCode != 1 ||
      p.stdout.toString().trim().isNotEmpty ||
      p.stderr.toString().trim().isNotEmpty) {
    throw StateError('AT port not unused');
  }
}

Future<Map<String, Object?>> hardwareProbe() async {
  await guardHardware();
  final at = ProbeAt();
  final c = PcanController<RSEvent, RSState>.withPcan(
    at,
    writeInterval: spacing,
  );
  final pending = <(int, RSKey), ({int queued, int? sent})>{};
  final replies = <Map<String, Object?>>[];
  final reports = <Map<String, Object?>>[];
  final tx = <Map<String, Object?>>[];
  final rxModes = <String, int>{};
  final rawParameters = <Map<String, Object?>>[];
  final toggled = <int>[];
  final periods = <int, int>{};
  var phase = 'initial_passive', peak = 0;
  Object? streamError;
  at.sent = (m, t) {
    final mode = m.id >> 24, id = m.id & 255;
    tx.add({
      't_us': t,
      'mode': mode,
      'id': id,
      'phase': phase,
      if (mode == 0x18) 'reporting_enable': m.data[6] == 1,
    });
    if (mode == 0x11) {
      final key = RSKey.fromValue(m.data[0] | m.data[1] << 8);
      final p = pending[(id, key)];
      if (p == null || p.sent != null) {
        streamError = 'Unexpected duplicate/untracked physical getter write';
        return;
      }
      pending[(id, key)] = (queued: p.queued, sent: t);
    }
  };
  at.received = (m) {
    final mode = '${m.id >> 24}';
    rxModes[mode] = (rxModes[mode] ?? 0) + 1;
    if (m.id >> 24 == 0x11 && phase == 'parameter_snapshot') {
      rawParameters.add({
        'id_hex': m.id.toRadixString(16),
        'data_hex': m.data
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join(),
      });
    }
  };
  final sub = c.state.listen(
    (s) {
      final t = at.watch.elapsedMicroseconds;
      switch (s) {
        case RSStateGetter(:final canId, :final hostId, :final getter):
          final key = getterKey(getter);
          final p = takeReply(pending, canId, key, hostId);
          if (p != null && getter is RSGetterEpscanTime) {
            periods[canId] = getter.value;
          }
          replies.add({
            't_us': t,
            'phase': phase,
            'id': canId,
            'key': key?.name,
            'value': getterValue(getter),
            'matched': p?.sent != null,
            'queue_ms': p?.sent == null ? null : (p!.sent! - p.queued) / 1000,
            'rtt_ms': p?.sent == null ? null : (t - p!.sent!) / 1000,
          });
        case RSStateReport(
              :final canId,
              :final status,
              :final position,
              :final velocity,
              :final torque,
              :final temperature,
              :final errors,
            ) ||
            RSStateResponse(
              :final canId,
              :final status,
              :final position,
              :final velocity,
              :final torque,
              :final temperature,
              :final errors,
            ):
          reports.add({
            't_us': t,
            'phase': phase,
            'id': canId,
            'kind': s is RSStateReport ? 'report' : 'response',
            'status': status.name,
            'position_rad': position,
            'velocity_rad_s': velocity,
            'torque_nm': torque,
            'temperature_c': temperature,
            'fault_bits': errors.value,
            'errors': errors.errors.map((e) => e.name).toList(),
          });
          if (status != RSStatus.reset || errors.value != 0) {
            streamError =
                'Motor $canId reports status=${status.name}, faults=${errors.value}';
          }
        case RSStateError(:final canId, :final errors):
          if (errors.value != 0) {
            streamError = 'Motor $canId full fault ${errors.value}';
          }
        default:
          break;
      }
    },
    onError: (Object e) {
      streamError = e.toString();
    },
  );
  void submit(int id, RSKey key) {
    pending[(id, key)] = (queued: at.watch.elapsedMicroseconds, sent: null);
    c.add(RSEvent.get(id, key: key));
    peak = math.max(peak, c.pendingWrites);
  }

  Future<void> drain() async {
    final deadline = at.watch.elapsedMilliseconds + 500;
    while ((pending.isNotEmpty || c.pendingWrites != 0) &&
        at.watch.elapsedMilliseconds < deadline) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    if (pending.isNotEmpty || c.pendingWrites != 0 || streamError != null) {
      throw StateError(
        'Unfinished replies/queue or invalid state: $pending $streamError',
      );
    }
  }

  Future<Map<String, Object?>> load(String name) async {
    phase = name;
    peak = 0;
    final first = replies.length,
        reportFirst = reports.length,
        txFirst = tx.length;
    final failures = c.failedWrites, start = at.watch.elapsedMicroseconds;
    var skipped = 0, callbacks = 0, ticks = 0;
    final timer = Timer.periodic(const Duration(milliseconds: 20), (t) {
      if (streamError != null) return;
      callbacks++;
      ticks = t.tick;
      for (var id = 1; id <= 4; id++) {
        if (pending.containsKey((id, RSKey.mechPos))) {
          skipped++;
          continue;
        }
        submit(id, RSKey.mechPos);
      }
    });
    try {
      await Future<void>.delayed(const Duration(seconds: 8));
    } finally {
      timer.cancel();
    }
    final end = at.watch.elapsedMicroseconds;
    await drain();
    final selected = replies.skip(first).toList();
    final rtt = selected
        .where((v) => v['rtt_ms'] != null)
        .map((v) => v['rtt_ms'] as double)
        .toList();
    final waits = selected
        .where((v) => v['queue_ms'] != null)
        .map((v) => v['queue_ms'] as double)
        .toList();
    final seconds = (end - start) / 1e6;
    final continuity = feedbackContinuity(
      reports.skip(reportFirst).toList(),
      start,
      end,
      periods,
    );
    if (selected.any((r) => r['matched'] != true) ||
        c.failedWrites != failures ||
        at.opens != 1) {
      throw StateError('Unmatched replies, send failures or transport reopen');
    }
    return {
      'name': name,
      'duration_s': seconds,
      'producer_callbacks': callbacks,
      'producer_tick_index': ticks,
      'submitted': callbacks * 4 - skipped,
      'written': tx.length - txFirst,
      'matched': selected.where((v) => v['matched'] == true).length,
      'skipped_outstanding': skipped,
      'mean_read_hz_per_motor': selected.length / seconds / 4,
      'rtt_p99_ms': percentile(rtt, .99),
      'rtt_max_ms': percentile(rtt, 1),
      'queue_p99_ms': percentile(waits, .99),
      'queue_max_ms': percentile(waits, 1),
      'pending_peak': peak,
      'failed_or_expired': c.failedWrites - failures,
      'feedback_count': reports.length - reportFirst,
      'feedback_continuity': continuity,
      'all_feedback_accepted_by_RealJoint_report_branch': reports
          .skip(reportFirst)
          .every((r) => r['kind'] == 'report'),
    };
  }

  final result = <String, Object?>{
    'time': DateTime.now().toIso8601String(),
    'port': atPath,
    'spacing_ms': 5,
    'motor_enable_or_control_sent': false,
  };
  var restored = false;
  try {
    if (!c.open()) throw StateError('Could not open AT');
    await Future<void>.delayed(const Duration(seconds: 1));
    if (streamError != null) throw StateError('$streamError');
    phase = 'parameter_snapshot';
    for (var id = 1; id <= 4; id++) {
      for (final key in readKeys) {
        submit(id, key);
        await drain();
      }
    }
    if (periods.length != 4 || periods.values.any((v) => v < 5 || v > 1000)) {
      throw StateError('Reporting interval not established: $periods');
    }
    phase = 'initial_report_observation';
    final observationStart = at.watch.elapsedMicroseconds;
    await Future<void>.delayed(
      Duration(
        milliseconds: math.max(1000, periods.values.reduce(math.max) * 2 + 200),
      ),
    );
    final initiallyReporting = reports
        .where((r) => (r['t_us'] as int) >= observationStart)
        .map((r) => r['id'] as int)
        .toSet();
    result['initial_reporting_ids_observed'] = initiallyReporting.toList();
    result['report_intervals_ms'] = periods.map((k, v) => MapEntry('$k', v));
    result['initial_silent_ids_are_not_readback_of_enable_flag'] = true;
    result['final_reporting_policy'] =
        'Explicitly close only streams enabled by this test; no permanent parameter save';
    result['initial_load'] = await load('initial_load');
    phase = 'reporting_on';
    for (var id = 1; id <= 4; id++) {
      if (!initiallyReporting.contains(id)) {
        toggled.add(id);
        c.add(RSEvent.setReporting(id, enable: true));
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (streamError != null) throw StateError('$streamError');
    var reportingIds = reports
        .where((r) => r['phase'] == 'reporting_on')
        .map((r) => r['id'])
        .toSet();
    final missingFirst = [
      for (var id = 1; id <= 4; id++)
        if (!reportingIds.contains(id)) id,
    ];
    result['first_enable_missing_ids'] = missingFirst;
    result['reporting_enable_retry_ids'] = <int>[];
    for (final id in missingFirst) {
      (result['reporting_enable_retry_ids'] as List<int>).add(id);
      c.add(RSEvent.setReporting(id, enable: true));
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    reportingIds = reports
        .where((r) => r['phase'] == 'reporting_on')
        .map((r) => r['id'])
        .toSet();
    if (!{1, 2, 3, 4}.every(reportingIds.contains)) {
      throw StateError('Missing full reports: $reportingIds');
    }
    result['full_feedback_load'] = await load('full_feedback_load');
    final full = result['full_feedback_load'] as Map<String, Object?>;
    if ((full['feedback_continuity'] as Map)['valid'] != true) {
      throw StateError(
        'Full feedback criteria failed; see per-motor measured rates and gaps',
      );
    }
  } catch (e) {
    result['failure'] = e.toString();
  } finally {
    phase = 'restoring_reporting';
    c.clearPendingWrites();
    pending.clear();
    final cleanupStart = at.watch.elapsedMicroseconds;
    for (final id in toggled) {
      c.add(RSEvent.setReporting(id, enable: false));
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
    phase = 'cleanup_fresh_reads';
    try {
      for (var id = 1; id <= 4; id++) {
        submit(id, RSKey.vbus);
      }
      await drain();
    } catch (e) {
      result['cleanup_failure'] = e.toString();
    }
    phase = 'restored_passive';
    final n = reports.length;
    await Future<void>.delayed(
      Duration(
        milliseconds: math.max(
          600,
          periods.values.fold(10, math.max) * 2 + 200,
        ),
      ),
    );
    final offSent = tx
        .where(
          (r) =>
              r['phase'] == 'restoring_reporting' &&
              r['mode'] == 0x18 &&
              r['reporting_enable'] == false &&
              (r['t_us'] as int) >= cleanupStart,
        )
        .map((r) => r['id'])
        .toSet();
    final freshIds = replies
        .where(
          (r) =>
              r['phase'] == 'cleanup_fresh_reads' &&
              r['matched'] == true &&
              r['key'] == 'vbus',
        )
        .map((r) => r['id'])
        .toSet();
    restored =
        at.opens == 1 &&
        c.failedWrites == 0 &&
        streamError == null &&
        toggled.every(offSent.contains) &&
        {1, 2, 3, 4}.every(freshIds.contains) &&
        c.pendingWrites == 0 &&
        at.status == PcanStatus.ok &&
        !reports.skip(n).any((r) => toggled.contains(r['id']));
    result.addAll({
      'reporting_toggled_ids': toggled,
      'test_enabled_reporting_closed_and_link_verified': restored,
      'cleanup_report_off_ids_sent': offSent.toList(),
      'cleanup_fresh_reply_ids': freshIds.toList(),
      'transport_opens': at.opens,
      'failed_or_expired_total': c.failedWrites,
      'rx_modes': rxModes,
      'raw_parameter_snapshot': rawParameters,
      'tx_frames': tx,
      'replies': replies,
      'reports': reports,
    });
    await sub.cancel();
    c.dispose();
  }
  if (!restored) {
    result['failure'] =
        '${result['failure'] ?? ''} Final report-off/link verification failed';
  }
  return result;
}

Future<void> main(List<String> args) async {
  if (args.isEmpty || args.singleOrNull == '--self-test') {
    selfTest();
    return;
  }
  if (args.singleOrNull == '--dry-controls') {
    print(jsonEncode(await dryControls()));
    return;
  }
  if (args.length != 2 ||
      args.first != '--hardware' ||
      !args[1].startsWith('--output=')) {
    throw ArgumentError(
      'Use --self-test, --dry-controls or --hardware --output=NEW.json',
    );
  }
  final output = File(args[1].substring('--output='.length));
  if (output.existsSync() || !output.parent.existsSync()) {
    throw StateError('Use a new output file in an existing directory');
  }
  Logger.root.level = Level.WARNING;
  final logs = <String>[];
  final logSub = Logger.root.onRecord.listen((r) {
    logs.add('${r.level.name}: ${r.message}');
    stderr.writeln(logs.last);
  });
  final result = await hardwareProbe();
  result['warnings'] = logs;
  output.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(result));
  await logSub.cancel();
  print(
    jsonEncode(
      {...result}
        ..remove('tx_frames')
        ..remove('replies')
        ..remove('reports'),
    ),
  );
  print('RESULT_FILE=${output.path}');
  if (result['failure'] != null) exitCode = 1;
}
