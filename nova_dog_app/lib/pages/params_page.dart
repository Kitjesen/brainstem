import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:han_dog_message/han_dog_message.dart' hide Duration, Matrix4, Matrix4Int32;
import '../services/grpc_service.dart';
import '../services/preset_service.dart';
import '../services/model_service.dart';
import '../models/robot_config.dart';
import '../theme/app_theme.dart';
import '../utils/app_toast.dart';
import '../utils/validators.dart';
import '../utils/debouncer.dart';

class ParamsPage extends StatefulWidget {
  final GrpcService grpc;
  final PresetService presetService;
  final ModelService modelService;
  const ParamsPage({super.key, required this.grpc, required this.presetService, required this.modelService});

  @override
  State<ParamsPage> createState() => _ParamsPageState();
}

/// Leg display order: FL, FR, RL, RR (reference). Each leg: 3 joint indices.
const List<(String, List<int>)> _legCards = [
  ('前左 (FL)', [3, 4, 5]),   // FL_hip, FL_thigh, FL_calf
  ('前右 (FR)', [0, 1, 2]),
  ('后左 (RL)', [9, 10, 11]),
  ('后右 (RR)', [6, 7, 8]),
];

class _ParamsPageState extends State<ParamsPage> {
  late RobotConfig _config;
  late TextEditingController _searchController;
  late Debouncer _searchDebouncer;
  bool _modified = false;
  int _tabIndex = 0;
  int _activePresetIndex = -1;
  bool _showHistory = false;
  DateTime? _lastSaved;

  PresetService get _ps => widget.presetService;

  @override
  void initState() {
    super.initState();
    _config = RobotConfig();
    _searchController = TextEditingController();
    _searchDebouncer = Debouncer(milliseconds: 300);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchDebouncer.dispose();
    super.dispose();
  }

  void _markModified() {
    if (!_modified) setState(() => _modified = true);
  }

  Future<void> _exportConfig() async {
    final result = await FilePicker.platform.saveFile(
      dialogTitle: '导出参数配置',
      fileName: 'robot_config.json',
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (result == null) return;
    final finalPath = result.toLowerCase().endsWith('.json') ? result : '$result.json';
    try {
      await _config.saveToFile(finalPath);
      if (mounted) AppToast.showSuccess(context, '已导出到 $finalPath');
    } catch (e) {
      if (mounted) AppToast.showError(context, '导出失败: $e');
    }
  }

  Future<void> _importConfig() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: '导入参数配置',
      type: FileType.custom,
      allowedExtensions: ['json'],
      allowMultiple: false,
    );
    final path = result?.files.single.path;
    if (path == null) return;

