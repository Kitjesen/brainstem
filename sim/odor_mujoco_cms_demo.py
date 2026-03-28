from __future__ import annotations

import argparse
import csv
import importlib.util
import math
import os
import random
import socket
import subprocess
import sys
import time
from collections import Counter
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

import grpc
import mujoco
import numpy as np


SCRIPT_DIR = Path(__file__).resolve().parent
BRAINSTEM_ROOT = SCRIPT_DIR.parent
PROTO_PY_ROOT = BRAINSTEM_ROOT / "han_dog_message" / "python"
if str(PROTO_PY_ROOT) not in sys.path:
    sys.path.insert(0, str(PROTO_PY_ROOT))

import han_dog_message as msg  # noqa: E402


DEFAULT_DART_EXE = Path(r"D:\software\flutter\bin\cache\dart-sdk\bin\dart.exe")
DEFAULT_GO2W_XML = Path(
    r"D:\inovxio\products\quadruped_ws\HIMLoco-for-Go2W\resources\robots\go2w\mjcf\go2w.xml"
)
DEFAULT_PORT = 13146
CONTROL_HZ = 50.0
MUJOCO_DT = 0.002
SUBSTEPS = int(round((1.0 / CONTROL_HZ) / MUJOCO_DT))

STANDING_POSE_DART = [
    -0.1,
    -0.8,
    1.8,
    0.1,
    0.8,
    -1.8,
    0.1,
    0.8,
    -1.8,
    -0.1,
    -0.8,
    1.8,
    0.0,
    0.0,
    0.0,
    0.0,
]

CMS_STATE_KIND_GROUNDED = 1
CMS_STATE_KIND_STANDING = 2
CMS_STATE_KIND_WALKING = 3


def clamp(value: float, low: float, high: float) -> float:
    return max(low, min(high, value))


def invert_quaternion_wxyz(quat: Iterable[float]) -> tuple[float, float, float, float]:
    w, x, y, z = quat
    return (w, -x, -y, -z)


def wrap_angle(angle: float) -> float:
    return math.atan2(math.sin(angle), math.cos(angle))


def yaw_from_quaternion_wxyz(quat: Iterable[float]) -> float:
    w, x, y, z = quat
    return math.atan2(2.0 * (w * z + x * y), 1.0 - 2.0 * (y * y + z * z))


def dart_to_mujoco(dart16: list[float]) -> list[float]:
    """Reorder Dart 12+4 layout to MuJoCo 4×4 layout and negate joint values."""
    mujoco16 = [0.0] * 16
    for leg in range(4):
        dart_base = leg * 3
        mj_base = leg * 4
        mujoco16[mj_base + 0] = -float(dart16[dart_base + 0])
        mujoco16[mj_base + 1] = -float(dart16[dart_base + 1])
        mujoco16[mj_base + 2] = -float(dart16[dart_base + 2])
        mujoco16[mj_base + 3] = -float(dart16[12 + leg])
    return mujoco16


def dart_gains_to_mujoco(dart16: list[float]) -> list[float]:
    """Reorder Dart 12+4 layout to MuJoCo 4×4 layout WITHOUT negation (for PD gains)."""
    mujoco16 = [0.0] * 16
    for leg in range(4):
        dart_base = leg * 3
        mj_base = leg * 4
        mujoco16[mj_base + 0] = float(dart16[dart_base + 0])
        mujoco16[mj_base + 1] = float(dart16[dart_base + 1])
        mujoco16[mj_base + 2] = float(dart16[dart_base + 2])
        mujoco16[mj_base + 3] = float(dart16[12 + leg])
    return mujoco16


def mujoco_to_dart(mj16: Iterable[float]) -> list[float]:
    """Reorder MuJoCo 4×4 layout to Dart 12+4 layout and negate joint values."""
    mj = list(mj16)
    dart16 = [0.0] * 16
    for leg in range(4):
        dart_base = leg * 3
        mj_base = leg * 4
        dart16[dart_base + 0] = -float(mj[mj_base + 0])
        dart16[dart_base + 1] = -float(mj[mj_base + 1])
        dart16[dart_base + 2] = -float(mj[mj_base + 2])
        dart16[12 + leg] = -float(mj[mj_base + 3])
    return dart16


@dataclass(frozen=True)
class Vec2:
    x: float
    y: float

    def dot(self, other: "Vec2") -> float:
        return self.x * other.x + self.y * other.y

    def norm(self) -> float:
        return math.hypot(self.x, self.y)

    def normalized(self) -> "Vec2":
        length = self.norm()
        if length <= 1e-6:
            return Vec2(0.0, 0.0)
        return Vec2(self.x / length, self.y / length)


@dataclass
class SensorChannel:
    name: str
    offset_body_xy: Vec2
    gain: float
    bias: float
    tau_s: float
    noise_sigma: float
    baseline_tau_s: float
    raw_value: float = 0.0
    filtered_value: float = 0.0
    baseline_value: float = 0.0
    delta_value: float = 0.0
    slope_value: float = 0.0
    drift_value: float = 0.0
    _prev_delta: float = 0.0

    def step(self, target_strength: float, dt: float, drift_sigma: float) -> None:
        self.drift_value += random.gauss(0.0, drift_sigma * math.sqrt(dt))
        target = self.bias + self.gain * target_strength + self.drift_value
        alpha = clamp(dt / self.tau_s, 0.0, 1.0)
        self.raw_value += alpha * (target - self.raw_value)
        self.raw_value += random.gauss(0.0, self.noise_sigma)
        self.filtered_value += 0.35 * (self.raw_value - self.filtered_value)

        baseline_alpha = clamp(dt / self.baseline_tau_s, 0.0, 1.0)
        if self.filtered_value > self.baseline_value + 1.0:
            baseline_alpha *= 0.15
        self.baseline_value += baseline_alpha * (self.filtered_value - self.baseline_value)

        self.delta_value = self.filtered_value - self.baseline_value
        self.slope_value = (self.delta_value - self._prev_delta) / max(dt, 1e-6)
        self._prev_delta = self.delta_value


@dataclass
class OdorField:
    source_xy: Vec2
    wind_heading_rad: float = 0.0
    wind_speed: float = 0.62
    source_strength: float = 1.2
    plume_sigma_m: float = 0.45
    plume_growth: float = 0.18
    upwind_leak: float = 0.05
    meander_amplitude: float = 0.28
    meander_frequency_hz: float = 0.56
    gust_strength: float = 0.16

    def sample_velocity(self, point_xy: Vec2, t_s: float) -> Vec2:
        base = Vec2(
            self.wind_speed * math.cos(self.wind_heading_rad),
            self.wind_speed * math.sin(self.wind_heading_rad),
        )
        phase_1 = 0.80 * point_xy.x + 1.35 * point_xy.y + 0.55 * t_s
        phase_2 = 1.45 * point_xy.x - 0.95 * point_xy.y - 0.38 * t_s + 0.60
        u_turb = self.gust_strength * (0.65 * math.sin(phase_1) + 0.35 * math.sin(phase_2))
        v_turb = self.gust_strength * (0.55 * math.cos(phase_1) - 0.45 * math.cos(phase_2))
        return Vec2(base.x + u_turb, base.y + v_turb)

    def concentration(self, point_xy: Vec2) -> float:
        wind_dir = Vec2(math.cos(self.wind_heading_rad), math.sin(self.wind_heading_rad))
        lateral = Vec2(-wind_dir.y, wind_dir.x)
        rel = Vec2(point_xy.x - self.source_xy.x, point_xy.y - self.source_xy.y)
        downwind = rel.dot(wind_dir)
        crosswind = rel.dot(lateral)
        if downwind >= 0.0:
            sigma = max(self.plume_sigma_m + self.plume_growth * downwind, 0.05)
            core = self.source_strength / (1.0 + downwind)
            return core * math.exp(-0.5 * (crosswind / sigma) ** 2)
        radius = max(rel.norm(), 1e-6)
        return self.upwind_leak * self.source_strength * math.exp(-0.5 * (radius / 0.5) ** 2)

    def visual_concentration(self, point_xy: Vec2, t_s: float) -> float:
        wind_dir = Vec2(math.cos(self.wind_heading_rad), math.sin(self.wind_heading_rad))
        lateral = Vec2(-wind_dir.y, wind_dir.x)
        rel = Vec2(point_xy.x - self.source_xy.x, point_xy.y - self.source_xy.y)
        downwind = rel.dot(wind_dir)
        crosswind = rel.dot(lateral)
        if downwind >= 0.0:
            sigma = max(self.plume_sigma_m + self.plume_growth * downwind, 0.05)
            plume_meander = self.meander_amplitude * math.sin(
                2.0 * math.pi * self.meander_frequency_hz * t_s - 0.55 * downwind
            )
            plume_meander += 0.08 * math.sin(0.95 * t_s + 0.35 * downwind)
            pulse = 0.92 + 0.14 * math.sin(0.42 * t_s - 0.48 * downwind)
            core = (self.source_strength * pulse) / (1.0 + 0.92 * downwind)
            return core * math.exp(-0.5 * ((crosswind - plume_meander) / sigma) ** 2)
        radius = max(rel.norm(), 1e-6)
        return self.upwind_leak * self.source_strength * math.exp(-0.5 * (radius / 0.5) ** 2)


