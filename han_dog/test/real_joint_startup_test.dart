import 'package:han_dog/han_dog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:robo_device/robo_device.dart';
import 'package:robo_device_proto/robo_device_proto.dart';
import 'package:test/test.dart';

class MockPcanController extends Mock
    implements PcanController<RSEvent, RSState> {}

void main() {
  setUpAll(() {
    registerFallbackValue(RSEvent.disable(1));
  });

  test('open sends disable to every motor before startup commands', () {
    final sent = <RSEvent>[];
    final pcans = List.generate(4, (_) => MockPcanController());
    for (final pcan in pcans) {
      when(() => pcan.state).thenAnswer((_) => const Stream<RSState>.empty());
      when(() => pcan.open()).thenReturn(true);
      when(() => pcan.add(any())).thenAnswer((invocation) {
        sent.add(invocation.positionalArguments.single as RSEvent);
      });
    }

    final joint = RealJoint.withControllers(pcans);

    expect(joint.open(), isTrue);
    expect(sent, hasLength(16));
    expect(
      sent.every((event) =>
          event is RSEventDisable && event.clearErrors == false),
      isTrue,
    );
    expect(
      sent.map((event) => (event as RSEventDisable).canId),
      [1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 3, 4],
    );
  });
}
