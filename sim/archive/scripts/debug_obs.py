"""
Debug: 对比 Dart 侧 obs 和 Python 本地 obs，找出差异。

同时运行:
1. 向 Dart server 发 Step + Tick (gRPC)
2. 本地用相同传感器数据算 obs
3. 逐帧对比 57 维 obs 差异

用法:
    # 终端 1: dart run han_dog/bin/server.dart
    # 终端 2: python sim/scripts/debug_obs.py
"""
import numpy as np
import mujoco
import grpc
import sys
from pathlib import Path
from scipy.spatial.transform import Rotation as R

SCRIPT_DIR = Path(__file__).resolve().parent
PROTO_PY_ROOT = SCRIPT_DIR.parent.parent / "han_dog_message" / "python"
if str(PROTO_PY_ROOT) not in sys.path:
    sys.path.insert(0, str(PROTO_PY_ROOT))
import han_dog_message as msg

dof_ids = [7,8,9, 11,12,13, 15,16,17, 19,20,21, 10,14,18,22]
dof_vel = [6,7,8, 10,11,12, 14,15,16, 18,19,20, 9,13,17,21]
default_angle = np.array([
    -0.1,-0.8,1.8, 0.1,0.8,-1.8, 0.1,0.8,-1.8, -0.1,-0.8,1.8, 0,0,0,0
], dtype=np.double)

OBS_NAMES = (
    ['gyro_x','gyro_y','gyro_z'] +
    ['grav_x','grav_y','grav_z'] +
    ['cmd_vx','cmd_vy','cmd_vyaw'] +
    [f'jpos_{i}' for i in range(16)] +
    [f'jvel_{i}' for i in range(16)] +
    [f'act_{i}' for i in range(16)]
)


def build_sim_state(data, elapsed_s):
    """和 xbox_brainstem.py 完全一致的 SimState 构建。"""
    # 不取共轭！Dart 的 q.rotate([0,0,-1]) 需要原始四元数
    raw_q = data.sensor('orientation').data
    qw = float(raw_q[0])
    qx, qy, qz = float(raw_q[1]), float(raw_q[2]), float(raw_q[3])
    gyro = data.sensor('angular-velocity').data
    joint_pos = [float(data.qpos[i]) for i in dof_ids]
    joint_vel = [float(data.qvel[i]) for i in dof_vel]
    seconds = int(elapsed_s)
    nanos = int((elapsed_s - seconds) * 1e9)
    return msg.SimState(
        gyroscope=msg.Vector3(x=float(gyro[0]), y=float(gyro[1]), z=float(gyro[2])),
        quaternion=msg.Quaternion(w=qw, x=qx, y=qy, z=qz),
        joint_position=msg.Matrix4(values=joint_pos),
        joint_velocity=msg.Matrix4(values=joint_vel),
        timestamp=msg.Duration(seconds=seconds, nanos=nanos),
    )


def local_obs(data, cmd_vx, cmd_vy, cmd_vyaw, last_action):
    """和 walk_ref.py 完全一致的本地 obs 构建。"""
    q = data.qpos[dof_ids].astype(np.double) - default_angle
    dq = data.qvel[dof_vel].astype(np.double) * 0.05
    q[-4:] = 0.0

    imu_quat = data.sensor('orientation').data[[1,2,3,0]].astype(np.double)
    r_imu = R.from_quat(imu_quat)
    proj = r_imu.apply([0.,0.,-1.], inverse=True).astype(np.double)

    gyro_local = data.sensor('angular-velocity').data.astype(np.double)
    base_quat = data.qpos[3:7][[1,2,3,0]].astype(np.double)
    r_base = R.from_quat(base_quat)
    gyro_world = r_imu.apply(gyro_local)
    gyro = r_base.apply(gyro_world, inverse=True) * 0.25

    return np.concatenate([
        gyro, proj,
        [cmd_vx, cmd_vy, cmd_vyaw],
        q, dq, last_action
    ]).astype(np.float32)


def dart_obs_from_history(h):
    """从 Dart tick 返回的 History 中提取最后一帧的 obs（反推）。"""
    gyro = np.array([h.gyroscope.x, h.gyroscope.y, h.gyroscope.z]) * 0.25
    grav = np.array([h.projected_gravity.x, h.projected_gravity.y, h.projected_gravity.z])
    cmd = np.array([0, 0, 0])
    if h.command.HasField('walk'):
        cmd = np.array([h.command.walk.x, h.command.walk.y, h.command.walk.z])
    jpos = np.array(h.joint_position.values) - default_angle
    jpos[-4:] = 0.0
    jvel = np.array(h.joint_velocity.values) * 0.05
    act = (np.array(h.action.values) - default_angle) / np.array([
        0.125,0.25,0.25, 0.125,0.25,0.25, 0.125,0.25,0.25, 0.125,0.25,0.25,
        5,5,5,5])

    return np.concatenate([gyro, grav, cmd, jpos, jvel, act]).astype(np.float32)