@dataclass
class OdorPolicy:
    detection_threshold: float = 8.0
    loss_threshold: float = 4.0
    search_speed: float = 0.45
    track_speed: float = 0.65
    cast_speed: float = 0.35
    search_turn_amplitude: float = 0.14
    cast_turn_amplitude: float = 0.20
    cast_turn_frequency_hz: float = 0.60
    signal_alpha: float = 0.22
    command_alpha: float = 0.28
    steering_deadband: float = 1.2
    heading_alpha: float = 0.10
    drift_sigma: float = 0.03
    steer_alpha: float = 0.16
    mode: str = "search"
    mode_elapsed_s: float = 0.0
    last_detect_time_s: float = -1e9
    cast_sign: float = 1.0
    filtered_strength: float = 0.0
    filtered_g_x: float = 0.0
    filtered_g_y: float = 0.0
    filtered_steer: float = 0.0
    filtered_heading_error: float = 0.0
    forward_cmd: float = 0.0
    lateral_cmd: float = 0.0
    turn_cmd: float = 0.0

    def step(
        self,
        sensors: list[SensorChannel],
        now_s: float,
        dt: float,
        yaw_rad: float,
        local_wind: Vec2,
    ) -> tuple[float, float, float, float, float]:
        values = {sensor.name: max(sensor.delta_value, 0.0) for sensor in sensors}
        raw_g_x = ((values["fl"] + values["fr"]) - (values["rl"] + values["rr"])) / 2.0
        raw_g_y = ((values["fl"] + values["rl"]) - (values["fr"] + values["rr"])) / 2.0
        raw_strength = sum(values.values()) / 4.0

        self.filtered_strength += self.signal_alpha * (raw_strength - self.filtered_strength)
        self.filtered_g_x += self.signal_alpha * (raw_g_x - self.filtered_g_x)
        self.filtered_g_y += self.signal_alpha * (raw_g_y - self.filtered_g_y)
        self.filtered_steer += self.steer_alpha * (raw_g_y - self.filtered_steer)
        upwind_heading = math.atan2(-local_wind.y, -local_wind.x)
        heading_error = wrap_angle(upwind_heading - yaw_rad)
        self.filtered_heading_error += self.heading_alpha * (heading_error - self.filtered_heading_error)

        detected = self.filtered_strength >= self.detection_threshold

        if detected:
            self.last_detect_time_s = now_s

        if self.mode == "search" and detected:
            self.mode = "track"
            self.mode_elapsed_s = 0.0
        elif self.mode == "track" and self.filtered_strength < self.loss_threshold and now_s - self.last_detect_time_s > 1.0:
            self.mode = "cast"
            self.mode_elapsed_s = 0.0
            self.cast_sign *= -1.0
        elif self.mode == "cast" and detected:
            self.mode = "track"
            self.mode_elapsed_s = 0.0

        self.mode_elapsed_s += dt

        if self.mode == "search":
            target_x = self.search_speed
            target_y = 0.0
            target_z = 0.85 * self.search_turn_amplitude * math.sin(now_s * 0.34)
        elif self.mode == "track":
            steer_input = self.filtered_steer
            near_source = self.filtered_strength > 62.0 or self.filtered_g_x < -4.0
            very_near_source = self.filtered_strength > 90.0 or self.filtered_g_x < -10.0
            deadband = self.steering_deadband * (1.40 if near_source else 1.0)
            if abs(steer_input) < deadband:
                steer_input = 0.0
            target_x = clamp(
                self.track_speed - min(abs(steer_input) * 0.0016, 0.09),
                0.40,
                self.track_speed,
            )
            if near_source:
                target_x = min(target_x, 0.36)
            if very_near_source:
                target_x = min(target_x, 0.28)
            if self.filtered_g_x < -12.0:
                target_x = min(target_x, 0.26)
            elif self.filtered_g_x < -5.0:
                target_x = min(target_x, self.cast_speed + 0.12)
            target_y = clamp(steer_input * 0.0019, -0.035, 0.035)
            turn_gain = 0.017 if not near_source else 0.009
            turn_limit = 0.22 if not near_source else 0.10
            target_z = clamp(steer_input * turn_gain, -turn_limit, turn_limit)
        else:
            target_x = self.cast_speed
            target_y = 0.0
            target_z = self.cast_sign * 0.88 * self.cast_turn_amplitude * math.sin(
                self.mode_elapsed_s * self.cast_turn_frequency_hz
            )

        self.forward_cmd += clamp(
            self.command_alpha * (target_x - self.forward_cmd),
            -0.035,
            0.035,
        )
        self.lateral_cmd += clamp(
            self.command_alpha * (target_y - self.lateral_cmd),
            -0.02,
            0.02,
        )
        self.turn_cmd += clamp(
            self.command_alpha * (target_z - self.turn_cmd),
            -0.028 if self.mode == "track" else -0.036,
            0.028 if self.mode == "track" else 0.036,
        )
        return self.forward_cmd, self.lateral_cmd, self.turn_cmd, self.filtered_g_x, self.filtered_g_y


@dataclass
class RenderFrame:
    time_s: float
    qpos: np.ndarray
    robot_xy: Vec2
    distance_to_source_m: float
    odor_mode: str
    cms_state_kind: int
    sensor_deltas: dict[str, float]
    local_wind_xy: Vec2


def make_default_sensors() -> list[SensorChannel]:
    geometry = {
        "fl": Vec2(+0.12, +0.10),
        "fr": Vec2(+0.12, -0.10),
        "rl": Vec2(-0.12, +0.10),
        "rr": Vec2(-0.12, -0.10),
    }
    sensors: list[SensorChannel] = []
    for index, (name, offset) in enumerate(geometry.items()):
        gain_scale = 1.0 + (index - 1.5) * 0.04
        sensors.append(
            SensorChannel(
                name=name,
                offset_body_xy=offset,
                gain=220.0 * gain_scale,
                bias=10.0 + index * 0.4,
                tau_s=1.3 + index * 0.15,
                noise_sigma=0.45,
                baseline_tau_s=20.0,
            )
        )
    return sensors


def wait_for_tcp(port: int, timeout_s: float) -> None:
    deadline = time.time() + timeout_s
    while time.time() < deadline:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            sock.settimeout(1.0)
            if sock.connect_ex(("127.0.0.1", port)) == 0:
                return
        time.sleep(0.5)
    raise TimeoutError(f"Timed out waiting for TCP port {port}")


def resolve_onnxruntime_dir(explicit_dir: Path | None = None) -> Path | None:
    if explicit_dir is not None:
        return explicit_dir if explicit_dir.exists() else None

    spec = importlib.util.find_spec("onnxruntime")
    if spec is None or spec.origin is None:
        return None

    package_root = Path(spec.origin).resolve().parent
    candidate = package_root / "capi"
    if (candidate / "onnxruntime.dll").exists():
        return candidate
    return None


