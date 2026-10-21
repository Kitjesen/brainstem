# Thunder deployed source snapshot, 2026-10-21

This commit preserves the deployed controller source without installing or
restarting anything on the robot. It is based on master `ac733617` and the
working files in `/home/bsrl1/brainstem_arm_teleop_stage_20260829`.
The robot's Git HEAD alone did not describe its deployed working tree.

## Active configuration at capture

- Profile: `flat_w5_model89999_kp80_policy_zero_20260929`.
- Model: `model/thunder_flat_w5_model89999_static_b1_arm64.onnx`.
- Walk: legs 80/6.93, wheels 0/1; L1/L2: 200/8.
- Default absolute Hip/Thigh/Calf angles: 0.12/0.93/1.96 rad.
- Normal joystick direction bypasses the retained 0.5/2.5 slew limiter.
- Normal zero command follows policy wheel targets; abnormal hard stop is separate.
- Existing target limits, enable interlocks, entry blending, CAN retries and
  fault diagnostics are retained, not newly installed on the robot by this sync.
- Arm bridge source remains for compatibility; the deployed main path is dog-only.

The original GitHub default profiles and newer upstream fixes are retained.
Adding these profile files does not select one automatically: systemd environment
and the model files must match an explicitly chosen deployment.
This is not a Recovery-policy deployment and does not add V89 Recovery support.

## Backup and excluded data

The local backup is `backups/brainstem_robot_github_sync_20261021_204618/`.
Its archive SHA256 is
`c0f6db56e2c89452172c7ef8db6cd963bb7f70bbe33edf163061d06a8a033de6`.
It contains source, Git metadata, models, logs and historical backups. The service
unit and drop-in configuration are backed up separately in the same directory.
Reproducible `.dart_tool`, `build`, Python and Node caches were excluded.
Linux symlinks remain in the archive but were not recreated in the Windows copy.

GitHub receives runtime source, tests and profile JSON, not logs, secrets, cache,
old backup copies, per-machine systemd configuration or model binaries.
A clone alone therefore does not contain the model assets needed to run these
profiles. The backup must be handled as private machine data, not uploaded whole.

## Validation

- 63 observation, behaviour, CMS and RobStride protocol tests passed.
- 5 CAN retry/error tests passed.
- `han_dog/test`: 270 passed, 2 skipped, 1 failed locally because the native
  CSerialPort asset was not available to the Windows test process. The failing
  test constructs the real serial wrapper before replacing it with a mock:
  `wheel_stop_watchdog_test.dart`. This is not a successful full test run.
- `dart analyze --no-fatal-warnings han_dog han_dog_brain pcan robo_device
  robo_device_proto`: no errors, two unused mode-ramp declarations and one
  unnecessary test import. Existing source was not cleaned up as part of sync.
- No enable, movement, calibration, fault-clear or service restart commands were
  issued. Service PID 1511 and its start timestamp were unchanged.

## Native submodule fix

The robot also has an uncommitted `CSerialPort` Unix pipe-descriptor cleanup fix.
The existing submodule commit is retained. A companion commit stores the exact
native diff as `serial_port/patches/close_unix_pipe_fds.patch` and applies it
idempotently in the native build hook. A conflicting upstream source fails the
build rather than silently losing the fix. Its local regression test checks
initial application, repeated application and incompatible-source rejection.
The hook change only affects future builds; it was not copied to the robot.

This snapshot is source preservation, not certification of all hardware,
firmware, model contents, Flutter builds or real robot motion.
