#!/usr/bin/env python3
"""Monitor TrimUI/App UDP commands without forwarding them to the robot.

This script is intentionally passive with respect to robot control:
- It does not import or call gRPC.
- It does not talk to han_dog.
- It only binds the UDP port, prints received packets, and optionally sends
  monitor-only ACK packets so the App can display a connection state.

Typical safe use on the robot:
  sudo systemctl stop trimui_udp_bridge.service
  python3 /home/bsrl1/brainstem/tools/trimui_udp_signal_monitor.py --port 13146

Press buttons or move the joystick in the App, then watch this terminal.
Stop with Ctrl+C, then restart the real bridge when done:
  sudo systemctl start trimui_udp_bridge.service
"""

from __future__ import annotations

import argparse
import json
import socket
import sys
import time
from datetime import datetime
from typing import Any


def _now() -> str:
    return datetime.now().strftime("%H:%M:%S.%f")[:-3]


def _float(value: Any) -> float | None:
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _fmt_float(value: Any) -> str:
    parsed = _float(value)
    if parsed is None:
        return "None"
    return f"{parsed:+.4f}"


def _is_moving(msg: dict[str, Any]) -> bool:
    return any(abs(_float(msg.get(axis)) or 0.0) > 1e-4 for axis in ("x", "y", "z"))


def _can_forward_walk(fake_state: str) -> bool:
    return fake_state in {"standing", "walking"}


def _summarize(msg: Any, *, remote_enabled: bool, fake_state: str) -> str:
    if not isinstance(msg, dict):
        return f"non-json-object: {msg!r}"

    cmd = msg.get("cmd")
    if cmd == "walk":
        x = _fmt_float(msg.get("x"))
        y = _fmt_float(msg.get("y"))
        z = _fmt_float(msg.get("z"))
        state = "MOVING" if _is_moving(msg) else "ZERO"
        if not remote_enabled:
            gate = "WOULD_BLOCK:not_enabled"
        elif not _can_forward_walk(fake_state):
            gate = f"WOULD_BLOCK:state={fake_state}"
        else:
            gate = "WOULD_FORWARD"
        return f"cmd=walk x={x} y={y} z={z} [{state}] [{gate}]"

    if cmd in {"hello", "heartbeat", "enable", "disable", "standup", "sitdown", "safe_exit", "calibrate"}:
        return f"cmd={cmd}"

    return f"cmd={cmd!r} keys={sorted(msg.keys())}"


def _walk_tuple(msg: Any) -> tuple[float, float, float] | None:
    if not isinstance(msg, dict) or msg.get("cmd") != "walk":
        return None
    return tuple((_float(msg.get(axis)) or 0.0) for axis in ("x", "y", "z"))  # type: ignore[return-value]


def _ack_payload(
    msg: Any,
    packet_index: int,
    *,
    remote_enabled: bool,
    fake_state: str,
    reset_enabled: bool = False,
) -> bytes:
    cmd = msg.get("cmd") if isinstance(msg, dict) else None
    reason = None
    if cmd == "walk":
        if not remote_enabled:
            event = "walk_ignored"
            reason = "disabled"
        elif not _can_forward_walk(fake_state):
            event = "walk_blocked"
            reason = f"state={fake_state}"
        else:
            event = "walk"
    elif cmd in {
        "hello",
        "heartbeat",
        "enable",
        "disable",
        "standup",
        "sitdown",
        "calibrate",
    }:
        event = cmd
    elif cmd == "safe_exit":
        event = "safe_exit_done"
    else:
                event = "monitor_only"

    payload = {
        "cmd": "ack",
        "event": event,
        "receivedCmd": cmd,
        "enabled": remote_enabled,
        "failsafe": False,
        "resetEnabled": reset_enabled or not remote_enabled,
        "monitorOnly": True,
        "note": "UDP monitor only; command was NOT forwarded to han_dog.",
        "packetIndex": packet_index,
        "t": time.time(),
        "telemetry": {
            "state": fake_state,
            "updatedAt": time.time(),
        },
    }
    if reason is not None:
        payload["reason"] = reason
    return json.dumps(payload, ensure_ascii=False).encode("utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Log TrimUI/App UDP commands without moving the robot.",
    )
    parser.add_argument("--host", default="0.0.0.0", help="UDP bind host, default: 0.0.0.0")
    parser.add_argument("--port", type=int, default=13146, help="UDP bind port, default: 13146")
    parser.add_argument("--no-ack", action="store_true", help="Do not send monitor-only ACK packets")
    parser.add_argument("--raw", action="store_true", help="Print raw packet bytes/text")
    parser.add_argument("--show-heartbeat", action="store_true", help="Print hello/heartbeat packets")
    parser.add_argument(
        "--walk-delta",
        type=float,
        default=0.01,
        help="Only print walk packets when any axis changes by at least this value, default: 0.01",
    )
    args = parser.parse_args()

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind((args.host, args.port))

    print("=" * 72)
    print("TrimUI/App UDP signal monitor - MONITOR ONLY, NO ROBOT MOTION")
    print(f"Listening on {args.host}:{args.port}")
    print("This script does not connect to gRPC and does not forward commands.")
    print("Stop with Ctrl+C.")
    print("=" * 72)
    sys.stdout.flush()

    packet_index = 0
    last_printed_walk: tuple[float, float, float] | None = None
    remote_enabled = False
    fake_state = "grounded"
    try:
        while True:
            data, addr = sock.recvfrom(65535)
            packet_index += 1
            text = data.decode("utf-8", errors="replace").strip()
            try:
                msg: Any = json.loads(text)
            except json.JSONDecodeError as exc:
                msg = None
                summary = f"invalid-json error={exc}"
            else:
                summary = _summarize(
                    msg,
                    remote_enabled=remote_enabled,
                    fake_state=fake_state,
                )

            should_print = True
            if isinstance(msg, dict):
                cmd = msg.get("cmd")
                if cmd == "enable":
                    remote_enabled = True
                    fake_state = "grounded"
                elif cmd == "disable":
                    remote_enabled = False
                    fake_state = "grounded"
                elif cmd == "safe_exit":
                    remote_enabled = False
                    fake_state = "grounded"
                elif cmd == "standup" and remote_enabled:
                    fake_state = "standing"
                elif cmd == "sitdown" and remote_enabled:
                    fake_state = "grounded"
                elif (
                    cmd == "walk"
                    and remote_enabled
                    and _can_forward_walk(fake_state)
                ):
                    fake_state = "walking"

                if cmd in {"hello", "heartbeat"} and not args.show_heartbeat:
                    should_print = False
                elif cmd == "walk":
                    current_walk = _walk_tuple(msg)
                    if current_walk is not None and last_printed_walk is not None:
                        max_delta = max(
                            abs(current_walk[i] - last_printed_walk[i])
                            for i in range(3)
                        )
                        should_print = max_delta >= args.walk_delta
                    if should_print and current_walk is not None:
                        last_printed_walk = current_walk

            if should_print:
                print(f"[{_now()}] #{packet_index:05d} from {addr[0]}:{addr[1]}  {summary}")
                if args.raw:
                    print(f"  raw={text}")
                sys.stdout.flush()

            if not args.no_ack:
                try:
                    sock.sendto(
                        _ack_payload(
                            msg,
                            packet_index,
                            remote_enabled=remote_enabled,
                            fake_state=fake_state,
                            reset_enabled=not remote_enabled,
                        ),
                        addr,
                    )
                except OSError as exc:
                    print(f"[{_now()}] ack-send-failed: {exc}", file=sys.stderr)
                    sys.stderr.flush()
    except KeyboardInterrupt:
        print("\nStopped.")
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
