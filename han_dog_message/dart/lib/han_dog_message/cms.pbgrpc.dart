// This is a generated file - do not edit.
//
// Generated from han_dog_message/cms.proto.

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
import 'package:protobuf/well_known_types/google/protobuf/empty.pb.dart' as $0;
import 'package:protobuf/well_known_types/google/protobuf/timestamp.pb.dart'
    as $3;

import 'cms.pb.dart' as $2;
import 'common.pb.dart' as $1;

export 'cms.pb.dart';

/// 四足机器人命令与监控服务。
///
/// 控制类 RPC（受仲裁器限制，遥控器优先级更高）：
///   Enable / Disable / Walk / StandUp / SitDown
///
/// 仿真类 RPC（仅在 sim 模式下使用）：
///   Tick / Step
///
/// 监控类 RPC（不受仲裁限制，任何客户端均可订阅）：
///   ListenHistory / ListenImu / ListenJoint / GetStartTime / GetParams
@$pb.GrpcServiceName('han_dog.Cms')
class CmsClient extends $grpc.Client {
  /// The hostname for this service.
  static const $core.String defaultHost = '';

  /// OAuth scopes needed for the client.
  static const $core.List<$core.String> oauthScopes = [
    '',
  ];

  CmsClient(super.channel, {super.options, super.interceptors});

  /// 使能所有电机（硬件级操作，不经仲裁）。
  $grpc.ResponseFuture<$0.Empty> enable(
    $0.Empty request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$enable, request, options: options);
  }

  /// 禁用所有电机（硬件级操作，不经仲裁）。
  $grpc.ResponseFuture<$0.Empty> disable(
    $0.Empty request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$disable, request, options: options);
  }

  /// 行走：传入方向向量 (x=前后, y=左右, z=旋转)，范围 [-1, 1]。
  $grpc.ResponseFuture<$0.Empty> walk(
    $1.Vector3 request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$walk, request, options: options);
  }

  /// 从坐姿过渡到站立姿态。
  $grpc.ResponseFuture<$0.Empty> standUp(
    $0.Empty request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$standUp, request, options: options);
  }

  /// 从站立过渡到坐姿。
  $grpc.ResponseFuture<$0.Empty> sitDown(
    $0.Empty request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$sitDown, request, options: options);
  }

  /// 推进一个仿真步（sim 模式），返回当前 History。
  $grpc.ResponseFuture<$2.History> tick(
    $0.Empty request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$tick, request, options: options);
  }

  /// 向控制器注入仿真传感器数据。
  $grpc.ResponseFuture<$0.Empty> step(
    $1.SimState request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$step, request, options: options);
  }

  /// 获取服务启动时间（UTC）。
  $grpc.ResponseFuture<$3.Timestamp> getStartTime(
    $0.Empty request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$getStartTime, request, options: options);
  }

  /// 实时推理历史流：每个推理周期（~20ms）发送一帧。
  $grpc.ResponseStream<$2.History> listenHistory(
    $0.Empty request, {
    $grpc.CallOptions? options,
  }) {
    return $createStreamingCall(
        _$listenHistory, $async.Stream.fromIterable([request]),
        options: options);
  }

  /// 实时 IMU 数据流。
  $grpc.ResponseStream<$2.Imu> listenImu(
    $0.Empty request, {
    $grpc.CallOptions? options,
  }) {
    return $createStreamingCall(
        _$listenImu, $async.Stream.fromIterable([request]),
        options: options);
  }

  /// 实时关节数据流（单关节上报或全关节快照）。
  $grpc.ResponseStream<$2.Joint> listenJoint(
    $0.Empty request, {
    $grpc.CallOptions? options,
  }) {
    return $createStreamingCall(
        _$listenJoint, $async.Stream.fromIterable([request]),
        options: options);
  }

  /// 获取机器人模型参数。
  $grpc.ResponseFuture<$2.Params> getParams(
    $0.Empty request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$getParams, request, options: options);
  }

  /// 切换到指定策略。机器人必须在 Grounded 状态。
  $grpc.ResponseFuture<$2.ProfileInfo> switchProfile(
    $2.ProfileRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$switchProfile, request, options: options);
  }

  /// 获取当前策略信息。
  $grpc.ResponseFuture<$2.ProfileInfo> getProfile(
    $0.Empty request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$getProfile, request, options: options);
  }

  // method descriptors

  static final _$enable = $grpc.ClientMethod<$0.Empty, $0.Empty>(
      '/han_dog.Cms/Enable',
      ($0.Empty value) => value.writeToBuffer(),
      $0.Empty.fromBuffer);
  static final _$disable = $grpc.ClientMethod<$0.Empty, $0.Empty>(
      '/han_dog.Cms/Disable',
      ($0.Empty value) => value.writeToBuffer(),
      $0.Empty.fromBuffer);
  static final _$walk = $grpc.ClientMethod<$1.Vector3, $0.Empty>(
      '/han_dog.Cms/Walk',
      ($1.Vector3 value) => value.writeToBuffer(),
      $0.Empty.fromBuffer);
  static final _$standUp = $grpc.ClientMethod<$0.Empty, $0.Empty>(
      '/han_dog.Cms/StandUp',
      ($0.Empty value) => value.writeToBuffer(),
      $0.Empty.fromBuffer);
  static final _$sitDown = $grpc.ClientMethod<$0.Empty, $0.Empty>(
      '/han_dog.Cms/SitDown',
      ($0.Empty value) => value.writeToBuffer(),
      $0.Empty.fromBuffer);
  static final _$tick = $grpc.ClientMethod<$0.Empty, $2.History>(
      '/han_dog.Cms/Tick',
      ($0.Empty value) => value.writeToBuffer(),
      $2.History.fromBuffer);
  static final _$step = $grpc.ClientMethod<$1.SimState, $0.Empty>(
      '/han_dog.Cms/Step',
      ($1.SimState value) => value.writeToBuffer(),
      $0.Empty.fromBuffer);
  static final _$getStartTime = $grpc.ClientMethod<$0.Empty, $3.Timestamp>(
      '/han_dog.Cms/GetStartTime',
      ($0.Empty value) => value.writeToBuffer(),
      $3.Timestamp.fromBuffer);
  static final _$listenHistory = $grpc.ClientMethod<$0.Empty, $2.History>(
      '/han_dog.Cms/ListenHistory',
      ($0.Empty value) => value.writeToBuffer(),
      $2.History.fromBuffer);
  static final _$listenImu = $grpc.ClientMethod<$0.Empty, $2.Imu>(
      '/han_dog.Cms/ListenImu',
      ($0.Empty value) => value.writeToBuffer(),
      $2.Imu.fromBuffer);
  static final _$listenJoint = $grpc.ClientMethod<$0.Empty, $2.Joint>(
      '/han_dog.Cms/ListenJoint',
      ($0.Empty value) => value.writeToBuffer(),
      $2.Joint.fromBuffer);
  static final _$getParams = $grpc.ClientMethod<$0.Empty, $2.Params>(
      '/han_dog.Cms/GetParams',
      ($0.Empty value) => value.writeToBuffer(),
      $2.Params.fromBuffer);
  static final _$switchProfile =
      $grpc.ClientMethod<$2.ProfileRequest, $2.ProfileInfo>(
          '/han_dog.Cms/SwitchProfile',
          ($2.ProfileRequest value) => value.writeToBuffer(),
          $2.ProfileInfo.fromBuffer);
  static final _$getProfile = $grpc.ClientMethod<$0.Empty, $2.ProfileInfo>(
      '/han_dog.Cms/GetProfile',
      ($0.Empty value) => value.writeToBuffer(),
      $2.ProfileInfo.fromBuffer);
}

