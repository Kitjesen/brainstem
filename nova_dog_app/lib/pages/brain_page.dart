import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../services/grpc_service.dart';
import '../theme/app_theme.dart';
import '../utils/app_toast.dart';
import '../widgets/status_card.dart';

class BrainPage extends StatefulWidget {
  final GrpcService grpc;
  const BrainPage({super.key, required this.grpc});

  @override
  State<BrainPage> createState() => _BrainPageState();
}

class _BrainPageState extends State<BrainPage> {
  String? _switchingTo;
  static const int _maxHzPts = 120;
  final List<double> _hzHistory = [];

  @override
  void initState() {
    super.initState();
    widget.grpc.addListener(_onData);
  }

  @override
  void dispose() {
    widget.grpc.removeListener(_onData);
    super.dispose();
  }

  void _onData() {
    if (!mounted) return;
    final hz = widget.grpc.historyHz;
    if (hz > 0) {
      _hzHistory.add(hz);
      if (_hzHistory.length > _maxHzPts) _hzHistory.removeAt(0);
    }
    setState(() {});
  }

  Future<void> _switchProfile(String name) async {
    if (_switchingTo != null) return;
    setState(() => _switchingTo = name);
    final ok = await widget.grpc.switchProfile(name);
    if (!mounted) return;
    setState(() => _switchingTo = null);
    if (!ok) {
      AppToast.showError(context, '切换策略失败（机器人需处于坐下状态）');
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.grpc;
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Header ──
        Row(children: [
          Text('智脑', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: cs.onSurface)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: (g.connected ? AppTheme.green : AppTheme.red).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: (g.connected ? AppTheme.green : AppTheme.red).withValues(alpha: 0.2)),
            ),
            child: Text(g.connected ? '在线' : '离线',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: g.connected ? AppTheme.green : AppTheme.red)),
          ),
          const SizedBox(width: 8),
          if (g.connected)
            Text('${g.historyHz.toStringAsFixed(0)} Hz',
                style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.4))),
          const Spacer(),
          if (g.connected && g.hasProfiles)
            Text('策略：${g.currentProfile}',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.brand)),
        ]),
        const SizedBox(height: 4),
        Text('策略管理与实时推理状态', style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.35))),
        const SizedBox(height: 16),

        Expanded(child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ── Left column ──
          Expanded(child: Column(children: [
            // FSM 节点图
            StatusCard(
              title: 'FSM 状态流',
              child: _FsmDiagram(cmsState: g.connected ? g.cmsState : ''),
            ),
            const SizedBox(height: 12),
            // 运行状态卡片
            StatusCard(
              title: '运行状态',
              child: _RunStatusContent(grpc: g, hzHistory: _hzHistory),
            ),
            const SizedBox(height: 12),
            // 状态输入卡片（实时观测向量）
            Expanded(
              child: StatusCard(
                title: '状态输入（实时观测）',
                child: _ObservationContent(grpc: g),
              ),
            ),
          ])),
          const SizedBox(width: 12),

          // ── Right column: 策略管理 ──
          SizedBox(
            width: 320,
            child: StatusCard(
              title: '策略管理',
              trailing: g.connected && !g.hasProfiles
                  ? Text('未配置', style: TextStyle(fontSize: 10, color: cs.onSurface.withValues(alpha: 0.4)))
                  : null,
              child: _ProfileListContent(
                grpc: g,
                switchingTo: _switchingTo,
                onSwitch: _switchProfile,
              ),
            ),
          ),
        ])),
      ]),
    );
  }
}

// ──────────────────────────────────────────────
// 运行状态内容
// ──────────────────────────────────────────────
class _RunStatusContent extends StatelessWidget {
  final GrpcService grpc;
  final List<double> hzHistory;
  const _RunStatusContent({required this.grpc, required this.hzHistory});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final g = grpc;

