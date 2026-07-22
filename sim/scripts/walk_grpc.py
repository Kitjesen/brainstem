"""End-to-end MuJoCo client for the Brainstem simulation gRPC server."""

import argparse
import json
import math
from pathlib import Path
import sys
import time

import grpc
import mujoco
import numpy as np

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parents[1]
API_ROOT = REPO_ROOT / "brainstem_api" / "python"
if str(API_ROOT) not in sys.path:
    sys.path.insert(0, str(API_ROOT))

from brainstem_api import cms_pb2, cms_pb2_grpc, common_pb2
from google.protobuf import duration_pb2, empty_pb2

from walk_ref import (
    DOF_IDS,
    DOF_VEL,
    load_profile,
    resolve_commands,
    validate_step,
)

CMS_GROUNDED = cms_pb2.CMS_STATE_KIND_GROUNDED
CMS_STANDING = cms_pb2.CMS_STATE_KIND_STANDING
CMS_WALKING = cms_pb2.CMS_STATE_KIND_WALKING


def build_sim_state(data, elapsed_s):
    """Convert MuJoCo state to the current brainstem.api.v1 SimState."""
    raw_quaternion = data.sensor("orientation").data
    gyro = data.sensor("angular-velocity").data
    seconds = int(elapsed_s)
    nanos = int(round((elapsed_s - seconds) * 1e9))
    if nanos == 1_000_000_000:
        seconds += 1
        nanos = 0

    # MuJoCo framequat is body-to-world. Dart rotates world gravity directly,
    # so the injected quaternion must be its conjugate (world-to-body).
    return common_pb2.SimState(
        gyroscope=common_pb2.Vector3(
            x=float(gyro[0]), y=float(gyro[1]), z=float(gyro[2])
        ),
        quaternion=common_pb2.Quaternion(
            w=float(raw_quaternion[0]),
            x=-float(raw_quaternion[1]),
            y=-float(raw_quaternion[2]),
            z=-float(raw_quaternion[3]),
        ),
        joint_position=common_pb2.Matrix4(
            values=[float(value) for value in data.qpos[DOF_IDS]]
        ),
        joint_velocity=common_pb2.Matrix4(
            values=[float(value) for value in data.qvel[DOF_VEL]]
        ),
        timestamp=duration_pb2.Duration(seconds=seconds, nanos=nanos),
    )


def start_walking(stub, height, velocity, timeout):
    stub.SetBodyHeight(
        cms_pb2.BodyHeightCommand(meters=float(height)), timeout=timeout
    )
    stub.Walk(
        common_pb2.Vector3(
            x=float(velocity[0]), y=float(velocity[1]), z=float(velocity[2])
        ),
        timeout=timeout,
    )


def validate_history(history, expected_observation_dim=None, expected_height=None):
    fields = {
        "next_action": history.next_action.values,
        "kp": history.kp.values,
        "kd": history.kd.values,
    }
    for name, values in fields.items():
        if len(values) != 16:
            raise RuntimeError(f"history {name} must contain 16 values, got {len(values)}")
        if not np.isfinite(values).all():
            raise RuntimeError(f"history {name} contains non-finite values")

    if expected_observation_dim is not None:
        if len(history.observation) != expected_observation_dim:
            raise RuntimeError(
                "history observation must contain "
                f"{expected_observation_dim} values, got {len(history.observation)}"
            )
        if not np.isfinite(history.observation).all():
            raise RuntimeError("history observation contains non-finite values")
    if expected_height is not None:
        if not math.isfinite(history.body_height_command):
            raise RuntimeError("history body height is non-finite")
        if not math.isclose(
            history.body_height_command, expected_height, rel_tol=0.0, abs_tol=1e-6
        ):
            raise RuntimeError(
                f"history body height {history.body_height_command} "
                f"does not match requested {expected_height}"
            )

def active_min_trunk_height(cms_kind, configured_minimum):
    if cms_kind in (CMS_STANDING, CMS_WALKING):
        return configured_minimum
    return 0.0


def compute_torque(target, position, velocity, kp, kd):
    arrays = [
        np.asarray(value, dtype=np.float64)
        for value in (target, position, velocity, kp, kd)
    ]
    if any(value.shape != (16,) for value in arrays):
        raise RuntimeError("target, state, kp, and kd must each contain 16 values")
    if not all(np.isfinite(value).all() for value in arrays):
        raise RuntimeError("non-finite target, state, or PD gain")
    target, position, velocity, kp, kd = arrays
    torque = np.empty(16, dtype=np.float64)
    torque[:12] = (
        kp[:12] * (target[:12] - position[:12]) - kd[:12] * velocity[:12]
    )
    torque[12:] = (
        kp[12:] * (target[12:] - position[12:])
        + kd[12:] * (target[12:] - velocity[12:])
    )
    if not np.isfinite(torque).all():
        raise RuntimeError("non-finite control torque")
    return torque


