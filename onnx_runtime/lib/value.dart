import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'status.dart';
import 'ffi/onnx_api.dart';
import 'ffi/bindings.g.dart';
import 'info.dart';

sealed class OnnxValue {
  final List<int> shape;

  const OnnxValue({required this.shape});

  Pointer<OrtValue> fill(
    Pointer<OrtValue> valuePtr,
    ONNXTensorElementDataType type,
  );

  int get elementCount => _elementCount(shape);

  factory OnnxValue.from(
    Pointer<OrtValue> valuePtr,
    ONNXTensorElementDataType type,
    List<int> shape,
  ) {
    // Callers historically passed the model's declared shape. That is
    // still symbolic ([-1, 16]) for a dynamic batch, and folding it
    // produces a negative length. Read the OrtValue when any dim is
    // not a concrete positive size.
    final List<int> resolved = shape.any((int dim) => dim <= 0)
        ? OnnxTensorInfo.fromOrtValue(valuePtr).dimensions
        : shape;
    final int length = _elementCount(resolved);
    if (length < 0) {
      throw ArgumentError(
        'Cannot copy tensor data with a dynamic shape $resolved',
      );
    }
    switch (type) {
      case ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64:
      case ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_INT32:
      case ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_INT16:
      case ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_INT8:
      case ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_UINT64:
      case ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_UINT32:
      case ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_UINT16:
      case ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_UINT8:
        return OnnxInt.from(valuePtr, type, resolved, length);
      case ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT:
      case ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_DOUBLE:
        return OnnxFloat.from(valuePtr, type, resolved, length);
      default:
        throw ArgumentError('Unsupported type: $type');
    }
  }
}

class OnnxInt extends OnnxValue {
  final List<int> value;

  const OnnxInt({required this.value, required super.shape});

  @override
  Pointer<OrtValue> fill(
    Pointer<OrtValue> valuePtr,
    ONNXTensorElementDataType type,
  ) {
    final bufferView = valuePtr.asIntList(value.length, type);
    bufferView.setRange(0, value.length, value);
    return valuePtr;
  }

  static OnnxInt from(
    Pointer<OrtValue> valuePtr,
    ONNXTensorElementDataType type,
    List<int> shape,
    int length,
  ) {
    final bufferView = valuePtr.asIntList(length, type);
    return OnnxInt(value: List.from(bufferView), shape: shape);
  }

  @override
  String toString() => 'OnnxInt(value: $value, shape: $shape)';
}

class OnnxFloat extends OnnxValue {
  final List<double> value;

  const OnnxFloat({required this.value, required super.shape});

  @override
  Pointer<OrtValue> fill(
    Pointer<OrtValue> valuePtr,
    ONNXTensorElementDataType type,
  ) {
    final bufferView = valuePtr.asDoubleList(value.length, type);
    bufferView.setRange(0, value.length, value);
    return valuePtr;
  }

  static OnnxFloat from(
    Pointer<OrtValue> valuePtr,
    ONNXTensorElementDataType type,
    List<int> shape,
    int length,
  ) {
    final bufferView = valuePtr.asDoubleList(length, type);
    return OnnxFloat(value: List.from(bufferView), shape: shape);
  }

  @override
  String toString() => 'OnnxFloat(value: $value, shape: $shape)';
}

int _elementCount(List<int> shape) {
  var count = 1;
  for (final int dim in shape) {
    if (dim < 0) return -1;
    count *= dim;
  }
  return count;
}

extension on Pointer<OrtValue> {
  List<int> asIntList(int length, ONNXTensorElementDataType type) {
    final valuePtr = this;
    switch (type) {
      case ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64:
        final bufferPtr = calloc<Pointer<Int64>>();
        try {
          ortApi.GetTensorMutableData(valuePtr, bufferPtr.cast()).guard();
          return bufferPtr.value.asTypedList(length);
        } finally {
          calloc.free(bufferPtr);
        }
      case ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_INT32:
        final bufferPtr = calloc<Pointer<Int32>>();
        try {
          ortApi.GetTensorMutableData(valuePtr, bufferPtr.cast()).guard();
          return bufferPtr.value.asTypedList(length);
        } finally {
          calloc.free(bufferPtr);
        }
      case ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_INT16:
        final bufferPtr = calloc<Pointer<Int16>>();
        try {
          ortApi.GetTensorMutableData(valuePtr, bufferPtr.cast()).guard();
          return bufferPtr.value.asTypedList(length);
        } finally {
          calloc.free(bufferPtr);
        }
      case ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_INT8:
        final bufferPtr = calloc<Pointer<Int8>>();
        try {
          ortApi.GetTensorMutableData(valuePtr, bufferPtr.cast()).guard();
          return bufferPtr.value.asTypedList(length);
        } finally {
          calloc.free(bufferPtr);
        }
      case ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_UINT64:
        final bufferPtr = calloc<Pointer<Uint64>>();
        try {
          ortApi.GetTensorMutableData(valuePtr, bufferPtr.cast()).guard();
          return bufferPtr.value.asTypedList(length);
        } finally {
          calloc.free(bufferPtr);
        }
      case ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_UINT32:
        final bufferPtr = calloc<Pointer<Uint32>>();
        try {
          ortApi.GetTensorMutableData(valuePtr, bufferPtr.cast()).guard();
          return bufferPtr.value.asTypedList(length);
        } finally {
          calloc.free(bufferPtr);
        }
      case ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_UINT16:
        final bufferPtr = calloc<Pointer<Uint16>>();
        try {
          ortApi.GetTensorMutableData(valuePtr, bufferPtr.cast()).guard();
          return bufferPtr.value.asTypedList(length);
        } finally {
          calloc.free(bufferPtr);
        }
      case ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_UINT8:
        final bufferPtr = calloc<Pointer<Uint8>>();
        try {
          ortApi.GetTensorMutableData(valuePtr, bufferPtr.cast()).guard();
          return bufferPtr.value.asTypedList(length);
        } finally {
          calloc.free(bufferPtr);
        }
      default:
        throw ArgumentError('Unsupported type: $type');
    }
  }

  List<double> asDoubleList(int length, ONNXTensorElementDataType type) {
    final valuePtr = this;
    switch (type) {
      case ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT:
        final bufferPtr = calloc<Pointer<Float>>();
        try {
          ortApi.GetTensorMutableData(valuePtr, bufferPtr.cast()).guard();
          return bufferPtr.value.asTypedList(length);
        } finally {
          calloc.free(bufferPtr);
        }
      case ONNXTensorElementDataType.ONNX_TENSOR_ELEMENT_DATA_TYPE_DOUBLE:
        final bufferPtr = calloc<Pointer<Double>>();
        try {
          ortApi.GetTensorMutableData(valuePtr, bufferPtr.cast()).guard();
          return bufferPtr.value.asTypedList(length);
        } finally {
          calloc.free(bufferPtr);
        }
      default:
        throw ArgumentError('Unsupported type: $type');
    }
  }
}
