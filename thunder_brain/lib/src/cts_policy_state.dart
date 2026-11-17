import 'dart:typed_data';
import 'package:skinny_dog_algebra/skinny_dog_algebra.dart';
import 'observation_builder.dart';

/// CTS V21: 50 Hz, 10 field-major frames, 12 rad/s leg targets.
class CtsPolicyState {
  static const frameCount = 10;
  static const frameSize = 53;
  static const termWidths = [3, 3, 3, 12, 16, 16];
  static const maxLegDelta = 12.0 * 0.02;
  final ThunderCtsObservationBuilder builder;
  final _frames = <Float64List>[];
  JointsMatrix lastRawAction = JointsMatrix.zero();
  late JointsMatrix _previousTarget = builder.standingPose;

  CtsPolicyState(this.builder);

  Float64List append(List<double> single) {
    if (single.length != frameSize || single.any((v) => !v.isFinite)) {
      throw StateError('CTS requires a finite 53D observation');
    }
    if (_frames.isEmpty) {
      // First-frame padding, never zero padding or old Flat history.
      for (var i = 0; i < frameCount; i++) {
        _frames.add(Float64List.fromList(single));
      }
    } else {
      _frames.removeAt(0);
      _frames.add(Float64List.fromList(single));
    }
    final history = Float64List(frameCount * frameSize);
    var sourceOffset = 0;
    var destination = 0;
    for (final width in termWidths) {
      for (final frame in _frames) {
        history.setRange(destination, destination + width, frame, sourceOffset);
        destination += width;
      }
      sourceOffset += width;
    }
    return history;
  }

  JointsMatrix decode(JointsMatrix raw) {
    if (raw.values.any((v) => !v.isFinite)) throw StateError('Non-finite CTS action');
    // History keeps network output, never a clipped/slewed motor target.
    lastRawAction = raw;
    final clipped = JointsMatrix.fromList([
      for (final v in raw.values) v.clamp(-100.0, 100.0).toDouble(),
    ]);
    final requested = (clipped * builder.actionScale + builder.standingPose).values;
    final low = builder.actionLowerLimits.values;
    final high = builder.actionUpperLimits.values;
    final bounded = JointsMatrix.fromList([
      for (var i = 0; i < 16; i++) requested[i].clamp(low[i], high[i]).toDouble(),
    ]);
    _previousTarget = limitLegDelta(_previousTarget, bounded);
    return _previousTarget;
  }

  static JointsMatrix limitLegDelta(JointsMatrix previous, JointsMatrix target) {
    final old = previous.values;
    final next = target.values;
    return JointsMatrix.fromList([
      for (var i = 0; i < 16; i++)
        i < 12 ? old[i] + (next[i] - old[i]).clamp(-maxLegDelta, maxLegDelta) : next[i],
    ]);
  }
}
