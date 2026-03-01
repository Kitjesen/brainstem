import 'dart:typed_data';

import 'package:skinny_dog_algebra/src/h.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  test('double vs DoubleH', () {
    final a = 0.1 + 0.2;
    final b = 0.3;
    expect(a == b, isFalse);
    expect(a.h == b.h, isTrue);
  });

  /// 证明了来源是 Float32List 里面的存储的设置
  test("Float32List", () {
    final list = Float32List.fromList([0.1, 0.1 + 1e-9, 0.1 + 1e-8]);
    expect(list[0] == list[1], isTrue);
    expect(list[0] == list[2], isFalse);
    // 转化为 double 就不行了
    expect(list[0] == list[0] + 1e-9, isFalse);
  });

  /// 说明 Vector3 自身的是有精度判定的
  test('Vector3 precision', () {
    expect(
      Vector3(0.1 + 1e-9, 0, 0) + Vector3(0.1, 0, 0) == Vector3(0.2, 0, 0),
      isTrue,
    );
    expect(
      Vector3(0.1 + 1e-8, 0, 0) + Vector3(0.1, 0, 0) == Vector3(0.2, 0, 0),
      isFalse,
    );
    // h 更为灵活的是设置精度
    ToleranceH.h = 1e-7;
    expect(
      (Vector3(0.1 + 1e-8, 0, 0) + Vector3(0.1, 0, 0)).h ==
          Vector3(0.2, 0, 0).h,
      isTrue,
    );
  });
}
