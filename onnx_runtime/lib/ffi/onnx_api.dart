// ignore_for_file: always_specify_types
// ignore_for_file: camel_case_types
// ignore_for_file: non_constant_identifier_names

import 'dart:ffi' as ffi;

import 'bindings.g.dart';
import 'api.dart';

part 'gc.dart';

final _apiBase = api.OrtGetApiBase().ref;
final _getApi = _apiBase.GetApi.asFunction<ffi.Pointer<OrtApi> Function(int)>();
final _api = _getApi(ORT_API_VERSION).ref;
final ortApi = OnnxApi(_api);

class OnnxApi {
  final OrtApi _api;
  OnnxApi(this._api);

  ffi.Pointer<OrtStatus> CreateStatus(int code, ffi.Pointer<ffi.Char> msg) {
    return _api.CreateStatus.asFunction<
      ffi.Pointer<OrtStatus> Function(int code, ffi.Pointer<ffi.Char> msg)
    >()(code, msg);
  }

  int GetErrorCode(ffi.Pointer<OrtStatus> status) {
    return _api.GetErrorCode.asFunction<
      int Function(ffi.Pointer<OrtStatus> status)
    >()(status);
  }

  ffi.Pointer<ffi.Char> GetErrorMessage(ffi.Pointer<OrtStatus> status) {
    return _api.GetErrorMessage.asFunction<
      ffi.Pointer<ffi.Char> Function(ffi.Pointer<OrtStatus> status)
    >()(status);
  }

  void ReleaseStatus(ffi.Pointer<OrtStatus> input) {
    _api.ReleaseStatus.asFunction<
      void Function(ffi.Pointer<OrtStatus> input)
    >()(input);
  }

  // Environment operations
  ffi.Pointer<OrtStatus> CreateEnv(
    int log_severity_level,
    ffi.Pointer<ffi.Char> logid,
    ffi.Pointer<ffi.Pointer<OrtEnv>> out,
  ) {
    return _api.CreateEnv.asFunction<
      ffi.Pointer<OrtStatus> Function(
        int log_severity_level,
        ffi.Pointer<ffi.Char> logid,
        ffi.Pointer<ffi.Pointer<OrtEnv>> out,
      )
    >()(log_severity_level, logid, out);
  }

  ffi.Pointer<OrtStatus> CreateEnvWithCustomLogger(
    OrtLoggingFunction logging_function,
    ffi.Pointer<ffi.Void> logger_param,
    int log_severity_level,
    ffi.Pointer<ffi.Char> logid,
    ffi.Pointer<ffi.Pointer<OrtEnv>> out,
  ) {
    return _api.CreateEnvWithCustomLogger.asFunction<
      ffi.Pointer<OrtStatus> Function(
        OrtLoggingFunction logging_function,
        ffi.Pointer<ffi.Void> logger_param,
        int log_severity_level,
        ffi.Pointer<ffi.Char> logid,
        ffi.Pointer<ffi.Pointer<OrtEnv>> out,
      )
    >()(logging_function, logger_param, log_severity_level, logid, out);
  }

  ffi.Pointer<OrtStatus> EnableTelemetryEvents(ffi.Pointer<OrtEnv> env) {
    return _api.EnableTelemetryEvents.asFunction<
      ffi.Pointer<OrtStatus> Function(ffi.Pointer<OrtEnv> env)
    >()(env);
  }

  ffi.Pointer<OrtStatus> DisableTelemetryEvents(ffi.Pointer<OrtEnv> env) {
    return _api.DisableTelemetryEvents.asFunction<
      ffi.Pointer<OrtStatus> Function(ffi.Pointer<OrtEnv> env)
    >()(env);
  }

  void ReleaseEnv(ffi.Pointer<OrtEnv> input) {
    _api.ReleaseEnv.asFunction<void Function(ffi.Pointer<OrtEnv> input)>()(
      input,
    );
  }

  // Session operations
  // ffi.Pointer<OrtStatus> CreateSession(
  //   ffi.Pointer<OrtEnv> env,
  //   ffi.Pointer<ffi.WChar> model_path,
  //   ffi.Pointer<OrtSessionOptions> options,
  //   ffi.Pointer<ffi.Pointer<OrtSession>> out,
  // ) {
  //   return _api.CreateSession.asFunction<
  //     ffi.Pointer<OrtStatus> Function(
  //       ffi.Pointer<OrtEnv> env,
  //       ffi.Pointer<ffi.WChar> model_path,
  //       ffi.Pointer<OrtSessionOptions> options,
  //       ffi.Pointer<ffi.Pointer<OrtSession>> out,
  //     )
  //   >()(env, model_path, options, out);
  // }

