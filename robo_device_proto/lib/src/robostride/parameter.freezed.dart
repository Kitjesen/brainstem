// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'parameter.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$RSGetter {

 Object get value;



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RSGetter&&const DeepCollectionEquality().equals(other.value, value));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(value));

@override
String toString() {
  return 'RSGetter(value: $value)';
}


}

/// @nodoc
class $RSGetterCopyWith<$Res>  {
$RSGetterCopyWith(RSGetter _, $Res Function(RSGetter) __);
}


/// Adds pattern-matching-related methods to [RSGetter].
extension RSGetterPatterns on RSGetter {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( RSGetterRunMode value)?  runMode,TResult Function( RSGetterIqRef value)?  iqRef,TResult Function( RSGetterSpdRef value)?  spdRef,TResult Function( RSGetterLimitTorque value)?  limitTorque,TResult Function( RSGetterCurKp value)?  curKp,TResult Function( RSGetterCurKi value)?  curKi,TResult Function( RSGetterCurFiltGain value)?  curFiltGain,TResult Function( RSGetterLocRef value)?  locRef,TResult Function( RSGetterLimitSpd value)?  limitSpd,TResult Function( RSGetterLimitCur value)?  limitCur,TResult Function( RSGetterMechPos value)?  mechPos,TResult Function( RSGetterIqf value)?  iqf,TResult Function( RSGetterMechVel value)?  mechVel,TResult Function( RSGetterVbus value)?  vbus,TResult Function( RSGetterLocKp value)?  locKp,TResult Function( RSGetterSpdKp value)?  spdKp,TResult Function( RSGetterSpdKi value)?  spdKi,TResult Function( RSGetterSpdFiltGain value)?  spdFiltGain,TResult Function( RSGetterAccRad value)?  accRad,TResult Function( RSGetterVelMax value)?  velMax,TResult Function( RSGetterAccSet value)?  accSet,TResult Function( RSGetterEpscanTime value)?  epscanTime,TResult Function( RSGetterCantimeout value)?  cantimeout,TResult Function( RSGetterZeroSta value)?  zeroSta,required TResult orElse(),}){
final _that = this;
switch (_that) {
case RSGetterRunMode() when runMode != null:
return runMode(_that);case RSGetterIqRef() when iqRef != null:
return iqRef(_that);case RSGetterSpdRef() when spdRef != null:
return spdRef(_that);case RSGetterLimitTorque() when limitTorque != null:
return limitTorque(_that);case RSGetterCurKp() when curKp != null:
return curKp(_that);case RSGetterCurKi() when curKi != null:
return curKi(_that);case RSGetterCurFiltGain() when curFiltGain != null:
return curFiltGain(_that);case RSGetterLocRef() when locRef != null:
return locRef(_that);case RSGetterLimitSpd() when limitSpd != null:
return limitSpd(_that);case RSGetterLimitCur() when limitCur != null:
return limitCur(_that);case RSGetterMechPos() when mechPos != null:
return mechPos(_that);case RSGetterIqf() when iqf != null:
return iqf(_that);case RSGetterMechVel() when mechVel != null:
return mechVel(_that);case RSGetterVbus() when vbus != null:
return vbus(_that);case RSGetterLocKp() when locKp != null:
return locKp(_that);case RSGetterSpdKp() when spdKp != null:
return spdKp(_that);case RSGetterSpdKi() when spdKi != null:
return spdKi(_that);case RSGetterSpdFiltGain() when spdFiltGain != null:
return spdFiltGain(_that);case RSGetterAccRad() when accRad != null:
return accRad(_that);case RSGetterVelMax() when velMax != null:
return velMax(_that);case RSGetterAccSet() when accSet != null:
return accSet(_that);case RSGetterEpscanTime() when epscanTime != null:
return epscanTime(_that);case RSGetterCantimeout() when cantimeout != null:
return cantimeout(_that);case RSGetterZeroSta() when zeroSta != null:
return zeroSta(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( RSGetterRunMode value)  runMode,required TResult Function( RSGetterIqRef value)  iqRef,required TResult Function( RSGetterSpdRef value)  spdRef,required TResult Function( RSGetterLimitTorque value)  limitTorque,required TResult Function( RSGetterCurKp value)  curKp,required TResult Function( RSGetterCurKi value)  curKi,required TResult Function( RSGetterCurFiltGain value)  curFiltGain,required TResult Function( RSGetterLocRef value)  locRef,required TResult Function( RSGetterLimitSpd value)  limitSpd,required TResult Function( RSGetterLimitCur value)  limitCur,required TResult Function( RSGetterMechPos value)  mechPos,required TResult Function( RSGetterIqf value)  iqf,required TResult Function( RSGetterMechVel value)  mechVel,required TResult Function( RSGetterVbus value)  vbus,required TResult Function( RSGetterLocKp value)  locKp,required TResult Function( RSGetterSpdKp value)  spdKp,required TResult Function( RSGetterSpdKi value)  spdKi,required TResult Function( RSGetterSpdFiltGain value)  spdFiltGain,required TResult Function( RSGetterAccRad value)  accRad,required TResult Function( RSGetterVelMax value)  velMax,required TResult Function( RSGetterAccSet value)  accSet,required TResult Function( RSGetterEpscanTime value)  epscanTime,required TResult Function( RSGetterCantimeout value)  cantimeout,required TResult Function( RSGetterZeroSta value)  zeroSta,}){
final _that = this;
switch (_that) {
case RSGetterRunMode():
return runMode(_that);case RSGetterIqRef():
return iqRef(_that);case RSGetterSpdRef():
return spdRef(_that);case RSGetterLimitTorque():
return limitTorque(_that);case RSGetterCurKp():
return curKp(_that);case RSGetterCurKi():
return curKi(_that);case RSGetterCurFiltGain():
return curFiltGain(_that);case RSGetterLocRef():
return locRef(_that);case RSGetterLimitSpd():
return limitSpd(_that);case RSGetterLimitCur():
return limitCur(_that);case RSGetterMechPos():
return mechPos(_that);case RSGetterIqf():
return iqf(_that);case RSGetterMechVel():
return mechVel(_that);case RSGetterVbus():
return vbus(_that);case RSGetterLocKp():
return locKp(_that);case RSGetterSpdKp():
return spdKp(_that);case RSGetterSpdKi():
return spdKi(_that);case RSGetterSpdFiltGain():
return spdFiltGain(_that);case RSGetterAccRad():
return accRad(_that);case RSGetterVelMax():
return velMax(_that);case RSGetterAccSet():
return accSet(_that);case RSGetterEpscanTime():
return epscanTime(_that);case RSGetterCantimeout():
return cantimeout(_that);case RSGetterZeroSta():
return zeroSta(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( RSGetterRunMode value)?  runMode,TResult? Function( RSGetterIqRef value)?  iqRef,TResult? Function( RSGetterSpdRef value)?  spdRef,TResult? Function( RSGetterLimitTorque value)?  limitTorque,TResult? Function( RSGetterCurKp value)?  curKp,TResult? Function( RSGetterCurKi value)?  curKi,TResult? Function( RSGetterCurFiltGain value)?  curFiltGain,TResult? Function( RSGetterLocRef value)?  locRef,TResult? Function( RSGetterLimitSpd value)?  limitSpd,TResult? Function( RSGetterLimitCur value)?  limitCur,TResult? Function( RSGetterMechPos value)?  mechPos,TResult? Function( RSGetterIqf value)?  iqf,TResult? Function( RSGetterMechVel value)?  mechVel,TResult? Function( RSGetterVbus value)?  vbus,TResult? Function( RSGetterLocKp value)?  locKp,TResult? Function( RSGetterSpdKp value)?  spdKp,TResult? Function( RSGetterSpdKi value)?  spdKi,TResult? Function( RSGetterSpdFiltGain value)?  spdFiltGain,TResult? Function( RSGetterAccRad value)?  accRad,TResult? Function( RSGetterVelMax value)?  velMax,TResult? Function( RSGetterAccSet value)?  accSet,TResult? Function( RSGetterEpscanTime value)?  epscanTime,TResult? Function( RSGetterCantimeout value)?  cantimeout,TResult? Function( RSGetterZeroSta value)?  zeroSta,}){
final _that = this;
switch (_that) {
case RSGetterRunMode() when runMode != null:
return runMode(_that);case RSGetterIqRef() when iqRef != null:
return iqRef(_that);case RSGetterSpdRef() when spdRef != null:
return spdRef(_that);case RSGetterLimitTorque() when limitTorque != null:
return limitTorque(_that);case RSGetterCurKp() when curKp != null:
return curKp(_that);case RSGetterCurKi() when curKi != null:
return curKi(_that);case RSGetterCurFiltGain() when curFiltGain != null:
return curFiltGain(_that);case RSGetterLocRef() when locRef != null:
return locRef(_that);case RSGetterLimitSpd() when limitSpd != null:
return limitSpd(_that);case RSGetterLimitCur() when limitCur != null:
return limitCur(_that);case RSGetterMechPos() when mechPos != null:
return mechPos(_that);case RSGetterIqf() when iqf != null:
return iqf(_that);case RSGetterMechVel() when mechVel != null:
return mechVel(_that);case RSGetterVbus() when vbus != null:
return vbus(_that);case RSGetterLocKp() when locKp != null:
return locKp(_that);case RSGetterSpdKp() when spdKp != null:
return spdKp(_that);case RSGetterSpdKi() when spdKi != null:
return spdKi(_that);case RSGetterSpdFiltGain() when spdFiltGain != null:
return spdFiltGain(_that);case RSGetterAccRad() when accRad != null:
return accRad(_that);case RSGetterVelMax() when velMax != null:
return velMax(_that);case RSGetterAccSet() when accSet != null:
return accSet(_that);case RSGetterEpscanTime() when epscanTime != null:
return epscanTime(_that);case RSGetterCantimeout() when cantimeout != null:
return cantimeout(_that);case RSGetterZeroSta() when zeroSta != null:
return zeroSta(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( RSRunMode value)?  runMode,TResult Function( double value)?  iqRef,TResult Function( double value)?  spdRef,TResult Function( double value)?  limitTorque,TResult Function( double value)?  curKp,TResult Function( double value)?  curKi,TResult Function( double value)?  curFiltGain,TResult Function( double value)?  locRef,TResult Function( double value)?  limitSpd,TResult Function( double value)?  limitCur,TResult Function( double value)?  mechPos,TResult Function( double value)?  iqf,TResult Function( double value)?  mechVel,TResult Function( double value)?  vbus,TResult Function( double value)?  locKp,TResult Function( double value)?  spdKp,TResult Function( double value)?  spdKi,TResult Function( double value)?  spdFiltGain,TResult Function( double value)?  accRad,TResult Function( double value)?  velMax,TResult Function( double value)?  accSet,TResult Function( int value)?  epscanTime,TResult Function( int value)?  cantimeout,TResult Function( bool value)?  zeroSta,required TResult orElse(),}) {final _that = this;
switch (_that) {
case RSGetterRunMode() when runMode != null:
return runMode(_that.value);case RSGetterIqRef() when iqRef != null:
return iqRef(_that.value);case RSGetterSpdRef() when spdRef != null:
return spdRef(_that.value);case RSGetterLimitTorque() when limitTorque != null:
return limitTorque(_that.value);case RSGetterCurKp() when curKp != null:
return curKp(_that.value);case RSGetterCurKi() when curKi != null:
return curKi(_that.value);case RSGetterCurFiltGain() when curFiltGain != null:
return curFiltGain(_that.value);case RSGetterLocRef() when locRef != null:
return locRef(_that.value);case RSGetterLimitSpd() when limitSpd != null:
return limitSpd(_that.value);case RSGetterLimitCur() when limitCur != null:
return limitCur(_that.value);case RSGetterMechPos() when mechPos != null:
return mechPos(_that.value);case RSGetterIqf() when iqf != null:
return iqf(_that.value);case RSGetterMechVel() when mechVel != null:
return mechVel(_that.value);case RSGetterVbus() when vbus != null:
return vbus(_that.value);case RSGetterLocKp() when locKp != null:
return locKp(_that.value);case RSGetterSpdKp() when spdKp != null:
return spdKp(_that.value);case RSGetterSpdKi() when spdKi != null:
return spdKi(_that.value);case RSGetterSpdFiltGain() when spdFiltGain != null:
return spdFiltGain(_that.value);case RSGetterAccRad() when accRad != null:
return accRad(_that.value);case RSGetterVelMax() when velMax != null:
return velMax(_that.value);case RSGetterAccSet() when accSet != null:
return accSet(_that.value);case RSGetterEpscanTime() when epscanTime != null:
return epscanTime(_that.value);case RSGetterCantimeout() when cantimeout != null:
return cantimeout(_that.value);case RSGetterZeroSta() when zeroSta != null:
return zeroSta(_that.value);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( RSRunMode value)  runMode,required TResult Function( double value)  iqRef,required TResult Function( double value)  spdRef,required TResult Function( double value)  limitTorque,required TResult Function( double value)  curKp,required TResult Function( double value)  curKi,required TResult Function( double value)  curFiltGain,required TResult Function( double value)  locRef,required TResult Function( double value)  limitSpd,required TResult Function( double value)  limitCur,required TResult Function( double value)  mechPos,required TResult Function( double value)  iqf,required TResult Function( double value)  mechVel,required TResult Function( double value)  vbus,required TResult Function( double value)  locKp,required TResult Function( double value)  spdKp,required TResult Function( double value)  spdKi,required TResult Function( double value)  spdFiltGain,required TResult Function( double value)  accRad,required TResult Function( double value)  velMax,required TResult Function( double value)  accSet,required TResult Function( int value)  epscanTime,required TResult Function( int value)  cantimeout,required TResult Function( bool value)  zeroSta,}) {final _that = this;
switch (_that) {
case RSGetterRunMode():
return runMode(_that.value);case RSGetterIqRef():
return iqRef(_that.value);case RSGetterSpdRef():
return spdRef(_that.value);case RSGetterLimitTorque():
return limitTorque(_that.value);case RSGetterCurKp():
return curKp(_that.value);case RSGetterCurKi():
return curKi(_that.value);case RSGetterCurFiltGain():
return curFiltGain(_that.value);case RSGetterLocRef():
return locRef(_that.value);case RSGetterLimitSpd():
return limitSpd(_that.value);case RSGetterLimitCur():
return limitCur(_that.value);case RSGetterMechPos():
return mechPos(_that.value);case RSGetterIqf():
return iqf(_that.value);case RSGetterMechVel():
return mechVel(_that.value);case RSGetterVbus():
return vbus(_that.value);case RSGetterLocKp():
return locKp(_that.value);case RSGetterSpdKp():
return spdKp(_that.value);case RSGetterSpdKi():
return spdKi(_that.value);case RSGetterSpdFiltGain():
return spdFiltGain(_that.value);case RSGetterAccRad():
return accRad(_that.value);case RSGetterVelMax():
return velMax(_that.value);case RSGetterAccSet():
return accSet(_that.value);case RSGetterEpscanTime():
return epscanTime(_that.value);case RSGetterCantimeout():
return cantimeout(_that.value);case RSGetterZeroSta():
return zeroSta(_that.value);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( RSRunMode value)?  runMode,TResult? Function( double value)?  iqRef,TResult? Function( double value)?  spdRef,TResult? Function( double value)?  limitTorque,TResult? Function( double value)?  curKp,TResult? Function( double value)?  curKi,TResult? Function( double value)?  curFiltGain,TResult? Function( double value)?  locRef,TResult? Function( double value)?  limitSpd,TResult? Function( double value)?  limitCur,TResult? Function( double value)?  mechPos,TResult? Function( double value)?  iqf,TResult? Function( double value)?  mechVel,TResult? Function( double value)?  vbus,TResult? Function( double value)?  locKp,TResult? Function( double value)?  spdKp,TResult? Function( double value)?  spdKi,TResult? Function( double value)?  spdFiltGain,TResult? Function( double value)?  accRad,TResult? Function( double value)?  velMax,TResult? Function( double value)?  accSet,TResult? Function( int value)?  epscanTime,TResult? Function( int value)?  cantimeout,TResult? Function( bool value)?  zeroSta,}) {final _that = this;
switch (_that) {
case RSGetterRunMode() when runMode != null:
return runMode(_that.value);case RSGetterIqRef() when iqRef != null:
return iqRef(_that.value);case RSGetterSpdRef() when spdRef != null:
return spdRef(_that.value);case RSGetterLimitTorque() when limitTorque != null:
return limitTorque(_that.value);case RSGetterCurKp() when curKp != null:
return curKp(_that.value);case RSGetterCurKi() when curKi != null:
return curKi(_that.value);case RSGetterCurFiltGain() when curFiltGain != null:
return curFiltGain(_that.value);case RSGetterLocRef() when locRef != null:
return locRef(_that.value);case RSGetterLimitSpd() when limitSpd != null:
return limitSpd(_that.value);case RSGetterLimitCur() when limitCur != null:
return limitCur(_that.value);case RSGetterMechPos() when mechPos != null:
return mechPos(_that.value);case RSGetterIqf() when iqf != null:
return iqf(_that.value);case RSGetterMechVel() when mechVel != null:
return mechVel(_that.value);case RSGetterVbus() when vbus != null:
return vbus(_that.value);case RSGetterLocKp() when locKp != null:
return locKp(_that.value);case RSGetterSpdKp() when spdKp != null:
return spdKp(_that.value);case RSGetterSpdKi() when spdKi != null:
return spdKi(_that.value);case RSGetterSpdFiltGain() when spdFiltGain != null:
return spdFiltGain(_that.value);case RSGetterAccRad() when accRad != null:
return accRad(_that.value);case RSGetterVelMax() when velMax != null:
return velMax(_that.value);case RSGetterAccSet() when accSet != null:
return accSet(_that.value);case RSGetterEpscanTime() when epscanTime != null:
return epscanTime(_that.value);case RSGetterCantimeout() when cantimeout != null:
return cantimeout(_that.value);case RSGetterZeroSta() when zeroSta != null:
return zeroSta(_that.value);case _:
  return null;

}
}

}

/// @nodoc


class RSGetterRunMode extends RSGetter {
   RSGetterRunMode(this.value): super._();
  

@override final  RSRunMode value;

/// Create a copy of RSGetter
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RSGetterRunModeCopyWith<RSGetterRunMode> get copyWith => _$RSGetterRunModeCopyWithImpl<RSGetterRunMode>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RSGetterRunMode&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,value);

@override
String toString() {
  return 'RSGetter.runMode(value: $value)';
}


}

/// @nodoc
abstract mixin class $RSGetterRunModeCopyWith<$Res> implements $RSGetterCopyWith<$Res> {
  factory $RSGetterRunModeCopyWith(RSGetterRunMode value, $Res Function(RSGetterRunMode) _then) = _$RSGetterRunModeCopyWithImpl;
@useResult
$Res call({
 RSRunMode value
});




}
/// @nodoc
class _$RSGetterRunModeCopyWithImpl<$Res>
    implements $RSGetterRunModeCopyWith<$Res> {
  _$RSGetterRunModeCopyWithImpl(this._self, this._then);

  final RSGetterRunMode _self;
  final $Res Function(RSGetterRunMode) _then;

/// Create a copy of RSGetter
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(RSGetterRunMode(
null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as RSRunMode,
  ));
}


}

