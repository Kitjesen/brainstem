#!/usr/bin/env bash
set -euo pipefail

PORT="${1:-13146}"
MONITOR="/home/bsrl1/brainstem/tools/trimui_udp_signal_monitor.py"
if [[ "${EUID}" -eq 0 ]]; then
  SYSTEMCTL=(systemctl)
else
  SYSTEMCTL=(sudo systemctl)
fi

echo "================================================================"
echo "TrimUI/App UDP signal monitor safe runner"
echo "MODE: MONITOR ONLY. App commands will NOT be forwarded to han_dog."
echo "Port: ${PORT}"
echo "================================================================"
echo
echo "Safety check:"
echo "  1. Put the robot in a safe supported state."
echo "  2. This runner stops trimui_udp_bridge.service first."
echo "  3. The monitor script only prints UDP packets and sends monitor-only ACK."
echo

WAS_ACTIVE=0
if "${SYSTEMCTL[@]}" is-active --quiet trimui_udp_bridge.service; then
  WAS_ACTIVE=1
  echo "[safe] stopping trimui_udp_bridge.service..."
  "${SYSTEMCTL[@]}" stop trimui_udp_bridge.service
else
  echo "[safe] trimui_udp_bridge.service is not active."
fi

restore_bridge() {
  echo
  echo "[safe] monitor stopped."
  if [[ "${WAS_ACTIVE}" == "1" ]]; then
    echo "[safe] restarting trimui_udp_bridge.service..."
    "${SYSTEMCTL[@]}" start trimui_udp_bridge.service
    "${SYSTEMCTL[@]}" --no-pager --plain status trimui_udp_bridge.service | sed -n '1,12p' || true
  else
    echo "[safe] bridge was not active before; leaving it stopped."
  fi
}
trap restore_bridge EXIT

echo "[safe] starting UDP monitor. Press Ctrl+C to stop."
echo
python3 "${MONITOR}" --port "${PORT}"