  ffi.Pointer<OrtStatus> CreateSessionFromArray(
    ffi.Pointer<OrtEnv> env,
    ffi.Pointer<ffi.Void> model_data,
    int model_data_length,
    ffi.Pointer<OrtSessionOptions> options,
    ffi.Pointer<ffi.Pointer<OrtSession>> out,
  ) {
    return _api.CreateSessionFromArray.asFunction<
      ffi.Pointer<OrtStatus> Function(
        ffi.Pointer<OrtEnv> env,
        ffi.Pointer<ffi.Void> model_data,
        int model_data_length,
        ffi.Pointer<OrtSessionOptions> options,
        ffi.Pointer<ffi.Pointer<OrtSession>> out,
      )
    >()(env, model_data, model_data_length, options, out);
  }

  ffi.Pointer<OrtStatus> Run(
    ffi.Pointer<OrtSession> session,
    ffi.Pointer<OrtRunOptions> run_options,
    ffi.Pointer<ffi.Pointer<ffi.Char>> input_names,
    ffi.Pointer<ffi.Pointer<OrtValue>> inputs,
    int input_len,
    ffi.Pointer<ffi.Pointer<ffi.Char>> output_names,
    int output_names_len,
    ffi.Pointer<ffi.Pointer<OrtValue>> outputs,
  ) {
    return _api.Run.asFunction<
      ffi.Pointer<OrtStatus> Function(
        ffi.Pointer<OrtSession> session,
        ffi.Pointer<OrtRunOptions> run_options,
        ffi.Pointer<ffi.Pointer<ffi.Char>> input_names,
        ffi.Pointer<ffi.Pointer<OrtValue>> inputs,
        int input_len,
        ffi.Pointer<ffi.Pointer<ffi.Char>> output_names,
        int output_names_len,
        ffi.Pointer<ffi.Pointer<OrtValue>> outputs,
      )
    >()(
      session,
      run_options,
      input_names,
      inputs,
      input_len,
      output_names,
      output_names_len,
      outputs,
    );
  }

  void ReleaseSession(ffi.Pointer<OrtSession> input) {
    _api.ReleaseSession.asFunction<
      void Function(ffi.Pointer<OrtSession> input)
    >()(input);
  }

  // Session Options operations
  ffi.Pointer<OrtStatus> CreateSessionOptions(
    ffi.Pointer<ffi.Pointer<OrtSessionOptions>> options,
  ) {
    return _api.CreateSessionOptions.asFunction<
      ffi.Pointer<OrtStatus> Function(
        ffi.Pointer<ffi.Pointer<OrtSessionOptions>> options,
      )
    >()(options);
  }

  // ffi.Pointer<OrtStatus> SetOptimizedModelFilePath(
  //   ffi.Pointer<OrtSessionOptions> options,
  //   ffi.Pointer<ffi.WChar> optimized_model_filepath,
  // ) {
  //   return _api.SetOptimizedModelFilePath.asFunction<
  //     ffi.Pointer<OrtStatus> Function(
  //       ffi.Pointer<OrtSessionOptions> options,
  //       ffi.Pointer<ffi.WChar> optimized_model_filepath,
  //     )
  //   >()(options, optimized_model_filepath);
  // }

  ffi.Pointer<OrtStatus> CloneSessionOptions(
    ffi.Pointer<OrtSessionOptions> in_options,
    ffi.Pointer<ffi.Pointer<OrtSessionOptions>> out_options,
  ) {
    return _api.CloneSessionOptions.asFunction<
      ffi.Pointer<OrtStatus> Function(
        ffi.Pointer<OrtSessionOptions> in_options,
        ffi.Pointer<ffi.Pointer<OrtSessionOptions>> out_options,
      )
    >()(in_options, out_options);
  }

  void ReleaseSessionOptions(ffi.Pointer<OrtSessionOptions> input) {
    _api.ReleaseSessionOptions.asFunction<
      void Function(ffi.Pointer<OrtSessionOptions> input)
    >()(input);
  }

  // Additional Session Options operations
  ffi.Pointer<OrtStatus> SetSessionExecutionMode(
    ffi.Pointer<OrtSessionOptions> options,
    int execution_mode,
  ) {
    return _api.SetSessionExecutionMode.asFunction<
      ffi.Pointer<OrtStatus> Function(
        ffi.Pointer<OrtSessionOptions> options,
        int execution_mode,
      )
    >()(options, execution_mode);
  }

  ffi.Pointer<OrtStatus> SetSessionGraphOptimizationLevel(
    ffi.Pointer<OrtSessionOptions> options,
    int graph_optimization_level,
  ) {
    return _api.SetSessionGraphOptimizationLevel.asFunction<
      ffi.Pointer<OrtStatus> Function(
        ffi.Pointer<OrtSessionOptions> options,
        int graph_optimization_level,
      )
    >()(options, graph_optimization_level);
  }

