// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$RSState {

 int get canId;
/// Create a copy of RSState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RSStateCopyWith<RSState> get copyWith => _$RSStateCopyWithImpl<RSState>(this as RSState, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RSState&&(identical(other.canId, canId) || other.canId == canId));
}


@override
int get hashCode => Object.hash(runtimeType,canId);

@override
String toString() {
  return 'RSState(canId: $canId)';
}


}

/// @nodoc
abstract mixin class $RSStateCopyWith<$Res>  {
  factory $RSStateCopyWith(RSState value, $Res Function(RSState) _then) = _$RSStateCopyWithImpl;
@useResult
$Res call({
 int canId
});




}
/// @nodoc
class _$RSStateCopyWithImpl<$Res>
    implements $RSStateCopyWith<$Res> {
  _$RSStateCopyWithImpl(this._self, this._then);

  final RSState _self;
  final $Res Function(RSState) _then;

/// Create a copy of RSState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? canId = null,}) {
  return _then(_self.copyWith(
canId: null == canId ? _self.canId : canId // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [RSState].
extension RSStatePatterns on RSState {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( RSStateDeviceId value)?  deviceId,TResult Function( RSStateResponse value)?  response,TResult Function( RSStateReport value)?  report,TResult Function( RSStateGetter value)?  getter,TResult Function( RSStateError value)?  error,required TResult orElse(),}){
final _that = this;
switch (_that) {
case RSStateDeviceId() when deviceId != null:
return deviceId(_that);case RSStateResponse() when response != null:
return response(_that);case RSStateReport() when report != null:
return report(_that);case RSStateGetter() when getter != null:
return getter(_that);case RSStateError() when error != null:
return error(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( RSStateDeviceId value)  deviceId,required TResult Function( RSStateResponse value)  response,required TResult Function( RSStateReport value)  report,required TResult Function( RSStateGetter value)  getter,required TResult Function( RSStateError value)  error,}){
final _that = this;
switch (_that) {
case RSStateDeviceId():
return deviceId(_that);case RSStateResponse():
return response(_that);case RSStateReport():
return report(_that);case RSStateGetter():
return getter(_that);case RSStateError():
return error(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( RSStateDeviceId value)?  deviceId,TResult? Function( RSStateResponse value)?  response,TResult? Function( RSStateReport value)?  report,TResult? Function( RSStateGetter value)?  getter,TResult? Function( RSStateError value)?  error,}){
final _that = this;
switch (_that) {
case RSStateDeviceId() when deviceId != null:
return deviceId(_that);case RSStateResponse() when response != null:
return response(_that);case RSStateReport() when report != null:
return report(_that);case RSStateGetter() when getter != null:
return getter(_that);case RSStateError() when error != null:
return error(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( int canId,  BigInt mcuId)?  deviceId,TResult Function( int hostId,  int canId,  RSStatus status,  double position,  double velocity,  double torque,  double temperature,  RSErrors1 errors)?  response,TResult Function( int hostId,  int canId,  RSStatus status,  double position,  double velocity,  double torque,  double temperature,  RSErrors1 errors)?  report,TResult Function( int hostId,  int canId,  RSGetter? getter)?  getter,TResult Function( int hostId,  int canId,  RSErrors2 errors)?  error,required TResult orElse(),}) {final _that = this;
switch (_that) {
case RSStateDeviceId() when deviceId != null:
return deviceId(_that.canId,_that.mcuId);case RSStateResponse() when response != null:
return response(_that.hostId,_that.canId,_that.status,_that.position,_that.velocity,_that.torque,_that.temperature,_that.errors);case RSStateReport() when report != null:
return report(_that.hostId,_that.canId,_that.status,_that.position,_that.velocity,_that.torque,_that.temperature,_that.errors);case RSStateGetter() when getter != null:
return getter(_that.hostId,_that.canId,_that.getter);case RSStateError() when error != null:
return error(_that.hostId,_that.canId,_that.errors);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( int canId,  BigInt mcuId)  deviceId,required TResult Function( int hostId,  int canId,  RSStatus status,  double position,  double velocity,  double torque,  double temperature,  RSErrors1 errors)  response,required TResult Function( int hostId,  int canId,  RSStatus status,  double position,  double velocity,  double torque,  double temperature,  RSErrors1 errors)  report,required TResult Function( int hostId,  int canId,  RSGetter? getter)  getter,required TResult Function( int hostId,  int canId,  RSErrors2 errors)  error,}) {final _that = this;
switch (_that) {
case RSStateDeviceId():
return deviceId(_that.canId,_that.mcuId);case RSStateResponse():
return response(_that.hostId,_that.canId,_that.status,_that.position,_that.velocity,_that.torque,_that.temperature,_that.errors);case RSStateReport():
return report(_that.hostId,_that.canId,_that.status,_that.position,_that.velocity,_that.torque,_that.temperature,_that.errors);case RSStateGetter():
return getter(_that.hostId,_that.canId,_that.getter);case RSStateError():
return error(_that.hostId,_that.canId,_that.errors);}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( int canId,  BigInt mcuId)?  deviceId,TResult? Function( int hostId,  int canId,  RSStatus status,  double position,  double velocity,  double torque,  double temperature,  RSErrors1 errors)?  response,TResult? Function( int hostId,  int canId,  RSStatus status,  double position,  double velocity,  double torque,  double temperature,  RSErrors1 errors)?  report,TResult? Function( int hostId,  int canId,  RSGetter? getter)?  getter,TResult? Function( int hostId,  int canId,  RSErrors2 errors)?  error,}) {final _that = this;
switch (_that) {
case RSStateDeviceId() when deviceId != null:
return deviceId(_that.canId,_that.mcuId);case RSStateResponse() when response != null:
return response(_that.hostId,_that.canId,_that.status,_that.position,_that.velocity,_that.torque,_that.temperature,_that.errors);case RSStateReport() when report != null:
return report(_that.hostId,_that.canId,_that.status,_that.position,_that.velocity,_that.torque,_that.temperature,_that.errors);case RSStateGetter() when getter != null:
return getter(_that.hostId,_that.canId,_that.getter);case RSStateError() when error != null:
return error(_that.hostId,_that.canId,_that.errors);case _:
  return null;

}
}

}

/// @nodoc


class RSStateDeviceId extends RSState {
   RSStateDeviceId({required this.canId, required this.mcuId}): super._();
  

@override final  int canId;
 final  BigInt mcuId;

/// Create a copy of RSState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RSStateDeviceIdCopyWith<RSStateDeviceId> get copyWith => _$RSStateDeviceIdCopyWithImpl<RSStateDeviceId>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RSStateDeviceId&&(identical(other.canId, canId) || other.canId == canId)&&(identical(other.mcuId, mcuId) || other.mcuId == mcuId));
}


@override
int get hashCode => Object.hash(runtimeType,canId,mcuId);

@override
String toString() {
  return 'RSState.deviceId(canId: $canId, mcuId: $mcuId)';
}


}

/// @nodoc
abstract mixin class $RSStateDeviceIdCopyWith<$Res> implements $RSStateCopyWith<$Res> {
  factory $RSStateDeviceIdCopyWith(RSStateDeviceId value, $Res Function(RSStateDeviceId) _then) = _$RSStateDeviceIdCopyWithImpl;
@override @useResult
$Res call({
 int canId, BigInt mcuId
});




}
/// @nodoc
class _$RSStateDeviceIdCopyWithImpl<$Res>
    implements $RSStateDeviceIdCopyWith<$Res> {
  _$RSStateDeviceIdCopyWithImpl(this._self, this._then);

  final RSStateDeviceId _self;
  final $Res Function(RSStateDeviceId) _then;

/// Create a copy of RSState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? canId = null,Object? mcuId = null,}) {
  return _then(RSStateDeviceId(
canId: null == canId ? _self.canId : canId // ignore: cast_nullable_to_non_nullable
as int,mcuId: null == mcuId ? _self.mcuId : mcuId // ignore: cast_nullable_to_non_nullable
as BigInt,
  ));
}


}

/// @nodoc


class RSStateResponse extends RSState {
   RSStateResponse({required this.hostId, required this.canId, required this.status, required this.position, required this.velocity, required this.torque, required this.temperature, required this.errors}): super._();
  

 final  int hostId;
@override final  int canId;
 final  RSStatus status;
 final  double position;
 final  double velocity;
 final  double torque;
 final  double temperature;
 final  RSErrors1 errors;

/// Create a copy of RSState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RSStateResponseCopyWith<RSStateResponse> get copyWith => _$RSStateResponseCopyWithImpl<RSStateResponse>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RSStateResponse&&(identical(other.hostId, hostId) || other.hostId == hostId)&&(identical(other.canId, canId) || other.canId == canId)&&(identical(other.status, status) || other.status == status)&&(identical(other.position, position) || other.position == position)&&(identical(other.velocity, velocity) || other.velocity == velocity)&&(identical(other.torque, torque) || other.torque == torque)&&(identical(other.temperature, temperature) || other.temperature == temperature)&&(identical(other.errors, errors) || other.errors == errors));
}


@override
int get hashCode => Object.hash(runtimeType,hostId,canId,status,position,velocity,torque,temperature,errors);

@override
String toString() {
  return 'RSState.response(hostId: $hostId, canId: $canId, status: $status, position: $position, velocity: $velocity, torque: $torque, temperature: $temperature, errors: $errors)';
}


}

