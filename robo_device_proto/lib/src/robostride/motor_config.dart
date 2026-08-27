/// RobStride motor models supported by this codec.
///
/// When adding a new motor model, add its MIT protocol ranges to the
/// exhaustive switch in [RSMotorModelProtocol.limits]. The compiler will then
/// point out every place that must understand the new model.
enum RSMotorModel {
  rs02('RS02'),
  rs04('RS04');

  final String label;

  const RSMotorModel(this.label);
}

/// Physical ranges represented by the unsigned 16-bit MIT-control fields.
///
/// These values are protocol mapping ranges, not continuous/rated motor
/// capability. Using the wrong ranges changes both outgoing commands and
/// decoded feedback even though the CAN frame itself still looks valid.
class RSMotorLimits {
  final double velocityMax;
  final double torqueMax;
  final double kpMax;
  final double kdMax;

  const RSMotorLimits({
    required this.velocityMax,
    required this.torqueMax,
    required this.kpMax,
    required this.kdMax,
  });
}

const rs04MotorLimits = RSMotorLimits(
  velocityMax: 15.0,
  torqueMax: 120.0,
  kpMax: 5000.0,
  kdMax: 100.0,
);

const rs02MotorLimits = RSMotorLimits(
  velocityMax: 44.0,
  torqueMax: 17.0,
  kpMax: 500.0,
  kdMax: 5.0,
);

extension RSMotorModelProtocol on RSMotorModel {
  RSMotorLimits get limits => switch (this) {
    RSMotorModel.rs02 => rs02MotorLimits,
    RSMotorModel.rs04 => rs04MotorLimits,
  };
}

enum HanDogMotorRole {
  hip('hip'),
  thigh('thigh'),
  calf('calf'),
  wheel('wheel');

  final String label;

  const HanDogMotorRole(this.label);
}

class HanDogMotorSlot {
  final int canId;
  final HanDogMotorRole role;
  final RSMotorModel model;

  const HanDogMotorSlot({
    required this.canId,
    required this.role,
    required this.model,
  });

  RSMotorLimits get limits => model.limits;
}

/// Han Dog hardware motor layout, repeated on each of the four leg CAN buses.
///
/// MOTOR REPLACEMENT ENTRY POINT
/// =============================
/// If an installed motor is replaced by another *supported* model, change the
/// corresponding `model:` below. Command encoding, feedback decoding and the
/// startup diagnostic log all read this same table.
///
/// If the replacement is a new model:
/// 1. Add it to [RSMotorModel].
/// 2. Add its documented MIT field ranges above.
/// 3. Add it to the exhaustive [RSMotorModelProtocol.limits] switch.
/// 4. Select it in this table and run `dart test robo_device_proto`.
///
/// Do not infer a motor model from its mechanical role or reuse another
/// model's values. A frame encoded with the wrong ranges remains syntactically
/// valid, so the error otherwise appears as bad tracking or unstable control.
const hanDogMotorLayout = <int, HanDogMotorSlot>{
  1: HanDogMotorSlot(
    canId: 1,
    role: HanDogMotorRole.hip,
    model: RSMotorModel.rs04,
  ),
  2: HanDogMotorSlot(
    canId: 2,
    role: HanDogMotorRole.thigh,
    model: RSMotorModel.rs04,
  ),
  3: HanDogMotorSlot(
    canId: 3,
    role: HanDogMotorRole.calf,
    model: RSMotorModel.rs04,
  ),
  4: HanDogMotorSlot(
    canId: 4,
    role: HanDogMotorRole.wheel,
    model: RSMotorModel.rs02,
  ),
};

HanDogMotorSlot rsMotorSlotForCanId(int canId) {
  final slot = hanDogMotorLayout[canId];
  if (slot == null) {
    throw ArgumentError.value(
      canId,
      'canId',
      'No motor model configured. Update hanDogMotorLayout before using this '
          'CAN ID.',
    );
  }
  return slot;
}

RSMotorLimits rsMotorLimitsForCanId(int canId) =>
    rsMotorSlotForCanId(canId).limits;

/// Fails fast if the four expected joint roles are missing or assigned to the
/// wrong CAN IDs. Motor model changes remain allowed through the table above.
void validateHanDogMotorLayout() {
  const expectedRoles = <int, HanDogMotorRole>{
    1: HanDogMotorRole.hip,
    2: HanDogMotorRole.thigh,
    3: HanDogMotorRole.calf,
    4: HanDogMotorRole.wheel,
  };

  if (hanDogMotorLayout.length != expectedRoles.length) {
    throw StateError(
      'hanDogMotorLayout must contain exactly CAN IDs 1-4; found '
      '${hanDogMotorLayout.keys.toList()}.',
    );
  }

  for (final entry in expectedRoles.entries) {
    final slot = hanDogMotorLayout[entry.key];
    if (slot == null || slot.canId != entry.key || slot.role != entry.value) {
      throw StateError(
        'CAN ID ${entry.key} must be ${entry.value.label}; found $slot.',
      );
    }
  }
}

String get hanDogMotorCodecSummary => hanDogMotorLayout.values
    .map((slot) {
      final limits = slot.limits;
      return 'CAN${slot.canId} ${slot.role.label}=${slot.model.label}'
          '(v=±${_number(limits.velocityMax)},'
          't=±${_number(limits.torqueMax)},'
          'kp=0..${_number(limits.kpMax)},'
          'kd=0..${_number(limits.kdMax)})';
    })
    .join('; ');

String _number(double value) => value == value.truncateToDouble()
    ? value.toInt().toString()
    : value.toString();
