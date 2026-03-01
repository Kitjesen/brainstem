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
