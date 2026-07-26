"""Profile-driven headless MuJoCo validation for Brainstem ONNX policies."""
import argparse
from collections import deque
import json
import math
from pathlib import Path
import sys
from typing import NamedTuple

import mujoco
import numpy as np
import onnxruntime as ort
from scipy.spatial.transform import Rotation as R

REPO_ROOT = Path(__file__).resolve().parents[2]
DOF_IDS = [7,8,9, 11,12,13, 15,16,17, 19,20,21, 10,14,18,22]
DOF_VEL = [6,7,8, 10,11,12, 14,15,16, 18,19,20, 9,13,17,21]

class Profile(NamedTuple):
    observation_type: str
    body_height_command: float | None
    min_body_height_command: float | None
    max_body_height_command: float | None
    velocity_min: np.ndarray
    velocity_max: np.ndarray
    standing_pose: np.ndarray
    stand_up_pose: np.ndarray
    policy_default_pose: np.ndarray
    action_scale: np.ndarray
    infer_kp: np.ndarray
    infer_kd: np.ndarray
    model_path: Path
    @property
    def frame_dim(self):
        return 58 if self.observation_type == "bodyHeight" else 57

def _vector(raw, name, length):
    value = np.asarray(raw, dtype=np.float64)
    if value.shape != (length,):
        raise ValueError(f"{name} must contain exactly {length} numbers")
    if not np.isfinite(value).all():
        raise ValueError(f"{name} must contain only finite numbers")
    return value

def _optional_finite(raw, name):
    if raw is None:
        return None
    value = float(raw)
    if not math.isfinite(value):
        raise ValueError(f"{name} must be finite")
    return value

def parse_profile(raw, repo_root=REPO_ROOT):
    observation_type = raw.get("observationType", "standard")
    if observation_type not in ("standard", "bodyHeight"):
        raise ValueError("observationType must be 'standard' or 'bodyHeight'")
    height = _optional_finite(raw.get("bodyHeightCommand"), "bodyHeightCommand")
    min_height = _optional_finite(raw.get("minBodyHeightCommand"), "minBodyHeightCommand")
    max_height = _optional_finite(raw.get("maxBodyHeightCommand"), "maxBodyHeightCommand")
    if observation_type == "bodyHeight":
        if height is None or min_height is None or max_height is None:
            raise ValueError("bodyHeight profiles require command, min, and max height")
        if min_height > max_height or not min_height <= height <= max_height:
            raise ValueError("bodyHeightCommand must be within its min/max range")
    velocity_min = _vector(raw.get("velocityCommandMin", [-0.5,-0.3,-1.0]), "velocityCommandMin", 3)
    velocity_max = _vector(raw.get("velocityCommandMax", [0.5,0.3,1.0]), "velocityCommandMax", 3)
    if np.any(velocity_min > velocity_max):
        raise ValueError("velocityCommandMin must not exceed velocityCommandMax")
    model_path = Path(raw["modelPath"])
    if not model_path.is_absolute():
        model_path = Path(repo_root) / model_path
    standing_pose = _vector(raw["standingPose"], "standingPose", 16)
    stand_up_pose = _vector(
        raw.get("standUpPose", standing_pose), "standUpPose", 16
    )
    policy_default_pose = _vector(
        raw.get("policyDefaultPose", standing_pose), "policyDefaultPose", 16
    )
    return Profile(
        observation_type=observation_type,
        body_height_command=height,
        min_body_height_command=min_height,
        max_body_height_command=max_height,
        velocity_min=velocity_min,
        velocity_max=velocity_max,
        standing_pose=standing_pose,
        stand_up_pose=stand_up_pose,
        policy_default_pose=policy_default_pose,
        action_scale=_vector(raw["actionScale"], "actionScale", 4),
        infer_kp=_vector(raw["inferKp"], "inferKp", 16),
        infer_kd=_vector(raw["inferKd"], "inferKd", 16),
        model_path=model_path.resolve(),
    )

def load_profile(path, repo_root=REPO_ROOT):
    with Path(path).open(encoding="utf-8") as stream:
        return parse_profile(json.load(stream), repo_root)

def resolve_commands(profile, height=None, vx=None, vy=None, vyaw=None):
    height_value = profile.body_height_command if height is None else height
    if height_value is None:
        height_value = 0.0
    values = np.asarray([height_value, 0.0 if vx is None else vx,
                         0.0 if vy is None else vy, 0.0 if vyaw is None else vyaw],
                        dtype=np.float64)
    if not np.isfinite(values).all():
        raise ValueError("height and velocity commands must be finite")
    velocity = np.clip(values[1:], profile.velocity_min, profile.velocity_max)
    if profile.observation_type == "bodyHeight":
        height_value = float(np.clip(values[0], profile.min_body_height_command,
                                     profile.max_body_height_command))
    else:
        height_value = float(values[0])
    return (height_value, *map(float, velocity))

