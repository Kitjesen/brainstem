import 'package:skinny_dog_algebra/skinny_dog_algebra.dart';

/// 推理 PD 增益（硬件调参值，按机型调整）
// dart format off
final inferKp = JointsMatrix(
    65, 95, 120,
    65, 95, 120,
    65, 95, 120,
    65, 95, 120,
    0, 0, 0, 0
);
final inferKd = JointsMatrix(
    20, 20, 20,
    20, 20, 20,
    20, 20, 20,
    20, 20, 20,
    1, 1, 1, 1
);
// dart format on

/// StandUp / SitDown 过渡增益
final standUpKp = JointsMatrix.fromList(List.generate(16, (_) => 200.0));
final standUpKd = JointsMatrix.fromList(List.generate(16, (_) => 8.0));
final sitDownKp = JointsMatrix.fromList(List.generate(16, (_) => 200.0));
final sitDownKd = JointsMatrix.fromList(List.generate(16, (_) => 8.0));

/// 站立姿态（rad）
// dart format off
final standingPose = JointsMatrix(
  -0.1, -0.8,  1.8,   // FR: hip, thigh, calf
   0.1,  0.8, -1.8,   // FL: hip, thigh, calf
   0.1,  0.8, -1.8,   // RR: hip, thigh, calf
  -0.1, -0.8,  1.8,   // RL: hip, thigh, calf
  0, 0, 0, 0,         // foot joints
);
// dart format on