    final file = File(path);
    final size = await file.length();
    if (size > 10 * 1024 * 1024) {
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

  // ignore: unused_element
  Future<String?> _showPathDialog(String title, String defaultValue) {
    final controller = TextEditingController(text: defaultValue);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: '输入文件路径，如 C:\\config.json'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('确定')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Top bar — full width (reference: PARAMETER SUITE, version, status, search, Gains/Pose/Brain)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          color: cs.surface,
          child: Row(
            children: [
              // Left: title + version + unsaved badge
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(children: [
                    Text('参数配置', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: cs.onSurface)),
                    if (_modified) ...[
                      const SizedBox(width: 8),
                      AnimatedOpacity(
                        opacity: _modified ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 200),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.orange.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppTheme.orange.withValues(alpha: 0.3)),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Container(width: 5, height: 5, decoration: BoxDecoration(shape: BoxShape.circle, color: AppTheme.orange)),
                            const SizedBox(width: 4),
                            Text('未保存', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: AppTheme.orange)),
                          ]),
                        ),
                      ),
                    ],
                  ]),
                  const SizedBox(height: 2),
                  Text('v1.0.0', style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.5))),
                ],
              ),
              const SizedBox(width: 32),
              // Center: battery, latency, CONNECTED
              Icon(Icons.battery_charging_full, size: 18, color: cs.onSurface.withValues(alpha: 0.6)),
              const SizedBox(width: 4),
              Text('86%', style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.7))),
              const SizedBox(width: 16),
              Icon(Icons.speed, size: 16, color: cs.onSurface.withValues(alpha: 0.6)),
              const SizedBox(width: 4),
              Text('${widget.grpc.connected ? 12 : 0}ms', style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.7))),
              const SizedBox(width: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: (widget.grpc.connected ? AppTheme.green : AppTheme.red).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: widget.grpc.connected ? AppTheme.green : AppTheme.red,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      widget.grpc.connected ? '已连接' : '离线',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: widget.grpc.connected ? AppTheme.green : AppTheme.red),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              // Config import/export
              IconButton(
                icon: const Icon(Icons.upload_file_rounded),
                iconSize: 18,
                tooltip: '导入配置',
                onPressed: _importConfig,
              ),
              IconButton(
                icon: const Icon(Icons.download_rounded),
                iconSize: 18,
                tooltip: '导出配置',
                onPressed: _exportConfig,
              ),
              const SizedBox(width: 4),
              // Search
              SizedBox(
                width: 200,
                height: 36,
                child: TextField(
                  controller: _searchController,
                  onChanged: (value) {
                    _searchDebouncer.run(() {
                      setState(() {
                        // Search logic will be implemented here
                      });
                    });
                  },
                  decoration: InputDecoration(
                    hintText: '搜索参数...',
                    hintStyle: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.4)),
                    prefixIcon: Icon(Icons.search, size: 18, color: cs.onSurface.withValues(alpha: 0.4)),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: cs.outline.withValues(alpha: 0.5))),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: cs.outline.withValues(alpha: 0.5))),
                    filled: true,
                    fillColor: cs.surface.withValues(alpha: 0.5),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Tab pills: Gains | Pose | Brain
              _TabPill(label: '增益', selected: _tabIndex == 0, onTap: () => setState(() => _tabIndex = 0)),
              const SizedBox(width: 6),
              _TabPill(label: '姿态', selected: _tabIndex == 1, onTap: () => setState(() => _tabIndex = 1)),
              const SizedBox(width: 6),
              _TabPill(label: '智脑', selected: _tabIndex == 2, onTap: () => setState(() => _tabIndex = 2)),
              const SizedBox(width: 6),
              _TabPill(label: '模型', selected: _tabIndex == 3, onTap: () => setState(() => _tabIndex = 3)),
            ],
          ),
        ),

        Divider(height: 1, thickness: 1, color: cs.outline.withValues(alpha: 0.2)),
        // Body: main content + right sidebar (Quick Profiles)
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: IndexedStack(
                  index: _tabIndex,
                  children: [
                    _buildGainsTab(tt, cs),
                    _buildPoseTab(tt, cs),
                    _buildBrainTab(tt, cs),
                    _buildModelsTab(tt, cs),
                  ],
                ),
              ),
              _buildQuickProfilesSidebar(cs),
            ],
          ),
        ),
      ],
    );
  }

  Future<String?> _showNameDialog(String title, String hint, {String? defaultValue}) {
    final ctrl = TextEditingController(text: defaultValue ?? '');
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(controller: ctrl, autofocus: true, decoration: InputDecoration(hintText: hint, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('确定')),
        ],
      ),
    );
  }

  Future<void> _createPreset() async {
    final name = await _showNameDialog('新建预设', '输入预设名称');
    if (name == null || name.trim().isEmpty) return;
    await _ps.create(name.trim(), _config);
    setState(() => _activePresetIndex = 0);
    if (mounted) AppToast.showSuccess(context, '已创建预设「$name」');
  }

  Future<void> _saveChanges() async {
    final name = await _showNameDialog('保存为预设', '输入预设名称', defaultValue: _activePresetIndex >= 0 && _activePresetIndex < _ps.presets.length ? _ps.presets[_activePresetIndex].name : '当前配置');
    if (name == null || name.trim().isEmpty) return;
    // Record history
    await _ps.recordHistory(name.trim(), _config);
    // Save as new or overwrite
    if (_activePresetIndex >= 0 && _activePresetIndex < _ps.presets.length && _ps.presets[_activePresetIndex].name == name.trim()) {
      _ps.presets[_activePresetIndex].config = _config;
      await _ps.save(_ps.presets[_activePresetIndex]);
    } else {
      await _ps.create(name.trim(), _config);
      setState(() => _activePresetIndex = 0);
    }
    setState(() { _modified = false; _lastSaved = DateTime.now(); });
    if (mounted) AppToast.showSuccess(context, '已保存「$name」');
  }

  Future<void> _deletePreset(int index) async {
    final preset = _ps.presets[index];
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning, color: AppTheme.red, size: 24),
            const SizedBox(width: 8),
            const Text('删除预设'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('确定要删除预设「${preset.name}」吗？'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppTheme.red.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: AppTheme.red),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '此操作无法撤销',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.red,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.red),
            child: const Text('确认删除'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await _ps.delete(preset);
    setState(() { if (_activePresetIndex >= _ps.presets.length) _activePresetIndex = _ps.presets.length - 1; });
    if (mounted) AppToast.showSuccess(context, '已删除「${preset.name}」');
  }

  Future<void> _renamePreset(int index) async {
    final preset = _ps.presets[index];
    final name = await _showNameDialog('重命名预设', '输入新名称', defaultValue: preset.name);
    if (name == null || name.trim().isEmpty) return;
    await _ps.rename(preset, name.trim());
    setState(() {});
    if (mounted) AppToast.showSuccess(context, '已重命名为「$name」');
  }

  Future<void> _loadPreset(int index) async {
    final preset = _ps.presets[index];
    setState(() { _config = RobotConfig.fromJson(preset.config.toJson()); _activePresetIndex = index; _modified = false; });
    if (mounted) AppToast.showSuccess(context, '已加载「${preset.name}」');
  }

  Future<void> _loadHistoryEntry(HistoryEntry entry) async {
    try {
      final config = await _ps.loadHistory(entry);
      setState(() { _config = config; _modified = true; });
      if (mounted) AppToast.showSuccess(context, '已还原历史：${entry.presetName}');
    } catch (e) {
      if (mounted) AppToast.showError(context, '还原失败: $e');
    }
  }

  Widget _buildQuickProfilesSidebar(ColorScheme cs) {
    return Container(
      width: 280,
      margin: const EdgeInsets.only(right: 16, top: 16, bottom: 16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outline.withValues(alpha: 0.4)),
        boxShadow: Theme.of(context).brightness == Brightness.dark ? null : [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('快速预设', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: cs.onSurface)),
              const SizedBox(height: 4),
              Text('快速加载预设配置', style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.5))),
            ]),
          ),
          const SizedBox(height: 12),
          // Scrollable preset list
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                ..._ps.presets.asMap().entries.map((e) {
                  final i = e.key;
                  final p = e.value;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _PresetCardFull(
                      title: p.name,
                      subtitle: i == _activePresetIndex ? '当前' : _timeAgo(p.createdAt),
                      active: i == _activePresetIndex,
                      onTap: () => _loadPreset(i),
                      onDelete: () => _deletePreset(i),
                      onRename: () => _renamePreset(i),
                    ),
                  );
                }),
                // Create Preset button
                OutlinedButton.icon(
                  onPressed: _createPreset,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('新建预设'),
                  style: OutlinedButton.styleFrom(foregroundColor: cs.onSurface.withValues(alpha: 0.6), side: BorderSide(color: cs.outline.withValues(alpha: 0.5)), padding: const EdgeInsets.symmetric(vertical: 10)),
                ),
                const SizedBox(height: 12),
                // History toggle
                GestureDetector(
                  onTap: () => setState(() => _showHistory = !_showHistory),
                  child: Row(children: [
                    Icon(_showHistory ? Icons.expand_less : Icons.expand_more, size: 18, color: cs.onSurface.withValues(alpha: 0.5)),
                    const SizedBox(width: 6),
                    Text('历史 (${_ps.history.length})', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cs.onSurface.withValues(alpha: 0.5))),
                  ]),
                ),
                if (_showHistory) ..._ps.history.take(20).map((h) => ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  contentPadding: EdgeInsets.zero,
                  title: Text(h.presetName, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: cs.onSurface)),
                  subtitle: Text(_formatDateTime(h.savedAt), style: TextStyle(fontSize: 9, color: cs.onSurface.withValues(alpha: 0.4))),
                  leading: Icon(Icons.history, size: 16, color: cs.onSurface.withValues(alpha: 0.3)),
                  onTap: () => _loadHistoryEntry(h),
                )),
              ],
            ),
          ),
          // Bottom buttons
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(children: [
              // Last saved timestamp
              if (_lastSaved != null) ...[
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.check_circle_outline_rounded, size: 11, color: AppTheme.green),
                  const SizedBox(width: 4),
                  Text(
                    '上次保存：${_fmtHms(_lastSaved!)}',
                    style: TextStyle(fontSize: 10, color: cs.onSurface.withValues(alpha: 0.4),
                        fontFeatures: const [FontFeature.tabularFigures()]),
                  ),
                ]),
                const SizedBox(height: 6),
              ],
              SizedBox(width: double.infinity, child: FilledButton(
                onPressed: _modified ? _saveChanges : null,
                style: FilledButton.styleFrom(backgroundColor: AppTheme.brand, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12)),
                child: const Text('保存更改'),
              )),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () { setState(() { _config = RobotConfig(); _modified = false; }); AppToast.showSuccess(context, '已还原为默认配置'); },
                style: OutlinedButton.styleFrom(foregroundColor: cs.onSurface, side: BorderSide(color: cs.outline)),
                child: const Text('还原'),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  static String _fmtHms(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}:'
      '${dt.second.toString().padLeft(2, '0')}';

  static String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes}分钟前';
    if (diff.inDays < 1) return '${diff.inHours}小时前';
    return '${diff.inDays}天前';
  }

  static String _formatDateTime(DateTime dt) => '${dt.month}/${dt.day} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';

  // --- Gains Tab (reference: LOCOMOTION INFERENCE, 4 leg cards 2x2, sensitivity chart) ---
  Widget _buildGainsTab(TextTheme tt, ColorScheme cs) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section title + MODE + Reset Defaults
          Row(
            children: [
              Text('行走推理', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: cs.onSurface)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: cs.primary.withValues(alpha: 0.3)),
                ),
                child: Text('模式：TROT_WALK', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cs.primary)),
              ),
              const SizedBox(width: 12),
              TextButton.icon(
                onPressed: () {
                  setState(() { _config = RobotConfig(); _markModified(); });
                  AppToast.showSnapAlign(context, '已对齐默认值');
                },
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('重置默认'),
                style: TextButton.styleFrom(foregroundColor: cs.onSurface.withValues(alpha: 0.8)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // 4 leg cards in 2x2 layout
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _LegCardGain(title: _legCards[0].$1, indices: _legCards[0].$2, kp: _config.inferKp, kd: _config.inferKd, onChanged: _markModified)),
              const SizedBox(width: 14),
              Expanded(child: _LegCardGain(title: _legCards[1].$1, indices: _legCards[1].$2, kp: _config.inferKp, kd: _config.inferKd, onChanged: _markModified)),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _LegCardGain(title: _legCards[2].$1, indices: _legCards[2].$2, kp: _config.inferKp, kd: _config.inferKd, onChanged: _markModified)),
              const SizedBox(width: 14),
              Expanded(child: _LegCardGain(title: _legCards[3].$1, indices: _legCards[3].$2, kp: _config.inferKp, kd: _config.inferKd, onChanged: _markModified)),
            ],
          ),
          const SizedBox(height: 20),
          // Parameter Overview: avg KP/KD per leg
          _ParameterOverview(config: _config, cs: cs),
          const SizedBox(height: 20),
          // 当前推理增益：从 latestHistory.kp/kd 读取实际执行值
          _InferenceGainCard(history: widget.grpc.latestHistory, cs: cs),
        ],
      ),
    );
  }

  // --- Pose Tab (multi-pose with string import) ---
  Widget _buildPoseTab(TextTheme tt, ColorScheme cs) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Fixed poses
          _PoseCard(title: '站立姿态 (Standing Pose)', values: _config.standingPose, onChanged: _markModified, onPaste: () => _pasteImportPose(_config.standingPose)),
          const SizedBox(height: 14),
          _PoseCard(title: '坐下姿态 (Sitting Pose)', values: _config.sittingPose, onChanged: _markModified, onPaste: () => _pasteImportPose(_config.sittingPose)),
          const SizedBox(height: 20),
          // Custom poses header
          Row(children: [
            Text('自定义姿态', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: cs.onSurface)),
            const SizedBox(width: 8),
            Text('(${_config.customPoses.length})', style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.4))),
            const Spacer(),
            OutlinedButton.icon(
              onPressed: _addCustomPose,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('新建姿态'),
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
            ),
          ]),
          const SizedBox(height: 12),
          // Custom poses list
          ..._config.customPoses.entries.map((e) => Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: _PoseCard(
              title: e.key,
              values: e.value,
              onChanged: _markModified,
              onPaste: () => _pasteImportPose(e.value),
              onDelete: () { setState(() => _config.customPoses.remove(e.key)); _markModified(); },
              onRename: () => _renameCustomPose(e.key),
            ),
          )),
        ],
      ),
    );
  }

  Future<void> _addCustomPose() async {
    final name = await _showNameDialog('新建姿态', '输入姿态名称');
    if (name == null || name.trim().isEmpty) return;
    setState(() { _config.customPoses[name.trim()] = List.filled(16, 0.0); });
    _markModified();
  }

  Future<void> _renameCustomPose(String oldName) async {
    final name = await _showNameDialog('重命名姿态', '输入新名称', defaultValue: oldName);
    if (name == null || name.trim().isEmpty || name.trim() == oldName) return;
    setState(() {
      final values = _config.customPoses.remove(oldName);
      if (values != null) _config.customPoses[name.trim()] = values;
    });
    _markModified();
  }

  Future<void> _pasteImportPose(List<double> target) async {
    final result = await showDialog<List<double>?>(
      context: context,
      builder: (ctx) => _PasteImportDialog(),
    );
    if (result != null && result.length == 16) {
      setState(() { for (int i = 0; i < 16; i++) { target[i] = result[i]; } });
      _markModified();
      if (mounted) AppToast.showSuccess(context, '已导入 16 个关节值');
    }
  }

  // --- Brain Tab --- (grid: one full-width card, then two side-by-side)
  Widget _buildBrainTab(TextTheme tt, ColorScheme cs) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ParamCard(
            title: '基础参数',
            child: Column(
              children: [
                _ParamRow(label: '历史帧数', value: _config.historySize.toDouble(), min: 1, max: 20, isInt: true, onChanged: (v) { _config.historySize = v.toInt(); _markModified(); }),
                _ParamRow(label: '起立步数', value: _config.standUpCounts.toDouble(), min: 10, max: 500, isInt: true, onChanged: (v) { _config.standUpCounts = v.toInt(); _markModified(); }),
                _ParamRow(label: '坐下步数', value: _config.sitDownCounts.toDouble(), min: 10, max: 500, isInt: true, onChanged: (v) { _config.sitDownCounts = v.toInt(); _markModified(); }),
                _ParamRow(label: '陀螺仪增益', value: _config.imuGyroscopeScale, min: 0.01, max: 2.0, onChanged: (v) { _config.imuGyroscopeScale = v; _markModified(); }),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _ParamCard(
                  title: '关节速度缩放（4 组）',
                  child: Column(
                    children: List.generate(4, (i) => _ParamRow(
                      label: legGroups[i],
                      value: _config.jointVelocityScale[i],
                      min: 0.001,
                      max: 1.0,
                      onChanged: (v) { _config.jointVelocityScale[i] = v; _markModified(); },
                    )),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _ParamCard(
                  title: '动作缩放（4 组）',
                  child: Column(
                    children: List.generate(4, (i) => _ParamRow(
                      label: legGroups[i],
                      value: _config.actionScale[i],
                      min: 0.01,
                      max: 10.0,
                      onChanged: (v) { _config.actionScale[i] = v; _markModified(); },
                    )),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- Models Tab ---
  Widget _buildModelsTab(TextTheme tt, ColorScheme cs) {
    final ms = widget.modelService;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('模型管理', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: cs.onSurface)),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left: local model list
              Expanded(flex: 3, child: _ParamCard(
                title: '本地模型仓库 (${ms.models.length})',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ...ms.models.map((m) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: cs.onSurface.withValues(alpha: 0.02), borderRadius: BorderRadius.circular(8), border: Border.all(color: cs.outline.withValues(alpha: 0.3))),
                        child: Row(children: [
                          Icon(Icons.memory, size: 20, color: AppTheme.brand),
                          const SizedBox(width: 10),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(m.name, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurface)),
                            Text('${m.sizeLabel} · ${m.modified.month}/${m.modified.day} ${m.modified.hour}:${m.modified.minute.toString().padLeft(2, '0')}', style: TextStyle(fontSize: 10, color: cs.onSurface.withValues(alpha: 0.5))),
                          ])),
                          IconButton(icon: Icon(Icons.delete_outline, size: 18, color: AppTheme.red), onPressed: () async {
                            await ms.delete(m);
                            setState(() {});
                            if (mounted) AppToast.showSuccess(context, '已删除 ${m.name}');
                          }),
                        ]),
                      ),
                    )),
                    if (ms.models.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        child: Center(child: Text('暂无模型，点击右侧导入', style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.4)))),
                      ),
                  ],
                ),
              )),
              const SizedBox(width: 14),
              // Right: import + remote upload
              Expanded(flex: 2, child: Column(children: [
                _ParamCard(
                  title: '导入模型',
                  child: Column(children: [
                    Text('导入 .onnx 文件或直接放入仓库目录', style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.5))),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(child: OutlinedButton.icon(
                        onPressed: () async {
                          final result = await FilePicker.platform.pickFiles(
                            dialogTitle: '选择 ONNX 模型文件',
                            type: FileType.custom,
                            allowedExtensions: ['onnx'],
                            allowMultiple: false,
                          );
                          final path = result?.files.single.path;
                          if (path == null) return;
                          try {
                            await ms.importModel(path);
                            setState(() {});
                            if (mounted) AppToast.showSuccess(context, '已导入模型');
                          } catch (e) {
                            if (mounted) AppToast.showError(context, '导入失败: $e');
                          }
                        },
                        icon: const Icon(Icons.file_upload_outlined, size: 16),
                        label: const Text('导入文件'),
                      )),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: () async { await ms.scan(); if (!mounted) return; setState(() {}); AppToast.showSuccess(context, '已刷新'); },
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('刷新'),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(child: Text(ms.modelsPath, style: TextStyle(fontSize: 9, color: cs.onSurface.withValues(alpha: 0.3)), overflow: TextOverflow.ellipsis)),
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: () => ms.openModelsFolder(),
                        child: Text('打开文件夹', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.primary)),
                      ),
                    ]),
                  ]),
                ),
                const SizedBox(height: 14),
                _ParamCard(
                  title: '远程刷入 (SCP)',
                  child: _RemoteUploadPanel(
                    modelService: ms,
                    grpcHost: widget.grpc.host,
                    onResult: (ok, msg) {
                      if (ok) {
                        AppToast.showSuccess(context, msg);
                      } else {
                        AppToast.showError(context, msg);
                      }
                    },
                  ),
                ),
              ])),
            ],
          ),
          const SizedBox(height: 20),
          // Firmware OTA section
          _ParamCard(
            title: 'FIRMWARE OTA (固件远程推送)',
            child: _FirmwareOtaPanel(
              modelService: ms,
              grpcHost: widget.grpc.host,
              onResult: (ok, msg) {
                if (ok) { AppToast.showSuccess(context, msg); } else { AppToast.showError(context, msg); }
              },
            ),
          ),
        ],
      ),
    );
  }
}

