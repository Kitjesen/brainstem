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

    // 获取张量形状元素总数
    final totalElementCount = () {
      final elementCountPtr = calloc<Size>();
      try {
        ortApi.GetTensorShapeElementCount(typeInfoPtr, elementCountPtr).guard();
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
