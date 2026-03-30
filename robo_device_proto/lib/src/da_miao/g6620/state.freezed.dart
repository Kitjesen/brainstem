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
mixin _$DMG6620State {

 int get hostId; int get canId; DMG6620Status get status; double get position; double get velocity; double get torque; double get temperatureMos; double get temperatureRotor;
/// Create a copy of DMG6620State
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DMG6620StateCopyWith<DMG6620State> get copyWith => _$DMG6620StateCopyWithImpl<DMG6620State>(this as DMG6620State, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DMG6620State&&(identical(other.hostId, hostId) || other.hostId == hostId)&&(identical(other.canId, canId) || other.canId == canId)&&(identical(other.status, status) || other.status == status)&&(identical(other.position, position) || other.position == position)&&(identical(other.velocity, velocity) || other.velocity == velocity)&&(identical(other.torque, torque) || other.torque == torque)&&(identical(other.temperatureMos, temperatureMos) || other.temperatureMos == temperatureMos)&&(identical(other.temperatureRotor, temperatureRotor) || other.temperatureRotor == temperatureRotor));
}


@override
int get hashCode => Object.hash(runtimeType,hostId,canId,status,position,velocity,torque,temperatureMos,temperatureRotor);

@override
String toString() {
  return 'DMG6620State(hostId: $hostId, canId: $canId, status: $status, position: $position, velocity: $velocity, torque: $torque, temperatureMos: $temperatureMos, temperatureRotor: $temperatureRotor)';
}


}

/// @nodoc
abstract mixin class $DMG6620StateCopyWith<$Res>  {
  factory $DMG6620StateCopyWith(DMG6620State value, $Res Function(DMG6620State) _then) = _$DMG6620StateCopyWithImpl;
@useResult
$Res call({
 int hostId, int canId, DMG6620Status status, double position, double velocity, double torque, double temperatureMos, double temperatureRotor
});




}
/// @nodoc
class _$DMG6620StateCopyWithImpl<$Res>
    implements $DMG6620StateCopyWith<$Res> {
  _$DMG6620StateCopyWithImpl(this._self, this._then);

  final DMG6620State _self;
  final $Res Function(DMG6620State) _then;

/// Create a copy of DMG6620State
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? hostId = null,Object? canId = null,Object? status = null,Object? position = null,Object? velocity = null,Object? torque = null,Object? temperatureMos = null,Object? temperatureRotor = null,}) {
  return _then(_self.copyWith(
hostId: null == hostId ? _self.hostId : hostId // ignore: cast_nullable_to_non_nullable
as int,canId: null == canId ? _self.canId : canId // ignore: cast_nullable_to_non_nullable
as int,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as DMG6620Status,position: null == position ? _self.position : position // ignore: cast_nullable_to_non_nullable
as double,velocity: null == velocity ? _self.velocity : velocity // ignore: cast_nullable_to_non_nullable
as double,torque: null == torque ? _self.torque : torque // ignore: cast_nullable_to_non_nullable
as double,temperatureMos: null == temperatureMos ? _self.temperatureMos : temperatureMos // ignore: cast_nullable_to_non_nullable
as double,temperatureRotor: null == temperatureRotor ? _self.temperatureRotor : temperatureRotor // ignore: cast_nullable_to_non_nullable
as double,
  ));
}

}


/// Adds pattern-matching-related methods to [DMG6620State].
extension DMG6620StatePatterns on DMG6620State {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _DMG6620State value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _DMG6620State() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _DMG6620State value)  $default,){
final _that = this;
switch (_that) {
case _DMG6620State():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _DMG6620State value)?  $default,){
final _that = this;
switch (_that) {
case _DMG6620State() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int hostId,  int canId,  DMG6620Status status,  double position,  double velocity,  double torque,  double temperatureMos,  double temperatureRotor)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _DMG6620State() when $default != null:
return $default(_that.hostId,_that.canId,_that.status,_that.position,_that.velocity,_that.torque,_that.temperatureMos,_that.temperatureRotor);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int hostId,  int canId,  DMG6620Status status,  double position,  double velocity,  double torque,  double temperatureMos,  double temperatureRotor)  $default,) {final _that = this;
switch (_that) {
case _DMG6620State():
return $default(_that.hostId,_that.canId,_that.status,_that.position,_that.velocity,_that.torque,_that.temperatureMos,_that.temperatureRotor);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int hostId,  int canId,  DMG6620Status status,  double position,  double velocity,  double torque,  double temperatureMos,  double temperatureRotor)?  $default,) {final _that = this;
switch (_that) {
case _DMG6620State() when $default != null:
return $default(_that.hostId,_that.canId,_that.status,_that.position,_that.velocity,_that.torque,_that.temperatureMos,_that.temperatureRotor);case _:
  return null;

}
}

}

