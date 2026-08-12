# Robot source backup: 2026-08-12

This branch captures the maintainable source and configuration present in the
robot's `/home/bsrl1/brainstem` working tree on 2026-08-12.

## Provenance

- Base repository commit: `f090844aae5678b341f5c8bb9f28f0ca7cf9ebc4`
- Active profile: `flat_v0_straight_wheel_smooth_19000`
- Active policy file: `pose_flat_v4_him_urdf_v0_straight_wheel_smooth_model19000_policy.onnx`
- Active policy SHA-256: `fdeba162d4965c60dd79b55cf1466c29654dd0289b6d86cd01e1400d5bff2f95`
- Local source archive SHA-256: `bd4f10d87778b69f88bdef5e80ca1f854bc0b7057dd0b9003a26f5b2bf28f98e`

The policy binary, logs, build caches, historical `.bak` files, and deployment
archives are intentionally excluded from this public Git branch. The policy
binary and systemd configuration are retained in the corresponding local
backup directory.

## CSerialPort

The robot uses `serial_port/src/CSerialPort` at commit
`cb8c8b4bb358c80a01f0605367a30b07643863cb` with one uncommitted resource
cleanup fix. Apply the preserved patch after initializing submodules:

```bash
git submodule update --init --recursive
git -C serial_port/src/CSerialPort apply ../../patches/cserialport_robot_20260812.patch
```

No service restart, motor command, or controller command was issued while this
backup was captured.

## Verification

The following local tests passed before the backup branch was published:

- `han_dog/test/real_control_dog_test.dart`
- `han_dog/test/real_joint_startup_test.dart`
- `robo_device_proto/test/subs_test.dart`
- `serial_port/test/fd_leak_test.dart`

Seven `han_dog_brain/test/behaviour_test.dart` cases passed. Its final Walk
case could not complete on the Windows backup host because the installed ONNX
Runtime 1.17.1 exposes API 17 while the Dart binding requests API 22; the native
library aborts before the test assertion runs.