// --- Reusable Widgets ---

class _TabPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _TabPill({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: selected ? AppTheme.brand : cs.surface,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: selected ? Colors.white : cs.onSurface.withValues(alpha: 0.7))),
        ),
      ),
    );
  }
}

/// Preset card with context menu for delete/rename.
class _PresetCardFull extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onRename;

  const _PresetCardFull({required this.title, required this.subtitle, required this.active, required this.onTap, required this.onDelete, required this.onRename});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: active ? cs.primary.withValues(alpha: 0.06) : cs.surface,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: active ? AppTheme.brand : cs.outline.withValues(alpha: 0.3), width: active ? 1.5 : 0.5),
          ),
          child: Row(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(color: active ? AppTheme.brand.withValues(alpha: 0.2) : cs.outline.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                child: Icon(Icons.tune, size: 18, color: active ? AppTheme.brand : cs.onSurface.withValues(alpha: 0.4)),
              ),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurface)),
                Text(subtitle, style: TextStyle(fontSize: 10, color: active ? AppTheme.brand : cs.onSurface.withValues(alpha: 0.5))),
              ])),
              if (active) ...[
                Icon(Icons.check_circle, size: 18, color: AppTheme.brand),
                const SizedBox(width: 4),
              ],
              PopupMenuButton<String>(
                padding: EdgeInsets.zero,
                iconSize: 18,
                icon: Icon(Icons.more_vert, size: 16, color: cs.onSurface.withValues(alpha: 0.3)),
                onSelected: (v) {
                  if (v == 'rename') onRename();
                  if (v == 'delete') onDelete();
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'rename', child: Row(children: [Icon(Icons.edit, size: 16), SizedBox(width: 8), Text('重命名')])),
                  const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_outline, size: 16, color: Colors.red), SizedBox(width: 8), Text('删除', style: TextStyle(color: Colors.red))])),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Single leg card for Gains with KP/KD sliders per joint.