    final rows = [
      ('FSM 状态', g.connected ? g.cmsState : '--'),
      ('推理频率', g.connected ? '${g.historyHz.toStringAsFixed(1)} Hz' : '--'),
      ('IMU 频率', g.connected ? '${g.imuHz.toStringAsFixed(1)} Hz' : '--'),
      ('关节频率', g.connected ? '${g.jointHz.toStringAsFixed(1)} Hz' : '--'),
    ];

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(
        spacing: 16,
        runSpacing: 8,
        children: rows.map((r) => SizedBox(
          width: 140,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(r.$1, style: TextStyle(fontSize: 10, color: cs.onSurface.withValues(alpha: 0.45))),
            const SizedBox(height: 2),
            Text(r.$2, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: cs.onSurface,
                fontFeatures: const [FontFeature.tabularFigures()])),
          ]),
        )).toList(),
      ),
      if (hzHistory.length >= 2) ...[
        const SizedBox(height: 12),
        Row(children: [
          Icon(Icons.show_chart_rounded, size: 11, color: cs.onSurface.withValues(alpha: 0.3)),
          const SizedBox(width: 4),
          Text('推理频率趋势', style: TextStyle(fontSize: 10, color: cs.onSurface.withValues(alpha: 0.35))),
          const Spacer(),
          Text('${hzHistory.last.toStringAsFixed(1)} Hz', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppTheme.brand)),
        ]),
        const SizedBox(height: 6),
        SizedBox(
          height: 48,
          child: LineChart(
            LineChartData(
              minY: 0,
              maxY: (hzHistory.reduce((a, b) => a > b ? a : b) * 1.2).clamp(10.0, 80.0),
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              titlesData: const FlTitlesData(show: false),
              lineBarsData: [
                LineChartBarData(
                  spots: List.generate(hzHistory.length, (i) => FlSpot(i.toDouble(), hzHistory[i])),
                  isCurved: true,
                  color: AppTheme.brand,
                  barWidth: 1.5,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(
                    show: true,
                    color: AppTheme.brand.withValues(alpha: 0.08),
                  ),
                ),
              ],
              lineTouchData: const LineTouchData(enabled: false),
            ),
            duration: Duration.zero,
          ),
        ),
      ],
    ]);
  }
}

// ──────────────────────────────────────────────
// 实时观测向量内容
// ──────────────────────────────────────────────
class _ObservationContent extends StatelessWidget {
  final GrpcService grpc;
  const _ObservationContent({required this.grpc});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final g = grpc;
    final h = g.latestHistory;

    if (h == null || !g.connected) {
      return Center(
        child: Text('等待数据...', style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.3))),
      );
    }

    String cmdLabel = '--';
    if (h.hasCommand()) {
      final cmd = h.command;
      if (cmd.hasWalk()) {
        cmdLabel = '行走  前进 ${cmd.walk.x.toStringAsFixed(2)} · 侧移 ${cmd.walk.y.toStringAsFixed(2)} · 旋转 ${cmd.walk.z.toStringAsFixed(2)}';
      } else if (cmd.hasStandUp()) {
        cmdLabel = '站立';
      } else if (cmd.hasSitDown()) {
        cmdLabel = '坐下';
      } else {
        cmdLabel = '待机';
      }
    }

    final gyro = h.hasGyroscope() ? h.gyroscope : null;
    final grav = h.hasProjectedGravity() ? h.projectedGravity : null;

    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _ObsRow('指令', cmdLabel, cs),
        if (gyro != null)
          _ObsRow('陀螺仪', 'Gx ${gyro.x.toStringAsFixed(3)} · Gy ${gyro.y.toStringAsFixed(3)} · Gz ${gyro.z.toStringAsFixed(3)}', cs),
        if (grav != null)
          _ObsRow('投影重力', 'gx ${grav.x.toStringAsFixed(3)} · gy ${grav.y.toStringAsFixed(3)} · gz ${grav.z.toStringAsFixed(3)}', cs),
        if (h.hasJointPosition()) ...[
          const SizedBox(height: 8),
          Text('关节位置 (rad)', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: cs.onSurface.withValues(alpha: 0.4))),
          const SizedBox(height: 4),
          _MatrixGrid(values: h.jointPosition.values, cs: cs),
        ],
        if (h.hasAction()) ...[
          const SizedBox(height: 8),
          Text('上一步动作', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: cs.onSurface.withValues(alpha: 0.4))),
          const SizedBox(height: 4),
          _MatrixGrid(values: h.action.values, cs: cs),
        ],
      ]),
    );
  }
}

