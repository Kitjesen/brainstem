// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'event.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$DMG6620Event {

 int get canId;
/// Create a copy of DMG6620Event
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DMG6620EventCopyWith<DMG6620Event> get copyWith => _$DMG6620EventCopyWithImpl<DMG6620Event>(this as DMG6620Event, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DMG6620Event&&(identical(other.canId, canId) || other.canId == canId));
}


@override
int get hashCode => Object.hash(runtimeType,canId);

@override
String toString() {
  return 'DMG6620Event(canId: $canId)';
}


}

/// @nodoc
abstract mixin class $DMG6620EventCopyWith<$Res>  {
  factory $DMG6620EventCopyWith(DMG6620Event value, $Res Function(DMG6620Event) _then) = _$DMG6620EventCopyWithImpl;
@useResult
$Res call({
 int canId
});




}
/// @nodoc
class _$DMG6620EventCopyWithImpl<$Res>
    implements $DMG6620EventCopyWith<$Res> {
  _$DMG6620EventCopyWithImpl(this._self, this._then);

  final DMG6620Event _self;
  final $Res Function(DMG6620Event) _then;

/// Create a copy of DMG6620Event
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? canId = null,}) {
  return _then(_self.copyWith(
canId: null == canId ? _self.canId : canId // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [DMG6620Event].
extension DMG6620EventPatterns on DMG6620Event {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( DMG6620Enable value)?  enable,TResult Function( DMG6620Disable value)?  disable,TResult Function( DMG6620SetZero value)?  setZero,TResult Function( DMG6620ClearError value)?  clearError,TResult Function( DMG6620Mit value)?  mit,required TResult orElse(),}){
final _that = this;
switch (_that) {
case DMG6620Enable() when enable != null:
return enable(_that);case DMG6620Disable() when disable != null:
return disable(_that);case DMG6620SetZero() when setZero != null:
return setZero(_that);case DMG6620ClearError() when clearError != null:
return clearError(_that);case DMG6620Mit() when mit != null:
return mit(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( DMG6620Enable value)  enable,required TResult Function( DMG6620Disable value)  disable,required TResult Function( DMG6620SetZero value)  setZero,required TResult Function( DMG6620ClearError value)  clearError,required TResult Function( DMG6620Mit value)  mit,}){
final _that = this;
switch (_that) {
case DMG6620Enable():
return enable(_that);case DMG6620Disable():
return disable(_that);case DMG6620SetZero():
return setZero(_that);case DMG6620ClearError():
return clearError(_that);case DMG6620Mit():
return mit(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( DMG6620Enable value)?  enable,TResult? Function( DMG6620Disable value)?  disable,TResult? Function( DMG6620SetZero value)?  setZero,TResult? Function( DMG6620ClearError value)?  clearError,TResult? Function( DMG6620Mit value)?  mit,}){
final _that = this;
switch (_that) {
case DMG6620Enable() when enable != null:
return enable(_that);case DMG6620Disable() when disable != null:
return disable(_that);case DMG6620SetZero() when setZero != null:
return setZero(_that);case DMG6620ClearError() when clearError != null:
return clearError(_that);case DMG6620Mit() when mit != null:
return mit(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( int canId)?  enable,TResult Function( int canId)?  disable,TResult Function( int canId)?  setZero,TResult Function( int canId)?  clearError,TResult Function( int canId,  double position,  double velocity,  double torque,  double kp,  double kd)?  mit,required TResult orElse(),}) {final _that = this;
switch (_that) {
case DMG6620Enable() when enable != null:
return enable(_that.canId);case DMG6620Disable() when disable != null:
return disable(_that.canId);case DMG6620SetZero() when setZero != null:
return setZero(_that.canId);case DMG6620ClearError() when clearError != null:
return clearError(_that.canId);case DMG6620Mit() when mit != null:
return mit(_that.canId,_that.position,_that.velocity,_that.torque,_that.kp,_that.kd);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( int canId)  enable,required TResult Function( int canId)  disable,required TResult Function( int canId)  setZero,required TResult Function( int canId)  clearError,required TResult Function( int canId,  double position,  double velocity,  double torque,  double kp,  double kd)  mit,}) {final _that = this;
switch (_that) {
case DMG6620Enable():
return enable(_that.canId);case DMG6620Disable():
return disable(_that.canId);case DMG6620SetZero():
return setZero(_that.canId);case DMG6620ClearError():
return clearError(_that.canId);case DMG6620Mit():
return mit(_that.canId,_that.position,_that.velocity,_that.torque,_that.kp,_that.kd);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( int canId)?  enable,TResult? Function( int canId)?  disable,TResult? Function( int canId)?  setZero,TResult? Function( int canId)?  clearError,TResult? Function( int canId,  double position,  double velocity,  double torque,  double kp,  double kd)?  mit,}) {final _that = this;
switch (_that) {
case DMG6620Enable() when enable != null:
return enable(_that.canId);case DMG6620Disable() when disable != null:
return disable(_that.canId);case DMG6620SetZero() when setZero != null:
return setZero(_that.canId);case DMG6620ClearError() when clearError != null:
return clearError(_that.canId);case DMG6620Mit() when mit != null:
return mit(_that.canId,_that.position,_that.velocity,_that.torque,_that.kp,_that.kd);case _:
  return null;

}
}

}

/// @nodoc


class DMG6620Enable extends DMG6620Event {
   DMG6620Enable(this.canId): super._();
  

@override final  int canId;

/// Create a copy of DMG6620Event
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DMG6620EnableCopyWith<DMG6620Enable> get copyWith => _$DMG6620EnableCopyWithImpl<DMG6620Enable>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DMG6620Enable&&(identical(other.canId, canId) || other.canId == canId));
}


@override
int get hashCode => Object.hash(runtimeType,canId);

@override
String toString() {
  return 'DMG6620Event.enable(canId: $canId)';
}


}

/// @nodoc
abstract mixin class $DMG6620EnableCopyWith<$Res> implements $DMG6620EventCopyWith<$Res> {
  factory $DMG6620EnableCopyWith(DMG6620Enable value, $Res Function(DMG6620Enable) _then) = _$DMG6620EnableCopyWithImpl;
@override @useResult
$Res call({
 int canId
});




}
/// @nodoc
class _$DMG6620EnableCopyWithImpl<$Res>
    implements $DMG6620EnableCopyWith<$Res> {
  _$DMG6620EnableCopyWithImpl(this._self, this._then);

  final DMG6620Enable _self;
  final $Res Function(DMG6620Enable) _then;

/// Create a copy of DMG6620Event
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? canId = null,}) {
  return _then(DMG6620Enable(
null == canId ? _self.canId : canId // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class DMG6620Disable extends DMG6620Event {
   DMG6620Disable(this.canId): super._();
  

@override final  int canId;

/// Create a copy of DMG6620Event
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DMG6620DisableCopyWith<DMG6620Disable> get copyWith => _$DMG6620DisableCopyWithImpl<DMG6620Disable>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DMG6620Disable&&(identical(other.canId, canId) || other.canId == canId));
}


@override
int get hashCode => Object.hash(runtimeType,canId);

@override
String toString() {
  return 'DMG6620Event.disable(canId: $canId)';
}


}

/// @nodoc
abstract mixin class $DMG6620DisableCopyWith<$Res> implements $DMG6620EventCopyWith<$Res> {
  factory $DMG6620DisableCopyWith(DMG6620Disable value, $Res Function(DMG6620Disable) _then) = _$DMG6620DisableCopyWithImpl;
@override @useResult
$Res call({
 int canId
});




}
/// @nodoc
class _$DMG6620DisableCopyWithImpl<$Res>
    implements $DMG6620DisableCopyWith<$Res> {
  _$DMG6620DisableCopyWithImpl(this._self, this._then);

  final DMG6620Disable _self;
  final $Res Function(DMG6620Disable) _then;

/// Create a copy of DMG6620Event
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? canId = null,}) {
  return _then(DMG6620Disable(
null == canId ? _self.canId : canId // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class DMG6620SetZero extends DMG6620Event {
   DMG6620SetZero(this.canId): super._();
  

@override final  int canId;

/// Create a copy of DMG6620Event
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DMG6620SetZeroCopyWith<DMG6620SetZero> get copyWith => _$DMG6620SetZeroCopyWithImpl<DMG6620SetZero>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DMG6620SetZero&&(identical(other.canId, canId) || other.canId == canId));
}


@override
int get hashCode => Object.hash(runtimeType,canId);

@override
String toString() {
  return 'DMG6620Event.setZero(canId: $canId)';
}


}