  ffi.Pointer<OrtStatus> SetIntraOpNumThreads(
    ffi.Pointer<OrtSessionOptions> options,
    int intra_op_num_threads,
  ) {
    return _api.SetIntraOpNumThreads.asFunction<
      ffi.Pointer<OrtStatus> Function(
        ffi.Pointer<OrtSessionOptions> options,
        int intra_op_num_threads,
      )
    >()(options, intra_op_num_threads);
  }

  ffi.Pointer<OrtStatus> SetInterOpNumThreads(
    ffi.Pointer<OrtSessionOptions> options,
    int inter_op_num_threads,
  ) {
    return _api.SetInterOpNumThreads.asFunction<
      ffi.Pointer<OrtStatus> Function(
        ffi.Pointer<OrtSessionOptions> options,
        int inter_op_num_threads,
      )
    >()(options, inter_op_num_threads);
  }

  // ffi.Pointer<OrtStatus> EnableProfiling(
  //   ffi.Pointer<OrtSessionOptions> options,
  //   ffi.Pointer<ffi.WChar> profile_file_prefix,
  // ) {
  //   return _api.EnableProfiling.asFunction<
  //     ffi.Pointer<OrtStatus> Function(
  //       ffi.Pointer<OrtSessionOptions> options,
  //       ffi.Pointer<ffi.WChar> profile_file_prefix,
  //     )
  //   >()(options, profile_file_prefix);
  // }

  ffi.Pointer<OrtStatus> DisableProfiling(
    ffi.Pointer<OrtSessionOptions> options,
  ) {
    return _api.DisableProfiling.asFunction<
      ffi.Pointer<OrtStatus> Function(ffi.Pointer<OrtSessionOptions> options)
    >()(options);
  }

  ffi.Pointer<OrtStatus> EnableMemPattern(
    ffi.Pointer<OrtSessionOptions> options,
  ) {
    return _api.EnableMemPattern.asFunction<
      ffi.Pointer<OrtStatus> Function(ffi.Pointer<OrtSessionOptions> options)
    >()(options);
  }

  ffi.Pointer<OrtStatus> DisableMemPattern(
    ffi.Pointer<OrtSessionOptions> options,
  ) {
    return _api.DisableMemPattern.asFunction<
      ffi.Pointer<OrtStatus> Function(ffi.Pointer<OrtSessionOptions> options)
    >()(options);
  }

  ffi.Pointer<OrtStatus> EnableCpuMemArena(
    ffi.Pointer<OrtSessionOptions> options,
  ) {
    return _api.EnableCpuMemArena.asFunction<
      ffi.Pointer<OrtStatus> Function(ffi.Pointer<OrtSessionOptions> options)
    >()(options);
  }

  ffi.Pointer<OrtStatus> DisableCpuMemArena(
    ffi.Pointer<OrtSessionOptions> options,
  ) {
    return _api.DisableCpuMemArena.asFunction<
      ffi.Pointer<OrtStatus> Function(ffi.Pointer<OrtSessionOptions> options)
    >()(options);
  }

  ffi.Pointer<OrtStatus> SetSessionLogId(
    ffi.Pointer<OrtSessionOptions> options,
    ffi.Pointer<ffi.Char> logid,
  ) {
    return _api.SetSessionLogId.asFunction<
      ffi.Pointer<OrtStatus> Function(
        ffi.Pointer<OrtSessionOptions> options,
        ffi.Pointer<ffi.Char> logid,
      )
    >()(options, logid);
  }

  ffi.Pointer<OrtStatus> SetSessionLogVerbosityLevel(
    ffi.Pointer<OrtSessionOptions> options,
    int session_log_verbosity_level,
  ) {
    return _api.SetSessionLogVerbosityLevel.asFunction<
      ffi.Pointer<OrtStatus> Function(
        ffi.Pointer<OrtSessionOptions> options,
        int session_log_verbosity_level,
      )
    >()(options, session_log_verbosity_level);
  }

  ffi.Pointer<OrtStatus> AddSessionConfigEntry(
    ffi.Pointer<OrtSessionOptions> options,
    ffi.Pointer<ffi.Char> config_key,
    ffi.Pointer<ffi.Char> config_value,
  ) {
    return _api.AddSessionConfigEntry.asFunction<
      ffi.Pointer<OrtStatus> Function(
        ffi.Pointer<OrtSessionOptions> options,
        ffi.Pointer<ffi.Char> config_key,
        ffi.Pointer<ffi.Char> config_value,
      )
    >()(options, config_key, config_value);
  }

  ffi.Pointer<OrtStatus> SetSessionLogSeverityLevel(
    ffi.Pointer<OrtSessionOptions> options,
    int session_log_severity_level,
  ) {
    return _api.SetSessionLogSeverityLevel.asFunction<
      ffi.Pointer<OrtStatus> Function(
        ffi.Pointer<OrtSessionOptions> options,
        int session_log_severity_level,
      )
    >()(options, session_log_severity_level);
  }

