#!/usr/bin/env bash
set -Eeuo pipefail

# Robot paths and service identity. Every value can be overridden for testing.
BRAINSTEM_ROOT="${BRAINSTEM_ROOT:-/home/bsrl1/brainstem-bodyheightctrl}"
DART_BIN="${DART_BIN:-/home/bsrl1/flutter/bin/dart}"
PYTHON_BIN="${PYTHON_BIN:-python3}"
SERVICE_USER="${SERVICE_USER:-bsrl1}"
SERVICE_GROUP="${SERVICE_GROUP:-bsrl1}"
PRODUCTION_UNIT="${PRODUCTION_UNIT:-han_dog.service}"
CANDIDATE_UNIT="${CANDIDATE_UNIT:-han-dog-bodyheight.service}"
GRPC_PORT="${GRPC_PORT:-13145}"
IMU_PORT="${IMU_PORT:-/dev/imu}"
YUNZHUO_PORT="${YUNZHUO_PORT:-/dev/yunzhuo}"
PROFILE_DIR="${PROFILE_DIR:-$BRAINSTEM_ROOT/han_dog/profiles}"
LD_LIBRARY_PATH="${LD_LIBRARY_PATH:-/opt/onnxruntime/lib:/usr/local/lib:/usr/lib/aarch64-linux-gnu:/lib/aarch64-linux-gnu}"
CSERIALPORT_LIBRARY="${CSERIALPORT_LIBRARY:-/lib/aarch64-linux-gnu/libcserialport.so}"
START_TIMEOUT_SECONDS="${START_TIMEOUT_SECONDS:-45}"
STOP_TIMEOUT_SECONDS="${STOP_TIMEOUT_SECONDS:-10s}"

# Operational commands are injectable so tests never reach the host system.
SYSTEMCTL_BIN="${SYSTEMCTL_BIN:-systemctl}"
SYSTEMD_RUN_BIN="${SYSTEMD_RUN_BIN:-systemd-run}"
SUDO_BIN="${SUDO_BIN:-sudo}"
SS_BIN="${SS_BIN:-ss}"
JOURNALCTL_BIN="${JOURNALCTL_BIN:-journalctl}"
SHA256SUM_BIN="${SHA256SUM_BIN:-sha256sum}"
SLEEP_BIN="${SLEEP_BIN:-sleep}"
FLOCK_BIN="${FLOCK_BIN:-flock}"
MKDIR_BIN="${MKDIR_BIN:-mkdir}"
LOCK_DIR="${LOCK_DIR:-/tmp/han-dog-bodyheight.lock.d}"

readonly H15_PROFILE="thunder_h15"
readonly H15_MODEL="thunder_h15_model10400.onnx"
readonly H15_SHA256="ded34be402b25a3a77a9feba196a3d76efa2b5660d7d9c8396b28963a0efbde4"
readonly H18_PROFILE="thunder_h18"
readonly H18_MODEL="thunder_h18_model5000.onnx"
readonly H18_SHA256="d632413aa9ddf16b6c795377bdbbef69c454ba1cc77f8acb7d560f381cd84296"

usage() {
  cat <<EOF
用法: $(basename "$0") COMMAND [ARGS]

安全管理 Thunder body-height 候选服务：
  help, --help       显示帮助
  status             查看生产/候选服务和端口状态（只读）
  start h15|h18      预检后启动候选服务；不会停止生产服务，也不会启用电机
  logs [--follow]    查看候选服务最近 100 行日志，可持续跟踪
  stop               仅停止候选服务
  restore-master     在候选服务完全停止且端口空闲后启动生产服务

重要安全说明：
  start 只会打开服务所需硬件，不会启用电机或发送运动 RPC。
  停机安全：stop 前必须先通过既有流程禁用电机并可靠支撑机器人；本脚本不会代办。
EOF
}

usage_error() {
  printf '参数错误：%s\n\n' "$1" >&2
  usage >&2
  return 2
}

