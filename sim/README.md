# sim/ — MuJoCo 仿真验证

MuJoCo 物理仿真，用于验证 RL 策略和 brainstem 控制链路。

## 目录结构

```
sim/
├── robot/                  # 机器人模型
│   ├── quadruped_v3.xml    # MuJoCo XML（从 URDF 转换，主用）
│   ├── quadruped.xml       # 旧手写 XML（参考）
│   ├── quadruped.urdf      # 旧 URDF（参考）
│   └── meshes/             # STL 碰撞/视觉模型
├── scripts/                # 仿真脚本
│   ├── walk_ref.py         # 纯本地 ONNX 仿真（验证策略）
│   ├── walk_grpc.py        # gRPC 闭环（验证 brainstem Dart server）
│   ├── walk_xbox.py        # Xbox 手柄实时控制
│   └── verify_gestures.py  # 动作库验证
├── output/                 # 视频输出
├── archive/
│   └── SIM_LESSONS.md      # 踩坑记录（必读）
└── README.md
```

## 快速开始

### 1. 验证策略（纯本地，不需要 Dart server）

```bash
cd brainstem
python sim/scripts/walk_ref.py --vx 0.3 --duration 10 --render
```

### 2. 验证 brainstem gRPC 链路

```bash
# 终端 1: 启动 Dart server
ONNXRUNTIME_DLL_PATH=... dart run han_dog/bin/server.dart

# 终端 2: 跑仿真
python sim/scripts/walk_grpc.py --vx 0.3 --duration 10 --render
```

### 3. Xbox 手柄控制

```bash
python sim/scripts/walk_xbox.py
```

控制映射：
| 输入 | 功能 | 范围 |
|------|------|------|
| 左摇杆 Y | 前后移动 | ±0.5 m/s |
| 左摇杆 X | 左右侧移 | ±0.3 m/s |
| 右摇杆 X | 旋转 yaw | ±1.0 rad/s |
| LT | 慢速 | 0.5x |
| RT | 快速 | 1.5x |
| B 键 | 退出 | - |

## 关键参数

| 参数 | 值 | 说明 |
|------|-----|------|
| timestep | 0.005s | MuJoCo 物理步长 |
| decimation | 4 | 每 4 步推理一次 (50Hz) |
| PD 频率 | 200Hz | 每步都算 PD |
| 腿 KP | 70/100/120 | hip/thigh/calf |
| 腿 KD | 15/15/20 | hip/thigh/calf |
| 轮 KD | 1.0 | 纯速度控制 |
| action scale | 0.125/0.25/0.25/5.0 | hip/thigh/calf/wheel |
| standing pose | [-0.1,-0.8,1.8, ...] | 16 DOF 默认角度 |

## quadruped_v3.xml

从 `轮足狗机器人v3.urdf` 转换，手动添加：
- freejoint（自由体）
- motor actuator（力矩执行器，PD 在 Python 侧算）
- IMU sensor（framequat + gyro）
- 物理参数对齐参考 ow_wheel2.xml

关节轴与 URDF/Isaac Lab 训练一致，Dart 值直接透传不取反。

## 注意事项

详见 `archive/SIM_LESSONS.md`。核心要点：

1. **PD 每个物理步都算**，不能 20 substep 共用一个 tau
2. **last_action 始终保存策略输出**，站立阶段不清零
3. **推理按 decimation 降频**，PD 保持高频
4. **四元数**: MuJoCo sensor 输出 body→world，计算 projectedGravity 需取共轭
