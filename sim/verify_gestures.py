"""
验证 Gesture SDK 的动作效果。

用 MuJoCo 物理仿真 + PD 位控播放关键帧插值，录制视频。
使用真实 STL mesh 渲染，自由基体（freejoint），躯体自然跟随腿部运动。

动作设计遵循动画原则：
- 余弦缓入缓出替代线性插值（两端慢、中间快）
- 预备动作（anticipation）：主动作前的反向小动作
- 过冲与回弹（overshoot & settle）
- 振幅包络（amplitude envelope）：节奏型动作渐强渐弱
- 次要动作（secondary action）：非主轴上的微妙联动

用法:
    python sim/verify_gestures.py
输出:
    sim/gesture_*.mp4
"""

import numpy as np
import mujoco
import mediapy
from pathlib import Path

# ── 路径 ──────────────────────────────────────────────────────
SCRIPT_DIR = Path(__file__).resolve().parent
MODEL_PATH = SCRIPT_DIR / "quadruped.xml"
OUTPUT_DIR = SCRIPT_DIR
FPS = 50
DT = 0.002  # MuJoCo timestep
STEPS_PER_FRAME = int(1.0 / FPS / DT)  # = 10 steps per frame at 50Hz

# ══════════════════════════════════════════════════════════════
#  布局定义 — 严格对应 Dart JointsMatrix
# ══════════════════════════════════════════════════════════════
#
# Dart JointsMatrix(16):
#   [0..2]   FR hip, thigh, calf
#   [3..5]   FL hip, thigh, calf
#   [6..8]   RR hip, thigh, calf
#   [9..11]  RL hip, thigh, calf
#   [12..15] FR_foot, FL_foot, RR_foot, RL_foot
#
# MuJoCo ctrl/qpos(16):
#   [0..3]   FR hip, thigh, calf, foot
#   [4..7]   FL hip, thigh, calf, foot
#   [8..11]  RR hip, thigh, calf, foot
#   [12..15] RL hip, thigh, calf, foot

# ── 站立姿态（Dart 真机约定，从 robot_params.dart 复制）────────
DART_STANDING = np.array([
    -0.1, -0.8,  1.8,     # FR: hip, thigh, calf
     0.1,  0.8, -1.8,     # FL
     0.1,  0.8, -1.8,     # RR
    -0.1, -0.8,  1.8,     # RL
     0.0,  0.0,  0.0, 0.0,  # foot: FR, FL, RR, RL
], dtype=np.float64)


def dart_to_mujoco(dart16: np.ndarray) -> np.ndarray:
    """将 Dart JointsMatrix 布局(16) 转换为 MuJoCo ctrl 布局(16)，同时取反角度。

    Dart 布局: [FR(3), FL(3), RR(3), RL(3), foot(4)]
    MuJoCo:    [FR(4), FL(4), RR(4), RL(4)]
    URDF 轴向与电机相反，角度全部取反。
    """
    mj = np.zeros(16)
    for leg in range(4):
        d = leg * 3          # Dart 非 foot 起始
        m = leg * 4          # MuJoCo 起始
        mj[m + 0] = -dart16[d + 0]      # hip
        mj[m + 1] = -dart16[d + 1]      # thigh
        mj[m + 2] = -dart16[d + 2]      # calf
        mj[m + 3] = -dart16[12 + leg]   # foot
    return mj


# MuJoCo 站立控制信号
STANDING_CTRL = dart_to_mujoco(DART_STANDING)


# ── 动作定义（Dart 约定: standingPose + offset）──────────────
def dart_offset(offsets: list[float]) -> np.ndarray:
    """在 DART_STANDING 基础上叠加 12 个关节偏移（Dart 约定），
    然后转换为 MuJoCo ctrl。"""
    dart = DART_STANDING.copy()
    for i in range(12):
        dart[i] += offsets[i]
    dart[12:] = 0.0  # foot 保持 0
    return dart_to_mujoco(dart)


def dart_standing_mujoco() -> np.ndarray:
    """站立姿态的 MuJoCo ctrl。"""
    return STANDING_CTRL.copy()


# ── 插值函数 ──────────────────────────────────────────────────

def cosine_ease(a: np.ndarray, b: np.ndarray, t: float) -> np.ndarray:
    """余弦缓入缓出插值：两端慢、中间快，比线性插值自然得多。"""
    tc = np.clip(t, 0.0, 1.0)
    s = (1.0 - np.cos(np.pi * tc)) / 2.0
    return a + (b - a) * s