/// @nodoc


class _DMG6620State implements DMG6620State {
   _DMG6620State({required this.hostId, required this.canId, required this.status, required this.position, required this.velocity, required this.torque, required this.temperatureMos, required this.temperatureRotor});
  

@override final  int hostId;
@override final  int canId;
@override final  DMG6620Status status;
@override final  double position;
@override final  double velocity;
@override final  double torque;
@override final  double temperatureMos;
@override final  double temperatureRotor;

/// Create a copy of DMG6620State
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$DMG6620StateCopyWith<_DMG6620State> get copyWith => __$DMG6620StateCopyWithImpl<_DMG6620State>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _DMG6620State&&(identical(other.hostId, hostId) || other.hostId == hostId)&&(identical(other.canId, canId) || other.canId == canId)&&(identical(other.status, status) || other.status == status)&&(identical(other.position, position) || other.position == position)&&(identical(other.velocity, velocity) || other.velocity == velocity)&&(identical(other.torque, torque) || other.torque == torque)&&(identical(other.temperatureMos, temperatureMos) || other.temperatureMos == temperatureMos)&&(identical(other.temperatureRotor, temperatureRotor) || other.temperatureRotor == temperatureRotor));
}


@override
int get hashCode => Object.hash(runtimeType,hostId,canId,status,position,velocity,torque,temperatureMos,temperatureRotor);

@override
String toString() {
  return 'DMG6620State(hostId: $hostId, canId: $canId, status: $status, position: $position, velocity: $velocity, torque: $torque, temperatureMos: $temperatureMos, temperatureRotor: $temperatureRotor)';
}


}

/// @nodoc
abstract mixin class _$DMG6620StateCopyWith<$Res> implements $DMG6620StateCopyWith<$Res> {
  factory _$DMG6620StateCopyWith(_DMG6620State value, $Res Function(_DMG6620State) _then) = __$DMG6620StateCopyWithImpl;
@override @useResult
$Res call({
 int hostId, int canId, DMG6620Status status, double position, double velocity, double torque, double temperatureMos, double temperatureRotor
});




}
/// @nodoc
class __$DMG6620StateCopyWithImpl<$Res>
    implements _$DMG6620StateCopyWith<$Res> {
  __$DMG6620StateCopyWithImpl(this._self, this._then);

  final _DMG6620State _self;
  final $Res Function(_DMG6620State) _then;

/// Create a copy of DMG6620State
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? hostId = null,Object? canId = null,Object? status = null,Object? position = null,Object? velocity = null,Object? torque = null,Object? temperatureMos = null,Object? temperatureRotor = null,}) {
  return _then(_DMG6620State(
hostId: null == hostId ? _self.hostId : hostId // ignore: cast_nullable_to_non_nullable
as int,canId: null == canId ? _self.canId : canId // ignore: cast_nullable_to_non_nullable
as int,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as DMG6620Status,position: null == position ? _self.position : position // ignore: cast_nullable_to_non_nullable
as double,velocity: null == velocity ? _self.velocity : velocity // ignore: cast_nullable_to_non_nullable
as double,torque: null == torque ? _self.torque : torque // ignore: cast_nullable_to_non_nullable
as double,temperatureMos: null == temperatureMos ? _self.temperatureMos : temperatureMos // ignore: cast_nullable_to_non_nullable
as double,temperatureRotor: null == temperatureRotor ? _self.temperatureRotor : temperatureRotor // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

// dart format on
