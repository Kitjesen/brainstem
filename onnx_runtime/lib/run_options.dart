import 'dart:ffi';
import 'package:ffi/ffi.dart';

import 'ffi/onnx_api.dart';
import 'ffi/bindings.g.dart';
import 'status.dart';

class RunOptions {
  /// Run log verbosity level
  final int? runLogVerbosityLevel;

  /// Run log severity level (refer to OrtLoggingLevel)
  final OrtLoggingLevel? runLogSeverityLevel;

  /// Run tag identifier
  final String? runTag;

  const RunOptions({
    this.runLogVerbosityLevel,
    this.runLogSeverityLevel,
    this.runTag,
  });

  Pointer<OrtRunOptions> fill(Pointer<OrtRunOptions> optionsPtr) {
    if (optionsPtr == nullptr) return optionsPtr;

    // Set run log verbosity level
    if (runLogVerbosityLevel != null) {
      ortApi.RunOptionsSetRunLogVerbosityLevel(
        optionsPtr,
        runLogVerbosityLevel!,
      ).guard();
    }

    // Set run log severity level
    if (runLogSeverityLevel != null) {
      ortApi.RunOptionsSetRunLogSeverityLevel(
        optionsPtr,
        runLogSeverityLevel!.value,
      ).guard();
    }

    // Set run tag
    if (runTag != null) {
      final runTagPtr = runTag!.toNativeUtf8();
      try {
        ortApi.RunOptionsSetRunTag(optionsPtr, runTagPtr.cast()).guard();
      } finally {
        malloc.free(runTagPtr);
      }
    }

    return optionsPtr;
  }
}
