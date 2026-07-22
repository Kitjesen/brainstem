// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'common.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$Command {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Command);
}


@override
int get hashCode => runtimeType.hashCode;



}

/// @nodoc
class $CommandCopyWith<$Res>  {
$CommandCopyWith(Command _, $Res Function(Command) __);
}


/// Adds pattern-matching-related methods to [Command].
extension CommandPatterns on Command {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( IdleCommand value)?  idle,TResult Function( StandUpCommand value)?  standUp,TResult Function( SitDownCommand value)?  sitDown,TResult Function( WalkCommand value)?  walk,TResult Function( GestureCommand value)?  gesture,required TResult orElse(),}){
final _that = this;
switch (_that) {
case IdleCommand() when idle != null:
return idle(_that);case StandUpCommand() when standUp != null:
return standUp(_that);case SitDownCommand() when sitDown != null:
return sitDown(_that);case WalkCommand() when walk != null:
return walk(_that);case GestureCommand() when gesture != null:
return gesture(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( IdleCommand value)  idle,required TResult Function( StandUpCommand value)  standUp,required TResult Function( SitDownCommand value)  sitDown,required TResult Function( WalkCommand value)  walk,required TResult Function( GestureCommand value)  gesture,}){
final _that = this;
switch (_that) {
case IdleCommand():
return idle(_that);case StandUpCommand():
return standUp(_that);case SitDownCommand():
return sitDown(_that);case WalkCommand():
return walk(_that);case GestureCommand():
return gesture(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( IdleCommand value)?  idle,TResult? Function( StandUpCommand value)?  standUp,TResult? Function( SitDownCommand value)?  sitDown,TResult? Function( WalkCommand value)?  walk,TResult? Function( GestureCommand value)?  gesture,}){
final _that = this;
switch (_that) {
case IdleCommand() when idle != null:
return idle(_that);case StandUpCommand() when standUp != null:
return standUp(_that);case SitDownCommand() when sitDown != null:
return sitDown(_that);case WalkCommand() when walk != null:
return walk(_that);case GestureCommand() when gesture != null:
return gesture(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  idle,TResult Function()?  standUp,TResult Function()?  sitDown,TResult Function( Vector3 direction)?  walk,TResult Function( String name)?  gesture,required TResult orElse(),}) {final _that = this;
switch (_that) {
case IdleCommand() when idle != null:
return idle();case StandUpCommand() when standUp != null:
return standUp();case SitDownCommand() when sitDown != null:
return sitDown();case WalkCommand() when walk != null:
return walk(_that.direction);case GestureCommand() when gesture != null:
return gesture(_that.name);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  idle,required TResult Function()  standUp,required TResult Function()  sitDown,required TResult Function( Vector3 direction)  walk,required TResult Function( String name)  gesture,}) {final _that = this;
switch (_that) {
case IdleCommand():
return idle();case StandUpCommand():
return standUp();case SitDownCommand():
return sitDown();case WalkCommand():
return walk(_that.direction);case GestureCommand():
return gesture(_that.name);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  idle,TResult? Function()?  standUp,TResult? Function()?  sitDown,TResult? Function( Vector3 direction)?  walk,TResult? Function( String name)?  gesture,}) {final _that = this;
switch (_that) {
case IdleCommand() when idle != null:
return idle();case StandUpCommand() when standUp != null:
return standUp();case SitDownCommand() when sitDown != null:
return sitDown();case WalkCommand() when walk != null:
return walk(_that.direction);case GestureCommand() when gesture != null:
return gesture(_that.name);case _:
  return null;

}
}

}

/// @nodoc


class IdleCommand extends Command {
  const IdleCommand(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is IdleCommand);
}


@override
int get hashCode => runtimeType.hashCode;



}




/// @nodoc


class StandUpCommand extends Command {
  const StandUpCommand(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StandUpCommand);
}


@override
int get hashCode => runtimeType.hashCode;



}




/// @nodoc


