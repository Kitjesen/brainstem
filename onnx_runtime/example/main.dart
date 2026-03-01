import 'dart:io';

import 'package:onnx_runtime/onnx_runtime.dart';

void main() async {
  final env = OnnxEnv.create(
    OrtLoggingLevel.ORT_LOGGING_LEVEL_WARNING,
    'onnx_runtime_example',
  );

  final modelBytes = await File('example/policy.onnx').readAsBytes();

  final session = InferenceSession.create(env, modelBytes);

  print('Session created successfully');

  print('session.inputCounts: ${session.inputCounts}');
  print('session.outputCounts: ${session.outputCounts}');
  print('session.getInputInfo(0): ${session.getInputInfo(0)}');
  print('session.getOutputInfo(0): ${session.getOutputInfo(0)}');
  print('session.getInputName(0): ${session.getInputName(0)}');
  print('session.getOutputName(0): ${session.getOutputName(0)}');
  final (outputNames, outputValues) = session.run({
    'obs': OnnxFloat(value: List.generate(57, (i) => 0), shape: [1, 57]),
  });
  for (int i = 0; i < outputNames.length; i++) {
    print('Output ${i}: ${outputNames[i]} - ${outputValues[i]}');
  }

  session.dispose();
  env.dispose();
}
