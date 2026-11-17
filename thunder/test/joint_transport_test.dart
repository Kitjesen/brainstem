import 'package:thunder/src/app/joint_transport.dart';
import 'package:robo_device/robo_device.dart';
import 'package:test/test.dart';

void main() {
  final paths = {
    '/sys/class/net/can0/device': '/sys/devices/usb1/1-1.1/1-1.1:1.0',
    '/sys/class/net/can2/device': '/sys/devices/usb1/1-1.2/1-1.2:1.0',
    '/sys/class/net/can1/device': '/sys/devices/usb1/1-2.1/1-2.1:1.0',
    '/sys/class/net/can3/device': '/sys/devices/usb1/1-1.3/1-1.3:1.0',
    '/dev/imu': '/dev/ttyUSB0',
  };
  const env = {
    'THUNDER_IMU_PORT': '/dev/imu',
    'THUNDER_JOINT_TRANSPORT': 'rdk-s100-pcan',
  };
  String resolve(String path) =>
      paths[path] ?? (throw StateError('Missing $path'));

  test('all four PCAN channels match the replacement-board USB mapping', () {
    expect(rdkS100PcanRoutes['FR']!.channel, PcanChannel.usbbus1);
    expect(rdkS100PcanRoutes['FL']!.channel, PcanChannel.usbbus3);
    expect(rdkS100PcanRoutes['RR']!.channel, PcanChannel.usbbus2);
    expect(rdkS100PcanRoutes['RL']!.channel, PcanChannel.usbbus4);
    expect(rdkS100PcanRoutes.values.map((r) => r.interface).toSet(), {
      'can0',
      'can1',
      'can2',
      'can3',
    });
    validateRdkS100JointTopology(environment: env, resolvePath: resolve);
  });

  test('USB topology mismatch fails before constructing devices', () {
    for (final route in rdkS100PcanRoutes.values) {
      expect(
        () => validateRdkS100JointTopology(
          environment: env,
          resolvePath: (p) => p == '/sys/class/net/${route.interface}/device'
              ? '/sys/devices/usb9/9-9/9-9:1.0'
              : resolve(p),
        ),
        throwsStateError,
      );
    }
  });

  test('IMU must be explicitly configured and resolve successfully', () {
    expect(
      () => validateRdkS100JointTopology(environment: {}, resolvePath: resolve),
      throwsStateError,
    );
    expect(
      () => validateRdkS100JointTopology(
        environment: {'THUNDER_IMU_PORT': '/dev/missing_imu'},
        resolvePath: resolve,
      ),
      throwsStateError,
    );
  });

  test(
    'four PCAN controllers construct without AT pacing or opening hardware',
    () {
      final joint = createHardwareJoint(environment: env, resolvePath: resolve);
      try {
        expect(joint.pcans, hasLength(4));
        expect(
          joint.pcans.map((p) => p.writeInterval),
          everyElement(Duration.zero),
        );
        expect(joint.pcans.map((p) => p.pendingWrites), everyElement(0));
        expect(joint.pcans.map((p) => p.failedWrites), everyElement(0));
      } finally {
        joint.dispose();
      }
    },
  );

  test('retired mixed selector fails rather than choosing a different leg', () {
    expect(
      () => createHardwareJoint(
        environment: {'THUNDER_JOINT_TRANSPORT': 'rdk-s100-mixed'},
      ),
      throwsStateError,
    );
  });

  test('unknown transport fails without hardware access', () {
    expect(
      () =>
          createHardwareJoint(environment: {'THUNDER_JOINT_TRANSPORT': 'typo'}),
      throwsArgumentError,
    );
  });
}