class _LegCardGain extends StatefulWidget {
  final String title;
  final List<int> indices;
  final List<double> kp;
  final List<double> kd;
  final VoidCallback onChanged;

  const _LegCardGain({required this.title, required this.indices, required this.kp, required this.kd, required this.onChanged});

  @override
  State<_LegCardGain> createState() => _LegCardGainState();
}

class _LegCardGainState extends State<_LegCardGain> {
  String _jointLabel(int idx) {
    final n = jointNames[idx];
    final parts = n.split('_');
    if (parts.length >= 2) return '${parts[0]}_${parts[1][0].toUpperCase()}${parts[1].substring(1)}';
    return n;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outline.withValues(alpha: 0.4)),
        boxShadow: dark ? null : [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.arrow_forward_ios, size: 12, color: AppTheme.brand),
              const SizedBox(width: 8),
              Expanded(child: Text(widget.title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.onSurface))),
              Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: AppTheme.brand)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              SizedBox(width: 64, child: Text('关节', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: cs.onSurface.withValues(alpha: 0.5)))),
              Expanded(child: Text('KP（刚度）', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: cs.onSurface.withValues(alpha: 0.5)))),
              Expanded(child: Text('KD（阻尼）', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: cs.onSurface.withValues(alpha: 0.5)))),
            ],
          ),
          const SizedBox(height: 4),
          for (int i = 0; i < widget.indices.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  SizedBox(width: 64, child: Text(_jointLabel(widget.indices[i]), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cs.onSurface.withValues(alpha: 0.8)))),
                  Expanded(child: Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: _KpKdField(value: widget.kp[widget.indices[i]], max: 300, onChanged: (v) { setState(() { widget.kp[widget.indices[i]] = v; }); widget.onChanged(); }),
                  )),
                  Expanded(child: _KpKdField(value: widget.kd[widget.indices[i]], max: 20, onChanged: (v) { setState(() { widget.kd[widget.indices[i]] = v; }); widget.onChanged(); })),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _KpKdField extends StatefulWidget {
  final double value;
  final double max;
  final ValueChanged<double> onChanged;

  const _KpKdField({required this.value, required this.max, required this.onChanged});

  @override
  State<_KpKdField> createState() => _KpKdFieldState();
}

