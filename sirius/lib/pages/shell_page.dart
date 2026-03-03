import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import '../services/data_recorder.dart';
import '../services/device_registry.dart';
import '../services/grpc_service.dart';
import '../widgets/joystick_pad.dart';
import '../services/preset_service.dart';
import '../services/model_service.dart';
import '../services/run_history_service.dart';
import '../theme/app_theme.dart';
import '../utils/app_toast.dart';
import '../widgets/sidebar.dart';
import 'dashboard_page.dart';
import 'monitor_page.dart';
import 'control_page.dart';
import 'params_page.dart';
import 'protocol_page.dart';
import 'imu_page.dart';
import 'history_page.dart';
import 'brain_page.dart';
import 'ota_page.dart';

class ShellPage extends StatefulWidget {
  final VoidCallback onToggleTheme;
  final VoidCallback onToggleLanguage;
  final bool isDark;
  final double textScale;
  final VoidCallback onScaleUp;
  final VoidCallback onScaleDown;
  final BrandColor brandColor;
  final ValueChanged<BrandColor> onChangeBrandColor;

  const ShellPage({
    super.key,
    required this.onToggleTheme, required this.onToggleLanguage, required this.isDark,
    required this.textScale, required this.onScaleUp, required this.onScaleDown,
    required this.brandColor, required this.onChangeBrandColor,
  });

  @override State<ShellPage> createState() => _ShellPageState();
}

class _ShellPageState extends State<ShellPage> {
  int _selectedIndex = 0;
  final GrpcService _grpc = GrpcService();
  final PresetService _presetService = PresetService();
  final ModelService _modelService = ModelService();
  final RunHistoryService _runHistory = RunHistoryService();
  final DeviceRegistry _deviceRegistry = DeviceRegistry();
  final DataRecorder _recorder = DataRecorder();
  final ValueNotifier<WalkSpeed> _speedNotifier = ValueNotifier(WalkSpeed.normal);
  bool _wasConnected = false;
  bool _showHelp = false;
  bool _showCommandPalette = false;
  bool _sidebarCollapsed = false;

  // ── Keyboard walk ──
  final _focusNode = FocusNode();
  final _keysDown = <LogicalKeyboardKey>{};
  final ValueNotifier<Set<String>> _keysNotifier = ValueNotifier({});
  Timer? _keyWalkTimer;
  static final _walkKeys = {
    LogicalKeyboardKey.keyW, LogicalKeyboardKey.keyS,
    LogicalKeyboardKey.keyA, LogicalKeyboardKey.keyD,
    LogicalKeyboardKey.keyQ, LogicalKeyboardKey.keyE,
  };

  @override void initState() {
    super.initState();
    _grpc.addListener(_onGrpcChanged);
    _grpc.onErrorNotify = (msg) {
      if (mounted) AppToast.showError(context, msg);
    };
    _presetService.init().then((_) { if (mounted) setState(() {}); });
    _modelService.init().then((_) { if (mounted) setState(() {}); });
    _runHistory.init();
    _deviceRegistry.load();
  }

  @override void dispose() {
    _grpc.removeListener(_onGrpcChanged);
    _grpc.dispose();
    _focusNode.dispose();
    _keyWalkTimer?.cancel();
    _speedNotifier.dispose();
    _keysNotifier.dispose();
    super.dispose();
  }