/// @nodoc
abstract mixin class $RSStateResponseCopyWith<$Res> implements $RSStateCopyWith<$Res> {
  factory $RSStateResponseCopyWith(RSStateResponse value, $Res Function(RSStateResponse) _then) = _$RSStateResponseCopyWithImpl;
@override @useResult
$Res call({
 int hostId, int canId, RSStatus status, double position, double velocity, double torque, double temperature, RSErrors1 errors
});




}
/// @nodoc
class _$RSStateResponseCopyWithImpl<$Res>
    implements $RSStateResponseCopyWith<$Res> {
  _$RSStateResponseCopyWithImpl(this._self, this._then);

  final RSStateResponse _self;
  final $Res Function(RSStateResponse) _then;

/// Create a copy of RSState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? hostId = null,Object? canId = null,Object? status = null,Object? position = null,Object? velocity = null,Object? torque = null,Object? temperature = null,Object? errors = null,}) {
  return _then(RSStateResponse(
hostId: null == hostId ? _self.hostId : hostId // ignore: cast_nullable_to_non_nullable
as int,canId: null == canId ? _self.canId : canId // ignore: cast_nullable_to_non_nullable
as int,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as RSStatus,position: null == position ? _self.position : position // ignore: cast_nullable_to_non_nullable
as double,velocity: null == velocity ? _self.velocity : velocity // ignore: cast_nullable_to_non_nullable
as double,torque: null == torque ? _self.torque : torque // ignore: cast_nullable_to_non_nullable
as double,temperature: null == temperature ? _self.temperature : temperature // ignore: cast_nullable_to_non_nullable
as double,errors: null == errors ? _self.errors : errors // ignore: cast_nullable_to_non_nullable
as RSErrors1,
  ));
}


}

