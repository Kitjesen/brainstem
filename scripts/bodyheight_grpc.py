#!/usr/bin/env python3
"""Safely command and verify Thunder body-height policy telemetry."""

from __future__ import annotations

import argparse
import json
import math
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable, Iterable, Sequence


DEFAULT_TARGET = "192.168.66.190:13145"
DEFAULT_TIMEOUT = 5.0
DEFAULT_PROFILE_DIR = Path(__file__).resolve().parents[1] / "han_dog" / "profiles"
SUPPORTED_PROFILES = frozenset(("thunder_h15", "thunder_h18"))
STANDING = 2
WALKING = 3
STATE_NAMES = {
    0: "Zero",
    1: "Grounded",
    STANDING: "Standing",
    WALKING: "Walking",
    4: "Transitioning",
}


class BodyHeightError(Exception):
    """Base class for expected, actionable failures."""


class ConfigError(BodyHeightError):
    """The active profile configuration is unavailable or unsafe."""


class CommandError(BodyHeightError):
    """A requested command is invalid or unsafe in the current state."""


class TelemetryError(BodyHeightError):
    """Command telemetry was unavailable or did not confirm the command."""


@dataclass(frozen=True)
class ProfileLimits:
    name: str
    height_min: float
    height_max: float
    velocity_min: tuple[float, float, float]
    velocity_max: tuple[float, float, float]


@dataclass(frozen=True)
class RuntimeApi:
    grpc: Any
    empty_factory: Callable[[], Any]
    stub_factory: Callable[[Any], Any]
    vector_factory: Callable[..., Any]
    body_height_factory: Callable[..., Any]


@dataclass(frozen=True)
class CommandResult:
    state: str
    history: Any


