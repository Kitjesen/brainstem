"""
Xbox 手柄控制 MuJoCo 机器狗。

左摇杆: 前后/左右移动
右摇杆 X: 旋转 (yaw)
LT/RT: 速度倍率 (0.5x / 1.5x)

用法:
    python sim/walk_xbox.py
    python sim/walk_xbox.py --render   (录视频)

依赖: pip install pygame mujoco onnxruntime scipy numpy
"""
import math
import numpy as np
import mujoco
import mujoco_viewer
import onnxruntime as ort
import pygame
import argparse, os, sys, time
from pathlib import Path
from scipy.spatial.transform import Rotation as R
from collections import deque

SCRIPT_DIR = Path(__file__).resolve().parent

# ── 关节索引 ─────────────────────────────────────────────────
dof_ids = [7,8,9, 11,12,13, 15,16,17, 19,20,21, 10,14,18,22]
dof_vel = [6,7,8, 10,11,12, 14,15,16, 18,19,20, 9,13,17,21]

default_angle = np.array([
    -0.1, -0.8, 1.8,
     0.1,  0.8, -1.8,
     0.1,  0.8, -1.8,
    -0.1, -0.8, 1.8,
     0.0,  0.0,  0.0, 0.0,
], dtype=np.double)

hip_scale = 0.125
thigh_calf_scale = 0.25
wheel_scale = 5.0

DEADZONE = 0.08


def get_obs(data, cmd_vx, cmd_vy, cmd_vyaw, last_action):
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
        gyro, proj,
        np.array([cmd_vx, cmd_vy, cmd_vyaw]),
        q, dq, last_action
    ]).astype(np.float32)
    return obs


def apply_deadzone(val):
    return 0.0 if abs(val) < DEADZONE else val