class _KpKdFieldState extends State<_KpKdField> {
  late TextEditingController _ctrl;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.value.toStringAsFixed(1));
  }

  @override
  void didUpdateWidget(covariant _KpKdField old) {
    super.didUpdateWidget(old);
    if (!_focused && old.value != widget.value) {
      _ctrl.text = widget.value.toStringAsFixed(1);
    }
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  void _submit() {
    final v = double.tryParse(_ctrl.text);
    if (v != null) {
      widget.onChanged(v.clamp(0, widget.max));
    } else {
      _ctrl.text = widget.value.toStringAsFixed(1);
    }
    setState(() => _focused = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Focus(
      onFocusChange: (f) { if (!f) _submit(); setState(() => _focused = f); },
      child: SizedBox(
        height: 28,
        child: TextField(
          controller: _ctrl,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _focused ? AppTheme.brand : cs.onSurface),
          textAlign: TextAlign.center,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: cs.outline.withValues(alpha: 0.35))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: AppTheme.brand, width: 1.5)),
          ),
          onSubmitted: (_) => _submit(),
          onEditingComplete: _submit,
        ),
      ),
    );
  }
}

/// Parameter Overview: avg KP/KD per leg, min/max range
class _ParameterOverview extends StatelessWidget {
  final RobotConfig config;
  final ColorScheme cs;

  const _ParameterOverview({required this.config, required this.cs});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    const legs = ['FL', 'FR', 'RL', 'RR'];
    const legIndices = [[3, 4, 5], [0, 1, 2], [9, 10, 11], [6, 7, 8]];
    const legColors = [Color(0xFF3B82F6), Color(0xFF10B981), Color(0xFF8B5CF6), Color(0xFFF59E0B)];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outline.withValues(alpha: 0.4)),
        boxShadow: dark ? null : [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.analytics_outlined, size: 18, color: AppTheme.brand),
            const SizedBox(width: 8),
            Text('参数概览', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.onSurface)),
          ]),
          const SizedBox(height: 14),
          Row(
            children: List.generate(4, (i) {
              final kpVals = legIndices[i].map((j) => config.inferKp[j]);
              final kdVals = legIndices[i].map((j) => config.inferKd[j]);
              final avgKp = kpVals.reduce((a, b) => a + b) / kpVals.length;
              final avgKd = kdVals.reduce((a, b) => a + b) / kdVals.length;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: i < 3 ? 12 : 0),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: legColors[i].withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: legColors[i].withValues(alpha: 0.15)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(legs[i], style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: legColors[i])),
                        const SizedBox(height: 8),
                        _OverviewRow(label: '均值 KP', value: avgKp.toStringAsFixed(1), cs: cs),
                        const SizedBox(height: 4),
                        _OverviewRow(label: '均值 KD', value: avgKd.toStringAsFixed(1), cs: cs),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: (avgKp / 300).clamp(0.0, 1.0),
                            minHeight: 4,
                            backgroundColor: cs.onSurface.withValues(alpha: 0.06),
                            valueColor: AlwaysStoppedAnimation(legColors[i]),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _OverviewRow extends StatelessWidget {
  final String label;
  final String value;
  final ColorScheme cs;

  const _OverviewRow({required this.label, required this.value, required this.cs});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: cs.onSurface.withValues(alpha: 0.4))),
        Text(value, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: cs.onSurface)),
      ],
    );
  }
}

/// 当前推理增益卡片：展示 latestHistory.kp/kd 的各腿均值
class _InferenceGainCard extends StatelessWidget {
  final History? history;
  final ColorScheme cs;

  const _InferenceGainCard({required this.history, required this.cs});

  // 关节组：腿名 → History.kp/kd 中的 index 列表（与 _legCards 一致）
  static const _legNames = ['前左 FL', '前右 FR', '后左 RL', '后右 RR'];
  static const _legIndices = [[3, 4, 5], [0, 1, 2], [9, 10, 11], [6, 7, 8]];
  static const _jointNames = ['髋', '大腿', '小腿'];
  static const _legColors = [Color(0xFF3B82F6), Color(0xFF10B981), Color(0xFF8B5CF6), Color(0xFFF59E0B)];

