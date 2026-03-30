// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'a.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$A {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is A);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'A()';
}


}

/// @nodoc
class $ACopyWith<$Res>  {
$ACopyWith(A _, $Res Function(A) __);
}


/// Adds pattern-matching-related methods to [A].
extension APatterns on A {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( Init value)?  init,TResult Function( CmdStandUp value)?  standUp,TResult Function( CmdSitDown value)?  sitDown,TResult Function( CmdWalk value)?  walk,TResult Function( CmdIdle value)?  idle,TResult Function( CmdGesture value)?  gesture,TResult Function( Fault value)?  fault,TResult Function( Done value)?  done,required TResult orElse(),}){
final _that = this;
switch (_that) {
case Init() when init != null:
return init(_that);case CmdStandUp() when standUp != null:
return standUp(_that);case CmdSitDown() when sitDown != null:
return sitDown(_that);case CmdWalk() when walk != null:
return walk(_that);case CmdIdle() when idle != null:
return idle(_that);case CmdGesture() when gesture != null:
return gesture(_that);case Fault() when fault != null:
return fault(_that);case Done() when done != null:
return done(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( Init value)  init,required TResult Function( CmdStandUp value)  standUp,required TResult Function( CmdSitDown value)  sitDown,required TResult Function( CmdWalk value)  walk,required TResult Function( CmdIdle value)  idle,required TResult Function( CmdGesture value)  gesture,required TResult Function( Fault value)  fault,required TResult Function( Done value)  done,}){
final _that = this;
switch (_that) {
case Init():
return init(_that);case CmdStandUp():
return standUp(_that);case CmdSitDown():
return sitDown(_that);case CmdWalk():
return walk(_that);case CmdIdle():
return idle(_that);case CmdGesture():
return gesture(_that);case Fault():
return fault(_that);case Done():
return done(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( Init value)?  init,TResult? Function( CmdStandUp value)?  standUp,TResult? Function( CmdSitDown value)?  sitDown,TResult? Function( CmdWalk value)?  walk,TResult? Function( CmdIdle value)?  idle,TResult? Function( CmdGesture value)?  gesture,TResult? Function( Fault value)?  fault,TResult? Function( Done value)?  done,}){
final _that = this;
switch (_that) {
case Init() when init != null:
return init(_that);case CmdStandUp() when standUp != null:
return standUp(_that);case CmdSitDown() when sitDown != null:
return sitDown(_that);case CmdWalk() when walk != null:
return walk(_that);case CmdIdle() when idle != null:
return idle(_that);case CmdGesture() when gesture != null:
return gesture(_that);case Fault() when fault != null:
return fault(_that);case Done() when done != null:
return done(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  init,TResult Function()?  standUp,TResult Function()?  sitDown,TResult Function( Vector3 direction)?  walk,TResult Function()?  idle,TResult Function( String name)?  gesture,TResult Function( String reason)?  fault,TResult Function()?  done,required TResult orElse(),}) {final _that = this;
switch (_that) {
case Init() when init != null:
return init();case CmdStandUp() when standUp != null:
return standUp();case CmdSitDown() when sitDown != null:
return sitDown();case CmdWalk() when walk != null:
return walk(_that.direction);case CmdIdle() when idle != null:
return idle();case CmdGesture() when gesture != null:
return gesture(_that.name);case Fault() when fault != null:
return fault(_that.reason);case Done() when done != null:
return done();case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  init,required TResult Function()  standUp,required TResult Function()  sitDown,required TResult Function( Vector3 direction)  walk,required TResult Function()  idle,required TResult Function( String name)  gesture,required TResult Function( String reason)  fault,required TResult Function()  done,}) {final _that = this;
switch (_that) {
case Init():
return init();case CmdStandUp():
return standUp();case CmdSitDown():
return sitDown();case CmdWalk():
return walk(_that.direction);case CmdIdle():
return idle();case CmdGesture():
return gesture(_that.name);case Fault():
return fault(_that.reason);case Done():
return done();}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  init,TResult? Function()?  standUp,TResult? Function()?  sitDown,TResult? Function( Vector3 direction)?  walk,TResult? Function()?  idle,TResult? Function( String name)?  gesture,TResult? Function( String reason)?  fault,TResult? Function()?  done,}) {final _that = this;
switch (_that) {
case Init() when init != null:
return init();case CmdStandUp() when standUp != null:
return standUp();case CmdSitDown() when sitDown != null:
return sitDown();case CmdWalk() when walk != null:
return walk(_that.direction);case CmdIdle() when idle != null:
return idle();case CmdGesture() when gesture != null:
return gesture(_that.name);case Fault() when fault != null:
return fault(_that.reason);case Done() when done != null:
return done();case _:
  return null;

}
}

}

/// @nodoc


class Init implements A {
  const Init();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Init);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'A.init()';
}


}