/// @nodoc


class RSStateReport extends RSState {
   RSStateReport({required this.hostId, required this.canId, required this.status, required this.position, required this.velocity, required this.torque, required this.temperature, required this.errors}): super._();
  

 final  int hostId;
@override final  int canId;
 final  RSStatus status;
 final  double position;
 final  double velocity;
 final  double torque;
 final  double temperature;
 final  RSErrors1 errors;

/// Create a copy of RSState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RSStateReportCopyWith<RSStateReport> get copyWith => _$RSStateReportCopyWithImpl<RSStateReport>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RSStateReport&&(identical(other.hostId, hostId) || other.hostId == hostId)&&(identical(other.canId, canId) || other.canId == canId)&&(identical(other.status, status) || other.status == status)&&(identical(other.position, position) || other.position == position)&&(identical(other.velocity, velocity) || other.velocity == velocity)&&(identical(other.torque, torque) || other.torque == torque)&&(identical(other.temperature, temperature) || other.temperature == temperature)&&(identical(other.errors, errors) || other.errors == errors));
}


@override
int get hashCode => Object.hash(runtimeType,hostId,canId,status,position,velocity,torque,temperature,errors);

@override
String toString() {
  return 'RSState.report(hostId: $hostId, canId: $canId, status: $status, position: $position, velocity: $velocity, torque: $torque, temperature: $temperature, errors: $errors)';
}


}

/// @nodoc
abstract mixin class $RSStateReportCopyWith<$Res> implements $RSStateCopyWith<$Res> {
  factory $RSStateReportCopyWith(RSStateReport value, $Res Function(RSStateReport) _then) = _$RSStateReportCopyWithImpl;
@override @useResult
$Res call({
 int hostId, int canId, RSStatus status, double position, double velocity, double torque, double temperature, RSErrors1 errors
});




}
/// @nodoc
class _$RSStateReportCopyWithImpl<$Res>
    implements $RSStateReportCopyWith<$Res> {
  _$RSStateReportCopyWithImpl(this._self, this._then);

  final RSStateReport _self;
  final $Res Function(RSStateReport) _then;

/// Create a copy of RSState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? hostId = null,Object? canId = null,Object? status = null,Object? position = null,Object? velocity = null,Object? torque = null,Object? temperature = null,Object? errors = null,}) {
  return _then(RSStateReport(
hostId: null == hostId ? _self.hostId : hostId // ignore: cast_nullable_to_non_nullable
as int,canId: null == canId ? _self.canId : canId // ignore: cast_nullable_to_non_nullable
as int,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as RSStatus,position: null == position ? _self.position : position // ignore: cast_nullable_to_non_nullable
as double,velocity: null == velocity ? _self.velocity : velocity // ignore: cast_nullable_to_non_nullable
as double,torque: null == torque ? _self.torque : torque // ignore: cast_nullable_to_non_nullable
as double,temperature: null == temperature ? _self.temperature : temperature // ignore: cast_nullable_to_non_nullable
as double,errors: null == errors ? _self.errors : errors // ignore: cast_nullable_to_non_nullable
as RSErrors1,
  ));
}


}