  double _avg(List<double> vals, List<int> indices) {
    if (vals.isEmpty) return 0.0;
    double sum = 0;
    int count = 0;
    for (final i in indices) {
      if (i < vals.length) { sum += vals[i]; count++; }
    }
    return count > 0 ? sum / count : 0.0;
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final kpVals = history?.hasKp() == true ? List<double>.from(history!.kp.values) : <double>[];
    final kdVals = history?.hasKd() == true ? List<double>.from(history!.kd.values) : <double>[];
    final hasData = history != null && kpVals.isNotEmpty && kdVals.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outline.withValues(alpha: 0.4)),
        boxShadow: dark ? null : [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题行
          Row(children: [
            Icon(Icons.tune_rounded, size: 18, color: AppTheme.teal),
            const SizedBox(width: 8),
            Text('当前推理增益', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.onSurface)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: (hasData ? AppTheme.green : cs.onSurface).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                hasData ? '实时' : '未连接',
                style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: hasData ? AppTheme.green : cs.onSurface.withValues(alpha: 0.35)),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          if (!hasData)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text('未连接或无推理数据', style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.3))),
              ),
            )
          else ...[
            // 表头
            Row(children: [
              SizedBox(width: 80, child: Text('腿 / 关节', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: cs.onSurface.withValues(alpha: 0.35), letterSpacing: 0.5))),
              Expanded(child: Text('Kp', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: cs.onSurface.withValues(alpha: 0.35), letterSpacing: 0.5), textAlign: TextAlign.center)),
              Expanded(child: Text('Kd', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: cs.onSurface.withValues(alpha: 0.35), letterSpacing: 0.5), textAlign: TextAlign.center)),
            ]),
            const SizedBox(height: 8),
            // 4 腿：每腿显示均值行 + 折叠关节明细
            ...List.generate(4, (leg) {
              final indices = _legIndices[leg];
              final avgKp = _avg(kpVals, indices);
              final avgKd = _avg(kdVals, indices);
              final color = _legColors[leg];
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Container(
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: color.withValues(alpha: 0.15)),
                  ),
                  child: Column(children: [
                    // 腿均值行
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                      child: Row(children: [
                        SizedBox(width: 80, child: Text(_legNames[leg], style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color))),
                        Expanded(child: Text(avgKp.toStringAsFixed(1), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.onSurface, fontFeatures: const [FontFeature.tabularFigures()]), textAlign: TextAlign.center)),
                        Expanded(child: Text(avgKd.toStringAsFixed(2), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.onSurface, fontFeatures: const [FontFeature.tabularFigures()]), textAlign: TextAlign.center)),
                      ]),
                    ),
                    // 关节明细（细分行）
                    ...List.generate(3, (ji) {
                      final idx = indices[ji];
                      final kp = idx < kpVals.length ? kpVals[idx] : 0.0;
                      final kd = idx < kdVals.length ? kdVals[idx] : 0.0;
                      return Container(
                        decoration: BoxDecoration(border: Border(top: BorderSide(color: color.withValues(alpha: 0.08)))),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        child: Row(children: [
                          SizedBox(width: 80, child: Text('  ${_jointNames[ji]}', style: TextStyle(fontSize: 9, color: cs.onSurface.withValues(alpha: 0.4)))),
                          Expanded(child: Text(kp.toStringAsFixed(1), style: TextStyle(fontSize: 9, color: cs.onSurface.withValues(alpha: 0.55), fontFeatures: const [FontFeature.tabularFigures()]), textAlign: TextAlign.center)),
                          Expanded(child: Text(kd.toStringAsFixed(2), style: TextStyle(fontSize: 9, color: cs.onSurface.withValues(alpha: 0.55), fontFeatures: const [FontFeature.tabularFigures()]), textAlign: TextAlign.center)),
                        ]),
                      );
                    }),
                  ]),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}

/// Parameter Suite style card: aligned, fills space, optional hover.
class _ParamCard extends StatefulWidget {
  final String title;
  final Widget child;
  const _ParamCard({required this.title, required this.child});

  @override
  State<_ParamCard> createState() => _ParamCardState();
}

class _ParamCardState extends State<_ParamCard> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          transform: _pressed ? Matrix4.diagonal3Values(0.995, 0.995, 1.0) : Matrix4.identity(),
          transformAlignment: Alignment.center,
          decoration: BoxDecoration(
            color: dark ? const Color(0xFF111C44) : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _hovered ? cs.primary.withValues(alpha: 0.35) : cs.outline.withValues(alpha: 0.4),
              width: _hovered ? 1 : 0.5,
            ),
            boxShadow: dark ? null : [BoxShadow(color: Colors.black.withValues(alpha: _hovered ? 0.08 : 0.05), blurRadius: _hovered ? 16 : 12, offset: Offset(0, _hovered ? 6 : 4))],
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(widget.title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: cs.onSurface)),
                const SizedBox(height: 12),
                widget.child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SmallButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _SmallButton({required this.label, required this.icon, required this.onTap});

  @override
  State<_SmallButton> createState() => _SmallButtonState();
}

class _SmallButtonState extends State<_SmallButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: _hovered ? cs.onSurface.withValues(alpha: 0.05) : cs.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: cs.outline, width: 0.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 14),
              const SizedBox(width: 6),
              Text(widget.label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pose card with title, paste import, optional delete/rename.
class _PoseCard extends StatelessWidget {
  final String title;
  final List<double> values;
  final VoidCallback onChanged;
  final VoidCallback onPaste;
  final VoidCallback? onDelete;
  final VoidCallback? onRename;

  const _PoseCard({required this.title, required this.values, required this.onChanged, required this.onPaste, this.onDelete, this.onRename});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outline.withValues(alpha: 0.4)),
        boxShadow: dark ? null : [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: cs.onSurface))),
          OutlinedButton.icon(
            onPressed: onPaste,
            icon: const Icon(Icons.content_paste, size: 14),
            label: const Text('粘贴导入'),
            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), textStyle: const TextStyle(fontSize: 11)),
          ),
          if (onRename != null) ...[
            const SizedBox(width: 6),
            IconButton(icon: Icon(Icons.edit, size: 16, color: cs.onSurface.withValues(alpha: 0.4)), onPressed: onRename, padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 28, minHeight: 28)),
          ],
          if (onDelete != null) ...[
            const SizedBox(width: 4),
            IconButton(icon: Icon(Icons.delete_outline, size: 16, color: AppTheme.red), onPressed: onDelete, padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 28, minHeight: 28)),
          ],
        ]),
        const SizedBox(height: 12),
        _PoseGrid(values: values, onChanged: onChanged),
      ]),
    );
  }
}

/// Dialog for pasting a string and auto-parsing 16 joint values.
class _PasteImportDialog extends StatefulWidget {
  @override
  State<_PasteImportDialog> createState() => _PasteImportDialogState();
}

class _PasteImportDialogState extends State<_PasteImportDialog> {
  final _ctrl = TextEditingController();
  List<double>? _parsed;

  void _parse() {
    final text = _ctrl.text;
    final matches = RegExp(r'-?\d+\.?\d*').allMatches(text);
    final values = matches.map((m) => double.tryParse(m.group(0)!) ?? 0.0).toList();
    // Pad to 16 or truncate
    while (values.length < 16) { values.add(0.0); }
    setState(() => _parsed = values.sublist(0, 16));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('粘贴导入姿态'),
      content: SizedBox(
        width: 500,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('支持 JSON 数组、逗号分隔、空格分隔等格式', style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.5))),
          const SizedBox(height: 10),
          TextField(
            controller: _ctrl,
            maxLines: 4,
            decoration: InputDecoration(
              hintText: '粘贴字符串，如 [0, -0.64, 1.6, 0, 0.64, -1.6, ...]',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onChanged: (_) => _parse(),
          ),
          if (_parsed != null) ...[
            const SizedBox(height: 12),
            Text('解析结果 (16 关节):', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cs.onSurface)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: List.generate(16, (i) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(4)),
                child: Text('${jointNames[i]}: ${_parsed![i].toStringAsFixed(3)}', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: cs.onSurface)),
              )),
            ),
          ],
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(onPressed: _parsed != null ? () => Navigator.pop(context, _parsed) : null, child: const Text('确认导入')),
      ],
    );
  }
}