def compose_observation(gyro, projected_gravity, velocity_command, joint_position,
                        joint_velocity, last_action, *, height, observation_type):
    observation = np.concatenate([gyro, projected_gravity, velocity_command,
                                  joint_position, joint_velocity, last_action]).astype(np.float32)
    if observation.shape != (57,):
        raise ValueError(f"standard observation must have 57 values, got {observation.size}")
    if observation_type == "bodyHeight":
        return np.append(observation, np.float32(height)).astype(np.float32)
    if observation_type != "standard":
        raise ValueError(f"unsupported observation type: {observation_type}")
    return observation

def infer_history_size(input_dim, frame_dim):
    if isinstance(input_dim, np.integer):
        input_dim = int(input_dim)
    if not isinstance(input_dim, int) or input_dim <= 0:
        raise ValueError(f"ONNX input dimension must be a positive integer, got {input_dim!r}")
    if input_dim % frame_dim:
        raise ValueError(f"ONNX input dimension {input_dim} is not divisible by frame dimension {frame_dim}")
    return input_dim // frame_dim

def initialize_history(observation, history_size):
    return deque((observation.copy() for _ in range(history_size)), maxlen=history_size)

def flatten_history(history):
    return np.concatenate(list(history)).astype(np.float32).reshape(1, -1)

def validate_step(state, action, trunk_height, min_trunk_height):
    if not np.isfinite(state).all() or not np.isfinite(action).all():
        raise RuntimeError("non-finite simulation state or policy action")
    if not math.isfinite(float(trunk_height)):
        raise RuntimeError("non-finite trunk height")
    if trunk_height < min_trunk_height:
        raise RuntimeError(f"robot fallen: trunk height {trunk_height:.3f} < {min_trunk_height:.3f}")

def relative_joint_position(joint_position, profile):
    q = _vector(joint_position, "jointPosition", 16) - profile.policy_default_pose
    q[-4:] = 0.0
    return q


def get_obs(data, velocity_command, last_action, profile, height):
    q = relative_joint_position(data.qpos[DOF_IDS], profile)
    dq = data.qvel[DOF_VEL].astype(np.float64) * 0.05
    imu_quat = data.sensor("orientation").data[[1,2,3,0]].astype(np.float64)
    imu_rotation = R.from_quat(imu_quat)
    gravity = imu_rotation.apply(np.array([0.,0.,-1.]), inverse=True)
    gyro_local = data.sensor("angular-velocity").data.astype(np.float64)
    base_rotation = R.from_quat(data.qpos[3:7][[1,2,3,0]].astype(np.float64))
    gyro = base_rotation.apply(imu_rotation.apply(gyro_local), inverse=True) * 0.25
    return compose_observation(gyro, gravity, velocity_command, q, dq, last_action,
                               height=height, observation_type=profile.observation_type)

def _input_dim(session):
    shape = session.get_inputs()[0].shape
    if len(shape) != 2:
        raise ValueError(f"ONNX input must be rank 2, got {shape}")
    return shape[1]

def _scaled_action(action, scales):
    scaled = np.empty(16, dtype=np.float32)
    for leg in range(4):
        index = leg * 3
        scaled[index:index+3] = action[index:index+3] * scales[:3]
    scaled[12:] = action[12:] * scales[3]
    return scaled


def policy_target(action, profile):
    action = _vector(action, "policyAction", 16)
    return profile.policy_default_pose + _scaled_action(action, profile.action_scale)

