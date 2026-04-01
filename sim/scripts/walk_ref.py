"""
1:1 复刻参考仿真代码，PyTorch -> ONNX, 单帧 -> 5帧 history。
其余逻辑完全不改。
"""
import math
import numpy as np
import mujoco
import onnxruntime as ort
from scipy.spatial.transform import Rotation as R
from collections import deque
import argparse, os, sys
from pathlib import Path

# ── 关节索引 (和参考代码 100% 一致) ──────────────────────────
dof_ids = [7,8,9, 11,12,13, 15,16,17, 19,20,21, 10,14,18,22]
dof_vel = [6,7,8, 10,11,12, 14,15,16, 18,19,20, 9,13,17,21]

# ── 默认角度 (和参考代码 100% 一致) ──────────────────────────
default_joint_angles = {
    "FR_hip_joint": -0.1,
    "FR_thigh_joint": -0.8,
    "FR_calf_joint": 1.8,
    "FR_foot_joint": 0.0,
    "FL_hip_joint": 0.1,
    "FL_thigh_joint": 0.8,
    "FL_calf_joint": -1.8,
    "FL_foot_joint": 0.0,
    "RR_hip_joint": 0.1,
    "RR_thigh_joint": 0.8,
    "RR_calf_joint": -1.8,
    "RR_foot_joint": 0.0,
    "RL_hip_joint": -0.1,
    "RL_thigh_joint": -0.8,
    "RL_calf_joint": 1.8,
    "RL_foot_joint": 0.0,
}

hip_scale = 0.125
thigh_calf_scale = 0.25
wheel_scale = 5.0

default_angle = np.array([
    default_joint_angles["FR_hip_joint"],
    default_joint_angles["FR_thigh_joint"],
    default_joint_angles["FR_calf_joint"],
    default_joint_angles["FL_hip_joint"],
    default_joint_angles["FL_thigh_joint"],
    default_joint_angles["FL_calf_joint"],
    default_joint_angles["RR_hip_joint"],
    default_joint_angles["RR_thigh_joint"],
    default_joint_angles["RR_calf_joint"],
    default_joint_angles["RL_hip_joint"],
    default_joint_angles["RL_thigh_joint"],
    default_joint_angles["RL_calf_joint"],
    0.0, 0.0, 0.0, 0.0
], dtype=np.double)


class Cmd:
    vx = 0.3
    vy = 0.0
    dyaw = 0.0


def get_obs(data, vel_cmd, last_action):
    """和参考代码 100% 一致的 obs 构建。"""
    q = data.qpos[dof_ids].astype(np.double)
    q = q - default_angle
    dq = data.qvel[dof_vel].astype(np.double) * 0.05
    q[-4:] = 0.0

    imu_quat = data.sensor('orientation').data[[1, 2, 3, 0]].astype(np.double)
    r_imu = R.from_quat(imu_quat)
    proj = r_imu.apply(np.array([0., 0., -1.]), inverse=True).astype(np.double)

    gyro_local = data.sensor('angular-velocity').data.astype(np.double)
    base_quat = data.qpos[3:7][[1, 2, 3, 0]].astype(np.double)
    r_base = R.from_quat(base_quat)
    gyro_world = r_imu.apply(gyro_local)
    gyro = r_base.apply(gyro_world, inverse=True) * 0.25

    obs = np.concatenate([
        gyro,
        proj,
        np.array([vel_cmd.vx, vel_cmd.vy, vel_cmd.dyaw]),
        q,
        dq,
        last_action
    ]).astype(np.float32)

    return obs


def pd_control(target_q, q, kp, target_dq, dq, kd):
    return kp * (target_q - q) + kd * (target_dq - dq)