  KeyEventResult _onKeyEvent(FocusNode _, KeyEvent event) {
    // Ignore keyboard shortcuts when a text field is focused
    final primary = FocusManager.instance.primaryFocus;
    if (primary != _focusNode && primary?.context?.widget is EditableText) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;

    if (event is KeyDownEvent) {
      _keysDown.add(key);

      // One-shot commands
      if (key == LogicalKeyboardKey.space) {
        if (_grpc.connected) _grpc.standUp();
      } else if (key == LogicalKeyboardKey.keyZ) {
        if (_grpc.connected) _grpc.sitDown();
      } else if (key == LogicalKeyboardKey.f1) {
        if (_grpc.connected) _grpc.enable();
      } else if (key == LogicalKeyboardKey.f2) {
        if (_grpc.connected) _grpc.disable();
      } else if (key == LogicalKeyboardKey.f3) {
        _speedNotifier.value = WalkSpeed.slow;
      } else if (key == LogicalKeyboardKey.f4) {
        _speedNotifier.value = WalkSpeed.normal;
      } else if (key == LogicalKeyboardKey.f5) {
        _speedNotifier.value = WalkSpeed.fast;
      } else if (key == LogicalKeyboardKey.f12) {
        setState(() => _showHelp = !_showHelp);
      } else if (key == LogicalKeyboardKey.escape && _showHelp) {
        setState(() => _showHelp = false);
      } else if (key == LogicalKeyboardKey.escape && _showCommandPalette) {
        setState(() => _showCommandPalette = false);
      } else if (event.character == 'k' &&
          HardwareKeyboard.instance.isControlPressed) {
        setState(() => _showCommandPalette = !_showCommandPalette);
      } else if (key == LogicalKeyboardKey.f11) {
        _toggleFullscreen();
      }

      // Start walk ticker if a walk key was pressed
      if (_walkKeys.contains(key)) _startKeyWalk();
      // Sync active walk keys to notifier
      _keysNotifier.value = {
        for (final k in _keysDown.intersection(_walkKeys))
          k.keyLabel,
      };
    } else if (event is KeyUpEvent) {
      _keysDown.remove(key);
      _keysNotifier.value = {
        for (final k in _keysDown.intersection(_walkKeys))
          k.keyLabel,
      };
      if (_keysDown.intersection(_walkKeys).isEmpty) {
        _keyWalkTimer?.cancel();
        _keyWalkTimer = null;
        if (_grpc.connected) _grpc.walk(0, 0, 0);
      }
    }
    return KeyEventResult.ignored;
  }

  void _startKeyWalk() {
    _keyWalkTimer ??= Timer.periodic(const Duration(milliseconds: 33), (_) {
      double x = 0, y = 0, z = 0;
      if (_keysDown.contains(LogicalKeyboardKey.keyW)) x += 1;
      if (_keysDown.contains(LogicalKeyboardKey.keyS)) x -= 1;
      if (_keysDown.contains(LogicalKeyboardKey.keyA)) y -= 1;
      if (_keysDown.contains(LogicalKeyboardKey.keyD)) y += 1;
      if (_keysDown.contains(LogicalKeyboardKey.keyQ)) z -= 1;
      if (_keysDown.contains(LogicalKeyboardKey.keyE)) z += 1;
      if (x == 0 && y == 0 && z == 0) {
        _keyWalkTimer?.cancel();
        _keyWalkTimer = null;
        return;
      }
      if (_grpc.connected) _grpc.walk(x * 0.55, y * 0.55, z * 0.3);
    });
  }
  Future<void> _toggleFullscreen() async {
    final isFull = await windowManager.isFullScreen();
    await windowManager.setFullScreen(!isFull);
  }

  void _onGrpcChanged() {
    if (mounted) setState(() {});
    // Feed recorder with latest IMU + joint data
    if (_grpc.connected && _recorder.isRecording) {
      _recorder.recordFrame(imu: _grpc.latestImu, joints: _grpc.latestJoints);
    }
    if (_grpc.connected && !_wasConnected) {
      _runHistory.onConnect(_grpc.host, _grpc.port);
      _deviceRegistry.touch(_grpc.host, _grpc.port);
      _wasConnected = true;
    } else if (!_grpc.connected && _wasConnected) {
      _runHistory.onDisconnect();
      _wasConnected = false;
    }
  }

  Map<int, int> _computeBadges() {
    final badges = <int, int>{};
    // Badge on Monitor (index 1): count error-level protocol log entries in last 60s
    final cutoff = DateTime.now().subtract(const Duration(seconds: 60));
    final errCount = _grpc.protocolLog.where((e) {
      if (e.time.isBefore(cutoff)) return false;
      final s = '${e.method} ${e.summary} ${e.direction}'.toLowerCase();
      return s.contains('error') || s.contains('fault') || s.contains('fail') || s.contains('⚠');
    }).length;
    if (errCount > 0) badges[1] = errCount;
    return badges;
  }

