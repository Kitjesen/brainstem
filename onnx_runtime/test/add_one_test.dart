import 'dart:io';
import 'package:test/test.dart';
import 'package:onnx_runtime/onnx_runtime.dart';

void main() {
  late OnnxEnv env;
  late InferenceSession session;

  setUp(() async {
    env = OnnxEnv.create(
      OrtLoggingLevel.ORT_LOGGING_LEVEL_WARNING,
      'onnx_runtime_example',
    );
    final modelBytes = await File('test/add_one.onnx').readAsBytes();
    session = InferenceSession.create(env, modelBytes);
  });

  tearDown(() {
    session.dispose();
    env.dispose();
  });

  test('add_one model inference returns correct result', () {
    final (outputNames, outputValues) = session.run({
      'x': OnnxFloat(value: [1.0], shape: [1]),
    });
    // You may want to adjust the expected value based on your model
    final result = outputValues[0] as OnnxFloat;
    expect(result.value[0], closeTo(2.0, 1e-5));
  });
}