/// @nodoc
abstract mixin class $DMG6620SetZeroCopyWith<$Res> implements $DMG6620EventCopyWith<$Res> {
  factory $DMG6620SetZeroCopyWith(DMG6620SetZero value, $Res Function(DMG6620SetZero) _then) = _$DMG6620SetZeroCopyWithImpl;
@override @useResult
$Res call({
 int canId
});




}
/// @nodoc
class _$DMG6620SetZeroCopyWithImpl<$Res>
    implements $DMG6620SetZeroCopyWith<$Res> {
  _$DMG6620SetZeroCopyWithImpl(this._self, this._then);

  final DMG6620SetZero _self;
  final $Res Function(DMG6620SetZero) _then;

/// Create a copy of DMG6620Event
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? canId = null,}) {
  return _then(DMG6620SetZero(
null == canId ? _self.canId : canId // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class DMG6620ClearError extends DMG6620Event {
   DMG6620ClearError(this.canId): super._();
  

@override final  int canId;

/// Create a copy of DMG6620Event
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DMG6620ClearErrorCopyWith<DMG6620ClearError> get copyWith => _$DMG6620ClearErrorCopyWithImpl<DMG6620ClearError>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DMG6620ClearError&&(identical(other.canId, canId) || other.canId == canId));
}


@override
int get hashCode => Object.hash(runtimeType,canId);

@override
String toString() {
  return 'DMG6620Event.clearError(canId: $canId)';
}


}