  Widget _buildPage() {
    switch (_selectedIndex) {
      case 0: return DashboardPage(grpc: _grpc, registry: _deviceRegistry, speedNotifier: _speedNotifier, keysNotifier: _keysNotifier);
      case 1: return MonitorPage(grpc: _grpc);
      case 2: return ControlPage(grpc: _grpc);
      case 3: return ParamsPage(grpc: _grpc, presetService: _presetService, modelService: _modelService);
      case 4: return ProtocolPage(grpc: _grpc);
      case 5: return ImuPage(grpc: _grpc, recorder: _recorder);
      case 6: return HistoryPage(runHistory: _runHistory);
      case 7: return BrainPage(grpc: _grpc);
      case 8: return const OtaPage();
      default: return DashboardPage(grpc: _grpc, registry: _deviceRegistry, speedNotifier: _speedNotifier, keysNotifier: _keysNotifier);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _onKeyEvent,
      child: Scaffold(
        body: Stack(children: [
          Column(children: [
            // Custom title bar with drag area and window controls
            _CustomTitleBar(grpc: _grpc),
            // Main content
            Expanded(
              child: Row(children: [
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Sidebar(
                    selectedIndex: _selectedIndex,
                    onSelect: (i) => setState(() => _selectedIndex = i),
                    isDark: widget.isDark,
                    onToggleTheme: widget.onToggleTheme,
                    onToggleLanguage: widget.onToggleLanguage,
                    isConnected: _grpc.connected,
                    connectionInfo: '${_grpc.host}:${_grpc.port}',
                    textScale: widget.textScale,
                    onScaleUp: widget.onScaleUp,
                    onScaleDown: widget.onScaleDown,
                    brandColor: widget.brandColor,
                    onChangeBrandColor: widget.onChangeBrandColor,
                    cmsState: _grpc.cmsState,
                    historyHz: _grpc.historyHz,
                    lastRttMs: _grpc.lastRttMs,
                    collapsed: _sidebarCollapsed,
                    onToggleCollapse: () => setState(() => _sidebarCollapsed = !_sidebarCollapsed),
                    badges: _selectedIndex != 1 ? _computeBadges() : {},
                  ),
                ),
                Expanded(child: _buildPage()),
              ]),
            ),
          ]),
          // Reconnecting overlay
          if (_grpc.isReconnecting)
            _ReconnectingOverlay(grpc: _grpc),
          // Keyboard shortcut help overlay (F12)
          if (_showHelp)
            _ShortcutHelpOverlay(onClose: () => setState(() => _showHelp = false)),
          // Command palette (Ctrl+K)
          if (_showCommandPalette)
            _CommandPalette(
              grpc: _grpc,
              onClose: () => setState(() => _showCommandPalette = false),
              onNavigate: (i) {
                setState(() {
                  _selectedIndex = i;
                  _showCommandPalette = false;
                });
              },
            ),
        ]),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════
// Reconnecting overlay
// ══════════════════════════════════════════════════════
class _ReconnectingOverlay extends StatelessWidget {
  final GrpcService grpc;
  const _ReconnectingOverlay({required this.grpc});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: Colors.black.withValues(alpha: 0.35),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 24)],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(
              width: 36, height: 36,
              child: CircularProgressIndicator(strokeWidth: 3, color: AppTheme.brand),
            ),
            const SizedBox(height: 16),
            Text('正在重连', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: cs.onSurface)),
            const SizedBox(height: 4),
            Text('${grpc.host}:${grpc.port}',
                style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.45),
                    fontFeatures: const [FontFeature.tabularFigures()])),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: grpc.disconnect,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.red.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.red.withValues(alpha: 0.2)),
                ),
                child: Text('取消', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.red)),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════
// Keyboard Shortcut Help Overlay (F12 to toggle)
// ══════════════════════════════════════════════════════
class _ShortcutHelpOverlay extends StatelessWidget {
  final VoidCallback onClose;
  const _ShortcutHelpOverlay({required this.onClose});