def launch_server(
    port: int,
    dart_exe: Path,
    log_path: Path,
    ort_runtime_dir: Path | None = None,
) -> subprocess.Popen[bytes]:
    env = os.environ.copy()
    appdata_root = SCRIPT_DIR / "output" / "dart_appdata"
    localappdata_root = SCRIPT_DIR / "output" / "dart_localappdata"
    appdata_root.mkdir(parents=True, exist_ok=True)
    localappdata_root.mkdir(parents=True, exist_ok=True)
    env["MEDULLA_PORT"] = str(port)
    env["MEDULLA_PROFILE_DIR"] = str(SCRIPT_DIR / "profiles")
    env["MEDULLA_DEFAULT_PROFILE"] = "odor_demo"
    env["HAN_DOG_LOG"] = "WARNING"
    env["DART_SUPPRESS_ANALYTICS"] = "true"
    env["APPDATA"] = str(appdata_root)
    env["LOCALAPPDATA"] = str(localappdata_root)
    runtime_dir = resolve_onnxruntime_dir(ort_runtime_dir)
    if runtime_dir is not None:
        env["ONNXRUNTIME_DLL_PATH"] = str(runtime_dir / "onnxruntime.dll")
        env["PATH"] = f"{runtime_dir}{os.pathsep}{env.get('PATH', '')}"
    log_path.parent.mkdir(parents=True, exist_ok=True)
    log_file = log_path.open("wb")
    return subprocess.Popen(
        [str(dart_exe), "run", "han_dog/bin/server.dart"],
        cwd=str(BRAINSTEM_ROOT),
        env=env,
        stdout=log_file,
        stderr=subprocess.STDOUT,
    )


def shutdown_server(process: subprocess.Popen[bytes]) -> None:
    if process.poll() is not None:
        return
    process.terminate()
    try:
        process.wait(timeout=10)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=10)


def build_sim_state(data: mujoco.MjData, elapsed_s: float) -> msg.SimState:
    qpos = data.qpos
    qvel = data.qvel
    body_to_world = (float(qpos[3]), float(qpos[4]), float(qpos[5]), float(qpos[6]))
    world_to_body = invert_quaternion_wxyz(body_to_world)
    joint_position = mujoco_to_dart(qpos[7:23])
    joint_velocity = mujoco_to_dart(qvel[6:22])
    gyro = qvel[3:6]

    seconds = int(elapsed_s)
    nanos = int((elapsed_s - seconds) * 1e9)
    return msg.SimState(
        gyroscope=msg.Vector3(x=float(gyro[0]), y=float(gyro[1]), z=float(gyro[2])),
        quaternion=msg.Quaternion(
            w=world_to_body[0],
            x=world_to_body[1],
            y=world_to_body[2],
            z=world_to_body[3],
        ),
        joint_position=msg.Matrix4(values=joint_position),
        joint_velocity=msg.Matrix4(values=joint_velocity),
        timestamp=msg.Duration(seconds=seconds, nanos=nanos),
    )


def apply_history_to_model(history: msg.History, model: mujoco.MjModel, data: mujoco.MjData) -> None:
    data.ctrl[:] = dart_to_mujoco(list(history.next_action.values))
    if len(history.kp.values) == 16 and len(history.kd.values) == 16:
        kp = dart_gains_to_mujoco(list(history.kp.values))
        kd = dart_gains_to_mujoco(list(history.kd.values))
        for index in range(16):
            model.actuator_gainprm[index, 0] = kp[index]
            model.actuator_biasprm[index, 1] = -kp[index]
            model.actuator_biasprm[index, 2] = -kd[index]


def get_sensor_world_xy(data: mujoco.MjData, body_id: int, offset: Vec2) -> Vec2:
    rot = data.xmat[body_id].reshape(3, 3)
    pos = data.xpos[body_id]
    world = pos + rot @ [offset.x, offset.y, 0.0]
    return Vec2(float(world[0]), float(world[1]))


def map_physics_qpos_to_render_qpos(
    physics_qpos: np.ndarray,
    *,
    render_robot: str,
) -> np.ndarray:
    if render_robot == "quadruped":
        return np.array(physics_qpos, copy=True)

    if render_robot != "go2w":
        raise ValueError(f"Unsupported render robot: {render_robot}")

    render_qpos = np.zeros(23, dtype=float)
    render_qpos[:7] = physics_qpos[:7]
    render_qpos[2] += 0.03

    source = np.asarray(physics_qpos[7:23], dtype=float)

    # Current CMS output order is FR, FL, RR, RL, 4 joints each.
    fr = source[0:4]
    fl = source[4:8]
    rr = source[8:12]
    rl = source[12:16]

    # Go2W render order is FL, FR, RL, RR. These affine transforms are tuned
    # to map the stable legacy demo pose into a plausible Go2W posture.
    target = np.zeros(16, dtype=float)
    target[0:4] = np.array([
        fl[0] + 0.10,
        -fl[1],
        np.clip(-fl[2] + 0.30, -2.72, -0.84),
        0.0,
    ])
    target[4:8] = np.array([
        fr[0] - 0.10,
        fr[1],
        np.clip(fr[2] + 0.30, -2.72, -0.84),
        0.0,
    ])
    target[8:12] = np.array([
        rl[0] - 0.10,
        rl[1],
        np.clip(rl[2] + 0.30, -2.72, -0.84),
        0.0,
    ])
    target[12:16] = np.array([
        rr[0] + 0.10,
        -rr[1],
        np.clip(-rr[2] + 0.30, -2.72, -0.84),
        0.0,
    ])

    render_qpos[7:23] = target
    return render_qpos


def _plume_color(value: float, scale: float) -> tuple[float, float, float, float]:
    strength = clamp(value / max(scale, 1e-6), 0.0, 1.0)
    if strength <= 0.0:
        return (0.0, 0.0, 0.0, 0.0)
    if strength < 0.35:
        alpha = 0.10 + 0.22 * (strength / 0.35)
        return (0.97, 0.84, 0.42, alpha)
    if strength < 0.72:
        blend = (strength - 0.35) / 0.37
        alpha = 0.32 + 0.25 * blend
        return (0.98, 0.69 - 0.25 * blend, 0.26 - 0.12 * blend, alpha)
    blend = (strength - 0.72) / 0.28
    alpha = 0.57 + 0.23 * blend
    return (0.85, 0.24 + 0.05 * blend, 0.16 + 0.04 * blend, alpha)


def _scene_handle(renderer: mujoco.Renderer):
    scene = getattr(renderer, "_scene", None)
    if scene is None:
        scene = getattr(renderer, "scene", None)
    return scene


def _add_box_geom(scene, *, center: tuple[float, float, float], size: tuple[float, float, float], rgba: tuple[float, float, float, float]) -> None:
    if scene is None or scene.ngeom >= scene.maxgeom - 1:
        return
    mujoco.mjv_initGeom(
        scene.geoms[scene.ngeom],
        mujoco.mjtGeom.mjGEOM_BOX,
        np.array(size, dtype=np.float64),
        np.array(center, dtype=np.float64),
        np.eye(3, dtype=np.float64).reshape(-1),
        np.array(rgba, dtype=np.float32),
    )
    scene.ngeom += 1


def _add_sphere_geom(scene, *, center: tuple[float, float, float], radius: float, rgba: tuple[float, float, float, float]) -> None:
    if scene is None or scene.ngeom >= scene.maxgeom - 1:
        return
    mujoco.mjv_initGeom(
        scene.geoms[scene.ngeom],
        mujoco.mjtGeom.mjGEOM_SPHERE,
        np.array([radius, 0.0, 0.0], dtype=np.float64),
        np.array(center, dtype=np.float64),
        np.eye(3, dtype=np.float64).reshape(-1),
        np.array(rgba, dtype=np.float32),
    )
    scene.ngeom += 1


def _add_cylinder_geom(
    scene,
    *,
    center: tuple[float, float, float],
    radius: float,
    half_height: float,
    rgba: tuple[float, float, float, float],
) -> None:
    if scene is None or scene.ngeom >= scene.maxgeom - 1:
        return
    mujoco.mjv_initGeom(
        scene.geoms[scene.ngeom],
        mujoco.mjtGeom.mjGEOM_CYLINDER,
        np.array([radius, half_height, 0.0], dtype=np.float64),
        np.array(center, dtype=np.float64),
        np.eye(3, dtype=np.float64).reshape(-1),
        np.array(rgba, dtype=np.float32),
    )
    scene.ngeom += 1


def _bounds_from_frames(frames: list[RenderFrame], field: OdorField) -> tuple[float, float, float, float]:
    xs = [frame.robot_xy.x for frame in frames] + [field.source_xy.x]
    ys = [frame.robot_xy.y for frame in frames] + [field.source_xy.y]
    pad = 0.9
    return min(xs) - pad, max(xs) + pad, min(ys) - pad, max(ys) + pad


