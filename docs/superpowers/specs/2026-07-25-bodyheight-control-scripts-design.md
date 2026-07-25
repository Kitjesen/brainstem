# Body-height service and gRPC helper design

## Goal

Replace error-prone pasted commands with two small, editable command-line
helpers:

- `scripts/bodyheight_service.sh` manages the H15/H18 robot-side process.
- `scripts/bodyheight_grpc.py` inspects the running service and submits a
  body-height command with telemetry confirmation.

The first version must not expose motor enable, stand, or sit commands. It does
expose a bounded velocity command, because velocity is part of the H15/H18
policy contract.

## Robot-side service helper

`bodyheight_service.sh` runs on the robot and provides:

```text
status
start h15
start h18
logs [--follow]
stop
restore-master
```

Configuration is overridable through environment variables, with defaults for
the verified `.190` robot:

- candidate repository: `/home/bsrl1/brainstem-bodyheightctrl`
- Dart: `/home/bsrl1/flutter/bin/dart`
- candidate unit: `han-dog-bodyheight.service`
- production unit: `han_dog.service`
- gRPC port: `13145`
- profile directory: `han_dog/profiles`

`start` validates the requested profile, ONNX file and SHA-256 hash, Dart
executable, IMU device, profile JSON, and port availability. It refuses to
continue while the production service is active or while port `13145` is
occupied. Profile JSON is parsed structurally, duplicate keys are rejected,
and the configured model hash must match the file. Lifecycle mutations share
a host-wide non-blocking lock so two helper processes cannot switch services
concurrently. It launches a transient systemd service with an explicit working
directory and environment, but it never invokes a motor-control RPC.

`stop` only stops the candidate service. It prints a prominent warning that
stopping an active controller is unsafe, but it has no confirmation flag or
interactive prompt.
`restore-master` first proves that the candidate process has stopped and the
port is free, then starts the existing production service. Neither operation
changes or installs systemd unit files.

If startup readiness cannot be confirmed, the helper does not automatically
stop the candidate. It reports that the process may still own IMU/PCAN/port
resources and instructs the operator to disable motors, support the robot,
stop the candidate, and re-check status before restoring production.

## Local gRPC helper

`bodyheight_grpc.py` runs from the repository on the operator PC and provides:

```text
status
set-height METRES
set-velocity [--vx METRES_PER_SECOND] [--vy METRES_PER_SECOND]
             [--yaw RADIANS_PER_SECOND]
watch-height
```

The default target is `192.168.66.190:13145`. An SSH tunnel can instead be
selected with `--target 127.0.0.1:13146`; the robot service itself remains on
port `13145`.

The helper imports the generated Python API from `brainstem_api/python` without
requiring package installation. `status` reports connectivity, CMS state,
active profile, and the latest height telemetry. `set-height`:

1. accepts only finite values in `0.20..0.54 m`;
2. requires the active profile to be `thunder_h15` or `thunder_h18`;
3. calls only `SetBodyHeight`;
4. reads the history stream and confirms that
`body_height_command` reaches the requested value within a timeout;
5. exits non-zero when the server returned success but control arbitration
   silently rejected the command.

The profiles initialize body height to `0.35 m` and velocity to
`[0.0, 0.0, 0.0]`. `set-height` still requires an explicit value; omitting the
command leaves the profile default unchanged. For `set-velocity`, omitted axes
default to zero, but at least one axis must be written explicitly so that a
bare command cannot move the FSM from `Standing` to `Walking`.

`set-velocity` calls the existing `Walk(Vector3)` RPC. It accepts only finite
values inside the active profile ranges (`vx=-2.5..2.5 m/s`,
`vy=-1.0..1.0 m/s`, `yaw=-1.0..1.0 rad/s`) and requires the CMS state to be
`Standing` or `Walking`. It then confirms the resulting `History.command.walk`
vector. There is no confirmation flag or interactive prompt.

The helper contains no motor-enable, stand-up, or sit-down command. Sending a
velocity while motors are already enabled may move the robot; the helper states
that fact in its help text but does not add an extra acknowledgement option.

## Failure handling

Both tools fail closed:

- ambiguous service ownership, wrong profile, missing model, hash mismatch,
  occupied port, unavailable telemetry, or rejected command returns non-zero;
- passwords and credentials are never stored;
- no automatic fallback starts a different policy or service;
- every state-changing action prints the exact service and profile affected.

## Verification

Implementation is test-first:

- Python unit tests use fake stubs for range validation, profile validation,
  successful height/velocity telemetry confirmation, default zero values for
  omitted velocity axes, bare velocity-command refusal, and silent arbitration
  rejection.
- Shell tests exercise argument parsing and refusal paths with command fakes.
- `bash -n` validates shell syntax.
- Existing Dart tests and H15/H18 ONNX smoke tests remain unchanged and must
  continue to pass.

No verification step starts the real robot controller or sends a motor command.
