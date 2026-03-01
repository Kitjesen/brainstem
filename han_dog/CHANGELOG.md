## 2.0.0

### 安全与可靠性
- **关机硬限时**：`_registerShutdown()` 增加 15s 全局 `Timer(exit(1))`，防止任意步骤挂死进程；gRPC shutdown 和 `m.close()` 分别加 3s/2s 超时
- **ONNX 加载重试**：最多 3 次（2s/4s 退避），失败后安全 `joint.disable()` 再退出
- **关节位置安全限位**：`startJointLimitMonitoring(limitRad)` 每 tick 检查 16 关节绝对值，超限立即 `arbiter.fault()`；新增环境变量 `HAN_DOG_JOINT_LIMIT_RAD`（默认 π rad）
- **YUNZHUO 双手偏航**：`direction` 流中 `rightStick.x × 0.5` 叠加到旋转轴；`LT` = 精确模式 0.5×，`RT` = 冲刺模式 1.5×
- **FSM 启动超时**：`firstWhere(Grounded).timeout(_cfg.startupTimeout)`；新增 `HAN_DOG_STARTUP_TIMEOUT`（默认 10s）

### 配置（`HanDogConfig`）
- `validate()` 返回类型从 `bool` 改为 `List<String>`（**破坏性变更**），返回所有错误描述；新增 `isValid` getter
- 新增字段：`startupTimeoutSec` / `startupTimeout`、`jointLimitRad`、`logDir`（`HAN_DOG_LOG_DIR`，默认 `logs`）
- `toString()` 包含全部新字段

### 日志持久化
- `setupLogging({String logDir = ''})` 新增 `logDir` 参数：非空时写入每日 `han_dog_YYYYMMDD.log`（同步 `RandomAccessFile`，`FileMode.append`）
- 启动时自动删除 7 天前旧日志文件（`_cleanOldLogs()`）

### 监控（`monitoring.dart`）
- `startSensorMonitoring()`：双阈值——首次降频仅 warning，连续 `threshold` 次才 Fault；恢复时记录持续低频帧数
- 新增 `startJointLimitMonitoring()`：16 关节位置超限即时 Fault，一帧只报一次
- `startDebugTui()` 新增 `ControlArbiter?` 参数，TUI 显示当前控制权；ANSI 颜色（≥45Hz 绿 / ≥30Hz 黄 / <30Hz 红）

### 策略管理（Profile）
- `RobotProfile` 新增 `description` 字段（可选，默认 `''`）；`fromJson` 改为严格校验（缺字段/类型错误均带字段名）
- `ProfileManager._profiles` 改为可变 `Map.of()`；新增 `reload(profileDir)` 方法：热扫描目录、添加新策略/更新非当前策略，切换进行中时跳过
- `ProfileManager` 新增 `descriptions` / `currentDescription` getter
- `han_dog.dart` 每 30s 调用 `pm.reload()`，关机时取消定时器（`_profileReloadTimer`）

### 其他改进
- `ControlArbiter`：`OwnershipEvent` 带 `reason` 字段 + 最近 20 条历史环形缓冲区
- `RobotProfile.fromJson`：引入 `_reqString` / `_joints16` 工具方法，错误信息精确定位字段
- `GainManager`：增益切换日志 + `identical()` 去重 `onChanged` 回调
- `ProfileManager.switchTo()`：`_switching` 防并发 + 失败自动回滚增益（try/catch + rethrow）
- `UnifiedCmsServer`：`_lastCommandAt` 时间戳，`_dispatch()` 记录命令间隔毫秒
- `SimSensor`：NaN/Inf 精确字段名定位 + `droppedFrames` 计数器
- 所有硬件驱动（`RealImu`/`RealJoint`/`RealController`）：补全 open/reopen/dispose 操作日志及 `onError` 回调

### DevOps
- `.github/workflows/ci.yml`：Dart analyze+test（ubuntu-latest）+ Flutter Windows release 构建 + 制品上传（7天保留）
- `Dockerfile.sim`：仿真服务器两阶段容器化（`dart:stable` 编译 → `ubuntu:22.04` 运行，挂载 `/app/model`，暴露 13145）

### 测试
- `han_dog_test.dart`：新增 HanDogConfig 校验、ControlArbiter 历史/幂等/抢占、RobotProfile 解析错误路径等 22 个测试
- `profile_manager_test.dart`：新增并发切换保护、失败回滚测试
- `analysis_options.yaml`：启用 `strict-casts / strict-raw-types / strict-inference`

## 1.3.0

### 新增
- `RealJoint` 实现 `MotorService` 接口：`enable()` / `disable()` 返回 `Future<void>`，新增 `sendAction(JointsMatrix)` 委托 `realActionExt()`

### 修复
- `SimImu.initialProjectedGravity`：从 `Vector3.zero()` 改为 `Vector3(0, 0, -1)`，修复仿真第 0 帧重力观测与后续帧不一致的问题
- `han_dog.dart`：`UnifiedCmsServer` 补传 `motor: joint`，修复 gRPC `enable` / `disable` 指令实际上是空操作的 bug

## 1.2.0

### 新增
- `RobotProfile.toObservationBuilder()`：从 profile 参数一键生成 `StandardObservationBuilder`，供 `ProfileManager` 传入 `Brain.switchProfile()`

### 变更
- `ProfileManager.switchTo()` 改用 `p.toObservationBuilder()` 传入 Brain，策略切换时不再传递散装 scale 参数

## 1.1.0

### 新增
- **策略切换（Profile Switching）**：运行时热切换 ONNX 模型、站姿、PD 增益，无需重启
  - `RobotProfile`：数据类，封装模型路径 / 姿态 / 增益 / 缩放参数
  - `ProfileManager`：编排 Brain + GainManager + RealControlDog 的统一切换入口
  - `loadProfiles(dir)`：从目录扫描 `.json` 文件，返回 `Map<String, RobotProfile>`
- **YUNZHUO R2 按钮**（CH16）触发 `ProfileManager.toggle()`，在 Grounded 状态下循环切换策略
- `RealControlDog` 新增 `onProfileSwitch` 回调 + `switchGains()` 方法
- `GainManager` 新增 `switchGains()` 方法
- `UnifiedCmsServer` 新增 `profileManager` 字段、`switchProfile()` / `getProfile()` 方法（待 proto 重生成后升级为 gRPC）
- `HanDogConfig` 新增 `profileDir` 配置项（环境变量 `HAN_DOG_PROFILE_DIR`，默认 `profiles/`）
- `profiles/default.json`：开箱即用的示例策略配置文件
- `han_dog.dart` / `server.dart` 两个入口均集成 ProfileManager

### 修复
- `RealControlDog` 测试（`real_control_dog_test.dart`）补充 `switchProfile` 流 mock，修复 18 个测试失败

## 1.0.0

- Initial version.