class SitDownCommand extends Command {
  const SitDownCommand(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SitDownCommand);
}


@override
int get hashCode => runtimeType.hashCode;



}




/// @nodoc


class WalkCommand extends Command {
  const WalkCommand(this.direction): super._();
  

 final  Vector3 direction;

/// Create a copy of Command
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$WalkCommandCopyWith<WalkCommand> get copyWith => _$WalkCommandCopyWithImpl<WalkCommand>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is WalkCommand&&(identical(other.direction, direction) || other.direction == direction));
}


@override
int get hashCode => Object.hash(runtimeType,direction);



}

/// @nodoc
abstract mixin class $WalkCommandCopyWith<$Res> implements $CommandCopyWith<$Res> {
  factory $WalkCommandCopyWith(WalkCommand value, $Res Function(WalkCommand) _then) = _$WalkCommandCopyWithImpl;
@useResult
$Res call({
 Vector3 direction
});




}
/// @nodoc
class _$WalkCommandCopyWithImpl<$Res>
    implements $WalkCommandCopyWith<$Res> {
  _$WalkCommandCopyWithImpl(this._self, this._then);

  final WalkCommand _self;
  final $Res Function(WalkCommand) _then;

/// Create a copy of Command
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? direction = null,}) {
  return _then(WalkCommand(
null == direction ? _self.direction : direction // ignore: cast_nullable_to_non_nullable
as Vector3,
  ));
}


}

/// @nodoc


class GestureCommand extends Command {
  const GestureCommand(this.name): super._();
  

 final  String name;

/// Create a copy of Command
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$GestureCommandCopyWith<GestureCommand> get copyWith => _$GestureCommandCopyWithImpl<GestureCommand>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GestureCommand&&(identical(other.name, name) || other.name == name));
}


@override
int get hashCode => Object.hash(runtimeType,name);



}

