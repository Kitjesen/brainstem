"""Thunder quadruped robot Python SDK.

3 lines to walk:

    from brainstem_sdk import ThunderClient
    dog = ThunderClient("192.168.66.190")
    dog.walk(vx=0.3)
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Iterator

import grpc
from google.protobuf.empty_pb2 import Empty

from brainstem_sdk._proto import cms_pb2, cms_pb2_grpc, common_pb2


# ── Data types ──────────────────────────────────────────────

@dataclass
class Vec3:
    x: float = 0.0
    y: float = 0.0
    z: float = 0.0

@dataclass
class Quat:
    w: float = 1.0
    x: float = 0.0
    y: float = 0.0
    z: float = 0.0

@dataclass
class ImuData:
    gyroscope: Vec3 = field(default_factory=Vec3)
    quaternion: Quat = field(default_factory=Quat)
    timestamp_ms: float = 0.0

@dataclass
class JointData:
    id: int = 0
    position: float = 0.0
    velocity: float = 0.0
    torque: float = 0.0
    status: int = 0

@dataclass
class MotorInfo:
    id: int = 0
    online: bool = False
    temperature: float = 0.0
    voltage: float = 0.0
    position: float = 0.0
    velocity: float = 0.0
    torque: float = 0.0
    errors: list[int] = field(default_factory=list)

@dataclass
class ProfileInfo:
    current: str = ""
    available: list[str] = field(default_factory=list)
    descriptions: list[str] = field(default_factory=list)


# ── State enum ──────────────────────────────────────────────

class RobotState:
    ZERO = "zero"
    GROUNDED = "grounded"
    STANDING = "standing"
    WALKING = "walking"
    TRANSITIONING = "transitioning"

    _MAP = {
        0: "zero",
        1: "grounded",
        2: "standing",
        3: "walking",
        4: "transitioning",
    }

    @staticmethod
    def from_proto(kind: int) -> str:
        return RobotState._MAP.get(kind, f"unknown({kind})")


# ── Client ──────────────────────────────────────────────────

class ThunderClient:
    """High-level Python client for Thunder quadruped robot.

    Args:
        host: Robot IP address (default "192.168.66.190").
        port: gRPC port (default 13145).
        timeout: Default RPC timeout in seconds (default 5.0).

    Example::

        dog = ThunderClient("192.168.66.190")
        dog.enable()
        dog.stand_up()
        dog.walk(vx=0.5)
        dog.sit_down()
        dog.disable()
    """

    def __init__(
        self,
        host: str = "192.168.66.190",
        port: int = 13145,
        timeout: float = 5.0,
    ):
        self._target = f"{host}:{port}"
        self._timeout = timeout
        self._channel = grpc.insecure_channel(self._target)
        self._stub = cms_pb2_grpc.CmsStub(self._channel)

    def close(self):
        """Close the gRPC channel."""
        self._channel.close()

    def __enter__(self):
        return self

    def __exit__(self, *args):
        self.close()

    # ── Motor control ───────────────────────────────────────

    def enable(self):
        """Enable all motors."""
        self._stub.Enable(Empty(), timeout=self._timeout)

    def disable(self):
        """Disable all motors (safe stop)."""
        self._stub.Disable(Empty(), timeout=self._timeout)

    # ── Motion commands ─────────────────────────────────────

    def walk(self, vx: float = 0.0, vy: float = 0.0, vyaw: float = 0.0):
        """Send walk command.

        Args:
            vx: Forward/backward speed [-1, 1]. Positive = forward.
            vy: Left/right speed [-1, 1]. Positive = left.
            vyaw: Rotation speed [-1, 1]. Positive = counter-clockwise.
        """
        cmd = common_pb2.Vector3(x=vx, y=vy, z=vyaw)
        self._stub.Walk(cmd, timeout=self._timeout)

    def stand_up(self):
        """Transition from sitting to standing."""
        self._stub.StandUp(Empty(), timeout=self._timeout)

    def sit_down(self):
        """Transition from standing to sitting."""
        self._stub.SitDown(Empty(), timeout=self._timeout)

    # ── State query ─────────────────────────────────────────

    def get_state(self) -> str:
        """Get current robot state.

        Returns:
            One of: "zero", "grounded", "standing", "walking", "transitioning".
        """
        resp = self._stub.GetCmsState(Empty(), timeout=self._timeout)
        return RobotState.from_proto(resp.kind)

    def get_voltage(self) -> list[float]:
        """Read bus voltage of all 16 motors (V)."""
        resp = self._stub.GetVoltage(Empty(), timeout=self._timeout)
        return list(resp.values)

    def get_motor_status(self) -> list[MotorInfo]:
        """Get health status of all 16 motors."""
        resp = self._stub.GetMotorStatus(Empty(), timeout=self._timeout)
        return [
            MotorInfo(
                id=m.id,
                online=m.online,
                temperature=m.temperature,
                voltage=m.voltage,
                position=m.position,
                velocity=m.velocity,
                torque=m.torque,
                errors=list(m.errors),
            )
            for m in resp.motors
        ]

    # ── Profile management ──────────────────────────────────

    def get_profile(self) -> ProfileInfo:
        """Get current profile info and available profiles."""
        resp = self._stub.GetProfile(Empty(), timeout=self._timeout)
        return ProfileInfo(
            current=resp.current,
            available=list(resp.available),
            descriptions=list(resp.descriptions),
        )

    def switch_profile(self, name: str) -> ProfileInfo:
        """Switch to a different motion profile. Robot must be grounded.

        Args:
            name: Profile name (see get_profile().available).
        """
        req = cms_pb2.ProfileRequest(name=name)
        resp = self._stub.SwitchProfile(req, timeout=self._timeout)
        return ProfileInfo(
            current=resp.current,
            available=list(resp.available),
            descriptions=list(resp.descriptions),
        )

    # ── Speed mode (速度模式) ─────────────────────────────

    def set_high_speed(self, enabled: bool = True):
        """Enable or disable high-speed mode (max 2.5m/s).

        High-speed mode increases the maximum walking speed. Use only
        in open, flat areas. The robot must be in Standing state.

        Args:
            enabled: True for high-speed (2.5m/s), False for normal.

        Example::

            dog.stand_up()
            dog.set_high_speed(True)   # enable 2.5m/s
            dog.walk(vx=1.0)           # full speed forward
            dog.set_high_speed(False)  # back to normal
        """
        mode = 1 if enabled else 0  # SPEED_MODE_HIGH=1, SPEED_MODE_NORMAL=0
        req = cms_pb2.SpeedModeRequest(mode=mode)
        self._stub.SetSpeedMode(req, timeout=self._timeout)

    def get_speed_mode(self) -> str:
        """Get current speed mode.

        Returns:
            "normal" or "high_speed".
        """
        resp = self._stub.GetSpeedMode(Empty(), timeout=self._timeout)
        return "high_speed" if resp.mode == 1 else "normal"

    # ── Gesture (动作系统) ───────────────────────────────

    def list_gestures(self) -> list[dict]:
        """List all available preset gestures.

        Returns:
            List of dicts with keys: name, description, duration_ms.

        Example::

            gestures = dog.list_gestures()
            for g in gestures:
                print(f"{g['name']}: {g['description']} ({g['duration_ms']}ms)")
        """
        resp = self._stub.ListGestures(Empty(), timeout=self._timeout)
        return [
            {
                "name": g.name,
                "description": g.description,
                "duration_ms": g.duration_ms,
            }
            for g in resp.gestures
        ]

    def play_gesture(self, name: str):
        """Play a preset gesture. Robot must be standing.

        Available gestures: bow (鞠躬), nod (点头), wiggle (扭动),
        stretch (伸展), dance (跳舞).

        Args:
            name: Gesture name (see list_gestures()).

        Example::

            dog.stand_up()
            dog.play_gesture("bow")    # 鞠躬
            dog.play_gesture("dance")  # 跳舞
        """
        req = cms_pb2.GestureRequest(name=name)
        self._stub.PlayGesture(req, timeout=30.0)  # gestures can take long

    # ── Diagnostics ─────────────────────────────────────────

    def clear_motor_fault(self, joint_ids: list[int] | None = None):
        """Clear motor faults.

        Args:
            joint_ids: Joint indices (0-15) to clear. None = clear all.
        """
        req = cms_pb2.ClearFaultRequest(joint_ids=joint_ids or [])
        self._stub.ClearMotorFault(req, timeout=self._timeout)

    def set_zero(self):
        """Calibrate current position as zero. Robot must be grounded."""
        self._stub.SetZero(Empty(), timeout=self._timeout)

    # ── Streaming (real-time data) ──────────────────────────

    def listen_imu(self) -> Iterator[ImuData]:
        """Subscribe to real-time IMU data stream (~50Hz).

        Yields:
            ImuData with gyroscope and quaternion.
        """
        for msg in self._stub.ListenImu(Empty()):
            yield ImuData(
                gyroscope=Vec3(
                    x=msg.gyroscope.x,
                    y=msg.gyroscope.y,
                    z=msg.gyroscope.z,
                ),
                quaternion=Quat(
                    w=msg.quaternion.w,
                    x=msg.quaternion.x,
                    y=msg.quaternion.y,
                    z=msg.quaternion.z,
                ),
                timestamp_ms=msg.timestamp.seconds * 1000
                + msg.timestamp.nanos / 1e6,
            )

    def listen_joint(self) -> Iterator[JointData]:
        """Subscribe to real-time joint data stream.

        Yields:
            JointData for each joint report.
        """
        for msg in self._stub.ListenJoint(Empty()):
            if msg.HasField("single_joint"):
                j = msg.single_joint
                yield JointData(
                    id=j.id,
                    position=j.position,
                    velocity=j.velocity,
                    torque=j.torque,
                    status=j.status,
                )

    def listen_state(self) -> Iterator[str]:
        """Subscribe to robot state changes.

        Yields:
            State string on each change.
        """
        for msg in self._stub.ListenCmsState(Empty()):
            yield RobotState.from_proto(msg.kind)


# Preferred public alias used by the current ORIX-facing documentation.
OrixClient = ThunderClient
