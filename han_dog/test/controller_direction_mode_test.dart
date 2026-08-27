import 'package:han_dog/src/real_controller.dart';
import 'package:robo_device_proto/robo_device_proto.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  test('standard observation keeps right-stick yaw contribution', () {
    final direction = mapYunZhuoDirection(
      _state(rightStickX: 0.8, knob: 0.1),
      observationType: 'standard',
    );

    expect(direction.z, closeTo(-0.5, 1e-6));
  });

  test('body-height observation ignores right-stick yaw contribution', () {
    final direction = mapYunZhuoDirection(
      _state(rightStickX: 0.8, knob: 0.1),
      observationType: 'bodyHeight',
    );

    expect(direction.z, closeTo(-0.1, 1e-6));
  });

  test('single-frame height observation isolates yaw from height stick', () {
    final direction = mapYunZhuoDirection(
      _state(rightStickX: 0.8, knob: 0.1),
      observationType: 'singleFrameHeight',
    );

    expect(direction.z, closeTo(-0.1, 1e-6));
  });

  test('body-height observation preserves knob sign', () {
    final direction = mapYunZhuoDirection(
      _state(knob: -0.25),
      observationType: 'bodyHeight',
    );

    expect(direction.z, closeTo(0.25, 1e-6));
  });

  test('body-height observation preserves left-stick direction signs', () {
    final direction = mapYunZhuoDirection(
      _state(leftStickX: 0.4, leftStickY: 0.6),
      observationType: 'bodyHeight',
    );

    expect(direction, closeToVector3(Vector3(0.6, -0.4, 0), 1e-6));
  });
}

YunZhuoState _state({
  double leftStickX = 0,
  double leftStickY = 0,
  double rightStickX = 0,
  double knob = 0,
}) => YunZhuoState(
  L1: false,
  L2: false,
  R1: false,
  R2: false,
  leftStick: Vector2(leftStickX, leftStickY),
  rightStick: Vector2(rightStickX, 0),
  H: false,
  G_S: GSState.middle,
  red: false,
  LT: false,
  RT: false,
  knob: knob,
  rawChannels: List<int>.filled(16, SbusValues.center),
);

Matcher closeToVector3(Vector3 expected, double delta) => predicate<Vector3>(
  (actual) =>
      (actual.x - expected.x).abs() <= delta &&
      (actual.y - expected.y).abs() <= delta &&
      (actual.z - expected.z).abs() <= delta,
  'Vector3 close to $expected within $delta',
);