  ffi.Pointer<OrtStatus> AddFreeDimensionOverride(
    ffi.Pointer<OrtSessionOptions> options,
    ffi.Pointer<ffi.Char> dim_denotation,
    int dim_value,
  ) {
    return _api.AddFreeDimensionOverride.asFunction<
      ffi.Pointer<OrtStatus> Function(
        ffi.Pointer<OrtSessionOptions> options,
        ffi.Pointer<ffi.Char> dim_denotation,
        int dim_value,
      )
    >()(options, dim_denotation, dim_value);
  }

  // Run Options operations
  ffi.Pointer<OrtStatus> CreateRunOptions(
    ffi.Pointer<ffi.Pointer<OrtRunOptions>> out,
  ) {
    return _api.CreateRunOptions.asFunction<
      ffi.Pointer<OrtStatus> Function(
        ffi.Pointer<ffi.Pointer<OrtRunOptions>> out,
      )
    >()(out);
  }

  ffi.Pointer<OrtStatus> RunOptionsSetRunLogVerbosityLevel(
    ffi.Pointer<OrtRunOptions> options,
    int log_verbosity_level,
  ) {
    return _api.RunOptionsSetRunLogVerbosityLevel.asFunction<
      ffi.Pointer<OrtStatus> Function(
        ffi.Pointer<OrtRunOptions> options,
        int log_verbosity_level,
      )
    >()(options, log_verbosity_level);
  }

  ffi.Pointer<OrtStatus> RunOptionsSetRunLogSeverityLevel(
    ffi.Pointer<OrtRunOptions> options,
    int log_severity_level,
  ) {
    return _api.RunOptionsSetRunLogSeverityLevel.asFunction<
      ffi.Pointer<OrtStatus> Function(
        ffi.Pointer<OrtRunOptions> options,
        int log_severity_level,
      )
    >()(options, log_severity_level);
  }

  ffi.Pointer<OrtStatus> RunOptionsSetRunTag(
    ffi.Pointer<OrtRunOptions> options,
    ffi.Pointer<ffi.Char> run_tag,
  ) {
    return _api.RunOptionsSetRunTag.asFunction<
      ffi.Pointer<OrtStatus> Function(
        ffi.Pointer<OrtRunOptions> options,
        ffi.Pointer<ffi.Char> run_tag,
      )
    >()(options, run_tag);
  }

  void ReleaseRunOptions(ffi.Pointer<OrtRunOptions> input) {
    _api.ReleaseRunOptions.asFunction<
      void Function(ffi.Pointer<OrtRunOptions> input)
    >()(input);
  }

  // Value operations
  ffi.Pointer<OrtStatus> CreateTensorWithDataAsOrtValue(
    ffi.Pointer<OrtMemoryInfo> info,
    ffi.Pointer<ffi.Void> p_data,
    int p_data_len,
    ffi.Pointer<ffi.Int64> shape,
    int shape_len,
    int type,
    ffi.Pointer<ffi.Pointer<OrtValue>> out,
  ) {
    return _api.CreateTensorWithDataAsOrtValue.asFunction<
      ffi.Pointer<OrtStatus> Function(
        ffi.Pointer<OrtMemoryInfo> info,
        ffi.Pointer<ffi.Void> p_data,
        int p_data_len,
        ffi.Pointer<ffi.Int64> shape,
        int shape_len,
        int type,
        ffi.Pointer<ffi.Pointer<OrtValue>> out,
      )
    >()(info, p_data, p_data_len, shape, shape_len, type, out);
  }

  ffi.Pointer<OrtStatus> IsTensor(
    ffi.Pointer<OrtValue> value,
    ffi.Pointer<ffi.Int> out,
  ) {
    return _api.IsTensor.asFunction<
      ffi.Pointer<OrtStatus> Function(
        ffi.Pointer<OrtValue> value,
        ffi.Pointer<ffi.Int> out,
      )
    >()(value, out);
  }

  ffi.Pointer<OrtStatus> GetTensorMutableData(
    ffi.Pointer<OrtValue> value,
    ffi.Pointer<ffi.Pointer<ffi.Void>> out,
  ) {
    return _api.GetTensorMutableData.asFunction<
      ffi.Pointer<OrtStatus> Function(
        ffi.Pointer<OrtValue> value,
        ffi.Pointer<ffi.Pointer<ffi.Void>> out,
      )
    >()(value, out);
  }

  void ReleaseValue(ffi.Pointer<OrtValue> input) {
    _api.ReleaseValue.asFunction<void Function(ffi.Pointer<OrtValue> input)>()(
      input,
    );
  }

