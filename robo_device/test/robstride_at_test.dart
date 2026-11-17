import 'dart:async';
import 'dart:typed_data';

import 'package:robo_device/robo_device.dart';
import 'package:robo_device_proto/robo_device_proto.dart';
import 'package:test/test.dart';

PcanMessage frame(int id, List<int> data) => PcanMessage(
  id: id,
  type: PcanMessageType.extended,
  data: Uint8List.fromList(data),
);

class FakeSerialPort implements SerialPort {
  final input = StreamController<Uint8List>(sync: true);
  final writes = <Uint8List>[];
  String? initializedPath;
  int? initializedBaud;
  int? writtenCount;
  bool openResult = true;
  bool disposed = false;
  @override
  Stream<Uint8List> get onData => input.stream;
  @override
  void init(
    String name, [
    int baudRate = 115200,
    Parity parity = Parity.ParityNone,
    DataBits dataBits = DataBits.DataBits8,
    StopBits stopbits = StopBits.StopOne,
    FlowControl flowControl = FlowControl.FlowNone,
    int readBufferSize = 4096,
  ]) {
    initializedPath = name;
    initializedBaud = baudRate;
    expect(
      (parity, dataBits, stopbits, flowControl),
      (
        Parity.ParityNone,
        DataBits.DataBits8,
        StopBits.StopOne,
        FlowControl.FlowNone,
      ),
    );
  }

  @override
  bool open() => openResult;
  @override
  set readIntervalTimeout(int milliseconds) => expect(milliseconds, 1);
  @override
  int write(Uint8List data) {
    writes.add(Uint8List.fromList(data));
    return writtenCount ?? data.length;
  }

  @override
  String get lastErrorMessage => 'fake open failure';
  @override
  int get lastErrorCode => 0;
  @override
  void dispose() {
    disposed = true;
    input.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('official manual AT golden vector, including big-endian packed ID', () {
    final message = frame(0x1200fd01, [5, 0x70, 0, 0, 1, 0, 0, 0]);
    final expected = [
      0x41,
      0x54,
      0x90,
      0x07,
      0xe8,
      0x0c,
      8,
      5,
      0x70,
      0,
      0,
      1,
      0,
      0,
      0,
      0x0d,
      0x0a,
    ];
    expect(encodeRobStrideAt(message), expected);
    final decoded = RobStrideAtDecoder()
        .add(Uint8List.fromList(expected))
        .single;
    expect(decoded.id, message.id);
    expect(decoded.data, message.data);
  });

  test(
    'decoder handles every split, coalescing and header bytes in payload',
    () {
      final source = frame(0x110001ff, [0x41, 0x54, 0x0d, 0x0a, 0, 0, 0, 0]);
      final bytes = encodeRobStrideAt(source);
      for (var split = 0; split <= bytes.length; split++) {
        final decoder = RobStrideAtDecoder();
        final decoded = [
          ...decoder.add(Uint8List.sublistView(bytes, 0, split)),
          ...decoder.add(
            Uint8List.fromList([...bytes.sublist(split), ...bytes]),
          ),
        ];
        expect(decoded.map((m) => m.id), [source.id, source.id]);
        expect(
          decoded.every((m) => m.data.toString() == source.data.toString()),
          isTrue,
        );
      }
    },
  );

  test(
    'decoder resynchronizes after noise, invalid DLC, flags and trailer',
    () {
      final valid = encodeRobStrideAt(frame(0x1fffffff, []));
      final badFlags = Uint8List.fromList(valid)..[5] = 0;
      final badTail = Uint8List.fromList(valid)..[8] = 0;
      final decoded = RobStrideAtDecoder()
          .add(
            Uint8List.fromList([
              0,
              0x41,
              ...[0x41, 0x54, 0, 0, 0, 4, 9],
              ...badFlags,
              ...badTail,
              ...valid,
            ]),
          )
          .toList();
      expect(decoded, hasLength(1));
      expect(decoded.single.id, 0x1fffffff);
      expect(decoded.single.data, isEmpty);
    },
  );

  test('codec rejects non-classic, non-extended and invalid identifiers', () {
    for (final message in [
      frame(-1, []),
      frame(0x20000000, []),
      frame(1, [])..type = PcanMessageType.rtr,
      frame(1, [])..data = Uint8List(9),
    ]) {
      expect(() => encodeRobStrideAt(message), throwsArgumentError);
    }
  });

  test('transport construction is lazy, open configures 921600 8N1', () {
    var creations = 0;
    final port = FakeSerialPort();
    final at = RobStrideAtPcan(
      '/dev/fake',
      createPort: () {
        creations++;
        return port;
      },
    );
    expect(creations, 0);
    expect(at.open(), PcanStatus.ok);
    expect(port.initializedPath, '/dev/fake');
    expect(port.initializedBaud, 921600);
    expect(port.writes, isEmpty);
    expect(
      at.write(frame(0x1100ff01, [0x19, 0x70, 0, 0, 0, 0, 0, 0])),
      PcanStatus.ok,
    );
    expect(port.writes, hasLength(1));
    at.close();
    at.close();
    expect(port.disposed, isTrue);
    expect(at.read().$3, PcanStatus.initialize);
  });

  test('short writes latch an error instead of replaying a partial frame', () {
    final port = FakeSerialPort()..writtenCount = 5;
    final at = RobStrideAtPcan('/dev/fake', createPort: () => port);
    at.open();
    expect(at.write(frame(1, [])), PcanStatus.busoff);
    expect(at.write(frame(2, [])), PcanStatus.busoff);
    expect(port.writes, hasLength(1));
    expect(at.read().$3, PcanStatus.busoff);
    at.close();
  });

  test('failed open disposes resources and permits a fresh open', () {
    final failed = FakeSerialPort()..openResult = false;
    final fresh = FakeSerialPort();
    var calls = 0;
    final at = RobStrideAtPcan(
      '/dev/fake',
      createPort: () => calls++ == 0 ? failed : fresh,
    );
    expect(at.open(), PcanStatus.illhw);
    expect(failed.disposed, isTrue);
    expect(at.open(), PcanStatus.ok);
    expect(at.read().$3, PcanStatus.qrcvempty);
    at.close();
  });

  test('fragmented AT feedback uses existing RS report decoding', () async {
    final port = FakeSerialPort();
    final controller = PcanController<RSEvent, RSState>.withPcan(
      RobStrideAtPcan('/dev/fake', createPort: () => port),
      writeInterval: const Duration(milliseconds: 5),
    );
    expect(controller.open(), isTrue);
    final received = controller.state.first.timeout(const Duration(seconds: 1));
    final wire = encodeRobStrideAt(
      frame(0x180003ff, [0x80, 0, 0x80, 0, 0x80, 0, 1, 44]),
    );
    port.input.add(Uint8List.sublistView(wire, 0, 3));
    port.input.add(Uint8List.sublistView(wire, 3));
    final state = await received as RSStateReport;
    expect(state.canId, 3);
    expect(state.hostId, 255);
    expect(state.position, closeTo(0, 0.001));
    expect(state.temperature, 30);
    controller.dispose();
    expect(port.writes, isEmpty);
  });

  test('receive overflow is bounded and not returned as stale feedback', () {
    final port = FakeSerialPort();
    final at = RobStrideAtPcan('/dev/fake', createPort: () => port);
    at.open();
    final wire = encodeRobStrideAt(frame(0x180001ff, List.filled(8, 0)));
    for (var i = 0; i < 513; i++) {
      port.input.add(wire);
    }
    expect(at.read().$3, PcanStatus.qoverrun);
    at.close();
  });
}
