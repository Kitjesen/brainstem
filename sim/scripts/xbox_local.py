"""
Xbox 手柄 + 纯本地 ONNX 推理（不走 gRPC/brainstem）。
和 walk_ref.py 完全一致的物理循环，加手柄输入。

用法: python sim/scripts/xbox_local.py
"""
import math
import numpy as np
import mujoco
import mujoco_viewer
import onnxruntime as ort
import pygame
import sys, time
from pathlib import Path
from scipy.spatial.transform import Rotation as R
from collections import deque

SCRIPT_DIR = Path(__file__).resolve().parent

dof_ids = [7,8,9, 11,12,13, 15,16,17, 19,20,21, 10,14,18,22]
dof_vel = [6,7,8, 10,11,12, 14,15,16, 18,19,20, 9,13,17,21]

default_angle = np.array([
    -0.1,-0.8,1.8, 0.1,0.8,-1.8, 0.1,0.8,-1.8, -0.1,-0.8,1.8, 0,0,0,0
], dtype=np.double)

hip_scale = 0.125
thigh_calf_scale = 0.25
wheel_scale = 5.0

DEADZONE = 0.08


def get_obs(data, vx, vy, vyaw, last_action):
    """和 walk_ref.py 100% 一致的 obs 构建。"""
    q = data.qpos[dof_ids].astype(np.double) - default_angle
    dq = data.qvel[dof_vel].astype(np.double) * 0.05
    q[-4:] = 0.0

    imu_quat = data.sensor('orientation').data[[1,2,3,0]].astype(np.double)
    r_imu = R.from_quat(imu_quat)
    proj = r_imu.apply([0.,0.,-1.], inverse=True).astype(np.double)

    gyro_local = data.sensor('angular-velocity').data.astype(np.double)
    base_quat = data.qpos[3:7][[1,2,3,0]].astype(np.double)
    r_base = R.from_quat(base_quat)
    gyro = r_base.apply(r_imu.apply(gyro_local), inverse=True) * 0.25

    return np.concatenate([
        gyro, proj, [vx, vy, vyaw], q, dq, last_action
    ]).astype(np.float32)


def dz(val):
    return 0.0 if abs(val) < DEADZONE else val


def main():
    # ── pygame ────────────────────────────────────────────────
    pygame.init()
    pygame.joystick.init()
    if pygame.joystick.get_count() == 0:
        print("No joystick found!")
        return
    joy = pygame.joystick.Joystick(0)
    joy.init()
    print(f"Joystick: {joy.get_name()}")

    # ── ONNX ──────────────────────────────────────────────────
    model_path = "sim/model/policy_v9_800.onnx"
    sess = ort.InferenceSession(model_path)
    input_name = sess.get_inputs()[0].name
    history_size = sess.get_inputs()[0].shape[1] // 57
    print(f"ONNX: {model_path}, input={input_name}, history={history_size}")

    # ── MuJoCo ────────────────────────────────────────────────
    model = mujoco.MjModel.from_xml_path("sim/robot/quadruped_v3.xml")
    model.opt.timestep = 0.005
    data = mujoco.MjData(model)
    decimation = 4
    dt = 0.005

    data.qpos[:3] = [0, 0, 0.5]
    data.qpos[3:7] = [1, 0, 0, 0]
    data.qpos[dof_ids] = default_angle.copy()
    data.qvel[:] = 0
    mujoco.mj_step(model, data)

    viewer = mujoco_viewer.MujocoViewer(model, data)

    # PD (训练增益)
    kp = np.array([70,100,120]*4, dtype=np.float64)
    kd = np.array([15, 15, 20]*4, dtype=np.float64)

    target_q = default_angle.copy()
    action = np.zeros(16, dtype=np.float32)
    last_action = np.zeros(16, dtype=np.float32)
    obs_history = deque(maxlen=history_size)

    count = 0
    warmup = 100  # 前 100 步纯 PD 站立（和 walk_ref 一致）
    walking = False
    last_btn = {}

    print()
    print("Controls:")
    print("  A        : toggle walk on/off")
    print("  Left stick : vx/vy")
    print("  Right stick X : yaw")
    print("  LT/RT    : slow/fast")
    print("  B        : quit")
    print()

    try:
        while viewer.is_alive:
            t_start = time.perf_counter()

            # ── 读手柄 ───────────────────────────────────────
            pygame.event.pump()

            lx = dz(joy.get_axis(0))
            ly = dz(-joy.get_axis(1))
            rx = dz(joy.get_axis(2) if joy.get_numaxes() > 2 else 0)

            scale = 1.0
            if joy.get_numaxes() >= 6:
                lt = (joy.get_axis(4) + 1) / 2
                rt = (joy.get_axis(5) + 1) / 2
                if lt > 0.3:
                    scale = 0.5
                elif rt > 0.3:
                    scale = 1.5

            cmd_vx = ly * scale
            cmd_vy = lx * scale
            cmd_vyaw = -rx * scale

            # Button edge detect
            def btn_pressed(idx):
                cur = joy.get_button(idx) if idx < joy.get_numbuttons() else 0
                prev = last_btn.get(idx, 0)
                last_btn[idx] = cur
                return cur and not prev

            if btn_pressed(0):  # A
                walking = not walking
                print(f"  Walking: {'ON' if walking else 'OFF'}")

            if btn_pressed(1):  # B
                break

            if not walking:
                cmd_vx = 0
                cmd_vy = 0
                cmd_vyaw = 0

            # ── 物理循环（和 walk_ref.py 完全一致）─────────────
            for _ in range(decimation):
                if count % decimation == 0:
                    obs = get_obs(data, cmd_vx, cmd_vy, cmd_vyaw, last_action)
                    obs_history.append(obs.copy())
                    while len(obs_history) < history_size:
                        obs_history.appendleft(obs.copy())

                    obs_flat = np.concatenate(list(obs_history)).astype(np.float32).reshape(1,-1)
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
                        last_action = action.copy()
                    else:
                        target_q = default_angle.copy()
                        last_action = action.copy()

                # PD 每步都算
                q = data.qpos[dof_ids]
                dq_val = data.qvel[dof_vel]
                tau_leg = kp * (target_q[:12] - q[:12]) - kd * dq_val[:12]
                # 非 Walking 时轮子刹车（target_vel=0）
                wheel_target = target_q[12:] if walking else np.zeros(4)
                tau_wheel = 1.0 * (wheel_target - dq_val[12:])
                tau = np.concatenate([tau_leg, tau_wheel])
                data.ctrl[:] = np.clip(tau, -100, 100)

                mujoco.mj_step(model, data)
                count += 1

            viewer.render()

            # 每 2 秒打印
            if count % int(2.0 / dt) == 0:
                now_s = count * dt
                x, y, z = data.qpos[0], data.qpos[1], data.qpos[2]
                mode = "WALK" if walking else "STAND"
                cmd_str = f"cmd=({cmd_vx:.2f},{cmd_vy:.2f},{cmd_vyaw:.2f})" if walking else ""
                print(f"  [{now_s:.1f}s] pos=({x:.2f},{y:.2f},{z:.3f}) {mode} {cmd_str}")

            # 实时
            elapsed = time.perf_counter() - t_start
            sleep_time = (decimation * dt) - elapsed
            if sleep_time > 0:
                time.sleep(sleep_time)

    except KeyboardInterrupt:
        print("\nStopped")
    finally:
        viewer.close()
        pygame.quit()


if __name__ == "__main__":
    main()