def _build_plume_tiles(
    field: OdorField,
    bounds: tuple[float, float, float, float],
    time_s: float,
    tiles_x: int = 28,
    tiles_y: int = 16,
) -> list[tuple[tuple[float, float, float], tuple[float, float, float], tuple[float, float, float, float]]]:
    x_min, x_max, y_min, y_max = bounds
    dx = (x_max - x_min) / max(tiles_x, 1)
    dy = (y_max - y_min) / max(tiles_y, 1)
    tile_size = (dx * 0.46, dy * 0.46, 0.003)
    scale = field.source_strength
    tiles: list[tuple[tuple[float, float, float], tuple[float, float, float], tuple[float, float, float, float]]] = []
    for ix in range(tiles_x):
        for iy in range(tiles_y):
            x = x_min + (ix + 0.5) * dx
            y = y_min + (iy + 0.5) * dy
            conc = field.visual_concentration(Vec2(float(x), float(y)), time_s)
            rgba = _plume_color(conc, scale)
            if rgba[3] <= 0.0:
                continue
            tiles.append(((float(x), float(y), 0.0025), tile_size, rgba))
    return tiles


def _source_puff_positions(
    *,
    field: OdorField,
    time_s: float,
    count: int = 12,
    dt_s: float = 0.22,
) -> list[tuple[float, float, float, float, float]]:
    puffs: list[tuple[float, float, float, float, float]] = []
    phase = time_s % dt_s
    for index in range(count):
        age = phase + index * dt_s
        x = field.source_xy.x + 0.28
        y = field.source_xy.y
        integration_dt = 0.08
        steps = max(1, int(age / integration_dt))
        for step in range(steps):
            sample_t = time_s - age + step * integration_dt
            wind = field.sample_velocity(Vec2(x, y), sample_t)
            x += 0.65 * wind.x * integration_dt
            y += 0.65 * wind.y * integration_dt
        z = 0.28 + min(age * 0.10, 0.52)
        radius = 0.028 + min(age * 0.007, 0.03)
        alpha = clamp(0.72 - 0.05 * index, 0.16, 0.72)
        puffs.append((x, y, z, radius, alpha))
    return puffs


def _flow_particle_positions(
    *,
    field: OdorField,
    corridor_center_x: float,
    corridor_center_y: float,
    corridor_half_x: float,
    corridor_half_y: float,
    time_s: float,
    layers: int = 3,
    per_layer: int = 12,
) -> list[tuple[float, float, float]]:
    particles: list[tuple[float, float, float]] = []
    span_x = max(corridor_half_x * 1.8, 1e-6)
    for layer in range(layers):
        for index in range(per_layer):
            phase = (index / max(per_layer, 1) + 0.19 * layer + 0.15 * time_s) % 1.0
            base_x = corridor_center_x - corridor_half_x * 0.90 + phase * span_x
            base_y = corridor_center_y + (layer - (layers - 1) / 2.0) * corridor_half_y * 0.34
            base_y += 0.10 * math.sin(5.4 * phase + 0.65 * time_s + 0.8 * layer)
            wind = field.sample_velocity(Vec2(base_x, base_y), time_s)
            particles.append(
                (
                    base_x + 0.12 * wind.x,
                    base_y + 0.12 * wind.y,
                    0.07 + 0.035 * layer,
                )
            )
    return particles


def _flow_streak_positions(
    *,
    field: OdorField,
    corridor_center_x: float,
    corridor_center_y: float,
    corridor_half_x: float,
    corridor_half_y: float,
    time_s: float,
    lanes: int = 6,
    segments: int = 8,
) -> list[tuple[float, float, float, float, float]]:
    streaks: list[tuple[float, float, float, float, float]] = []
    lane_span = max(lanes - 1, 1)
    for lane in range(lanes):
        lane_ratio = lane / lane_span
        head_x = corridor_center_x + corridor_half_x * (0.82 - ((time_s * 0.22 + lane_ratio * 0.11) % 1.0) * 1.68)
        head_y = corridor_center_y + (lane_ratio - 0.5) * corridor_half_y * 1.35
        point = Vec2(head_x, head_y)
        for segment in range(segments):
            sample_t = time_s - segment * 0.08
            wind = field.sample_velocity(point, sample_t).normalized()
            jitter = 0.035 * math.sin(1.8 * sample_t + 1.7 * lane_ratio + 0.4 * segment)
            point = Vec2(point.x - 0.18 * wind.x, point.y - 0.18 * wind.y + jitter)
            z = 0.06 + 0.026 * (segment % 3)
            radius = max(0.030 - 0.0025 * segment, 0.010)
            alpha = clamp(0.46 - 0.045 * segment, 0.10, 0.46)
            streaks.append((point.x, point.y, z, radius, alpha))
    return streaks