  static const _groups = [
    (
      title: '行走控制',
      items: [
        ('W / S', '前进 / 后退'),
        ('A / D', '左移 / 右移'),
        ('Q / E', '左转 / 右转'),
        ('空格', '站立'),
        ('Z', '坐下'),
      ]
    ),
    (
      title: '速度切换',
      items: [
        ('F3', '慢速 (×0.3)'),
        ('F4', '标准速度 (×0.55)'),
        ('F5', '快速 (×1.0)'),
      ]
    ),
    (
      title: '系统控制',
      items: [
        ('F1', '使能电机'),
        ('F2', '禁用电机'),
        ('F11', '全屏 / 退出全屏'),
        ('F12', '显示 / 隐藏此帮助'),
        ('Ctrl+K', '命令面板'),
        ('ESC', '关闭帮助/面板'),
      ]
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onClose,
      child: Container(
        color: Colors.black.withValues(alpha: 0.55),
        child: Center(
          child: GestureDetector(
            onTap: () {}, // prevent backdrop dismiss on card tap
            child: Container(
              width: 560,
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 40)],
              ),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Header
                Row(children: [
                  Icon(Icons.keyboard_rounded, size: 20, color: AppTheme.brand),
                  const SizedBox(width: 10),
                  Text('键盘快捷键', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: cs.onSurface)),
                  const Spacer(),
                  GestureDetector(
                    onTap: onClose,
                    child: Icon(Icons.close_rounded, size: 20, color: cs.onSurface.withValues(alpha: 0.4)),
                  ),
                ]),
                const SizedBox(height: 20),
                // Shortcut groups
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  ..._groups.map((g) => Expanded(child: Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: AppTheme.brand.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                        child: Text(g.title, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppTheme.brand, letterSpacing: 0.5)),
                      ),
                      const SizedBox(height: 10),
                      ...g.items.map((item) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: cs.onSurface.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(color: cs.outline.withValues(alpha: 0.4)),
                            ),
                            child: Text(item.$1, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, fontFamily: 'monospace', color: cs.onSurface)),
                          ),
                          const SizedBox(width: 10),
                          Expanded(child: Text(item.$2, style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.6)))),
                        ]),
                      )),
                    ]),
                  ))),
                ]),
                const SizedBox(height: 8),
                Divider(color: cs.outline.withValues(alpha: 0.3)),
                const SizedBox(height: 8),
                Text('按 ESC 或点击背景关闭', style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.3))),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════
// Command Palette (Ctrl+K)
// ══════════════════════════════════════════════════
class _CommandPalette extends StatefulWidget {
  final GrpcService grpc;
  final VoidCallback onClose;
  final ValueChanged<int> onNavigate;
  const _CommandPalette({required this.grpc, required this.onClose, required this.onNavigate});