# ── 动作关键帧（应用动画原则，与 gesture.dart 对应）────────────
GESTURES = {
    "bow": {
        "description": "鞠躬 / 拜年",
        "keyframes": [
            # 预备：身体微微上抬（anticipation —— 反向预备动作）
            (dart_offset([
                0, 0.08,-0.12,   0,-0.08, 0.12,
                0,-0.04, 0.06,   0, 0.04,-0.06,
            ]), 15),
            # 鞠躬：前腿深弯、后腿略伸
            (dart_offset([
                0,-0.5,  0.8,    0, 0.5, -0.8,
                0, 0.2, -0.35,   0,-0.2,  0.35,
            ]), 55),
            # 保持鞠躬（hold）
            (dart_offset([
                0,-0.5,  0.8,    0, 0.5, -0.8,
                0, 0.2, -0.35,   0,-0.2,  0.35,
            ]), 50),
            # 缓缓起身
            (dart_standing_mujoco(), 60),
        ],
    },
    "nod": {
        "description": "点头",
        "keyframes": [
            # 第一次点头（较深）
            (dart_offset([
                0,-0.25, 0.38,   0, 0.25,-0.38,
                0,-0.12, 0.18,   0, 0.12,-0.18,
            ]), 20),
            # 抬起时微过冲（overshoot —— 超过站立位一点点）
            (dart_offset([
                0, 0.06,-0.09,   0,-0.06, 0.09,
                0, 0.03,-0.05,   0,-0.03, 0.05,
            ]), 15),
            # 第二次点头（较浅 —— 递减节奏更自然）
            (dart_offset([
                0,-0.15, 0.22,   0, 0.15,-0.22,
                0,-0.08, 0.12,   0, 0.08,-0.12,
            ]), 18),
            # 回到站立附近
            (dart_standing_mujoco(), 12),
            # 第三次微点头（最轻 —— 收尾感）
            (dart_offset([
                0,-0.08, 0.12,   0, 0.08,-0.12,
                0,-0.04, 0.06,   0, 0.04,-0.06,
            ]), 10),
            # 最终回位
            (dart_standing_mujoco(), 12),
        ],
    },
    "wiggle": {
        "description": "左右扭动",
        "keyframes": [
            # 振幅包络：小 → 中 → 大 → 中 → 小（渐强渐弱）
            # 每个倾斜带微量大腿联动（secondary action —— 身体自然跟随）
            # fmt: off
            (dart_offset([-0.08, 0.02, 0,  -0.08, 0.02, 0,  -0.08, 0.02, 0,  -0.08, 0.02, 0]), 12),
            (dart_offset([ 0.08,-0.02, 0,   0.08,-0.02, 0,   0.08,-0.02, 0,   0.08,-0.02, 0]), 12),
            (dart_offset([-0.15, 0.04, 0,  -0.15, 0.04, 0,  -0.15, 0.04, 0,  -0.15, 0.04, 0]), 15),
            (dart_offset([ 0.15,-0.04, 0,   0.15,-0.04, 0,   0.15,-0.04, 0,   0.15,-0.04, 0]), 15),
            (dart_offset([-0.22, 0.06, 0,  -0.22, 0.06, 0,  -0.22, 0.06, 0,  -0.22, 0.06, 0]), 18),
            (dart_offset([ 0.22,-0.06, 0,   0.22,-0.06, 0,   0.22,-0.06, 0,   0.22,-0.06, 0]), 18),
            (dart_offset([-0.15, 0.04, 0,  -0.15, 0.04, 0,  -0.15, 0.04, 0,  -0.15, 0.04, 0]), 15),
            (dart_offset([ 0.08,-0.02, 0,   0.08,-0.02, 0,   0.08,-0.02, 0,   0.08,-0.02, 0]), 12),
            (dart_standing_mujoco(), 10),
            # fmt: on
        ],
    },
    "stretch": {
        "description": "伸展",
        "keyframes": [
            # 预备：微蹲（anticipation —— 蓄力感）
            (dart_offset([
                0,-0.1,  0.15,   0, 0.1, -0.15,
                0, 0.1, -0.15,   0,-0.1,  0.15,
            ]), 12),
            # 前伸：前腿伸展、后腿蹲下（猫式伸懒腰）
            (dart_offset([
                0, 0.35,-0.55,   0,-0.35, 0.55,
                0,-0.25, 0.4,    0, 0.25,-0.4,
            ]), 50),
            # 保持前伸（hold —— 慵懒感）
            (dart_offset([
                0, 0.35,-0.55,   0,-0.35, 0.55,
                0,-0.25, 0.4,    0, 0.25,-0.4,
            ]), 30),
            # 回到站立
            (dart_standing_mujoco(), 25),
            # 预备后伸（轻微 anticipation）
            (dart_offset([
                0, 0.06,-0.09,   0,-0.06, 0.09,
                0,-0.06, 0.09,   0, 0.06,-0.09,
            ]), 10),
            # 后伸：后腿伸展、前腿蹲下
            (dart_offset([
                0,-0.25, 0.4,    0, 0.25,-0.4,
                0, 0.35,-0.55,   0,-0.35, 0.55,
            ]), 50),
            # 保持后伸（hold）
            (dart_offset([
                0,-0.25, 0.4,    0, 0.25,-0.4,
                0, 0.35,-0.55,   0,-0.35, 0.55,
            ]), 30),
            # 缓缓回到站立
            (dart_standing_mujoco(), 30),
        ],
    },
    "dance": {
        "description": "跳舞",
        "keyframes": [
            # ── Section 1: 力量弹跳（快节奏 120 BPM）──
            # 深蹲 (deep crouch)
            (dart_offset([0,-0.45,0.68, 0,0.45,-0.68, 0,0.45,-0.68, 0,-0.45,0.68]), 8),
            # 弹起 + 右倾 (explosive spring + right lean)
            (dart_offset([0.15,0.3,-0.45, 0.15,-0.3,0.45, 0.15,-0.3,0.45, 0.15,0.3,-0.45]), 8),
            # 深蹲 + 左倾
            (dart_offset([-0.12,-0.45,0.68, -0.12,0.45,-0.68, -0.12,0.45,-0.68, -0.12,-0.45,0.68]), 8),
            # 弹起
            (dart_offset([0,0.3,-0.45, 0,-0.3,0.45, 0,-0.3,0.45, 0,0.3,-0.45]), 8),

            # ── Section 2: 大幅摇摆（wide groove）──
            # 大右倾 + 下沉 (far right lean + dip)
            (dart_offset([0.45,-0.15,0.22, 0.45,0.15,-0.22, 0.45,0.15,-0.22, 0.45,-0.15,0.22]), 12),
            # 大左倾 + 下沉
            (dart_offset([-0.45,-0.15,0.22, -0.45,0.15,-0.22, -0.45,0.15,-0.22, -0.45,-0.15,0.22]), 12),
            # 大右倾 + 弹起 (far right + bounce up)
            (dart_offset([0.4,0.1,-0.15, 0.4,-0.1,0.15, 0.4,-0.1,0.15, 0.4,0.1,-0.15]), 10),
            # 大左倾 + 弹起
            (dart_offset([-0.4,0.1,-0.15, -0.4,-0.1,0.15, -0.4,-0.1,0.15, -0.4,0.1,-0.15]), 10),

            # ── Section 3: 身体波浪 + 扭转（body wave + twist）──
            # 深前俯 (deep front bow)
            (dart_offset([0,-0.5,0.75, 0,0.5,-0.75, 0,-0.15,0.22, 0,0.15,-0.22]), 12),
            # 深后仰 (deep rear dip)
            (dart_offset([0,0.15,-0.22, 0,-0.15,0.22, 0,0.5,-0.75, 0,-0.5,0.75]), 12),
            # 对角线：前左俯 + 后右抬 (diagonal front-left bow + rear-right rise)
            (dart_offset([-0.35,-0.4,0.6, -0.35,0.4,-0.6, 0.35,-0.15,0.22, 0.35,0.15,-0.22]), 12),
            # 对角线：前右俯 + 后左抬
            (dart_offset([0.35,-0.4,0.6, 0.35,0.4,-0.6, -0.35,-0.15,0.22, -0.35,0.15,-0.22]), 12),

            # ── Section 4: 爆发收尾（explosive finale）──
            # 最深蹲 (deepest crouch — 蓄力)
            (dart_offset([0,-0.5,0.75, 0,0.5,-0.75, 0,0.5,-0.75, 0,-0.5,0.75]), 10),
            # 爆发弹起造型 (pop up: front right-lean + high, rear left-lean)
            (dart_offset([0.35,0.3,-0.45, 0.35,-0.3,0.45, -0.25,0.08,-0.12, -0.25,-0.08,0.12]), 14),
            # 保持造型 (dramatic hold)
            (dart_offset([0.35,0.3,-0.45, 0.35,-0.3,0.45, -0.25,0.08,-0.12, -0.25,-0.08,0.12]), 25),
            # 回到站立
            (dart_standing_mujoco(), 25),
        ],
    },
}


