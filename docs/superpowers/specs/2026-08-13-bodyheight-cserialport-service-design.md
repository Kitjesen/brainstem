# Body-height libcserialport Service Fix Design

## Problem

The robot-side candidate service exits before opening the IMU or Yunzhuo
serial ports because Dart cannot resolve `CSerialPortMalloc`. The shared
library exists at `/lib/aarch64-linux-gnu/libcserialport.so`, and a read-only
serial enumeration succeeds when that library is supplied through
`LD_PRELOAD`.

The robot working tree previously contained an uncommitted operational fix,
but it was preserved only in `stash@{0}` when the branch was synchronized.
The tracked `bodyheightctrl` branch therefore lost the runtime environment
needed on this board.

## Design

Restore the existing two-file operational fix rather than changing Dart FFI
bindings or the production service:

- Declare an overridable `CSERIALPORT_LIBRARY`, defaulting to the installed
  AArch64 library path.
- Fail the candidate preflight before `sudo` when the configured file is not
  an absolute, readable regular file.
- Pass the library to the transient candidate unit with `LD_PRELOAD`.
- Use a 45-second default readiness timeout because `dart run` may spend more
  than 10 seconds compiling before opening port 13145.
- Extend the shell test fixture to assert the exact launch argument and the
  missing-library preflight failure.

No production unit, master checkout, Dart source, motor-enable behavior, or
hardware mapping changes are in scope. Verification must not start the robot
control service or send a motor command.

## Acceptance Criteria

1. The service test fails before implementation because the launch command
   lacks `LD_PRELOAD`.
2. A missing serial library fails preflight without invoking `sudo`.
3. All `bodyheight_service_test.sh` cases pass after implementation.
4. On the robot, the candidate library exists and read-only serial enumeration
   succeeds with the same preload value.
5. Only `/home/bsrl1/brainstem-bodyheightctrl` is synchronized; both robot
   services remain inactive after verification.
