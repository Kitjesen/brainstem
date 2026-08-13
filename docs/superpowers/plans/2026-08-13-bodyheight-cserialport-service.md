# Body-height libcserialport Service Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the H15/H18 transient service load the installed CSerialPort library reliably without changing master or starting the robot.

**Architecture:** Keep the fix at the candidate-service boundary. The shell helper validates the installed library and injects it into `systemd-run`; the Dart controller and production systemd unit remain unchanged.

**Tech Stack:** Bash, systemd-run, Dart FFI runtime environment, shell regression tests.

---

### Task 1: Lock the launch contract with failing tests

**Files:**
- Modify: `scripts/tests/bodyheight_service_test.sh`
- Test: `scripts/tests/bodyheight_service_test.sh`

- [ ] **Step 1: Require the preload argument in the fake systemd-run contract**

Add the expected argument immediately after `LD_LIBRARY_PATH`:

```bash
"--setenv=LD_PRELOAD=$CSERIALPORT_LIBRARY"
```

- [ ] **Step 2: Give each fixture a readable fake library**

Set `CSERIALPORT_LIBRARY="$CASE_DIR/libcserialport.so"`, create it with
`: >"$CSERIALPORT_LIBRARY"`, and pass it through `run_service`.

- [ ] **Step 3: Add a missing-library preflight assertion**

```bash
reset_fixture
rm "$CSERIALPORT_LIBRARY"
run_service start h15
assert_status 1 "missing libcserialport fails preflight"
assert_contains "libcserialport" "missing libcserialport prints actionable output"
assert_log_absent '^sudo:' "missing libcserialport never invokes sudo"
```

- [ ] **Step 4: Run the test and verify RED**

Run: `bash scripts/tests/bodyheight_service_test.sh`

Expected: FAIL because `CSERIALPORT_LIBRARY`/`LD_PRELOAD` is not implemented
by `scripts/bodyheight_service.sh`.

### Task 2: Restore the candidate runtime environment

**Files:**
- Modify: `scripts/bodyheight_service.sh`
- Test: `scripts/tests/bodyheight_service_test.sh`

- [ ] **Step 1: Add the installed-library configuration and readiness default**

```bash
CSERIALPORT_LIBRARY="${CSERIALPORT_LIBRARY:-/lib/aarch64-linux-gnu/libcserialport.so}"
START_TIMEOUT_SECONDS="${START_TIMEOUT_SECONDS:-45}"
```

- [ ] **Step 2: Validate the library before privilege escalation**

Require an absolute, newline-free, readable regular-file path and emit a
`libcserialport` preflight message on failure.

- [ ] **Step 3: Preload the library in the transient unit**

Add:

```bash
"--setenv=LD_PRELOAD=$CSERIALPORT_LIBRARY"
```

before the Dart executable in the ordered `systemd-run` argument list.

- [ ] **Step 4: Run the test and verify GREEN**

Run: `bash scripts/tests/bodyheight_service_test.sh`

Expected: all assertions pass with exit code 0.

### Task 3: Deliver and verify without motion

**Files:**
- Commit: the spec, plan, service helper, and service tests only.

- [ ] **Step 1: Inspect the scoped diff**

Run: `git diff --check` and `git diff -- scripts/bodyheight_service.sh scripts/tests/bodyheight_service_test.sh`.

Expected: no whitespace errors and only the approved runtime changes.

- [ ] **Step 2: Commit and push using the requested author identity**

```bash
git add docs/superpowers/specs/2026-08-13-bodyheight-cserialport-service-design.md \
  docs/superpowers/plans/2026-08-13-bodyheight-cserialport-service.md \
  scripts/bodyheight_service.sh scripts/tests/bodyheight_service_test.sh
git -c user.name=hahadahe -c user.email=911987281@qq.com commit \
  -m "fix(bodyheight): preload serial runtime"
git push origin bodyheightctrl
```

- [ ] **Step 3: Fast-forward only the robot candidate checkout**

Fetch and fast-forward `/home/bsrl1/brainstem-bodyheightctrl`, leaving
`/home/bsrl1/brainstem` unchanged and preserving the existing stash.

- [ ] **Step 4: Verify the deployed files without starting a service**

Confirm the candidate commit, clean status, serial-library path, preload line,
and successful read-only `serial_port/example/list_all.dart` execution with
`LD_PRELOAD`. Confirm both robot services remain inactive.
