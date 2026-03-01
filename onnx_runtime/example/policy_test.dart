import 'dart:async';
import 'dart:io';

import 'package:onnx_runtime/onnx_runtime.dart';

void main() async {
  final env = OnnxEnv.create(
    OrtLoggingLevel.ORT_LOGGING_LEVEL_WARNING,
    'onnx_runtime_example',
  );

  final modelBytes = await File('example/policy.onnx').readAsBytes();

  final session = InferenceSession.create(env, modelBytes, SessionOptions());

  print('Session created successfully');

  print('session.inputCounts: ${session.inputCounts}');
  print('session.outputCounts: ${session.outputCounts}');
  print('session.getInputInfo(0): ${session.getInputInfo(0)}');
  print('session.getOutputInfo(0): ${session.getOutputInfo(0)}');
  print('session.getInputName(0): ${session.getInputName(0)}');
  print('session.getOutputName(0): ${session.getOutputName(0)}');

  int counts = 0;
  int frequency = 0;

  final t1 = Timer.periodic(Duration(seconds: 1), (timer) {
    frequency = counts;
    counts = 0;
  });

  // 用 Timer 驱动推理
  final t2 = Timer.periodic(Duration(milliseconds: 1), (timer) {
    final (outputNames, outputValues) = session.run({
      'obs': OnnxFloat(value: List.generate(57, (i) => 0), shape: [1, 57]),
    });
    print('$frequency hz x: $counts, y: ${outputValues[0]}');
    counts++;
  });

  await Future.delayed(Duration(seconds: 5));

  t1.cancel();
  t2.cancel();
  // 注意：不要在这里dispose，因为Timer是异步的，会导致session被过早释放
  session.dispose();
  env.dispose();
}