def _render_hud(
    frame_image: np.ndarray,
    frame: RenderFrame,
    field: OdorField,
    trail_world: list[Vec2],
    bounds: tuple[float, float, float, float],
    success_radius: float,
    sensor_peak: float,
) -> "Image.Image":
    from PIL import Image, ImageDraw, ImageFont

    image = Image.fromarray(frame_image)
    draw = ImageDraw.Draw(image, "RGBA")
    width, height = image.size
    ui_scale = max(min(width / 1280.0, height / 720.0), 1.0)

    def scaled(value: float) -> int:
        return max(1, int(round(value * ui_scale)))

    font_candidates = (
        r"C:\Windows\Fonts\msyh.ttc",
        r"C:\Windows\Fonts\msyhbd.ttc",
        r"C:\Windows\Fonts\arial.ttf",
    )

    def load_font(size: int, *, bold: bool = False):
        candidate_list = font_candidates[::-1] if bold else font_candidates
        for candidate in candidate_list:
            path = Path(candidate)
            if path.exists():
                try:
                    return ImageFont.truetype(str(path), scaled(size))
                except OSError:
                    continue
        return ImageFont.load_default()

    font_title = load_font(22, bold=True)
    font_body = load_font(15)
    font_small = load_font(13)
    font_metric = load_font(16, bold=True)

    title_box = (scaled(22), scaled(18), scaled(620), scaled(128))
    draw.rounded_rectangle(title_box, radius=scaled(16), fill=(6, 10, 20, 190))
    mode_fill = {
        "search": (240, 140, 0, 235),
        "track": (43, 138, 62, 235),
        "cast": (156, 54, 181, 235),
    }.get(frame.odor_mode, (80, 80, 80, 235))
    draw.rounded_rectangle(
        (scaled(38), scaled(72), scaled(170), scaled(108)),
        radius=scaled(12),
        fill=mode_fill,
    )
    draw.text((scaled(38), scaled(28)), "MuJoCo odor seek demo", fill=(255, 255, 255, 255), font=font_title)
    draw.text(
        (scaled(42), scaled(77)),
        frame.odor_mode.upper(),
        fill=(255, 255, 255, 255),
        font=font_body,
    )
    draw.text(
        (scaled(196), scaled(28)),
        f"t={frame.time_s:5.2f}s  dist={frame.distance_to_source_m:4.2f} m",
        fill=(230, 234, 240, 255),
        font=font_metric,
    )
    draw.text(
        (scaled(196), scaled(60)),
        f"source=({field.source_xy.x:.1f}, {field.source_xy.y:.1f})  wind={math.degrees(field.wind_heading_rad):.0f} deg",
        fill=(190, 202, 216, 255),
        font=font_body,
    )
    draw.text(
        (scaled(196), scaled(90)),
        f"cms_state={frame.cms_state_kind}",
        fill=(190, 202, 216, 255),
        font=font_body,
    )

    panel_w = scaled(560)
    panel_h = scaled(560)
    panel_x = width - panel_w - scaled(24)
    panel_y = scaled(18)
    draw.rounded_rectangle(
        (panel_x, panel_y, panel_x + panel_w, panel_y + panel_h),
        radius=scaled(16),
        fill=(10, 13, 24, 190),
    )

    map_pad = scaled(20)
    map_left = panel_x + map_pad
    map_top = panel_y + map_pad
    map_right = panel_x + panel_w - map_pad
    map_bottom = panel_y + scaled(360)
    draw.rectangle((map_left, map_top, map_right, map_bottom), fill=(27, 31, 45, 235))

    x_min, x_max, y_min, y_max = bounds
    map_w = max(map_right - map_left, 1)
    map_h = max(map_bottom - map_top, 1)

    def world_to_panel(point: Vec2) -> tuple[float, float]:
        px = map_left + (point.x - x_min) / max(x_max - x_min, 1e-6) * map_w
        py = map_bottom - (point.y - y_min) / max(y_max - y_min, 1e-6) * map_h
        return float(px), float(py)

    for sample_x in np.linspace(x_min, x_max, 52):
        for sample_y in np.linspace(y_min, y_max, 30):
            conc = field.visual_concentration(Vec2(float(sample_x), float(sample_y)), frame.time_s)
            rgba = _plume_color(conc, field.source_strength)
            if rgba[3] < 0.05:
                continue
            px, py = world_to_panel(Vec2(float(sample_x), float(sample_y)))
            draw.ellipse(
                (px - scaled(4), py - scaled(4), px + scaled(4), py + scaled(4)),
                fill=(
                    int(rgba[0] * 255),
                    int(rgba[1] * 255),
                    int(rgba[2] * 255),
                    int(rgba[3] * 255),
                ),
            )

    if len(trail_world) >= 2:
        draw.line(
            [world_to_panel(point) for point in trail_world],
            fill=(66, 184, 214, 230),
            width=scaled(4),
        )

    source_px, source_py = world_to_panel(field.source_xy)
    scale_radius = success_radius / max(x_max - x_min, 1e-6) * map_w
    draw.ellipse(
        (source_px - scale_radius, source_py - scale_radius, source_px + scale_radius, source_py + scale_radius),
        outline=(255, 120, 120, 235),
        width=scaled(2),
    )
    draw.ellipse(
        (source_px - scaled(6), source_py - scaled(6), source_px + scaled(6), source_py + scaled(6)),
        fill=(214, 51, 108, 255),
    )

    robot_px, robot_py = world_to_panel(frame.robot_xy)
    draw.ellipse(
        (robot_px - scaled(6), robot_py - scaled(6), robot_px + scaled(6), robot_py + scaled(6)),
        fill=(99, 230, 190, 255),
    )

    wind_samples_x = np.linspace(x_min + 0.45, x_max - 0.45, 7)
    wind_samples_y = np.linspace(y_min + 0.22, y_max - 0.22, 5)
    for sample_x in wind_samples_x:
        for sample_y in wind_samples_y:
            anchor = Vec2(float(sample_x), float(sample_y))
            wind = field.sample_velocity(anchor, frame.time_s)
            px, py = world_to_panel(anchor)
            scale = scaled(22)
            dx = clamp(wind.x, -1.0, 1.0) * scale
            dy = -clamp(wind.y, -1.0, 1.0) * scale
            draw.line((px, py, px + dx, py + dy), fill=(92, 186, 255, 210), width=scaled(2))
            draw.ellipse(
                (px - scaled(2), py - scaled(2), px + scaled(2), py + scaled(2)),
                fill=(164, 224, 255, 220),
            )

    wind_center_x = panel_x + scaled(74)
    wind_center_y = panel_y + scaled(432)
    arrow_len = scaled(42)
    local_wind = frame.local_wind_xy
    wind_norm = max(local_wind.norm(), 1e-6)
    wind_dx = local_wind.x / wind_norm * arrow_len
    wind_dy = -local_wind.y / wind_norm * arrow_len
    draw.line(
        (wind_center_x, wind_center_y, wind_center_x + wind_dx, wind_center_y + wind_dy),
        fill=(80, 171, 241, 255),
        width=scaled(4),
    )
    draw.text(
        (wind_center_x - scaled(14), wind_center_y + scaled(18)),
        "wind",
        fill=(180, 210, 245, 255),
        font=font_body,
    )
    draw.text(
        (wind_center_x + scaled(44), wind_center_y - scaled(10)),
        f"{local_wind.norm():.2f} m/s",
        fill=(220, 228, 239, 255),
        font=font_small,
    )

    palette = {
        "fl": (217, 72, 15, 255),
        "fr": (194, 37, 92, 255),
        "rl": (43, 138, 62, 255),
        "rr": (28, 126, 214, 255),
    }
    bar_origin_x = panel_x + scaled(188)
    bar_origin_y = panel_y + scaled(392)
    bar_width = scaled(276)
    bar_height = scaled(22)
    for index, name in enumerate(("fl", "fr", "rl", "rr")):
        y = bar_origin_y + index * scaled(30)
        draw.text((bar_origin_x - scaled(48), y - scaled(2)), name.upper(), fill=palette[name], font=font_body)
        draw.rounded_rectangle(
            (bar_origin_x, y, bar_origin_x + bar_width, y + bar_height),
            radius=scaled(8),
            fill=(42, 49, 68, 220),
        )
        fill_ratio = clamp(frame.sensor_deltas.get(name, 0.0) / max(sensor_peak, 1e-6), 0.0, 1.0)
        draw.rounded_rectangle(
            (bar_origin_x, y, bar_origin_x + fill_ratio * bar_width, y + bar_height),
            radius=scaled(8),
            fill=palette[name],
        )
        draw.text(
            (bar_origin_x + bar_width + scaled(10), y - scaled(1)),
            f"{frame.sensor_deltas.get(name, 0.0):5.1f}",
            fill=(226, 232, 240, 255),
            font=font_small,
        )

    return image