def run(args):
    # ── pygame + joystick ─────────────────────────────────────
    pygame.init()
    pygame.joystick.init()

    if pygame.joystick.get_count() == 0:
        print("No joystick found! Connect Xbox controller and retry.")
        return

    joy = pygame.joystick.Joystick(0)
    joy.init()
    print(f"Joystick: {joy.get_name()}")
    print(f"  Axes: {joy.get_numaxes()}, Buttons: {joy.get_numbuttons()}")
    print()
    print("Controls:")
    print("  Left stick Y  : forward/backward")
    print("  Left stick X  : left/right")
    print("  Right stick X : yaw rotation")
    print("  LT / RT       : slow (0.5x) / fast (1.5x)")
    print("  B button       : quit")
    print()

    # ── ONNX ──────────────────────────────────────────────────
    sess = ort.InferenceSession(args.model)
    input_name = sess.get_inputs()[0].name
    history_size = sess.get_inputs()[0].shape[1] // 57
    print(f"ONNX: {input_name}, history={history_size}")

    # ── MuJoCo ────────────────────────────────────────────────
    model = mujoco.MjModel.from_xml_path(args.xml)
    model.opt.timestep = 0.005
    data = mujoco.MjData(model)
    decimation = 4
    dt = 0.005

    data.qpos[:3] = [0, 0, 0.5]
    data.qpos[3:7] = [1, 0, 0, 0]
    data.qpos[dof_ids] = default_angle.copy()
    data.qvel[:] = 0
    mujoco.mj_step(model, data)

    # PD
    kp = np.array([70,100,120]*4, dtype=np.float64)
    kd = np.array([15,15,20]*4, dtype=np.float64)

    target_q = default_angle.copy()
    action = np.zeros(16, dtype=np.float32)
    last_action = np.zeros(16, dtype=np.float32)
    obs_history = deque(maxlen=history_size)

    # 可视化窗口
    viewer = mujoco_viewer.MujocoViewer(model, data)

    cmd_vx = 0.0
    cmd_vy = 0.0
    cmd_vyaw = 0.0
    count = 0
    running = True
    warmup = 100  # 前 100 步站立

    print("Running... (press B to quit)")

    try:
        while running:
            t_start = time.perf_counter()

            # ── 读手柄 ────────────────────────────────────────
            pygame.event.pump()

            # Left stick: forward/lateral
            lx = apply_deadzone(joy.get_axis(0))  # left/right
            ly = apply_deadzone(-joy.get_axis(1))  # forward (Y 轴反转)

            # Right stick X: yaw
            rx = apply_deadzone(joy.get_axis(2) if joy.get_numaxes() > 2 else
                               joy.get_axis(3))

            # LT/RT 速度倍率
            # Xbox: axis 4 = LT (-1~1), axis 5 = RT (-1~1)
            scale = 1.0
            if joy.get_numaxes() >= 6:
                lt = (joy.get_axis(4) + 1) / 2  # 0~1
                rt = (joy.get_axis(5) + 1) / 2  # 0~1
                if lt > 0.3:
                    scale = 0.5
                elif rt > 0.3:
                    scale = 1.5

            # B button = quit
            if joy.get_numbuttons() > 1 and joy.get_button(1):
                running = False
                break

            cmd_vx = ly * 0.5 * scale   # max 0.5 m/s (or 0.75 with RT)
            cmd_vy = -lx * 0.3 * scale  # max 0.3 m/s lateral
            cmd_vyaw = -rx * 1.0        # max 1.0 rad/s

            # ── 物理循环 (和 walk_ref 一致) ────────────────────
            for _ in range(decimation):
                if count % decimation == 0:
                    obs = get_obs(data, cmd_vx, cmd_vy, cmd_vyaw, last_action)
                    obs_history.append(obs.copy())
                    while len(obs_history) < history_size:
                        obs_history.appendleft(obs.copy())

                    obs_flat = np.concatenate(list(obs_history)).astype(np.float32).reshape(1, -1)
                    raw = sess.run(None, {input_name: obs_flat})[0].squeeze()
                    action[:] = raw

                    if count > warmup:
                        scaled = np.zeros(16, dtype=np.float32)
                        for j in range(4):
                            b = j * 3
                            scaled[b] = action[b] * hip_scale
                            scaled[b+1] = action[b+1] * thigh_calf_scale
                            scaled[b+2] = action[b+2] * thigh_calf_scale
                        scaled[12:] = action[12:] * wheel_scale
                        target_q = scaled + default_angle
                    else:
                        target_q = default_angle.copy()
                    last_action = action.copy()

                q = data.qpos[dof_ids]
                dq = data.qvel[dof_vel]
                tau = np.zeros(16)
                tau[:12] = kp * (target_q[:12] - q[:12]) - kd * dq[:12]
                tau[12:] = 1.0 * (target_q[12:] - dq[12:])
                data.ctrl[:] = np.clip(tau, -120, 120)
                mujoco.mj_step(model, data)
                count += 1

            # 渲染窗口
            if viewer.is_alive:
                viewer.render()
            else:
                running = False
                break

            # 打印
            if count % 200 == 0:
                x, y, z = data.qpos[0], data.qpos[1], data.qpos[2]
                print(f"  [{count*dt:.1f}s] pos=({x:.2f}, {y:.2f}, {z:.3f}) "
                      f"cmd=({cmd_vx:.2f}, {cmd_vy:.2f}, {cmd_vyaw:.2f})")

            # 实时控制：等待到 20ms
            elapsed = time.perf_counter() - t_start
            sleep_time = (decimation * dt) - elapsed
            if sleep_time > 0:
                time.sleep(sleep_time)

    except KeyboardInterrupt:
        print("\nStopped by user")

    x, y = data.qpos[0], data.qpos[1]
    print(f"\nFinal: x={x:.3f} y={y:.3f}")

    viewer.close()
    pygame.quit()


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument("--xml", default="sim/robot/quadruped_v3.xml")
    parser.add_argument("--model", default="model/policy_260106.onnx")
    args = parser.parse_args()
    run(args)
