// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 's.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$S {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is S);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'S()';
}


}

/// @nodoc
class $SCopyWith<$Res>  {
$SCopyWith(S _, $Res Function(S) __);
}


/// Adds pattern-matching-related methods to [S].
extension SPatterns on S {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( Zero value)?  zero,TResult Function( Grounded value)?  grounded,TResult Function( Standing value)?  standing,TResult Function( Walking value)?  walking,TResult Function( Transitioning value)?  transitioning,required TResult orElse(),}){
final _that = this;
switch (_that) {
case Zero() when zero != null:
return zero(_that);case Grounded() when grounded != null:
return grounded(_that);case Standing() when standing != null:
return standing(_that);case Walking() when walking != null:
return walking(_that);case Transitioning() when transitioning != null:
return transitioning(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( Zero value)  zero,required TResult Function( Grounded value)  grounded,required TResult Function( Standing value)  standing,required TResult Function( Walking value)  walking,required TResult Function( Transitioning value)  transitioning,}){
final _that = this;
switch (_that) {
case Zero():
return zero(_that);case Grounded():
return grounded(_that);case Standing():
return standing(_that);case Walking():
return walking(_that);case Transitioning():
return transitioning(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( Zero value)?  zero,TResult? Function( Grounded value)?  grounded,TResult? Function( Standing value)?  standing,TResult? Function( Walking value)?  walking,TResult? Function( Transitioning value)?  transitioning,}){
final _that = this;
switch (_that) {
case Zero() when zero != null:
return zero(_that);case Grounded() when grounded != null:
return grounded(_that);case Standing() when standing != null:
return standing(_that);case Walking() when walking != null:
return walking(_that);case Transitioning() when transitioning != null:
return transitioning(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  zero,TResult Function( StreamSubscription<History> sub)?  grounded,TResult Function( StreamSubscription<History> sub)?  standing,TResult Function( StreamSubscription<History> sub)?  walking,TResult Function( Command target,  StreamSubscription<History> sub,  A? pending)?  transitioning,required TResult orElse(),}) {final _that = this;
switch (_that) {
case Zero() when zero != null:
return zero();case Grounded() when grounded != null:
return grounded(_that.sub);case Standing() when standing != null:
return standing(_that.sub);case Walking() when walking != null:
return walking(_that.sub);case Transitioning() when transitioning != null:
return transitioning(_that.target,_that.sub,_that.pending);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  zero,required TResult Function( StreamSubscription<History> sub)  grounded,required TResult Function( StreamSubscription<History> sub)  standing,required TResult Function( StreamSubscription<History> sub)  walking,required TResult Function( Command target,  StreamSubscription<History> sub,  A? pending)  transitioning,}) {final _that = this;
switch (_that) {
case Zero():
return zero();case Grounded():
return grounded(_that.sub);case Standing():
return standing(_that.sub);case Walking():
return walking(_that.sub);case Transitioning():
return transitioning(_that.target,_that.sub,_that.pending);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  zero,TResult? Function( StreamSubscription<History> sub)?  grounded,TResult? Function( StreamSubscription<History> sub)?  standing,TResult? Function( StreamSubscription<History> sub)?  walking,TResult? Function( Command target,  StreamSubscription<History> sub,  A? pending)?  transitioning,}) {final _that = this;
switch (_that) {
case Zero() when zero != null:
return zero();case Grounded() when grounded != null:
return grounded(_that.sub);case Standing() when standing != null:
return standing(_that.sub);case Walking() when walking != null:
return walking(_that.sub);case Transitioning() when transitioning != null:
return transitioning(_that.target,_that.sub,_that.pending);case _:
  return null;

}
}

}

/// @nodoc


class Zero implements S {
  const Zero();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Zero);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'S.zero()';
}


}




/// @nodoc


class Grounded implements S {
  const Grounded(this.sub);
  

 final  StreamSubscription<History> sub;

/// Create a copy of S
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$GroundedCopyWith<Grounded> get copyWith => _$GroundedCopyWithImpl<Grounded>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Grounded&&(identical(other.sub, sub) || other.sub == sub));
}


@override
int get hashCode => Object.hash(runtimeType,sub);

@override
String toString() {
  return 'S.grounded(sub: $sub)';
}


}

/// @nodoc
abstract mixin class $GroundedCopyWith<$Res> implements $SCopyWith<$Res> {
  factory $GroundedCopyWith(Grounded value, $Res Function(Grounded) _then) = _$GroundedCopyWithImpl;
@useResult
$Res call({
 StreamSubscription<History> sub
});




}
/// @nodoc
class _$GroundedCopyWithImpl<$Res>
    implements $GroundedCopyWith<$Res> {
  _$GroundedCopyWithImpl(this._self, this._then);

  final Grounded _self;
  final $Res Function(Grounded) _then;

/// Create a copy of S
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? sub = null,}) {
  return _then(Grounded(
null == sub ? _self.sub : sub // ignore: cast_nullable_to_non_nullable
as StreamSubscription<History>,
  ));
}


}

