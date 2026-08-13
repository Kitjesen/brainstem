#!/usr/bin/env bash
set -Eeuo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_SCRIPT="$TEST_DIR/../bodyheight_service.sh"
TEST_BASH_BIN="$(command -v bash)"
TEST_PYTHON_BIN="$(command -v "${PYTHON_BIN_FOR_TESTS:-python3}")"
TEST_CAT_BIN="$(command -v cat)"
TEST_BASENAME_BIN="$(command -v basename)"
TEST_MKDIR_BIN="$(command -v mkdir)"
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

assert_file_present() {
  local path="$1"
  local label="$2"
  if [[ -e "$path" ]]; then
    pass "$label"
  else
    fail "$label (missing file: $path)"
  fi
}

assert_log_absent() {
  local pattern="$1"
  local label="$2"
  if ! grep -Eq -- "$pattern" "$CALL_LOG"; then
    pass "$label"
  else
    fail "$label (unexpected log match: $pattern)"
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

assert_no_lifecycle_calls() {
  local label="$1"
  if ! grep -Eq '^(sudo|systemctl|systemd-run|ss|sha256sum|sleep|journalctl):' "$CALL_LOG"; then
    pass "$label"
  else
    fail "$label (unexpected lifecycle call log: $(<"$CALL_LOG"))"
  fi
}

make_fake_commands() {
  mkdir -p "$FAKE_BIN"

  cat >"$FAKE_BIN/systemctl" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'systemctl:%s\n' "$*" >>"$CALL_LOG"
reject() { printf 'unexpected systemctl argv: %s\n' "$*" >&2; exit 97; }
if (($# == 2)) && [[ "$1" == is-active ]]; then
  case "$2" in
    "$PRODUCTION_UNIT") state="$PRODUCTION_STATE" ;;
    "$CANDIDATE_UNIT")
      if [[ -e "$CANDIDATE_MARKER" ]]; then state=active; else state="$CANDIDATE_STATE"; fi
      ;;
    *) reject "$@" ;;
  esac
  case "$state" in
    active) echo active; exit 0 ;;
    inactive|failed|activating|deactivating|absent|unknown)
      echo "$state"
      exit 3
      ;;
    *) reject "$@" ;;
  esac