def render_mujoco_animation(
    model: mujoco.MjModel,
    frames: list[RenderFrame],
    field: OdorField,
    success_radius: float,
    gif_path: Path | None,
    mp4_path: Path | None,
    storyboard_path: Path | None,
    *,
    render_robot: str,
    go2w_xml_path: Path,
    width: int,
    height: int,
 ) -> tuple[bool, bool, bool]:
    if not frames or (gif_path is None and mp4_path is None and storyboard_path is None):
        return False, False, False

    from PIL import Image, ImageDraw

    if render_robot == "quadruped":
        render_model = model
    elif render_robot == "go2w":
        if not go2w_xml_path.exists():
            raise FileNotFoundError(f"Go2W render model not found: {go2w_xml_path}")
        render_model = mujoco.MjModel.from_xml_path(str(go2w_xml_path))
    else:
        raise ValueError(f"Unsupported render robot: {render_robot}")

    render_model.vis.global_.offwidth = max(int(render_model.vis.global_.offwidth), int(width))
    render_model.vis.global_.offheight = max(int(render_model.vis.global_.offheight), int(height))
    render_width = min(width, int(render_model.vis.global_.offwidth))
    render_height = min(height, int(render_model.vis.global_.offheight))
    render_data = mujoco.MjData(render_model)
    renderer = mujoco.Renderer(render_model, height=render_height, width=render_width)
    try:
        bounds = _bounds_from_frames(frames, field)
        sensor_peak = max(
            max(frame.sensor_deltas.values(), default=0.0) for frame in frames
        )
        camera = mujoco.MjvCamera()
        camera.type = mujoco.mjtCamera.mjCAMERA_FREE
        x_min, x_max, y_min, y_max = bounds
        span = max(x_max - x_min, y_max - y_min, 2.5)
        camera.lookat[:] = [(x_min + x_max) / 2.0, (y_min + y_max) / 2.0, 0.26]
        camera.distance = 0.98 * span + 0.95
        camera.azimuth = 108.0
        camera.elevation = -18.0

        rendered_images: list[Image.Image] = []
        for frame_index, frame in enumerate(frames):
            render_qpos = map_physics_qpos_to_render_qpos(
                frame.qpos,
                render_robot=render_robot,
            )
            render_data.qpos[:] = render_qpos
            render_data.qvel[:] = 0.0
            mujoco.mj_forward(render_model, render_data)
            renderer.update_scene(render_data, camera=camera)
            scene = _scene_handle(renderer)

            start_xy = frames[0].robot_xy
            center_x = (x_min + x_max) * 0.5
            center_y = (y_min + y_max) * 0.5
            span_x = x_max - x_min
            span_y = y_max - y_min
            corridor_center_x = (start_xy.x + field.source_xy.x) * 0.5
            corridor_center_y = (start_xy.y + field.source_xy.y) * 0.5
            corridor_half_x = max(abs(field.source_xy.x - start_xy.x) * 0.55 + 0.65, 1.6)
            corridor_half_y = max(abs(field.source_xy.y - start_xy.y) * 0.55 + 0.42, 0.62)
            plume_tiles = _build_plume_tiles(field, bounds, frame.time_s)

            _add_box_geom(
                scene,
                center=(center_x, center_y, -0.05),
                size=(span_x * 0.72, span_y * 0.72, 0.028),
                rgba=(0.22, 0.26, 0.31, 1.0),
            )
            _add_box_geom(
                scene,
                center=(corridor_center_x, corridor_center_y, -0.016),
                size=(corridor_half_x, corridor_half_y, 0.012),
                rgba=(0.82, 0.84, 0.86, 1.0),
            )
            _add_box_geom(
                scene,
                center=(corridor_center_x, corridor_center_y, -0.004),
                size=(corridor_half_x * 0.94, corridor_half_y * 0.36, 0.003),
                rgba=(0.96, 0.93, 0.72, 0.98),
            )
            _add_box_geom(
                scene,
                center=(corridor_center_x, corridor_center_y + corridor_half_y + 0.10, 0.26),
                size=(corridor_half_x * 0.92, 0.06, 0.02),
                rgba=(0.48, 0.54, 0.62, 0.45),
            )
            rail_half_y = corridor_half_y + 0.12
            for rail_y in (corridor_center_y - rail_half_y, corridor_center_y + rail_half_y):
                _add_box_geom(
                    scene,
                    center=(corridor_center_x, rail_y, 0.13),
                    size=(corridor_half_x * 0.98, 0.025, 0.13),
                    rgba=(0.33, 0.39, 0.46, 0.94),
                )
            for wall_y in (corridor_center_y - corridor_half_y - 0.24, corridor_center_y + corridor_half_y + 0.24):
                _add_box_geom(
                    scene,
                    center=(corridor_center_x, wall_y, 0.24),
                    size=(corridor_half_x * 0.98, 0.05, 0.24),
                    rgba=(0.20, 0.25, 0.30, 0.42),
                )
            for stripe_x in np.linspace(corridor_center_x - corridor_half_x * 0.92, corridor_center_x + corridor_half_x * 0.92, 10):
                _add_box_geom(
                    scene,
                    center=(stripe_x, corridor_center_y + corridor_half_y + 0.17, 0.010),
                    size=(0.10, 0.026, 0.010),
                    rgba=(0.94, 0.73, 0.18, 0.95),
                )
                _add_box_geom(
                    scene,
                    center=(stripe_x, corridor_center_y - corridor_half_y - 0.17, 0.010),
                    size=(0.10, 0.026, 0.010),
                    rgba=(0.94, 0.73, 0.18, 0.95),
                )

            source_pad_half_x = 0.42
            source_pad_half_y = 0.58
            _add_box_geom(
                scene,
                center=(field.source_xy.x, field.source_xy.y, 0.03),
                size=(source_pad_half_x, source_pad_half_y, 0.03),
                rgba=(0.28, 0.30, 0.34, 0.98),
            )
            _add_box_geom(
                scene,
                center=(field.source_xy.x, field.source_xy.y, 0.062),
                size=(source_pad_half_x * 0.82, source_pad_half_y * 0.82, 0.004),
                rgba=(0.95, 0.73, 0.18, 0.95),
            )
            _add_box_geom(
                scene,
                center=(field.source_xy.x + 0.28, field.source_xy.y, 0.34),
                size=(0.15, 0.22, 0.34),
                rgba=(0.29, 0.30, 0.33, 0.98),
            )
            _add_box_geom(
                scene,
                center=(field.source_xy.x + 0.28, field.source_xy.y - 0.26, 0.16),
                size=(0.26, 0.08, 0.16),
                rgba=(0.34, 0.36, 0.40, 0.96),
            )
            _add_cylinder_geom(
                scene,
                center=(field.source_xy.x + 0.28, field.source_xy.y, 0.76),
                radius=0.035,
                half_height=0.18,
                rgba=(0.76, 0.78, 0.82, 0.96),
            )
            for vent_y in (field.source_xy.y - 0.16, field.source_xy.y, field.source_xy.y + 0.16):
                _add_cylinder_geom(
                    scene,
                    center=(field.source_xy.x + 0.42, vent_y, 0.28),
                    radius=0.035,
                    half_height=0.03,
                    rgba=(0.60, 0.64, 0.70, 0.96),
                )

            crate_specs = [
                (corridor_center_x - corridor_half_x * 0.55, corridor_center_y + corridor_half_y + 0.34, 0.18, 0.18, 0.18),
                (corridor_center_x - corridor_half_x * 0.05, corridor_center_y - corridor_half_y - 0.30, 0.22, 0.16, 0.14),
                (field.source_xy.x - 0.55, field.source_xy.y + 0.92, 0.14, 0.22, 0.22),
            ]
            for crate_x, crate_y, sx, sy, sz in crate_specs:
                _add_box_geom(
                    scene,
                    center=(crate_x, crate_y, sz),
                    size=(sx, sy, sz),
                    rgba=(0.49, 0.32, 0.18, 0.96),
                )

            for tile_center, tile_size, tile_rgba in plume_tiles:
                _add_box_geom(scene, center=tile_center, size=tile_size, rgba=tile_rgba)

            for puff_x, puff_y, puff_z, puff_radius, puff_alpha in _source_puff_positions(
                field=field,
                time_s=frame.time_s,
            ):
                _add_sphere_geom(
                    scene,
                    center=(puff_x, puff_y, puff_z),
                    radius=puff_radius,
                    rgba=(1.0, 0.76, 0.24, puff_alpha),
                )

            for streak_x, streak_y, streak_z, streak_radius, streak_alpha in _flow_streak_positions(
                field=field,
                corridor_center_x=corridor_center_x,
                corridor_center_y=corridor_center_y,
                corridor_half_x=corridor_half_x,
                corridor_half_y=corridor_half_y,
                time_s=frame.time_s,
            ):
                _add_sphere_geom(
                    scene,
                    center=(streak_x, streak_y, streak_z),
                    radius=1.15 * streak_radius,
                    rgba=(0.56, 0.92, 1.00, min(streak_alpha + 0.08, 0.60)),
                )

            for particle_x, particle_y, particle_z in _flow_particle_positions(
                field=field,
                corridor_center_x=corridor_center_x,
                corridor_center_y=corridor_center_y,
                corridor_half_x=corridor_half_x,
                corridor_half_y=corridor_half_y,
                time_s=frame.time_s,
            ):
                _add_sphere_geom(
                    scene,
                    center=(particle_x, particle_y, particle_z),
                    radius=0.032,
                    rgba=(0.62, 0.94, 1.00, 0.62),
                )

            trail_limit = max(0, frame_index + 1)
            trail_stride = max(1, trail_limit // 40)
            trail_points = [frames[index].robot_xy for index in range(0, trail_limit, trail_stride)]
            for trail_point in trail_points:
                _add_sphere_geom(
                    scene,
                    center=(trail_point.x, trail_point.y, 0.035),
                    radius=0.030,
                    rgba=(0.11, 0.69, 0.86, 0.78),
                )

            _add_sphere_geom(
                scene,
                center=(frames[0].robot_xy.x, frames[0].robot_xy.y, 0.055),
                radius=0.055,
                rgba=(0.96, 0.61, 0.15, 0.92),
            )
            _add_cylinder_geom(
                scene,
                center=(field.source_xy.x, field.source_xy.y, 0.18),
                radius=0.08,
                half_height=0.18,
                rgba=(0.83, 0.18, 0.24, 0.96),
            )
            _add_sphere_geom(
                scene,
                center=(field.source_xy.x, field.source_xy.y, 0.41),
                radius=0.07,
                rgba=(0.96, 0.72, 0.21, 0.94),
            )

            frame_image = renderer.render()
            hud_image = _render_hud(
                frame_image,
                frame=frame,
                field=field,
                trail_world=trail_points,
                bounds=bounds,
                success_radius=success_radius,
                sensor_peak=max(sensor_peak, 1.0),
            )
            rendered_images.append(hud_image)

        gif_written = False
        if gif_path is not None and rendered_images:
            gif_path.parent.mkdir(parents=True, exist_ok=True)
            rendered_images[0].save(
                gif_path,
                save_all=True,
                append_images=rendered_images[1:],
                duration=100,
                loop=0,
                optimize=False,
                disposal=2,
            )
            gif_written = True

        mp4_written = False
        if mp4_path is not None and rendered_images:
            import imageio.v2 as imageio

            mp4_path.parent.mkdir(parents=True, exist_ok=True)
            with imageio.get_writer(
                str(mp4_path),
                fps=10,
                codec="libx264",
                quality=8,
                macro_block_size=None,
            ) as writer:
                for image in rendered_images:
                    writer.append_data(np.asarray(image))
            mp4_written = True

        storyboard_written = False
        if storyboard_path is not None and rendered_images:
            storyboard_path.parent.mkdir(parents=True, exist_ok=True)
            count = min(4, len(rendered_images))
            sample_indices = sorted({round(index * (len(rendered_images) - 1) / max(count - 1, 1)) for index in range(count)})
            sample_frames = [rendered_images[index] for index in sample_indices]
            tile_width, tile_height = sample_frames[0].size
            canvas = Image.new("RGB", (tile_width * len(sample_frames), tile_height), (10, 12, 18))
            draw = ImageDraw.Draw(canvas, "RGBA")
            for tile_index, image in enumerate(sample_frames):
                x_offset = tile_index * tile_width
                canvas.paste(image, (x_offset, 0))
                stamp = frames[sample_indices[tile_index]]
                draw.rectangle((x_offset + 14, 14, x_offset + 170, 52), fill=(0, 0, 0, 170))
                draw.text((x_offset + 26, 24), f"{stamp.time_s:4.1f}s  {stamp.odor_mode}", fill=(255, 255, 255, 255))
            canvas.save(storyboard_path, quality=95)
            storyboard_written = True

        return gif_written, mp4_written, storyboard_written
    finally:
        renderer.close()


def render_demo_plot(
    rows: list[dict[str, float | str]],
    field: OdorField,
    success_radius: float,
    path: Path,
) -> bool:
    try:
        import matplotlib

        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
        import numpy as np
    except Exception:
        return False

    if not rows:
        return False

    xs = [float(row["robot_x_m"]) for row in rows]
    ys = [float(row["robot_y_m"]) for row in rows]
    distances = [float(row["distance_to_source_m"]) for row in rows]
    times = [float(row["time_s"]) for row in rows]
    final_time_s = times[-1]
    sensor_names = ("fl", "fr", "rl", "rr")

    x_min = min(min(xs), field.source_xy.x) - 0.8
    x_max = max(max(xs), field.source_xy.x) + 0.8
    y_min = min(min(ys), field.source_xy.y) - 0.8
    y_max = max(max(ys), field.source_xy.y) + 0.8

    grid_x = np.linspace(x_min, x_max, 140)
    grid_y = np.linspace(y_min, y_max, 100)
    field_grid = np.zeros((len(grid_y), len(grid_x)))
    for y_index, y_value in enumerate(grid_y):
        for x_index, x_value in enumerate(grid_x):
            field_grid[y_index, x_index] = field.visual_concentration(Vec2(float(x_value), float(y_value)), final_time_s)

    fig, axes = plt.subplots(1, 3, figsize=(16.5, 4.8), dpi=220)
    ax_field, ax_distance, ax_sensors = axes

    image = ax_field.imshow(
        field_grid,
        origin="lower",
        extent=[x_min, x_max, y_min, y_max],
        cmap="YlOrRd",
        alpha=0.82,
        aspect="auto",
    )
    fig.colorbar(image, ax=ax_field, fraction=0.046, pad=0.04, label="odor concentration")
    ax_field.plot(xs, ys, color="#0b7285", linewidth=2.2, label="robot path")
    ax_field.scatter([xs[0]], [ys[0]], color="#f08c00", s=44, label="start", zorder=3)
    ax_field.scatter([field.source_xy.x], [field.source_xy.y], color="#c92a2a", s=54, label="source", zorder=3)
    ax_field.add_patch(
        plt.Circle(
            (field.source_xy.x, field.source_xy.y),
            success_radius,
            color="#c92a2a",
            fill=False,
            linestyle="--",
            linewidth=1.2,
            alpha=0.75,
        )
    )

    wind_dx = math.cos(field.wind_heading_rad)
    wind_dy = math.sin(field.wind_heading_rad)
    wind_x = np.linspace(x_min + 0.4, x_max - 0.4, 8)
    wind_y = np.linspace(y_min + 0.3, y_max - 0.3, 5)
    wind_xx, wind_yy = np.meshgrid(wind_x, wind_y)
    ax_field.quiver(
        wind_xx,
        wind_yy,
        np.vectorize(lambda x, y: field.sample_velocity(Vec2(float(x), float(y)), final_time_s).x)(wind_xx, wind_yy),
        np.vectorize(lambda x, y: field.sample_velocity(Vec2(float(x), float(y)), final_time_s).y)(wind_xx, wind_yy),
        color="#1c7ed6",
        alpha=0.7,
        scale=12.0,
        width=0.004,
    )
    ax_field.set_title("Dynamic odor plume, wind, and robot path")
    ax_field.set_xlabel("x (m)")
    ax_field.set_ylabel("y (m)")
    ax_field.grid(True, alpha=0.16)
    ax_field.legend(loc="upper left")

    ax_distance.plot(times, distances, color="#2b8a3e", linewidth=2.2)
    ax_distance.axhline(success_radius, color="#c92a2a", linestyle="--", linewidth=1.2)
    ax_distance.set_title("Distance to source")
    ax_distance.set_xlabel("time (s)")
    ax_distance.set_ylabel("distance (m)")
    ax_distance.grid(True, alpha=0.25)

    palette = {
        "fl": "#d9480f",
        "fr": "#c2255c",
        "rl": "#2b8a3e",
        "rr": "#1c7ed6",
    }
    for name in sensor_names:
        deltas = [float(row[f"{name}_delta"]) for row in rows]
        ax_sensors.plot(times, deltas, linewidth=1.8, label=name.upper(), color=palette[name])
    ax_sensors.set_title("Sensor delta traces")
    ax_sensors.set_xlabel("time (s)")
    ax_sensors.set_ylabel("delta")
    ax_sensors.grid(True, alpha=0.25)
    ax_sensors.legend(loc="upper left")

    fig.tight_layout()
    path.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(path)
    plt.close(fig)
    return True


def write_csv_header(path: Path) -> csv.DictWriter:
    path.parent.mkdir(parents=True, exist_ok=True)
    csv_file = path.open("w", newline="", encoding="utf-8")
    headers = [
        "time_s",
        "robot_x_m",
        "robot_y_m",
        "distance_to_source_m",
        "cms_state_kind",
        "odor_mode",
        "walk_x",
        "walk_y",
        "walk_z",
        "g_x",
        "g_y",
    ]
    for name in ("fl", "fr", "rl", "rr"):
        headers.extend((f"{name}_raw", f"{name}_baseline", f"{name}_delta", f"{name}_slope"))
    writer = csv.DictWriter(csv_file, fieldnames=headers)
    writer.writeheader()
    writer._csv_file = csv_file  # type: ignore[attr-defined]
    return writer


def close_writer(writer: csv.DictWriter) -> None:
    csv_file = getattr(writer, "_csv_file", None)
    if csv_file is not None:
        csv_file.close()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run the four-sensor odor demo through the existing MuJoCo CMS chain.")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT)
    parser.add_argument("--control-steps", type=int, default=1200)
    parser.add_argument("--seed", type=int, default=7)
    parser.add_argument("--dart-exe", type=Path, default=DEFAULT_DART_EXE)
    parser.add_argument("--render-robot", choices=("quadruped", "go2w"), default="quadruped")
    parser.add_argument("--go2w-xml", type=Path, default=DEFAULT_GO2W_XML)
    parser.add_argument("--csv", type=Path, default=SCRIPT_DIR / "output" / "odor_mujoco_cms_demo.csv")
    parser.add_argument("--plot", type=Path, default=SCRIPT_DIR / "output" / "odor_mujoco_cms_demo.png")
    parser.add_argument("--gif", type=Path, default=SCRIPT_DIR / "output" / "odor_mujoco_cms_demo.gif")
    parser.add_argument("--mp4", type=Path, default=SCRIPT_DIR / "output" / "odor_mujoco_cms_demo.mp4")
    parser.add_argument(
        "--storyboard",
        type=Path,
        default=SCRIPT_DIR / "output" / "odor_mujoco_cms_storyboard.png",
    )
    parser.add_argument("--render-every", type=int, default=4)
    parser.add_argument("--render-width", type=int, default=1920)
    parser.add_argument("--render-height", type=int, default=1080)
    parser.add_argument("--server-log", type=Path, default=SCRIPT_DIR / "output" / "odor_mujoco_cms_server.log")
    parser.add_argument("--source-x", type=float, default=4.8)
    parser.add_argument("--source-y", type=float, default=1.2)
    parser.add_argument("--wind-heading-deg", type=float, default=180.0)
    parser.add_argument("--wind-speed", type=float, default=0.62)
    parser.add_argument("--start-x", type=float, default=0.8)
    parser.add_argument("--start-y", type=float, default=0.8)
    parser.add_argument("--start-yaw-deg", type=float, default=0.0)
    parser.add_argument("--success-radius", type=float, default=0.65)
    parser.add_argument("--server-timeout", type=float, default=240.0)
    parser.add_argument("--ort-runtime-dir", type=Path, default=None)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    random.seed(args.seed)

    if not args.dart_exe.exists():
        raise FileNotFoundError(f"Dart executable not found: {args.dart_exe}")

    process = launch_server(
        args.port,
        args.dart_exe,
        args.server_log,
        ort_runtime_dir=args.ort_runtime_dir,
    )
    try:
        wait_for_tcp(args.port, args.server_timeout)
        channel = grpc.insecure_channel(f"127.0.0.1:{args.port}")
        grpc.channel_ready_future(channel).result(timeout=args.server_timeout)
        stub = msg.CmsStub(channel)
        stub.GetCmsState(msg.Empty())

        model = mujoco.MjModel.from_xml_path(str(SCRIPT_DIR / "quadruped.xml"))
        data = mujoco.MjData(model)
        body_id = mujoco.mj_name2id(model, mujoco.mjtObj.mjOBJ_BODY, "trunk")

        standing_mj = dart_to_mujoco(STANDING_POSE_DART)
        half_yaw = math.radians(args.start_yaw_deg) * 0.5
        data.qpos[0:3] = [args.start_x, args.start_y, 0.45]
        data.qpos[3:7] = [math.cos(half_yaw), 0.0, 0.0, math.sin(half_yaw)]
        data.qpos[7:23] = standing_mj
        data.qvel[:] = 0.0
        data.ctrl[:] = standing_mj
        mujoco.mj_forward(model, data)
        for _ in range(50):
            mujoco.mj_step(model, data)

        field = OdorField(
            source_xy=Vec2(args.source_x, args.source_y),
            wind_heading_rad=math.radians(args.wind_heading_deg),
            wind_speed=args.wind_speed,
        )
        sensors = make_default_sensors()
        policy = OdorPolicy()

        writer = write_csv_header(args.csv)
        plot_rows: list[dict[str, float | str]] = []
        render_frames: list[RenderFrame] = []
        try:
            standup_sent = False
            state_counts: Counter[str] = Counter()
            min_distance = float("inf")
            reached_at = None

            for control_step in range(args.control_steps):
                now_s = control_step / CONTROL_HZ
                sim_state = build_sim_state(data, now_s)
                stub.Step(sim_state)

                cms_state = stub.GetCmsState(msg.Empty())
                state_counts[str(cms_state.kind)] += 1
                if not standup_sent and cms_state.kind == CMS_STATE_KIND_GROUNDED:
                    stub.StandUp(msg.Empty())
                    standup_sent = True

                if cms_state.kind in (CMS_STATE_KIND_STANDING, CMS_STATE_KIND_WALKING):
                    robot_yaw = yaw_from_quaternion_wxyz(data.qpos[3:7])
                    local_wind = field.sample_velocity(Vec2(float(data.qpos[0]), float(data.qpos[1])), now_s)
                    for sensor in sensors:
                        sample_xy = get_sensor_world_xy(data, body_id, sensor.offset_body_xy)
                        concentration = field.concentration(sample_xy)
                        sensor.step(concentration, 1.0 / CONTROL_HZ, policy.drift_sigma)
                    walk_x, walk_y, walk_z, g_x, g_y = policy.step(
                        sensors,
                        now_s=now_s,
                        dt=1.0 / CONTROL_HZ,
                        yaw_rad=robot_yaw,
                        local_wind=local_wind,
                    )
                    stub.Walk(msg.Vector3(x=walk_x, y=walk_y, z=walk_z))
                else:
                    walk_x = walk_y = walk_z = 0.0
                    g_x = g_y = 0.0
                    local_wind = field.sample_velocity(Vec2(float(data.qpos[0]), float(data.qpos[1])), now_s)

                history = stub.Tick(msg.Empty())
                apply_history_to_model(history, model, data)

                for _ in range(SUBSTEPS):
                    mujoco.mj_step(model, data)

                robot_xy = Vec2(float(data.qpos[0]), float(data.qpos[1]))
                distance = math.hypot(robot_xy.x - field.source_xy.x, robot_xy.y - field.source_xy.y)
                min_distance = min(min_distance, distance)
                if reached_at is None and distance <= args.success_radius:
                    reached_at = now_s

                row = {
                    "time_s": f"{now_s:.2f}",
                    "robot_x_m": f"{robot_xy.x:.4f}",
                    "robot_y_m": f"{robot_xy.y:.4f}",
                    "distance_to_source_m": f"{distance:.4f}",
                    "cms_state_kind": str(cms_state.kind),
                    "odor_mode": policy.mode,
                    "walk_x": f"{walk_x:.4f}",
                    "walk_y": f"{walk_y:.4f}",
                    "walk_z": f"{walk_z:.4f}",
                    "g_x": f"{g_x:.4f}",
                    "g_y": f"{g_y:.4f}",
                }
                for sensor in sensors:
                    row[f"{sensor.name}_raw"] = f"{sensor.raw_value:.4f}"
                    row[f"{sensor.name}_baseline"] = f"{sensor.baseline_value:.4f}"
                    row[f"{sensor.name}_delta"] = f"{sensor.delta_value:.4f}"
                    row[f"{sensor.name}_slope"] = f"{sensor.slope_value:.4f}"
                writer.writerow(row)
                plot_rows.append(row.copy())
                if args.render_every > 0 and (control_step % args.render_every == 0 or reached_at is not None):
                    render_frames.append(
                        RenderFrame(
                            time_s=now_s,
                            qpos=np.array(data.qpos, copy=True),
                            robot_xy=robot_xy,
                            distance_to_source_m=distance,
                            odor_mode=policy.mode,
                            cms_state_kind=int(cms_state.kind),
                            sensor_deltas={sensor.name: max(sensor.delta_value, 0.0) for sensor in sensors},
                            local_wind_xy=local_wind,
                        )
                    )

                if reached_at is not None:
                    break
        finally:
            close_writer(writer)
            channel.close()

        plot_written = render_demo_plot(
            plot_rows,
            field=field,
            success_radius=args.success_radius,
            path=args.plot,
        )
        gif_written, mp4_written, storyboard_written = render_mujoco_animation(
            model,
            render_frames,
            field=field,
            success_radius=args.success_radius,
            gif_path=args.gif,
            mp4_path=args.mp4,
            storyboard_path=args.storyboard,
            render_robot=args.render_robot,
            go2w_xml_path=args.go2w_xml,
            width=args.render_width,
            height=args.render_height,
        )

        print(f"seed={args.seed}")
        print(f"render_robot={args.render_robot}")
        print(f"csv={args.csv}")
        if plot_written:
            print(f"plot={args.plot}")
        if gif_written:
            print(f"gif={args.gif}")
        if mp4_written:
            print(f"mp4={args.mp4}")
        if storyboard_written:
            print(f"storyboard={args.storyboard}")
        print(f"server_log={args.server_log}")
        print(f"start=({args.start_x:.2f},{args.start_y:.2f}) yaw_deg={args.start_yaw_deg:.1f}")
        print(f"source=({args.source_x:.2f},{args.source_y:.2f})")
        print(f"wind_heading_deg={args.wind_heading_deg:.1f}")
        print(f"wind_speed_mps={args.wind_speed:.2f}")
        print(f"reached_source={str(reached_at is not None).lower()}")
        if reached_at is not None:
            print(f"reached_at_s={reached_at:.2f}")
        print(f"min_distance_m={min_distance:.3f}")
        print(
            "cms_state_counts="
            + ",".join(f"{key}:{value}" for key, value in sorted(state_counts.items(), key=lambda item: item[0]))
        )
        return 0
    finally:
        shutdown_server(process)


if __name__ == "__main__":
    raise SystemExit(main())
