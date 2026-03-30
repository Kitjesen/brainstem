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
mixin _$Hi91State {

 HipnucStatusFlags get status; int get temperature; double get airPressure; int get timeStamp; Vector3 get acceleration; Vector3 get gyroscope; Vector3 get magneticField; double get roll; double get pitch; double get yaw; Quaternion get quaternion;
/// Create a copy of Hi91State
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$Hi91StateCopyWith<Hi91State> get copyWith => _$Hi91StateCopyWithImpl<Hi91State>(this as Hi91State, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Hi91State&&(identical(other.status, status) || other.status == status)&&(identical(other.temperature, temperature) || other.temperature == temperature)&&(identical(other.airPressure, airPressure) || other.airPressure == airPressure)&&(identical(other.timeStamp, timeStamp) || other.timeStamp == timeStamp)&&(identical(other.acceleration, acceleration) || other.acceleration == acceleration)&&(identical(other.gyroscope, gyroscope) || other.gyroscope == gyroscope)&&(identical(other.magneticField, magneticField) || other.magneticField == magneticField)&&(identical(other.roll, roll) || other.roll == roll)&&(identical(other.pitch, pitch) || other.pitch == pitch)&&(identical(other.yaw, yaw) || other.yaw == yaw)&&(identical(other.quaternion, quaternion) || other.quaternion == quaternion));
}


@override
int get hashCode => Object.hash(runtimeType,status,temperature,airPressure,timeStamp,acceleration,gyroscope,magneticField,roll,pitch,yaw,quaternion);

@override
String toString() {
  return 'Hi91State(status: $status, temperature: $temperature, airPressure: $airPressure, timeStamp: $timeStamp, acceleration: $acceleration, gyroscope: $gyroscope, magneticField: $magneticField, roll: $roll, pitch: $pitch, yaw: $yaw, quaternion: $quaternion)';
}


}

/// @nodoc
abstract mixin class $Hi91StateCopyWith<$Res>  {
  factory $Hi91StateCopyWith(Hi91State value, $Res Function(Hi91State) _then) = _$Hi91StateCopyWithImpl;
@useResult
$Res call({
 HipnucStatusFlags status, int temperature, double airPressure, int timeStamp, Vector3 acceleration, Vector3 gyroscope, Vector3 magneticField, double roll, double pitch, double yaw, Quaternion quaternion
});




}
/// @nodoc
class _$Hi91StateCopyWithImpl<$Res>
    implements $Hi91StateCopyWith<$Res> {
  _$Hi91StateCopyWithImpl(this._self, this._then);

  final Hi91State _self;
  final $Res Function(Hi91State) _then;

/// Create a copy of Hi91State
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? status = null,Object? temperature = null,Object? airPressure = null,Object? timeStamp = null,Object? acceleration = null,Object? gyroscope = null,Object? magneticField = null,Object? roll = null,Object? pitch = null,Object? yaw = null,Object? quaternion = null,}) {
  return _then(_self.copyWith(
status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as HipnucStatusFlags,temperature: null == temperature ? _self.temperature : temperature // ignore: cast_nullable_to_non_nullable
as int,airPressure: null == airPressure ? _self.airPressure : airPressure // ignore: cast_nullable_to_non_nullable
as double,timeStamp: null == timeStamp ? _self.timeStamp : timeStamp // ignore: cast_nullable_to_non_nullable
as int,acceleration: null == acceleration ? _self.acceleration : acceleration // ignore: cast_nullable_to_non_nullable
as Vector3,gyroscope: null == gyroscope ? _self.gyroscope : gyroscope // ignore: cast_nullable_to_non_nullable
as Vector3,magneticField: null == magneticField ? _self.magneticField : magneticField // ignore: cast_nullable_to_non_nullable
as Vector3,roll: null == roll ? _self.roll : roll // ignore: cast_nullable_to_non_nullable
as double,pitch: null == pitch ? _self.pitch : pitch // ignore: cast_nullable_to_non_nullable
as double,yaw: null == yaw ? _self.yaw : yaw // ignore: cast_nullable_to_non_nullable
as double,quaternion: null == quaternion ? _self.quaternion : quaternion // ignore: cast_nullable_to_non_nullable
as Quaternion,
  ));
}

}