class _PoseGrid extends StatelessWidget {
  final List<double> values;
  final VoidCallback onChanged;

  const _PoseGrid({required this.values, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: List.generate(16, (i) => SizedBox(
        width: 148,
        child: Row(
          children: [
            SizedBox(
              width: 62,
              child: Text(
                jointNames[i],
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cs.onSurface.withValues(alpha: 0.7)),
              ),
            ),
            Expanded(
              child: _InlineNumberField(
                value: values[i],
                onChanged: (v) {
                  values[i] = v;
                  onChanged();
                },
              ),
            ),
          ],
        ),
      )),
    );
  }
}

class _InlineNumberField extends StatefulWidget {
  final double value;
  final ValueChanged<double> onChanged;
  const _InlineNumberField({required this.value, required this.onChanged});

  @override
  State<_InlineNumberField> createState() => _InlineNumberFieldState();
}

class _InlineNumberFieldState extends State<_InlineNumberField> {
  late TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: _format(widget.value));
  }

  @override
  void didUpdateWidget(covariant _InlineNumberField old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) {
      _ctrl.text = _format(widget.value);
    }
  }

  String _format(double v) => v == v.truncateToDouble() ? v.toInt().toString() : v.toStringAsFixed(3);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return TextField(
      controller: _ctrl,
      style: TextStyle(fontSize: 12, fontFeatures: const [FontFeature.tabularFigures()]),
      decoration: InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        filled: true,
        fillColor: cs.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: cs.outline, width: 0.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: cs.outline, width: 0.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: cs.primary, width: 1),
        ),
      ),
      onSubmitted: (text) {
        final v = double.tryParse(text);
        if (v != null) widget.onChanged(v);
      },
    );
  }
}

class _ParamRow extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final bool isInt;
  final ValueChanged<double> onChanged;
  const _ParamRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    this.isInt = false,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 140, child: Text(label, style: tt.titleMedium)),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                activeTrackColor: cs.primary,
                inactiveTrackColor: cs.outline.withValues(alpha: 0.3),
                thumbColor: cs.primary,
                overlayShape: SliderComponentShape.noOverlay,
                trackHeight: 3,
              ),
              child: Slider(
                value: value.clamp(min, max),
                min: min,
                max: max,
                divisions: isInt ? (max - min).toInt() : null,
                onChanged: onChanged,
              ),
            ),
          ),
          SizedBox(
            width: 60,
            child: Text(
              isInt ? value.toInt().toString() : value.toStringAsFixed(3),
              style: tt.bodySmall?.copyWith(fontFeatures: [const FontFeature.tabularFigures()]),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}
// ══════════════════════════════════════
// Remote Upload Panel for Models tab
// ══════════════════════════════════════
class _RemoteUploadPanel extends StatefulWidget {
  final ModelService modelService;
  final String grpcHost;
  final void Function(bool success, String message) onResult;

  const _RemoteUploadPanel({required this.modelService, required this.grpcHost, required this.onResult});

  @override
  State<_RemoteUploadPanel> createState() => _RemoteUploadPanelState();
}

class _RemoteUploadPanelState extends State<_RemoteUploadPanel> {
  late TextEditingController _hostCtrl;
  late TextEditingController _userCtrl;
  late TextEditingController _pathCtrl;
  late TextEditingController _passCtrl;
  int _selectedModelIndex = 0;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _hostCtrl = TextEditingController(text: widget.grpcHost);
    _userCtrl = TextEditingController(text: widget.modelService.sshUser);
    _pathCtrl = TextEditingController(text: widget.modelService.sshRemotePath);
    _passCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _hostCtrl.dispose();
    _userCtrl.dispose();
    _pathCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _upload() async {
    final models = widget.modelService.models;
    if (models.isEmpty) { widget.onResult(false, '无模型可上传'); return; }

    // Validate SSH parameters
    final host = _hostCtrl.text.trim();
    final user = _userCtrl.text.trim();
    final remotePath = _pathCtrl.text.trim();

    if (!Validators.isValidIP(host)) {
      widget.onResult(false, 'IP 地址格式错误');
      return;
    }

    if (!Validators.isValidSshUsername(user)) {
      widget.onResult(false, 'SSH 用户名格式错误（只允许字母、数字、下划线、连字符）');
      return;
    }

    if (remotePath.isEmpty) {
      widget.onResult(false, '请输入远程路径');
      return;
    }

    if (_selectedModelIndex >= models.length) _selectedModelIndex = 0;
    final model = models[_selectedModelIndex];

    setState(() => _uploading = true);
    try {
      final result = await widget.modelService.uploadToRobot(
        modelPath: model.path,
        host: host,
        user: user,
        remotePath: remotePath,
        password: _passCtrl.text.isNotEmpty ? _passCtrl.text : null,
      );
      if (result.exitCode == 0) {
        widget.onResult(true, '已上传 ${model.name} 到 $host');
      } else {
        widget.onResult(false, '上传失败: ${result.stderr}');
      }
    } catch (e) {
      widget.onResult(false, '上传异常: $e');
    }
    if (mounted) setState(() => _uploading = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final models = widget.modelService.models;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _field('目标 IP', _hostCtrl, cs),
        const SizedBox(height: 8),
        _field('SSH 用户', _userCtrl, cs),
        const SizedBox(height: 8),
        _field('远程路径', _pathCtrl, cs),
        const SizedBox(height: 8),
        _field('密码 (可选)', _passCtrl, cs, obscure: true),
        const SizedBox(height: 10),
        if (models.isNotEmpty) ...[
          Text('选择模型:', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: cs.onSurface.withValues(alpha: 0.6))),
          const SizedBox(height: 6),
          DropdownButtonFormField<int>(
            // ignore: deprecated_member_use  — initialValue 不支持外部 setState 同步，保留 value
            value: _selectedModelIndex < models.length ? _selectedModelIndex : 0,
            decoration: InputDecoration(isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
            items: models.asMap().entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value.name, style: const TextStyle(fontSize: 11)))).toList(),
            onChanged: (v) => setState(() => _selectedModelIndex = v ?? 0),
          ),
          const SizedBox(height: 12),
        ],
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _uploading || models.isEmpty ? null : _upload,
            icon: _uploading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.upload_rounded, size: 18),
            label: Text(_uploading ? '上传中...' : '刷入模型'),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.green, foregroundColor: Colors.white),
          ),
        ),
      ],
    );
  }

  Widget _field(String label, TextEditingController ctrl, ColorScheme cs, {bool obscure = false}) {
    return TextField(
      controller: ctrl,
      obscureText: obscure,
      style: TextStyle(fontSize: 11, color: cs.onSurface),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(fontSize: 10, color: cs.onSurface.withValues(alpha: 0.5)),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: cs.outline.withValues(alpha: 0.5))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: cs.outline.withValues(alpha: 0.5))),
      ),
    );
  }
}

