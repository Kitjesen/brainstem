## 1.4.1

### 文档
- `README.md`：完整重写（197行）——Brain API 说明、FSM 状态转换图、5 种行为规范、传感器接口定义、使用示例
- `cms.dart`：3 处英文文档注释改为中文（idleStream / transitionStream / walkStream 的 onDone 语义说明）

## 1.4.0

### 新增
- `memory.dart`：Memory 类补充内部状态保护，防止历史观测缓冲越界访问
- `gesture.dart`：GestureLibrary 注册默认手势时日志增强，registerDefaults() 加入 Logger 输出

### 变更
- `behaviour.dart`：Walk / StandUp / SitDown 行为类补全 `onError` + `StackTrace` 回调签名，与 strict 模式兼容
- `cms.dart`：FSM 过渡状态的 Fault 安全路径补充日志，StandUp→SitDown 防死循环逻辑注释说明

### 代码质量
- `analysis_options.yaml`：启用 `strict-casts / strict-raw-types / strict-inference`
- 全包将 `Future.delayed()` 统一改为 `Future<void>.delayed()`，满足 strict-inference 要求
- 测试文件（`cms_test.dart` / `behaviour_test.dart` / `gesture_test.dart`）：修复 strict 模式下类型推断警告（`<S>[]` 显式泛型、`Future<void>.delayed`）

### 测试
- 全包 181 个测试全部通过（含 han_dog 包）

## 1.3.0

### 新增
- **`MotorService.sendAction(JointsMatrix action)`**（`sensor.dart`）：补全电机输出接口，打通接口→实现的完整链路
- `han_dog_brain/test/observation_builder_test.dart`：12 个单元测试，锁定 `StandardObservationBuilder.build()` 的张量布局（含 JointsMatrix 每腿索引语义）

### 修复
- `observation_builder_test.dart` 揭示并记录了三个关键的索引语义：足端关节在 JointsMatrix 位于索引 12-15（末尾集中），髋关节索引为 0/3/6/9（非 0/4/8/12），`Vector3` 使用 float32（精度 1e-6）

## 1.2.0

### 新增
- **`ObservationBuilder` 接口**（`observation_builder.dart`）：将 `History → List<double>` 的张量编码逻辑从 `Walk` 中抽离为独立接口，支持自定义观测空间
  - `tensorSize`：每帧张量维度，用于 ONNX shape 验证
  - `build(History h)`：将一帧历史编码为定长 `List<double>`
  - `actionScale` / `standingPose`：供 Walk 做 `toRealAction` / `fromRealAction` 使用
- **`StandardObservationBuilder`**：标准 57 维实现，封装原 `Walk._toObservation()` 逻辑
  - 构造参数（均有默认值，向后兼容）：`standingPose`、`imuGyroscopeScale`、`jointVelocityScale`、`actionScale`
- `han_dog_brain.dart` 新增 `ObservationBuilder` / `StandardObservationBuilder` 导出

### 变更
- `Walk` 构造参数：4 个散装参数（`imuGyroscopeScale`、`jointVelocityScale`、`actionScale`、`standingPose`）合并为单一 `ObservationBuilder observationBuilder`
- `Walk` 内部观测缓冲从 `List<WalkObservation>` 改为平铺 `List<double>`，减少 50Hz 热路径的对象分配
- `Brain.standingPose`：可变字段改为 getter（`walk.observationBuilder.standingPose`），外部只读语义不变
- `factory Brain` 和 `Brain.switchProfile()` 均新增可选 `ObservationBuilder? observationBuilder` 参数；旧的散装 scale 参数保留作向后兼容兜底

### 移除
- `WalkObservation` 类（逻辑已移入 `StandardObservationBuilder.build()`）

## 1.1.0

### 新增
- `Brain.switchProfile()`：热替换内部 Walk / StandUp / SitDown 行为对象并重新加载 ONNX 模型；保留 Memory / ImuService / JointService / 时钟引用，不影响历史观测缓冲

### 设计说明
- FSM（`M`）无需任何修改：`M` 通过 `_brain.standUp.doing` 等间接引用行为，`switchProfile()` 替换对象后下次状态转换自动使用新行为
- `Brain.standingPose` / `walk` / `standUp` / `sitDown` / `idle` 由 `final` 改为可变字段（实现热替换的基础）

## 1.0.0

- Initial version.