  @override
  State<_CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<_CommandPalette> {
  final _controller = TextEditingController();
  int _selectedIdx = 0;
  String _query = '';

  // All searchable items: (label, subtitle, icon, action)
  late final List<_CmdItem> _all;

  @override
  void initState() {
    super.initState();
    _all = [
      _CmdItem('仪表盘', '控制与连接', Icons.space_dashboard_rounded, () => widget.onNavigate(0)),
      _CmdItem('实时监控', '关节数据与日志', Icons.monitor_heart_rounded, () => widget.onNavigate(1)),
      _CmdItem('遥控操作', '虚拟摇杆控制', Icons.gamepad_rounded, () => widget.onNavigate(2)),
      _CmdItem('参数配置', '增益与模型', Icons.tune_rounded, () => widget.onNavigate(3)),
      _CmdItem('协议日志', 'gRPC 消息记录', Icons.terminal_rounded, () => widget.onNavigate(4)),
      _CmdItem('姿态 IMU', '陀螺仪与姿态', Icons.explore_rounded, () => widget.onNavigate(5)),
      _CmdItem('运行记录', '历次会话历史', Icons.history_rounded, () => widget.onNavigate(6)),
      _CmdItem('智脑', '推理策略管理', Icons.psychology_rounded, () => widget.onNavigate(7)),
      _CmdItem('站立', '执行站立动作', Icons.arrow_upward_rounded, () { if (widget.grpc.connected) widget.grpc.standUp(); widget.onClose(); }),
      _CmdItem('坐下', '执行坐下动作', Icons.arrow_downward_rounded, () { if (widget.grpc.connected) widget.grpc.sitDown(); widget.onClose(); }),
      _CmdItem('使能电机', '发送 Enable 命令', Icons.power_rounded, () { if (widget.grpc.connected) widget.grpc.enable(); widget.onClose(); }),
      _CmdItem('禁用电机', '发送 Disable 命令', Icons.power_off_rounded, () { if (widget.grpc.connected) widget.grpc.disable(); widget.onClose(); }),
    ];
  }

  @override
  void dispose() { _controller.dispose(); super.dispose(); }

  List<_CmdItem> get _filtered {
    if (_query.isEmpty) return _all;
    final q = _query.toLowerCase();
    return _all.where((e) => e.label.toLowerCase().contains(q) || e.subtitle.toLowerCase().contains(q)).toList();
  }

  void _execute() {
    final items = _filtered;
    if (items.isNotEmpty && _selectedIdx < items.length) items[_selectedIdx].action();
    widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final items = _filtered;
    // Clamp selected index
    final sel = _selectedIdx.clamp(0, items.isEmpty ? 0 : items.length - 1);

    return GestureDetector(
      onTap: widget.onClose,
      child: Container(
        color: Colors.black.withValues(alpha: 0.5),
        child: Center(
          child: GestureDetector(
            onTap: () {},
            child: Container(
              width: 520,
              constraints: const BoxConstraints(maxHeight: 420),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 48, spreadRadius: -8)],
                border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                // Search field
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(children: [
                    Icon(Icons.search_rounded, size: 18, color: cs.onSurface.withValues(alpha: 0.4)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: KeyboardListener(
                        focusNode: FocusNode(),
                        onKeyEvent: (e) {
                          if (e is KeyDownEvent) {
                            if (e.logicalKey == LogicalKeyboardKey.arrowDown) {
                              setState(() => _selectedIdx = (sel + 1).clamp(0, items.length - 1));
                            } else if (e.logicalKey == LogicalKeyboardKey.arrowUp) {
                              setState(() => _selectedIdx = (sel - 1).clamp(0, items.length - 1));
                            } else if (e.logicalKey == LogicalKeyboardKey.enter) {
                              _execute();
                            }
                          }
                        },
                        child: TextField(
                          controller: _controller,
                          autofocus: true,
                          decoration: const InputDecoration(hintText: '搜索页面或操作...', border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.zero),
                          style: TextStyle(fontSize: 14, color: cs.onSurface),
                          onChanged: (v) => setState(() { _query = v; _selectedIdx = 0; }),
                          onSubmitted: (_) => _execute(),
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: cs.onSurface.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(4), border: Border.all(color: cs.outline.withValues(alpha: 0.3))),
                      child: Text('ESC', style: TextStyle(fontSize: 9, color: cs.onSurface.withValues(alpha: 0.35), fontFamily: 'monospace')),
                    ),
                  ]),
                ),
                Divider(height: 1, color: cs.outline.withValues(alpha: 0.15)),
                // Results
                Flexible(
                  child: items.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text('无匹配项', style: TextStyle(fontSize: 13, color: cs.onSurface.withValues(alpha: 0.3))),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          itemCount: items.length,
                          itemBuilder: (_, i) {
                            final item = items[i];
                            final isSelected = i == sel;
                            return GestureDetector(
                              onTap: () { item.action(); widget.onClose(); },
                              child: Container(
                                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                                decoration: BoxDecoration(
                                  color: isSelected ? AppTheme.brand.withValues(alpha: 0.1) : Colors.transparent,
                                  borderRadius: BorderRadius.circular(8),
                                  border: isSelected ? Border.all(color: AppTheme.brand.withValues(alpha: 0.2)) : null,
                                ),
                                child: Row(children: [
                                  Icon(item.icon, size: 16, color: isSelected ? AppTheme.brand : cs.onSurface.withValues(alpha: 0.4)),
                                  const SizedBox(width: 12),
                                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(item.label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: isSelected ? AppTheme.brand : cs.onSurface)),
                                    Text(item.subtitle, style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.4))),
                                  ])),
                                  if (isSelected)
                                    Icon(Icons.keyboard_return_rounded, size: 13, color: AppTheme.brand.withValues(alpha: 0.5)),
                                ]),
                              ),
                            );
                          },
                        ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _CmdItem {
  final String label;
  final String subtitle;
  final IconData icon;
  final VoidCallback action;
  const _CmdItem(this.label, this.subtitle, this.icon, this.action);
}

/// Custom title bar with drag-to-move and window control buttons.
class _CustomTitleBar extends StatefulWidget {
  final GrpcService grpc;
  const _CustomTitleBar({required this.grpc});

