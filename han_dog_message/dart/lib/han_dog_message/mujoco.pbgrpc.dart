// This is a generated file - do not edit.
//
// Generated from han_dog_message/mujoco.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:async' as $async;
import 'dart:core' as $core;

import 'package:grpc/service_api.dart' as $grpc;
import 'package:protobuf/protobuf.dart' as $pb;
import 'package:protobuf/well_known_types/google/protobuf/empty.pb.dart' as $1;

import 'common.pb.dart' as $0;
import 'mujoco.pb.dart' as $2;

export 'mujoco.pb.dart';

/// MuJoCo 物理仿真服务。
/// 由 Python 端实现，Dart 端作为客户端调用。
@$pb.GrpcServiceName('han_dog.Mujoco')
class MujocoClient extends $grpc.Client {
  /// The hostname for this service.
  static const $core.String defaultHost = '';

  /// OAuth scopes needed for the client.
  static const $core.List<$core.String> oauthScopes = [
    '',
  ];

  MujocoClient(super.channel, {super.options, super.interceptors});

  /// 初始化仿真器：设置机器人模型和初始姿态。
  $grpc.ResponseFuture<$1.Empty> setModel(
    $0.RobotModel request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$setModel, request, options: options);
  }

  /// 执行一步物理仿真：传入目标关节角度，返回仿真后的传感器状态。
  $grpc.ResponseFuture<$0.SimState> step(
    $0.Matrix4 request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$step, request, options: options);
  }

  // method descriptors

  static final _$setModel = $grpc.ClientMethod<$0.RobotModel, $1.Empty>(
      '/han_dog.Mujoco/SetModel',
      ($0.RobotModel value) => value.writeToBuffer(),
      $1.Empty.fromBuffer);
  static final _$step = $grpc.ClientMethod<$0.Matrix4, $0.SimState>(
      '/han_dog.Mujoco/Step',
      ($0.Matrix4 value) => value.writeToBuffer(),
      $0.SimState.fromBuffer);
}

@$pb.GrpcServiceName('han_dog.Mujoco')
abstract class MujocoServiceBase extends $grpc.Service {
  $core.String get $name => 'han_dog.Mujoco';

  MujocoServiceBase() {
    $addMethod($grpc.ServiceMethod<$0.RobotModel, $1.Empty>(
        'SetModel',
        setModel_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.RobotModel.fromBuffer(value),
        ($1.Empty value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.Matrix4, $0.SimState>(
        'Step',
        step_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.Matrix4.fromBuffer(value),
        ($0.SimState value) => value.writeToBuffer()));
  }

  $async.Future<$1.Empty> setModel_Pre(
      $grpc.ServiceCall $call, $async.Future<$0.RobotModel> $request) async {
    return setModel($call, await $request);
  }

  $async.Future<$1.Empty> setModel(
      $grpc.ServiceCall call, $0.RobotModel request);

  $async.Future<$0.SimState> step_Pre(
      $grpc.ServiceCall $call, $async.Future<$0.Matrix4> $request) async {
    return step($call, await $request);
  }

  $async.Future<$0.SimState> step($grpc.ServiceCall call, $0.Matrix4 request);
}

/// MuJoCo 可视化服务。
/// 用于将仿真/真机数据回放到 MuJoCo viewer 中。
@$pb.GrpcServiceName('han_dog.MujocoViewer')
class MujocoViewerClient extends $grpc.Client {
  /// The hostname for this service.
  static const $core.String defaultHost = '';

  /// OAuth scopes needed for the client.
  static const $core.List<$core.String> oauthScopes = [
    '',
  ];

  MujocoViewerClient(super.channel, {super.options, super.interceptors});

  /// 播放一帧：将广义坐标/速度发送到 viewer 进行渲染。
  $grpc.ResponseFuture<$1.Empty> play(
    $2.ViewerFrame request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$play, request, options: options);
  }

  // method descriptors

  static final _$play = $grpc.ClientMethod<$2.ViewerFrame, $1.Empty>(
      '/han_dog.MujocoViewer/Play',
      ($2.ViewerFrame value) => value.writeToBuffer(),
      $1.Empty.fromBuffer);
}

@$pb.GrpcServiceName('han_dog.MujocoViewer')
abstract class MujocoViewerServiceBase extends $grpc.Service {
  $core.String get $name => 'han_dog.MujocoViewer';

  MujocoViewerServiceBase() {
    $addMethod($grpc.ServiceMethod<$2.ViewerFrame, $1.Empty>(
        'Play',
        play_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $2.ViewerFrame.fromBuffer(value),
        ($1.Empty value) => value.writeToBuffer()));
  }

  $async.Future<$1.Empty> play_Pre(
      $grpc.ServiceCall $call, $async.Future<$2.ViewerFrame> $request) async {
    return play($call, await $request);
  }

  $async.Future<$1.Empty> play($grpc.ServiceCall call, $2.ViewerFrame request);
}
