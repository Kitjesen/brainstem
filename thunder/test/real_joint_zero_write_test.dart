import 'package:thunder/thunder.dart';
import 'package:mocktail/mocktail.dart';
import 'package:robo_device/robo_device.dart';
import 'package:robo_device_proto/robo_device_proto.dart';
import 'package:test/test.dart';

class MockZeroPcan extends Mock implements PcanController<RSEvent, RSState> {}

void main() {
  late List<MockZeroPcan> pcans;
  late RealJoint joint;
  late List<RSEvent> sent;
  var failAt = -1;
  setUpAll(() => registerFallbackValue(RSEvent.setZero(1)));
  setUp(() {
    sent = [];
    failAt = -1;
    pcans = List.generate(4, (_) => MockZeroPcan());
    for (final pcan in pcans) {
      when(() => pcan.state).thenAnswer((_) => const Stream<RSState>.empty());
      when(() => pcan.canWriteImmediately).thenReturn(true);
      when(() => pcan.tryWriteImmediately(any())).thenAnswer((i) {
        sent.add(i.positionalArguments.single as RSEvent);
        return sent.length != failAt;
      });
    }
    joint = RealJoint.withControllers(pcans);
    addTearDown(joint.dispose);
  });

  test('zero checks all 48 CAN sends and never uses deferred add', () async {
    expect(await joint.setZero(), true);
    expect(sent, hasLength(48));
    expect(sent.take(16), everyElement(isA<RSEventSetZero>()));
    expect(sent.skip(16).take(16), everyElement(isA<RSEventSet>()));
    expect(sent.skip(32), everyElement(isA<RSEventSaveData>()));
    for (final pcan in pcans) {
      verifyNever(() => pcan.add(any()));
    }
  });

  test('a busy leg rejects the entire batch without writing', () async {
    when(() => pcans[2].canWriteImmediately).thenReturn(false);
    expect(joint.canZeroWriteImmediately, false);
    expect(await joint.setZero(), false);
    expect(sent, isEmpty);
  });

  test(
    'partial send fails immediately without retry or optimistic success',
    () async {
      failAt = 7;
      expect(await joint.setZero(), false);
      expect(sent, hasLength(7));
      expect(sent, everyElement(isA<RSEventSetZero>()));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(sent, hasLength(7));
    },
  );

  test('failed parameter save also refuses success', () async {
    failAt = 35;
    expect(await joint.setZero(), false);
    expect(sent, hasLength(35));
  });
}
