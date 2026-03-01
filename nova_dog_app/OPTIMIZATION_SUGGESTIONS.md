# 穹沛科技 - NOVA Dog 控制面板优化建议

## 1. 连接管理验证（Dashboard Page）

### 当前问题：
- IP 地址和端口输入没有格式验证
- 连接失败后没有重试机制
- 没有连接超时设置

### 优化建议：
```dart
// IP 地址验证
bool _validateIP(String ip) {
  final ipRegex = RegExp(r'^(\d{1,3}\.){3}\d{1,3}$');
  if (!ipRegex.hasMatch(ip)) return false;
  final parts = ip.split('.');
  return parts.every((part) => int.parse(part) <= 255);
}

// 端口验证
bool _validatePort(String port) {
  final p = int.tryParse(port);
  return p != null && p > 0 && p <= 65535;
}

// 添加连接超时
Future<void> _connect() async {
  if (!_validateIP(_hC.text.trim())) {
    AppToast.showError(context, 'IP 地址格式错误');
    return;
  }
  if (!_validatePort(_pC.text.trim())) {
    AppToast.showError(context, '端口号必须在 1-65535 之间');
    return;
  }
  // ... 连接逻辑
}
```

## 2. 参数范围验证（Params Page）

### 当前问题：
- KP/KD 值可以输入任意数字，没有合理范围限制
- 姿态角度值没有物理限制验证
- 导入配置文件没有格式验证

### 优化建议：
```dart
// 添加参数范围验证
class ParameterValidator {
  static const double kpMin = 0.0;
  static const double kpMax = 300.0;
  static const double kdMin = 0.0;
  static const double kdMax = 20.0;
  static const double jointAngleMin = -3.14; // -180度
  static const double jointAngleMax = 3.14;  // 180度

  static bool validateKp(double value) {
    return value >= kpMin && value <= kpMax;
  }

  static bool validateKd(double value) {
    return value >= kdMin && value <= kdMax;
  }

  static bool validateJointAngle(double value) {
    return value >= jointAngleMin && value <= jointAngleMax;
  }
}

// 在输入时添加验证
void _submitText() {
  final v = double.tryParse(_ctrl.text);
  if (v != null) {
    if (!ParameterValidator.validateKp(v)) {
      AppToast.showError(context, 'KP 值必须在 0-300 之间');
      return;
    }
    widget.onChanged(v.clamp(widget.min, widget.max));
  }
  setState(() => _editing = false);
}
```

## 3. 文件路径验证（Params Page - Models Tab）

### 当前问题：
- 导入模型时没有验证文件是否存在
- 没有验证文件扩展名
- 导出路径没有检查写入权限

### 优化建议：
```dart
Future<void> _importConfig() async {
  final path = await _showPathDialog('导入路径', '');
  if (path == null || path.trim().isEmpty) return;

  // 验证文件存在
  final file = File(path.trim());
  if (!await file.exists()) {
    if (mounted) AppToast.showError(context, '文件不存在');
    return;
  }

  // 验证文件扩展名
  if (!path.toLowerCase().endsWith('.json')) {
    if (mounted) AppToast.showError(context, '只支持 .json 格式');
    return;
  }

  // 验证文件大小
  final size = await file.length();
  if (size > 10 * 1024 * 1024) { // 10MB
    if (mounted) AppToast.showError(context, '文件过大（最大 10MB）');
    return;
  }

  try {
    _config = await RobotConfig.loadFromFile(path);
    setState(() => _modified = true);
    if (mounted) AppToast.showSuccess(context, '配置导入成功');
  } catch (e) {
    if (mounted) AppToast.showError(context, '导入失败: $e');
  }
}
```

## 4. SSH 连接验证（Models Tab - Remote Upload）

### 当前问题：
- SSH 密码明文存储在内存中
- 没有验证 SSH 连接参数
- 上传失败没有详细错误信息

### 优化建议：
```dart
// 添加 SSH 参数验证
bool _validateSshParams() {
  if (_hostCtrl.text.trim().isEmpty) {
    widget.onResult(false, '请输入目标 IP');
    return false;
  }
  if (!_validateIP(_hostCtrl.text.trim())) {
    widget.onResult(false, 'IP 地址格式错误');
    return false;
  }
  if (_userCtrl.text.trim().isEmpty) {
    widget.onResult(false, '请输入 SSH 用户名');
    return false;
  }
  if (_pathCtrl.text.trim().isEmpty) {
    widget.onResult(false, '请输入远程路径');
    return false;
  }
  return true;
}

Future<void> _upload() async {
  if (!_validateSshParams()) return;

  final models = widget.modelService.models;
  if (models.isEmpty) {
    widget.onResult(false, '无模型可上传');
    return;
  }

  // ... 上传逻辑
}
```

## 5. 控制输入验证（Control Page）

### 当前问题：
- 摇杆输入没有死区（deadzone）处理
- 没有速度限制保护
- 没有紧急停止功能

