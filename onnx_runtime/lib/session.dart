import 'dart:ffi';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';

import 'ffi/onnx_api.dart';
import 'ffi/bindings.g.dart';

import 'status.dart';
import 'session_options.dart';
import 'env.dart';
import 'info.dart';
import 'run_options.dart';
import 'value.dart';

/// https://onnxruntime.ai/docs/api/c/struct_ort_1_1_allocator_with_default_options.html?utm_source=chatgpt.com
/// Wrapper around OrtAllocator default instance that is owned by Onnxruntime.
/// 所以不需要 free
final defaultAllocator = () {
  final allocatorPtrPtr = calloc<Pointer<OrtAllocator>>();
  try {
    ortApi.GetAllocatorWithDefaultOptions(allocatorPtrPtr).guard();
    return allocatorPtrPtr.value;
  } finally {
    calloc.free(allocatorPtrPtr);
  }
}();

class InferenceSession implements Finalizable {
  final Pointer<OrtSession> sesPtr;
  // Keeps the environment alive as long as the session exists.
  final OnnxEnv _env; // ignore: unused_field
  InferenceSession._(this.sesPtr, this._env);

  static InferenceSession create(
    OnnxEnv env,
    Uint8List modelBuffer, [
    SessionOptions? options,
  ]) {
    final size = modelBuffer.length;
    final bufferPtr = () {
      final ptr = calloc<Uint8>(size);
      ptr.asTypedList(size).setRange(0, size, modelBuffer);
      return ptr;
    }();

    final optionsPtr = () {
      final optionsPtrPtr = calloc<Pointer<OrtSessionOptions>>();
      try {
        ortApi.CreateSessionOptions(optionsPtrPtr).guard();
        return options?.fill(optionsPtrPtr.value) ?? optionsPtrPtr.value;
      } finally {
        calloc.free(optionsPtrPtr);
      }
    }();

    final sessionPtr = () {
      final sessionPtrPtr = calloc<Pointer<OrtSession>>();
      try {
        ortApi.CreateSessionFromArray(
          env.envPtr,
          bufferPtr.cast(),
          size,
          optionsPtr,
          sessionPtrPtr,
        ).guard();
        return sessionPtrPtr.value;
      } finally {
        calloc.free(sessionPtrPtr);
      }
    }();

    calloc.free(bufferPtr);
    ortApi.ReleaseSessionOptions(optionsPtr);

    final obj = InferenceSession._(sessionPtr, env);

    Gc.session.attach(obj, sessionPtr.cast(), detach: obj);

    return obj;
  }

  void dispose() => Gc.session.detach(this);

  int get inputCounts {
    final countPtr = calloc<Size>();
    try {
      ortApi.SessionGetInputCount(sesPtr, countPtr).guard();
      return countPtr.value;
    } finally {
      calloc.free(countPtr);
    }
  }

  int get outputCounts {
    final countPtr = calloc<Size>();
    try {
      ortApi.SessionGetOutputCount(sesPtr, countPtr).guard();
      return countPtr.value;
    } finally {
      calloc.free(countPtr);
    }
  }

  OnnxInfo getInputInfo(int index) {
    final typeInfo = calloc<Pointer<OrtTypeInfo>>();
    try {
      ortApi.SessionGetInputTypeInfo(sesPtr, index, typeInfo).guard();
      return OnnxInfo.from(typeInfo.value);
    } finally {
      calloc.free(typeInfo);
    }
  }

  OnnxInfo getOutputInfo(int index) {
    final typeInfo = calloc<Pointer<OrtTypeInfo>>();
    try {
      ortApi.SessionGetOutputTypeInfo(sesPtr, index, typeInfo).guard();
      return OnnxInfo.from(typeInfo.value);
    } finally {
      calloc.free(typeInfo);
    }
  }

  String getInputName(int index) {
    final namePtr = calloc<Pointer<Char>>();
    try {
      ortApi.SessionGetInputName(
        sesPtr,
        index,
        defaultAllocator,
        namePtr,
      ).guard();
      return namePtr.value.cast<Utf8>().toDartString();
    } finally {
      calloc.free(namePtr);
    }
  }

  String getOutputName(int index) {
    final namePtr = calloc<Pointer<Char>>();
    try {
      ortApi.SessionGetOutputName(
        sesPtr,
        index,
        defaultAllocator,
        namePtr,
      ).guard();
      return namePtr.value.cast<Utf8>().toDartString();
    } finally {
      calloc.free(namePtr);
    }
  }