/// @nodoc
abstract mixin class $GestureCommandCopyWith<$Res> implements $CommandCopyWith<$Res> {
  factory $GestureCommandCopyWith(GestureCommand value, $Res Function(GestureCommand) _then) = _$GestureCommandCopyWithImpl;
@useResult
$Res call({
 String name
});




}
/// @nodoc
class _$GestureCommandCopyWithImpl<$Res>
    implements $GestureCommandCopyWith<$Res> {
  _$GestureCommandCopyWithImpl(this._self, this._then);

  final GestureCommand _self;
  final $Res Function(GestureCommand) _then;

/// Create a copy of Command
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? name = null,}) {
  return _then(GestureCommand(
null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$History {

 Vector3 get gyroscope; Vector3 get projectedGravity; Command get command; double get bodyHeightCommand; JointsMatrix get jointPosition; JointsMatrix get jointVelocity; JointsMatrix get action; JointsMatrix get nextAction;
/// Create a copy of History
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$HistoryCopyWith<History> get copyWith => _$HistoryCopyWithImpl<History>(this as History, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is History&&(identical(other.gyroscope, gyroscope) || other.gyroscope == gyroscope)&&(identical(other.projectedGravity, projectedGravity) || other.projectedGravity == projectedGravity)&&(identical(other.command, command) || other.command == command)&&(identical(other.bodyHeightCommand, bodyHeightCommand) || other.bodyHeightCommand == bodyHeightCommand)&&(identical(other.jointPosition, jointPosition) || other.jointPosition == jointPosition)&&(identical(other.jointVelocity, jointVelocity) || other.jointVelocity == jointVelocity)&&(identical(other.action, action) || other.action == action)&&(identical(other.nextAction, nextAction) || other.nextAction == nextAction));
}


@override
int get hashCode => Object.hash(runtimeType,gyroscope,projectedGravity,command,bodyHeightCommand,jointPosition,jointVelocity,action,nextAction);



}

/// @nodoc
abstract mixin class $HistoryCopyWith<$Res>  {
  factory $HistoryCopyWith(History value, $Res Function(History) _then) = _$HistoryCopyWithImpl;
@useResult
$Res call({
 Vector3 gyroscope, Vector3 projectedGravity, Command command, double bodyHeightCommand, JointsMatrix jointPosition, JointsMatrix jointVelocity, JointsMatrix action, JointsMatrix nextAction
});


$CommandCopyWith<$Res> get command;

}
/// @nodoc
class _$HistoryCopyWithImpl<$Res>
    implements $HistoryCopyWith<$Res> {
  _$HistoryCopyWithImpl(this._self, this._then);

  final History _self;
  final $Res Function(History) _then;

/// Create a copy of History
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? gyroscope = null,Object? projectedGravity = null,Object? command = null,Object? bodyHeightCommand = null,Object? jointPosition = null,Object? jointVelocity = null,Object? action = null,Object? nextAction = null,}) {
  return _then(_self.copyWith(
gyroscope: null == gyroscope ? _self.gyroscope : gyroscope // ignore: cast_nullable_to_non_nullable
as Vector3,projectedGravity: null == projectedGravity ? _self.projectedGravity : projectedGravity // ignore: cast_nullable_to_non_nullable
as Vector3,command: null == command ? _self.command : command // ignore: cast_nullable_to_non_nullable
as Command,bodyHeightCommand: null == bodyHeightCommand ? _self.bodyHeightCommand : bodyHeightCommand // ignore: cast_nullable_to_non_nullable
as double,jointPosition: null == jointPosition ? _self.jointPosition : jointPosition // ignore: cast_nullable_to_non_nullable
as JointsMatrix,jointVelocity: null == jointVelocity ? _self.jointVelocity : jointVelocity // ignore: cast_nullable_to_non_nullable
as JointsMatrix,action: null == action ? _self.action : action // ignore: cast_nullable_to_non_nullable
as JointsMatrix,nextAction: null == nextAction ? _self.nextAction : nextAction // ignore: cast_nullable_to_non_nullable
as JointsMatrix,
  ));
}
/// Create a copy of History
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CommandCopyWith<$Res> get command {
  
  return $CommandCopyWith<$Res>(_self.command, (value) {
    return _then(_self.copyWith(command: value));
  });
}
}


/// Adds pattern-matching-related methods to [History].
extension HistoryPatterns on History {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _History value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _History() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _History value)  $default,){
final _that = this;
switch (_that) {
case _History():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _History value)?  $default,){
final _that = this;
switch (_that) {
case _History() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( Vector3 gyroscope,  Vector3 projectedGravity,  Command command,  double bodyHeightCommand,  JointsMatrix jointPosition,  JointsMatrix jointVelocity,  JointsMatrix action,  JointsMatrix nextAction)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _History() when $default != null:
return $default(_that.gyroscope,_that.projectedGravity,_that.command,_that.bodyHeightCommand,_that.jointPosition,_that.jointVelocity,_that.action,_that.nextAction);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( Vector3 gyroscope,  Vector3 projectedGravity,  Command command,  double bodyHeightCommand,  JointsMatrix jointPosition,  JointsMatrix jointVelocity,  JointsMatrix action,  JointsMatrix nextAction)  $default,) {final _that = this;
switch (_that) {
case _History():
return $default(_that.gyroscope,_that.projectedGravity,_that.command,_that.bodyHeightCommand,_that.jointPosition,_that.jointVelocity,_that.action,_that.nextAction);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( Vector3 gyroscope,  Vector3 projectedGravity,  Command command,  double bodyHeightCommand,  JointsMatrix jointPosition,  JointsMatrix jointVelocity,  JointsMatrix action,  JointsMatrix nextAction)?  $default,) {final _that = this;
switch (_that) {
case _History() when $default != null:
return $default(_that.gyroscope,_that.projectedGravity,_that.command,_that.bodyHeightCommand,_that.jointPosition,_that.jointVelocity,_that.action,_that.nextAction);case _:
  return null;

}
}

}

/// @nodoc


class _History extends History {
  const _History({required this.gyroscope, required this.projectedGravity, required this.command, this.bodyHeightCommand = 0.35, required this.jointPosition, required this.jointVelocity, required this.action, required this.nextAction}): super._();
  

@override final  Vector3 gyroscope;
@override final  Vector3 projectedGravity;
@override final  Command command;
@override@JsonKey() final  double bodyHeightCommand;
@override final  JointsMatrix jointPosition;
@override final  JointsMatrix jointVelocity;
@override final  JointsMatrix action;
@override final  JointsMatrix nextAction;

/// Create a copy of History
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$HistoryCopyWith<_History> get copyWith => __$HistoryCopyWithImpl<_History>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _History&&(identical(other.gyroscope, gyroscope) || other.gyroscope == gyroscope)&&(identical(other.projectedGravity, projectedGravity) || other.projectedGravity == projectedGravity)&&(identical(other.command, command) || other.command == command)&&(identical(other.bodyHeightCommand, bodyHeightCommand) || other.bodyHeightCommand == bodyHeightCommand)&&(identical(other.jointPosition, jointPosition) || other.jointPosition == jointPosition)&&(identical(other.jointVelocity, jointVelocity) || other.jointVelocity == jointVelocity)&&(identical(other.action, action) || other.action == action)&&(identical(other.nextAction, nextAction) || other.nextAction == nextAction));
}