@$pb.GrpcServiceName('han_dog.Cms')
abstract class CmsServiceBase extends $grpc.Service {
  $core.String get $name => 'han_dog.Cms';

  CmsServiceBase() {
    $addMethod($grpc.ServiceMethod<$0.Empty, $0.Empty>(
        'Enable',
        enable_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.Empty.fromBuffer(value),
        ($0.Empty value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.Empty, $0.Empty>(
        'Disable',
        disable_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.Empty.fromBuffer(value),
        ($0.Empty value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$1.Vector3, $0.Empty>(
        'Walk',
        walk_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $1.Vector3.fromBuffer(value),
        ($0.Empty value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.Empty, $0.Empty>(
        'StandUp',
        standUp_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.Empty.fromBuffer(value),
        ($0.Empty value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.Empty, $0.Empty>(
        'SitDown',
        sitDown_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.Empty.fromBuffer(value),
        ($0.Empty value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.Empty, $2.History>(
        'Tick',
        tick_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.Empty.fromBuffer(value),
        ($2.History value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$1.SimState, $0.Empty>(
        'Step',
        step_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $1.SimState.fromBuffer(value),
        ($0.Empty value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.Empty, $3.Timestamp>(
        'GetStartTime',
        getStartTime_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.Empty.fromBuffer(value),
        ($3.Timestamp value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.Empty, $2.History>(
        'ListenHistory',
        listenHistory_Pre,
        false,
        true,
        ($core.List<$core.int> value) => $0.Empty.fromBuffer(value),
        ($2.History value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.Empty, $2.Imu>(
        'ListenImu',
        listenImu_Pre,
        false,
        true,
        ($core.List<$core.int> value) => $0.Empty.fromBuffer(value),
        ($2.Imu value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.Empty, $2.Joint>(
        'ListenJoint',
        listenJoint_Pre,
        false,
        true,
        ($core.List<$core.int> value) => $0.Empty.fromBuffer(value),
        ($2.Joint value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.Empty, $2.Params>(
        'GetParams',
        getParams_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.Empty.fromBuffer(value),
        ($2.Params value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$2.ProfileRequest, $2.ProfileInfo>(
        'SwitchProfile',
        switchProfile_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $2.ProfileRequest.fromBuffer(value),
        ($2.ProfileInfo value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.Empty, $2.ProfileInfo>(
        'GetProfile',
        getProfile_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.Empty.fromBuffer(value),
        ($2.ProfileInfo value) => value.writeToBuffer()));
  }

  $async.Future<$0.Empty> enable_Pre(
      $grpc.ServiceCall $call, $async.Future<$0.Empty> $request) async {
    return enable($call, await $request);
  }

  $async.Future<$0.Empty> enable($grpc.ServiceCall call, $0.Empty request);

  $async.Future<$0.Empty> disable_Pre(
      $grpc.ServiceCall $call, $async.Future<$0.Empty> $request) async {
    return disable($call, await $request);
  }

  $async.Future<$0.Empty> disable($grpc.ServiceCall call, $0.Empty request);

  $async.Future<$0.Empty> walk_Pre(
      $grpc.ServiceCall $call, $async.Future<$1.Vector3> $request) async {
    return walk($call, await $request);
  }

  $async.Future<$0.Empty> walk($grpc.ServiceCall call, $1.Vector3 request);

  $async.Future<$0.Empty> standUp_Pre(
      $grpc.ServiceCall $call, $async.Future<$0.Empty> $request) async {
    return standUp($call, await $request);
  }

  $async.Future<$0.Empty> standUp($grpc.ServiceCall call, $0.Empty request);

  $async.Future<$0.Empty> sitDown_Pre(
      $grpc.ServiceCall $call, $async.Future<$0.Empty> $request) async {
    return sitDown($call, await $request);
  }

  $async.Future<$0.Empty> sitDown($grpc.ServiceCall call, $0.Empty request);

  $async.Future<$2.History> tick_Pre(
      $grpc.ServiceCall $call, $async.Future<$0.Empty> $request) async {
    return tick($call, await $request);
  }

  $async.Future<$2.History> tick($grpc.ServiceCall call, $0.Empty request);

  $async.Future<$0.Empty> step_Pre(
      $grpc.ServiceCall $call, $async.Future<$1.SimState> $request) async {
    return step($call, await $request);
  }

  $async.Future<$0.Empty> step($grpc.ServiceCall call, $1.SimState request);

  $async.Future<$3.Timestamp> getStartTime_Pre(
      $grpc.ServiceCall $call, $async.Future<$0.Empty> $request) async {
    return getStartTime($call, await $request);
  }

  $async.Future<$3.Timestamp> getStartTime(
      $grpc.ServiceCall call, $0.Empty request);

  $async.Stream<$2.History> listenHistory_Pre(
      $grpc.ServiceCall $call, $async.Future<$0.Empty> $request) async* {
    yield* listenHistory($call, await $request);
  }

  $async.Stream<$2.History> listenHistory(
      $grpc.ServiceCall call, $0.Empty request);

  $async.Stream<$2.Imu> listenImu_Pre(
      $grpc.ServiceCall $call, $async.Future<$0.Empty> $request) async* {
    yield* listenImu($call, await $request);
  }

  $async.Stream<$2.Imu> listenImu($grpc.ServiceCall call, $0.Empty request);

  $async.Stream<$2.Joint> listenJoint_Pre(
      $grpc.ServiceCall $call, $async.Future<$0.Empty> $request) async* {
    yield* listenJoint($call, await $request);
  }

  $async.Stream<$2.Joint> listenJoint($grpc.ServiceCall call, $0.Empty request);

  $async.Future<$2.Params> getParams_Pre(
      $grpc.ServiceCall $call, $async.Future<$0.Empty> $request) async {
    return getParams($call, await $request);
  }

  $async.Future<$2.Params> getParams($grpc.ServiceCall call, $0.Empty request);

  $async.Future<$2.ProfileInfo> switchProfile_Pre($grpc.ServiceCall $call,
      $async.Future<$2.ProfileRequest> $request) async {
    return switchProfile($call, await $request);
  }

  $async.Future<$2.ProfileInfo> switchProfile(
      $grpc.ServiceCall call, $2.ProfileRequest request);

  $async.Future<$2.ProfileInfo> getProfile_Pre(
      $grpc.ServiceCall $call, $async.Future<$0.Empty> $request) async {
    return getProfile($call, await $request);
  }

  $async.Future<$2.ProfileInfo> getProfile(
      $grpc.ServiceCall call, $0.Empty request);
}