  late final run = () {
    final inputLen = inputCounts;
    final outputLen = outputCounts;

    final outputNames = List.generate(outputLen, (i) => getOutputName(i));

    final inputInfos = List.generate(inputLen, (i) => getInputInfo(i));

    final outputInfos = List.generate(outputLen, (i) => getOutputInfo(i));

    return (Map<String, OnnxValue> inputs, [RunOptions? runOptions]) {
      return (
        outputNames,
        runVerbose(inputs, outputNames, inputInfos, outputInfos, runOptions),
      );
    };
  }();

  List<OnnxValue> runVerbose(
    Map<String, OnnxValue> inputs,
    List<String> outputNames,
    List<OnnxInfo> inputInfos,
    List<OnnxInfo> outputInfos, [
    RunOptions? runOptions,
  ]) {
    final runOptionsPtr = () {
      final optionsPtrPtr = calloc<Pointer<OrtRunOptions>>();
      try {
        ortApi.CreateRunOptions(optionsPtrPtr).guard();
        return runOptions?.fill(optionsPtrPtr.value) ?? optionsPtrPtr.value;
      } finally {
        calloc.free(optionsPtrPtr);
      }
    }();

    final inputLen = inputs.length;
    final inputNames = inputs.keys.toList();
    final inputNamesPtrPtr = () {
      final namesPtr = calloc<Pointer<Char>>(inputLen);
      for (int i = 0; i < inputLen; i++) {
        namesPtr[i] = inputNames[i].toNativeUtf8().cast();
      }
      return namesPtr;
    }();

    final outputLen = outputNames.length;
    final outputNamesPtr = () {
      final namesPtr = calloc<Pointer<Char>>(outputLen);
      for (int i = 0; i < outputLen; i++) {
        namesPtr[i] = outputNames[i].toNativeUtf8().cast();
      }
      return namesPtr;
    }();

    final inputValuesPtr = () {
      final valuesPtr = calloc<Pointer<OrtValue>>(inputLen);
      final tempPtr = calloc<Pointer<OrtValue>>();
      for (int i = 0; i < inputLen; i++) {
        final value = inputs[inputNames[i]]!;
        final shapeLen = value.shape.length;
        final shape = () {
          final shapePtr = calloc<Int64>(shapeLen);
          for (int j = 0; j < shapeLen; j++) {
            shapePtr[j] = value.shape[j];
          }
          return shapePtr;
        }();

        final type = inputInfos[i].info.tensorElementType;

        ortApi.CreateTensorAsOrtValue(
          defaultAllocator,
          shape,
          shapeLen,
          type.value,
          tempPtr,
        );

        valuesPtr[i] = value.fill(tempPtr.value, type);
      }
      calloc.free(tempPtr);
      return valuesPtr;
    }();

    final outputValuesPtr = calloc<Pointer<OrtValue>>(outputLen);

    ortApi.Run(
      sesPtr,
      runOptionsPtr,
      inputNamesPtrPtr,
      inputValuesPtr,
      inputLen,
      outputNamesPtr,
      outputLen,
      outputValuesPtr,
    ).guard();

    final List<OnnxValue> outputValues = List.generate(
      outputLen,
      (i) => OnnxValue.from(
        outputValuesPtr[i],
        outputInfos[i].info.tensorElementType,
        outputInfos[i].info.dimensions,
      ),
    );

    ortApi.ReleaseRunOptions(runOptionsPtr);
    {
      for (int i = 0; i < inputLen; i++) {
        calloc.free(inputNamesPtrPtr[i]);
      }
      calloc.free(inputNamesPtrPtr);
    }

    {
      for (int i = 0; i < outputLen; i++) {
        calloc.free(outputNamesPtr[i]);
      }
      calloc.free(outputNamesPtr);
    }

    {
      for (int i = 0; i < inputLen; i++) {
        ortApi.ReleaseValue(inputValuesPtr[i]);
      }
      calloc.free(inputValuesPtr);
    }

    {
      for (int i = 0; i < outputLen; i++) {
        ortApi.ReleaseValue(outputValuesPtr[i]);
      }
      calloc.free(outputValuesPtr);
    }

    return outputValues;
  }
}