### 优化建议：
```dart
class ControlValidator {
  static const double deadzone = 0.05; // 5% 死区
  static const double maxSpeed = 1.0;
  static const double maxRotation = 1.0;

  static double applyDeadzone(double value) {
    if (value.abs() < deadzone) return 0.0;
    return value;
  }

  static double clampSpeed(double value) {
    return value.clamp(-maxSpeed, maxSpeed);
  }
}

void _updatePosition(Offset local, double radius) {
  final center = Offset(radius, radius);
  var delta = local - center;
  final maxR = radius - 28;
  if (delta.distance > maxR) {
    delta = delta / delta.distance * maxR;
  }
  setState(() => _pos = delta);

  var x = (delta.dx / maxR).clamp(-1.0, 1.0);
  var y = -(delta.dy / maxR).clamp(-1.0, 1.0);

  // 应用死区
  x = ControlValidator.applyDeadzone(x);
  y = ControlValidator.applyDeadzone(y);

  widget.onChanged(x, y);
}

// 添加紧急停止按钮
ElevatedButton(
  onPressed: () {
    _stopWalking();
    widget.grpc.disable();
    AppToast.showSuccess(context, '紧急停止');
  },
  style: ElevatedButton.styleFrom(
    backgroundColor: Colors.red,
    padding: EdgeInsets.all(20),
  ),
  child: Icon(Icons.stop, size: 40),
)
```

## 6. 数据持久化验证

### 当前问题：
- 预设配置保存没有备份机制
- 历史记录没有数量限制
- 没有数据损坏检测

### 优化建议：
```dart
class PresetService {
  static const int maxHistoryEntries = 100;

  Future<void> recordHistory(String name, RobotConfig config) async {
    final entry = HistoryEntry(
      presetName: name,
      savedAt: DateTime.now(),
      configPath: '${_historyDir.path}/${DateTime.now().millisecondsSinceEpoch}.json',
    );

    // 保存配置文件
    await config.saveToFile(entry.configPath);

    // 添加到历史记录
    _history.insert(0, entry);

    // 限制历史记录数量
    if (_history.length > maxHistoryEntries) {
      final removed = _history.removeLast();
      // 删除旧文件
      final file = File(removed.configPath);
      if (await file.exists()) {
        await file.delete();
      }
    }

    await _saveHistory();
  }

  // 添加数据完整性检查
  Future<bool> validateConfigFile(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return false;

      final content = await file.readAsString();
      final json = jsonDecode(content);

      // 验证必要字段
      if (!json.containsKey('inferKp') || !json.containsKey('inferKd')) {
        return false;
      }

      return true;
    } catch (e) {
      return false;
    }
  }
}
```

## 7. UI 响应式优化

### 当前问题：
- 长时间操作没有加载指示器
- 没有操作确认对话框
- 错误信息不够详细

### 优化建议：
```dart
// 添加加载指示器
Future<void> _saveChanges() async {
  // 显示加载对话框
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => Center(
      child: CircularProgressIndicator(),
    ),
  );

  try {
    final name = await _showNameDialog('保存为预设', '输入预设名称');
    if (name == null || name.trim().isEmpty) {
      Navigator.pop(context); // 关闭加载对话框
      return;
    }

    // 保存逻辑...

    Navigator.pop(context); // 关闭加载对话框
    if (mounted) AppToast.showSuccess(context, '已保存「$name」');
  } catch (e) {
    Navigator.pop(context); // 关闭加载对话框
    if (mounted) AppToast.showError(context, '保存失败: $e');
  }
}

// 添加危险操作确认
Future<void> _deletePreset(int index) async {
  final preset = _ps.presets[index];

  // 使用更详细的确认对话框
  final confirm = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Row(
        children: [
          Icon(Icons.warning, color: AppTheme.red),
          SizedBox(width: 8),
          Text('删除预设'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('确定要删除预设「${preset.name}」吗？'),
          SizedBox(height: 8),
          Text(
            '此操作无法撤销',
            style: TextStyle(
              fontSize: 12,
              color: AppTheme.red,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: FilledButton.styleFrom(backgroundColor: AppTheme.red),
          child: Text('确认删除'),
        ),
      ],
    ),
  );

  if (confirm != true) return;

  await _ps.delete(preset);
  setState(() {
    if (_activePresetIndex >= _ps.presets.length) {
      _activePresetIndex = _ps.presets.length - 1;
    }
  });
  if (mounted) AppToast.showSuccess(context, '已删除「${preset.name}」');
}
```

## 8. 性能优化

### 建议：
- 使用 `const` 构造函数减少重建
- 添加 `RepaintBoundary` 隔离重绘区域
- 使用 `ListView.builder` 替代直接生成列表
- 添加防抖（debounce）处理频繁更新

```dart
// 添加防抖
class Debouncer {
  final int milliseconds;
  Timer? _timer;

  Debouncer({required this.milliseconds});

  void run(VoidCallback action) {
    _timer?.cancel();
    _timer = Timer(Duration(milliseconds: milliseconds), action);
  }

  void dispose() {
    _timer?.cancel();
  }
}

// 使用防抖处理搜索
final _searchDebouncer = Debouncer(milliseconds: 300);

TextField(
  controller: _searchController,
  onChanged: (value) {
    _searchDebouncer.run(() {
      setState(() {
        // 执行搜索
      });
    });
  },
)
```

## 9. 安全性优化

### 建议：
- 添加操作日志记录
- 实现权限管理
- 添加数据加密（敏感配置）
- 实现会话超时机制

## 10. 用户体验优化

### 建议：
- 添加键盘快捷键支持
- 实现撤销/重做功能
- 添加操作历史记录
- 提供导出日志功能
- 添加帮助文档和工具提示

## 优先级排序

### 高优先级（安全性和稳定性）：
1. 连接管理验证
2. 参数范围验证
3. 文件路径验证
4. 控制输入验证（紧急停止）

### 中优先级（用户体验）：
5. UI 响应式优化
6. 数据持久化验证
7. SSH 连接验证

### 低优先级（性能和扩展）：
8. 性能优化
9. 安全性优化
10. 用户体验优化
