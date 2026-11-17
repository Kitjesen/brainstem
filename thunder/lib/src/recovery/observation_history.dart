import 'dart:math' as math;
import 'dart:typed_data';
import 'recovery.dart';

class RecoveryObservationHistory {
  static final _nominal = Float32List.fromList(RecoveryController.nominal);
  static final _velocityScale = Float32List.fromList([.05])[0];
  Float32List? frames;
  final previousRaw = Float32List(16);
  int step = 0;

  void reset() {
    frames = null;
    previousRaw.fillRange(0, 16, 0);
    step = 0;
  }

  Float32List append(RecoverySample sample) {
    sample.validate();
    final angular = Float32List.fromList(sample.angular);
    final gravity = Float32List.fromList(sample.gravity);
    final q = Float32List.fromList(sample.q);
    final dq = Float32List.fromList(sample.dq);
    final obs = Float32List(60);
    for (var i = 0; i < 3; i++) {
      obs[i] = angular[i].clamp(-100, 100) * .25;
      obs[3 + i] = gravity[i].clamp(-100, 100);
    }
    for (var i = 0; i < 12; i++) {
      obs[9 + i] = q[i] - _nominal[i];
      obs[9 + i] = obs[9 + i].clamp(-100, 100);
    }
    for (var i = 0; i < 16; i++) {
      obs[25 + i] = dq[i].clamp(-100, 100) * _velocityScale;
      obs[41 + i] = previousRaw[i];
    }
    obs[57] = 2;
    final phase = 2 * math.pi * (step * .02) / 1.2;
    obs[58] = math.sin(phase);
    obs[59] = math.cos(phase);
    final history = frames;
    if (history == null) {
      frames = Float32List(360);
      for (var i = 0; i < 6; i++) {
        frames!.setRange(i * 60, (i + 1) * 60, obs);
      }
    } else {
      history.setRange(0, 300, history, 60);
      history.setRange(300, 360, obs);
    }
    return frames!;
  }

  void commit(List<double> raw) {
    if (raw.length != 16 || raw.any((v) => !v.isFinite || v.abs() > 4)) {
      throw StateError('Invalid raw action history');
    }
    previousRaw.setAll(0, raw);
    step++;
  }
}