def run(args):
    model = mujoco.MjModel.from_xml_path(args.xml)
    model.opt.timestep = 0.005  # 和参考代码一致
    data = mujoco.MjData(model)

    decimation = 4  # 和参考代码一致
    dt = 0.005

    # ONNX
    sess = ort.InferenceSession(args.model)
    input_name = sess.get_inputs()[0].name
    obs_dim = 57
    history_size = sess.get_inputs()[0].shape[1] // obs_dim
    print(f"ONNX: {input_name}, history={history_size}")

    # Init
    data.qpos[:3] = [0, 0, 0.5]
    data.qpos[3:7] = [1, 0, 0, 0]
    data.qpos[dof_ids] = default_angle.copy()
    data.qvel[:] = 0.0
    mujoco.mj_step(model, data)  # 初始化 sensor 数据

    target_q = np.zeros(16, dtype=np.float32)
    action = np.zeros(16, dtype=np.float32)
    last_action = np.zeros(16, dtype=np.float32)

    # History buffer
    obs_history = deque(maxlen=history_size)

    vel_cmd = Cmd()
    vel_cmd.vx = args.vx
    vel_cmd.vy = args.vy
    vel_cmd.dyaw = args.vyaw

    count_lowlevel = 0
    sim_steps = int(args.duration / dt)

    # 录帧
    renderer = None
    frames = []
    if args.render:
        renderer = mujoco.Renderer(model, width=640, height=480)
        cam = mujoco.MjvCamera()
        cam.type = mujoco.mjtCamera.mjCAMERA_TRACKING
        cam.trackbodyid = model.body('trunk').id
        cam.distance = 2.5
        cam.azimuth = 180
        cam.elevation = -20

    print(f"Running {sim_steps} steps ({args.duration}s), decimation={decimation}")

    for i in range(sim_steps):
        if count_lowlevel % decimation == 0:
            obs = get_obs(data, vel_cmd, last_action)
            obs_history.append(obs.copy())

            # 填充 history 如果不够
            while len(obs_history) < history_size:
                obs_history.appendleft(obs.copy())

            obs_flat = np.concatenate(list(obs_history)).astype(np.float32).reshape(1, -1)
            raw_action = sess.run(None, {input_name: obs_flat})[0].squeeze()
            action[:] = raw_action

            if count_lowlevel > 100:
                scaled_action = np.zeros(16, dtype=np.float32)
                for j in range(4):
                    base_idx = j * 3
                    scaled_action[base_idx + 0] = action[base_idx + 0] * hip_scale
                    scaled_action[base_idx + 1] = action[base_idx + 1] * thigh_calf_scale
                    scaled_action[base_idx + 2] = action[base_idx + 2] * thigh_calf_scale
                scaled_action[12:] = action[12:] * wheel_scale

                target_q = scaled_action + default_angle
                last_action = action.copy()
            else:
                target_q = default_angle.copy()
                last_action = action.copy()  # 和参考一样，站立也保存 action

            # PD 控制 (训练增益: hip=70/15, thigh=100/15, calf=120/20)
        q = data.qpos[dof_ids]
        dq = data.qvel[dof_vel]
        kp = np.array([70,100,120, 70,100,120, 70,100,120, 70,100,120], dtype=np.float64)
        kd = np.array([15, 15, 20, 15, 15, 20, 15, 15, 20, 15, 15, 20], dtype=np.float64)
        tau_leg = kp * (target_q[:12] - q[:12]) - kd * dq[:12]
        tau_wheel = 1 * (target_q[12:] - dq[12:])
        tau = np.concatenate([tau_leg, tau_wheel])
        tau = np.clip(tau, -120, 120)
        data.ctrl[:] = tau

        mujoco.mj_step(model, data)
        count_lowlevel += 1

        if renderer and count_lowlevel % decimation == 0:
            renderer.update_scene(data, camera=cam)
            frames.append(renderer.render().copy())

        if count_lowlevel % int(1.0 / dt) == 0:
            sec = count_lowlevel * dt
            x, y, z = data.qpos[0], data.qpos[1], data.qpos[2]
            mode = "WALK" if count_lowlevel > 100 else "STAND"
            print(f"  [{sec:.1f}s] pos=({x:.3f}, {y:.3f}, {z:.3f}) {mode}")

    x, y = data.qpos[0], data.qpos[1]
    print(f"\nFinal: x={x:.3f} y={y:.3f} disp={math.sqrt(x**2+y**2):.3f}")

    if renderer and frames:
        SCRIPT_DIR = Path(__file__).resolve().parent
        out_dir = SCRIPT_DIR.parent / "output"
        os.makedirs(out_dir, exist_ok=True)
        video_path = str(out_dir / "walk_ref.mp4")
        try:
            import imageio
            imageio.mimsave(video_path, frames, fps=50)
            print(f"Video: {video_path} ({len(frames)} frames)")
        except ImportError:
            print(f"imageio not installed ({len(frames)} frames)")
        renderer.close()


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument("--xml", default="sim/robot/quadruped_v3.xml")
    parser.add_argument("--model", default="model/policy_260106.onnx")
    parser.add_argument("--vx", type=float, default=0.3)
    parser.add_argument("--vy", type=float, default=0.0)
    parser.add_argument("--vyaw", type=float, default=0.0)
    parser.add_argument("--duration", type=float, default=10.0)
    parser.add_argument("--render", action="store_true")
    args = parser.parse_args()
    run(args)
