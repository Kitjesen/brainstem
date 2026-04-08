# Brainstem CMS/App Handoff

Date: 2026-03-10
Updated: 2026-03-29

## Scope

This handoff records the `brainstem` work around:

- `han_dog` profile path resolution and deploy-time env compatibility
- full-tree `dart analyze` cleanup
- model-driven `historySize` inference in `han_dog/bin/server.dart`
- CMS authoritative state RPCs and Flutter app alignment
- remote validation on `sunrise@192.168.66.192:2020`
- **[2026-03-26] Walk command coordinate convention fix**
- **[2026-03-26] MuJoCo simulation PD gains fix**
- **[2026-03-26] Full coordinate system audit**
- **[2026-03-29] MuJoCo simulation scripts added to repo**

Remote workspace:

- host: `sunrise@192.168.66.192:2020`
- password: `sunrise`
- repo path: `/home/sunrise/Desktop/brainstem`

## What Changed

### 1. Profile path / deploy compatibility

Problem:

- code read `HAN_DOG_PROFILE_DIR`
- deploy script wrote `HAN_DOG_PROFILES_DIR`
- starting from the repo root could fail to locate `profiles/`

Result:

- `han_dog` now accepts the new env var and remains compatible with the old one
- default probing now covers both `profiles/` and `han_dog/profiles/`
- root-level startup works without relying on the old path layout

Relevant files:

- `han_dog/lib/src/app/config.dart`
- `han_dog/bin/server.dart`
- `han_dog/test/han_dog_test.dart`
- `scripts/setup_brainstem_service.py`

### 2. Full-tree `dart analyze` cleanup

Problem:

- `robo_device/example` still used old imports and APIs
- generated / legacy test noise also blocked whole-tree analysis

Result:

- old example imports were made compatible again
- `robo_device/example/*` was updated to current public exports
- `serial_port` and generated `onnx_runtime` noise were cleaned enough for full analyze to pass

Relevant files:

- `robo_device/lib/device.dart`
- `robo_device_proto/lib/device_proto.dart`
- `robo_device/example/*`
- `serial_port/test/serial_port_test.dart`
- `onnx_runtime/lib/ffi/bindings.g.dart`

### 3. `server.dart` model input compatibility

Problem:

- `medulla` used a fixed default history size of `1`
- remote model `model/policy_260106.onnx` expects a larger input window

Result:

- `server.dart` now infers `historySize` from the model metadata
- remote smoke showed `historySize=5`, which matches the deployed model shape

Relevant files:

- `han_dog/bin/server.dart`
- `han_dog_brain/lib/src/model_info.dart`

### 4. CMS authoritative state API

Problem:

- Flutter app guessed CMS state from `History.command`
- gRPC command success did not clearly mean the state transition was allowed
- there was no authoritative state query / state stream for the app

Result:

- added `GetCmsState` and `ListenCmsState` to `cms.proto`
- added `CmsStateKind` and `CmsTransitionKind`
- server now exposes authoritative state mapping from FSM state
- invalid commands now return `FAILED_PRECONDITION` instead of silently being treated as accepted

Relevant files:

- `han_dog_message/han_dog_message/cms.proto`
- `han_dog/lib/src/server/unified_cms_server.dart`
- `han_dog/test/unified_cms_server_test.dart`
- regenerated message code under `han_dog_message/dart` and `han_dog_message/python`

### 5. Flutter Sirius state handling

Problem:

- `sirius` used heuristic state derivation from history stream
- UI state labels were not aligned with the backend state names

Result:

- `GrpcService` now fetches and subscribes to authoritative CMS state
- UI state labels now match backend semantics:
  - `Grounded`
  - `StandUp`
  - `Standing`
  - `Walking`
  - `SitDown`
- error surfaces for rejected motion commands now preserve the server-side precondition message

Relevant files:

- `sirius/lib/services/grpc_service.dart`
- `sirius/lib/pages/dashboard_page.dart`
- `sirius/lib/pages/protocol_page.dart`
- `sirius/test/grpc_service_test.dart`

### 6. Walk command coordinate convention fix (2026-03-26)

Problem:

- YUNZHUO controller output was in joystick coordinates (x=lateral, y=forward, z=yaw)
- `RealControlDog` did axis swapping: `corrected = Vector3(direction.y, -direction.x, -direction.z)`
- gRPC Walk path was direct (x=forward, y=lateral, z=yaw) with NO axis swap
- Two different coordinate conventions in the same system caused command confusion
- Robot fell because the RL policy received wrong velocity commands