unit_state() {
  local unit="$1"
  local state
  state="$("$SYSTEMCTL_BIN" is-active "$unit" 2>/dev/null || true)"
  printf '%s' "${state:-unknown}"
}

port_is_listening() {
  local output
  if ! output="$("$SS_BIN" -ltnH "sport = :$GRPC_PORT" 2>/dev/null)"; then
    return 2
  fi
  [[ -n "$output" ]]
}

candidate_is_blocking_start() {
  local state="$1"
  [[ "$state" == active || "$state" == activating || "$state" == deactivating ]]
}

candidate_is_blocking_restore() {
  local state="$1"
  [[ "$state" == active || "$state" == activating || "$state" == deactivating ]]
}

validate_mutation_config() {
  local unit
  for unit in "$PRODUCTION_UNIT" "$CANDIDATE_UNIT"; do
    if [[ -z "$unit" || ! "$unit" =~ ^[A-Za-z0-9_.@:-]+[.]service$ ]]; then
      printf '配置错误：unit 名称必须为安全的非空 .service 名称：%s\n' "$unit" >&2
      return 1
    fi
  done
  if [[ "$PRODUCTION_UNIT" == "$CANDIDATE_UNIT" ]]; then
    printf '配置错误：PRODUCTION_UNIT 与 CANDIDATE_UNIT 不得相同。\n' >&2
    return 1
  fi
  if [[ ! "$GRPC_PORT" =~ ^[1-9][0-9]{0,4}$ ]] ||
    ((10#$GRPC_PORT < 1 || 10#$GRPC_PORT > 65535)); then
    printf '配置错误：GRPC_PORT 必须是 1..65535 的十进制整数：%s\n' "$GRPC_PORT" >&2
    return 1
  fi
  if [[ ! "$START_TIMEOUT_SECONDS" =~ ^[1-9][0-9]{0,2}$ ]] ||
    ((10#$START_TIMEOUT_SECONDS < 1 || 10#$START_TIMEOUT_SECONDS > 300)); then
    printf '配置错误：START_TIMEOUT_SECONDS 必须是 1..300 的十进制整数：%s\n' \
      "$START_TIMEOUT_SECONDS" >&2
    return 1
  fi
  if [[ ! "$STOP_TIMEOUT_SECONDS" =~ ^[1-9][0-9]{0,2}s$ ]]; then
    printf '配置错误：STOP_TIMEOUT_SECONDS 必须使用 1s..999s 格式：%s\n' \
      "$STOP_TIMEOUT_SECONDS" >&2
    return 1
  fi
}

acquire_mutation_lock() {
  local old_umask mkdir_status=0
  if [[ -z "$LOCK_DIR" || "$LOCK_DIR" != /* || "$LOCK_DIR" == *$'\n'* ||
        "${LOCK_DIR##*/}" != han-dog-bodyheight.lock.d ]]; then
    printf '配置错误：LOCK_DIR 必须是无换行的绝对路径，且 basename 必须为 han-dog-bodyheight.lock.d。\n' >&2
    return 1
  fi
  if ! command -v "$FLOCK_BIN" >/dev/null 2>&1; then
    printf '安全锁不可用：找不到 flock：%s\n' "$FLOCK_BIN" >&2
    return 1
  fi
  if ! command -v "$MKDIR_BIN" >/dev/null 2>&1; then
    printf '安全锁不可用：找不到 mkdir：%s\n' "$MKDIR_BIN" >&2
    return 1
  fi
  if [[ -L "$LOCK_DIR" ]]; then
    printf '安全锁不可用：LOCK_DIR 不得是符号链接：%s\n' "$LOCK_DIR" >&2
    return 1
  fi
  if [[ ! -e "$LOCK_DIR" ]]; then
    old_umask="$(umask)"
    umask 077
    "$MKDIR_BIN" -m 700 -- "$LOCK_DIR" || mkdir_status=$?
    umask "$old_umask"
    if ((mkdir_status != 0)) &&
      [[ ! -d "$LOCK_DIR" || -L "$LOCK_DIR" || ! -O "$LOCK_DIR" ]]; then
      printf '安全锁不可用：无法安全创建锁目录：%s\n' "$LOCK_DIR" >&2
      return 1
    fi
  fi
  if [[ ! -d "$LOCK_DIR" || -L "$LOCK_DIR" || ! -O "$LOCK_DIR" ]]; then
    printf '安全锁不可用：LOCK_DIR 必须是真实且由当前用户所有的目录：%s\n' \
      "$LOCK_DIR" >&2
    return 1
  fi
  if ! exec 9<"$LOCK_DIR"; then
    printf '安全锁不可用：无法只读打开锁目录：%s\n' "$LOCK_DIR" >&2
    return 1
  fi
  if ! "$FLOCK_BIN" -n 9; then
    printf '拒绝操作：另一个 body-height 生命周期操作正在进行（锁：%s）。\n' \
      "$LOCK_DIR" >&2
    return 1
  fi
}

run_mutation() {
  acquire_mutation_lock || return 1
  validate_mutation_config || return 1
  "$@"
}

show_status() {
  local production_state candidate_state port_result
  production_state="$(unit_state "$PRODUCTION_UNIT")"
  candidate_state="$(unit_state "$CANDIDATE_UNIT")"

  printf '生产服务 %s: %s\n' "$PRODUCTION_UNIT" "$production_state"
  printf '候选服务 %s: %s\n' "$CANDIDATE_UNIT" "$candidate_state"

  if port_is_listening; then
    printf '端口 %s: listening（已占用）\n' "$GRPC_PORT"
  else
    port_result=$?
    if ((port_result == 2)); then
      printf '端口 %s: unknown（ss 检查失败）\n' "$GRPC_PORT"
    else
      printf '端口 %s: free\n' "$GRPC_PORT"
    fi
  fi

  if [[ "$candidate_state" == active ]]; then
    "$SYSTEMCTL_BIN" show "$CANDIDATE_UNIT" \
      --property=MainPID \
      --property=ActiveState \
      --property=SubState \
      --no-pager || true
  fi
}

select_profile() {
  case "$1" in
    h15)
      PROFILE_NAME="$H15_PROFILE"
      MODEL_NAME="$H15_MODEL"
      EXPECTED_SHA256="$H15_SHA256"
      ;;
    h18)
      PROFILE_NAME="$H18_PROFILE"
      MODEL_NAME="$H18_MODEL"
      EXPECTED_SHA256="$H18_SHA256"
      ;;
    *)
      return 2
      ;;
  esac
}

preflight_files() {
  local profile_file="$PROFILE_DIR/$PROFILE_NAME.json"
  local model_file="$BRAINSTEM_ROOT/model/$MODEL_NAME"
  local hash_output actual_sha256

  [[ -d "$BRAINSTEM_ROOT" ]] || {
    printf '预检失败：仓库目录不存在：%s\n' "$BRAINSTEM_ROOT" >&2
    return 1
  }
  [[ -x "$DART_BIN" ]] || {
    printf '预检失败：Dart 不存在或不可执行：%s\n' "$DART_BIN" >&2
    return 1
  }
  [[ "$CSERIALPORT_LIBRARY" == /* && "$CSERIALPORT_LIBRARY" != *$'\n'* &&
      -f "$CSERIALPORT_LIBRARY" && -r "$CSERIALPORT_LIBRARY" ]] || {
    printf '预检失败：libcserialport 必须是无换行、可读的绝对路径普通文件：%s\n' \
      "$CSERIALPORT_LIBRARY" >&2
    return 1
  }
  [[ -f "$BRAINSTEM_ROOT/han_dog/bin/han_dog.dart" ]] || {
    printf '预检失败：服务入口不存在：%s\n' "$BRAINSTEM_ROOT/han_dog/bin/han_dog.dart" >&2
    return 1
  }
  [[ -f "$profile_file" ]] || {
    printf '预检失败：profile 不存在：%s\n' "$profile_file" >&2
    return 1
  }
  [[ -f "$model_file" ]] || {
    printf '预检失败：模型不存在：%s\n' "$model_file" >&2
    return 1
  }
  [[ -e "$IMU_PORT" ]] || {
    printf '预检失败：IMU 设备不存在：%s\n' "$IMU_PORT" >&2
    return 1
  }
  [[ -e "$YUNZHUO_PORT" ]] || {
    printf '预检失败：Yunzhuo 设备不存在：%s\n' "$YUNZHUO_PORT" >&2
    return 1
  }

  if ! command -v "$PYTHON_BIN" >/dev/null 2>&1; then
    printf '预检失败：找不到 Python JSON 解析器：%s\n' "$PYTHON_BIN" >&2
    printf '请安装 Python 3，或通过 PYTHON_BIN 指定可执行文件。\n' >&2
    return 1
  fi
  if ! "$PYTHON_BIN" - "$profile_file" "$PROFILE_NAME" \
    "model/$MODEL_NAME" "$EXPECTED_SHA256" <<'PY'
import json
import sys


class DuplicateKeyError(ValueError):
    pass


def reject_duplicate_keys(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise DuplicateKeyError(f"duplicate key: {key}")
        result[key] = value
    return result


profile_path, expected_name, expected_model, expected_sha256 = sys.argv[1:]
expected = {
    "name": expected_name,
    "modelPath": expected_model,
    "_onnxSha256": expected_sha256,
}

try:
    with open(profile_path, "r", encoding="utf-8") as profile_file:
        profile = json.load(profile_file, object_pairs_hook=reject_duplicate_keys)
    if not isinstance(profile, dict):
        raise ValueError("top-level JSON value must be an object")
    for key, expected_value in expected.items():
        actual_value = profile.get(key)
        if actual_value != expected_value:
            raise ValueError(
                f"top-level {key} mismatch: expected {expected_value!r}, "
                f"got {actual_value!r}"
            )
except (OSError, UnicodeError, ValueError) as error:
    print(f"profile JSON validation failed: {error}", file=sys.stderr)
    raise SystemExit(1)
PY
  then
    printf '预检失败：profile JSON 结构或顶层策略字段无效：%s\n' "$profile_file" >&2
    return 1
  fi

  if ! hash_output="$("$SHA256SUM_BIN" "$model_file")"; then
    printf '预检失败：无法计算模型 SHA-256：%s\n' "$model_file" >&2
    return 1
  fi
  actual_sha256="${hash_output%%[[:space:]]*}"
  if [[ "${actual_sha256,,}" != "$EXPECTED_SHA256" ]]; then
    printf '预检失败：模型 SHA-256 不匹配。\n期望：%s\n实际：%s\n' \
      "$EXPECTED_SHA256" "$actual_sha256" >&2
    return 1
  fi
}

preflight_runtime() {
  local production_state candidate_state port_result
  production_state="$(unit_state "$PRODUCTION_UNIT")"
  if [[ "$production_state" != inactive && "$production_state" != failed ]]; then
    printf '拒绝启动：生产服务状态为 %s，必须先由操作员明确停止。\n' "$production_state" >&2
    printf '确认机器人安全后执行：sudo systemctl stop %s\n' "$PRODUCTION_UNIT" >&2
    return 1
  fi

  candidate_state="$(unit_state "$CANDIDATE_UNIT")"
  if candidate_is_blocking_start "$candidate_state"; then
    printf '拒绝启动：候选服务状态为 %s。\n' "$candidate_state" >&2
    printf '确认安全后执行：sudo systemctl stop %s\n' "$CANDIDATE_UNIT" >&2
    return 1
  fi
  if [[ "$candidate_state" != inactive && "$candidate_state" != failed ]]; then
    printf '拒绝启动：无法确认候选服务安全停止（状态：%s）。\n' "$candidate_state" >&2
    return 1
  fi

  if port_is_listening; then
    printf '拒绝启动：端口 %s 已被占用。\n' "$GRPC_PORT" >&2
    printf "排查命令：sudo ss -ltnp 'sport = :%s'\n" "$GRPC_PORT" >&2
    return 1
  else
    port_result=$?
    if ((port_result == 2)); then
      printf '拒绝启动：无法用 ss 确认端口 %s 空闲。\n' "$GRPC_PORT" >&2
      return 1
    fi
  fi
}

wait_until_ready() {
  local attempt state port_result
  for ((attempt = 0; attempt < START_TIMEOUT_SECONDS; attempt++)); do
    state="$(unit_state "$CANDIDATE_UNIT")"
    if [[ "$state" == active ]]; then
      if port_is_listening; then
        return 0
      else
        port_result=$?
        ((port_result == 2)) && break
      fi
    fi
    "$SLEEP_BIN" 1
  done
  return 1
}

observed_port_state() {
  local result
  if port_is_listening; then
    printf 'listening'
  else
    result=$?
    if ((result == 2)); then printf 'unknown'; else printf 'free'; fi
  fi
}

start_candidate() {
  local requested_profile="$1"
  select_profile "$requested_profile" || return 2
  preflight_runtime || return 1
  preflight_files || return 1

  printf '预检通过，启动候选服务 %s（不会启用电机）...\n' "$PROFILE_NAME"
  if ! "$SUDO_BIN" "$SYSTEMD_RUN_BIN" \
    "--collect" \
    "--unit=$CANDIDATE_UNIT" \
    "--property=User=$SERVICE_USER" \
    "--property=Group=$SERVICE_GROUP" \
    "--property=WorkingDirectory=$BRAINSTEM_ROOT" \
    "--property=Type=simple" \
    "--property=KillSignal=SIGINT" \
    "--property=TimeoutStopSec=$STOP_TIMEOUT_SECONDS" \
    "--property=Restart=no" \
    "--setenv=HAN_DOG_DEFAULT_PROFILE=$PROFILE_NAME" \
    "--setenv=HAN_DOG_PROFILE_DIR=$PROFILE_DIR" \
    "--setenv=HAN_DOG_IMU_PORT=$IMU_PORT" \
    "--setenv=HAN_DOG_YUNZHUO_PORT=$YUNZHUO_PORT" \
    "--setenv=HAN_DOG_PORT=$GRPC_PORT" \
    "--setenv=LD_LIBRARY_PATH=$LD_LIBRARY_PATH" \
    "--setenv=LD_PRELOAD=$CSERIALPORT_LIBRARY" \
    "$DART_BIN" run han_dog/bin/han_dog.dart; then
    printf '启动失败：systemd-run 未能创建候选服务。\n' >&2
    printf '检查：%s status\n' "$0" >&2
    printf '日志：%s logs\n' "$0" >&2
    return 1
  fi

  if wait_until_ready; then
    printf '候选服务已启动：%s，端口 %s 正在监听。\n' "$CANDIDATE_UNIT" "$GRPC_PORT"
    printf '提示：服务启动不代表电机已启用，本脚本不会发送运动命令。\n'
    return 0
  fi

  local observed_candidate observed_port
  observed_candidate="$(unit_state "$CANDIDATE_UNIT")"
  observed_port="$(observed_port_state)"
  printf 'READINESS NOT CONFIRMED: candidate MAY STILL BE ACTIVE and may hold IMU/PCAN/port.\n' >&2
  printf 'DO NOT restore-master until the candidate is safely stopped and status is verified.\n' >&2
  printf 'Observed candidate state: %s\n' "$observed_candidate" >&2
  printf 'Observed port state: %s\n' "$observed_port" >&2
  printf 'Safe sequence:\n' >&2
  printf '  1. disable motors and support robot\n' >&2
  printf '  2. %s stop\n' "$0" >&2
  printf '  3. %s status\n' "$0" >&2
  return 1
}

show_logs() {
  if (($# == 0)); then
    "$JOURNALCTL_BIN" -u "$CANDIDATE_UNIT" -n 100 --no-pager
  elif (($# == 1)) && [[ "$1" == --follow ]]; then
    "$JOURNALCTL_BIN" -u "$CANDIDATE_UNIT" -n 100 --follow
  else
    usage_error "logs 仅接受可选参数 --follow"
  fi
}

stop_candidate() {
  printf '警告：仅在电机已禁用且机器人已可靠支撑后停止服务。\n' >&2
  printf '本操作只停止候选服务 %s，绝不会停止生产服务 %s。\n' \
    "$CANDIDATE_UNIT" "$PRODUCTION_UNIT"
  "$SUDO_BIN" "$SYSTEMCTL_BIN" stop "$CANDIDATE_UNIT"
  printf '候选服务停止命令已完成。\n'
}

restore_master() {
  local candidate_state production_state port_result
  candidate_state="$(unit_state "$CANDIDATE_UNIT")"
  if candidate_is_blocking_restore "$candidate_state"; then
    printf '拒绝恢复：候选服务状态为 %s，必须先安全停止。\n' "$candidate_state" >&2
    printf '确认电机已禁用且机器人已支撑后执行：sudo systemctl stop %s\n' \
      "$CANDIDATE_UNIT" >&2
    return 1
  fi
  if [[ "$candidate_state" != inactive && "$candidate_state" != failed ]]; then
    printf '拒绝恢复：无法确认候选服务已停止（状态：%s）。\n' "$candidate_state" >&2
    return 1
  fi

  production_state="$(unit_state "$PRODUCTION_UNIT")"
  if [[ "$production_state" != inactive && "$production_state" != failed ]]; then
    printf '拒绝恢复：生产服务状态不适合启动（状态：%s）。\n' "$production_state" >&2
    return 1
  fi

  if port_is_listening; then
    printf '拒绝恢复：端口 %s 仍被占用，请先查明占用进程。\n' "$GRPC_PORT" >&2
    printf "排查命令：sudo ss -ltnp 'sport = :%s'\n" "$GRPC_PORT" >&2
    return 1
  else
    port_result=$?
    if ((port_result == 2)); then
      printf '拒绝恢复：无法确认端口 %s 空闲。\n' "$GRPC_PORT" >&2
      return 1
    fi
  fi

  "$SUDO_BIN" "$SYSTEMCTL_BIN" start "$PRODUCTION_UNIT"
  printf '生产服务启动命令已完成：%s\n' "$PRODUCTION_UNIT"
}

main() {
  local command="${1:-help}"
  (($# > 0)) && shift

  case "$command" in
    help|--help|-h)
      (($# == 0)) || usage_error "help 不接受额外参数"
      usage
      ;;
    status)
      (($# == 0)) || usage_error "status 不接受额外参数"
      show_status
      ;;
    start)
      (($# == 1)) || {
        usage_error "start 需要且仅需要 h15 或 h18"
        return
      }
      if ! select_profile "$1"; then
        usage_error "未知 profile：$1（仅支持 h15 或 h18）"
        return
      fi
      run_mutation start_candidate "$1"
      ;;
    logs)
      show_logs "$@"
      ;;
    stop)
      (($# == 0)) || usage_error "stop 不接受额外参数"
      run_mutation stop_candidate
      ;;
    restore-master)
      (($# == 0)) || usage_error "restore-master 不接受额外参数"
      run_mutation restore_master
      ;;
    *)
      usage_error "未知命令：$command"
      ;;
  esac
}

main "$@"