def _finite_number(value: Any, field: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ConfigError(f"{field} must be a number")
    result = float(value)
    if not math.isfinite(result):
        raise ConfigError(f"{field} must be finite")
    return result


def _vector(raw: Any, field: str) -> tuple[float, float, float]:
    if not isinstance(raw, list) or len(raw) != 3:
        raise ConfigError(f"{field} must contain exactly three numbers")
    values = tuple(_finite_number(value, f"{field}[{index}]") for index, value in enumerate(raw))
    return values  # type: ignore[return-value]


def load_profile(profile_dir: Path | str, active_profile: str) -> ProfileLimits:
    """Load and strictly validate limits for an already-active supported profile."""
    if active_profile not in SUPPORTED_PROFILES:
        expected = ", ".join(sorted(SUPPORTED_PROFILES))
        raise CommandError(
            f"active profile {active_profile!r} is unsupported; expected {expected}"
        )

    path = Path(profile_dir) / f"{active_profile}.json"
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise ConfigError(f"profile config not found: {path}") from exc
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise ConfigError(f"cannot read valid profile JSON {path}: {exc}") from exc

    if not isinstance(raw, dict):
        raise ConfigError(f"profile config must be a JSON object: {path}")
    if raw.get("name") != active_profile:
        raise ConfigError(
            f"profile config name mismatch: expected {active_profile!r}, "
            f"got {raw.get('name')!r}"
        )

    try:
        height_min = _finite_number(raw["minBodyHeightCommand"], "minBodyHeightCommand")
        height_max = _finite_number(raw["maxBodyHeightCommand"], "maxBodyHeightCommand")
        velocity_min = _vector(raw["velocityCommandMin"], "velocityCommandMin")
        velocity_max = _vector(raw["velocityCommandMax"], "velocityCommandMax")
    except KeyError as exc:
        raise ConfigError(f"profile config is missing {exc.args[0]!r}") from exc

    if height_min > height_max:
        raise ConfigError("minBodyHeightCommand exceeds maxBodyHeightCommand")
    if any(low > high for low, high in zip(velocity_min, velocity_max)):
        raise ConfigError("velocityCommandMin exceeds velocityCommandMax")

    return ProfileLimits(
        name=active_profile,
        height_min=height_min,
        height_max=height_max,
        velocity_min=velocity_min,
        velocity_max=velocity_max,
    )


def resolve_velocity(args: argparse.Namespace) -> tuple[float, float, float]:
    """Resolve explicitly supplied axes, converting omitted axes to zero."""
    supplied = (args.vx, args.vy, args.yaw)
    if all(value is None for value in supplied):
        raise CommandError("set-velocity requires at least one explicit axis")
    vector = tuple(0.0 if value is None else float(value) for value in supplied)
    if not all(math.isfinite(value) for value in vector):
        raise CommandError("velocity axes must be finite")
    return vector  # type: ignore[return-value]


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Command Thunder H15/H18 height and velocity with telemetry verification."
    )
    parser.add_argument("--target", default=DEFAULT_TARGET, help="gRPC host:port")
    parser.add_argument(
        "--timeout",
        default=DEFAULT_TIMEOUT,
        type=float,
        help="RPC and telemetry confirmation timeout in seconds",
    )
    parser.add_argument(
        "--profile-dir",
        default=DEFAULT_PROFILE_DIR,
        type=Path,
        help="directory containing thunder_h15.json and thunder_h18.json",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("status", help="show CMS state, profile, and current telemetry")

    set_height = subparsers.add_parser(
        "set-height", help="set body height in metres and verify telemetry"
    )
    set_height.add_argument("metres", type=float)

    set_velocity = subparsers.add_parser(
        "set-velocity",
        help=(
            "set walk velocity and verify telemetry; WARNING: sending while "
            "motors are enabled may move the robot"
        ),
        description=(
            "Set walk velocity and verify telemetry. WARNING: sending this "
            "command while motors are enabled may move the robot."
        ),
    )
    set_velocity.add_argument("--vx", type=float, default=None, help="forward m/s")
    set_velocity.add_argument("--vy", type=float, default=None, help="lateral m/s")
    set_velocity.add_argument("--yaw", type=float, default=None, help="yaw rad/s")

    subparsers.add_parser(
        "watch-height", help="stream body-height and walk telemetry until Ctrl+C"
    )
    return parser


def _validate_timeout(timeout: float) -> float:
    if not math.isfinite(timeout) or timeout <= 0:
        raise CommandError("--timeout must be a positive finite number")
    return timeout


def _walk_vector(item: Any) -> tuple[float, float, float] | None:
    command = getattr(item, "command", None)
    if command is None:
        return None
    try:
        if command.WhichOneof("data") != "walk":
            return None
        walk = command.walk
        values = (float(walk.x), float(walk.y), float(walk.z))
    except (AttributeError, TypeError, ValueError):
        return None
    return values if all(math.isfinite(value) for value in values) else None


def _history_height(item: Any) -> float | None:
    try:
        value = float(item.body_height_command)
    except (AttributeError, TypeError, ValueError):
        return None
    return value if math.isfinite(value) else None


class BodyHeightClient:
    """Small injectable wrapper around only the approved RobotControl RPCs."""

    def __init__(
        self,
        stub: Any,
        *,
        empty_factory: Callable[[], Any],
        vector_factory: Callable[..., Any],
        body_height_factory: Callable[..., Any],
        timeout: float = DEFAULT_TIMEOUT,
    ) -> None:
        self._stub = stub
        self._empty_factory = empty_factory
        self._vector_factory = vector_factory
        self._body_height_factory = body_height_factory
        self.timeout = _validate_timeout(float(timeout))

    def active_profile(self) -> str:
        response = self._stub.GetProfile(self._empty_factory(), timeout=self.timeout)
        current = getattr(response, "current", None)
        if not isinstance(current, str) or not current:
            raise TelemetryError("GetProfile returned no active profile")
        return current

    def cms_state(self) -> int:
        response = self._stub.GetCmsState(self._empty_factory(), timeout=self.timeout)
        kind = getattr(response, "kind", None)
        if isinstance(kind, bool) or not isinstance(kind, int):
            raise TelemetryError("GetCmsState returned an invalid state")
        return kind

    def histories(self, *, bounded: bool = True) -> Iterable[Any]:
        if bounded:
            return self._stub.ListenHistory(
                self._empty_factory(), timeout=self.timeout
            )
        return self._stub.ListenHistory(self._empty_factory())

    def latest_history(self) -> Any:
        try:
            return next(iter(self.histories()))
        except StopIteration as exc:
            raise TelemetryError("history telemetry is unavailable") from exc

    def status(self) -> tuple[int, str, Any]:
        state = self.cms_state()
        profile = self.active_profile()
        latest = self.latest_history()
        if _history_height(latest) is None:
            raise TelemetryError("history contains no finite body-height telemetry")
        return state, profile, latest

    def set_height(
        self,
        metres: float,
        profile_dir: Path | str,
        *,
        tolerance: float = 0.001,
    ) -> CommandResult:
        value = float(metres)
        if not math.isfinite(value):
            raise CommandError("height must be finite")
        profile = load_profile(profile_dir, self.active_profile())
        if not profile.height_min <= value <= profile.height_max:
            raise CommandError(
                f"height {value:g} is outside [{profile.height_min:g}, "
                f"{profile.height_max:g}] for {profile.name}"
            )

        try:
            stream = iter(self.histories())
            baseline = next(stream)
        except StopIteration as exc:
            raise TelemetryError(
                "history telemetry is unavailable; height command was not sent"
            ) from exc
        except Exception as exc:
            raise TelemetryError(
                f"height baseline telemetry failed; command was not sent: {exc}"
            ) from exc

        observed = _history_height(baseline)
        if observed is None:
            raise TelemetryError(
                "height baseline telemetry is missing or non-finite; command was not sent"
            )
        if abs(observed - value) <= tolerance:
            return CommandResult("already_active", baseline)

        self._stub.SetBodyHeight(
            self._body_height_factory(meters=value), timeout=self.timeout
        )
        try:
            for item in stream:
                observed = _history_height(item)
                if observed is not None and abs(observed - value) <= tolerance:
                    return CommandResult("confirmed", item)
        except Exception as exc:
            raise TelemetryError(
                f"height command {value:g} was not confirmed before the telemetry "
                f"stream failed: {exc}"
            ) from exc
        raise TelemetryError(
            f"height command {value:g} was not confirmed by telemetry within "
            f"{self.timeout:g}s; verify the CMS state and active profile"
        )

    def set_velocity(
        self,
        vector: Sequence[float],
        profile_dir: Path | str,
        *,
        tolerance: float = 0.001,
    ) -> CommandResult:
        if len(vector) != 3:
            raise CommandError("velocity must contain vx, vy, and yaw")
        values = tuple(float(value) for value in vector)
        if not all(math.isfinite(value) for value in values):
            raise CommandError("velocity axes must be finite")

        profile = load_profile(profile_dir, self.active_profile())
        labels = ("vx", "vy", "yaw")
        for label, value, low, high in zip(
            labels, values, profile.velocity_min, profile.velocity_max
        ):
            if not low <= value <= high:
                raise CommandError(
                    f"{label} {value:g} is outside [{low:g}, {high:g}] "
                    f"for {profile.name}"
                )

        state = self.cms_state()
        if state not in (STANDING, WALKING):
            name = STATE_NAMES.get(state, f"Unknown({state})")
            raise CommandError(
                f"set-velocity requires CMS state Standing or Walking; current state is {name}"
            )

        try:
            stream = iter(self.histories())
            baseline = next(stream)
        except StopIteration as exc:
            raise TelemetryError(
                "history telemetry is unavailable; velocity command was not sent"
            ) from exc
        except Exception as exc:
            raise TelemetryError(
                f"velocity baseline telemetry failed; command was not sent: {exc}"
            ) from exc

        observed = _walk_vector(baseline)
        if observed is not None and all(
            abs(actual - expected) <= tolerance
            for actual, expected in zip(observed, values)
        ):
            return CommandResult("already_active", baseline)

        self._stub.Walk(
            self._vector_factory(x=values[0], y=values[1], z=values[2]),
            timeout=self.timeout,
        )
        try:
            for item in stream:
                observed = _walk_vector(item)
                if observed is not None and all(
                    abs(actual - expected) <= tolerance
                    for actual, expected in zip(observed, values)
                ):
                    return CommandResult("confirmed", item)
        except Exception as exc:
            requested = ", ".join(f"{value:g}" for value in values)
            raise TelemetryError(
                f"velocity command ({requested}) was not confirmed before the "
                f"telemetry stream failed: {exc}"
            ) from exc
        requested = ", ".join(f"{value:g}" for value in values)
        raise TelemetryError(
            f"velocity command ({requested}) was not confirmed by telemetry within "
            f"{self.timeout:g}s; verify the CMS state and active profile"
        )


def _load_runtime_api() -> RuntimeApi:
    generated_root = (
        Path(__file__).resolve().parents[1] / "brainstem_api" / "python"
    )
    if generated_root.is_dir():
        generated_path = str(generated_root)
        if generated_path not in sys.path:
            sys.path.insert(0, generated_path)
    try:
        import grpc
        from brainstem_api import Empty, RobotControlStub, Vector3
        from brainstem_api.cms_pb2 import BodyHeightCommand
    except (ImportError, OSError) as exc:
        raise BodyHeightError(
            "gRPC runtime unavailable; expected generated API at "
            f"{generated_root} or an installed brainstem_api package, plus grpc"
        ) from exc
    return RuntimeApi(grpc, Empty, RobotControlStub, Vector3, BodyHeightCommand)


def _timestamp_text(item: Any) -> str:
    timestamp = getattr(item, "timestamp", None)
    if timestamp is None:
        return "-"
    seconds = getattr(timestamp, "seconds", None)
    nanos = getattr(timestamp, "nanos", None)
    if isinstance(seconds, int) and isinstance(nanos, int):
        return f"{seconds + nanos / 1_000_000_000:.3f}"
    return str(timestamp)


def _telemetry_text(item: Any) -> str:
    height = _history_height(item)
    height_text = "-" if height is None else f"{height:.4f}"
    walk = _walk_vector(item)
    walk_text = "none" if walk is None else (
        f"vx={walk[0]:.4f} vy={walk[1]:.4f} yaw={walk[2]:.4f}"
    )
    return f"timestamp={_timestamp_text(item)} height={height_text} walk={walk_text}"


def _run(args: argparse.Namespace) -> None:
    timeout = _validate_timeout(float(args.timeout))
    runtime = _load_runtime_api()
    channel = runtime.grpc.insecure_channel(args.target)
    try:
        client = BodyHeightClient(
            runtime.stub_factory(channel),
            empty_factory=runtime.empty_factory,
            vector_factory=runtime.vector_factory,
            body_height_factory=runtime.body_height_factory,
            timeout=timeout,
        )
        if args.command == "status":
            state, profile, latest = client.status()
            print(f"target: {args.target}")
            print(f"cms_state: {STATE_NAMES.get(state, f'Unknown({state})')} ({state})")
            print(f"active_profile: {profile}")
            print(_telemetry_text(latest))
        elif args.command == "set-height":
            result = client.set_height(args.metres, args.profile_dir)
            label = "already active" if result.state == "already_active" else "confirmed"
            print(f"{label} {_telemetry_text(result.history)}")
        elif args.command == "set-velocity":
            result = client.set_velocity(resolve_velocity(args), args.profile_dir)
            label = "already active" if result.state == "already_active" else "confirmed"
            print(f"{label} {_telemetry_text(result.history)}")
        elif args.command == "watch-height":
            for item in client.histories(bounded=False):
                print(_telemetry_text(item), flush=True)
        else:
            raise CommandError(f"unsupported command: {args.command}")
    finally:
        close = getattr(channel, "close", None)
        if close is not None:
            close()


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        _run(args)
    except KeyboardInterrupt:
        return 130
    except BodyHeightError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    except Exception as exc:
        # gRPC implementations use their own exception types; keep expected
        # transport failures concise without importing grpc at module import time.
        if exc.__class__.__module__.startswith("grpc"):
            details = getattr(exc, "details", lambda: str(exc))()
            print(f"error: gRPC request failed: {details}", file=sys.stderr)
            return 1
        print(f"error: unexpected RPC response: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