elif (($# == 6)) &&
  [[ "$1" == show && "$2" == "$CANDIDATE_UNIT" &&
     "$3" == --property=MainPID && "$4" == --property=ActiveState &&
     "$5" == --property=SubState && "$6" == --no-pager ]]; then
    printf 'MainPID=4242\nActiveState=active\nSubState=running\n'
elif (($# == 2)) && [[ "$1" == start && "$2" == "$PRODUCTION_UNIT" ]]; then
  exit 0
elif (($# == 2)) && [[ "$1" == stop && "$2" == "$CANDIDATE_UNIT" ]]; then
  exit 0
else
  reject "$@"
fi
EOF

  cat >"$FAKE_BIN/systemd-run" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
expected=(
  --collect
  "--unit=$CANDIDATE_UNIT"
  "--property=User=$SERVICE_USER"
  "--property=Group=$SERVICE_GROUP"
  "--property=WorkingDirectory=$BRAINSTEM_ROOT"
  --property=Type=simple
  --property=KillSignal=SIGINT
  "--property=TimeoutStopSec=$STOP_TIMEOUT_SECONDS"
  --property=Restart=no
  "--setenv=HAN_DOG_DEFAULT_PROFILE=$EXPECTED_LAUNCH_PROFILE"
  "--setenv=HAN_DOG_PROFILE_DIR=$PROFILE_DIR"
  "--setenv=HAN_DOG_IMU_PORT=$IMU_PORT"
  "--setenv=HAN_DOG_YUNZHUO_PORT=$YUNZHUO_PORT"
  "--setenv=HAN_DOG_PORT=$GRPC_PORT"
  "--setenv=LD_LIBRARY_PATH=$LD_LIBRARY_PATH"
  "--setenv=LD_PRELOAD=$CSERIALPORT_LIBRARY"
  "$DART_BIN"
  run
  han_dog/bin/han_dog.dart
)
(($# == ${#expected[@]})) || {
  printf 'unexpected systemd-run argc: %s\n' "$#" >&2
  exit 97
}
for index in "${!expected[@]}"; do
  position=$((index + 1))
  [[ "${!position}" == "${expected[$index]}" ]] || {
    printf 'unexpected systemd-run argv[%s]\n' "$index" >&2
    exit 97
  }
done
printf 'systemd-run:argv-ok:%s\n' "$EXPECTED_LAUNCH_PROFILE" >>"$CALL_LOG"
[[ "${SYSTEMD_RUN_FAIL:-0}" == 1 ]] && exit 1
: >"$RUN_MARKER"
: >"$CANDIDATE_MARKER"
EOF

  cat >"$FAKE_BIN/sudo" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'sudo:%s\n' "$*" >>"$CALL_LOG"
if [[ "${1-}" != "$FAKE_SYSTEMCTL" && "${1-}" != "$FAKE_SYSTEMD_RUN" ]]; then
  printf 'sudo target rejected: %s\n' "${1-}" >&2
  exit 98
fi
exec "$@"
EOF

  cat >"$FAKE_BIN/ss" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'ss:%s\n' "$*" >>"$CALL_LOG"
if (($# != 2)) || [[ "$1" != -ltnH || "$2" != "sport = :$GRPC_PORT" ]]; then
  printf 'unexpected ss argv: %s\n' "$*" >&2
  exit 97
fi
[[ "${SS_FAIL:-0}" == 1 ]] && exit 96
if [[ "${PORT_BUSY:-0}" == 1 ||
      ( -e "$CANDIDATE_MARKER" && "${READINESS_PORT:-1}" == 1 ) ]]; then
  printf 'LISTEN 0 128 0.0.0.0:%s 0.0.0.0:*\n' "$GRPC_PORT"
fi
EOF

  cat >"$FAKE_BIN/journalctl" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'journalctl:%s\n' "$*" >>"$CALL_LOG"
if (($# == 5)) &&
  [[ "$1" == -u && "$2" == "$CANDIDATE_UNIT" &&
     "$3" == -n && "$4" == 100 && "$5" == --no-pager ]]; then
  exit 0
elif (($# == 5)) &&
  [[ "$1" == -u && "$2" == "$CANDIDATE_UNIT" &&
     "$3" == -n && "$4" == 100 && "$5" == --follow ]]; then
  exit 0
fi
printf 'unexpected journalctl argv: %s\n' "$*" >&2
exit 97
EOF

  cat >"$FAKE_BIN/sha256sum" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s  %s\n' "${FAKE_SHA:-bad}" "${1-}"
printf 'sha256sum:%s\n' "$*" >>"$CALL_LOG"
(($# == 1)) && [[ "$1" == "$EXPECTED_MODEL_PATH" ]] || {
  printf 'unexpected sha256sum argv: %s\n' "$*" >&2
  exit 97
}
EOF

  cat >"$FAKE_BIN/sleep" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'sleep:%s\n' "$*" >>"$CALL_LOG"
(($# == 1)) && [[ "$1" == 1 ]] || exit 97
EOF

  cat >"$FAKE_BIN/flock" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'flock:%s\n' "$*" >>"$CALL_LOG"
(($# == 2)) && [[ "$1" == -n && "$2" =~ ^[0-9]+$ ]] || exit 97
if [[ "${LOCK_BUSY:-0}" == 1 ]]; then
  exit 1
fi
exit 0
EOF

  cat >"$FAKE_BIN/mkdir" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'mkdir:%s\n' "$*" >>"$CALL_LOG"
if (($# != 4)) ||
  [[ "$1" != -m || "$2" != 700 || "$3" != -- || "$4" != "$LOCK_DIR" ]]; then
  printf 'unexpected mkdir argv: %s\n' "$*" >&2
  exit 97
fi
exec "$REAL_MKDIR_BIN" "$@"
EOF

  chmod +x "$FAKE_BIN"/*
  ln -s "$TEST_BASH_BIN" "$FAKE_BIN/bash"
  ln -s "$TEST_CAT_BIN" "$FAKE_BIN/cat"
  ln -s "$TEST_BASENAME_BIN" "$FAKE_BIN/basename"
}

reset_fixture() {
  CASE_DIR="$FIXTURE/case-$RANDOM-$RANDOM"
  BRAINSTEM_ROOT="$CASE_DIR/brainstem"
  PROFILE_DIR="$BRAINSTEM_ROOT/han_dog/profiles"
  FAKE_BIN="$CASE_DIR/fake-bin"
  CALL_LOG="$CASE_DIR/calls.log"
  RUN_MARKER="$CASE_DIR/systemd-run.called"
  CANDIDATE_MARKER="$CASE_DIR/candidate.active"
  LOCK_DIR="$CASE_DIR/han-dog-bodyheight.lock.d"
  DART_BIN="$CASE_DIR/dart"
  PYTHON_BIN="$TEST_PYTHON_BIN"
  IMU_PORT="$CASE_DIR/imu"
  YUNZHUO_PORT="$CASE_DIR/yunzhuo"
  CSERIALPORT_LIBRARY="$CASE_DIR/libcserialport.so"
  SERVICE_USER=test-user
  SERVICE_GROUP=test-group
  PRODUCTION_UNIT=han_dog.service
  CANDIDATE_UNIT=han-dog-bodyheight.service
  GRPC_PORT=13145
  START_TIMEOUT_SECONDS=2
  STOP_TIMEOUT_SECONDS=10s
  mkdir -p "$PROFILE_DIR" "$BRAINSTEM_ROOT/han_dog/bin" "$BRAINSTEM_ROOT/model"
  : >"$CALL_LOG"
  : >"$DART_BIN"
  : >"$IMU_PORT"
  : >"$YUNZHUO_PORT"
  : >"$CSERIALPORT_LIBRARY"
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
  READINESS_PORT=1
  SS_FAIL=0
  LOCK_BUSY=0
  SYSTEMD_RUN_FAIL=0
  EXPECTED_LAUNCH_PROFILE=thunder_h15
  EXPECTED_MODEL_PATH="$BRAINSTEM_ROOT/model/thunder_h15_model10400.onnx"
  FAKE_SHA=ded34be402b25a3a77a9feba196a3d76efa2b5660d7d9c8396b28963a0efbde4
  make_fake_commands
  FAKE_SYSTEMCTL="$FAKE_BIN/systemctl"
  FAKE_SYSTEMD_RUN="$FAKE_BIN/systemd-run"
}

run_service() {
  set +e
  LAST_OUTPUT="$(
    PATH="$FAKE_BIN" \
    BRAINSTEM_ROOT="$BRAINSTEM_ROOT" \
    DART_BIN="$DART_BIN" \
    PYTHON_BIN="$PYTHON_BIN" \
    SERVICE_USER="$SERVICE_USER" \
    SERVICE_GROUP="$SERVICE_GROUP" \
    PRODUCTION_UNIT="$PRODUCTION_UNIT" \
    CANDIDATE_UNIT="$CANDIDATE_UNIT" \
    GRPC_PORT="$GRPC_PORT" \
    IMU_PORT="$IMU_PORT" \
    YUNZHUO_PORT="$YUNZHUO_PORT" \
    PROFILE_DIR="$PROFILE_DIR" \
    LD_LIBRARY_PATH=/opt/onnxruntime/lib:/usr/local/lib:/usr/lib/aarch64-linux-gnu:/lib/aarch64-linux-gnu \
    CSERIALPORT_LIBRARY="$CSERIALPORT_LIBRARY" \
    START_TIMEOUT_SECONDS="$START_TIMEOUT_SECONDS" \
    STOP_TIMEOUT_SECONDS="$STOP_TIMEOUT_SECONDS" \
    LOCK_DIR="$LOCK_DIR" \
    SYSTEMCTL_BIN="$FAKE_SYSTEMCTL" \
    SYSTEMD_RUN_BIN="$FAKE_SYSTEMD_RUN" \
    SUDO_BIN="$FAKE_BIN/sudo" \
    SS_BIN="$FAKE_BIN/ss" \
    JOURNALCTL_BIN="$FAKE_BIN/journalctl" \
    SHA256SUM_BIN="$FAKE_BIN/sha256sum" \
    SLEEP_BIN="$FAKE_BIN/sleep" \
    FLOCK_BIN="$FAKE_BIN/flock" \
    MKDIR_BIN="$FAKE_BIN/mkdir" \
    CALL_LOG="$CALL_LOG" \
    RUN_MARKER="$RUN_MARKER" \
    CANDIDATE_MARKER="$CANDIDATE_MARKER" \
    FAKE_SYSTEMCTL="$FAKE_SYSTEMCTL" \
    FAKE_SYSTEMD_RUN="$FAKE_SYSTEMD_RUN" \
    PRODUCTION_STATE="$PRODUCTION_STATE" \
    CANDIDATE_STATE="$CANDIDATE_STATE" \
    PORT_BUSY="$PORT_BUSY" \
    READINESS_PORT="$READINESS_PORT" \
    SS_FAIL="$SS_FAIL" \
    LOCK_BUSY="$LOCK_BUSY" \
    REAL_MKDIR_BIN="$TEST_MKDIR_BIN" \
    SYSTEMD_RUN_FAIL="$SYSTEMD_RUN_FAIL" \
    EXPECTED_LAUNCH_PROFILE="$EXPECTED_LAUNCH_PROFILE" \
    EXPECTED_MODEL_PATH="$EXPECTED_MODEL_PATH" \
    FAKE_SHA="$FAKE_SHA" \
    "$TEST_BASH_BIN" "$SERVICE_SCRIPT" "$@" 2>&1
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

test_hermetic_command_resolution() {
  local name resolved expected rejected_status legacy_lock_name
  legacy_lock_name='LOCK_''FILE'
  reset_fixture
  for name in sudo systemctl systemd-run ss journalctl sha256sum sleep flock mkdir; do
    resolved="$(PATH="$FAKE_BIN" "$TEST_BASH_BIN" -c 'command -v "$1"' -- "$name")"
    expected="$FAKE_BIN/$name"
    if [[ "$resolved" == "$expected" ]]; then
      pass "literal $name resolves to fixture fake"
    else
      fail "literal $name resolved outside fixture: $resolved"
    fi
  done
  if ! grep -Eq '/(usr/)?(local/)?(s?bin)/(sudo|systemctl|systemd-run|ss|journalctl|sha256sum|sleep|flock|mkdir)([\"[:space:]]|$)' "$SERVICE_SCRIPT"; then
    pass "production helper contains no absolute operational command path"
  else
    fail "production helper contains an absolute operational command path"
  fi
  if ! grep -Eq "$legacy_lock_name|exec[[:space:]]+9(>|>>|<>)" "$SERVICE_SCRIPT"; then
    pass "production helper has no output lock FD or legacy lock-file variable"
  else
    fail "production helper retains an unsafe output lock FD or legacy lock-file variable"
  fi
  set +e
  PATH="$FAKE_BIN" \
    CALL_LOG="$CALL_LOG" \
    FAKE_SYSTEMCTL="$FAKE_SYSTEMCTL" \
    FAKE_SYSTEMD_RUN="$FAKE_SYSTEMD_RUN" \
    "$FAKE_BIN/sudo" /bin/true >/dev/null 2>&1
  rejected_status=$?
  set -e
  if ((rejected_status == 98)); then
    pass "fake sudo rejects every non-allowlisted target"
  else
    fail "fake sudo allowlist returned unexpected status $rejected_status"
  fi
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
  rm "$CSERIALPORT_LIBRARY"
  run_service start h15
  assert_status 1 "missing libcserialport fails preflight"
  assert_contains "libcserialport" "missing libcserialport prints actionable output"
  assert_log_absent '^sudo:' "missing libcserialport never invokes sudo"

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

  reset_fixture
  printf '%s\n' '{"name":"thunder_h15",' >"$PROFILE_DIR/thunder_h15.json"
  run_service start h15
  assert_status 1 "malformed profile JSON fails preflight"
  assert_file_absent "$RUN_MARKER" "malformed profile JSON prevents systemd-run"

  reset_fixture
  cat >"$PROFILE_DIR/thunder_h15.json" <<'EOF'
{"name":"thunder_h15","name":"wrong","modelPath":"model/thunder_h15_model10400.onnx","_onnxSha256":"ded34be402b25a3a77a9feba196a3d76efa2b5660d7d9c8396b28963a0efbde4"}
EOF
  run_service start h15
  assert_status 1 "duplicate profile key fails preflight"
  assert_file_absent "$RUN_MARKER" "duplicate profile key prevents systemd-run"

  reset_fixture
  cat >"$PROFILE_DIR/thunder_h15.json" <<'EOF'
{"name":"wrong","modelPath":"model/wrong.onnx","_onnxSha256":"bad","spoof":"\"name\":\"thunder_h15\",\"modelPath\":\"model/thunder_h15_model10400.onnx\",\"_onnxSha256\":\"ded34be402b25a3a77a9feba196a3d76efa2b5660d7d9c8396b28963a0efbde4\""}
EOF
  run_service start h15
  assert_status 1 "unrelated-field profile spoof fails preflight"
  assert_file_absent "$RUN_MARKER" "unrelated-field spoof prevents systemd-run"

  reset_fixture
  PYTHON_BIN="$CASE_DIR/missing-python3"
  run_service start h15
  assert_status 1 "missing JSON parser fails preflight"
  assert_contains "Python" "missing JSON parser prints actionable output"
  assert_file_absent "$RUN_MARKER" "missing JSON parser prevents systemd-run"
}

test_successful_start_command() {
  reset_fixture
  run_service start h15
  assert_status 0 "valid h15 start succeeds with fakes"
  assert_contains "候选服务已启动" "successful start reports readiness"
  assert_log_line "systemd-run:argv-ok:thunder_h15" "launch argv exactly matches ordered H15 contract"
  if ! grep -Fq 'systemctl:stop han_dog.service' "$CALL_LOG"; then
    pass "successful candidate start never stops production"
  else
    fail "successful candidate start stopped production"
  fi
}

test_h18_launch_command() {
  reset_fixture
  EXPECTED_LAUNCH_PROFILE=thunder_h18
  EXPECTED_MODEL_PATH="$BRAINSTEM_ROOT/model/thunder_h18_model5000.onnx"
  FAKE_SHA=d632413aa9ddf16b6c795377bdbbef69c454ba1cc77f8acb7d560f381cd84296
  run_service start h18
  assert_status 0 "valid h18 start succeeds with fakes"
  assert_log_line "systemd-run:argv-ok:thunder_h18" "launch argv exactly matches ordered H18 contract"
}

test_readiness_timeout_is_explicitly_unsafe() {
  reset_fixture
  READINESS_PORT=0
  run_service start h15
  assert_status 1 "active candidate without listening port times out"
  assert_file_present "$CANDIDATE_MARKER" "readiness timeout leaves candidate marker active"
  assert_contains "READINESS NOT CONFIRMED" "timeout says readiness was not confirmed"
  assert_contains "MAY STILL BE ACTIVE" "timeout warns candidate may still be active"
  assert_contains "DO NOT restore-master" "timeout forbids immediate master restore"
  assert_contains "disable motors and support robot" "timeout gives physical safety prerequisite"
  assert_contains "$SERVICE_SCRIPT stop" "timeout gives exact stop command"
  assert_contains "$SERVICE_SCRIPT status" "timeout gives exact status command"
  assert_contains "candidate state: active" "timeout reports observed candidate state"
  assert_contains "port state: free" "timeout reports observed port state"
}

test_identity_and_format_validation() {
  local command
  for command in start stop restore-master; do
    reset_fixture
    CANDIDATE_UNIT="$PRODUCTION_UNIT"
    if [[ "$command" == start ]]; then run_service start h15; else run_service "$command"; fi
    assert_status 1 "$command rejects identical production and candidate units"
    assert_no_lifecycle_calls "$command identity failure invokes no lifecycle command"
  done

  reset_fixture
  GRPC_PORT=70000
  run_service start h15
  assert_status 1 "start rejects out-of-range gRPC port"
  assert_no_lifecycle_calls "invalid port prevents lifecycle commands"

  reset_fixture
  START_TIMEOUT_SECONDS=09x
  run_service start h15
  assert_status 1 "start rejects malformed readiness timeout"
  assert_no_lifecycle_calls "invalid readiness timeout prevents lifecycle commands"

  reset_fixture
  STOP_TIMEOUT_SECONDS='10 seconds;restart'
  run_service stop
  assert_status 1 "stop rejects unsafe systemd duration"
  assert_no_lifecycle_calls "invalid stop timeout prevents lifecycle commands"
}

test_busy_lock_blocks_mutations() {
  local command
  for command in start stop restore-master; do
    reset_fixture
    LOCK_BUSY=1
    if [[ "$command" == start ]]; then run_service start h15; else run_service "$command"; fi
    assert_status 1 "busy host lock blocks $command"
    assert_log_line "flock:-n 9" "busy $command attempts nonblocking host lock"
    assert_no_lifecycle_calls "busy lock prevents $command lifecycle calls"
  done
}

test_safe_lock_directory_validation() {
  local target_contents
  reset_fixture
  printf '%s\n' 'do-not-modify' >"$CASE_DIR/lock-target"
  ln -s "$CASE_DIR/lock-target" "$LOCK_DIR"
  run_service stop
  assert_status 1 "symlink lock directory fails closed"
  target_contents="$(<"$CASE_DIR/lock-target")"
  if [[ "$target_contents" == do-not-modify ]]; then
    pass "symlink target is not truncated or modified"
  else
    fail "symlink target was modified: $target_contents"
  fi
  assert_log_absent '^(mkdir|flock|sudo|systemctl):' "symlink lock path invokes no lock or lifecycle command"

  reset_fixture
  LOCK_DIR="$CASE_DIR/wrong-name.lock.d"
  run_service restore-master
  assert_status 1 "wrong lock directory basename fails closed"
  assert_file_absent "$LOCK_DIR" "wrong lock directory is never created"
  assert_log_absent '^(mkdir|flock|sudo|systemctl):' "wrong lock basename invokes no lock or lifecycle command"

  reset_fixture
  run_service stop
  assert_status 0 "safe absent lock directory is created for mutation"
  if [[ -d "$LOCK_DIR" && ! -L "$LOCK_DIR" ]]; then
    pass "created lock path is a real directory"
  else
    fail "safe lock directory was not created correctly"
  fi
  assert_log_line "mkdir:-m 700 -- $LOCK_DIR" "lock directory creation uses restrictive exact argv"
}

test_ss_failure_fails_closed() {
  reset_fixture
  SS_FAIL=1
  run_service start h15
  assert_status 1 "ss failure blocks start"
  assert_file_absent "$RUN_MARKER" "ss failure prevents systemd-run"
  assert_log_absent '^(sudo|systemd-run):' "ss failure never reaches sudo/systemd-run"
}

test_stop_and_restore_exact_targets() {
  reset_fixture
  run_service stop
  assert_status 0 "stop succeeds with strict fakes"
  assert_log_line "systemctl:stop $CANDIDATE_UNIT" "stop targets exact candidate unit"
  assert_log_absent "systemctl:stop $PRODUCTION_UNIT" "stop never targets production"

  reset_fixture
  run_service restore-master
  assert_status 0 "restore succeeds with strict fakes"
  assert_log_line "systemctl:start $PRODUCTION_UNIT" "restore targets exact production unit"
  assert_log_absent "systemctl:start $CANDIDATE_UNIT" "restore never starts candidate"
}

test_state_handling() {
  reset_fixture
  PRODUCTION_STATE=failed
  CANDIDATE_STATE=failed
  run_service start h15
  assert_status 0 "failed inactive units permit a verified start"

  reset_fixture
  PRODUCTION_STATE=deactivating
  run_service start h15
  assert_status 1 "deactivating production blocks start"
  assert_file_absent "$RUN_MARKER" "deactivating production prevents launch"

  reset_fixture
  PRODUCTION_STATE=absent
  run_service start h15
  assert_status 1 "absent production unit fails closed"
  assert_file_absent "$RUN_MARKER" "absent production prevents launch"

  reset_fixture
  CANDIDATE_STATE=unknown
  run_service restore-master
  assert_status 1 "unknown candidate state blocks restore"
  assert_log_absent '^sudo:' "unknown candidate never invokes sudo"

  reset_fixture
  PRODUCTION_STATE=absent
  run_service restore-master
  assert_status 1 "absent production unit blocks restore"
  assert_log_absent '^sudo:' "absent production never invokes sudo"

  reset_fixture
  CANDIDATE_STATE=deactivating
  run_service restore-master
  assert_status 1 "deactivating candidate blocks restore"
  assert_log_absent '^sudo:' "deactivating candidate never invokes sudo"

  reset_fixture
  PRODUCTION_STATE=absent
  CANDIDATE_STATE=unknown
  run_service status
  assert_status 0 "status reports absent and unknown without failing"
  assert_contains "absent" "status reports absent production"
  assert_contains "unknown" "status reports unknown candidate"
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
test_hermetic_command_resolution
test_start_requires_profile
test_unknown_profile
test_invalid_logs_option
test_start_refuses_production
test_restore_refuses_candidate
test_preflight_failures_do_not_launch
test_successful_start_command
test_h18_launch_command
test_readiness_timeout_is_explicitly_unsafe
test_identity_and_format_validation
test_busy_lock_blocks_mutations
test_safe_lock_directory_validation
test_ss_failure_fails_closed
test_stop_and_restore_exact_targets
test_state_handling
test_launch_failure_prints_hints

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
((FAIL == 0))
