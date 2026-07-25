# Body-height policy deployment contract

This branch adds the Thunder V4 H15 and H18 body-height policies without changing the legacy 57-value policy contract.

## Policy interface

A single body-height frame has 58 values in this exact order:

| Slice | Values | Runtime transform |
|---|---:|---|
| `0:3` | base angular velocity | multiply by `0.25` |
| `3:6` | projected gravity | none |
| `6:9` | `[vx, vy, yaw]` command | none |
| `9:25` | joint position relative to the training default | wheel entries are zero |
| `25:41` | joint velocity | multiply by `0.05` |
| `41:57` | previous normalized policy action | none |
| `57` | body-height command | raw metres |

History is flattened oldest-to-newest. H15 uses one frame (`58` values, input `policy_obs`); H18 uses ten frames (`580` values, input `policy_history`). Both output 16 normalized actions. Leg action scales are `0.125/0.25/0.25`; wheel velocity scale is `5.0`.

The gRPC API exposes `SetBodyHeight(BodyHeightCommand)`. The server rejects non-finite values, rate-limits updates to the 50 Hz control period, rejects unsafe FSM states, participates in control arbitration, and clamps the command to the active profile range. Velocity is clamped per axis to the profile training range.

## Profiles and model files

Profiles are committed at:

- `han_dog/profiles/thunder_h15.json`
- `han_dog/profiles/thunder_h18.json`

ONNX binaries are intentionally ignored by Git. Copy them into `model/` using these exact names and verify them before launch:

```text
ded34be402b25a3a77a9feba196a3d76efa2b5660d7d9c8396b28963a0efbde4  model/thunder_h15_model10400.onnx
d632413aa9ddf16b6c795377bdbbef69c454ba1cc77f8acb7d560f381cd84296  model/thunder_h18_model5000.onnx
```

```bash
sha256sum model/thunder_h15_model10400.onnx model/thunder_h18_model5000.onnx
```

The committed ranges and transforms match the archived Isaac Lab training configuration: height `0.20..0.54 m`, velocity `vx=-2.5..2.5`, `vy=-1.0..1.0`, `yaw=-1.0..1.0`, and training standing pose `[-0.1,-1.1,2.6, 0.1,1.1,-2.6, 0.1,1.1,-2.6, -0.1,-1.1,2.6, 0,0,0,0]`.

H15 and H18 have different history tensor sizes. Select one at process startup; switching between them requires a restart. The model shape check deliberately rejects a mismatched live switch before replacing the active policy.

## Simulation launch

H15 server:

```bash
ONNXRUNTIME_DLL_PATH=/path/to/libonnxruntime.so \
MEDULLA_PROFILE_DIR=han_dog/profiles \
MEDULLA_DEFAULT_PROFILE=thunder_h15 \
dart run han_dog/bin/server.dart
```

H18 uses the same command with `MEDULLA_DEFAULT_PROFILE=thunder_h18`. In another terminal:

```bash
python sim/scripts/walk_grpc.py --profile han_dog/profiles/thunder_h15.json --height 0.32 --vx 0.3 --duration 5
```

The validation run on 2026-07-22 completed the full `Grounded -> StandUp -> SetBodyHeight -> Walk -> Tick -> Dart ONNX -> MuJoCo PD` chain:

| Policy | Input | Walking ticks | X displacement | Final trunk Z |
|---|---:|---:|---:|---:|
| H15 | 58 | 98 | 0.489 m | 0.346 m |
| H18 | 580 | 98 | 0.726 m | 0.342 m |

## Hardware safety gate

No unattended or remote motor motion is part of automated validation. Complete every item below on the robot before enabling output:

1. Verify the ONNX hashes, selected profile name, input name, inferred history length, finite zero-state inference, and all Dart/Python tests.
2. Place the robot on a rigid support with all wheels clear of the floor; use a restraint/harness and keep the work area clear.
3. Assign a second operator to the physical emergency stop. Confirm that disable cuts motor output before any policy command.
4. With motor output disabled, inspect all 16 reported joint positions and signs against the order `FR, FL, RR, RL`, each as `hip, thigh, calf`, followed by four wheels.
5. Confirm IMU projected gravity is approximately `[0, 0, -1]` while level and that sensor/control frequency is stable at 50 Hz.
6. Enable only while supported, command zero velocity at `0.35 m`, and stop immediately on a sign/order mismatch, non-finite value, unexpected motion, lost sensor reporting, or joint-limit/fault event.
7. Exercise height only in a narrow `0.30..0.40 m` window, then forward velocity no higher than `0.1 m/s`. Expand toward the training envelope only after reviewing logs and measured tracking.
8. Repeat separately for H15 and H18, restarting the process between profiles. Save logs, selected profile, model hash, and abort/accept result.

The remote development server has no verified robot/CAN attachment, so this branch can prove the no-motion software preflight and MuJoCo chain only. Final motor-enabled acceptance must be performed by an onsite operator under this gate.

## Operator helper scripts

Two editable helpers replace the long service and gRPC commands. Neither
helper enables motors or sends stand-up/sit-down commands.

### Robot-side service lifecycle

Run these commands on the robot from the body-height checkout:

```bash
cd /home/bsrl1/brainstem-bodyheightctrl

./scripts/bodyheight_service.sh status
./scripts/bodyheight_service.sh start h15
./scripts/bodyheight_service.sh logs
./scripts/bodyheight_service.sh logs --follow
./scripts/bodyheight_service.sh stop
./scripts/bodyheight_service.sh restore-master
```

Use `start h18` for H18. `start` verifies that `han_dog.service` is already
stopped, the candidate service and port `13145` are free, the selected profile
matches the ONNX filename/hash, and the required IMU/Yunzhuo devices exist. It
never stops the production service automatically.

Before manually stopping production or running `stop`, disable the motors and
place the robot on reliable support. Starting the candidate opens its hardware
interfaces, but the helper itself does not call motor enable or a motion RPC.
If readiness times out, treat the candidate as potentially still active; do
not restore production until `stop` and `status` confirm that it and the port
are clear.

### Local gRPC commands

The direct robot endpoint is the default:

```powershell
python scripts/bodyheight_grpc.py status
python scripts/bodyheight_grpc.py set-height 0.32
python scripts/bodyheight_grpc.py set-velocity --vx 0.1
```

When using the existing SSH tunnel, select its local endpoint explicitly:

```powershell
python scripts/bodyheight_grpc.py `
  --target 127.0.0.1:13146 `
  status
```

The robot service still listens on `13145`; `13146` is only the chosen local
tunnel port.

`set-height` requires an explicit target. If it is not called, both policies
start with the profile default `0.35 m`. For `set-velocity`, at least one axis
must be present; omitted axes default to zero:

```powershell
python scripts/bodyheight_grpc.py set-velocity --vx 0.1
# sends vx=0.1 m/s, vy=0.0 m/s, yaw=0.0 rad/s
```

There is no confirmation flag. A velocity command is accepted only in
`Standing` or `Walking`, and it may move the robot if motors are already
enabled. Height and velocity values are checked against the active H15/H18
profile. The client opens the history stream before sending a changed target
and only reports `confirmed` after matching later telemetry. If the requested
value is already active, it reports `already active` without sending a
redundant RPC. A silently rejected arbitration command returns a non-zero exit
status instead of being reported as successful.