Root cause:

- Controller and gRPC paths used different coordinate conventions
- Any new command source (navigation, odor policy) would inherit the wrong convention

Fix:

- `real_controller.dart`: controller now outputs directly in Walk convention `(x=forward, y=left, z=ccw_yaw)`
- `real_control_dog.dart`: removed axis swapping, passes direction through directly
- All paths (controller, gRPC, future sources) now use one unified convention

Relevant files:

- `han_dog/lib/src/real_controller.dart`
- `han_dog/lib/src/real_control_dog.dart`

Commit: `fbaa01e`

### 7. MuJoCo simulation PD gains fix (2026-03-26)

Problem:

- `apply_history_to_model()` in `odor_mujoco_cms_demo.py` passed PD gains through `dart_to_mujoco()`
- `dart_to_mujoco()` negates all values (correct for joint angles, WRONG for gains)
- Negative kp/kd makes MuJoCo position servo unstable (positive feedback)
- Robot immediately falls in simulation

Fix:

- Added `dart_gains_to_mujoco()`: reorders Dart 12+4 layout to MuJoCo 4x4 layout WITHOUT negation
- `apply_history_to_model()` now uses `dart_gains_to_mujoco()` for kp/kd

Relevant files:

- `sim/odor_mujoco_cms_demo.py`

### 8. Full coordinate system audit (2026-03-26)

Audited the entire brainstem codebase for coordinate/axis/sign convention bugs. Results:

| Component | Convention | Status |
|-----------|-----------|--------|
| RL training (Isaac Lab) | obs = [ang_vel*0.25, proj_grav, cmd(vx,vy,vyaw), joint_pos_rel, joint_vel, action] | Baseline |
| ObservationBuilder | [gyro*0.25, projGrav, direction.xyz, (pos-standing), vel*scale, (act-standing)/actScale] | Matches |
| Walk RPC proto | x=forward, y=lateral, z=yaw | Matches |
| Controller output (fixed) | x=forward(+), y=left(+), z=ccw(+) | Matches |
| Joint order (Dart) | FR(0-2), FL(3-5), RR(6-8), RL(9-11), feet(12-15) | Matches training |
| dart_to_mujoco | reorder 12+4 to 4x4 + negate (joints/velocity) | Correct |
| dart_gains_to_mujoco | reorder 12+4 to 4x4, NO negate (PD gains) | Correct |
| Quaternion proto | Hamilton (w,x,y,z) -> Dart vm.Quaternion(x,y,z,w) | Correct |
| projectedGravity | world_to_body.rotate([0,0,-1]) -> body frame gravity | Correct |

No other coordinate bugs found.

### 9. MuJoCo simulation scripts added (2026-03-29)

Added `sim/` directory with MuJoCo simulation resources:

- `odor_mujoco_cms_demo.py` - Full CMS-in-the-loop odor seeking demo (Dart server + MuJoCo physics)
- `odor_cfd_turbulence_demo.py` - CFD turbulence wind field odor navigation
- `odor_room_scenarios.py` - Multi-scenario room odor validation
- `odor_nav_gateway_retarget_demo.py` - Navigation gateway retarget integration
- `build_odor_casebook.py` - Scenario casebook generator
- `build_odor_report_ppt.py` - PowerPoint report generator
- `verify_gestures.py` - Gesture SDK MuJoCo verification
- `quadruped.xml` - MuJoCo robot model (hand-written, joint axes negated from URDF)
- `profiles/odor_demo.json` - Simulation profile config

`sim/output/` is gitignored (generated videos/images/CSVs).

## Local Validation

Verified locally on `D:\inovxio\brain\brainstem`:

- `dart analyze han_dog/ han_dog_brain/` -> zero issues
- `dart test han_dog/ han_dog_brain/ frequency_watch/ skinny_dog_algebra/` -> 232 tests passed
- previously verified package test set:
  - `han_dog/test`
  - `han_dog_brain/test`
  - `frequency_watch/test`
  - `robo_device_proto/test`

What the tests specifically cover:

- `Grounded` rejects `Walk` with `FAILED_PRECONDITION`
- `Transitioning` rejects conflicting commands
- `GetCmsState` returns authoritative current state
- `ListenCmsState` yields initial state plus subsequent updates
- `GrpcService` follows the state stream instead of guessing from `History.command`

