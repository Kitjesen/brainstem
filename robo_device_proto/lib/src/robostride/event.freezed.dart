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
mixin _$RSEvent {

 int get canId;
/// Create a copy of RSEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RSEventCopyWith<RSEvent> get copyWith => _$RSEventCopyWithImpl<RSEvent>(this as RSEvent, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RSEvent&&(identical(other.canId, canId) || other.canId == canId));
}


@override
int get hashCode => Object.hash(runtimeType,canId);

@override
String toString() {
  return 'RSEvent(canId: $canId)';
}


}

/// @nodoc
abstract mixin class $RSEventCopyWith<$Res>  {
  factory $RSEventCopyWith(RSEvent value, $Res Function(RSEvent) _then) = _$RSEventCopyWithImpl;
@useResult
$Res call({
 int canId
});




}
/// @nodoc
class _$RSEventCopyWithImpl<$Res>
    implements $RSEventCopyWith<$Res> {
  _$RSEventCopyWithImpl(this._self, this._then);

  final RSEvent _self;
  final $Res Function(RSEvent) _then;

/// Create a copy of RSEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? canId = null,}) {
  return _then(_self.copyWith(
canId: null == canId ? _self.canId : canId // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [RSEvent].
extension RSEventPatterns on RSEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( RSEventGetDeviceId value)?  getDeviceId,TResult Function( RSEventControl value)?  control,TResult Function( RSEventEnable value)?  enable,TResult Function( RSEventDisable value)?  disable,TResult Function( RSEventCalibration value)?  calibration,TResult Function( RSEventSetZero value)?  setZero,TResult Function( RSEventSetId value)?  setId,TResult Function( RSEventGet value)?  get,TResult Function( RSEventSet value)?  set,TResult Function( RSEventSaveData value)?  saveData,TResult Function( RSEventSetBaudRate value)?  setBaudRate,TResult Function( RSEventSetReporting value)?  setReporting,TResult Function( RSEventSetProtocol value)?  setProtocol,required TResult orElse(),}){
final _that = this;
switch (_that) {
case RSEventGetDeviceId() when getDeviceId != null:
return getDeviceId(_that);case RSEventControl() when control != null:
return control(_that);case RSEventEnable() when enable != null:
return enable(_that);case RSEventDisable() when disable != null:
return disable(_that);case RSEventCalibration() when calibration != null:
return calibration(_that);case RSEventSetZero() when setZero != null:
return setZero(_that);case RSEventSetId() when setId != null:
return setId(_that);case RSEventGet() when get != null:
return get(_that);case RSEventSet() when set != null:
return set(_that);case RSEventSaveData() when saveData != null:
return saveData(_that);case RSEventSetBaudRate() when setBaudRate != null:
return setBaudRate(_that);case RSEventSetReporting() when setReporting != null:
return setReporting(_that);case RSEventSetProtocol() when setProtocol != null:
return setProtocol(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( RSEventGetDeviceId value)  getDeviceId,required TResult Function( RSEventControl value)  control,required TResult Function( RSEventEnable value)  enable,required TResult Function( RSEventDisable value)  disable,required TResult Function( RSEventCalibration value)  calibration,required TResult Function( RSEventSetZero value)  setZero,required TResult Function( RSEventSetId value)  setId,required TResult Function( RSEventGet value)  get,required TResult Function( RSEventSet value)  set,required TResult Function( RSEventSaveData value)  saveData,required TResult Function( RSEventSetBaudRate value)  setBaudRate,required TResult Function( RSEventSetReporting value)  setReporting,required TResult Function( RSEventSetProtocol value)  setProtocol,}){
final _that = this;
switch (_that) {
case RSEventGetDeviceId():
return getDeviceId(_that);case RSEventControl():
return control(_that);case RSEventEnable():
return enable(_that);case RSEventDisable():
return disable(_that);case RSEventCalibration():
return calibration(_that);case RSEventSetZero():
return setZero(_that);case RSEventSetId():
return setId(_that);case RSEventGet():
return get(_that);case RSEventSet():
return set(_that);case RSEventSaveData():
return saveData(_that);case RSEventSetBaudRate():
return setBaudRate(_that);case RSEventSetReporting():
return setReporting(_that);case RSEventSetProtocol():
return setProtocol(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( RSEventGetDeviceId value)?  getDeviceId,TResult? Function( RSEventControl value)?  control,TResult? Function( RSEventEnable value)?  enable,TResult? Function( RSEventDisable value)?  disable,TResult? Function( RSEventCalibration value)?  calibration,TResult? Function( RSEventSetZero value)?  setZero,TResult? Function( RSEventSetId value)?  setId,TResult? Function( RSEventGet value)?  get,TResult? Function( RSEventSet value)?  set,TResult? Function( RSEventSaveData value)?  saveData,TResult? Function( RSEventSetBaudRate value)?  setBaudRate,TResult? Function( RSEventSetReporting value)?  setReporting,TResult? Function( RSEventSetProtocol value)?  setProtocol,}){
final _that = this;
switch (_that) {
case RSEventGetDeviceId() when getDeviceId != null:
return getDeviceId(_that);case RSEventControl() when control != null:
return control(_that);case RSEventEnable() when enable != null:
return enable(_that);case RSEventDisable() when disable != null:
return disable(_that);case RSEventCalibration() when calibration != null:
return calibration(_that);case RSEventSetZero() when setZero != null:
return setZero(_that);case RSEventSetId() when setId != null:
return setId(_that);case RSEventGet() when get != null:
return get(_that);case RSEventSet() when set != null:
return set(_that);case RSEventSaveData() when saveData != null:
return saveData(_that);case RSEventSetBaudRate() when setBaudRate != null:
return setBaudRate(_that);case RSEventSetReporting() when setReporting != null:
return setReporting(_that);case RSEventSetProtocol() when setProtocol != null:
return setProtocol(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( int canId,  int hostId)?  getDeviceId,TResult Function( int canId,  double torque,  double position,  double velocity,  double kp,  double kd)?  control,TResult Function( int canId,  int hostId)?  enable,TResult Function( int canId,  int hostId,  bool clearErrors)?  disable,TResult Function( int canId)?  calibration,TResult Function( int canId,  int hostId)?  setZero,TResult Function( int canId,  int hostId,  int newId)?  setId,TResult Function( int canId,  int hostId,  RSKey key)?  get,TResult Function( int canId,  int hostId,  RSSetter setter)?  set,TResult Function( int canId,  int hostId)?  saveData,TResult Function( int canId,  int hostId,  RSBaudRate baudRate)?  setBaudRate,TResult Function( int canId,  int hostId,  bool enable)?  setReporting,TResult Function( int canId,  int hostId,  RSProtocol protocol)?  setProtocol,required TResult orElse(),}) {final _that = this;
switch (_that) {
case RSEventGetDeviceId() when getDeviceId != null:
return getDeviceId(_that.canId,_that.hostId);case RSEventControl() when control != null:
return control(_that.canId,_that.torque,_that.position,_that.velocity,_that.kp,_that.kd);case RSEventEnable() when enable != null:
return enable(_that.canId,_that.hostId);case RSEventDisable() when disable != null:
return disable(_that.canId,_that.hostId,_that.clearErrors);case RSEventCalibration() when calibration != null:
return calibration(_that.canId);case RSEventSetZero() when setZero != null:
return setZero(_that.canId,_that.hostId);case RSEventSetId() when setId != null:
return setId(_that.canId,_that.hostId,_that.newId);case RSEventGet() when get != null:
return get(_that.canId,_that.hostId,_that.key);case RSEventSet() when set != null:
return set(_that.canId,_that.hostId,_that.setter);case RSEventSaveData() when saveData != null:
return saveData(_that.canId,_that.hostId);case RSEventSetBaudRate() when setBaudRate != null:
return setBaudRate(_that.canId,_that.hostId,_that.baudRate);case RSEventSetReporting() when setReporting != null:
return setReporting(_that.canId,_that.hostId,_that.enable);case RSEventSetProtocol() when setProtocol != null:
return setProtocol(_that.canId,_that.hostId,_that.protocol);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( int canId,  int hostId)  getDeviceId,required TResult Function( int canId,  double torque,  double position,  double velocity,  double kp,  double kd)  control,required TResult Function( int canId,  int hostId)  enable,required TResult Function( int canId,  int hostId,  bool clearErrors)  disable,required TResult Function( int canId)  calibration,required TResult Function( int canId,  int hostId)  setZero,required TResult Function( int canId,  int hostId,  int newId)  setId,required TResult Function( int canId,  int hostId,  RSKey key)  get,required TResult Function( int canId,  int hostId,  RSSetter setter)  set,required TResult Function( int canId,  int hostId)  saveData,required TResult Function( int canId,  int hostId,  RSBaudRate baudRate)  setBaudRate,required TResult Function( int canId,  int hostId,  bool enable)  setReporting,required TResult Function( int canId,  int hostId,  RSProtocol protocol)  setProtocol,}) {final _that = this;
switch (_that) {
case RSEventGetDeviceId():
return getDeviceId(_that.canId,_that.hostId);case RSEventControl():
return control(_that.canId,_that.torque,_that.position,_that.velocity,_that.kp,_that.kd);case RSEventEnable():
return enable(_that.canId,_that.hostId);case RSEventDisable():
return disable(_that.canId,_that.hostId,_that.clearErrors);case RSEventCalibration():
return calibration(_that.canId);case RSEventSetZero():
return setZero(_that.canId,_that.hostId);case RSEventSetId():
return setId(_that.canId,_that.hostId,_that.newId);case RSEventGet():
return get(_that.canId,_that.hostId,_that.key);case RSEventSet():
return set(_that.canId,_that.hostId,_that.setter);case RSEventSaveData():
return saveData(_that.canId,_that.hostId);case RSEventSetBaudRate():
return setBaudRate(_that.canId,_that.hostId,_that.baudRate);case RSEventSetReporting():
return setReporting(_that.canId,_that.hostId,_that.enable);case RSEventSetProtocol():
return setProtocol(_that.canId,_that.hostId,_that.protocol);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( int canId,  int hostId)?  getDeviceId,TResult? Function( int canId,  double torque,  double position,  double velocity,  double kp,  double kd)?  control,TResult? Function( int canId,  int hostId)?  enable,TResult? Function( int canId,  int hostId,  bool clearErrors)?  disable,TResult? Function( int canId)?  calibration,TResult? Function( int canId,  int hostId)?  setZero,TResult? Function( int canId,  int hostId,  int newId)?  setId,TResult? Function( int canId,  int hostId,  RSKey key)?  get,TResult? Function( int canId,  int hostId,  RSSetter setter)?  set,TResult? Function( int canId,  int hostId)?  saveData,TResult? Function( int canId,  int hostId,  RSBaudRate baudRate)?  setBaudRate,TResult? Function( int canId,  int hostId,  bool enable)?  setReporting,TResult? Function( int canId,  int hostId,  RSProtocol protocol)?  setProtocol,}) {final _that = this;
switch (_that) {
case RSEventGetDeviceId() when getDeviceId != null:
return getDeviceId(_that.canId,_that.hostId);case RSEventControl() when control != null:
return control(_that.canId,_that.torque,_that.position,_that.velocity,_that.kp,_that.kd);case RSEventEnable() when enable != null:
return enable(_that.canId,_that.hostId);case RSEventDisable() when disable != null:
return disable(_that.canId,_that.hostId,_that.clearErrors);case RSEventCalibration() when calibration != null:
return calibration(_that.canId);case RSEventSetZero() when setZero != null:
return setZero(_that.canId,_that.hostId);case RSEventSetId() when setId != null:
return setId(_that.canId,_that.hostId,_that.newId);case RSEventGet() when get != null:
return get(_that.canId,_that.hostId,_that.key);case RSEventSet() when set != null:
return set(_that.canId,_that.hostId,_that.setter);case RSEventSaveData() when saveData != null:
return saveData(_that.canId,_that.hostId);case RSEventSetBaudRate() when setBaudRate != null:
return setBaudRate(_that.canId,_that.hostId,_that.baudRate);case RSEventSetReporting() when setReporting != null:
return setReporting(_that.canId,_that.hostId,_that.enable);case RSEventSetProtocol() when setProtocol != null:
return setProtocol(_that.canId,_that.hostId,_that.protocol);case _:
  return null;

}
}

}

/// @nodoc


class RSEventGetDeviceId extends RSEvent {
   RSEventGetDeviceId(this.canId, {this.hostId = _defaultHostId}): super._();
  

@override final  int canId;
@JsonKey() final  int hostId;

/// Create a copy of RSEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RSEventGetDeviceIdCopyWith<RSEventGetDeviceId> get copyWith => _$RSEventGetDeviceIdCopyWithImpl<RSEventGetDeviceId>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RSEventGetDeviceId&&(identical(other.canId, canId) || other.canId == canId)&&(identical(other.hostId, hostId) || other.hostId == hostId));
}


@override
int get hashCode => Object.hash(runtimeType,canId,hostId);

@override
String toString() {
  return 'RSEvent.getDeviceId(canId: $canId, hostId: $hostId)';
}


}

/// @nodoc
abstract mixin class $RSEventGetDeviceIdCopyWith<$Res> implements $RSEventCopyWith<$Res> {
  factory $RSEventGetDeviceIdCopyWith(RSEventGetDeviceId value, $Res Function(RSEventGetDeviceId) _then) = _$RSEventGetDeviceIdCopyWithImpl;
@override @useResult
$Res call({
 int canId, int hostId
});




}
/// @nodoc
class _$RSEventGetDeviceIdCopyWithImpl<$Res>
    implements $RSEventGetDeviceIdCopyWith<$Res> {
  _$RSEventGetDeviceIdCopyWithImpl(this._self, this._then);

  final RSEventGetDeviceId _self;
  final $Res Function(RSEventGetDeviceId) _then;

/// Create a copy of RSEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? canId = null,Object? hostId = null,}) {
  return _then(RSEventGetDeviceId(
null == canId ? _self.canId : canId // ignore: cast_nullable_to_non_nullable
as int,hostId: null == hostId ? _self.hostId : hostId // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class RSEventControl extends RSEvent {
   RSEventControl(this.canId, {this.torque = 0.0, this.position = 0.0, this.velocity = 0.0, this.kp = 0.0, this.kd = 0.0}): super._();
  

@override final  int canId;
@JsonKey() final  double torque;
// (-120Nm~120Nm)
@JsonKey() final  double position;
// (-12.57f~12.57f)
@JsonKey() final  double velocity;
// (-15rad/s~15rad/s)
@JsonKey() final  double kp;
// (0.0~5000.0)
@JsonKey() final  double kd;

/// Create a copy of RSEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RSEventControlCopyWith<RSEventControl> get copyWith => _$RSEventControlCopyWithImpl<RSEventControl>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RSEventControl&&(identical(other.canId, canId) || other.canId == canId)&&(identical(other.torque, torque) || other.torque == torque)&&(identical(other.position, position) || other.position == position)&&(identical(other.velocity, velocity) || other.velocity == velocity)&&(identical(other.kp, kp) || other.kp == kp)&&(identical(other.kd, kd) || other.kd == kd));
}


@override
int get hashCode => Object.hash(runtimeType,canId,torque,position,velocity,kp,kd);

@override
String toString() {
  return 'RSEvent.control(canId: $canId, torque: $torque, position: $position, velocity: $velocity, kp: $kp, kd: $kd)';
}


}

/// @nodoc
abstract mixin class $RSEventControlCopyWith<$Res> implements $RSEventCopyWith<$Res> {
  factory $RSEventControlCopyWith(RSEventControl value, $Res Function(RSEventControl) _then) = _$RSEventControlCopyWithImpl;
@override @useResult
$Res call({
 int canId, double torque, double position, double velocity, double kp, double kd
});




}
/// @nodoc
class _$RSEventControlCopyWithImpl<$Res>
    implements $RSEventControlCopyWith<$Res> {
  _$RSEventControlCopyWithImpl(this._self, this._then);

  final RSEventControl _self;
  final $Res Function(RSEventControl) _then;

/// Create a copy of RSEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? canId = null,Object? torque = null,Object? position = null,Object? velocity = null,Object? kp = null,Object? kd = null,}) {
  return _then(RSEventControl(
null == canId ? _self.canId : canId // ignore: cast_nullable_to_non_nullable
as int,torque: null == torque ? _self.torque : torque // ignore: cast_nullable_to_non_nullable
as double,position: null == position ? _self.position : position // ignore: cast_nullable_to_non_nullable
as double,velocity: null == velocity ? _self.velocity : velocity // ignore: cast_nullable_to_non_nullable
as double,kp: null == kp ? _self.kp : kp // ignore: cast_nullable_to_non_nullable
as double,kd: null == kd ? _self.kd : kd // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

/// @nodoc


class RSEventEnable extends RSEvent {
   RSEventEnable(this.canId, {this.hostId = _defaultHostId}): super._();
  

@override final  int canId;
@JsonKey() final  int hostId;

/// Create a copy of RSEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RSEventEnableCopyWith<RSEventEnable> get copyWith => _$RSEventEnableCopyWithImpl<RSEventEnable>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RSEventEnable&&(identical(other.canId, canId) || other.canId == canId)&&(identical(other.hostId, hostId) || other.hostId == hostId));
}


@override
int get hashCode => Object.hash(runtimeType,canId,hostId);

@override
String toString() {
  return 'RSEvent.enable(canId: $canId, hostId: $hostId)';
}


}

/// @nodoc
abstract mixin class $RSEventEnableCopyWith<$Res> implements $RSEventCopyWith<$Res> {
  factory $RSEventEnableCopyWith(RSEventEnable value, $Res Function(RSEventEnable) _then) = _$RSEventEnableCopyWithImpl;
@override @useResult
$Res call({
 int canId, int hostId
});




}
/// @nodoc
class _$RSEventEnableCopyWithImpl<$Res>
    implements $RSEventEnableCopyWith<$Res> {
  _$RSEventEnableCopyWithImpl(this._self, this._then);

  final RSEventEnable _self;
  final $Res Function(RSEventEnable) _then;

/// Create a copy of RSEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? canId = null,Object? hostId = null,}) {
  return _then(RSEventEnable(
null == canId ? _self.canId : canId // ignore: cast_nullable_to_non_nullable
as int,hostId: null == hostId ? _self.hostId : hostId // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class RSEventDisable extends RSEvent {
   RSEventDisable(this.canId, {this.hostId = _defaultHostId, this.clearErrors = false}): super._();
  

@override final  int canId;
@JsonKey() final  int hostId;
@JsonKey() final  bool clearErrors;

/// Create a copy of RSEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RSEventDisableCopyWith<RSEventDisable> get copyWith => _$RSEventDisableCopyWithImpl<RSEventDisable>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RSEventDisable&&(identical(other.canId, canId) || other.canId == canId)&&(identical(other.hostId, hostId) || other.hostId == hostId)&&(identical(other.clearErrors, clearErrors) || other.clearErrors == clearErrors));
}


@override
int get hashCode => Object.hash(runtimeType,canId,hostId,clearErrors);

@override
String toString() {
  return 'RSEvent.disable(canId: $canId, hostId: $hostId, clearErrors: $clearErrors)';
}


}

/// @nodoc
abstract mixin class $RSEventDisableCopyWith<$Res> implements $RSEventCopyWith<$Res> {
  factory $RSEventDisableCopyWith(RSEventDisable value, $Res Function(RSEventDisable) _then) = _$RSEventDisableCopyWithImpl;
@override @useResult
$Res call({
 int canId, int hostId, bool clearErrors
});




}
/// @nodoc
class _$RSEventDisableCopyWithImpl<$Res>
    implements $RSEventDisableCopyWith<$Res> {
  _$RSEventDisableCopyWithImpl(this._self, this._then);

  final RSEventDisable _self;
  final $Res Function(RSEventDisable) _then;

/// Create a copy of RSEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? canId = null,Object? hostId = null,Object? clearErrors = null,}) {
  return _then(RSEventDisable(
null == canId ? _self.canId : canId // ignore: cast_nullable_to_non_nullable
as int,hostId: null == hostId ? _self.hostId : hostId // ignore: cast_nullable_to_non_nullable
as int,clearErrors: null == clearErrors ? _self.clearErrors : clearErrors // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc


class RSEventCalibration extends RSEvent {
   RSEventCalibration(this.canId): super._();
  

@override final  int canId;

/// Create a copy of RSEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RSEventCalibrationCopyWith<RSEventCalibration> get copyWith => _$RSEventCalibrationCopyWithImpl<RSEventCalibration>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RSEventCalibration&&(identical(other.canId, canId) || other.canId == canId));
}


@override
int get hashCode => Object.hash(runtimeType,canId);

@override
String toString() {
  return 'RSEvent.calibration(canId: $canId)';
}


}

/// @nodoc
abstract mixin class $RSEventCalibrationCopyWith<$Res> implements $RSEventCopyWith<$Res> {
  factory $RSEventCalibrationCopyWith(RSEventCalibration value, $Res Function(RSEventCalibration) _then) = _$RSEventCalibrationCopyWithImpl;
@override @useResult
$Res call({
 int canId
});




}
/// @nodoc
class _$RSEventCalibrationCopyWithImpl<$Res>
    implements $RSEventCalibrationCopyWith<$Res> {
  _$RSEventCalibrationCopyWithImpl(this._self, this._then);

  final RSEventCalibration _self;
  final $Res Function(RSEventCalibration) _then;

/// Create a copy of RSEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? canId = null,}) {
  return _then(RSEventCalibration(
null == canId ? _self.canId : canId // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class RSEventSetZero extends RSEvent {
   RSEventSetZero(this.canId, {this.hostId = _defaultHostId}): super._();
  

@override final  int canId;
@JsonKey() final  int hostId;

/// Create a copy of RSEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RSEventSetZeroCopyWith<RSEventSetZero> get copyWith => _$RSEventSetZeroCopyWithImpl<RSEventSetZero>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RSEventSetZero&&(identical(other.canId, canId) || other.canId == canId)&&(identical(other.hostId, hostId) || other.hostId == hostId));
}


@override
int get hashCode => Object.hash(runtimeType,canId,hostId);

@override
String toString() {
  return 'RSEvent.setZero(canId: $canId, hostId: $hostId)';
}


}

/// @nodoc
abstract mixin class $RSEventSetZeroCopyWith<$Res> implements $RSEventCopyWith<$Res> {
  factory $RSEventSetZeroCopyWith(RSEventSetZero value, $Res Function(RSEventSetZero) _then) = _$RSEventSetZeroCopyWithImpl;
@override @useResult
$Res call({
 int canId, int hostId
});




}
/// @nodoc
class _$RSEventSetZeroCopyWithImpl<$Res>
    implements $RSEventSetZeroCopyWith<$Res> {
  _$RSEventSetZeroCopyWithImpl(this._self, this._then);

  final RSEventSetZero _self;
  final $Res Function(RSEventSetZero) _then;

/// Create a copy of RSEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? canId = null,Object? hostId = null,}) {
  return _then(RSEventSetZero(
null == canId ? _self.canId : canId // ignore: cast_nullable_to_non_nullable
as int,hostId: null == hostId ? _self.hostId : hostId // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class RSEventSetId extends RSEvent {
   RSEventSetId(this.canId, {this.hostId = _defaultHostId, required this.newId}): super._();
  

@override final  int canId;
@JsonKey() final  int hostId;
 final  int newId;

/// Create a copy of RSEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RSEventSetIdCopyWith<RSEventSetId> get copyWith => _$RSEventSetIdCopyWithImpl<RSEventSetId>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RSEventSetId&&(identical(other.canId, canId) || other.canId == canId)&&(identical(other.hostId, hostId) || other.hostId == hostId)&&(identical(other.newId, newId) || other.newId == newId));
}


@override
int get hashCode => Object.hash(runtimeType,canId,hostId,newId);

@override
String toString() {
  return 'RSEvent.setId(canId: $canId, hostId: $hostId, newId: $newId)';
}


}

/// @nodoc
abstract mixin class $RSEventSetIdCopyWith<$Res> implements $RSEventCopyWith<$Res> {
  factory $RSEventSetIdCopyWith(RSEventSetId value, $Res Function(RSEventSetId) _then) = _$RSEventSetIdCopyWithImpl;
@override @useResult
$Res call({
 int canId, int hostId, int newId
});




}
/// @nodoc
class _$RSEventSetIdCopyWithImpl<$Res>
    implements $RSEventSetIdCopyWith<$Res> {
  _$RSEventSetIdCopyWithImpl(this._self, this._then);

  final RSEventSetId _self;
  final $Res Function(RSEventSetId) _then;

/// Create a copy of RSEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? canId = null,Object? hostId = null,Object? newId = null,}) {
  return _then(RSEventSetId(
null == canId ? _self.canId : canId // ignore: cast_nullable_to_non_nullable
as int,hostId: null == hostId ? _self.hostId : hostId // ignore: cast_nullable_to_non_nullable
as int,newId: null == newId ? _self.newId : newId // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class RSEventGet extends RSEvent {
   RSEventGet(this.canId, {this.hostId = _defaultHostId, required this.key}): super._();
  

@override final  int canId;
@JsonKey() final  int hostId;
 final  RSKey key;

/// Create a copy of RSEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RSEventGetCopyWith<RSEventGet> get copyWith => _$RSEventGetCopyWithImpl<RSEventGet>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RSEventGet&&(identical(other.canId, canId) || other.canId == canId)&&(identical(other.hostId, hostId) || other.hostId == hostId)&&(identical(other.key, key) || other.key == key));
}


@override
int get hashCode => Object.hash(runtimeType,canId,hostId,key);

@override
String toString() {
  return 'RSEvent.get(canId: $canId, hostId: $hostId, key: $key)';
}


}

/// @nodoc
abstract mixin class $RSEventGetCopyWith<$Res> implements $RSEventCopyWith<$Res> {
  factory $RSEventGetCopyWith(RSEventGet value, $Res Function(RSEventGet) _then) = _$RSEventGetCopyWithImpl;
@override @useResult
$Res call({
 int canId, int hostId, RSKey key
});




}
/// @nodoc
class _$RSEventGetCopyWithImpl<$Res>
    implements $RSEventGetCopyWith<$Res> {
  _$RSEventGetCopyWithImpl(this._self, this._then);

  final RSEventGet _self;
  final $Res Function(RSEventGet) _then;

/// Create a copy of RSEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? canId = null,Object? hostId = null,Object? key = null,}) {
  return _then(RSEventGet(
null == canId ? _self.canId : canId // ignore: cast_nullable_to_non_nullable
as int,hostId: null == hostId ? _self.hostId : hostId // ignore: cast_nullable_to_non_nullable
as int,key: null == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as RSKey,
  ));
}


}

/// @nodoc


class RSEventSet extends RSEvent {
   RSEventSet(this.canId, {this.hostId = _defaultHostId, required this.setter}): super._();
  

@override final  int canId;
@JsonKey() final  int hostId;
 final  RSSetter setter;

/// Create a copy of RSEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RSEventSetCopyWith<RSEventSet> get copyWith => _$RSEventSetCopyWithImpl<RSEventSet>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RSEventSet&&(identical(other.canId, canId) || other.canId == canId)&&(identical(other.hostId, hostId) || other.hostId == hostId)&&(identical(other.setter, setter) || other.setter == setter));
}


@override
int get hashCode => Object.hash(runtimeType,canId,hostId,setter);

@override
String toString() {
  return 'RSEvent.set(canId: $canId, hostId: $hostId, setter: $setter)';
}


}

/// @nodoc
abstract mixin class $RSEventSetCopyWith<$Res> implements $RSEventCopyWith<$Res> {
  factory $RSEventSetCopyWith(RSEventSet value, $Res Function(RSEventSet) _then) = _$RSEventSetCopyWithImpl;
@override @useResult
$Res call({
 int canId, int hostId, RSSetter setter
});


$RSSetterCopyWith<$Res> get setter;

}
/// @nodoc
class _$RSEventSetCopyWithImpl<$Res>
    implements $RSEventSetCopyWith<$Res> {
  _$RSEventSetCopyWithImpl(this._self, this._then);

  final RSEventSet _self;
  final $Res Function(RSEventSet) _then;

/// Create a copy of RSEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? canId = null,Object? hostId = null,Object? setter = null,}) {
  return _then(RSEventSet(
null == canId ? _self.canId : canId // ignore: cast_nullable_to_non_nullable
as int,hostId: null == hostId ? _self.hostId : hostId // ignore: cast_nullable_to_non_nullable
as int,setter: null == setter ? _self.setter : setter // ignore: cast_nullable_to_non_nullable
as RSSetter,
  ));
}

/// Create a copy of RSEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$RSSetterCopyWith<$Res> get setter {
  
  return $RSSetterCopyWith<$Res>(_self.setter, (value) {
    return _then(_self.copyWith(setter: value));
  });
}
}

/// @nodoc


class RSEventSaveData extends RSEvent {
   RSEventSaveData(this.canId, {this.hostId = _defaultHostId}): super._();
  

@override final  int canId;
@JsonKey() final  int hostId;

/// Create a copy of RSEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RSEventSaveDataCopyWith<RSEventSaveData> get copyWith => _$RSEventSaveDataCopyWithImpl<RSEventSaveData>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RSEventSaveData&&(identical(other.canId, canId) || other.canId == canId)&&(identical(other.hostId, hostId) || other.hostId == hostId));
}


@override
int get hashCode => Object.hash(runtimeType,canId,hostId);

@override
String toString() {
  return 'RSEvent.saveData(canId: $canId, hostId: $hostId)';
}


}

/// @nodoc
abstract mixin class $RSEventSaveDataCopyWith<$Res> implements $RSEventCopyWith<$Res> {
  factory $RSEventSaveDataCopyWith(RSEventSaveData value, $Res Function(RSEventSaveData) _then) = _$RSEventSaveDataCopyWithImpl;
@override @useResult
$Res call({
 int canId, int hostId
});




}
/// @nodoc
class _$RSEventSaveDataCopyWithImpl<$Res>
    implements $RSEventSaveDataCopyWith<$Res> {
  _$RSEventSaveDataCopyWithImpl(this._self, this._then);

  final RSEventSaveData _self;
  final $Res Function(RSEventSaveData) _then;

/// Create a copy of RSEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? canId = null,Object? hostId = null,}) {
  return _then(RSEventSaveData(
null == canId ? _self.canId : canId // ignore: cast_nullable_to_non_nullable
as int,hostId: null == hostId ? _self.hostId : hostId // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class RSEventSetBaudRate extends RSEvent {
   RSEventSetBaudRate(this.canId, {this.hostId = _defaultHostId, required this.baudRate}): super._();
  

@override final  int canId;
@JsonKey() final  int hostId;
 final  RSBaudRate baudRate;

/// Create a copy of RSEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RSEventSetBaudRateCopyWith<RSEventSetBaudRate> get copyWith => _$RSEventSetBaudRateCopyWithImpl<RSEventSetBaudRate>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RSEventSetBaudRate&&(identical(other.canId, canId) || other.canId == canId)&&(identical(other.hostId, hostId) || other.hostId == hostId)&&(identical(other.baudRate, baudRate) || other.baudRate == baudRate));
}


@override
int get hashCode => Object.hash(runtimeType,canId,hostId,baudRate);

@override
String toString() {
  return 'RSEvent.setBaudRate(canId: $canId, hostId: $hostId, baudRate: $baudRate)';
}


}

/// @nodoc
abstract mixin class $RSEventSetBaudRateCopyWith<$Res> implements $RSEventCopyWith<$Res> {
  factory $RSEventSetBaudRateCopyWith(RSEventSetBaudRate value, $Res Function(RSEventSetBaudRate) _then) = _$RSEventSetBaudRateCopyWithImpl;
@override @useResult
$Res call({
 int canId, int hostId, RSBaudRate baudRate
});




}
/// @nodoc
class _$RSEventSetBaudRateCopyWithImpl<$Res>
    implements $RSEventSetBaudRateCopyWith<$Res> {
  _$RSEventSetBaudRateCopyWithImpl(this._self, this._then);

  final RSEventSetBaudRate _self;
  final $Res Function(RSEventSetBaudRate) _then;

/// Create a copy of RSEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? canId = null,Object? hostId = null,Object? baudRate = null,}) {
  return _then(RSEventSetBaudRate(
null == canId ? _self.canId : canId // ignore: cast_nullable_to_non_nullable
as int,hostId: null == hostId ? _self.hostId : hostId // ignore: cast_nullable_to_non_nullable
as int,baudRate: null == baudRate ? _self.baudRate : baudRate // ignore: cast_nullable_to_non_nullable
as RSBaudRate,
  ));
}


}

/// @nodoc


class RSEventSetReporting extends RSEvent {
   RSEventSetReporting(this.canId, {this.hostId = _defaultHostId, this.enable = false}): super._();
  

@override final  int canId;
@JsonKey() final  int hostId;
@JsonKey() final  bool enable;

/// Create a copy of RSEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RSEventSetReportingCopyWith<RSEventSetReporting> get copyWith => _$RSEventSetReportingCopyWithImpl<RSEventSetReporting>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RSEventSetReporting&&(identical(other.canId, canId) || other.canId == canId)&&(identical(other.hostId, hostId) || other.hostId == hostId)&&(identical(other.enable, enable) || other.enable == enable));
}


@override
int get hashCode => Object.hash(runtimeType,canId,hostId,enable);

@override
String toString() {
  return 'RSEvent.setReporting(canId: $canId, hostId: $hostId, enable: $enable)';
}


}

/// @nodoc
abstract mixin class $RSEventSetReportingCopyWith<$Res> implements $RSEventCopyWith<$Res> {
  factory $RSEventSetReportingCopyWith(RSEventSetReporting value, $Res Function(RSEventSetReporting) _then) = _$RSEventSetReportingCopyWithImpl;
@override @useResult
$Res call({
 int canId, int hostId, bool enable
});




}
/// @nodoc
class _$RSEventSetReportingCopyWithImpl<$Res>
    implements $RSEventSetReportingCopyWith<$Res> {
  _$RSEventSetReportingCopyWithImpl(this._self, this._then);

  final RSEventSetReporting _self;
  final $Res Function(RSEventSetReporting) _then;

/// Create a copy of RSEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? canId = null,Object? hostId = null,Object? enable = null,}) {
  return _then(RSEventSetReporting(
null == canId ? _self.canId : canId // ignore: cast_nullable_to_non_nullable
as int,hostId: null == hostId ? _self.hostId : hostId // ignore: cast_nullable_to_non_nullable
as int,enable: null == enable ? _self.enable : enable // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc


class RSEventSetProtocol extends RSEvent {
   RSEventSetProtocol(this.canId, {this.hostId = _defaultHostId, required this.protocol}): super._();
  

@override final  int canId;
@JsonKey() final  int hostId;
 final  RSProtocol protocol;

/// Create a copy of RSEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RSEventSetProtocolCopyWith<RSEventSetProtocol> get copyWith => _$RSEventSetProtocolCopyWithImpl<RSEventSetProtocol>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RSEventSetProtocol&&(identical(other.canId, canId) || other.canId == canId)&&(identical(other.hostId, hostId) || other.hostId == hostId)&&(identical(other.protocol, protocol) || other.protocol == protocol));
}


@override
int get hashCode => Object.hash(runtimeType,canId,hostId,protocol);

@override
String toString() {
  return 'RSEvent.setProtocol(canId: $canId, hostId: $hostId, protocol: $protocol)';
}


}

/// @nodoc
abstract mixin class $RSEventSetProtocolCopyWith<$Res> implements $RSEventCopyWith<$Res> {
  factory $RSEventSetProtocolCopyWith(RSEventSetProtocol value, $Res Function(RSEventSetProtocol) _then) = _$RSEventSetProtocolCopyWithImpl;
@override @useResult
$Res call({
 int canId, int hostId, RSProtocol protocol
});




}
/// @nodoc
class _$RSEventSetProtocolCopyWithImpl<$Res>
    implements $RSEventSetProtocolCopyWith<$Res> {
  _$RSEventSetProtocolCopyWithImpl(this._self, this._then);

  final RSEventSetProtocol _self;
  final $Res Function(RSEventSetProtocol) _then;

/// Create a copy of RSEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? canId = null,Object? hostId = null,Object? protocol = null,}) {
  return _then(RSEventSetProtocol(
null == canId ? _self.canId : canId // ignore: cast_nullable_to_non_nullable
as int,hostId: null == hostId ? _self.hostId : hostId // ignore: cast_nullable_to_non_nullable
as int,protocol: null == protocol ? _self.protocol : protocol // ignore: cast_nullable_to_non_nullable
as RSProtocol,
  ));
}


}

// dart format on