/// @nodoc
abstract mixin class $DMG6620ClearErrorCopyWith<$Res> implements $DMG6620EventCopyWith<$Res> {
  factory $DMG6620ClearErrorCopyWith(DMG6620ClearError value, $Res Function(DMG6620ClearError) _then) = _$DMG6620ClearErrorCopyWithImpl;
@override @useResult
$Res call({
 int canId
});




}
/// @nodoc
class _$DMG6620ClearErrorCopyWithImpl<$Res>
    implements $DMG6620ClearErrorCopyWith<$Res> {
  _$DMG6620ClearErrorCopyWithImpl(this._self, this._then);

  final DMG6620ClearError _self;
  final $Res Function(DMG6620ClearError) _then;

/// Create a copy of DMG6620Event
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? canId = null,}) {
  return _then(DMG6620ClearError(
null == canId ? _self.canId : canId // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class DMG6620Mit extends DMG6620Event {
   DMG6620Mit(this.canId, {this.position = 0.0, this.velocity = 0.0, this.torque = 0.0, this.kp = 0.0, this.kd = 0.0}): super._();
  

@override final  int canId;
@JsonKey() final  double position;
@JsonKey() final  double velocity;
@JsonKey() final  double torque;
@JsonKey() final  double kp;
@JsonKey() final  double kd;

/// Create a copy of DMG6620Event
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DMG6620MitCopyWith<DMG6620Mit> get copyWith => _$DMG6620MitCopyWithImpl<DMG6620Mit>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DMG6620Mit&&(identical(other.canId, canId) || other.canId == canId)&&(identical(other.position, position) || other.position == position)&&(identical(other.velocity, velocity) || other.velocity == velocity)&&(identical(other.torque, torque) || other.torque == torque)&&(identical(other.kp, kp) || other.kp == kp)&&(identical(other.kd, kd) || other.kd == kd));
}


@override
int get hashCode => Object.hash(runtimeType,canId,position,velocity,torque,kp,kd);

@override
String toString() {
  return 'DMG6620Event.mit(canId: $canId, position: $position, velocity: $velocity, torque: $torque, kp: $kp, kd: $kd)';
}


}

/// @nodoc
abstract mixin class $DMG6620MitCopyWith<$Res> implements $DMG6620EventCopyWith<$Res> {
  factory $DMG6620MitCopyWith(DMG6620Mit value, $Res Function(DMG6620Mit) _then) = _$DMG6620MitCopyWithImpl;
@override @useResult
$Res call({
 int canId, double position, double velocity, double torque, double kp, double kd
});




}
/// @nodoc
class _$DMG6620MitCopyWithImpl<$Res>
    implements $DMG6620MitCopyWith<$Res> {
  _$DMG6620MitCopyWithImpl(this._self, this._then);

  final DMG6620Mit _self;
  final $Res Function(DMG6620Mit) _then;

/// Create a copy of DMG6620Event
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? canId = null,Object? position = null,Object? velocity = null,Object? torque = null,Object? kp = null,Object? kd = null,}) {
  return _then(DMG6620Mit(
null == canId ? _self.canId : canId // ignore: cast_nullable_to_non_nullable
as int,position: null == position ? _self.position : position // ignore: cast_nullable_to_non_nullable
as double,velocity: null == velocity ? _self.velocity : velocity // ignore: cast_nullable_to_non_nullable
as double,torque: null == torque ? _self.torque : torque // ignore: cast_nullable_to_non_nullable
as double,kp: null == kp ? _self.kp : kp // ignore: cast_nullable_to_non_nullable
as double,kd: null == kd ? _self.kd : kd // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

// dart format on
