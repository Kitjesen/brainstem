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
START_TIMEOUT_SECONDS="${START_TIMEOUT_SECONDS:-10}"
STOP_TIMEOUT_SECONDS="${STOP_TIMEOUT_SECONDS:-10s}"

# Operational commands are injectable so tests never reach the host system.
SYSTEMCTL_BIN="${SYSTEMCTL_BIN:-systemctl}"
SYSTEMD_RUN_BIN="${SYSTEMD_RUN_BIN:-systemd-run}"
SUDO_BIN="${SUDO_BIN:-sudo}"
SS_BIN="${SS_BIN:-ss}"
JOURNALCTL_BIN="${JOURNALCTL_BIN:-journalctl}"
SHA256SUM_BIN="${SHA256SUM_BIN:-sha256sum}"
SLEEP_BIN="${SLEEP_BIN:-sleep}"

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
  local state
  state="$(unit_state "$CANDIDATE_UNIT")"
  [[ "$state" == active || "$state" == activating || "$state" == deactivating ]]
}

candidate_is_blocking_restore() {
  local state
  state="$(unit_state "$CANDIDATE_UNIT")"
  [[ "$state" == active || "$state" == activating || "$state" == deactivating ]]
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
  if candidate_is_blocking_start; then
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

  printf '启动失败：候选服务未在 %s 秒内进入 active 且监听端口 %s。\n' \
    "$START_TIMEOUT_SECONDS" "$GRPC_PORT" >&2
  printf '检查：%s status\n' "$0" >&2
  printf '日志：%s logs\n' "$0" >&2
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
  local candidate_state port_result
  candidate_state="$(unit_state "$CANDIDATE_UNIT")"
  if candidate_is_blocking_restore; then
    printf '拒绝恢复：候选服务状态为 %s，必须先安全停止。\n' "$candidate_state" >&2
    printf '确认电机已禁用且机器人已支撑后执行：sudo systemctl stop %s\n' \
      "$CANDIDATE_UNIT" >&2
    return 1
  fi
  if [[ "$candidate_state" != inactive && "$candidate_state" != failed ]]; then
    printf '拒绝恢复：无法确认候选服务已停止（状态：%s）。\n' "$candidate_state" >&2
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
      start_candidate "$1"
      ;;
    logs)
      show_logs "$@"
      ;;
    stop)
      (($# == 0)) || usage_error "stop 不接受额外参数"
      stop_candidate
      ;;
    restore-master)
      (($# == 0)) || usage_error "restore-master 不接受额外参数"
      restore_master
      ;;
    *)
      usage_error "未知命令：$command"
      ;;
  esac
}

main "$@"
