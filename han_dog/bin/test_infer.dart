import 'dart:io';
import 'package:onnx_runtime/onnx_runtime.dart';

void main() async {
  print('Testing ONNX model info...');
  final env = OnnxEnv.create(OrtLoggingLevel.ORT_LOGGING_LEVEL_WARNING, 'Test');
  try {
    final bytes = await File('model/policy_260106.onnx').readAsBytes();
    print('Model loaded: ${bytes.length} bytes');
    final session = InferenceSession.create(env, bytes);
    print('Session created');
    final name = session.getInputName(0);
    print('Input name: $name');
    final info = session.getInputInfo(0).info;
    print('Input dims: ${info.dimensions}');
    session.dispose();
  } catch (e, st) {
    print('Error: $e');
    print('Stack: $st');
  }
  env.dispose();
}