def run(args):
    profile = load_profile(args.profile, REPO_ROOT)
    model_path = Path(args.model) if args.model else profile.model_path
    if not model_path.is_absolute():
        model_path = REPO_ROOT / model_path
    model_path = model_path.resolve()
    if not model_path.is_file():
        raise FileNotFoundError(f"ONNX model not found: {model_path}")
    xml_path = Path(args.xml)
    if not xml_path.is_absolute():
        xml_path = REPO_ROOT / xml_path
    model = mujoco.MjModel.from_xml_path(str(xml_path.resolve()))
    model.opt.timestep = 0.005
    data = mujoco.MjData(model)
    height, vx, vy, vyaw = resolve_commands(profile, args.height, args.vx, args.vy, args.vyaw)
    velocity_command = np.array([vx,vy,vyaw], dtype=np.float64)
    session = ort.InferenceSession(str(model_path), providers=["CPUExecutionProvider"])
    input_info = session.get_inputs()[0]
    history_size = infer_history_size(_input_dim(session), profile.frame_dim)
    print(f"ONNX: {input_info.name}, frame={profile.frame_dim}, history={history_size}, model={model_path}")
    print(f"Command: height={height:.3f}, velocity=({vx:.3f}, {vy:.3f}, {vyaw:.3f})")
    data.qpos[:3] = [0.,0.,0.5]
    data.qpos[3:7] = [1.,0.,0.,0.]
    data.qpos[DOF_IDS] = profile.stand_up_pose
    data.qvel[:] = 0.
    mujoco.mj_forward(model, data)
    target = profile.stand_up_pose.copy()
    action = np.zeros(16, dtype=np.float32)
    last_action = np.zeros(16, dtype=np.float32)
    history = initialize_history(get_obs(data, velocity_command, last_action, profile, height), history_size)
    renderer = None
    frames = []
    if args.render:
        renderer = mujoco.Renderer(model, width=640, height=480)
        camera = mujoco.MjvCamera()
        camera.type = mujoco.mjtCamera.mjCAMERA_TRACKING
        camera.trackbodyid = model.body("trunk").id
        camera.distance, camera.azimuth, camera.elevation = 2.5, 180, -20
    dt, decimation = 0.005, 4
    sim_steps = int(args.duration / dt)
    min_height_seen = float(data.qpos[2])
    max_action_seen = 0.0
    print(f"Running {sim_steps} steps ({args.duration}s), decimation={decimation}")
    try:
        for step in range(sim_steps):
            if step % decimation == 0:
                observation = get_obs(data, velocity_command, last_action, profile, height)
                if step:
                    history.append(observation.copy())
                policy_input = flatten_history(history)
                action = np.asarray(session.run(None, {input_info.name: policy_input})[0],
                                    dtype=np.float32).reshape(-1)
                if action.shape != (16,):
                    raise RuntimeError(f"policy output must contain 16 actions, got {action.shape}")
                validate_step(observation, action, float(data.qpos[2]), args.min_trunk_height)
                max_action_seen = max(max_action_seen, float(np.max(np.abs(action))))
                last_action = action.copy()
                if step > 100:
                    target = policy_target(action, profile)
            q, dq = data.qpos[DOF_IDS], data.qvel[DOF_VEL]
            leg_tau = profile.infer_kp[:12] * (target[:12]-q[:12]) - profile.infer_kd[:12]*dq[:12]
            wheel_tau = profile.infer_kp[12:] * (target[12:]-q[12:]) + profile.infer_kd[12:] * (target[12:]-dq[12:])
            torque = np.clip(np.concatenate([leg_tau,wheel_tau]), -120., 120.)
            validate_step(np.concatenate([data.qpos,data.qvel]), torque, float(data.qpos[2]), args.min_trunk_height)
            data.ctrl[:] = torque
            mujoco.mj_step(model, data)
            validate_step(np.concatenate([data.qpos,data.qvel]), action,
                          float(data.qpos[2]), args.min_trunk_height)
            min_height_seen = min(min_height_seen, float(data.qpos[2]))
            if renderer and step % decimation == 0:
                renderer.update_scene(data, camera=camera)
                frames.append(renderer.render().copy())
            if (step+1) % int(1./dt) == 0:
                print(f"  [{(step+1)*dt:.1f}s] pos=({data.qpos[0]:.3f}, {data.qpos[1]:.3f}, {data.qpos[2]:.3f})")
    finally:
        if renderer:
            renderer.close()
    x, y = float(data.qpos[0]), float(data.qpos[1])
    metrics = {"x":x, "y":y, "displacement":math.hypot(x,y),
               "finalTrunkHeight":float(data.qpos[2]), "minTrunkHeight":min_height_seen,
               "maxAbsAction":max_action_seen, "historySize":history_size,
               "frameDim":profile.frame_dim}
    print("METRICS " + json.dumps(metrics, sort_keys=True))
    if args.render and frames:
        output_dir = REPO_ROOT / "sim" / "output"
        output_dir.mkdir(parents=True, exist_ok=True)
        try:
            import imageio
            video_path = output_dir / "walk_ref.mp4"
            imageio.mimsave(str(video_path), frames, fps=50)
            print(f"Video: {video_path} ({len(frames)} frames)")
        except ImportError:
            print(f"imageio not installed ({len(frames)} frames)")
    return metrics

def build_parser():
    parser = argparse.ArgumentParser()
    parser.add_argument("--profile", required=True, help="RobotProfile JSON")
    parser.add_argument("--xml", default="sim/robot/quadruped_v3.xml")
    parser.add_argument("--model", help="override profile modelPath")
    parser.add_argument("--height", type=float)
    parser.add_argument("--vx", type=float)
    parser.add_argument("--vy", type=float)
    parser.add_argument("--vyaw", type=float)
    parser.add_argument("--duration", type=float, default=10.0)
    parser.add_argument("--min-trunk-height", type=float, default=0.12)
    parser.add_argument("--render", action="store_true")
    return parser

if __name__ == "__main__":
    try:
        run(build_parser().parse_args())
    except Exception as error:
        print(f"ERROR: {error}", file=sys.stderr)
        sys.exit(2)