# ── MuJoCo 仿真 ──────────────────────────────────────────────

def step_physics(model, data, n_steps: int = STEPS_PER_FRAME):
    for _ in range(n_steps):
        mujoco.mj_step(model, data)


def render_frame(model, data, renderer, camera) -> np.ndarray:
    renderer.update_scene(data, camera)
    return renderer.render().copy()


def settle_standing(model, data, n_frames: int = 100):
    """让机器人在站立姿态下稳定。"""
    data.ctrl[:] = STANDING_CTRL
    for _ in range(n_frames):
        step_physics(model, data)


def play_gesture(
    model, data, renderer, camera,
    gesture_name: str, gesture_def: dict,
) -> list[np.ndarray]:
    """播放一个动作，返回所有帧。使用余弦缓入缓出插值。"""
    frames = []
    keyframes = gesture_def["keyframes"]

    current_ctrl = STANDING_CTRL.copy()

    # 先渲染几帧站立
    data.ctrl[:] = STANDING_CTRL
    for _ in range(25):
        step_physics(model, data)
        frames.append(render_frame(model, data, renderer, camera))

    # 播放关键帧序列（余弦缓入缓出）
    for target_ctrl, counts in keyframes:
        start_ctrl = current_ctrl.copy()
        for i in range(counts + 1):
            t = (i / counts) if counts > 0 else 1.0
            ctrl = cosine_ease(start_ctrl, target_ctrl, t)
            data.ctrl[:] = ctrl
            step_physics(model, data)
            frames.append(render_frame(model, data, renderer, camera))
        current_ctrl = target_ctrl.copy()

    # 结尾站立
    data.ctrl[:] = STANDING_CTRL
    for _ in range(25):
        step_physics(model, data)
        frames.append(render_frame(model, data, renderer, camera))

    return frames