/// @nodoc


class RSGetterIqRef extends RSGetter {
   RSGetterIqRef(this.value): super._();
  

@override final  double value;

/// Create a copy of RSGetter
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RSGetterIqRefCopyWith<RSGetterIqRef> get copyWith => _$RSGetterIqRefCopyWithImpl<RSGetterIqRef>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RSGetterIqRef&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,value);

@override
String toString() {
  return 'RSGetter.iqRef(value: $value)';
}


}

/// @nodoc
abstract mixin class $RSGetterIqRefCopyWith<$Res> implements $RSGetterCopyWith<$Res> {
  factory $RSGetterIqRefCopyWith(RSGetterIqRef value, $Res Function(RSGetterIqRef) _then) = _$RSGetterIqRefCopyWithImpl;
@useResult
$Res call({
 double value
});




}
/// @nodoc
class _$RSGetterIqRefCopyWithImpl<$Res>
    implements $RSGetterIqRefCopyWith<$Res> {
  _$RSGetterIqRefCopyWithImpl(this._self, this._then);

  final RSGetterIqRef _self;
  final $Res Function(RSGetterIqRef) _then;

/// Create a copy of RSGetter
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(RSGetterIqRef(
null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

/// @nodoc


class RSGetterSpdRef extends RSGetter {
   RSGetterSpdRef(this.value): super._();
  

@override final  double value;

/// Create a copy of RSGetter
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RSGetterSpdRefCopyWith<RSGetterSpdRef> get copyWith => _$RSGetterSpdRefCopyWithImpl<RSGetterSpdRef>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RSGetterSpdRef&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,value);

@override
String toString() {
  return 'RSGetter.spdRef(value: $value)';
}


}

/// @nodoc
abstract mixin class $RSGetterSpdRefCopyWith<$Res> implements $RSGetterCopyWith<$Res> {
  factory $RSGetterSpdRefCopyWith(RSGetterSpdRef value, $Res Function(RSGetterSpdRef) _then) = _$RSGetterSpdRefCopyWithImpl;
@useResult
$Res call({
 double value
});




}
/// @nodoc
class _$RSGetterSpdRefCopyWithImpl<$Res>
    implements $RSGetterSpdRefCopyWith<$Res> {
  _$RSGetterSpdRefCopyWithImpl(this._self, this._then);

  final RSGetterSpdRef _self;
  final $Res Function(RSGetterSpdRef) _then;

/// Create a copy of RSGetter
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(RSGetterSpdRef(
null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

/// @nodoc


class RSGetterLimitTorque extends RSGetter {
   RSGetterLimitTorque(this.value): super._();
  

@override final  double value;

/// Create a copy of RSGetter
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RSGetterLimitTorqueCopyWith<RSGetterLimitTorque> get copyWith => _$RSGetterLimitTorqueCopyWithImpl<RSGetterLimitTorque>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RSGetterLimitTorque&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,value);

@override
String toString() {
  return 'RSGetter.limitTorque(value: $value)';
}


}

/// @nodoc
abstract mixin class $RSGetterLimitTorqueCopyWith<$Res> implements $RSGetterCopyWith<$Res> {
  factory $RSGetterLimitTorqueCopyWith(RSGetterLimitTorque value, $Res Function(RSGetterLimitTorque) _then) = _$RSGetterLimitTorqueCopyWithImpl;
@useResult
$Res call({
 double value
});




}
/// @nodoc
class _$RSGetterLimitTorqueCopyWithImpl<$Res>
    implements $RSGetterLimitTorqueCopyWith<$Res> {
  _$RSGetterLimitTorqueCopyWithImpl(this._self, this._then);

  final RSGetterLimitTorque _self;
  final $Res Function(RSGetterLimitTorque) _then;

/// Create a copy of RSGetter
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(RSGetterLimitTorque(
null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

/// @nodoc


class RSGetterCurKp extends RSGetter {
   RSGetterCurKp(this.value): super._();
  

@override final  double value;

/// Create a copy of RSGetter
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RSGetterCurKpCopyWith<RSGetterCurKp> get copyWith => _$RSGetterCurKpCopyWithImpl<RSGetterCurKp>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RSGetterCurKp&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,value);

@override
String toString() {
  return 'RSGetter.curKp(value: $value)';
}


}

/// @nodoc
abstract mixin class $RSGetterCurKpCopyWith<$Res> implements $RSGetterCopyWith<$Res> {
  factory $RSGetterCurKpCopyWith(RSGetterCurKp value, $Res Function(RSGetterCurKp) _then) = _$RSGetterCurKpCopyWithImpl;
@useResult
$Res call({
 double value
});




}
/// @nodoc
class _$RSGetterCurKpCopyWithImpl<$Res>
    implements $RSGetterCurKpCopyWith<$Res> {
  _$RSGetterCurKpCopyWithImpl(this._self, this._then);

  final RSGetterCurKp _self;
  final $Res Function(RSGetterCurKp) _then;

/// Create a copy of RSGetter
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(RSGetterCurKp(
null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

/// @nodoc


class RSGetterCurKi extends RSGetter {
   RSGetterCurKi(this.value): super._();
  

@override final  double value;

/// Create a copy of RSGetter
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RSGetterCurKiCopyWith<RSGetterCurKi> get copyWith => _$RSGetterCurKiCopyWithImpl<RSGetterCurKi>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RSGetterCurKi&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,value);

@override
String toString() {
  return 'RSGetter.curKi(value: $value)';
}


}

/// @nodoc
abstract mixin class $RSGetterCurKiCopyWith<$Res> implements $RSGetterCopyWith<$Res> {
  factory $RSGetterCurKiCopyWith(RSGetterCurKi value, $Res Function(RSGetterCurKi) _then) = _$RSGetterCurKiCopyWithImpl;
@useResult
$Res call({
 double value
});




}
/// @nodoc
class _$RSGetterCurKiCopyWithImpl<$Res>
    implements $RSGetterCurKiCopyWith<$Res> {
  _$RSGetterCurKiCopyWithImpl(this._self, this._then);

  final RSGetterCurKi _self;
  final $Res Function(RSGetterCurKi) _then;

/// Create a copy of RSGetter
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(RSGetterCurKi(
null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

/// @nodoc


class RSGetterCurFiltGain extends RSGetter {
   RSGetterCurFiltGain(this.value): super._();
  

@override final  double value;

/// Create a copy of RSGetter
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RSGetterCurFiltGainCopyWith<RSGetterCurFiltGain> get copyWith => _$RSGetterCurFiltGainCopyWithImpl<RSGetterCurFiltGain>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RSGetterCurFiltGain&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,value);

@override
String toString() {
  return 'RSGetter.curFiltGain(value: $value)';
}


}

/// @nodoc
abstract mixin class $RSGetterCurFiltGainCopyWith<$Res> implements $RSGetterCopyWith<$Res> {
  factory $RSGetterCurFiltGainCopyWith(RSGetterCurFiltGain value, $Res Function(RSGetterCurFiltGain) _then) = _$RSGetterCurFiltGainCopyWithImpl;
@useResult
$Res call({
 double value
});




}
/// @nodoc
class _$RSGetterCurFiltGainCopyWithImpl<$Res>
    implements $RSGetterCurFiltGainCopyWith<$Res> {
  _$RSGetterCurFiltGainCopyWithImpl(this._self, this._then);

  final RSGetterCurFiltGain _self;
  final $Res Function(RSGetterCurFiltGain) _then;

/// Create a copy of RSGetter
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(RSGetterCurFiltGain(
null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

/// @nodoc


class RSGetterLocRef extends RSGetter {
   RSGetterLocRef(this.value): super._();
  

@override final  double value;

/// Create a copy of RSGetter
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RSGetterLocRefCopyWith<RSGetterLocRef> get copyWith => _$RSGetterLocRefCopyWithImpl<RSGetterLocRef>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RSGetterLocRef&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,value);

@override
String toString() {
  return 'RSGetter.locRef(value: $value)';
}


}

/// @nodoc
abstract mixin class $RSGetterLocRefCopyWith<$Res> implements $RSGetterCopyWith<$Res> {
  factory $RSGetterLocRefCopyWith(RSGetterLocRef value, $Res Function(RSGetterLocRef) _then) = _$RSGetterLocRefCopyWithImpl;
@useResult
$Res call({
 double value
});




}
/// @nodoc
class _$RSGetterLocRefCopyWithImpl<$Res>
    implements $RSGetterLocRefCopyWith<$Res> {
  _$RSGetterLocRefCopyWithImpl(this._self, this._then);

  final RSGetterLocRef _self;
  final $Res Function(RSGetterLocRef) _then;

/// Create a copy of RSGetter
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(RSGetterLocRef(
null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

/// @nodoc


class RSGetterLimitSpd extends RSGetter {
   RSGetterLimitSpd(this.value): super._();
  

@override final  double value;

/// Create a copy of RSGetter
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RSGetterLimitSpdCopyWith<RSGetterLimitSpd> get copyWith => _$RSGetterLimitSpdCopyWithImpl<RSGetterLimitSpd>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RSGetterLimitSpd&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,value);

@override
String toString() {
  return 'RSGetter.limitSpd(value: $value)';
}


}

/// @nodoc
abstract mixin class $RSGetterLimitSpdCopyWith<$Res> implements $RSGetterCopyWith<$Res> {
  factory $RSGetterLimitSpdCopyWith(RSGetterLimitSpd value, $Res Function(RSGetterLimitSpd) _then) = _$RSGetterLimitSpdCopyWithImpl;
@useResult
$Res call({
 double value
});




}
/// @nodoc
class _$RSGetterLimitSpdCopyWithImpl<$Res>
    implements $RSGetterLimitSpdCopyWith<$Res> {
  _$RSGetterLimitSpdCopyWithImpl(this._self, this._then);

  final RSGetterLimitSpd _self;
  final $Res Function(RSGetterLimitSpd) _then;

/// Create a copy of RSGetter
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(RSGetterLimitSpd(
null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

/// @nodoc


class RSGetterLimitCur extends RSGetter {
   RSGetterLimitCur(this.value): super._();
  

@override final  double value;

/// Create a copy of RSGetter
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RSGetterLimitCurCopyWith<RSGetterLimitCur> get copyWith => _$RSGetterLimitCurCopyWithImpl<RSGetterLimitCur>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RSGetterLimitCur&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,value);

@override
String toString() {
  return 'RSGetter.limitCur(value: $value)';
}


}

/// @nodoc
abstract mixin class $RSGetterLimitCurCopyWith<$Res> implements $RSGetterCopyWith<$Res> {
  factory $RSGetterLimitCurCopyWith(RSGetterLimitCur value, $Res Function(RSGetterLimitCur) _then) = _$RSGetterLimitCurCopyWithImpl;
@useResult
$Res call({
 double value
});




}
/// @nodoc
class _$RSGetterLimitCurCopyWithImpl<$Res>
    implements $RSGetterLimitCurCopyWith<$Res> {
  _$RSGetterLimitCurCopyWithImpl(this._self, this._then);

  final RSGetterLimitCur _self;
  final $Res Function(RSGetterLimitCur) _then;

/// Create a copy of RSGetter
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(RSGetterLimitCur(
null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

/// @nodoc


class RSGetterMechPos extends RSGetter {
   RSGetterMechPos(this.value): super._();
  

@override final  double value;

/// Create a copy of RSGetter
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RSGetterMechPosCopyWith<RSGetterMechPos> get copyWith => _$RSGetterMechPosCopyWithImpl<RSGetterMechPos>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RSGetterMechPos&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,value);

@override
String toString() {
  return 'RSGetter.mechPos(value: $value)';
}


}

/// @nodoc
abstract mixin class $RSGetterMechPosCopyWith<$Res> implements $RSGetterCopyWith<$Res> {
  factory $RSGetterMechPosCopyWith(RSGetterMechPos value, $Res Function(RSGetterMechPos) _then) = _$RSGetterMechPosCopyWithImpl;
@useResult
$Res call({
 double value
});




}
/// @nodoc
class _$RSGetterMechPosCopyWithImpl<$Res>
    implements $RSGetterMechPosCopyWith<$Res> {
  _$RSGetterMechPosCopyWithImpl(this._self, this._then);

  final RSGetterMechPos _self;
  final $Res Function(RSGetterMechPos) _then;

/// Create a copy of RSGetter
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(RSGetterMechPos(
null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

/// @nodoc


class RSGetterIqf extends RSGetter {
   RSGetterIqf(this.value): super._();
  

@override final  double value;

/// Create a copy of RSGetter
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RSGetterIqfCopyWith<RSGetterIqf> get copyWith => _$RSGetterIqfCopyWithImpl<RSGetterIqf>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RSGetterIqf&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,value);

@override
String toString() {
  return 'RSGetter.iqf(value: $value)';
}


}

/// @nodoc
abstract mixin class $RSGetterIqfCopyWith<$Res> implements $RSGetterCopyWith<$Res> {
  factory $RSGetterIqfCopyWith(RSGetterIqf value, $Res Function(RSGetterIqf) _then) = _$RSGetterIqfCopyWithImpl;
@useResult
$Res call({
 double value
});




}
/// @nodoc
class _$RSGetterIqfCopyWithImpl<$Res>
    implements $RSGetterIqfCopyWith<$Res> {
  _$RSGetterIqfCopyWithImpl(this._self, this._then);

  final RSGetterIqf _self;
  final $Res Function(RSGetterIqf) _then;

/// Create a copy of RSGetter
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(RSGetterIqf(
null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

/// @nodoc


class RSGetterMechVel extends RSGetter {
   RSGetterMechVel(this.value): super._();
  

@override final  double value;

/// Create a copy of RSGetter
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RSGetterMechVelCopyWith<RSGetterMechVel> get copyWith => _$RSGetterMechVelCopyWithImpl<RSGetterMechVel>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RSGetterMechVel&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,value);

@override
String toString() {
  return 'RSGetter.mechVel(value: $value)';
}


}

/// @nodoc
abstract mixin class $RSGetterMechVelCopyWith<$Res> implements $RSGetterCopyWith<$Res> {
  factory $RSGetterMechVelCopyWith(RSGetterMechVel value, $Res Function(RSGetterMechVel) _then) = _$RSGetterMechVelCopyWithImpl;
@useResult
$Res call({
 double value
});




}
/// @nodoc
class _$RSGetterMechVelCopyWithImpl<$Res>
    implements $RSGetterMechVelCopyWith<$Res> {
  _$RSGetterMechVelCopyWithImpl(this._self, this._then);

  final RSGetterMechVel _self;
  final $Res Function(RSGetterMechVel) _then;

/// Create a copy of RSGetter
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(RSGetterMechVel(
null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

/// @nodoc


class RSGetterVbus extends RSGetter {
   RSGetterVbus(this.value): super._();
  

@override final  double value;

/// Create a copy of RSGetter
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RSGetterVbusCopyWith<RSGetterVbus> get copyWith => _$RSGetterVbusCopyWithImpl<RSGetterVbus>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RSGetterVbus&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,value);

@override
String toString() {
  return 'RSGetter.vbus(value: $value)';
}


}

/// @nodoc
abstract mixin class $RSGetterVbusCopyWith<$Res> implements $RSGetterCopyWith<$Res> {
  factory $RSGetterVbusCopyWith(RSGetterVbus value, $Res Function(RSGetterVbus) _then) = _$RSGetterVbusCopyWithImpl;
@useResult
$Res call({
 double value
});




}
/// @nodoc
class _$RSGetterVbusCopyWithImpl<$Res>
    implements $RSGetterVbusCopyWith<$Res> {
  _$RSGetterVbusCopyWithImpl(this._self, this._then);

  final RSGetterVbus _self;
  final $Res Function(RSGetterVbus) _then;

/// Create a copy of RSGetter
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(RSGetterVbus(
null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

/// @nodoc


class RSGetterLocKp extends RSGetter {
   RSGetterLocKp(this.value): super._();
  

@override final  double value;

/// Create a copy of RSGetter
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RSGetterLocKpCopyWith<RSGetterLocKp> get copyWith => _$RSGetterLocKpCopyWithImpl<RSGetterLocKp>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RSGetterLocKp&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,value);

@override
String toString() {
  return 'RSGetter.locKp(value: $value)';
}


}

/// @nodoc
abstract mixin class $RSGetterLocKpCopyWith<$Res> implements $RSGetterCopyWith<$Res> {
  factory $RSGetterLocKpCopyWith(RSGetterLocKp value, $Res Function(RSGetterLocKp) _then) = _$RSGetterLocKpCopyWithImpl;
@useResult
$Res call({
 double value
});




}
/// @nodoc
class _$RSGetterLocKpCopyWithImpl<$Res>
    implements $RSGetterLocKpCopyWith<$Res> {
  _$RSGetterLocKpCopyWithImpl(this._self, this._then);

  final RSGetterLocKp _self;
  final $Res Function(RSGetterLocKp) _then;

/// Create a copy of RSGetter
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(RSGetterLocKp(
null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

/// @nodoc


class RSGetterSpdKp extends RSGetter {
   RSGetterSpdKp(this.value): super._();
  

@override final  double value;

/// Create a copy of RSGetter
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RSGetterSpdKpCopyWith<RSGetterSpdKp> get copyWith => _$RSGetterSpdKpCopyWithImpl<RSGetterSpdKp>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RSGetterSpdKp&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,value);

@override
String toString() {
  return 'RSGetter.spdKp(value: $value)';
}


}

/// @nodoc
abstract mixin class $RSGetterSpdKpCopyWith<$Res> implements $RSGetterCopyWith<$Res> {
  factory $RSGetterSpdKpCopyWith(RSGetterSpdKp value, $Res Function(RSGetterSpdKp) _then) = _$RSGetterSpdKpCopyWithImpl;
@useResult
$Res call({
 double value
});




}
/// @nodoc
class _$RSGetterSpdKpCopyWithImpl<$Res>
    implements $RSGetterSpdKpCopyWith<$Res> {
  _$RSGetterSpdKpCopyWithImpl(this._self, this._then);

  final RSGetterSpdKp _self;
  final $Res Function(RSGetterSpdKp) _then;

/// Create a copy of RSGetter
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(RSGetterSpdKp(
null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

/// @nodoc


class RSGetterSpdKi extends RSGetter {
   RSGetterSpdKi(this.value): super._();
  

@override final  double value;

/// Create a copy of RSGetter
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RSGetterSpdKiCopyWith<RSGetterSpdKi> get copyWith => _$RSGetterSpdKiCopyWithImpl<RSGetterSpdKi>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RSGetterSpdKi&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,value);

@override
String toString() {
  return 'RSGetter.spdKi(value: $value)';
}


}

/// @nodoc
abstract mixin class $RSGetterSpdKiCopyWith<$Res> implements $RSGetterCopyWith<$Res> {
  factory $RSGetterSpdKiCopyWith(RSGetterSpdKi value, $Res Function(RSGetterSpdKi) _then) = _$RSGetterSpdKiCopyWithImpl;
@useResult
$Res call({
 double value
});




}
/// @nodoc
class _$RSGetterSpdKiCopyWithImpl<$Res>
    implements $RSGetterSpdKiCopyWith<$Res> {
  _$RSGetterSpdKiCopyWithImpl(this._self, this._then);

  final RSGetterSpdKi _self;
  final $Res Function(RSGetterSpdKi) _then;

/// Create a copy of RSGetter
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(RSGetterSpdKi(
null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

/// @nodoc


class RSGetterSpdFiltGain extends RSGetter {
   RSGetterSpdFiltGain(this.value): super._();
  

@override final  double value;

/// Create a copy of RSGetter
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RSGetterSpdFiltGainCopyWith<RSGetterSpdFiltGain> get copyWith => _$RSGetterSpdFiltGainCopyWithImpl<RSGetterSpdFiltGain>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RSGetterSpdFiltGain&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,value);

@override
String toString() {
  return 'RSGetter.spdFiltGain(value: $value)';
}


}

/// @nodoc
abstract mixin class $RSGetterSpdFiltGainCopyWith<$Res> implements $RSGetterCopyWith<$Res> {
  factory $RSGetterSpdFiltGainCopyWith(RSGetterSpdFiltGain value, $Res Function(RSGetterSpdFiltGain) _then) = _$RSGetterSpdFiltGainCopyWithImpl;
@useResult
$Res call({
 double value
});




}
/// @nodoc
class _$RSGetterSpdFiltGainCopyWithImpl<$Res>
    implements $RSGetterSpdFiltGainCopyWith<$Res> {
  _$RSGetterSpdFiltGainCopyWithImpl(this._self, this._then);

  final RSGetterSpdFiltGain _self;
  final $Res Function(RSGetterSpdFiltGain) _then;

/// Create a copy of RSGetter
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(RSGetterSpdFiltGain(
null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

/// @nodoc


class RSGetterAccRad extends RSGetter {
   RSGetterAccRad(this.value): super._();
  

@override final  double value;

/// Create a copy of RSGetter
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RSGetterAccRadCopyWith<RSGetterAccRad> get copyWith => _$RSGetterAccRadCopyWithImpl<RSGetterAccRad>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RSGetterAccRad&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,value);

@override
String toString() {
  return 'RSGetter.accRad(value: $value)';
}


}

/// @nodoc
abstract mixin class $RSGetterAccRadCopyWith<$Res> implements $RSGetterCopyWith<$Res> {
  factory $RSGetterAccRadCopyWith(RSGetterAccRad value, $Res Function(RSGetterAccRad) _then) = _$RSGetterAccRadCopyWithImpl;
@useResult
$Res call({
 double value
});




}
/// @nodoc
class _$RSGetterAccRadCopyWithImpl<$Res>
    implements $RSGetterAccRadCopyWith<$Res> {
  _$RSGetterAccRadCopyWithImpl(this._self, this._then);

  final RSGetterAccRad _self;
  final $Res Function(RSGetterAccRad) _then;

/// Create a copy of RSGetter
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(RSGetterAccRad(
null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

/// @nodoc


class RSGetterVelMax extends RSGetter {
   RSGetterVelMax(this.value): super._();
  

@override final  double value;

/// Create a copy of RSGetter
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RSGetterVelMaxCopyWith<RSGetterVelMax> get copyWith => _$RSGetterVelMaxCopyWithImpl<RSGetterVelMax>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RSGetterVelMax&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,value);

@override
String toString() {
  return 'RSGetter.velMax(value: $value)';
}


}

/// @nodoc
abstract mixin class $RSGetterVelMaxCopyWith<$Res> implements $RSGetterCopyWith<$Res> {
  factory $RSGetterVelMaxCopyWith(RSGetterVelMax value, $Res Function(RSGetterVelMax) _then) = _$RSGetterVelMaxCopyWithImpl;
@useResult
$Res call({
 double value
});




}
/// @nodoc
class _$RSGetterVelMaxCopyWithImpl<$Res>
    implements $RSGetterVelMaxCopyWith<$Res> {
  _$RSGetterVelMaxCopyWithImpl(this._self, this._then);

  final RSGetterVelMax _self;
  final $Res Function(RSGetterVelMax) _then;

/// Create a copy of RSGetter
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(RSGetterVelMax(
null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

/// @nodoc


class RSGetterAccSet extends RSGetter {
   RSGetterAccSet(this.value): super._();
  

@override final  double value;

/// Create a copy of RSGetter
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RSGetterAccSetCopyWith<RSGetterAccSet> get copyWith => _$RSGetterAccSetCopyWithImpl<RSGetterAccSet>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RSGetterAccSet&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,value);

@override
String toString() {
  return 'RSGetter.accSet(value: $value)';
}


}

/// @nodoc
abstract mixin class $RSGetterAccSetCopyWith<$Res> implements $RSGetterCopyWith<$Res> {
  factory $RSGetterAccSetCopyWith(RSGetterAccSet value, $Res Function(RSGetterAccSet) _then) = _$RSGetterAccSetCopyWithImpl;
@useResult
$Res call({
 double value
});




}
/// @nodoc
class _$RSGetterAccSetCopyWithImpl<$Res>
    implements $RSGetterAccSetCopyWith<$Res> {
  _$RSGetterAccSetCopyWithImpl(this._self, this._then);

  final RSGetterAccSet _self;
  final $Res Function(RSGetterAccSet) _then;

/// Create a copy of RSGetter
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(RSGetterAccSet(
null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

/// @nodoc


class RSGetterEpscanTime extends RSGetter {
   RSGetterEpscanTime(this.value): super._();
  

@override final  int value;

/// Create a copy of RSGetter
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RSGetterEpscanTimeCopyWith<RSGetterEpscanTime> get copyWith => _$RSGetterEpscanTimeCopyWithImpl<RSGetterEpscanTime>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RSGetterEpscanTime&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,value);

@override
String toString() {
  return 'RSGetter.epscanTime(value: $value)';
}


}

/// @nodoc
abstract mixin class $RSGetterEpscanTimeCopyWith<$Res> implements $RSGetterCopyWith<$Res> {
  factory $RSGetterEpscanTimeCopyWith(RSGetterEpscanTime value, $Res Function(RSGetterEpscanTime) _then) = _$RSGetterEpscanTimeCopyWithImpl;
@useResult
$Res call({
 int value
});




}
/// @nodoc
class _$RSGetterEpscanTimeCopyWithImpl<$Res>
    implements $RSGetterEpscanTimeCopyWith<$Res> {
  _$RSGetterEpscanTimeCopyWithImpl(this._self, this._then);

  final RSGetterEpscanTime _self;
  final $Res Function(RSGetterEpscanTime) _then;

/// Create a copy of RSGetter
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(RSGetterEpscanTime(
null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class RSGetterCantimeout extends RSGetter {
   RSGetterCantimeout(this.value): super._();
  

@override final  int value;

/// Create a copy of RSGetter
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RSGetterCantimeoutCopyWith<RSGetterCantimeout> get copyWith => _$RSGetterCantimeoutCopyWithImpl<RSGetterCantimeout>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RSGetterCantimeout&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,value);

@override
String toString() {
  return 'RSGetter.cantimeout(value: $value)';
}


}

/// @nodoc
abstract mixin class $RSGetterCantimeoutCopyWith<$Res> implements $RSGetterCopyWith<$Res> {
  factory $RSGetterCantimeoutCopyWith(RSGetterCantimeout value, $Res Function(RSGetterCantimeout) _then) = _$RSGetterCantimeoutCopyWithImpl;
@useResult
$Res call({
 int value
});




}
/// @nodoc
class _$RSGetterCantimeoutCopyWithImpl<$Res>
    implements $RSGetterCantimeoutCopyWith<$Res> {
  _$RSGetterCantimeoutCopyWithImpl(this._self, this._then);

  final RSGetterCantimeout _self;
  final $Res Function(RSGetterCantimeout) _then;

/// Create a copy of RSGetter
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(RSGetterCantimeout(
null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class RSGetterZeroSta extends RSGetter {
   RSGetterZeroSta(this.value): super._();
  

@override final  bool value;

/// Create a copy of RSGetter
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RSGetterZeroStaCopyWith<RSGetterZeroSta> get copyWith => _$RSGetterZeroStaCopyWithImpl<RSGetterZeroSta>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RSGetterZeroSta&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,value);

@override
String toString() {
  return 'RSGetter.zeroSta(value: $value)';
}


}

/// @nodoc
abstract mixin class $RSGetterZeroStaCopyWith<$Res> implements $RSGetterCopyWith<$Res> {
  factory $RSGetterZeroStaCopyWith(RSGetterZeroSta value, $Res Function(RSGetterZeroSta) _then) = _$RSGetterZeroStaCopyWithImpl;
@useResult
$Res call({
 bool value
});




}
/// @nodoc
class _$RSGetterZeroStaCopyWithImpl<$Res>
    implements $RSGetterZeroStaCopyWith<$Res> {
  _$RSGetterZeroStaCopyWithImpl(this._self, this._then);

  final RSGetterZeroSta _self;
  final $Res Function(RSGetterZeroSta) _then;

/// Create a copy of RSGetter
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(RSGetterZeroSta(
null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc
mixin _$RSSetter {

 Object get value;



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RSSetter&&const DeepCollectionEquality().equals(other.value, value));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(value));

@override
String toString() {
  return 'RSSetter(value: $value)';
}


}

/// @nodoc
class $RSSetterCopyWith<$Res>  {
$RSSetterCopyWith(RSSetter _, $Res Function(RSSetter) __);
}


/// Adds pattern-matching-related methods to [RSSetter].
extension RSSetterPatterns on RSSetter {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( RSSetterRunMode value)?  runMode,TResult Function( RSSetterIqRef value)?  iqRef,TResult Function( RSSetterSpdRef value)?  spdRef,TResult Function( RSSetterLimitTorque value)?  limitTorque,TResult Function( RSSetterCurKp value)?  curKp,TResult Function( RSSetterCurKi value)?  curKi,TResult Function( RSSetterCurFiltGain value)?  curFiltGain,TResult Function( RSSetterLocRef value)?  locRef,TResult Function( RSSetterLimitSpd value)?  limitSpd,TResult Function( RSSetterLimitCur value)?  limitCur,TResult Function( RSSetterLocKp value)?  locKp,TResult Function( RSSetterSpdKp value)?  spdKp,TResult Function( RSSetterSpdKi value)?  spdKi,TResult Function( RSSetterSpdFiltGain value)?  spdFiltGain,TResult Function( RSSetterAccRad value)?  accRad,TResult Function( RSSetterVelMax value)?  velMax,TResult Function( RSSetterAccSet value)?  accSet,TResult Function( RSSetterEpscanTime value)?  epscanTime,TResult Function( RSSetterCantimeout value)?  cantimeout,TResult Function( RSSetterZeroSta value)?  zeroSta,required TResult orElse(),}){
final _that = this;
switch (_that) {
case RSSetterRunMode() when runMode != null:
return runMode(_that);case RSSetterIqRef() when iqRef != null:
return iqRef(_that);case RSSetterSpdRef() when spdRef != null:
return spdRef(_that);case RSSetterLimitTorque() when limitTorque != null:
return limitTorque(_that);case RSSetterCurKp() when curKp != null:
return curKp(_that);case RSSetterCurKi() when curKi != null:
return curKi(_that);case RSSetterCurFiltGain() when curFiltGain != null:
return curFiltGain(_that);case RSSetterLocRef() when locRef != null:
return locRef(_that);case RSSetterLimitSpd() when limitSpd != null:
return limitSpd(_that);case RSSetterLimitCur() when limitCur != null:
return limitCur(_that);case RSSetterLocKp() when locKp != null:
return locKp(_that);case RSSetterSpdKp() when spdKp != null:
return spdKp(_that);case RSSetterSpdKi() when spdKi != null:
return spdKi(_that);case RSSetterSpdFiltGain() when spdFiltGain != null:
return spdFiltGain(_that);case RSSetterAccRad() when accRad != null:
return accRad(_that);case RSSetterVelMax() when velMax != null:
return velMax(_that);case RSSetterAccSet() when accSet != null:
return accSet(_that);case RSSetterEpscanTime() when epscanTime != null:
return epscanTime(_that);case RSSetterCantimeout() when cantimeout != null:
return cantimeout(_that);case RSSetterZeroSta() when zeroSta != null:
return zeroSta(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( RSSetterRunMode value)  runMode,required TResult Function( RSSetterIqRef value)  iqRef,required TResult Function( RSSetterSpdRef value)  spdRef,required TResult Function( RSSetterLimitTorque value)  limitTorque,required TResult Function( RSSetterCurKp value)  curKp,required TResult Function( RSSetterCurKi value)  curKi,required TResult Function( RSSetterCurFiltGain value)  curFiltGain,required TResult Function( RSSetterLocRef value)  locRef,required TResult Function( RSSetterLimitSpd value)  limitSpd,required TResult Function( RSSetterLimitCur value)  limitCur,required TResult Function( RSSetterLocKp value)  locKp,required TResult Function( RSSetterSpdKp value)  spdKp,required TResult Function( RSSetterSpdKi value)  spdKi,required TResult Function( RSSetterSpdFiltGain value)  spdFiltGain,required TResult Function( RSSetterAccRad value)  accRad,required TResult Function( RSSetterVelMax value)  velMax,required TResult Function( RSSetterAccSet value)  accSet,required TResult Function( RSSetterEpscanTime value)  epscanTime,required TResult Function( RSSetterCantimeout value)  cantimeout,required TResult Function( RSSetterZeroSta value)  zeroSta,}){
final _that = this;
switch (_that) {
case RSSetterRunMode():
return runMode(_that);case RSSetterIqRef():
return iqRef(_that);case RSSetterSpdRef():
return spdRef(_that);case RSSetterLimitTorque():
return limitTorque(_that);case RSSetterCurKp():
return curKp(_that);case RSSetterCurKi():
return curKi(_that);case RSSetterCurFiltGain():
return curFiltGain(_that);case RSSetterLocRef():
return locRef(_that);case RSSetterLimitSpd():
return limitSpd(_that);case RSSetterLimitCur():
return limitCur(_that);case RSSetterLocKp():
return locKp(_that);case RSSetterSpdKp():
return spdKp(_that);case RSSetterSpdKi():
return spdKi(_that);case RSSetterSpdFiltGain():
return spdFiltGain(_that);case RSSetterAccRad():
return accRad(_that);case RSSetterVelMax():
return velMax(_that);case RSSetterAccSet():
return accSet(_that);case RSSetterEpscanTime():
return epscanTime(_that);case RSSetterCantimeout():
return cantimeout(_that);case RSSetterZeroSta():
return zeroSta(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( RSSetterRunMode value)?  runMode,TResult? Function( RSSetterIqRef value)?  iqRef,TResult? Function( RSSetterSpdRef value)?  spdRef,TResult? Function( RSSetterLimitTorque value)?  limitTorque,TResult? Function( RSSetterCurKp value)?  curKp,TResult? Function( RSSetterCurKi value)?  curKi,TResult? Function( RSSetterCurFiltGain value)?  curFiltGain,TResult? Function( RSSetterLocRef value)?  locRef,TResult? Function( RSSetterLimitSpd value)?  limitSpd,TResult? Function( RSSetterLimitCur value)?  limitCur,TResult? Function( RSSetterLocKp value)?  locKp,TResult? Function( RSSetterSpdKp value)?  spdKp,TResult? Function( RSSetterSpdKi value)?  spdKi,TResult? Function( RSSetterSpdFiltGain value)?  spdFiltGain,TResult? Function( RSSetterAccRad value)?  accRad,TResult? Function( RSSetterVelMax value)?  velMax,TResult? Function( RSSetterAccSet value)?  accSet,TResult? Function( RSSetterEpscanTime value)?  epscanTime,TResult? Function( RSSetterCantimeout value)?  cantimeout,TResult? Function( RSSetterZeroSta value)?  zeroSta,}){
final _that = this;
switch (_that) {
case RSSetterRunMode() when runMode != null:
return runMode(_that);case RSSetterIqRef() when iqRef != null:
return iqRef(_that);case RSSetterSpdRef() when spdRef != null:
return spdRef(_that);case RSSetterLimitTorque() when limitTorque != null:
return limitTorque(_that);case RSSetterCurKp() when curKp != null:
return curKp(_that);case RSSetterCurKi() when curKi != null:
return curKi(_that);case RSSetterCurFiltGain() when curFiltGain != null:
return curFiltGain(_that);case RSSetterLocRef() when locRef != null:
return locRef(_that);case RSSetterLimitSpd() when limitSpd != null:
return limitSpd(_that);case RSSetterLimitCur() when limitCur != null:
return limitCur(_that);case RSSetterLocKp() when locKp != null:
return locKp(_that);case RSSetterSpdKp() when spdKp != null:
return spdKp(_that);case RSSetterSpdKi() when spdKi != null:
return spdKi(_that);case RSSetterSpdFiltGain() when spdFiltGain != null:
return spdFiltGain(_that);case RSSetterAccRad() when accRad != null:
return accRad(_that);case RSSetterVelMax() when velMax != null:
return velMax(_that);case RSSetterAccSet() when accSet != null:
return accSet(_that);case RSSetterEpscanTime() when epscanTime != null:
return epscanTime(_that);case RSSetterCantimeout() when cantimeout != null:
return cantimeout(_that);case RSSetterZeroSta() when zeroSta != null:
return zeroSta(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( RSRunMode value)?  runMode,TResult Function( double value)?  iqRef,TResult Function( double value)?  spdRef,TResult Function( double value)?  limitTorque,TResult Function( double value)?  curKp,TResult Function( double value)?  curKi,TResult Function( double value)?  curFiltGain,TResult Function( double value)?  locRef,TResult Function( double value)?  limitSpd,TResult Function( double value)?  limitCur,TResult Function( double value)?  locKp,TResult Function( double value)?  spdKp,TResult Function( double value)?  spdKi,TResult Function( double value)?  spdFiltGain,TResult Function( double value)?  accRad,TResult Function( double value)?  velMax,TResult Function( double value)?  accSet,TResult Function( int value)?  epscanTime,TResult Function( int value)?  cantimeout,TResult Function( bool value)?  zeroSta,required TResult orElse(),}) {final _that = this;
switch (_that) {
case RSSetterRunMode() when runMode != null:
return runMode(_that.value);case RSSetterIqRef() when iqRef != null:
return iqRef(_that.value);case RSSetterSpdRef() when spdRef != null:
return spdRef(_that.value);case RSSetterLimitTorque() when limitTorque != null:
return limitTorque(_that.value);case RSSetterCurKp() when curKp != null:
return curKp(_that.value);case RSSetterCurKi() when curKi != null:
return curKi(_that.value);case RSSetterCurFiltGain() when curFiltGain != null:
return curFiltGain(_that.value);case RSSetterLocRef() when locRef != null:
return locRef(_that.value);case RSSetterLimitSpd() when limitSpd != null:
return limitSpd(_that.value);case RSSetterLimitCur() when limitCur != null:
return limitCur(_that.value);case RSSetterLocKp() when locKp != null:
return locKp(_that.value);case RSSetterSpdKp() when spdKp != null:
return spdKp(_that.value);case RSSetterSpdKi() when spdKi != null:
return spdKi(_that.value);case RSSetterSpdFiltGain() when spdFiltGain != null:
return spdFiltGain(_that.value);case RSSetterAccRad() when accRad != null:
return accRad(_that.value);case RSSetterVelMax() when velMax != null:
return velMax(_that.value);case RSSetterAccSet() when accSet != null:
return accSet(_that.value);case RSSetterEpscanTime() when epscanTime != null:
return epscanTime(_that.value);case RSSetterCantimeout() when cantimeout != null:
return cantimeout(_that.value);case RSSetterZeroSta() when zeroSta != null:
return zeroSta(_that.value);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( RSRunMode value)  runMode,required TResult Function( double value)  iqRef,required TResult Function( double value)  spdRef,required TResult Function( double value)  limitTorque,required TResult Function( double value)  curKp,required TResult Function( double value)  curKi,required TResult Function( double value)  curFiltGain,required TResult Function( double value)  locRef,required TResult Function( double value)  limitSpd,required TResult Function( double value)  limitCur,required TResult Function( double value)  locKp,required TResult Function( double value)  spdKp,required TResult Function( double value)  spdKi,required TResult Function( double value)  spdFiltGain,required TResult Function( double value)  accRad,required TResult Function( double value)  velMax,required TResult Function( double value)  accSet,required TResult Function( int value)  epscanTime,required TResult Function( int value)  cantimeout,required TResult Function( bool value)  zeroSta,}) {final _that = this;
switch (_that) {
case RSSetterRunMode():
return runMode(_that.value);case RSSetterIqRef():
return iqRef(_that.value);case RSSetterSpdRef():
return spdRef(_that.value);case RSSetterLimitTorque():
return limitTorque(_that.value);case RSSetterCurKp():
return curKp(_that.value);case RSSetterCurKi():
return curKi(_that.value);case RSSetterCurFiltGain():
return curFiltGain(_that.value);case RSSetterLocRef():
return locRef(_that.value);case RSSetterLimitSpd():
return limitSpd(_that.value);case RSSetterLimitCur():
return limitCur(_that.value);case RSSetterLocKp():
return locKp(_that.value);case RSSetterSpdKp():
return spdKp(_that.value);case RSSetterSpdKi():
return spdKi(_that.value);case RSSetterSpdFiltGain():
return spdFiltGain(_that.value);case RSSetterAccRad():
return accRad(_that.value);case RSSetterVelMax():
return velMax(_that.value);case RSSetterAccSet():
return accSet(_that.value);case RSSetterEpscanTime():
return epscanTime(_that.value);case RSSetterCantimeout():
return cantimeout(_that.value);case RSSetterZeroSta():
return zeroSta(_that.value);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( RSRunMode value)?  runMode,TResult? Function( double value)?  iqRef,TResult? Function( double value)?  spdRef,TResult? Function( double value)?  limitTorque,TResult? Function( double value)?  curKp,TResult? Function( double value)?  curKi,TResult? Function( double value)?  curFiltGain,TResult? Function( double value)?  locRef,TResult? Function( double value)?  limitSpd,TResult? Function( double value)?  limitCur,TResult? Function( double value)?  locKp,TResult? Function( double value)?  spdKp,TResult? Function( double value)?  spdKi,TResult? Function( double value)?  spdFiltGain,TResult? Function( double value)?  accRad,TResult? Function( double value)?  velMax,TResult? Function( double value)?  accSet,TResult? Function( int value)?  epscanTime,TResult? Function( int value)?  cantimeout,TResult? Function( bool value)?  zeroSta,}) {final _that = this;
switch (_that) {
case RSSetterRunMode() when runMode != null:
return runMode(_that.value);case RSSetterIqRef() when iqRef != null:
return iqRef(_that.value);case RSSetterSpdRef() when spdRef != null:
return spdRef(_that.value);case RSSetterLimitTorque() when limitTorque != null:
return limitTorque(_that.value);case RSSetterCurKp() when curKp != null:
return curKp(_that.value);case RSSetterCurKi() when curKi != null:
return curKi(_that.value);case RSSetterCurFiltGain() when curFiltGain != null:
return curFiltGain(_that.value);case RSSetterLocRef() when locRef != null:
return locRef(_that.value);case RSSetterLimitSpd() when limitSpd != null:
return limitSpd(_that.value);case RSSetterLimitCur() when limitCur != null:
return limitCur(_that.value);case RSSetterLocKp() when locKp != null:
return locKp(_that.value);case RSSetterSpdKp() when spdKp != null:
return spdKp(_that.value);case RSSetterSpdKi() when spdKi != null:
return spdKi(_that.value);case RSSetterSpdFiltGain() when spdFiltGain != null:
return spdFiltGain(_that.value);case RSSetterAccRad() when accRad != null:
return accRad(_that.value);case RSSetterVelMax() when velMax != null:
return velMax(_that.value);case RSSetterAccSet() when accSet != null:
return accSet(_that.value);case RSSetterEpscanTime() when epscanTime != null:
return epscanTime(_that.value);case RSSetterCantimeout() when cantimeout != null:
return cantimeout(_that.value);case RSSetterZeroSta() when zeroSta != null:
return zeroSta(_that.value);case _:
  return null;

}
}

}

/// @nodoc


class RSSetterRunMode extends RSSetter {
   RSSetterRunMode(this.value): super._();
  

@override final  RSRunMode value;

/// Create a copy of RSSetter
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RSSetterRunModeCopyWith<RSSetterRunMode> get copyWith => _$RSSetterRunModeCopyWithImpl<RSSetterRunMode>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RSSetterRunMode&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,value);

@override
String toString() {
  return 'RSSetter.runMode(value: $value)';
}


}

/// @nodoc
abstract mixin class $RSSetterRunModeCopyWith<$Res> implements $RSSetterCopyWith<$Res> {
  factory $RSSetterRunModeCopyWith(RSSetterRunMode value, $Res Function(RSSetterRunMode) _then) = _$RSSetterRunModeCopyWithImpl;
@useResult
$Res call({
 RSRunMode value
});




}
/// @nodoc
class _$RSSetterRunModeCopyWithImpl<$Res>
    implements $RSSetterRunModeCopyWith<$Res> {
  _$RSSetterRunModeCopyWithImpl(this._self, this._then);

  final RSSetterRunMode _self;
  final $Res Function(RSSetterRunMode) _then;

/// Create a copy of RSSetter
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(RSSetterRunMode(
null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as RSRunMode,
  ));
}


}

/// @nodoc


class RSSetterIqRef extends RSSetter {
   RSSetterIqRef(this.value): super._();
  

@override final  double value;

/// Create a copy of RSSetter
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RSSetterIqRefCopyWith<RSSetterIqRef> get copyWith => _$RSSetterIqRefCopyWithImpl<RSSetterIqRef>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RSSetterIqRef&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,value);

@override
String toString() {
  return 'RSSetter.iqRef(value: $value)';
}


}

/// @nodoc
abstract mixin class $RSSetterIqRefCopyWith<$Res> implements $RSSetterCopyWith<$Res> {
  factory $RSSetterIqRefCopyWith(RSSetterIqRef value, $Res Function(RSSetterIqRef) _then) = _$RSSetterIqRefCopyWithImpl;
@useResult
$Res call({
 double value
});




}
/// @nodoc
class _$RSSetterIqRefCopyWithImpl<$Res>
    implements $RSSetterIqRefCopyWith<$Res> {
  _$RSSetterIqRefCopyWithImpl(this._self, this._then);

  final RSSetterIqRef _self;
  final $Res Function(RSSetterIqRef) _then;

/// Create a copy of RSSetter
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(RSSetterIqRef(
null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

/// @nodoc


class RSSetterSpdRef extends RSSetter {
   RSSetterSpdRef(this.value): super._();
  

@override final  double value;

/// Create a copy of RSSetter
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RSSetterSpdRefCopyWith<RSSetterSpdRef> get copyWith => _$RSSetterSpdRefCopyWithImpl<RSSetterSpdRef>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RSSetterSpdRef&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,value);

@override
String toString() {
  return 'RSSetter.spdRef(value: $value)';
}


}

/// @nodoc
abstract mixin class $RSSetterSpdRefCopyWith<$Res> implements $RSSetterCopyWith<$Res> {
  factory $RSSetterSpdRefCopyWith(RSSetterSpdRef value, $Res Function(RSSetterSpdRef) _then) = _$RSSetterSpdRefCopyWithImpl;
@useResult
$Res call({
 double value
});




}
/// @nodoc
class _$RSSetterSpdRefCopyWithImpl<$Res>
    implements $RSSetterSpdRefCopyWith<$Res> {
  _$RSSetterSpdRefCopyWithImpl(this._self, this._then);

  final RSSetterSpdRef _self;
  final $Res Function(RSSetterSpdRef) _then;

/// Create a copy of RSSetter
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(RSSetterSpdRef(
null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

/// @nodoc


class RSSetterLimitTorque extends RSSetter {
   RSSetterLimitTorque(this.value): super._();
  

@override final  double value;

/// Create a copy of RSSetter
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RSSetterLimitTorqueCopyWith<RSSetterLimitTorque> get copyWith => _$RSSetterLimitTorqueCopyWithImpl<RSSetterLimitTorque>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RSSetterLimitTorque&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,value);

@override
String toString() {
  return 'RSSetter.limitTorque(value: $value)';
}


}

/// @nodoc
abstract mixin class $RSSetterLimitTorqueCopyWith<$Res> implements $RSSetterCopyWith<$Res> {
  factory $RSSetterLimitTorqueCopyWith(RSSetterLimitTorque value, $Res Function(RSSetterLimitTorque) _then) = _$RSSetterLimitTorqueCopyWithImpl;
@useResult
$Res call({
 double value
});




}
/// @nodoc
class _$RSSetterLimitTorqueCopyWithImpl<$Res>
    implements $RSSetterLimitTorqueCopyWith<$Res> {
  _$RSSetterLimitTorqueCopyWithImpl(this._self, this._then);

  final RSSetterLimitTorque _self;
  final $Res Function(RSSetterLimitTorque) _then;

/// Create a copy of RSSetter
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(RSSetterLimitTorque(
null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

/// @nodoc


class RSSetterCurKp extends RSSetter {
   RSSetterCurKp(this.value): super._();
  

@override final  double value;

/// Create a copy of RSSetter
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RSSetterCurKpCopyWith<RSSetterCurKp> get copyWith => _$RSSetterCurKpCopyWithImpl<RSSetterCurKp>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RSSetterCurKp&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,value);

@override
String toString() {
  return 'RSSetter.curKp(value: $value)';
}


}

/// @nodoc
abstract mixin class $RSSetterCurKpCopyWith<$Res> implements $RSSetterCopyWith<$Res> {
  factory $RSSetterCurKpCopyWith(RSSetterCurKp value, $Res Function(RSSetterCurKp) _then) = _$RSSetterCurKpCopyWithImpl;
@useResult
$Res call({
 double value
});




}
/// @nodoc
class _$RSSetterCurKpCopyWithImpl<$Res>
    implements $RSSetterCurKpCopyWith<$Res> {
  _$RSSetterCurKpCopyWithImpl(this._self, this._then);

  final RSSetterCurKp _self;
  final $Res Function(RSSetterCurKp) _then;

/// Create a copy of RSSetter
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(RSSetterCurKp(
null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

/// @nodoc


class RSSetterCurKi extends RSSetter {
   RSSetterCurKi(this.value): super._();
  

@override final  double value;

/// Create a copy of RSSetter
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RSSetterCurKiCopyWith<RSSetterCurKi> get copyWith => _$RSSetterCurKiCopyWithImpl<RSSetterCurKi>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RSSetterCurKi&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,value);

@override
String toString() {
  return 'RSSetter.curKi(value: $value)';
}


}

/// @nodoc
abstract mixin class $RSSetterCurKiCopyWith<$Res> implements $RSSetterCopyWith<$Res> {
  factory $RSSetterCurKiCopyWith(RSSetterCurKi value, $Res Function(RSSetterCurKi) _then) = _$RSSetterCurKiCopyWithImpl;
@useResult
$Res call({
 double value
});




}
/// @nodoc
class _$RSSetterCurKiCopyWithImpl<$Res>
    implements $RSSetterCurKiCopyWith<$Res> {
  _$RSSetterCurKiCopyWithImpl(this._self, this._then);

  final RSSetterCurKi _self;
  final $Res Function(RSSetterCurKi) _then;

/// Create a copy of RSSetter
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(RSSetterCurKi(
null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

/// @nodoc


class RSSetterCurFiltGain extends RSSetter {
   RSSetterCurFiltGain(this.value): super._();
  

@override final  double value;

/// Create a copy of RSSetter
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RSSetterCurFiltGainCopyWith<RSSetterCurFiltGain> get copyWith => _$RSSetterCurFiltGainCopyWithImpl<RSSetterCurFiltGain>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RSSetterCurFiltGain&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,value);

@override
String toString() {
  return 'RSSetter.curFiltGain(value: $value)';
}


}

/// @nodoc
abstract mixin class $RSSetterCurFiltGainCopyWith<$Res> implements $RSSetterCopyWith<$Res> {
  factory $RSSetterCurFiltGainCopyWith(RSSetterCurFiltGain value, $Res Function(RSSetterCurFiltGain) _then) = _$RSSetterCurFiltGainCopyWithImpl;
@useResult
$Res call({
 double value
});




}
/// @nodoc
class _$RSSetterCurFiltGainCopyWithImpl<$Res>
    implements $RSSetterCurFiltGainCopyWith<$Res> {
  _$RSSetterCurFiltGainCopyWithImpl(this._self, this._then);

  final RSSetterCurFiltGain _self;
  final $Res Function(RSSetterCurFiltGain) _then;

/// Create a copy of RSSetter
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(RSSetterCurFiltGain(
null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

/// @nodoc


class RSSetterLocRef extends RSSetter {
   RSSetterLocRef(this.value): super._();
  

@override final  double value;

/// Create a copy of RSSetter
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RSSetterLocRefCopyWith<RSSetterLocRef> get copyWith => _$RSSetterLocRefCopyWithImpl<RSSetterLocRef>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RSSetterLocRef&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,value);

@override
String toString() {
  return 'RSSetter.locRef(value: $value)';
}


}

/// @nodoc
abstract mixin class $RSSetterLocRefCopyWith<$Res> implements $RSSetterCopyWith<$Res> {
  factory $RSSetterLocRefCopyWith(RSSetterLocRef value, $Res Function(RSSetterLocRef) _then) = _$RSSetterLocRefCopyWithImpl;
@useResult
$Res call({
 double value
});




}
/// @nodoc
class _$RSSetterLocRefCopyWithImpl<$Res>
    implements $RSSetterLocRefCopyWith<$Res> {
  _$RSSetterLocRefCopyWithImpl(this._self, this._then);

  final RSSetterLocRef _self;
  final $Res Function(RSSetterLocRef) _then;

/// Create a copy of RSSetter
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(RSSetterLocRef(
null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

/// @nodoc


class RSSetterLimitSpd extends RSSetter {
   RSSetterLimitSpd(this.value): super._();
  

@override final  double value;

/// Create a copy of RSSetter
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RSSetterLimitSpdCopyWith<RSSetterLimitSpd> get copyWith => _$RSSetterLimitSpdCopyWithImpl<RSSetterLimitSpd>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RSSetterLimitSpd&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,value);

@override
String toString() {
  return 'RSSetter.limitSpd(value: $value)';
}


}

/// @nodoc
abstract mixin class $RSSetterLimitSpdCopyWith<$Res> implements $RSSetterCopyWith<$Res> {
  factory $RSSetterLimitSpdCopyWith(RSSetterLimitSpd value, $Res Function(RSSetterLimitSpd) _then) = _$RSSetterLimitSpdCopyWithImpl;
@useResult
$Res call({
 double value
});




}
/// @nodoc
class _$RSSetterLimitSpdCopyWithImpl<$Res>
    implements $RSSetterLimitSpdCopyWith<$Res> {
  _$RSSetterLimitSpdCopyWithImpl(this._self, this._then);

  final RSSetterLimitSpd _self;
  final $Res Function(RSSetterLimitSpd) _then;

/// Create a copy of RSSetter
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(RSSetterLimitSpd(
null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

/// @nodoc


class RSSetterLimitCur extends RSSetter {
   RSSetterLimitCur(this.value): super._();
  

@override final  double value;

/// Create a copy of RSSetter
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RSSetterLimitCurCopyWith<RSSetterLimitCur> get copyWith => _$RSSetterLimitCurCopyWithImpl<RSSetterLimitCur>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RSSetterLimitCur&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,value);

@override
String toString() {
  return 'RSSetter.limitCur(value: $value)';
}


}

/// @nodoc
abstract mixin class $RSSetterLimitCurCopyWith<$Res> implements $RSSetterCopyWith<$Res> {
  factory $RSSetterLimitCurCopyWith(RSSetterLimitCur value, $Res Function(RSSetterLimitCur) _then) = _$RSSetterLimitCurCopyWithImpl;
@useResult
$Res call({
 double value
});




}
/// @nodoc
class _$RSSetterLimitCurCopyWithImpl<$Res>
    implements $RSSetterLimitCurCopyWith<$Res> {
  _$RSSetterLimitCurCopyWithImpl(this._self, this._then);

  final RSSetterLimitCur _self;
  final $Res Function(RSSetterLimitCur) _then;

/// Create a copy of RSSetter
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(RSSetterLimitCur(
null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

/// @nodoc


class RSSetterLocKp extends RSSetter {
   RSSetterLocKp(this.value): super._();
  

@override final  double value;

/// Create a copy of RSSetter
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RSSetterLocKpCopyWith<RSSetterLocKp> get copyWith => _$RSSetterLocKpCopyWithImpl<RSSetterLocKp>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RSSetterLocKp&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,value);

@override
String toString() {
  return 'RSSetter.locKp(value: $value)';
}


}

/// @nodoc
abstract mixin class $RSSetterLocKpCopyWith<$Res> implements $RSSetterCopyWith<$Res> {
  factory $RSSetterLocKpCopyWith(RSSetterLocKp value, $Res Function(RSSetterLocKp) _then) = _$RSSetterLocKpCopyWithImpl;
@useResult
$Res call({
 double value
});




}
/// @nodoc
class _$RSSetterLocKpCopyWithImpl<$Res>
    implements $RSSetterLocKpCopyWith<$Res> {
  _$RSSetterLocKpCopyWithImpl(this._self, this._then);

  final RSSetterLocKp _self;
  final $Res Function(RSSetterLocKp) _then;

/// Create a copy of RSSetter
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(RSSetterLocKp(
null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

/// @nodoc


class RSSetterSpdKp extends RSSetter {
   RSSetterSpdKp(this.value): super._();
  

@override final  double value;

/// Create a copy of RSSetter
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RSSetterSpdKpCopyWith<RSSetterSpdKp> get copyWith => _$RSSetterSpdKpCopyWithImpl<RSSetterSpdKp>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RSSetterSpdKp&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,value);

@override
String toString() {
  return 'RSSetter.spdKp(value: $value)';
}


}

/// @nodoc
abstract mixin class $RSSetterSpdKpCopyWith<$Res> implements $RSSetterCopyWith<$Res> {
  factory $RSSetterSpdKpCopyWith(RSSetterSpdKp value, $Res Function(RSSetterSpdKp) _then) = _$RSSetterSpdKpCopyWithImpl;
@useResult
$Res call({
 double value
});




}
/// @nodoc
class _$RSSetterSpdKpCopyWithImpl<$Res>
    implements $RSSetterSpdKpCopyWith<$Res> {
  _$RSSetterSpdKpCopyWithImpl(this._self, this._then);

  final RSSetterSpdKp _self;
  final $Res Function(RSSetterSpdKp) _then;

/// Create a copy of RSSetter
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(RSSetterSpdKp(
null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

/// @nodoc


class RSSetterSpdKi extends RSSetter {
   RSSetterSpdKi(this.value): super._();
  

@override final  double value;

/// Create a copy of RSSetter
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RSSetterSpdKiCopyWith<RSSetterSpdKi> get copyWith => _$RSSetterSpdKiCopyWithImpl<RSSetterSpdKi>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RSSetterSpdKi&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,value);

@override
String toString() {
  return 'RSSetter.spdKi(value: $value)';
}


}

/// @nodoc
abstract mixin class $RSSetterSpdKiCopyWith<$Res> implements $RSSetterCopyWith<$Res> {
  factory $RSSetterSpdKiCopyWith(RSSetterSpdKi value, $Res Function(RSSetterSpdKi) _then) = _$RSSetterSpdKiCopyWithImpl;
@useResult
$Res call({
 double value
});




}
/// @nodoc
class _$RSSetterSpdKiCopyWithImpl<$Res>
    implements $RSSetterSpdKiCopyWith<$Res> {
  _$RSSetterSpdKiCopyWithImpl(this._self, this._then);

  final RSSetterSpdKi _self;
  final $Res Function(RSSetterSpdKi) _then;

/// Create a copy of RSSetter
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(RSSetterSpdKi(
null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

/// @nodoc


class RSSetterSpdFiltGain extends RSSetter {
   RSSetterSpdFiltGain(this.value): super._();
  

@override final  double value;

/// Create a copy of RSSetter
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RSSetterSpdFiltGainCopyWith<RSSetterSpdFiltGain> get copyWith => _$RSSetterSpdFiltGainCopyWithImpl<RSSetterSpdFiltGain>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RSSetterSpdFiltGain&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,value);

@override
String toString() {
  return 'RSSetter.spdFiltGain(value: $value)';
}


}

/// @nodoc
abstract mixin class $RSSetterSpdFiltGainCopyWith<$Res> implements $RSSetterCopyWith<$Res> {
  factory $RSSetterSpdFiltGainCopyWith(RSSetterSpdFiltGain value, $Res Function(RSSetterSpdFiltGain) _then) = _$RSSetterSpdFiltGainCopyWithImpl;
@useResult
$Res call({
 double value
});




}
/// @nodoc
class _$RSSetterSpdFiltGainCopyWithImpl<$Res>
    implements $RSSetterSpdFiltGainCopyWith<$Res> {
  _$RSSetterSpdFiltGainCopyWithImpl(this._self, this._then);

  final RSSetterSpdFiltGain _self;
  final $Res Function(RSSetterSpdFiltGain) _then;

/// Create a copy of RSSetter
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(RSSetterSpdFiltGain(
null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

/// @nodoc


class RSSetterAccRad extends RSSetter {
   RSSetterAccRad(this.value): super._();
  

@override final  double value;

/// Create a copy of RSSetter
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RSSetterAccRadCopyWith<RSSetterAccRad> get copyWith => _$RSSetterAccRadCopyWithImpl<RSSetterAccRad>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RSSetterAccRad&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,value);

@override
String toString() {
  return 'RSSetter.accRad(value: $value)';
}


}

/// @nodoc
abstract mixin class $RSSetterAccRadCopyWith<$Res> implements $RSSetterCopyWith<$Res> {
  factory $RSSetterAccRadCopyWith(RSSetterAccRad value, $Res Function(RSSetterAccRad) _then) = _$RSSetterAccRadCopyWithImpl;
@useResult
$Res call({
 double value
});




}
/// @nodoc
class _$RSSetterAccRadCopyWithImpl<$Res>
    implements $RSSetterAccRadCopyWith<$Res> {
  _$RSSetterAccRadCopyWithImpl(this._self, this._then);

  final RSSetterAccRad _self;
  final $Res Function(RSSetterAccRad) _then;

/// Create a copy of RSSetter
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(RSSetterAccRad(
null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

/// @nodoc


class RSSetterVelMax extends RSSetter {
   RSSetterVelMax(this.value): super._();
  

@override final  double value;

/// Create a copy of RSSetter
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RSSetterVelMaxCopyWith<RSSetterVelMax> get copyWith => _$RSSetterVelMaxCopyWithImpl<RSSetterVelMax>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RSSetterVelMax&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,value);

@override
String toString() {
  return 'RSSetter.velMax(value: $value)';
}


}

/// @nodoc
abstract mixin class $RSSetterVelMaxCopyWith<$Res> implements $RSSetterCopyWith<$Res> {
  factory $RSSetterVelMaxCopyWith(RSSetterVelMax value, $Res Function(RSSetterVelMax) _then) = _$RSSetterVelMaxCopyWithImpl;
@useResult
$Res call({
 double value
});




}
/// @nodoc
class _$RSSetterVelMaxCopyWithImpl<$Res>
    implements $RSSetterVelMaxCopyWith<$Res> {
  _$RSSetterVelMaxCopyWithImpl(this._self, this._then);

  final RSSetterVelMax _self;
  final $Res Function(RSSetterVelMax) _then;

/// Create a copy of RSSetter
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(RSSetterVelMax(
null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

/// @nodoc


class RSSetterAccSet extends RSSetter {
   RSSetterAccSet(this.value): super._();
  

@override final  double value;

/// Create a copy of RSSetter
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RSSetterAccSetCopyWith<RSSetterAccSet> get copyWith => _$RSSetterAccSetCopyWithImpl<RSSetterAccSet>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RSSetterAccSet&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,value);

@override
String toString() {
  return 'RSSetter.accSet(value: $value)';
}


}

/// @nodoc
abstract mixin class $RSSetterAccSetCopyWith<$Res> implements $RSSetterCopyWith<$Res> {
  factory $RSSetterAccSetCopyWith(RSSetterAccSet value, $Res Function(RSSetterAccSet) _then) = _$RSSetterAccSetCopyWithImpl;
@useResult
$Res call({
 double value
});




}
/// @nodoc
class _$RSSetterAccSetCopyWithImpl<$Res>
    implements $RSSetterAccSetCopyWith<$Res> {
  _$RSSetterAccSetCopyWithImpl(this._self, this._then);

  final RSSetterAccSet _self;
  final $Res Function(RSSetterAccSet) _then;

/// Create a copy of RSSetter
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(RSSetterAccSet(
null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

/// @nodoc


class RSSetterEpscanTime extends RSSetter {
   RSSetterEpscanTime(this.value): super._();
  

@override final  int value;

/// Create a copy of RSSetter
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RSSetterEpscanTimeCopyWith<RSSetterEpscanTime> get copyWith => _$RSSetterEpscanTimeCopyWithImpl<RSSetterEpscanTime>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RSSetterEpscanTime&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,value);

@override
String toString() {
  return 'RSSetter.epscanTime(value: $value)';
}


}

/// @nodoc
abstract mixin class $RSSetterEpscanTimeCopyWith<$Res> implements $RSSetterCopyWith<$Res> {
  factory $RSSetterEpscanTimeCopyWith(RSSetterEpscanTime value, $Res Function(RSSetterEpscanTime) _then) = _$RSSetterEpscanTimeCopyWithImpl;
@useResult
$Res call({
 int value
});




}
/// @nodoc
class _$RSSetterEpscanTimeCopyWithImpl<$Res>
    implements $RSSetterEpscanTimeCopyWith<$Res> {
  _$RSSetterEpscanTimeCopyWithImpl(this._self, this._then);

  final RSSetterEpscanTime _self;
  final $Res Function(RSSetterEpscanTime) _then;

/// Create a copy of RSSetter
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(RSSetterEpscanTime(
null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class RSSetterCantimeout extends RSSetter {
   RSSetterCantimeout(this.value): super._();
  

@override final  int value;

/// Create a copy of RSSetter
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RSSetterCantimeoutCopyWith<RSSetterCantimeout> get copyWith => _$RSSetterCantimeoutCopyWithImpl<RSSetterCantimeout>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RSSetterCantimeout&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,value);

@override
String toString() {
  return 'RSSetter.cantimeout(value: $value)';
}


}

/// @nodoc
abstract mixin class $RSSetterCantimeoutCopyWith<$Res> implements $RSSetterCopyWith<$Res> {
  factory $RSSetterCantimeoutCopyWith(RSSetterCantimeout value, $Res Function(RSSetterCantimeout) _then) = _$RSSetterCantimeoutCopyWithImpl;
@useResult
$Res call({
 int value
});




}
/// @nodoc
class _$RSSetterCantimeoutCopyWithImpl<$Res>
    implements $RSSetterCantimeoutCopyWith<$Res> {
  _$RSSetterCantimeoutCopyWithImpl(this._self, this._then);

  final RSSetterCantimeout _self;
  final $Res Function(RSSetterCantimeout) _then;

/// Create a copy of RSSetter
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(RSSetterCantimeout(
null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class RSSetterZeroSta extends RSSetter {
   RSSetterZeroSta(this.value): super._();
  

@override final  bool value;

/// Create a copy of RSSetter
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RSSetterZeroStaCopyWith<RSSetterZeroSta> get copyWith => _$RSSetterZeroStaCopyWithImpl<RSSetterZeroSta>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RSSetterZeroSta&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,value);

@override
String toString() {
  return 'RSSetter.zeroSta(value: $value)';
}


}

/// @nodoc
abstract mixin class $RSSetterZeroStaCopyWith<$Res> implements $RSSetterCopyWith<$Res> {
  factory $RSSetterZeroStaCopyWith(RSSetterZeroSta value, $Res Function(RSSetterZeroSta) _then) = _$RSSetterZeroStaCopyWithImpl;
@useResult
$Res call({
 bool value
});




}
/// @nodoc
class _$RSSetterZeroStaCopyWithImpl<$Res>
    implements $RSSetterZeroStaCopyWith<$Res> {
  _$RSSetterZeroStaCopyWithImpl(this._self, this._then);

  final RSSetterZeroSta _self;
  final $Res Function(RSSetterZeroSta) _then;

/// Create a copy of RSSetter
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(RSSetterZeroSta(
null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
