import 'dart:io';

import 'package:onnx_runtime/onnx_runtime.dart';

void main(List<String> args) async {
  if (args.length != 2) {
    stderr.writeln(
      'Usage: dart run model_smoke_generic.dart MODEL_PATH INPUT_DIM',
    );
    exitCode = 2;
    return;
  }

  final modelPath = args[0];
  final inputDimension = int.parse(args[1]);
  final env = OnnxEnv.create(
    OrtLoggingLevel.ORT_LOGGING_LEVEL_WARNING,
    'generic_model_smoke',
  );
  try {
    final bytes = await File(modelPath).readAsBytes();
    final session = InferenceSession.create(env, bytes);
    try {
      final inputName = session.getInputName(0);
      final inputDimensions = session.getInputInfo(0).info.dimensions;
      final outputDimensions = session.getOutputInfo(0).info.dimensions;
      if (inputDimensions.join(',') != '1,$inputDimension') {
        throw StateError('Unexpected input: $inputName $inputDimensions');
      }
      if (outputDimensions.join(',') != '1,16') {
        throw StateError('Unexpected output: $outputDimensions');
      }

      final (_, values) = session.run({
        inputName: OnnxFloat(
          value: List.filled(inputDimension, 0.0),
          shape: [1, inputDimension],
        ),
      });
      final output = values.single as OnnxFloat;
      if (output.value.length != 16 ||
          output.value.any((value) => !value.isFinite)) {
        throw StateError('Invalid inference output: ${output.value}');
      }
      print('model smoke OK');
      print('input=$inputName $inputDimensions output=$outputDimensions');
      print('zero_input_output=${output.value}');
    } finally {
      session.dispose();
    }
  } finally {
    env.dispose();
  }
}