  // Memory Info operations
  ffi.Pointer<OrtStatus> CreateCpuMemoryInfo(
    int allocator_type,
    int memory_type,
    ffi.Pointer<ffi.Pointer<OrtMemoryInfo>> out,
  ) {
    return _api.CreateCpuMemoryInfo.asFunction<
      ffi.Pointer<OrtStatus> Function(
        int allocator_type,
        int memory_type,
        ffi.Pointer<ffi.Pointer<OrtMemoryInfo>> out,
      )
    >()(allocator_type, memory_type, out);
  }

  void ReleaseMemoryInfo(ffi.Pointer<OrtMemoryInfo> input) {
    _api.ReleaseMemoryInfo.asFunction<
      void Function(ffi.Pointer<OrtMemoryInfo> input)
    >()(input);
  }

  // Session Information operations
  ffi.Pointer<OrtStatus> SessionGetInputCount(
    ffi.Pointer<OrtSession> session,
    ffi.Pointer<ffi.Size> out,
  ) {
    return _api.SessionGetInputCount.asFunction<
      ffi.Pointer<OrtStatus> Function(
        ffi.Pointer<OrtSession> session,
        ffi.Pointer<ffi.Size> out,
      )
    >()(session, out);
  }

  ffi.Pointer<OrtStatus> SessionGetOutputCount(
    ffi.Pointer<OrtSession> session,
    ffi.Pointer<ffi.Size> out,
  ) {
    return _api.SessionGetOutputCount.asFunction<
      ffi.Pointer<OrtStatus> Function(
        ffi.Pointer<OrtSession> session,
        ffi.Pointer<ffi.Size> out,
      )
    >()(session, out);
  }

  ffi.Pointer<OrtStatus> SessionGetOverridableInitializerCount(
    ffi.Pointer<OrtSession> session,
    ffi.Pointer<ffi.Size> out,
  ) {
    return _api.SessionGetOverridableInitializerCount.asFunction<
      ffi.Pointer<OrtStatus> Function(
        ffi.Pointer<OrtSession> session,
        ffi.Pointer<ffi.Size> out,
      )
    >()(session, out);
  }

  ffi.Pointer<OrtStatus> SessionGetInputTypeInfo(
    ffi.Pointer<OrtSession> session,
    int index,
    ffi.Pointer<ffi.Pointer<OrtTypeInfo>> type_info,
  ) {
    return _api.SessionGetInputTypeInfo.asFunction<
      ffi.Pointer<OrtStatus> Function(
        ffi.Pointer<OrtSession> session,
        int index,
        ffi.Pointer<ffi.Pointer<OrtTypeInfo>> type_info,
      )
    >()(session, index, type_info);
  }

  ffi.Pointer<OrtStatus> SessionGetOutputTypeInfo(
    ffi.Pointer<OrtSession> session,
    int index,
    ffi.Pointer<ffi.Pointer<OrtTypeInfo>> type_info,
  ) {
    return _api.SessionGetOutputTypeInfo.asFunction<
      ffi.Pointer<OrtStatus> Function(
        ffi.Pointer<OrtSession> session,
        int index,
        ffi.Pointer<ffi.Pointer<OrtTypeInfo>> type_info,
      )
    >()(session, index, type_info);
  }

  ffi.Pointer<OrtStatus> SessionGetOverridableInitializerTypeInfo(
    ffi.Pointer<OrtSession> session,
    int index,
    ffi.Pointer<ffi.Pointer<OrtTypeInfo>> type_info,
  ) {
    return _api.SessionGetOverridableInitializerTypeInfo.asFunction<
      ffi.Pointer<OrtStatus> Function(
        ffi.Pointer<OrtSession> session,
        int index,
        ffi.Pointer<ffi.Pointer<OrtTypeInfo>> type_info,
      )
    >()(session, index, type_info);
  }

  ffi.Pointer<OrtStatus> SessionGetInputName(
    ffi.Pointer<OrtSession> session,
    int index,
    ffi.Pointer<OrtAllocator> allocator,
    ffi.Pointer<ffi.Pointer<ffi.Char>> value,
  ) {
    return _api.SessionGetInputName.asFunction<
      ffi.Pointer<OrtStatus> Function(
        ffi.Pointer<OrtSession> session,
        int index,
        ffi.Pointer<OrtAllocator> allocator,
        ffi.Pointer<ffi.Pointer<ffi.Char>> value,
      )
    >()(session, index, allocator, value);
  }

  ffi.Pointer<OrtStatus> SessionGetOutputName(
    ffi.Pointer<OrtSession> session,
    int index,
    ffi.Pointer<OrtAllocator> allocator,
    ffi.Pointer<ffi.Pointer<ffi.Char>> value,
  ) {
    return _api.SessionGetOutputName.asFunction<
      ffi.Pointer<OrtStatus> Function(
        ffi.Pointer<OrtSession> session,
        int index,
        ffi.Pointer<OrtAllocator> allocator,
        ffi.Pointer<ffi.Pointer<ffi.Char>> value,
      )
    >()(session, index, allocator, value);
  }