/// @nodoc


class RSStateGetter extends RSState {
   RSStateGetter({required this.hostId, required this.canId, this.getter}): super._();
  

 final  int hostId;
@override final  int canId;
 final  RSGetter? getter;

/// Create a copy of RSState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RSStateGetterCopyWith<RSStateGetter> get copyWith => _$RSStateGetterCopyWithImpl<RSStateGetter>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RSStateGetter&&(identical(other.hostId, hostId) || other.hostId == hostId)&&(identical(other.canId, canId) || other.canId == canId)&&(identical(other.getter, getter) || other.getter == getter));
}


@override
int get hashCode => Object.hash(runtimeType,hostId,canId,getter);

@override
String toString() {
  return 'RSState.getter(hostId: $hostId, canId: $canId, getter: $getter)';
}


}

/// @nodoc
abstract mixin class $RSStateGetterCopyWith<$Res> implements $RSStateCopyWith<$Res> {
  factory $RSStateGetterCopyWith(RSStateGetter value, $Res Function(RSStateGetter) _then) = _$RSStateGetterCopyWithImpl;
@override @useResult
$Res call({
 int hostId, int canId, RSGetter? getter
});


$RSGetterCopyWith<$Res>? get getter;

}
/// @nodoc
class _$RSStateGetterCopyWithImpl<$Res>
    implements $RSStateGetterCopyWith<$Res> {
  _$RSStateGetterCopyWithImpl(this._self, this._then);

  final RSStateGetter _self;
  final $Res Function(RSStateGetter) _then;

/// Create a copy of RSState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? hostId = null,Object? canId = null,Object? getter = freezed,}) {
  return _then(RSStateGetter(
hostId: null == hostId ? _self.hostId : hostId // ignore: cast_nullable_to_non_nullable
as int,canId: null == canId ? _self.canId : canId // ignore: cast_nullable_to_non_nullable
as int,getter: freezed == getter ? _self.getter : getter // ignore: cast_nullable_to_non_nullable
as RSGetter?,
  ));
}

/// Create a copy of RSState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$RSGetterCopyWith<$Res>? get getter {
    if (_self.getter == null) {
    return null;
  }

  return $RSGetterCopyWith<$Res>(_self.getter!, (value) {
    return _then(_self.copyWith(getter: value));
  });
}
}

/// @nodoc


class RSStateError extends RSState {
   RSStateError({required this.hostId, required this.canId, required this.errors}): super._();
  

 final  int hostId;
@override final  int canId;
 final  RSErrors2 errors;

/// Create a copy of RSState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RSStateErrorCopyWith<RSStateError> get copyWith => _$RSStateErrorCopyWithImpl<RSStateError>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RSStateError&&(identical(other.hostId, hostId) || other.hostId == hostId)&&(identical(other.canId, canId) || other.canId == canId)&&(identical(other.errors, errors) || other.errors == errors));
}


@override
int get hashCode => Object.hash(runtimeType,hostId,canId,errors);

@override
String toString() {
  return 'RSState.error(hostId: $hostId, canId: $canId, errors: $errors)';
}


}

/// @nodoc
abstract mixin class $RSStateErrorCopyWith<$Res> implements $RSStateCopyWith<$Res> {
  factory $RSStateErrorCopyWith(RSStateError value, $Res Function(RSStateError) _then) = _$RSStateErrorCopyWithImpl;
@override @useResult
$Res call({
 int hostId, int canId, RSErrors2 errors
});




}
/// @nodoc
class _$RSStateErrorCopyWithImpl<$Res>
    implements $RSStateErrorCopyWith<$Res> {
  _$RSStateErrorCopyWithImpl(this._self, this._then);

  final RSStateError _self;
  final $Res Function(RSStateError) _then;

/// Create a copy of RSState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? hostId = null,Object? canId = null,Object? errors = null,}) {
  return _then(RSStateError(
hostId: null == hostId ? _self.hostId : hostId // ignore: cast_nullable_to_non_nullable
as int,canId: null == canId ? _self.canId : canId // ignore: cast_nullable_to_non_nullable
as int,errors: null == errors ? _self.errors : errors // ignore: cast_nullable_to_non_nullable
as RSErrors2,
  ));
}


}

// dart format on