def main():
    print("Loading MuJoCo model...")
    model = mujoco.MjModel.from_xml_path(str(MODEL_PATH))
    data = mujoco.MjData(model)

    print(f"Model: nq={model.nq}, nu={model.nu}, njnt={model.njnt}")
    print(f"STANDING_CTRL = {STANDING_CTRL}")

    # 设置渲染器
    renderer = mujoco.Renderer(model, height=720, width=1280)
    camera = mujoco.MjvCamera()
    camera.type = mujoco.mjtCamera.mjCAMERA_FREE
    camera.lookat[:] = [0.0, 0.0, 0.2]
    camera.distance = 1.5
    camera.azimuth = 135
    camera.elevation = -25

    all_frames = []

    for gesture_name, gesture_def in GESTURES.items():
        desc = gesture_def["description"]
        print(f"\nPlaying gesture: {gesture_name} ({desc})...")

        # 重置到站立
        mujoco.mj_resetData(model, data)
        data.qpos[2] = 0.35   # trunk height
        data.qpos[3] = 1.0    # quaternion w

        # 初始化关节角度为站立姿态（MuJoCo 布局）
        data.qpos[7:23] = STANDING_CTRL
        data.ctrl[:] = STANDING_CTRL

        # 稳定站立 (物理仿真)
        settle_standing(model, data, n_frames=150)
        print(f"  Trunk z after settling: {data.qpos[2]:.4f}")

        frames = play_gesture(model, data, renderer, camera,
                              gesture_name, gesture_def)
        print(f"  Rendered {len(frames)} frames")

        # 保存单个动作视频
        video_path = OUTPUT_DIR / f"gesture_{gesture_name}.mp4"
        mediapy.write_video(str(video_path), frames, fps=FPS)
        print(f"  Saved: {video_path}")

        all_frames.extend(frames)
        if frames:
            all_frames.extend([frames[-1]] * 15)

    # 保存合集视频
    all_video_path = OUTPUT_DIR / "gesture_all.mp4"
    mediapy.write_video(str(all_video_path), all_frames, fps=FPS)
    print(f"\nAll gestures video: {all_video_path}")
    print(f"Total frames: {len(all_frames)}, Duration: {len(all_frames)/FPS:.1f}s")


if __name__ == "__main__":
    main()