  @override
  State<_CustomTitleBar> createState() => _CustomTitleBarState();
}

class _CustomTitleBarState extends State<_CustomTitleBar> with WindowListener {
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    widget.grpc.addListener(_onGrpc);
    _checkMaximized();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    widget.grpc.removeListener(_onGrpc);
    super.dispose();
  }

  void _onGrpc() { if (mounted) setState(() {}); }

  Future<void> _checkMaximized() async {
    final maximized = await windowManager.isMaximized();
    if (mounted) setState(() => _isMaximized = maximized);
  }

  @override
  void onWindowMaximize() {
    setState(() => _isMaximized = true);
  }

  @override
  void onWindowUnmaximize() {
    setState(() => _isMaximized = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onDoubleTap: () async {
        if (_isMaximized) {
          await windowManager.unmaximize();
        } else {
          await windowManager.maximize();
        }
      },
      child: Container(
        height: 36,
        color: cs.surface,
        child: Row(
          children: [
            const SizedBox(width: 16),
            // App icon + title
            Icon(Icons.smart_toy_rounded, size: 16, color: AppTheme.brand),
            const SizedBox(width: 8),
            Text(
              '穹佩控制面板',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: cs.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(width: 12),
            // CMS state chip
            if (widget.grpc.connected) ...[
              _CmsStateChip(state: widget.grpc.cmsState),
              const SizedBox(width: 8),
            ],
            // Drag area fills remaining space
            Expanded(
              child: DragToMoveArea(child: Container(height: 36)),
            ),
            // Window control buttons
            _WindowButton(
              icon: Icons.remove_rounded,
              onTap: () => windowManager.minimize(),
              hoverColor: cs.onSurface.withValues(alpha: 0.08),
            ),
            _WindowButton(
              icon: _isMaximized ? Icons.filter_none_rounded : Icons.crop_square_rounded,
              iconSize: _isMaximized ? 13 : 15,
              onTap: () async {
                if (_isMaximized) {
                  await windowManager.unmaximize();
                } else {
                  await windowManager.maximize();
                }
              },
              hoverColor: cs.onSurface.withValues(alpha: 0.08),
            ),
            _WindowButton(
              icon: Icons.close_rounded,
              onTap: () => windowManager.close(),
              hoverColor: const Color(0xFFE81123),
              hoverIconColor: Colors.white,
            ),
          ],
        ),
      ),
    );
  }
}

/// A single window control button (minimize / maximize / close).
class _WindowButton extends StatefulWidget {
  final IconData icon;
  final double iconSize;
  final VoidCallback onTap;
  final Color hoverColor;
  final Color? hoverIconColor;

  const _WindowButton({
    required this.icon,
    this.iconSize = 15,
    required this.onTap,
    required this.hoverColor,
    this.hoverIconColor,
  });

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
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
          width: 46,
          height: 36,
          color: _hovered ? widget.hoverColor : Colors.transparent,
          child: Center(
            child: Icon(
              widget.icon,
              size: widget.iconSize,
              color: _hovered && widget.hoverIconColor != null
                  ? widget.hoverIconColor
                  : cs.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ),
      ),
    );
  }
}

// ── CMS State chip shown in the title bar ─────────────────────────────────────
class _CmsStateChip extends StatelessWidget {
  final String state;
  const _CmsStateChip({required this.state});

  static Color _stateColor(String s) {
    switch (s) {
      case 'Walking': return AppTheme.green;
      case 'Standing': case 'StandUp': return AppTheme.teal;
      case 'SitDown': case 'Grounded': return AppTheme.orange;
      case 'Transitioning': return AppTheme.yellow;
      default: return AppTheme.red;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _stateColor(state);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 5, height: 5, decoration: BoxDecoration(shape: BoxShape.circle, color: color,
            boxShadow: [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 3)])),
        const SizedBox(width: 5),
        Text(state.isEmpty ? '--' : state,
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color)),
      ]),
    );
  }
}