  ffi.Pointer<OrtStatus> SessionGetOverridableInitializerName(
    ffi.Pointer<OrtSession> session,
    int index,
    ffi.Pointer<OrtAllocator> allocator,
    ffi.Pointer<ffi.Pointer<ffi.Char>> value,
  ) {
    return _api.SessionGetOverridableInitializerName.asFunction<
      ffi.Pointer<OrtStatus> Function(
        ffi.Pointer<OrtSession> session,
        int index,
        ffi.Pointer<OrtAllocator> allocator,
        ffi.Pointer<ffi.Pointer<ffi.Char>> value,
      )
    >()(session, index, allocator, value);
  }

  // Type Information operations
  ffi.Pointer<OrtStatus> GetTensorTypeAndShape(
    ffi.Pointer<OrtValue> value,
    ffi.Pointer<ffi.Pointer<OrtTensorTypeAndShapeInfo>> out,
  ) {
    return _api.GetTensorTypeAndShape.asFunction<
      ffi.Pointer<OrtStatus> Function(
        ffi.Pointer<OrtValue> value,
        ffi.Pointer<ffi.Pointer<OrtTensorTypeAndShapeInfo>> out,
      )
    >()(value, out);
  }

  ffi.Pointer<OrtStatus> GetTypeInfo(
    ffi.Pointer<OrtValue> value,
    ffi.Pointer<ffi.Pointer<OrtTypeInfo>> out,
  ) {
    return _api.GetTypeInfo.asFunction<
      ffi.Pointer<OrtStatus> Function(
        ffi.Pointer<OrtValue> value,
        ffi.Pointer<ffi.Pointer<OrtTypeInfo>> out,
      )
    >()(value, out);
  }

  ffi.Pointer<OrtStatus> GetValueType(
    ffi.Pointer<OrtValue> value,
    ffi.Pointer<ffi.UnsignedInt> out,
  ) {
    return _api.GetValueType.asFunction<
      ffi.Pointer<OrtStatus> Function(
        ffi.Pointer<OrtValue> value,
        ffi.Pointer<ffi.UnsignedInt> out,
      )
    >()(value, out);
  }

  void ReleaseTypeInfo(ffi.Pointer<OrtTypeInfo> input) {
    _api.ReleaseTypeInfo.asFunction<
      void Function(ffi.Pointer<OrtTypeInfo> input)
    >()(input);
  }

  void ReleaseTensorTypeAndShapeInfo(
    ffi.Pointer<OrtTensorTypeAndShapeInfo> input,
  ) {
    _api.ReleaseTensorTypeAndShapeInfo.asFunction<
      void Function(ffi.Pointer<OrtTensorTypeAndShapeInfo> input)
    >()(input);
  }

  // Tensor Type and Shape Information operations
  ffi.Pointer<OrtStatus> GetTensorElementType(
    ffi.Pointer<OrtTensorTypeAndShapeInfo> info,
    ffi.Pointer<ffi.UnsignedInt> out,
  ) {
    return _api.GetTensorElementType.asFunction<
      ffi.Pointer<OrtStatus> Function(
        ffi.Pointer<OrtTensorTypeAndShapeInfo> info,
        ffi.Pointer<ffi.UnsignedInt> out,
      )
    >()(info, out);
  }

  ffi.Pointer<OrtStatus> GetDimensionsCount(
    ffi.Pointer<OrtTensorTypeAndShapeInfo> info,
    ffi.Pointer<ffi.Size> out,
  ) {
    return _api.GetDimensionsCount.asFunction<
      ffi.Pointer<OrtStatus> Function(
        ffi.Pointer<OrtTensorTypeAndShapeInfo> info,
        ffi.Pointer<ffi.Size> out,
      )
    >()(info, out);
  }

  ffi.Pointer<OrtStatus> GetDimensions(
    ffi.Pointer<OrtTensorTypeAndShapeInfo> info,
    ffi.Pointer<ffi.Int64> dim_values,
    int dim_values_length,
  ) {
    return _api.GetDimensions.asFunction<
      ffi.Pointer<OrtStatus> Function(
        ffi.Pointer<OrtTensorTypeAndShapeInfo> info,
        ffi.Pointer<ffi.Int64> dim_values,
        int dim_values_length,
      )
    >()(info, dim_values, dim_values_length);
  }

  ffi.Pointer<OrtStatus> GetSymbolicDimensions(
    ffi.Pointer<OrtTensorTypeAndShapeInfo> info,
    ffi.Pointer<ffi.Pointer<ffi.Char>> dim_params,
    int dim_params_length,
  ) {
    return _api.GetSymbolicDimensions.asFunction<
      ffi.Pointer<OrtStatus> Function(
        ffi.Pointer<OrtTensorTypeAndShapeInfo> info,
        ffi.Pointer<ffi.Pointer<ffi.Char>> dim_params,
        int dim_params_length,
      )
    >()(info, dim_params, dim_params_length);
  }