def dart_to_mj(d):
    mj = np.zeros(16)
    for leg in range(4):
        dd, m = leg*3, leg*4
        mj[m]=d[dd]; mj[m+1]=d[dd+1]; mj[m+2]=d[dd+2]; mj[m+3]=d[12+leg]
    return mj


def main():
    print("Connecting to brainstem...")
    channel = grpc.insecure_channel("127.0.0.1:13145")
    grpc.channel_ready_future(channel).result(timeout=10)
    stub = msg.CmsStub(channel)
    print(f"Connected. CMS: {stub.GetCmsState(msg.Empty()).kind}")

    model = mujoco.MjModel.from_xml_path("sim/robot/quadruped_v3.xml")
    model.opt.timestep = 0.005
    data = mujoco.MjData(model)
    decimation = 4
    dt = 0.005

    data.qpos[:3] = [0,0,0.5]
    data.qpos[3:7] = [1,0,0,0]
    data.qpos[dof_ids] = default_angle.copy()
    data.qvel[:] = 0
    mujoco.mj_step(model, data)

    kp = np.array([70,100,120]*4, dtype=np.float64)
    kd = np.array([15,15,20]*4, dtype=np.float64)
    target_q = default_angle.copy()
    last_action_local = np.zeros(16, dtype=np.float32)

    # StandUp first
    stub.StandUp(msg.Empty())
    count = 0

    print("\nRunning 200 control steps (4s)...")
    print("Will Walk at step 100 (2s)\n")

    for step in range(200):
        now_s = count * dt

        if count % decimation == 0:
            sim_state = build_sim_state(data, now_s)
            stub.Step(sim_state)

            cms = stub.GetCmsState(msg.Empty())

            # Walk at step 100
            if step == 100:
                try:
                    stub.Walk(msg.Vector3(x=0.3, y=0.0, z=0.0))
                    print(f"  [{now_s:.1f}s] >> Walk(0.3,0,0) sent")
                except grpc.RpcError:
                    pass

            history = stub.Tick(msg.Empty())
            target_q = np.array(history.next_action.values, dtype=np.float64)

            if len(history.kp.values) == 16:
                kp = np.array(history.kp.values[:12], dtype=np.float64)
            if len(history.kd.values) == 16:
                kd = np.array(history.kd.values[:12], dtype=np.float64)

            # 对比 obs: 只在推理帧对比
            cmd_vx = 0.3 if step >= 100 else 0.0
            py_obs = local_obs(data, cmd_vx, 0, 0, last_action_local)
            dart_obs = dart_obs_from_history(history)

            # 打印差异
            diff = np.abs(py_obs - dart_obs)
            max_diff_idx = np.argmax(diff)
            max_diff = diff[max_diff_idx]

            if step % 20 == 0 or max_diff > 0.05:
                z = float(data.qpos[2])
                print(f"  [{now_s:.1f}s] z={z:.3f} cms={cms.kind} max_diff={max_diff:.4f} @ {OBS_NAMES[max_diff_idx]}")
                if max_diff > 0.01:
                    # 打印所有差异 > 0.01 的维度
                    bad = np.where(diff > 0.01)[0]
                    for idx in bad:
                        print(f"    [{idx:2d}] {OBS_NAMES[idx]:8s} py={py_obs[idx]:+.4f} dart={dart_obs[idx]:+.4f} diff={diff[idx]:.4f}")

            # 更新 local last_action (模拟 walk_ref 的逻辑)
            if step >= 100:
                raw_action = (target_q - default_angle) / np.array([
                    0.125,0.25,0.25, 0.125,0.25,0.25, 0.125,0.25,0.25, 0.125,0.25,0.25,
                    5,5,5,5])
                last_action_local = raw_action.astype(np.float32)
            else:
                last_action_local = np.zeros(16, dtype=np.float32)

        # PD
        q = data.qpos[dof_ids].astype(np.float64)
        dq = data.qvel[dof_vel].astype(np.float64)
        tau = np.zeros(16)
        tau[:12] = kp * (target_q[:12] - q[:12]) - kd * dq[:12]
        tau[12:] = 1.0 * (target_q[12:] - dq[12:])
        data.ctrl[:] = np.clip(tau, -120, 120)

        mujoco.mj_step(model, data)
        count += 1

    print("\nDone.")
    channel.close()


if __name__ == "__main__":
    main()
