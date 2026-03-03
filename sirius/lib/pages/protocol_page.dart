import 'dart:io';
import 'dart:math' as math;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../services/grpc_service.dart';
import '../theme/app_theme.dart';
import '../utils/app_toast.dart';
import '../widgets/status_card.dart';

/// 将 DateTime 格式化为 HH:mm:ss.mmm（供日志列表和导出共用）
String _fmtTime(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:'
    '${t.minute.toString().padLeft(2, '0')}:'
    '${t.second.toString().padLeft(2, '0')}.'
    '${t.millisecond.toString().padLeft(3, '0')}';

class ProtocolPage extends StatefulWidget {
  final GrpcService grpc;
  const ProtocolPage({super.key, required this.grpc});

  @override
  State<ProtocolPage> createState() => _ProtocolPageState();
}

class _ProtocolPageState extends State<ProtocolPage> {
  final _scrollController = ScrollController();
  String _filter = '';

  // 状态机节点顺序（每次 build 无需重建）
  static const _cmsStates = ['Idle', 'StandUp', 'SitDown', 'Walking'];

  /// 过滤后日志缓存，仅在 filter 或日志长度变化时重算
  List<ProtocolLogEntry>? _cachedLog;
  String _lastFilter = '';
  int _lastLogLen = -1;

  @override
  void initState() {
    super.initState();
    widget.grpc.addListener(_onUpdate);
  }

  @override
  void dispose() {
    widget.grpc.removeListener(_onUpdate);
    _scrollController.dispose();
    super.dispose();
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  Future<void> _exportLog() async {
    final log = widget.grpc.protocolLog;
    if (log.isEmpty) {
      if (mounted) AppToast.showError(context, '日志为空，无法导出');
      return;
    }
    final ts = DateTime.now();
    final stamp = '${ts.year}${ts.month.toString().padLeft(2,'0')}${ts.day.toString().padLeft(2,'0')}_'
        '${ts.hour.toString().padLeft(2,'0')}${ts.minute.toString().padLeft(2,'0')}';
    final path = await FilePicker.platform.saveFile(
      dialogTitle: '导出协议日志',
      fileName: 'grpc_log_$stamp.txt',
      type: FileType.custom,
      allowedExtensions: ['txt'],
    );
    if (path == null || !mounted) return;
    final lines = log.reversed.map((e) {
      return '${_fmtTime(e.time)}  ${e.direction}  ${e.method.padRight(20)}  ${e.summary}';
    }).join('\n');
    await File(path).writeAsString('# Sirius gRPC 协议日志\n# 导出时间: ${DateTime.now()}\n\n$lines\n');
    if (mounted) AppToast.showSuccess(context, '日志已导出');
  }

  List<ProtocolLogEntry> get _filteredLog {
    final rawLog = widget.grpc.protocolLog;
    if (_filter == _lastFilter && rawLog.length == _lastLogLen && _cachedLog != null) {
      return _cachedLog!;
    }
    _lastFilter = _filter;
    _lastLogLen = rawLog.length;
    if (_filter.isEmpty) {
      _cachedLog = rawLog;
    } else {
      final lowerFilter = _filter.toLowerCase();
      _cachedLog = rawLog
          .where((e) =>
              e.method.toLowerCase().contains(lowerFilter) ||
              e.summary.toLowerCase().contains(lowerFilter))
          .toList();
    }
    return _cachedLog!;
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final grpc = widget.grpc;
    final log = _filteredLog;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('协议日志', style: tt.headlineLarge),
                const SizedBox(height: 4),
                Text('gRPC 通信记录与 CMS 状态机可视化', style: tt.bodySmall),
              ]),
              const Spacer(),
              _CallRateWidget(log: grpc.protocolLog),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // State machine visualization
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: _buildStateMachine(tt, cs, grpc),
        ),
        const SizedBox(height: 16),

        // Filter bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  style: tt.bodyMedium,
                  decoration: InputDecoration(
                    hintText: '筛选方法名或内容...',
                    hintStyle: tt.bodySmall,
                    prefixIcon: Icon(Icons.search_rounded, size: 18, color: cs.onSurface.withValues(alpha: 0.3)),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    filled: true,
                    fillColor: cs.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: cs.outline, width: 0.5),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: cs.outline, width: 0.5),
                    ),
                  ),
                  onChanged: (v) => setState(() => _filter = v),
                ),
              ),
              const SizedBox(width: 12),
              Text('${log.length} 条', style: tt.bodySmall),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: _exportLog,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: cs.outline, width: 0.5),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.download_rounded, size: 14, color: AppTheme.brand),
                    const SizedBox(width: 4),
                    Text('导出', style: tt.labelMedium?.copyWith(color: AppTheme.brand)),
                  ]),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () {
                  grpc.protocolLog.clear();
                  setState(() {});
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: cs.outline, width: 0.5),
                  ),
                  child: Text('清空', style: tt.labelMedium),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Log list
        Expanded(
          child: log.isEmpty
              ? Center(
                  child: Text('暂无日志', style: tt.bodySmall?.copyWith(color: cs.onSurface.withValues(alpha: 0.3))),
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  itemCount: log.length,
                  itemBuilder: (_, i) => _LogRow(entry: log[i]),
                ),
        ),
      ],
    );
  }

  // 状态颜色映射（每次 build 无需重建）
  static const _stateColors = {
    'Idle': AppTheme.yellow,
    'StandUp': AppTheme.teal,
    'SitDown': AppTheme.orange,
    'Walking': AppTheme.green,
    'Unknown': AppTheme.red,
  };

  Widget _buildStateMachine(TextTheme tt, ColorScheme cs, GrpcService grpc) {
    const states = _cmsStates;
    const colors = _stateColors;

    return StatusCard(
      title: 'CMS 状态机',
      trailing: Text(
        '当前: ${grpc.cmsState}',
        style: tt.labelMedium?.copyWith(
          color: colors[grpc.cmsState] ?? AppTheme.red,
          fontWeight: FontWeight.w600,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: states.map((state) {
          final isActive = grpc.cmsState == state;
          final color = colors[state] ?? cs.outline;
          return Column(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isActive ? color.withValues(alpha: 0.15) : Colors.transparent,
                  border: Border.all(
                    color: isActive ? color : cs.outline.withValues(alpha: 0.3),
                    width: isActive ? 2.5 : 1,
                  ),
                  boxShadow: isActive
                      ? [BoxShadow(color: color.withValues(alpha: 0.2), blurRadius: 12)]
                      : [],
                ),
                child: Center(
                  child: Icon(
                    _stateIcon(state),
                    size: 24,
                    color: isActive ? color : cs.onSurface.withValues(alpha: 0.3),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                state,
                style: tt.labelSmall?.copyWith(
                  color: isActive ? color : cs.onSurface.withValues(alpha: 0.4),
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  IconData _stateIcon(String state) {
    switch (state) {
      case 'Idle':
        return Icons.pause_circle_outline_rounded;
      case 'StandUp':
        return Icons.arrow_upward_rounded;
      case 'SitDown':
        return Icons.arrow_downward_rounded;
      case 'Walking':
        return Icons.directions_walk_rounded;
      default:
        return Icons.help_outline_rounded;
    }
  }
}

class _LogRow extends StatefulWidget {
  final ProtocolLogEntry entry;
  const _LogRow({required this.entry});
  @override State<_LogRow> createState() => _LogRowState();
}

class _LogRowState extends State<_LogRow> {
  bool _hov = false;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final entry = widget.entry;

    Color dirColor;
    switch (entry.direction) {
      case '→': dirColor = AppTheme.teal; break;
      case '←': dirColor = AppTheme.green; break;
      default:  dirColor = AppTheme.red;
    }

    final timeStr = _fmtTime(entry.time);

    return MouseRegion(
      onEnter: (_) => setState(() => _hov = true),
      onExit: (_) => setState(() { _hov = false; _expanded = false; }),
      child: GestureDetector(
        onTap: () => setState(() => _expanded = !_expanded),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: _hov ? cs.onSurface.withValues(alpha: 0.04) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                SizedBox(
                  width: 85,
                  child: Text(timeStr,
                    style: tt.bodySmall?.copyWith(fontFeatures: [const FontFeature.tabularFigures()],
                        color: cs.onSurface.withValues(alpha: 0.4), fontSize: 11)),
                ),
                SizedBox(width: 20,
                  child: Text(entry.direction, style: TextStyle(color: dirColor, fontSize: 12, fontWeight: FontWeight.w600))),
                SizedBox(width: 120,
                  child: Text(entry.method, style: tt.bodySmall?.copyWith(fontWeight: FontWeight.w600))),
                Expanded(
                  child: Text(entry.summary,
                    style: tt.bodySmall?.copyWith(color: cs.onSurface.withValues(alpha: 0.5)),
                    overflow: _expanded ? null : TextOverflow.ellipsis),
                ),
                if (_hov)
                  Icon(_expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                    size: 14, color: cs.onSurface.withValues(alpha: 0.3)),
              ]),
              if (_expanded && entry.summary.isNotEmpty) ...[
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: cs.onSurface.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: SelectableText(
                    entry.summary,
                    style: tt.bodySmall?.copyWith(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.6),
                        fontFeatures: [const FontFeature.tabularFigures()]),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Call-rate mini bar chart ──────────────────────────────────────────────────
class _CallRateWidget extends StatelessWidget {
  final List<ProtocolLogEntry> log;
  const _CallRateWidget({required this.log});

  List<int> _buckets() {
    const buckets = 30;
    final counts = List<int>.filled(buckets, 0);
    final now = DateTime.now();
    for (final e in log) {
      final age = now.difference(e.time).inSeconds;
      if (age >= 0 && age < buckets) counts[buckets - 1 - age]++;
    }
    return counts;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final counts = _buckets();
    final peak = counts.reduce(math.max);
    final recentRate = counts.sublist(counts.length - 5).reduce((a, b) => a + b) / 5.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text('调用/秒', style: TextStyle(fontSize: 8, color: cs.onSurface.withValues(alpha: 0.35))),
            const SizedBox(width: 6),
            Text(recentRate.toStringAsFixed(1),
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                color: AppTheme.brand, fontFeatures: const [FontFeature.tabularFigures()])),
          ],
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: 120,
          height: 28,
          child: CustomPaint(
            painter: _RateBarPainter(counts: counts, peak: peak, color: AppTheme.brand.withValues(alpha: 0.6), cs: cs),
          ),
        ),
      ],
    );
  }
}

class _RateBarPainter extends CustomPainter {
  final List<int> counts;
  final int peak;
  final Color color;
  final ColorScheme cs;
  const _RateBarPainter({required this.counts, required this.peak, required this.color, required this.cs});

  @override
  void paint(Canvas canvas, Size size) {
    if (counts.isEmpty) return;
    final barW = size.width / counts.length;
    final maxH = size.height;
    final effectivePeak = peak < 1 ? 1 : peak;
    final paint = Paint()..color = color..style = PaintingStyle.fill;
    final fadePaint = Paint()..color = cs.onSurface.withValues(alpha: 0.06)..style = PaintingStyle.fill;
    for (int i = 0; i < counts.length; i++) {
      final x = i * barW + 1;
      final w = barW - 2;
      // Background bar
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, 0, w, maxH), const Radius.circular(1.5)), fadePaint);
      // Filled bar
      final h = (counts[i] / effectivePeak) * maxH;
      if (h > 0) {
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, maxH - h, w, h), const Radius.circular(1.5)), paint);
      }
    }
  }

  @override bool shouldRepaint(covariant _RateBarPainter old) => true;
}
