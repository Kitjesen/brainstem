import 'dart:ffi';
import 'package:ffi/ffi.dart';

import 'ffi/onnx_api.dart';
import 'ffi/bindings.g.dart';

class OnnxStatus {
  final String message;
  final OrtErrorCode code;
  OnnxStatus({required this.message, required this.code});

  static OnnxStatus fromPointer(Pointer<OrtStatus> statusPtr) {
    final code = ortApi.GetErrorCode(statusPtr);
    final message = ortApi.GetErrorMessage(
      statusPtr,
    ).cast<Utf8>().toDartString();
    return OnnxStatus(message: message, code: OrtErrorCode.fromValue(code));
  }

  @override
  String toString() {
    return 'status($code): $message';
  }
}

extension OrtStatusExt on Pointer<OrtStatus> {
  void guard() {
    final status = toStatus();
    if (status == null) return;
    throw status;
  }

  OnnxStatus? toStatus() {
    if (this == nullptr) return null;
    final status = OnnxStatus.fromPointer(this);
    // https://onnxruntime.ai/docs/api/c/struct_ort_api.html?utm_source=chatgpt.com#a22085f699a2d1adb52f809383f475ed1
    // If no error, nullptr will be returned. If there is an error, a pointer to an OrtStatus that contains error details will be returned. Use OrtApi::ReleaseStatus to free this pointer.
    ortApi.ReleaseStatus(this);
    return status;
  }
}
