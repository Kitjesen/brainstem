import 'package:skinny_dog_algebra/skinny_dog_algebra.dart';
import 'package:vector_math/vector_math.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'common.freezed.dart';

@freezed
sealed class Command with _$Command {
  const Command._();

  const factory Command.idle() = IdleCommand;
  const factory Command.standUp() = StandUpCommand;
  const factory Command.sitDown() = SitDownCommand;
  const factory Command.walk(Vector3 direction) = WalkCommand;
  const factory Command.gesture(String name) = GestureCommand;

  @override
  String toString() => switch (this) {
    IdleCommand() => 'idle',
    StandUpCommand() => 'stand up',
    SitDownCommand() => 'sit down',
    WalkCommand(:final direction) => 'walk ${direction.str}',
    GestureCommand(:final name) => 'gesture($name)',
  };
}

@freezed
abstract class History with _$History {
  const History._();

  const factory History({
    required Vector3 gyroscope,
    required Vector3 projectedGravity,
    required Command command,
    required JointsMatrix jointPosition,
    required JointsMatrix jointVelocity,
    required JointsMatrix action,
    required JointsMatrix nextAction,
  }) = _History;
  factory History.zero() => History(
    gyroscope: .zero(),
    projectedGravity: .zero(),
    command: .idle(),
    jointPosition: .zero(),
    jointVelocity: .zero(),
    action: .zero(),
    nextAction: .zero(),
  );

  @override
  String toString() =>
      """
gyr: ${gyroscope.str}
gra: ${projectedGravity.str}
cmd: $command
pos: 
$jointPosition
vel: 
$jointVelocity
act: 
$action
nxt: 
$nextAction
""";
}

extension on Vector3 {
  String get str => "(${x.str}, ${y.str}, ${z.str})";
}

const _dots = 3;
const _numWidth = _dots * 2 + 1; // 1 for .

extension on double {
  String get str =>
      "${sign < 0 ? '-' : ' '}"
      "${abs().toStringAsFixed(_dots).padLeft(_numWidth, '0')}";
}