  ffi.Pointer<OrtStatus> GetTensorShapeElementCount(
    ffi.Pointer<OrtTensorTypeAndShapeInfo> info,
    ffi.Pointer<ffi.Size> out,
  ) {
    return _api.GetTensorShapeElementCount.asFunction<
      ffi.Pointer<OrtStatus> Function(
        ffi.Pointer<OrtTensorTypeAndShapeInfo> info,
        ffi.Pointer<ffi.Size> out,
      )
    >()(info, out);
  }

  // Allocator operations
  ffi.Pointer<OrtStatus> GetAllocatorWithDefaultOptions(
    ffi.Pointer<ffi.Pointer<OrtAllocator>> out,
  ) {
    return _api.GetAllocatorWithDefaultOptions.asFunction<
      ffi.Pointer<OrtStatus> Function(
        ffi.Pointer<ffi.Pointer<OrtAllocator>> out,
      )
    >()(out);
  }

  ffi.Pointer<OrtStatus> AllocatorAlloc(
    ffi.Pointer<OrtAllocator> ort_allocator,
    int size,
    ffi.Pointer<ffi.Pointer<ffi.Void>> out,
  ) {
    return _api.AllocatorAlloc.asFunction<
      ffi.Pointer<OrtStatus> Function(
        ffi.Pointer<OrtAllocator> ort_allocator,
        int size,
        ffi.Pointer<ffi.Pointer<ffi.Void>> out,
      )
    >()(ort_allocator, size, out);
  }

  ffi.Pointer<OrtStatus> AllocatorFree(
    ffi.Pointer<OrtAllocator> ort_allocator,
    ffi.Pointer<ffi.Void> p,
  ) {
    return _api.AllocatorFree.asFunction<
      ffi.Pointer<OrtStatus> Function(
        ffi.Pointer<OrtAllocator> ort_allocator,
        ffi.Pointer<ffi.Void> p,
      )
    >()(ort_allocator, p);
  }

  ffi.Pointer<OrtStatus> AllocatorGetInfo(
    ffi.Pointer<OrtAllocator> ort_allocator,
    ffi.Pointer<ffi.Pointer<OrtMemoryInfo>> out,
  ) {
    return _api.AllocatorGetInfo.asFunction<
      ffi.Pointer<OrtStatus> Function(
        ffi.Pointer<OrtAllocator> ort_allocator,
        ffi.Pointer<ffi.Pointer<OrtMemoryInfo>> out,
      )
    >()(ort_allocator, out);
  }

  ffi.Pointer<OrtStatus> CreateAllocator(
    ffi.Pointer<OrtSession> session,
    ffi.Pointer<OrtMemoryInfo> mem_info,
    ffi.Pointer<ffi.Pointer<OrtAllocator>> out,
  ) {
    return _api.CreateAllocator.asFunction<
      ffi.Pointer<OrtStatus> Function(
        ffi.Pointer<OrtSession> session,
        ffi.Pointer<OrtMemoryInfo> mem_info,
        ffi.Pointer<ffi.Pointer<OrtAllocator>> out,
      )
    >()(session, mem_info, out);
  }

  void ReleaseAllocator(ffi.Pointer<OrtAllocator> input) {
    _api.ReleaseAllocator.asFunction<
      void Function(ffi.Pointer<OrtAllocator> input)
    >()(input);
  }

  // Additional Tensor operations
  ffi.Pointer<OrtStatus> CreateTensorAsOrtValue(
    ffi.Pointer<OrtAllocator> allocator,
    ffi.Pointer<ffi.Int64> shape,
    int shape_len,
    int type,
    ffi.Pointer<ffi.Pointer<OrtValue>> out,
  ) {
    return _api.CreateTensorAsOrtValue.asFunction<
      ffi.Pointer<OrtStatus> Function(
        ffi.Pointer<OrtAllocator> allocator,
        ffi.Pointer<ffi.Int64> shape,
        int shape_len,
        int type,
        ffi.Pointer<ffi.Pointer<OrtValue>> out,
      )
    >()(allocator, shape, shape_len, type, out);
  }

  ffi.Pointer<OrtStatus> CastTypeInfoToTensorInfo(
    ffi.Pointer<OrtTypeInfo> type_info,
    ffi.Pointer<ffi.Pointer<OrtTensorTypeAndShapeInfo>> out,
  ) {
    return _api.CastTypeInfoToTensorInfo.asFunction<
      ffi.Pointer<OrtStatus> Function(
        ffi.Pointer<OrtTypeInfo> type_info,
        ffi.Pointer<ffi.Pointer<OrtTensorTypeAndShapeInfo>> out,
      )
    >()(type_info, out);
  }

