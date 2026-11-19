import 'dart:io';

import 'package:onnx_runtime/onnx_runtime.dart';
import 'package:test/test.dart';

/// Recovery-style fixture: history[batch, 360] -> raw_action[batch, 16]
/// and features[batch, 56]. The graph is two Slices, so the values are
/// the input columns [0, 16) and [16, 72). The model file keeps a
/// symbolic batch dim; OrtRun must still return a concrete shape.
void main() {
  test('elementCount treats a symbolic dim as unknown', () {
    expect(
      OnnxFloat(
        value: const <double>[0],
        shape: const <int>[-1, 16],
      ).elementCount,
      -1,
    );
    expect(
      OnnxFloat(
        value: const <double>[],
        shape: const <int>[0, 16],
      ).elementCount,
      0,
    );
    expect(
      OnnxFloat(value: const <double>[1], shape: const <int>[]).elementCount,
      1,
    );
    expect(
      OnnxFloat(
        value: const <double>[1, 2, 3, 4],
        shape: const <int>[1, 4],
      ).elementCount,
      4,
    );
  });

  group('dynamic batch model', () {
    late OnnxEnv env;
    late InferenceSession session;

    setUp(() {
      env = OnnxEnv.create(
        OrtLoggingLevel.ORT_LOGGING_LEVEL_WARNING,
        'onnx_runtime_dynamic_batch',
      );
      // Same cwd contract as add_one_test: `dart test` from this package.
      final modelBytes = File('test/dynamic_batch.onnx').readAsBytesSync();
      session = InferenceSession.create(env, modelBytes);
    });

    tearDown(() {
      session.dispose();
      env.dispose();
    });

    test('dynamic declared shape does not overflow element count', () {
      final input = session.getInputInfo(0).info;
      expect(session.getInputName(0), 'history');
      expect(input.dimensions, [-1, 360]);
      expect(input.symbolicDimensions, ['batch', '']);
      expect(input.totalElementCount, -1);

      final raw = session.getOutputInfo(0).info;
      expect(session.getOutputName(0), 'raw_action');
      expect(raw.dimensions, [-1, 16]);
      expect(raw.symbolicDimensions.first, 'batch');
      expect(raw.totalElementCount, -1);

      final features = session.getOutputInfo(1).info;
      expect(session.getOutputName(1), 'features');
      expect(features.dimensions, [-1, 56]);
      expect(features.symbolicDimensions.first, 'batch');
      expect(features.totalElementCount, -1);
    });

    test('run uses the concrete OrtValue shape for each batch', () {
      for (final batch in [1, 2]) {
        final history = <double>[
          for (var row = 0; row < batch; row++)
            for (var col = 0; col < 360; col++) (row * 360 + col).toDouble(),
        ];
        final (names, outputs) = session.run({
          'history': OnnxFloat(value: history, shape: [batch, 360]),
        });
        expect(names, ['raw_action', 'features']);

        final raw = outputs[0] as OnnxFloat;
        final features = outputs[1] as OnnxFloat;
        expect(raw.shape, [batch, 16]);
        expect(features.shape, [batch, 56]);
        expect(raw.value, _columns(history, batch, 0, 16));
        expect(features.value, _columns(history, batch, 16, 56));
        expect(raw.shape.any((int dim) => dim <= 0), isFalse);
        expect(features.shape.any((int dim) => dim <= 0), isFalse);
      }
    });
  });
}

List<double> _columns(List<double> history, int batch, int start, int width) {
  return <double>[
    for (var row = 0; row < batch; row++)
      for (var col = 0; col < width; col++) history[row * 360 + start + col],
  ];
}
