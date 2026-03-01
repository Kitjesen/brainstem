import 'dart:ffi';
import 'package:ffi/ffi.dart';

import 'ffi/onnx_api.dart';
import 'ffi/bindings.g.dart';
import 'status.dart';

class SessionOptions {
  /// Number of threads used to parallelize the execution within nodes
  final int? intraOpNumThreads;

  /// Number of threads used to parallelize the execution of the graph
  final int? interOpNumThreads;

  /// Controls whether you want to execute operators sequentially or in parallel
  final ExecutionMode? executionMode;

  /// Graph optimization level
  final GraphOptimizationLevel? graphOptimizationLevel;

  /// Filepath to save optimized model after graph level transformations
  final String? optimizedModelFilePath;

  /// Enable profiling with profile file prefix
  final String? profilingFilePrefix;

  /// Disable profiling
  final bool disableProfiling;

  /// Enable memory pattern optimization
  final bool enableMemPattern;

  /// Disable memory pattern optimization
  final bool disableMemPattern;

  /// Enable CPU memory arena
  final bool enableCpuMemArena;

  /// Disable CPU memory arena
  final bool disableCpuMemArena;

  /// Session log identifier
  final String? sessionLogId;

  /// Session log verbosity level
  final int? sessionLogVerbosityLevel;

  /// Session log severity level (refer to OrtLoggingLevel)
  final OrtLoggingLevel? sessionLogSeverityLevel;

  /// Session configuration entries as key-value pairs
  final Map<String, String>? configEntries;

  /// Override symbolic dimensions with actual values
  final Map<String, int>? freeDimensionOverrides;

  const SessionOptions({
    this.intraOpNumThreads,
    this.interOpNumThreads,
    this.executionMode,
    this.graphOptimizationLevel,
    this.optimizedModelFilePath,
    this.profilingFilePrefix,
    this.disableProfiling = false,
    this.enableMemPattern = false,
    this.disableMemPattern = false,
    this.enableCpuMemArena = false,
    this.disableCpuMemArena = false,
    this.sessionLogId,
    this.sessionLogVerbosityLevel,
    this.sessionLogSeverityLevel,
    this.configEntries,
    this.freeDimensionOverrides,
  });

  Pointer<OrtSessionOptions> fill(Pointer<OrtSessionOptions> optionsPtr) {
    if (optionsPtr == nullptr) return optionsPtr;

    // Set thread numbers
    if (intraOpNumThreads != null) {
      ortApi.SetIntraOpNumThreads(optionsPtr, intraOpNumThreads!).guard();
    }

    if (interOpNumThreads != null) {
      ortApi.SetInterOpNumThreads(optionsPtr, interOpNumThreads!).guard();
    }

    // Set execution mode
    if (executionMode != null) {
      ortApi.SetSessionExecutionMode(optionsPtr, executionMode!.value).guard();
    }

    // Set graph optimization level
    if (graphOptimizationLevel != null) {
      ortApi.SetSessionGraphOptimizationLevel(
        optionsPtr,
        graphOptimizationLevel!.value,
      ).guard();
    }

    // // Set optimized model file path
    // if (optimizedModelFilePath != null) {
    //   final pathPtr = optimizedModelFilePath!.toNativeUtf16();
    //   try {
    //     ortApi.SetOptimizedModelFilePath(
    //       optionsPtr,
    //       pathPtr.cast<Utf16>().cast(),
    //     ).guard();
    //   } finally {
    //     malloc.free(pathPtr);
    //   }
    // }

    // // Configure profiling
    // if (profilingFilePrefix != null) {
    //   final prefixPtr = profilingFilePrefix!.toNativeUtf16();
    //   try {
    //     ortApi.EnableProfiling(
    //       optionsPtr,
    //       prefixPtr.cast<Utf16>().cast(),
    //     ).guard();
    //   } finally {
    //     malloc.free(prefixPtr);
    //   }
    // } else if (disableProfiling) {
    //   ortApi.DisableProfiling(optionsPtr).guard();
    // }

    // Configure memory pattern
    if (enableMemPattern) {
      ortApi.EnableMemPattern(optionsPtr).guard();
    } else if (disableMemPattern) {
      ortApi.DisableMemPattern(optionsPtr).guard();
    }

    // Configure CPU memory arena
    if (enableCpuMemArena) {
      ortApi.EnableCpuMemArena(optionsPtr).guard();
    } else if (disableCpuMemArena) {
      ortApi.DisableCpuMemArena(optionsPtr).guard();
    }

    // Set session log id
    if (sessionLogId != null) {
      final logIdPtr = sessionLogId!.toNativeUtf8();
      try {
        ortApi.SetSessionLogId(optionsPtr, logIdPtr.cast()).guard();
      } finally {
        malloc.free(logIdPtr);
      }
    }

    // Set log verbosity level
    if (sessionLogVerbosityLevel != null) {
      ortApi.SetSessionLogVerbosityLevel(
        optionsPtr,
        sessionLogVerbosityLevel!,
      ).guard();
    }

    // Set log severity level
    if (sessionLogSeverityLevel != null) {
      ortApi.SetSessionLogSeverityLevel(
        optionsPtr,
        sessionLogSeverityLevel!.value,
      ).guard();
    }

    // Add configuration entries
    if (configEntries != null) {
      for (final entry in configEntries!.entries) {
        final keyPtr = entry.key.toNativeUtf8();
        final valuePtr = entry.value.toNativeUtf8();
        try {
          ortApi.AddSessionConfigEntry(
            optionsPtr,
            keyPtr.cast(),
            valuePtr.cast(),
          ).guard();
        } finally {
          malloc.free(keyPtr);
          malloc.free(valuePtr);
        }
      }
    }

    // Add free dimension overrides
    if (freeDimensionOverrides != null) {
      for (final entry in freeDimensionOverrides!.entries) {
        final denotationPtr = entry.key.toNativeUtf8();
        try {
          ortApi.AddFreeDimensionOverride(
            optionsPtr,
            denotationPtr.cast(),
            entry.value,
          ).guard();
        } finally {
          malloc.free(denotationPtr);
        }
      }
    }

    return optionsPtr;
  }
}
