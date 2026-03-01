import 'dart:async';

import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:han_dog_brain/src/common.dart';

import 'a.dart';

part 's.freezed.dart';

@freezed
sealed class S with _$S {
  const factory S.zero() = Zero;
  const factory S.grounded(StreamSubscription<History> sub) = Grounded;
  const factory S.standing(StreamSubscription<History> sub) = Standing;
  const factory S.walking(StreamSubscription<History> sub) = Walking;
  const factory S.transitioning(
    Command target,
    StreamSubscription<History> sub,
    A? pending,
  ) = Transitioning;
}