/// @nodoc


class CmdStandUp implements A {
  const CmdStandUp();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CmdStandUp);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'A.standUp()';
}


}




/// @nodoc


class CmdSitDown implements A {
  const CmdSitDown();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CmdSitDown);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'A.sitDown()';
}


}




/// @nodoc


class CmdWalk implements A {
  const CmdWalk(this.direction);
  

 final  Vector3 direction;

/// Create a copy of A
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CmdWalkCopyWith<CmdWalk> get copyWith => _$CmdWalkCopyWithImpl<CmdWalk>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CmdWalk&&(identical(other.direction, direction) || other.direction == direction));
}


@override
int get hashCode => Object.hash(runtimeType,direction);

@override
String toString() {
  return 'A.walk(direction: $direction)';
}


}

/// @nodoc
abstract mixin class $CmdWalkCopyWith<$Res> implements $ACopyWith<$Res> {
  factory $CmdWalkCopyWith(CmdWalk value, $Res Function(CmdWalk) _then) = _$CmdWalkCopyWithImpl;
@useResult
$Res call({
 Vector3 direction
});




}
/// @nodoc
class _$CmdWalkCopyWithImpl<$Res>
    implements $CmdWalkCopyWith<$Res> {
  _$CmdWalkCopyWithImpl(this._self, this._then);

  final CmdWalk _self;
  final $Res Function(CmdWalk) _then;

/// Create a copy of A
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? direction = null,}) {
  return _then(CmdWalk(
null == direction ? _self.direction : direction // ignore: cast_nullable_to_non_nullable
as Vector3,
  ));
}


}

/// @nodoc


class CmdIdle implements A {
  const CmdIdle();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CmdIdle);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'A.idle()';
}


}




/// @nodoc


class CmdGesture implements A {
  const CmdGesture(this.name);
  

 final  String name;

/// Create a copy of A
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CmdGestureCopyWith<CmdGesture> get copyWith => _$CmdGestureCopyWithImpl<CmdGesture>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CmdGesture&&(identical(other.name, name) || other.name == name));
}


@override
int get hashCode => Object.hash(runtimeType,name);

@override
String toString() {
  return 'A.gesture(name: $name)';
}


}

/// @nodoc
abstract mixin class $CmdGestureCopyWith<$Res> implements $ACopyWith<$Res> {
  factory $CmdGestureCopyWith(CmdGesture value, $Res Function(CmdGesture) _then) = _$CmdGestureCopyWithImpl;
@useResult
$Res call({
 String name
});




}
/// @nodoc
class _$CmdGestureCopyWithImpl<$Res>
    implements $CmdGestureCopyWith<$Res> {
  _$CmdGestureCopyWithImpl(this._self, this._then);

  final CmdGesture _self;
  final $Res Function(CmdGesture) _then;

/// Create a copy of A
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? name = null,}) {
  return _then(CmdGesture(
null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class Fault implements A {
  const Fault(this.reason);
  

 final  String reason;

/// Create a copy of A
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FaultCopyWith<Fault> get copyWith => _$FaultCopyWithImpl<Fault>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Fault&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode => Object.hash(runtimeType,reason);

@override
String toString() {
  return 'A.fault(reason: $reason)';
}


}

/// @nodoc
abstract mixin class $FaultCopyWith<$Res> implements $ACopyWith<$Res> {
  factory $FaultCopyWith(Fault value, $Res Function(Fault) _then) = _$FaultCopyWithImpl;
@useResult
$Res call({
 String reason
});




}
/// @nodoc
class _$FaultCopyWithImpl<$Res>
    implements $FaultCopyWith<$Res> {
  _$FaultCopyWithImpl(this._self, this._then);

  final Fault _self;
  final $Res Function(Fault) _then;

/// Create a copy of A
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? reason = null,}) {
  return _then(Fault(
null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class Done implements A {
  const Done();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Done);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'A.done()';
}


}




// dart format on
