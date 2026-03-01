# skinny dog algebra

为避免歧义, 采用和 onnx 文件对齐的顺序

统一的顺序为:

```dart
values = [
      frHip, frThigh, frCalf,
      flHip, flThigh, flCalf,
      rrHip, rrThigh, rrCalf,
      rlHip, rlThigh, rlCalf,
      frFoot, flFoot, rrFoot, rlFoot
];
```

## quick start

```dart
void main() {
  // dart format off
  final s0 = JointsMatrix(
    0.0, 0 .7, -1.5,
    0.0, -0.7,  1.5,
    0.0, -0.7,  1.5,
    0.0,  0.7, -1.5,
    0.0, 0.0, 0.0, 0.0
  );
  // dart format on
  final s1 = JointsMatrix.zero();
  for (double t = 0; t <= 1; t += 0.1) {
    final status = JointsMatrix.lerp(s0, s1, t);
    print('t: $t, status: \n${status.toString()}');
  }
}
```

### 精度比较

h 借用了普朗克常量

```dart
final a = 0.1 + 0.2;
final b = 0.3;
expect(a == b, isFalse);
expect(a.h == b.h, isTrue);

expect(
  Vector3(0.1 + 1e-8, 0, 0) + Vector3(0.1, 0, 0) == Vector3(0.2, 0, 0),
  isFalse,
);
// h 更为灵活的是设置精度
ToleranceH.h = 1e-7;
expect(
  (Vector3(0.1 + 1e-8, 0, 0) + Vector3(0.1, 0, 0)).h == Vector3(0.2, 0, 0).h,
  isTrue,
);
```