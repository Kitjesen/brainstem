#!/usr/bin/env bash
set -Eeuo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_SCRIPT="$TEST_DIR/../bodyheight_service.sh"
FIXTURE="$(mktemp -d)"
trap 'rm -rf -- "$FIXTURE"' EXIT

PASS=0
FAIL=0
LAST_OUTPUT=""
LAST_STATUS=0

fail() {
  printf 'not ok - %s\n' "$1"
  FAIL=$((FAIL + 1))
}

pass() {
  printf 'ok - %s\n' "$1"
  PASS=$((PASS + 1))
}

assert_status() {
  local expected="$1"
  local label="$2"
  if [[ "$LAST_STATUS" == "$expected" ]]; then
    pass "$label"
  else
    fail "$label (expected status $expected, got $LAST_STATUS; output: $LAST_OUTPUT)"
  fi
}

assert_contains() {
  local needle="$1"
  local label="$2"
  if [[ "$LAST_OUTPUT" == *"$needle"* ]]; then
    pass "$label"
  else
    fail "$label (missing: $needle; output: $LAST_OUTPUT)"
  fi
}

assert_file_absent() {
  local path="$1"
  local label="$2"
  if [[ ! -e "$path" ]]; then
    pass "$label"
  else
    fail "$label (unexpected file: $path)"
  fi
}

assert_log_line() {
  local line="$1"
  local label="$2"
  if grep -Fqx -- "$line" "$CALL_LOG"; then
    pass "$label"
  else
    fail "$label (missing exact log line: $line)"
  fi
}

make_fake_commands() {
  mkdir -p "$FAKE_BIN"

  cat >"$FAKE_BIN/systemctl" <<'EOF'
#!/usr/bin/env bash
set -u
printf 'systemctl:%s\n' "$*" >>"$CALL_LOG"
case "${1-}:${2-}" in
  is-active:han_dog.service)
    [[ "${PRODUCTION_STATE:-inactive}" == active ]] && { echo active; exit 0; }
    echo "${PRODUCTION_STATE:-inactive}"
    exit 3
    ;;
  is-active:han-dog-bodyheight.service)
    if [[ -e "$CANDIDATE_MARKER" ]]; then echo active; exit 0; fi
    case "${CANDIDATE_STATE:-inactive}" in
      active) echo active; exit 0 ;;
      activating) echo activating; exit 3 ;;
      deactivating) echo deactivating; exit 3 ;;
      *) echo inactive; exit 3 ;;
    esac
    ;;
  show:han-dog-bodyheight.service)
    printf 'MainPID=4242\nActiveState=active\nSubState=running\n'
    ;;
  start:han_dog.service|stop:han-dog-bodyheight.service)
    exit 0
    ;;
esac
exit 0
EOF

  cat >"$FAKE_BIN/systemd-run" <<'EOF'
#!/usr/bin/env bash
set -u
printf 'systemd-run\n' >>"$CALL_LOG"
printf '%s\n' "$@" >>"$CALL_LOG"
[[ "${SYSTEMD_RUN_FAIL:-0}" == 1 ]] && exit 1
: >"$RUN_MARKER"
: >"$CANDIDATE_MARKER"
EOF

  cat >"$FAKE_BIN/sudo" <<'EOF'
#!/usr/bin/env bash
set -u
printf 'sudo:%s\n' "$*" >>"$CALL_LOG"
exec "$@"
EOF

  cat >"$FAKE_BIN/ss" <<'EOF'
#!/usr/bin/env bash
set -u
printf 'ss:%s\n' "$*" >>"$CALL_LOG"
if [[ "${PORT_BUSY:-0}" == 1 || -e "$CANDIDATE_MARKER" ]]; then
  echo 'LISTEN 0 128 0.0.0.0:13145 0.0.0.0:*'
fi
EOF

  cat >"$FAKE_BIN/journalctl" <<'EOF'
#!/usr/bin/env bash
set -u
printf 'journalctl:%s\n' "$*" >>"$CALL_LOG"
EOF

  cat >"$FAKE_BIN/sha256sum" <<'EOF'