/// @nodoc


class Standing implements S {
  const Standing(this.sub);
  

 final  StreamSubscription<History> sub;

/// Create a copy of S
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StandingCopyWith<Standing> get copyWith => _$StandingCopyWithImpl<Standing>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Standing&&(identical(other.sub, sub) || other.sub == sub));
}


@override
int get hashCode => Object.hash(runtimeType,sub);

@override
String toString() {
  return 'S.standing(sub: $sub)';
}


}

/// @nodoc
abstract mixin class $StandingCopyWith<$Res> implements $SCopyWith<$Res> {
  factory $StandingCopyWith(Standing value, $Res Function(Standing) _then) = _$StandingCopyWithImpl;
@useResult
$Res call({
 StreamSubscription<History> sub
});




}
/// @nodoc
class _$StandingCopyWithImpl<$Res>
    implements $StandingCopyWith<$Res> {
  _$StandingCopyWithImpl(this._self, this._then);

  final Standing _self;
  final $Res Function(Standing) _then;

/// Create a copy of S
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? sub = null,}) {
  return _then(Standing(
null == sub ? _self.sub : sub // ignore: cast_nullable_to_non_nullable
as StreamSubscription<History>,
  ));
}


}

/// @nodoc


class Walking implements S {
  const Walking(this.sub);
  

 final  StreamSubscription<History> sub;

/// Create a copy of S
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$WalkingCopyWith<Walking> get copyWith => _$WalkingCopyWithImpl<Walking>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Walking&&(identical(other.sub, sub) || other.sub == sub));
}


@override
int get hashCode => Object.hash(runtimeType,sub);

@override
String toString() {
  return 'S.walking(sub: $sub)';
}


}

/// @nodoc
abstract mixin class $WalkingCopyWith<$Res> implements $SCopyWith<$Res> {
  factory $WalkingCopyWith(Walking value, $Res Function(Walking) _then) = _$WalkingCopyWithImpl;
@useResult
$Res call({
 StreamSubscription<History> sub
});




}
/// @nodoc
class _$WalkingCopyWithImpl<$Res>
    implements $WalkingCopyWith<$Res> {
  _$WalkingCopyWithImpl(this._self, this._then);

  final Walking _self;
  final $Res Function(Walking) _then;

/// Create a copy of S
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? sub = null,}) {
  return _then(Walking(
null == sub ? _self.sub : sub // ignore: cast_nullable_to_non_nullable
as StreamSubscription<History>,
  ));
}


}

/// @nodoc


class Transitioning implements S {
  const Transitioning(this.target, this.sub, this.pending);
  

 final  Command target;
 final  StreamSubscription<History> sub;
 final  A? pending;

/// Create a copy of S
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TransitioningCopyWith<Transitioning> get copyWith => _$TransitioningCopyWithImpl<Transitioning>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Transitioning&&(identical(other.target, target) || other.target == target)&&(identical(other.sub, sub) || other.sub == sub)&&(identical(other.pending, pending) || other.pending == pending));
}


@override
int get hashCode => Object.hash(runtimeType,target,sub,pending);

@override
String toString() {
  return 'S.transitioning(target: $target, sub: $sub, pending: $pending)';
}


}

/// @nodoc
abstract mixin class $TransitioningCopyWith<$Res> implements $SCopyWith<$Res> {
  factory $TransitioningCopyWith(Transitioning value, $Res Function(Transitioning) _then) = _$TransitioningCopyWithImpl;
@useResult
$Res call({
 Command target, StreamSubscription<History> sub, A? pending
});


$CommandCopyWith<$Res> get target;$ACopyWith<$Res>? get pending;

}
/// @nodoc
class _$TransitioningCopyWithImpl<$Res>
    implements $TransitioningCopyWith<$Res> {
  _$TransitioningCopyWithImpl(this._self, this._then);

  final Transitioning _self;
  final $Res Function(Transitioning) _then;

/// Create a copy of S
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? target = null,Object? sub = null,Object? pending = freezed,}) {
  return _then(Transitioning(
null == target ? _self.target : target // ignore: cast_nullable_to_non_nullable
as Command,null == sub ? _self.sub : sub // ignore: cast_nullable_to_non_nullable
as StreamSubscription<History>,freezed == pending ? _self.pending : pending // ignore: cast_nullable_to_non_nullable
as A?,
  ));
}

/// Create a copy of S
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CommandCopyWith<$Res> get target {
  
  return $CommandCopyWith<$Res>(_self.target, (value) {
    return _then(_self.copyWith(target: value));
  });
}/// Create a copy of S
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ACopyWith<$Res>? get pending {
    if (_self.pending == null) {
    return null;
  }

  return $ACopyWith<$Res>(_self.pending!, (value) {
    return _then(_self.copyWith(pending: value));
  });
}
}

// dart format on
