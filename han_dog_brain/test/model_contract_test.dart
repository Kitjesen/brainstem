import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:han_dog_brain/han_dog_brain.dart';
import 'package:mocktail/mocktail.dart';
import 'package:skinny_dog_algebra/skinny_dog_algebra.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

class _Imu extends Mock implements ImuService {}

class _Joint extends Mock implements JointService {}

void main() {
  late Directory temp;
  late _Imu imu;
  late _Joint joint;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('model-contract-');
    imu = _Imu();
    joint = _Joint();
    when(() => imu.initialGyroscope).thenReturn(Vector3.zero());
    when(() => imu.initialProjectedGravity).thenReturn(Vector3(0, 0, -1));
    when(() => imu.gyroscope).thenReturn(Vector3.zero());
    when(() => imu.projectedGravity).thenReturn(Vector3(0, 0, -1));
    when(() => joint.initialPosition).thenReturn(JointsMatrix.zero());
    when(() => joint.initialVelocity).thenReturn(JointsMatrix.zero());
    when(() => joint.position).thenReturn(JointsMatrix.zero());
    when(() => joint.velocity).thenReturn(JointsMatrix.zero());
  });
  tearDown(() => temp.delete(recursive: true));

  Brain brain() {
    final clock = StreamController<void>.broadcast();
    final result = Brain(
      imu: imu,
      joint: joint,
      clock: clock,
      historySize: 1,
      standingPose: JointsMatrix.zero(),
      sittingPose: JointsMatrix.zero(),
      observationBuilder: BodyHeightObservationBuilder(
        standingPose: JointsMatrix.zero(),
      ),
    );
    addTearDown(() async {
      result.dispose();
      await clock.close();
    });
    return result;
  }

  Future<String> model(_Spec spec) async {
    final file = File('${temp.path}/model.onnx');
    await file.writeAsBytes(_model(spec));
    return file.path;
  }

  test('accepts rank-2 float tensors with fixed or dynamic batch', () async {
    for (final spec in [
      const _Spec(),
      const _Spec(input: ['batch', 58], output: ['batch', 16]),
    ]) {
      final target = brain();
      await target.loadModel(await model(spec));
      expect(target.isModelLoaded, isTrue);
    }
  });

  final invalid = <String, (_Spec, String)>{
    'input count': (const _Spec(inputs: 2), 'exactly 1 input'),
    'output count': (const _Spec(outputs: 2), 'exactly 1 output'),
    'input type': (const _Spec(inputType: 7), 'input type'),
    'output type': (const _Spec(outputType: 7), 'output type'),
    'input rank': (const _Spec(input: [58]), 'input rank'),
    'output rank': (const _Spec(output: [16]), 'output rank'),
    'input batch': (const _Spec(input: [2, 58]), 'input batch'),
    'output batch': (const _Spec(output: [2, 16]), 'output batch'),
    'dynamic feature': (
      const _Spec(input: [1, 'features']),
      'input feature dimension',
    ),
    'dynamic action': (
      const _Spec(output: [1, 'actions']),
      'output action dimension',
    ),
  };
  for (final MapEntry(key: name, value: entry) in invalid.entries) {
    test('rejects unsupported $name and leaves no session', () async {
      final target = brain();
      await expectLater(
        target.loadModel(await model(entry.$1)),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains(entry.$2),
          ),
        ),
      );
      expect(target.isModelLoaded, isFalse);
    });
  }
}

class _Spec {
  final int inputs, outputs, inputType, outputType;
  final List<Object> input, output;
  const _Spec({
    this.inputs = 1,
    this.outputs = 1,
    this.inputType = 1,
    this.outputType = 1,
    this.input = const [1, 58],
    this.output = const [1, 16],
  });
}

Uint8List _model(_Spec s) {
  final g = BytesBuilder(copy: false);
  for (var i = 0; i < s.outputs; i++) {
    g.add(
      _m(
        1,
        _constant(
          'action$i',
          s.output.map((d) => d is int ? d : 1),
          s.outputType,
        ),
      ),
    );
  }
  g.add(_s(2, 'contract'));
  for (var i = 0; i < s.inputs; i++) {
    g.add(_m(11, _value('obs$i', s.input, s.inputType)));
  }
  for (var i = 0; i < s.outputs; i++) {
    g.add(_m(12, _value('action$i', s.output, s.outputType)));
  }
  return (BytesBuilder(copy: false)
        ..add(_i(1, 8))
        ..add(_m(7, g.takeBytes()))
        ..add(_m(8, _i(2, 13))))
      .takeBytes();
}

Uint8List _constant(String output, Iterable<int> shape, int type) {
  final a = BytesBuilder(copy: false)
    ..add(_s(1, 'value'))
    ..add(_m(5, _tensor('${output}_value', shape, type)))
    ..add(_i(20, 4));
  return (BytesBuilder(copy: false)
        ..add(_s(2, output))
        ..add(_s(4, 'Constant'))
        ..add(_m(5, a.takeBytes())))
      .takeBytes();
}

Uint8List _tensor(String name, Iterable<int> shape, int type) {
  final dims = shape.toList(), b = BytesBuilder(copy: false);
  for (final d in dims) {
    b.add(_i(1, d));
  }
  final count = dims.fold(1, (a, d) => a * d);
  b
    ..add(_i(2, type))
    ..add(_s(8, name))
    ..add(_b(9, Uint8List(count * (type == 1 ? 4 : 8))));
  return b.takeBytes();
}

Uint8List _value(String name, List<Object> shape, int type) {
  final dimensions = BytesBuilder(copy: false);
  for (final d in shape) {
    dimensions.add(_m(1, d is int ? _i(1, d) : _s(2, '$d')));
  }
  final tensor = BytesBuilder(copy: false)
    ..add(_i(1, type))
    ..add(_m(2, dimensions.takeBytes()));
  return (BytesBuilder(copy: false)
        ..add(_s(1, name))
        ..add(_m(2, _m(1, tensor.takeBytes()))))
      .takeBytes();
}

Uint8List _i(int f, int v) => Uint8List.fromList([..._v(f << 3), ..._v(v)]);
Uint8List _s(int f, String v) => _b(f, utf8.encode(v));
Uint8List _m(int f, List<int> v) => _b(f, v);
Uint8List _b(int f, List<int> v) =>
    Uint8List.fromList([..._v((f << 3) | 2), ..._v(v.length), ...v]);
List<int> _v(int v) {
  final r = <int>[];
  do {
    var b = v & 127;
    v >>= 7;
    if (v != 0) b |= 128;
    r.add(b);
  } while (v != 0);
  return r;
}