@override
int get hashCode => Object.hash(runtimeType,gyroscope,projectedGravity,command,bodyHeightCommand,jointPosition,jointVelocity,action,nextAction);



}

/// @nodoc
abstract mixin class _$HistoryCopyWith<$Res> implements $HistoryCopyWith<$Res> {
  factory _$HistoryCopyWith(_History value, $Res Function(_History) _then) = __$HistoryCopyWithImpl;
@override @useResult
$Res call({
 Vector3 gyroscope, Vector3 projectedGravity, Command command, double bodyHeightCommand, JointsMatrix jointPosition, JointsMatrix jointVelocity, JointsMatrix action, JointsMatrix nextAction
});


@override $CommandCopyWith<$Res> get command;

}
/// @nodoc
class __$HistoryCopyWithImpl<$Res>
    implements _$HistoryCopyWith<$Res> {
  __$HistoryCopyWithImpl(this._self, this._then);

  final _History _self;
  final $Res Function(_History) _then;

/// Create a copy of History
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? gyroscope = null,Object? projectedGravity = null,Object? command = null,Object? bodyHeightCommand = null,Object? jointPosition = null,Object? jointVelocity = null,Object? action = null,Object? nextAction = null,}) {
  return _then(_History(
gyroscope: null == gyroscope ? _self.gyroscope : gyroscope // ignore: cast_nullable_to_non_nullable
as Vector3,projectedGravity: null == projectedGravity ? _self.projectedGravity : projectedGravity // ignore: cast_nullable_to_non_nullable
as Vector3,command: null == command ? _self.command : command // ignore: cast_nullable_to_non_nullable
as Command,bodyHeightCommand: null == bodyHeightCommand ? _self.bodyHeightCommand : bodyHeightCommand // ignore: cast_nullable_to_non_nullable
as double,jointPosition: null == jointPosition ? _self.jointPosition : jointPosition // ignore: cast_nullable_to_non_nullable
as JointsMatrix,jointVelocity: null == jointVelocity ? _self.jointVelocity : jointVelocity // ignore: cast_nullable_to_non_nullable
as JointsMatrix,action: null == action ? _self.action : action // ignore: cast_nullable_to_non_nullable
as JointsMatrix,nextAction: null == nextAction ? _self.nextAction : nextAction // ignore: cast_nullable_to_non_nullable
as JointsMatrix,
  ));
}

/// Create a copy of History
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CommandCopyWith<$Res> get command {
  
  return $CommandCopyWith<$Res>(_self.command, (value) {
    return _then(_self.copyWith(command: value));
  });
}
}

// dart format on