/// Adds pattern-matching-related methods to [Hi91State].
extension Hi91StatePatterns on Hi91State {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Hi91State value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Hi91State() when $default != null:
return $default(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Hi91State value)  $default,){
final _that = this;
switch (_that) {
case _Hi91State():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Hi91State value)?  $default,){
final _that = this;
switch (_that) {
case _Hi91State() when $default != null:
return $default(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( HipnucStatusFlags status,  int temperature,  double airPressure,  int timeStamp,  Vector3 acceleration,  Vector3 gyroscope,  Vector3 magneticField,  double roll,  double pitch,  double yaw,  Quaternion quaternion)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Hi91State() when $default != null:
return $default(_that.status,_that.temperature,_that.airPressure,_that.timeStamp,_that.acceleration,_that.gyroscope,_that.magneticField,_that.roll,_that.pitch,_that.yaw,_that.quaternion);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( HipnucStatusFlags status,  int temperature,  double airPressure,  int timeStamp,  Vector3 acceleration,  Vector3 gyroscope,  Vector3 magneticField,  double roll,  double pitch,  double yaw,  Quaternion quaternion)  $default,) {final _that = this;
switch (_that) {
case _Hi91State():
return $default(_that.status,_that.temperature,_that.airPressure,_that.timeStamp,_that.acceleration,_that.gyroscope,_that.magneticField,_that.roll,_that.pitch,_that.yaw,_that.quaternion);case _:
  throw StateError('Unexpected subclass');

}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( HipnucStatusFlags status,  int temperature,  double airPressure,  int timeStamp,  Vector3 acceleration,  Vector3 gyroscope,  Vector3 magneticField,  double roll,  double pitch,  double yaw,  Quaternion quaternion)?  $default,) {final _that = this;
switch (_that) {
case _Hi91State() when $default != null:
return $default(_that.status,_that.temperature,_that.airPressure,_that.timeStamp,_that.acceleration,_that.gyroscope,_that.magneticField,_that.roll,_that.pitch,_that.yaw,_that.quaternion);case _:
  return null;

}
}

}

/// @nodoc


class _Hi91State implements Hi91State {
   _Hi91State({required this.status, required this.temperature, required this.airPressure, required this.timeStamp, required this.acceleration, required this.gyroscope, required this.magneticField, required this.roll, required this.pitch, required this.yaw, required this.quaternion});
  

@override final  HipnucStatusFlags status;
@override final  int temperature;
@override final  double airPressure;
@override final  int timeStamp;
@override final  Vector3 acceleration;
@override final  Vector3 gyroscope;
@override final  Vector3 magneticField;
@override final  double roll;
@override final  double pitch;
@override final  double yaw;
@override final  Quaternion quaternion;

/// Create a copy of Hi91State
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$Hi91StateCopyWith<_Hi91State> get copyWith => __$Hi91StateCopyWithImpl<_Hi91State>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Hi91State&&(identical(other.status, status) || other.status == status)&&(identical(other.temperature, temperature) || other.temperature == temperature)&&(identical(other.airPressure, airPressure) || other.airPressure == airPressure)&&(identical(other.timeStamp, timeStamp) || other.timeStamp == timeStamp)&&(identical(other.acceleration, acceleration) || other.acceleration == acceleration)&&(identical(other.gyroscope, gyroscope) || other.gyroscope == gyroscope)&&(identical(other.magneticField, magneticField) || other.magneticField == magneticField)&&(identical(other.roll, roll) || other.roll == roll)&&(identical(other.pitch, pitch) || other.pitch == pitch)&&(identical(other.yaw, yaw) || other.yaw == yaw)&&(identical(other.quaternion, quaternion) || other.quaternion == quaternion));
}


@override
int get hashCode => Object.hash(runtimeType,status,temperature,airPressure,timeStamp,acceleration,gyroscope,magneticField,roll,pitch,yaw,quaternion);

@override
String toString() {
  return 'Hi91State(status: $status, temperature: $temperature, airPressure: $airPressure, timeStamp: $timeStamp, acceleration: $acceleration, gyroscope: $gyroscope, magneticField: $magneticField, roll: $roll, pitch: $pitch, yaw: $yaw, quaternion: $quaternion)';
}


}

/// @nodoc
abstract mixin class _$Hi91StateCopyWith<$Res> implements $Hi91StateCopyWith<$Res> {
  factory _$Hi91StateCopyWith(_Hi91State value, $Res Function(_Hi91State) _then) = __$Hi91StateCopyWithImpl;
@override @useResult
$Res call({
 HipnucStatusFlags status, int temperature, double airPressure, int timeStamp, Vector3 acceleration, Vector3 gyroscope, Vector3 magneticField, double roll, double pitch, double yaw, Quaternion quaternion
});




}
/// @nodoc
class __$Hi91StateCopyWithImpl<$Res>
    implements _$Hi91StateCopyWith<$Res> {
  __$Hi91StateCopyWithImpl(this._self, this._then);

  final _Hi91State _self;
  final $Res Function(_Hi91State) _then;

/// Create a copy of Hi91State
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? status = null,Object? temperature = null,Object? airPressure = null,Object? timeStamp = null,Object? acceleration = null,Object? gyroscope = null,Object? magneticField = null,Object? roll = null,Object? pitch = null,Object? yaw = null,Object? quaternion = null,}) {
  return _then(_Hi91State(
status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as HipnucStatusFlags,temperature: null == temperature ? _self.temperature : temperature // ignore: cast_nullable_to_non_nullable
as int,airPressure: null == airPressure ? _self.airPressure : airPressure // ignore: cast_nullable_to_non_nullable
as double,timeStamp: null == timeStamp ? _self.timeStamp : timeStamp // ignore: cast_nullable_to_non_nullable
as int,acceleration: null == acceleration ? _self.acceleration : acceleration // ignore: cast_nullable_to_non_nullable
as Vector3,gyroscope: null == gyroscope ? _self.gyroscope : gyroscope // ignore: cast_nullable_to_non_nullable
as Vector3,magneticField: null == magneticField ? _self.magneticField : magneticField // ignore: cast_nullable_to_non_nullable
as Vector3,roll: null == roll ? _self.roll : roll // ignore: cast_nullable_to_non_nullable
as double,pitch: null == pitch ? _self.pitch : pitch // ignore: cast_nullable_to_non_nullable
as double,yaw: null == yaw ? _self.yaw : yaw // ignore: cast_nullable_to_non_nullable
as double,quaternion: null == quaternion ? _self.quaternion : quaternion // ignore: cast_nullable_to_non_nullable
as Quaternion,
  ));
}


}

// dart format on