class _ObsRow extends StatelessWidget {
  final String label;
  final String value;
  final ColorScheme cs;
  const _ObsRow(this.label, this.value, this.cs);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 64, child: Text(label, style: TextStyle(fontSize: 10, color: cs.onSurface.withValues(alpha: 0.45)))),
        Expanded(child: Text(value, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: cs.onSurface,
            fontFeatures: const [FontFeature.tabularFigures()]))),
      ]),
    );
  }
}

class _MatrixGrid extends StatelessWidget {
  final List<double> values;
  final ColorScheme cs;
  const _MatrixGrid({required this.values, required this.cs});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: List.generate(values.length, (i) => SizedBox(
        width: 52,
        child: Text(
          values[i].toStringAsFixed(2),
          style: TextStyle(fontSize: 10, color: cs.onSurface.withValues(alpha: 0.6),
              fontFeatures: const [FontFeature.tabularFigures()]),
          textAlign: TextAlign.right,
        ),
      )),
    );
  }
}

// ──────────────────────────────────────────────
// 策略列表内容
// ──────────────────────────────────────────────
class _ProfileListContent extends StatelessWidget {
  final GrpcService grpc;
  final String? switchingTo;
  final void Function(String) onSwitch;
  const _ProfileListContent({required this.grpc, required this.switchingTo, required this.onSwitch});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final g = grpc;

    if (!g.connected) {
      return Center(
        child: Text('未连接', style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.3))),
      );
    }

    if (!g.hasProfiles) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.folder_off_outlined, size: 32, color: cs.onSurface.withValues(alpha: 0.2)),
          const SizedBox(height: 8),
          Text('机器人未配置策略', style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.35))),
          const SizedBox(height: 4),
          Text('请在 han_dog 的 profiles/ 目录中\n添加 JSON 策略文件', textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10, color: cs.onSurface.withValues(alpha: 0.25))),
        ]),
      );
    }

    final profiles = g.availableProfiles;
    final descriptions = g.profileDescriptions;
    final current = g.currentProfile;
    final currentDesc = g.currentProfileDescription;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // 当前策略说明
      if (currentDesc.isNotEmpty) ...[
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppTheme.brand.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.brand.withValues(alpha: 0.15)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('当前策略说明', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700,
                color: AppTheme.brand.withValues(alpha: 0.7), letterSpacing: 0.5)),
            const SizedBox(height: 4),
            Text(currentDesc, style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.7))),
          ]),
        ),
        const SizedBox(height: 12),
      ],

      // 策略列表
      Expanded(
        child: ListView.separated(
          itemCount: profiles.length,
          separatorBuilder: (_, index) => const SizedBox(height: 8),
          itemBuilder: (ctx, i) {
            final name = profiles[i];
            final desc = i < descriptions.length ? descriptions[i] : '';
            final isCurrent = name == current;
            final isLoading = switchingTo == name;

            return _ProfileCard(
              name: name,
              description: desc,
              isCurrent: isCurrent,
              isLoading: isLoading,
              disabled: switchingTo != null,
              onSwitch: () => onSwitch(name),
            );
          },
        ),
      ),
    ]);
  }
}

class _ProfileCard extends StatelessWidget {
  final String name;
  final String description;
  final bool isCurrent;
  final bool isLoading;
  final bool disabled;
  final VoidCallback onSwitch;