// ══════════════════════════════════════
// Firmware OTA Panel
// ══════════════════════════════════════
class _FirmwareOtaPanel extends StatefulWidget {
  final ModelService modelService;
  final String grpcHost;
  final void Function(bool success, String message) onResult;

  const _FirmwareOtaPanel({required this.modelService, required this.grpcHost, required this.onResult});

  @override
  State<_FirmwareOtaPanel> createState() => _FirmwareOtaPanelState();
}

class _FirmwareOtaPanelState extends State<_FirmwareOtaPanel> {
  late TextEditingController _firmwarePathCtrl;
  late TextEditingController _hostCtrl;
  late TextEditingController _userCtrl;
  late TextEditingController _remotePathCtrl;
  late TextEditingController _passCtrl;
  late TextEditingController _restartCmdCtrl;
  bool _uploading = false;
  bool _restartAfterUpload = false;

  @override
  void initState() {
    super.initState();
    _firmwarePathCtrl = TextEditingController();
    _hostCtrl = TextEditingController(text: widget.grpcHost);
    _userCtrl = TextEditingController(text: 'pi');
    _remotePathCtrl = TextEditingController(text: '~/han_dog/bin/');
    _passCtrl = TextEditingController();
    _restartCmdCtrl = TextEditingController(text: 'sudo systemctl restart han_dog');
  }

  @override
  void dispose() {
    _firmwarePathCtrl.dispose(); _hostCtrl.dispose(); _userCtrl.dispose();
    _remotePathCtrl.dispose(); _passCtrl.dispose(); _restartCmdCtrl.dispose();
    super.dispose();
  }

  Future<void> _upload() async {
    final path = _firmwarePathCtrl.text.trim();
    final host = _hostCtrl.text.trim();
    final user = _userCtrl.text.trim();
    final remotePath = _remotePathCtrl.text.trim();

    // Validate firmware path
    if (path.isEmpty) {
      widget.onResult(false, '请输入固件文件路径');
      return;
    }

    if (!Validators.isValidFilePath(path)) {
      widget.onResult(false, '文件路径包含非法字符');
      return;
    }

    // Check file exists
    final file = File(path);
    if (!await file.exists()) {
      widget.onResult(false, '固件文件不存在');
      return;
    }

    // Validate SSH parameters
    if (!Validators.isValidIP(host)) {
      widget.onResult(false, 'IP 地址格式错误');
      return;
    }

    if (!Validators.isValidSshUsername(user)) {
      widget.onResult(false, 'SSH 用户名格式错误');
      return;
    }

    if (remotePath.isEmpty) {
      widget.onResult(false, '请输入远程路径');
      return;
    }

    setState(() => _uploading = true);
    try {
      final result = await widget.modelService.uploadFirmware(
        firmwarePath: path,
        host: host,
        user: user,
        remotePath: remotePath,
        password: _passCtrl.text.isNotEmpty ? _passCtrl.text : null,
      );
      if (result.exitCode != 0) {
        widget.onResult(false, '上传失败: ${result.stderr}');
        if (mounted) setState(() => _uploading = false);
        return;
      }
      if (_restartAfterUpload && _restartCmdCtrl.text.trim().isNotEmpty) {
        final restart = await widget.modelService.sshCommand(
          host: host,
          user: user,
          command: _restartCmdCtrl.text.trim(),
          password: _passCtrl.text.isNotEmpty ? _passCtrl.text : null,
        );
        if (restart.exitCode != 0) {
          widget.onResult(false, '固件已上传，但重启失败: ${restart.stderr}');
          if (mounted) setState(() => _uploading = false);
          return;
        }
      }
      widget.onResult(true, '固件已推送到 $host${_restartAfterUpload ? ' 并已重启服务' : ''}');
    } catch (e) {
      widget.onResult(false, '异常: $e');
    }
    if (mounted) setState(() => _uploading = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('将编译好的 han_dog 可执行文件推送到机器人', style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.5))),
      const SizedBox(height: 10),
      _otaField('固件文件路径', _firmwarePathCtrl, cs, hint: 'D:\\build\\han_dog.exe'),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: _otaField('目标 IP', _hostCtrl, cs)),
        const SizedBox(width: 8),
        Expanded(child: _otaField('SSH 用户', _userCtrl, cs)),
      ]),
      const SizedBox(height: 8),
      _otaField('远程目标路径', _remotePathCtrl, cs),
      const SizedBox(height: 8),
      _otaField('密码 (可选)', _passCtrl, cs, obscure: true),
      const SizedBox(height: 10),
      Row(children: [
        SizedBox(width: 24, height: 24, child: Checkbox(value: _restartAfterUpload, onChanged: (v) => setState(() => _restartAfterUpload = v ?? false))),
        const SizedBox(width: 6),
        Text('上传后重启服务', style: TextStyle(fontSize: 11, color: cs.onSurface)),
      ]),
      if (_restartAfterUpload) ...[const SizedBox(height: 6), _otaField('重启命令', _restartCmdCtrl, cs)],
      const SizedBox(height: 12),
      SizedBox(width: double.infinity, child: FilledButton.icon(
        onPressed: _uploading ? null : _upload,
        icon: _uploading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.rocket_launch, size: 18),
        label: Text(_uploading ? '推送中...' : '推送固件'),
        style: FilledButton.styleFrom(backgroundColor: AppTheme.orange, foregroundColor: Colors.white),
      )),
    ]);
  }

  Widget _otaField(String label, TextEditingController ctrl, ColorScheme cs, {bool obscure = false, String? hint}) {
    return TextField(
      controller: ctrl, obscureText: obscure,
      style: TextStyle(fontSize: 11, color: cs.onSurface),
      decoration: InputDecoration(
        labelText: label, hintText: hint,
        labelStyle: TextStyle(fontSize: 10, color: cs.onSurface.withValues(alpha: 0.5)),
        hintStyle: TextStyle(fontSize: 10, color: cs.onSurface.withValues(alpha: 0.3)),
        isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: cs.outline.withValues(alpha: 0.5))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: cs.outline.withValues(alpha: 0.5))),
      ),
    );
  }
}
