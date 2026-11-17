import 'dart:async';
import 'dart:typed_data';

import 'package:robo_device/src/serial_port/controller.dart';
import 'package:test/test.dart';

Stream<Iterable<int>> decodeBytes(Stream<Uint8List> input) =>
    input.map<Iterable<int>>((bytes) => bytes);

class FakeSerialPort implements SerialPort {
  FakeSerialPort({this.openResult = true});

  final bool openResult;
  final actions = <String>[];
  final data = StreamController<Uint8List>.broadcast();
  String _portName = '';

  @override
  String get portName => _portName;

  @override
  String get lastErrorMessage => 'fake open failure';

  @override
  Stream<Uint8List> get onData => data.stream;

  @override
  void init(
    String portName, [
    int baudRate = 115200,
    Parity parity = Parity.ParityNone,
    DataBits dataBits = DataBits.DataBits8,
    StopBits stopbits = StopBits.StopOne,
    FlowControl flowControl = FlowControl.FlowNone,
    int readBufferSize = 4096,
  ]) {
    _portName = portName;
    actions.add('init:$portName');
  }

  @override
  bool open() {
    actions.add('open');
    return openResult;
  }

  @override
  set dtr(bool value) => actions.add('dtr:$value');

  @override
  set readIntervalTimeout(int value) => actions.add('timeout:$value');

  @override
  void close() => actions.add('close');

  @override
  void dispose() => actions.add('dispose');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'read-only controller constructs and decodes without a send converter',
    () async {
      final native = FakeSerialPort();
      final controller = SerialPortController<Never, int>(
        '/dev/yunzhuo',
        serialPort: native,
        stateDecoder: decodeBytes,
      );
      final first = controller.state.first.timeout(const Duration(seconds: 1));
      native.data.add(Uint8List.fromList([0x0f, 0x80, 0xff]));

      expect(await first, [0x0f, 0x80, 0xff]);
      controller.dispose();
      await native.data.close();
    },
  );

  test('DTR and timeout are applied only after a successful open', () async {
    final native = FakeSerialPort();
    final controller = SerialPortController<Never, int>(
      '/dev/yunzhuo',
      serialPort: native,
      stateDecoder: decodeBytes,
      dtr: true,
      readIntervalTimeoutMs: 5,
    );

    expect(controller.open(), isTrue);
    expect(native.actions, [
      'init:/dev/yunzhuo',
      'open',
      'timeout:5',
      'dtr:true',
    ]);
    controller.close();
    controller.dispose();
    controller.close();
    controller.dispose();
    expect(native.actions.sublist(4), ['close', 'dispose']);
    await native.data.close();
  });

  test('failed open does not change DTR or timeout', () async {
    final native = FakeSerialPort(openResult: false);
    final controller = SerialPortController<Never, int>(
      '/dev/yunzhuo',
      serialPort: native,
      stateDecoder: decodeBytes,
      dtr: true,
      readIntervalTimeoutMs: 5,
    );

    expect(controller.open(), isFalse);
    expect(native.actions, ['init:/dev/yunzhuo', 'open']);
    controller.dispose();
    await native.data.close();
  });

  test('default DTR leaves existing serial devices unchanged', () async {
    final native = FakeSerialPort();
    final controller = SerialPortController<Never, int>(
      '/dev/imu',
      serialPort: native,
      stateDecoder: decodeBytes,
    );

    expect(controller.open(), isTrue);
    expect(native.actions, ['init:/dev/imu', 'open']);
    controller.dispose();
    await native.data.close();
  });

  test('explicit low DTR is preserved on each open', () async {
    final native = FakeSerialPort();
    final controller = SerialPortController<Never, int>(
      '/dev/test',
      serialPort: native,
      stateDecoder: decodeBytes,
      dtr: false,
    );

    expect(controller.open(), isTrue);
    controller.close();
    expect(controller.open(), isTrue);
    expect(native.actions, [
      'init:/dev/test',
      'open',
      'dtr:false',
      'close',
      'open',
      'dtr:false',
    ]);
    controller.dispose();
    await native.data.close();
  });
}