def _load_sim_profile(path):
    profile_path = Path(path)
    if not profile_path.is_absolute():
        profile_path = REPO_ROOT / profile_path
    with profile_path.open(encoding="utf-8") as stream:
        raw = json.load(stream)
    profile = load_profile(profile_path, REPO_ROOT)
    sitting_pose = np.asarray(raw["sittingPose"], dtype=np.float64)
    if sitting_pose.shape != (16,) or not np.isfinite(sitting_pose).all():
        raise ValueError("sittingPose must contain exactly 16 finite values")
    configured_history = int(raw.get("_historySize", 1))
    if configured_history < 1:
        raise ValueError("_historySize must be positive")
    return profile, sitting_pose, configured_history


def connect_stub(host, port, connect_timeout):
    target = f"{host}:{port}"
    channel = grpc.insecure_channel(target)
    deadline = time.monotonic() + connect_timeout
    last_error = None
    while time.monotonic() < deadline:
        try:
            grpc.channel_ready_future(channel).result(
                timeout=min(1.0, max(0.05, deadline - time.monotonic()))
            )
            return channel, cms_pb2_grpc.RobotControlStub(channel)
        except grpc.FutureTimeoutError as error:
            last_error = error
    channel.close()
    raise TimeoutError(
        f"Brainstem gRPC server at {target} was not ready within "
        f"{connect_timeout:.1f}s"
    ) from last_error


