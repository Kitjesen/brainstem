import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'ffi/bindings.g.dart';
import 'ffi/onnx_api.dart';
import 'status.dart';

class OnnxInfo {
  final ONNXType type;
  final OnnxTensorInfo info;

  const OnnxInfo({required this.type, required this.info});

  static OnnxInfo from(Pointer<OrtTypeInfo> typeInfoPtr) {
    final typePtr = calloc<UnsignedInt>();
    try {
      ortApi.GetOnnxTypeFromTypeInfo(typeInfoPtr, typePtr).guard();
      final type = ONNXType.fromValue(typePtr.value);
      return OnnxInfo(
        type: type,
        info: OnnxTensorInfo.fromTypeInfo(typeInfoPtr),
      );
    } finally {
      calloc.free(typePtr);
    }
  }

  @override
  String toString() {
    return 'OnnxInfo(type: $type, info: $info)';
  }
}

class OnnxTensorInfo {
  final ONNXTensorElementDataType tensorElementType;
  final int dimensionsCount;
  final List<int> dimensions;
  final List<String> symbolicDimensions;
  final int totalElementCount;

  const OnnxTensorInfo({
    required this.tensorElementType,
    required this.dimensionsCount,
    required this.dimensions,
    required this.symbolicDimensions,
    required this.totalElementCount,
  });

  static OnnxTensorInfo fromTypeInfo(Pointer<OrtTypeInfo> typeInfoPtr) {
    final tensorTypeInfoPtr = calloc<Pointer<OrtTensorTypeAndShapeInfo>>();
    try {
      ortApi.CastTypeInfoToTensorInfo(typeInfoPtr, tensorTypeInfoPtr).guard();
      return from(tensorTypeInfoPtr.value);
    } finally {
      calloc.free(tensorTypeInfoPtr);
    }
  }

  /// Concrete type and shape of a tensor OrtValue produced by OrtRun.
  ///
  /// Session input/output info keeps symbolic dims such as `[-1, 16]`.
  /// The value itself has the shape that was actually computed, for
  /// example `[1, 16]`. The caller still releases the OrtValue; the type
  /// info allocated here is released before this returns.
  static OnnxTensorInfo fromOrtValue(Pointer<OrtValue> value) {
    final infoPtr = calloc<Pointer<OrtTensorTypeAndShapeInfo>>();
    try {
      ortApi.GetTensorTypeAndShape(value, infoPtr).guard();
      final Pointer<OrtTensorTypeAndShapeInfo> typeInfo = infoPtr.value;
      try {
        return from(typeInfo);
      } finally {
        ortApi.ReleaseTensorTypeAndShapeInfo(typeInfo);
      }
    } finally {
      calloc.free(infoPtr);
    }
  }

  static OnnxTensorInfo from(Pointer<OrtTensorTypeAndShapeInfo> typeInfoPtr) {
    // 获取张量元素类型
    final tensorType = () {
      final tensorTypePtr = calloc<UnsignedInt>();
      try {
        ortApi.GetTensorElementType(typeInfoPtr, tensorTypePtr).guard();
        return ONNXTensorElementDataType.fromValue(tensorTypePtr.value);
      } finally {
        calloc.free(tensorTypePtr);
      }
    }();

    // 获取维度数量
    final dimensionsCount = () {
      final dimensionsCountPtr = calloc<Size>();
      try {
        ortApi.GetDimensionsCount(typeInfoPtr, dimensionsCountPtr).guard();
        return dimensionsCountPtr.value;
      } finally {
        calloc.free(dimensionsCountPtr);
      }
    }();

    // 获取维度值数组
    final List<int> dimensions = dimensionsCount > 0
        ? () {
            final dimValuesPtr = calloc<Int64>(dimensionsCount);
            try {
              ortApi.GetDimensions(
                typeInfoPtr,
                dimValuesPtr,
                dimensionsCount,
              ).guard();
              return List.generate(dimensionsCount, (i) => dimValuesPtr[i]);
            } finally {
              calloc.free(dimValuesPtr);
            }
          }()
        : [];

    // 获取符号维度名称
    final List<String> symbolicDimensions = dimensionsCount > 0
        ? () {
            final dimParamsPtr = calloc<Pointer<Char>>(dimensionsCount);
            try {
              ortApi.GetSymbolicDimensions(
                typeInfoPtr,
                dimParamsPtr,
                dimensionsCount,
              ).guard();
              final result = <String>[];
              for (int i = 0; i < dimensionsCount; i++) {
                result.add(
                  dimParamsPtr[i] != nullptr
                      ? dimParamsPtr[i].cast<Utf8>().toDartString()
                      : '',
                );
              }
              return result;
            } finally {
              calloc.free(dimParamsPtr);
            }
          }()
        : [];

    // Dynamic dims are reported as <= 0 (a symbolic batch is -1).
    // GetTensorShapeElementCount multiplies those with SafeInt<size_t>
    // and fails with ORT_FAIL / SafeIntOnOverflow instead of the
    // documented -1, which aborts the whole session. Skip the call and
    // return a safe count: -1 if any dim is symbolic, otherwise the
    // product (0 when a dim is empty).
    final int totalElementCount = dimensions.any((int dim) => dim <= 0)
        ? _safeElementCount(dimensions)
        : () {
            final elementCountPtr = calloc<Size>();
            try {
              ortApi.GetTensorShapeElementCount(
                typeInfoPtr,
                elementCountPtr,
              ).guard();
              return elementCountPtr.value;
            } finally {
              calloc.free(elementCountPtr);
            }
          }();

    return OnnxTensorInfo(
      tensorElementType: tensorType,
      dimensionsCount: dimensionsCount,
      dimensions: dimensions,
      symbolicDimensions: symbolicDimensions,
      totalElementCount: totalElementCount,
    );
  }

  bool get isScalar => dimensionsCount == 0;
  bool get isVector => dimensionsCount == 1;
  bool get isMatrix => dimensionsCount == 2;

  @override
  String toString() {
    return 'OnnxTensorInfo('
        'tensorElementType: $tensorElementType, '
        'dimensions: $dimensions, '
        'dimensionsCount: $dimensionsCount, '
        'totalElementCount: $totalElementCount'
        ', symbolicDimensions: $symbolicDimensions'
        ')';
  }
}

/// Element count for a shape that must not be passed to
/// GetTensorShapeElementCount.
///
/// A negative dimension is symbolic, so the count is unknown (`-1`).
/// Zero dimensions are an empty tensor and the product is 0. A scalar
/// (no dimensions) is 1.
int _safeElementCount(List<int> dimensions) {
  var count = 1;
  for (final int dim in dimensions) {
    if (dim < 0) return -1;
    count *= dim;
  }
  return count;
}
