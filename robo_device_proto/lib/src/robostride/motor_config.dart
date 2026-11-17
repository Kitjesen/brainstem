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

enum ThunderMotorRole {
  hip('hip'),
  thigh('thigh'),
  calf('calf'),
  wheel('wheel');

  final String label;

  const ThunderMotorRole(this.label);
}

class ThunderMotorSlot {
  final int canId;
  final ThunderMotorRole role;
  final RSMotorModel model;

  const ThunderMotorSlot({
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
const thunderMotorLayout = <int, ThunderMotorSlot>{
  1: ThunderMotorSlot(
    canId: 1,
    role: ThunderMotorRole.hip,
    model: RSMotorModel.rs04,
  ),
  2: ThunderMotorSlot(
    canId: 2,
    role: ThunderMotorRole.thigh,
    model: RSMotorModel.rs04,
  ),
  3: ThunderMotorSlot(
    canId: 3,
    role: ThunderMotorRole.calf,
    model: RSMotorModel.rs04,
  ),
  4: ThunderMotorSlot(
    canId: 4,
    role: ThunderMotorRole.wheel,
    model: RSMotorModel.rs02,
  ),
};

ThunderMotorSlot rsMotorSlotForCanId(int canId) {
  final slot = thunderMotorLayout[canId];
  if (slot == null) {
    throw ArgumentError.value(
      canId,
      'canId',
      'No motor model configured. Update thunderMotorLayout before using this '
          'CAN ID.',
    );
  }
  return slot;
}

RSMotorLimits rsMotorLimitsForCanId(int canId) =>
    rsMotorSlotForCanId(canId).limits;

/// Fails fast if the four expected joint roles are missing or assigned to the
/// wrong CAN IDs. Motor model changes remain allowed through the table above.
void validateThunderMotorLayout() {
  const expectedRoles = <int, ThunderMotorRole>{
    1: ThunderMotorRole.hip,
    2: ThunderMotorRole.thigh,
    3: ThunderMotorRole.calf,
    4: ThunderMotorRole.wheel,
  };

  if (thunderMotorLayout.length != expectedRoles.length) {
    throw StateError(
      'thunderMotorLayout must contain exactly CAN IDs 1-4; found '
      '${thunderMotorLayout.keys.toList()}.',
    );
  }

  for (final entry in expectedRoles.entries) {
    final slot = thunderMotorLayout[entry.key];
    if (slot == null || slot.canId != entry.key || slot.role != entry.value) {
      throw StateError(
        'CAN ID ${entry.key} must be ${entry.value.label}; found $slot.',
      );
    }
  }
}

String get thunderMotorCodecSummary => thunderMotorLayout.values
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