def run(args):
    profile, sitting_pose, history_size = _load_sim_profile(args.profile)
    height, vx, vy, vyaw = resolve_commands(
        profile, args.height, args.vx, args.vy, args.vyaw
    )
    expected_observation_dim = profile.frame_dim * history_size

    xml_path = Path(args.xml)
    if not xml_path.is_absolute():
        xml_path = REPO_ROOT / xml_path
    model = mujoco.MjModel.from_xml_path(str(xml_path.resolve()))
    model.opt.timestep = 0.005
    data = mujoco.MjData(model)
    data.qpos[:3] = [0.0, 0.0, args.initial_trunk_height]
    data.qpos[3:7] = [1.0, 0.0, 0.0, 0.0]
    data.qpos[DOF_IDS] = sitting_pose
    data.qvel[:] = 0.0
    mujoco.mj_forward(model, data)

    channel, stub = connect_stub(args.host, args.port, args.connect_timeout)
    renderer = None
    frames = []
    if args.render:
        renderer = mujoco.Renderer(model, width=640, height=480)
        camera = mujoco.MjvCamera()
        camera.type = mujoco.mjtCamera.mjCAMERA_TRACKING
        camera.trackbodyid = model.body("trunk").id
        camera.distance, camera.azimuth, camera.elevation = 2.5, 180, -20

    empty = empty_pb2.Empty()
    rpc_timeout = args.rpc_timeout
    initial_state = stub.GetCmsState(empty, timeout=rpc_timeout)
    if initial_state.kind != CMS_GROUNDED:
        raise RuntimeError(
            f"server must start Grounded, got CMS state {initial_state.kind}"
        )
    current_cms_kind = initial_state.kind

    target = sitting_pose.copy()
    kp = profile.infer_kp.copy()
    kd = profile.infer_kd.copy()
    standup_sent = False
    walk_sent = False
    walking_ticks = 0
    observation_dim_seen = None
    min_height_seen = float(data.qpos[2])
    min_active_height_seen = float("inf")
    max_torque_seen = 0.0
    dt = 0.005
    decimation = 4
    sim_steps = int(args.duration / dt)
    if sim_steps < 1:
        raise ValueError("duration must be at least one MuJoCo timestep")
    print(
        f"Connected to {args.host}:{args.port}; profile={args.profile}; "
        f"expected observation={expected_observation_dim}"
    )

    try:
        for step in range(sim_steps):
            if step % decimation == 0:
                state_vector = np.concatenate([data.qpos, data.qvel])
                validate_step(
                    state_vector, target, float(data.qpos[2]),
                    active_min_trunk_height(current_cms_kind, args.min_trunk_height)
                )
                stub.Step(build_sim_state(data, step * dt), timeout=rpc_timeout)
                cms_state = stub.GetCmsState(empty, timeout=rpc_timeout)
                current_cms_kind = cms_state.kind

                if not standup_sent and cms_state.kind == CMS_GROUNDED:
                    stub.StandUp(empty, timeout=rpc_timeout)
                    standup_sent = True
                elif standup_sent and not walk_sent and cms_state.kind == CMS_STANDING:
                    start_walking(
                        stub,
                        height,
                        (vx, vy, vyaw),
                        timeout=rpc_timeout,
                    )
                    walk_sent = True

                history = stub.Tick(empty, timeout=rpc_timeout)
                validate_history(history)
                target = np.asarray(history.next_action.values, dtype=np.float64)
                kp = np.asarray(history.kp.values, dtype=np.float64)
                kd = np.asarray(history.kd.values, dtype=np.float64)

                if cms_state.kind == CMS_WALKING:
                    validate_history(
                        history,
                        expected_observation_dim=expected_observation_dim,
                        expected_height=height,
                    )
                    walking_ticks += 1
                    observation_dim_seen = len(history.observation)

            position = data.qpos[DOF_IDS]
            velocity = data.qvel[DOF_VEL]
            torque = np.clip(
                compute_torque(target, position, velocity, kp, kd), -120.0, 120.0
            )
            max_torque_seen = max(max_torque_seen, float(np.max(np.abs(torque))))
            data.ctrl[:] = torque
            mujoco.mj_step(model, data)
            active_minimum = active_min_trunk_height(
                current_cms_kind, args.min_trunk_height)
            validate_step(
                np.concatenate([data.qpos, data.qvel]),
                torque,
                float(data.qpos[2]),
                active_min_trunk_height(
                    current_cms_kind, args.min_trunk_height),
            )
            min_height_seen = min(min_height_seen, float(data.qpos[2]))
            if active_minimum > 0.0:
                min_active_height_seen = min(
                    min_active_height_seen, float(data.qpos[2]))

            if renderer and step % decimation == 0:
                renderer.update_scene(data, camera=camera)
                frames.append(renderer.render().copy())

            if (step + 1) % int(1.0 / dt) == 0:
                state = stub.GetCmsState(empty, timeout=rpc_timeout)
                print(
                    f"[{(step + 1) * dt:.1f}s] state={state.kind} "
                    f"pos=({data.qpos[0]:.3f}, {data.qpos[1]:.3f}, "
                    f"{data.qpos[2]:.3f})"
                )
    finally:
        if renderer:
            renderer.close()
        channel.close()

    if not standup_sent:
        raise RuntimeError("StandUp was never accepted by the simulation server")
    if not walk_sent or walking_ticks == 0:
        raise RuntimeError(
            "server never reached a validated Walking inference tick; "
            "increase --duration or inspect the FSM"
        )

    metrics = {
        "x": float(data.qpos[0]),
        "y": float(data.qpos[1]),
        "finalTrunkHeight": float(data.qpos[2]),
        "minTrunkHeight": min_height_seen,
        "minActiveTrunkHeight": min_active_height_seen,
        "maxAbsTorque": max_torque_seen,
        "walkingTicks": walking_ticks,
        "observationDim": observation_dim_seen,
        "bodyHeightCommand": height,
    }
    metrics["displacement"] = math.hypot(metrics["x"], metrics["y"])
    print("METRICS " + json.dumps(metrics, sort_keys=True))

    if args.render and frames:
        output_dir = REPO_ROOT / "sim" / "output"
        output_dir.mkdir(parents=True, exist_ok=True)
        try:
            import imageio

            video_path = output_dir / "walk_grpc.mp4"
            imageio.mimsave(str(video_path), frames, fps=50)
            print(f"Video: {video_path} ({len(frames)} frames)")
        except ImportError:
            print(f"imageio not installed ({len(frames)} frames)")
    return metrics


def build_parser():
    parser = argparse.ArgumentParser()
    parser.add_argument("--profile", required=True, help="RobotProfile JSON")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=13145)
    parser.add_argument("--xml", default="sim/robot/quadruped_v3.xml")
    parser.add_argument("--height", type=float)
    parser.add_argument("--vx", type=float)
    parser.add_argument("--vy", type=float)
    parser.add_argument("--vyaw", type=float)
    parser.add_argument("--duration", type=float, default=8.0)
    parser.add_argument("--initial-trunk-height", type=float, default=0.15)
    parser.add_argument("--min-trunk-height", type=float, default=0.10)
    parser.add_argument("--connect-timeout", type=float, default=30.0)
    parser.add_argument("--rpc-timeout", type=float, default=3.0)
    parser.add_argument("--render", action="store_true")
    return parser


if __name__ == "__main__":
    try:
        run(build_parser().parse_args())
    except Exception as error:
        print(f"ERROR: {error}", file=sys.stderr)
        sys.exit(2)
