import 'dart:io';

import 'package:logging/logging.dart';
import 'package:onnx_runtime/onnx_runtime.dart';

final _log = Logger('han_dog_brain.model_info');

/// 根据 ONNX 输入观测维度推断历史帧数。
///
/// 例如标准 57 维观测下：
/// - 57   -> 1
/// - 285  -> 5
/// - 114  -> 2
int? inferHistorySizeFromObsDim(int obsDim, int tensorSize) {
  if (obsDim <= 0 || tensorSize <= 0) {
    return null;
  }
  if (obsDim % tensorSize != 0) {
    return null;
  }
  final historySize = obsDim ~/ tensorSize;
  return historySize >= 1 ? historySize : null;
}

/// 从模型文件首个输入张量形状推断历史帧数。
///
/// 当输入维度为动态形状、不可整除或模型无法读取时返回 `null`。
Future<int?> inferHistorySizeFromModel({
  required String modelPath,
  required int tensorSize,
}) async {
  final env = OnnxEnv.create(
    OrtLoggingLevel.ORT_LOGGING_LEVEL_WARNING,
    'ModelInfo',
  );
  InferenceSession? session;
  try {
    final modelBytes = await File(modelPath).readAsBytes();
    session = InferenceSession.create(env, modelBytes);
    final inputInfo = session.getInputInfo(0).info;
    if (inputInfo.dimensions.length < 2) {
      return null;
    }
    final obsDim = inputInfo.dimensions[1];
    if (obsDim == -1) {
      return null;
    }
    return inferHistorySizeFromObsDim(obsDim, tensorSize);
  } catch (e, st) {
    _log.warning('Failed to infer history size from $modelPath', e, st);
    return null;
  } finally {
    session?.dispose();
    env.dispose();
  }
}
