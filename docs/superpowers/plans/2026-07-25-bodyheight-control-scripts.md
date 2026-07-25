# Body-height Control Scripts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add editable robot-side service management and local gRPC helpers for the Thunder H15/H18 body-height policies without automating motor enable or posture transitions.

**Architecture:** A Bash script owns only robot process lifecycle and systemd state. A dependency-light Python script owns gRPC status, height, and bounded velocity commands; gRPC imports are delayed so its validation and command-confirmation logic can be unit-tested with fake stubs.

**Tech Stack:** Bash, systemd, Python 3 standard library, grpcio, generated `brainstem_api`, `unittest`.

---

## File structure

- Create `scripts/bodyheight_service.sh`: robot-side `status`, `start`,
  `logs`, `stop`, and `restore-master` commands.
- Create `scripts/bodyheight_grpc.py`: local gRPC status/command client.
- Create `scripts/tests/test_bodyheight_grpc.py`: fake-stub Python tests.
- Create `scripts/tests/bodyheight_service_test.sh`: Bash parsing/refusal tests.
- Modify `docs/BODYHEIGHTCTRL.md`: operator examples, defaults, and safety
  semantics.

### Task 1: Lock the Python command contract with failing tests

**Files:**
- Create: `scripts/tests/test_bodyheight_grpc.py`
- Test: `scripts/tests/test_bodyheight_grpc.py`

- [ ] **Step 1: Write tests for defaults and validation**

Use `importlib.util.spec_from_file_location` to import
`scripts/bodyheight_grpc.py`. Assert that `build_parser()` gives target
`192.168.66.190:13145`, that omitted velocity axes resolve to zero, that a bare
`set-velocity` is rejected, and that H15/H18 limits are read from profile JSON.

```python
def test_missing_velocity_axes_default_to_zero(self):
    args = self.module.build_parser().parse_args(
        ["set-velocity", "--vx", "0.1"]
    )
    self.assertEqual(self.module.resolve_velocity(args), (0.1, 0.0, 0.0))

def test_bare_velocity_is_rejected(self):
    args = self.module.build_parser().parse_args(["set-velocity"])
    with self.assertRaisesRegex(ValueError, "at least one"):
        self.module.resolve_velocity(args)
```

- [ ] **Step 2: Write fake-stub confirmation tests**

Create fake protobuf message factories and a fake stub. Test:

```python
def test_set_height_confirms_history(self):
    client = self.make_client(
        profile="thunder_h15",
        histories=[history(height=0.32)],
    )
    client.set_height(0.32)
    self.assertAlmostEqual(client.stub.height_requests[0].meters, 0.32)

def test_set_height_detects_silent_rejection(self):
    client = self.make_client(
        profile="thunder_h15",
        histories=[history(height=0.35)],
    )
    with self.assertRaisesRegex(RuntimeError, "not observed"):
        client.set_height(0.32)

def test_set_velocity_confirms_walk_vector(self):
    client = self.make_client(
        state=2,
        histories=[history(walk=(0.1, 0.0, 0.0))],
    )
    client.set_velocity(0.1, 0.0, 0.0)
    self.assertEqual(len(client.stub.walk_requests), 1)
```

- [ ] **Step 3: Run the tests and prove they fail**

Run:

```text
python -m unittest discover -s scripts/tests -p "test_bodyheight_grpc.py" -v
```

Expected: import failure because `scripts/bodyheight_grpc.py` does not yet
exist.

### Task 2: Implement the Python gRPC helper

**Files:**
- Create: `scripts/bodyheight_grpc.py`
- Test: `scripts/tests/test_bodyheight_grpc.py`

- [ ] **Step 1: Implement pure configuration and argument parsing**

Add:

```python
@dataclass(frozen=True)
class PolicyLimits:
    min_height: float
    max_height: float
    min_velocity: tuple[float, float, float]
    max_velocity: tuple[float, float, float]

def resolve_velocity(args):
    values = (args.vx, args.vy, args.yaw)
    if all(value is None for value in values):
        raise ValueError("set-velocity requires at least one axis")
    return tuple(0.0 if value is None else value for value in values)
```

The parser exposes `status`, `set-height METRES`,
`set-velocity [--vx] [--vy] [--yaw]`, and `watch-height`. The global defaults
are `--target 192.168.66.190:13145`, `--timeout 5.0`, and
`--profile-dir han_dog/profiles`.

- [ ] **Step 2: Implement delayed API loading**

Search `brainstem_api/python` relative to the repository before importing
`grpc`, `RobotControlStub`, `Empty`, `Vector3`, and
`brainstem_api.cms_pb2.BodyHeightCommand`. Missing dependencies produce a
single actionable error instead of an import traceback.

- [ ] **Step 3: Implement profile and telemetry guards**

`BodyHeightClient` must:

```python
ALLOWED_PROFILES = frozenset({"thunder_h15", "thunder_h18"})
ALLOWED_VELOCITY_STATES = frozenset({2, 3})  # Standing, Walking
```

