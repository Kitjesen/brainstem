# Body-height service and gRPC helper design

## Goal

Replace error-prone pasted commands with two small, editable command-line
helpers:

- `scripts/bodyheight_service.sh` manages the H15/H18 robot-side process.
- `scripts/bodyheight_grpc.py` inspects the running service and submits a
  body-height command with telemetry confirmation.

The first version must not expose motor enable, stand, walk, sit, or velocity
commands.

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
- candidate unit: `han-dog-bodyheight`
- production unit: `han_dog.service`
- gRPC port: `13145`
- profile directory: `han_dog/profiles`

`start` validates the requested profile, ONNX file and SHA-256 hash, Dart
executable, IMU device, profile JSON, and port availability. It refuses to
continue while the production service is active or while port `13145` is
occupied. It launches a transient systemd service with an explicit working
directory and environment, but it never invokes a motor-control RPC.

`stop` only stops the candidate service. It warns that stopping an active
controller is unsafe and therefore requires an explicit confirmation flag.
`restore-master` first proves that the candidate process has stopped and the
port is free, then starts the existing production service. Neither operation
changes or installs systemd unit files.

## Local gRPC helper

`bodyheight_grpc.py` runs from the repository on the operator PC and provides:

```text
status
set-height METRES
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

The helper contains no motor-enable or locomotion command.

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
  successful telemetry confirmation, and silent arbitration rejection.
- Shell tests exercise argument parsing and refusal paths with command fakes.
- `bash -n` validates shell syntax.
- Existing Dart tests and H15/H18 ONNX smoke tests remain unchanged and must
  continue to pass.

No verification step starts the real robot controller or sends a motor command.