## Remote Validation On `sunrise`

When the host was reachable, the following completed successfully on:

- `/home/sunrise/Desktop/brainstem`

Validated:

- targeted non-Flutter analyze:
  - `dart analyze han_dog han_dog_brain han_dog_message frequency_watch robo_device_proto robo_device serial_port onnx_runtime skinny_dog_algebra`
- compile:
  - `dart compile exe han_dog/bin/server.dart -o build/server`
- smoke:
  - `timeout 5 ./build/server`
  - server loaded profiles and model
  - inferred `historySize=5`
  - FSM entered `Init -> Grounded`
  - gRPC listened on `:13145`
  - clean timeout shutdown

Also validated remotely through gRPC before the host became unreachable:

- `GetStartTime` returned successfully
- `GetCmsState` returned `Grounded`
- first `ListenCmsState` event was `Grounded`
- `Walk` while grounded returned `FAILED_PRECONDITION`
- `StandUp` was accepted and moved FSM into `Transitioning/StandUp`

## Pending Real-Robot Verification

The following can ONLY be verified on real hardware:

1. **Hi91 IMU physical mounting** - If IMU XYZ axes don't align with robot body frame (X=forward, Y=left, Z=up), gyroscope and projectedGravity will be wrong and the robot won't balance. Test: StandUp with no Walk command - if it falls immediately, IMU orientation is wrong.

2. **Walk direction** - Test: Walk(x=0.3, y=0, z=0) should move the robot forward. If it goes sideways or backward, there's an axis mismatch between IMU and training convention.

3. **Yaw sign** - Test: push yaw knob and observe rotation direction. If clockwise/counterclockwise are reversed, change `-yaw` to `yaw` in `real_controller.dart:42`.

4. **Motor encoder sign convention** - Robstride motor encoder outputs must match URDF joint angle convention. If a joint moves the wrong way, the specific motor's sign needs to be flipped in `RealJoint`.

## Known Remaining Issues

### 1. Motor output gated by CH5 enable

In `han_dog/bin/han_dog.dart`, motor output is gated through `motorOutputEnabled` flag, controlled by YUNZHUO CH5 switch. This is the intended safety mechanism for bench testing.

### 2. Remote Sirius checks need Flutter SDK

`sirius` is a Flutter app. On `sunrise`, whole-tree `dart analyze` will fail if the environment does not have Flutter package resolution available.

Use this instead on the remote host:

```bash
/usr/local/dart-sdk/bin/dart analyze \
  han_dog han_dog_brain han_dog_message frequency_watch \
  robo_device_proto robo_device serial_port onnx_runtime skinny_dog_algebra
```

Do not treat remote `sirius` analyze failure as a backend regression unless Flutter is installed there.

## Recommended Next Steps

Once `sunrise` is reachable again:

1. `git pull` to get the Walk convention fix (`fbaa01e`).

2. Clean old server processes.

```bash
pkill -9 -f "build/server" || true
```

3. Rebuild the remote server binary.

```bash
cd /home/sunrise/Desktop/brainstem
/usr/local/dart-sdk/bin/dart compile exe han_dog/bin/server.dart -o build/server
```

4. Real robot bring-up sequence:

```
a. Enable motors (CH5 on controller)
b. StandUp -> verify robot stands stably (IMU check)
c. Walk(x=0.3, 0, 0) -> verify forward movement (command check)
d. Walk(0, 0.3, 0) -> verify leftward movement (lateral check)
e. Walk(0, 0, 0.3) -> verify counterclockwise rotation (yaw check)
f. Full cycle: Grounded -> StandUp -> Standing -> Walking -> SitDown -> Grounded
```

5. If yaw is reversed, change `real_controller.dart:42` from `-yaw` to `yaw`.

6. After direction is confirmed, connect Sirius Flutter app and verify dashboard state tracking.

## Quick Resume Checklist

If someone resumes this later, start with this exact order:

1. `git pull` on target machine
2. Rebuild `build/server` (or `han_dog.dart` for real hardware)
3. Verify IMU orientation: StandUp without Walk -> should stand stable
4. Verify Walk directions: forward/left/yaw match expectations
5. If yaw reversed: flip sign in `real_controller.dart:42`
6. Connect Sirius and verify live state display
7. Full FSM cycle test