It calls `GetProfile` before either command, reads bounds from the matching
local JSON, rejects non-finite/out-of-range values, and confirms the result
from `ListenHistory`. Confirmation uses a deadline and a small floating-point
tolerance. A gRPC success with no matching telemetry exits non-zero.

- [ ] **Step 4: Run Python tests**

Run:

```text
python -m unittest discover -s scripts/tests -p "test_bodyheight_grpc.py" -v
```

Expected: all tests pass.

- [ ] **Step 5: Compile-check the helper**

Run:

```text
python -m py_compile scripts/bodyheight_grpc.py scripts/tests/test_bodyheight_grpc.py
```

Expected: exit code 0.

### Task 3: Lock and implement the robot service helper

**Files:**
- Create: `scripts/tests/bodyheight_service_test.sh`
- Create: `scripts/bodyheight_service.sh`

- [ ] **Step 1: Write parsing/refusal tests first**

The Bash test runs the script in a temporary directory and asserts:

```bash
expect_status 0 help
expect_status 2 start
expect_status 2 start unknown
expect_status 2 logs --bad-option
```

It also supplies fake `systemctl`, `ss`, and `journalctl` executables to prove
that `start h15` refuses while `han_dog.service` is active and that no
`systemd-run` command was invoked.

- [ ] **Step 2: Run the Bash test and prove it fails**

Run on Linux:

```text
bash scripts/tests/bodyheight_service_test.sh
```

Expected: failure because `scripts/bodyheight_service.sh` does not yet exist.

- [ ] **Step 3: Implement configuration and safe preflight**

At the top of `bodyheight_service.sh`, define overridable defaults:

```bash
BRAINSTEM_ROOT="${BRAINSTEM_ROOT:-/home/bsrl1/brainstem-bodyheightctrl}"
DART_BIN="${DART_BIN:-/home/bsrl1/flutter/bin/dart}"
PRODUCTION_UNIT="${PRODUCTION_UNIT:-han_dog.service}"
CANDIDATE_UNIT="${CANDIDATE_UNIT:-han-dog-bodyheight.service}"
GRPC_PORT="${GRPC_PORT:-13145}"
IMU_PORT="${IMU_PORT:-/dev/imu}"
YUNZHUO_PORT="${YUNZHUO_PORT:-/dev/yunzhuo}"
```

`start` maps `h15` and `h18` to exact profile/model/hash tuples, then checks:
production/candidate unit state, port ownership, executable paths, device
paths, model hash, and profile JSON. Every ambiguous condition fails closed.

- [ ] **Step 4: Implement lifecycle commands**

`start` uses `sudo systemd-run` with explicit unit name, user/group, working
directory, Dart entry point, profile, profile directory, IMU/Yunzhuo paths,
gRPC port, and library path. It waits for the unit and port to become ready.

`status` is read-only. `logs` calls `journalctl` with optional `--follow`.
`stop` stops only the candidate unit and prints a prominent motor-disabled
warning. `restore-master` refuses unless the candidate is inactive and port
`13145` is free, then starts only the existing production unit. No command
installs, edits, enables, or daemon-reloads a systemd unit.

- [ ] **Step 5: Run shell verification**

Run:

```text
bash -n scripts/bodyheight_service.sh
bash scripts/tests/bodyheight_service_test.sh
```

Expected: syntax check and all shell tests pass.

### Task 4: Document and verify the complete change

**Files:**
- Modify: `docs/BODYHEIGHTCTRL.md`
- Modify: `docs/superpowers/specs/2026-07-25-bodyheight-control-scripts-design.md`

- [ ] **Step 1: Add operator examples**

Document direct and tunneled targets:

```text
python scripts/bodyheight_grpc.py status
python scripts/bodyheight_grpc.py --target 127.0.0.1:13146 set-height 0.32
python scripts/bodyheight_grpc.py set-velocity --vx 0.1
```

Explain that `set-velocity --vx 0.1` means `(0.1, 0.0, 0.0)`, a bare
`set-velocity` is rejected, and the tool does not enable motors or stand the
robot.

- [ ] **Step 2: Run all new offline checks**

Run:

```text
python -m unittest discover -s scripts/tests -p "test_*.py" -v
python -m py_compile scripts/bodyheight_grpc.py scripts/tests/test_bodyheight_grpc.py
bash -n scripts/bodyheight_service.sh
bash scripts/tests/bodyheight_service_test.sh
git diff --check
```

Expected: all tests pass and `git diff --check` reports no errors. Bash checks
may run through the robot's shell over SSH, but the script itself must not be
started and no gRPC command may be sent.

- [ ] **Step 3: Review safety invariants**

Search the new files and prove there are no calls to `Enable`, `StandUp`, or
`SitDown`, no embedded password, and no automatic stop of
`han_dog.service`.

- [ ] **Step 4: Commit and push**

Commit with per-command identity only:

```text
git -c user.name=hahadahe -c user.email=911987281@qq.com commit
```

Push `bodyheightctrl` without changing repository-default Git identity. Do not
open or merge a pull request.