#!/usr/bin/env bash
set -u
printf '%s  %s\n' "${FAKE_SHA:-bad}" "${1-}"
EOF

  cat >"$FAKE_BIN/sleep" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

  chmod +x "$FAKE_BIN"/*
}

reset_fixture() {
  CASE_DIR="$FIXTURE/case-$RANDOM-$RANDOM"
  BRAINSTEM_ROOT="$CASE_DIR/brainstem"
  PROFILE_DIR="$BRAINSTEM_ROOT/han_dog/profiles"
  FAKE_BIN="$CASE_DIR/fake-bin"
  CALL_LOG="$CASE_DIR/calls.log"
  RUN_MARKER="$CASE_DIR/systemd-run.called"
  CANDIDATE_MARKER="$CASE_DIR/candidate.active"
  DART_BIN="$CASE_DIR/dart"
  IMU_PORT="$CASE_DIR/imu"
  YUNZHUO_PORT="$CASE_DIR/yunzhuo"
  mkdir -p "$PROFILE_DIR" "$BRAINSTEM_ROOT/han_dog/bin" "$BRAINSTEM_ROOT/model"
  : >"$CALL_LOG"
  : >"$DART_BIN"
  : >"$IMU_PORT"
  : >"$YUNZHUO_PORT"
  : >"$BRAINSTEM_ROOT/han_dog/bin/han_dog.dart"
  : >"$BRAINSTEM_ROOT/model/thunder_h15_model10400.onnx"
  : >"$BRAINSTEM_ROOT/model/thunder_h18_model5000.onnx"
  chmod +x "$DART_BIN"
  cat >"$PROFILE_DIR/thunder_h15.json" <<'EOF'
{"name":"thunder_h15","modelPath":"model/thunder_h15_model10400.onnx","_onnxSha256":"ded34be402b25a3a77a9feba196a3d76efa2b5660d7d9c8396b28963a0efbde4"}
EOF
  cat >"$PROFILE_DIR/thunder_h18.json" <<'EOF'
{"name":"thunder_h18","modelPath":"model/thunder_h18_model5000.onnx","_onnxSha256":"d632413aa9ddf16b6c795377bdbbef69c454ba1cc77f8acb7d560f381cd84296"}
EOF
  PRODUCTION_STATE=inactive
  CANDIDATE_STATE=inactive
  PORT_BUSY=0
  SYSTEMD_RUN_FAIL=0
  FAKE_SHA=ded34be402b25a3a77a9feba196a3d76efa2b5660d7d9c8396b28963a0efbde4
  make_fake_commands
}

run_service() {
  set +e
  LAST_OUTPUT="$(
    BRAINSTEM_ROOT="$BRAINSTEM_ROOT" \
    DART_BIN="$DART_BIN" \
    SERVICE_USER=test-user \
    SERVICE_GROUP=test-group \
    PRODUCTION_UNIT=han_dog.service \
    CANDIDATE_UNIT=han-dog-bodyheight.service \
    GRPC_PORT=13145 \
    IMU_PORT="$IMU_PORT" \
    YUNZHUO_PORT="$YUNZHUO_PORT" \
    PROFILE_DIR="$PROFILE_DIR" \
    LD_LIBRARY_PATH=/opt/onnxruntime/lib:/usr/local/lib:/usr/lib/aarch64-linux-gnu:/lib/aarch64-linux-gnu \
    SYSTEMCTL_BIN="$FAKE_BIN/systemctl" \
    SYSTEMD_RUN_BIN="$FAKE_BIN/systemd-run" \
    SUDO_BIN="$FAKE_BIN/sudo" \
    SS_BIN="$FAKE_BIN/ss" \
    JOURNALCTL_BIN="$FAKE_BIN/journalctl" \
    SHA256SUM_BIN="$FAKE_BIN/sha256sum" \
    SLEEP_BIN="$FAKE_BIN/sleep" \
    CALL_LOG="$CALL_LOG" \
    RUN_MARKER="$RUN_MARKER" \
    CANDIDATE_MARKER="$CANDIDATE_MARKER" \
    PRODUCTION_STATE="$PRODUCTION_STATE" \
    CANDIDATE_STATE="$CANDIDATE_STATE" \
    PORT_BUSY="$PORT_BUSY" \
    SYSTEMD_RUN_FAIL="$SYSTEMD_RUN_FAIL" \
    FAKE_SHA="$FAKE_SHA" \
    bash "$SERVICE_SCRIPT" "$@" 2>&1
  )"
  LAST_STATUS=$?
  set -e
}

test_help() {
  reset_fixture
  run_service --help
  assert_status 0 "help exits zero"
  assert_contains "不会启用电机" "help states start does not enable motors"
  assert_contains "停机" "help explains stop safety"
}

test_start_requires_profile() {
  reset_fixture
  run_service start
  assert_status 2 "start without profile exits two"
}

test_unknown_profile() {
  reset_fixture
  run_service start h99
  assert_status 2 "unknown profile exits two"
}

test_invalid_logs_option() {
  reset_fixture
  run_service logs --tail
  assert_status 2 "invalid logs option exits two"
}

test_start_refuses_production() {
  reset_fixture
  PRODUCTION_STATE=active
  run_service start h15
  assert_status 1 "start refuses while production is active"
  assert_contains "sudo systemctl stop han_dog.service" "production refusal prints exact remediation"
  assert_file_absent "$RUN_MARKER" "production refusal never calls systemd-run"
}

test_restore_refuses_candidate() {
  reset_fixture
  CANDIDATE_STATE=activating
  run_service restore-master
  assert_status 1 "restore-master refuses while candidate is activating"
  if ! grep -Fq 'systemctl:start han_dog.service' "$CALL_LOG"; then
    pass "restore-master refusal never starts production"
  else
    fail "restore-master refusal unexpectedly starts production"
  fi
}

test_preflight_failures_do_not_launch() {
  reset_fixture
  rm "$BRAINSTEM_ROOT/model/thunder_h15_model10400.onnx"
  run_service start h15
  assert_status 1 "missing model fails preflight"
  assert_file_absent "$RUN_MARKER" "missing model prevents systemd-run"

  reset_fixture
  FAKE_SHA=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  run_service start h15
  assert_status 1 "hash mismatch fails preflight"
  assert_file_absent "$RUN_MARKER" "hash mismatch prevents systemd-run"

  reset_fixture
  printf '%s\n' '{"name":"wrong","modelPath":"model/wrong.onnx","_onnxSha256":"bad"}' >"$PROFILE_DIR/thunder_h15.json"
  run_service start h15
  assert_status 1 "profile mismatch fails preflight"
  assert_file_absent "$RUN_MARKER" "profile mismatch prevents systemd-run"
}

test_successful_start_command() {
  reset_fixture
  run_service start h15
  assert_status 0 "valid h15 start succeeds with fakes"
  assert_contains "候选服务已启动" "successful start reports readiness"
  assert_log_line "--unit=han-dog-bodyheight.service" "launch uses exact candidate unit"
  assert_log_line "--property=User=test-user" "launch sets service user"
  assert_log_line "--property=Group=test-group" "launch sets service group"
  assert_log_line "--property=WorkingDirectory=$BRAINSTEM_ROOT" "launch sets exact working directory"
  assert_log_line "--property=Type=simple" "launch sets simple service type"
  assert_log_line "--property=KillSignal=SIGINT" "launch sets safe interrupt signal"
  assert_log_line "--property=TimeoutStopSec=10s" "launch bounds stop timeout"
  assert_log_line "--property=Restart=no" "launch disables restart loops"
  assert_log_line "--setenv=HAN_DOG_DEFAULT_PROFILE=thunder_h15" "launch sets exact profile"
  assert_log_line "--setenv=HAN_DOG_PROFILE_DIR=$PROFILE_DIR" "launch sets profile directory"
  assert_log_line "--setenv=HAN_DOG_IMU_PORT=$IMU_PORT" "launch sets IMU port"
  assert_log_line "--setenv=HAN_DOG_YUNZHUO_PORT=$YUNZHUO_PORT" "launch sets Yunzhuo port"
  assert_log_line "--setenv=HAN_DOG_PORT=13145" "launch sets gRPC port"
  assert_log_line "--setenv=LD_LIBRARY_PATH=/opt/onnxruntime/lib:/usr/local/lib:/usr/lib/aarch64-linux-gnu:/lib/aarch64-linux-gnu" "launch sets library path"
  assert_log_line "$DART_BIN" "launch uses configured Dart"
  assert_log_line "run" "launch invokes dart run"
  assert_log_line "han_dog/bin/han_dog.dart" "launch uses exact Dart entrypoint"
  if ! grep -Fq 'systemctl:stop han_dog.service' "$CALL_LOG"; then
    pass "successful candidate start never stops production"
  else
    fail "successful candidate start stopped production"
  fi
}

test_launch_failure_prints_hints() {
  reset_fixture
  SYSTEMD_RUN_FAIL=1
  run_service start h15
  assert_status 1 "systemd-run failure is reported"
  assert_contains "status" "systemd-run failure prints status hint"
  assert_contains "logs" "systemd-run failure prints logs hint"
  assert_file_absent "$RUN_MARKER" "failed systemd-run never creates readiness marker"
}

test_help
test_start_requires_profile
test_unknown_profile
test_invalid_logs_option
test_start_refuses_production
test_restore_refuses_candidate
test_preflight_failures_do_not_launch
test_successful_start_command
test_launch_failure_prints_hints

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
((FAIL == 0))