  ffi.Pointer<OrtStatus> GetOnnxTypeFromTypeInfo(
    ffi.Pointer<OrtTypeInfo> type_info,
    ffi.Pointer<ffi.UnsignedInt> out,
  ) {
    return _api.GetOnnxTypeFromTypeInfo.asFunction<
      ffi.Pointer<OrtStatus> Function(
        ffi.Pointer<OrtTypeInfo> type_info,
        ffi.Pointer<ffi.UnsignedInt> out,
      )
    >()(type_info, out);
  }

  ffi.Pointer<OrtStatus> CreateTensorTypeAndShapeInfo(
    ffi.Pointer<ffi.Pointer<OrtTensorTypeAndShapeInfo>> out,
  ) {
    return _api.CreateTensorTypeAndShapeInfo.asFunction<
      ffi.Pointer<OrtStatus> Function(
        ffi.Pointer<ffi.Pointer<OrtTensorTypeAndShapeInfo>> out,
      )
    >()(out);
  }

  // String Tensor operations
  ffi.Pointer<OrtStatus> FillStringTensor(
    ffi.Pointer<OrtValue> value,
    ffi.Pointer<ffi.Pointer<ffi.Char>> s,
    int s_len,
  ) {
    return _api.FillStringTensor.asFunction<
      ffi.Pointer<OrtStatus> Function(
        ffi.Pointer<OrtValue> value,
        ffi.Pointer<ffi.Pointer<ffi.Char>> s,
        int s_len,
      )
    >()(value, s, s_len);
  }

  ffi.Pointer<OrtStatus> GetStringTensorDataLength(
    ffi.Pointer<OrtValue> value,
    ffi.Pointer<ffi.Size> len,
  ) {
    return _api.GetStringTensorDataLength.asFunction<
      ffi.Pointer<OrtStatus> Function(
        ffi.Pointer<OrtValue> value,
        ffi.Pointer<ffi.Size> len,
      )
    >()(value, len);
  }

  ffi.Pointer<OrtStatus> GetStringTensorContent(
    ffi.Pointer<OrtValue> value,
    ffi.Pointer<ffi.Void> s,
    int s_len,
    ffi.Pointer<ffi.Size> offsets,
    int offsets_len,
  ) {
    return _api.GetStringTensorContent.asFunction<
      ffi.Pointer<OrtStatus> Function(
        ffi.Pointer<OrtValue> value,
        ffi.Pointer<ffi.Void> s,
        int s_len,
        ffi.Pointer<ffi.Size> offsets,
        int offsets_len,
      )
    >()(value, s, s_len, offsets, offsets_len);
  }

  // Tensor Type Setting operations
  ffi.Pointer<OrtStatus> SetTensorElementType(
    ffi.Pointer<OrtTensorTypeAndShapeInfo> info,
    int type,
  ) {
    return _api.SetTensorElementType.asFunction<
      ffi.Pointer<OrtStatus> Function(
        ffi.Pointer<OrtTensorTypeAndShapeInfo> info,
        int type,
      )
    >()(info, type);
  }

  ffi.Pointer<OrtStatus> SetDimensions(
    ffi.Pointer<OrtTensorTypeAndShapeInfo> info,
    ffi.Pointer<ffi.Int64> dim_values,
    int dim_count,
  ) {
    return _api.SetDimensions.asFunction<
      ffi.Pointer<OrtStatus> Function(
        ffi.Pointer<OrtTensorTypeAndShapeInfo> info,
        ffi.Pointer<ffi.Int64> dim_values,
        int dim_count,
      )
    >()(info, dim_values, dim_count);
  }

  // Provider operations
  ffi.Pointer<OrtStatus> GetAvailableProviders(
    ffi.Pointer<ffi.Pointer<ffi.Pointer<ffi.Char>>> out_ptr,
    ffi.Pointer<ffi.Int> provider_length,
  ) {
    return _api.GetAvailableProviders.asFunction<
      ffi.Pointer<OrtStatus> Function(
        ffi.Pointer<ffi.Pointer<ffi.Pointer<ffi.Char>>> out_ptr,
        ffi.Pointer<ffi.Int> provider_length,
      )
    >()(out_ptr, provider_length);
  }

  ffi.Pointer<OrtStatus> ReleaseAvailableProviders(
    ffi.Pointer<ffi.Pointer<ffi.Char>> ptr,
    int providers_length,
  ) {
    return _api.ReleaseAvailableProviders.asFunction<
      ffi.Pointer<OrtStatus> Function(
        ffi.Pointer<ffi.Pointer<ffi.Char>> ptr,
        int providers_length,
      )
    >()(ptr, providers_length);
  }
}