  const _ProfileCard({
    required this.name,
    required this.description,
    required this.isCurrent,
    required this.isLoading,
    required this.disabled,
    required this.onSwitch,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isCurrent ? AppTheme.brand.withValues(alpha: 0.06) : cs.onSurface.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isCurrent ? AppTheme.brand.withValues(alpha: 0.25) : cs.outline.withValues(alpha: 0.3),
          width: isCurrent ? 1.5 : 1,
        ),
      ),
      child: Row(children: [
        // 状态圆点
        Container(
          width: 8, height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isCurrent ? AppTheme.brand : cs.onSurface.withValues(alpha: 0.2),
          ),
        ),
        const SizedBox(width: 10),

        // 名称 + 说明
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurface)),
          if (description.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(description, style: TextStyle(fontSize: 10, color: cs.onSurface.withValues(alpha: 0.45))),
          ],
        ])),

        const SizedBox(width: 8),

        // 按钮
        if (isCurrent)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.brand.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text('当前', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppTheme.brand)),
          )
        else if (isLoading)
          const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
        else
          TextButton(
            onPressed: disabled ? null : onSwitch,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('切换', style: TextStyle(fontSize: 10)),
          ),
      ]),
    );
  }
}

// ──────────────────────────────────────────────
// FSM 节点图
// ──────────────────────────────────────────────
class _FsmDiagram extends StatelessWidget {
  final String cmsState;
  const _FsmDiagram({required this.cmsState});

  // Map state names to display labels + colors
  static const _nodes = [
    ('Grounded', '接地'),
    ('Transitioning', '过渡'),
    ('Standing', '站立'),
    ('Walking', '行走'),
  ];
  static const _stateColors = {
    'Grounded': AppTheme.orange,
    'Transitioning': AppTheme.yellow,
    'Standing': AppTheme.teal,
    'Walking': AppTheme.green,
  };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Normalize: StandUp / SitDown → Transitioning
    String norm = cmsState;
    if (cmsState == 'StandUp' || cmsState == 'SitDown' || cmsState == 'Transitioning') {
      norm = 'Transitioning';
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (int i = 0; i < _nodes.length; i++) ...[
          _FsmNode(
            key: ValueKey(_nodes[i].$1),
            id: _nodes[i].$1,
            label: _nodes[i].$2,
            isActive: norm == _nodes[i].$1,
            color: _stateColors[_nodes[i].$1] ?? AppTheme.brand,
            cs: cs,
          ),
          if (i < _nodes.length - 1)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Icon(
                // Standing ⟺ Walking uses bidirectional arrow
                (i == 2) ? Icons.swap_horiz_rounded : Icons.arrow_forward_rounded,
                size: 14,
                color: cs.onSurface.withValues(alpha: 0.2),
              ),
            ),
        ],
      ],
    );
  }
}

class _FsmNode extends StatelessWidget {
  final String id;
  final String label;
  final bool isActive;
  final Color color;
  final ColorScheme cs;
  const _FsmNode({super.key, required this.id, required this.label, required this.isActive, required this.color, required this.cs});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isActive ? color.withValues(alpha: 0.12) : cs.onSurface.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isActive ? color.withValues(alpha: 0.5) : cs.onSurface.withValues(alpha: 0.1),
          width: isActive ? 1.5 : 1,
        ),
        boxShadow: isActive ? [BoxShadow(color: color.withValues(alpha: 0.2), blurRadius: 8)] : [],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(id, style: TextStyle(fontSize: 8, color: isActive ? color.withValues(alpha: 0.7) : cs.onSurface.withValues(alpha: 0.25), letterSpacing: 0.3)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 11, fontWeight: isActive ? FontWeight.w700 : FontWeight.w500, color: isActive ? color : cs.onSurface.withValues(alpha: 0.4))),
      ]),
    );
  }
}
