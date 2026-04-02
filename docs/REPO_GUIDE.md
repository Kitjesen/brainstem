# brainstem 仓库维护指南

> 2026-04-03 创建 | 配合仓库整理一起使用

---

## 目录结构总览

```
brainstem/
├── [Tier 1] 运控核心 ─────────────────────────────
│   ├── han_dog/           主程序 + gRPC + 硬件驱动 (52 files)
│   ├── han_dog_brain/     推理核心：Brain/FSM/Behaviour (35 files)
│   └── skinny_dog_algebra/ 数学库：JointsMatrix (13 files)
│
├── [Tier 2] 硬件驱动 ─────────────────────────────
│   ├── robo_device/       设备抽象层 (25 files)
│   ├── pcan/              CAN 总线通信 FFI (22 files)
│   ├── serial_port/       串口通信 FFI (17 files)
│   └── onnx_runtime/      ONNX 推理 FFI (36 files)
│
├── [Tier 3] 协议层 ───────────────────────────────
│   ├── han_dog_message/   gRPC protobuf (50 files, 生成代码勿手改)
│   ├── robo_device_proto/ 设备协议编解码 (37 files)
│   └── protoframe/        帧协议解析 (9 files)
│
├── [Tier 4] 应用 / 工具 ──────────────────────────
│   ├── sirius/            Flutter Desktop 控制台 (68 files)
│   ├── sim/               MuJoCo 仿真资源 (17 tracked files)
│   └── frequency_watch/   频率统计工具 (13 files)
│
├── docs/                  文档归档
│   ├── HANDOFF_*.md       工作交接记录
│   ├── sim_archive/       旧仿真脚本
│   └── REPO_GUIDE.md      ← 你在看的这个文件
│
├── _archive/              旧版代码/资源 (untracked, 不入 git)
│   ├── legacy/            旧版全量代码快照 (~1149 files)
│   ├── sim_output/        旧仿真输出视频 (.mp4)
│   ├── assets/            旧 URDF/ZIP 资源
│   └── model/             旧 ONNX 模型
│
├── scripts/               部署脚本
├── CLAUDE.md              AI 工作指南（含完整架构表）
├── README.md              项目文档
└── SDK_DESIGN.md          SDK 架构设计（Phase 1-2 已完成）
```

---

## 日常开发规则

### 1. 代码质量门控

每次改动后必须通过：

```bash
dart analyze han_dog_brain/ han_dog/   # 必须零 issue
dart test han_dog/ han_dog_brain/ frequency_watch/ skinny_dog_algebra/  # 全部通过
```

### 2. 不可手动编辑的文件

| 模式 | 来源 | 重新生成方式 |
|------|------|-------------|
| `*.freezed.dart` | Freezed | `dart run build_runner build --delete-conflicting-outputs` |
| `*.g.dart` | build_runner | 同上 |
| `*.pb.dart` / `*.pbgrpc.dart` | protoc | 重新运行 protoc |

### 3. 新文件放哪里

| 你要做的事 | 放在 |
|-----------|------|
| 新的运动行为（如 Trot） | `han_dog_brain/lib/src/` |
| 新的 gRPC RPC | 先改 `han_dog_message/` proto，再在 `han_dog/lib/src/server/` 实现 |
| 新的硬件驱动 | `han_dog/lib/src/` (如 `real_xxx.dart`) |
| 新的设备协议 | `robo_device_proto/` |
| 新的 Python 仿真脚本 | `sim/scripts/` |
| 新的 MuJoCo 模型 | `sim/robot/` |
| 临时文档/交接 | `docs/` |
| 不再使用的旧代码 | `_archive/`（不入 git） |

### 4. 新包的创建规则

**尽量不创建新包。** 当前 12 个包已经覆盖了所有层次。如果确实需要：

1. 确认现有包无法容纳
2. 明确属于哪个 Tier
3. 更新 `CLAUDE.md` 架构表
4. 更新 `README.md` 目录结构
5. 更新本文件

---

## _archive/ 使用说明

`_archive/` 是**本地磁盘归档**，不进 git 仓库（已在 .gitignore 中）。

### 什么时候用

- 旧代码想保留但不想在仓库里看到 → 移到 `_archive/`
- 大文件（.onnx, .mp4, .zip）不想 track → 放 `_archive/`
- 实验性代码跑完了 → 移到 `_archive/`

### 注意事项

- `_archive/` 不在 git 里，**换机器会丢失**。重要的东西仍需入库或备份到别处
- 不要把 `_archive/` 从 .gitignore 中移除
- 如果要从 `_archive/` 恢复代码，直接 cp 回对应目录即可

---

## 依赖图

```
                    han_dog (主程序入口)
                   /    |     \      \
        han_dog_brain  freq_watch  robo_device  han_dog_message
           /    \                   /   |   \
  skinny_dog  onnx_runtime     pcan serial protoframe
   _algebra                         _port
                                robo_device_proto
```

**规则：依赖只能从上到下，不能反向。** `han_dog_brain` 不依赖 `han_dog`，`pcan` 不依赖 `robo_device`。

---

## .gitignore 保护清单

以下类型的文件被 .gitignore 排除，**不会意外进入仓库**：

| 模式 | 原因 |
|------|------|
| `_archive/` | 旧代码/资源归档 |
| `*.mp4` | 视频文件太大 |
| `*.tlog` | 构建日志 |
| `*.dll` / `*.so` / `*.dylib` | 原生二进制 |
| `sim/legacy/` | 旧版代码（双重保护） |
| `sim/output/` | 仿真输出 |
| `model/` | ONNX 模型 |
| `__pycache__/` | Python 缓存 |

如果你执行 `git add -A`，这些文件**不会**被加入。

---

## 常见操作速查

### 获取依赖

```bash
flutter pub get    # 必须用 flutter（workspace 含 sirius）
```

### 真机运行

```bash
HAN_DOG_IMU_PORT=/dev/imu dart run han_dog/bin/han_dog.dart
```

### MuJoCo 仿真

```bash
# 终端 1
dart run han_dog/bin/server.dart

# 终端 2
python sim/scripts/walk_ref.py
```

### 部署到新机器

```bash
sudo bash scripts/setup_brainstem.sh
```

### 电机诊断

```bash
dart run han_dog/bin/ping.dart           # 16 电机连接检测
dart run han_dog/bin/calibrate_can.dart  # CAN 通道校准
```
