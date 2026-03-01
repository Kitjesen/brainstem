import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:file_picker/file_picker.dart';
import '../services/run_history_service.dart';
import '../theme/app_theme.dart';
import '../utils/app_toast.dart';
import '../widgets/status_card.dart';

class HistoryPage extends StatefulWidget {
  final RunHistoryService runHistory;
  const HistoryPage({super.key, required this.runHistory});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Refresh every second to update duration of the current (live) session
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _clearHistory() async {
    await widget.runHistory.clear();
    if (mounted) setState(() {});
  }

  Future<void> _exportCsv() async {
    final entries = widget.runHistory.entries;
    if (entries.isEmpty) return;
    final now = DateTime.now();
    final stamp = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
    final path = await FilePicker.platform.saveFile(
      dialogTitle: '导出运行记录',
      fileName: 'run_history_$stamp.csv',
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );
    if (path == null) return;
    final buf = StringBuffer();
    buf.writeln('host,port,connected_at,disconnected_at,duration_s');
    for (final e in entries) {
      final disc = e.disconnectedAt?.toIso8601String() ?? '';
      buf.writeln('${e.host},${e.port},${e.connectedAt.toIso8601String()},$disc,${e.duration.inSeconds}');
    }
    await File(path).writeAsString(buf.toString());
    if (mounted) AppToast.showSuccess(context, '已导出 ${entries.length} 条记录');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final entries = widget.runHistory.entries;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──
          Row(children: [
            Text('运行记录', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: cs.onSurface)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: cs.onSurface.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text('共 ${entries.length} 条',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: cs.onSurface.withValues(alpha: 0.5))),
            ),
            const Spacer(),
            // Export CSV button
            GestureDetector(
              onTap: entries.isEmpty ? null : _exportCsv,
              child: AnimatedOpacity(
                opacity: entries.isEmpty ? 0.3 : 1.0,
                duration: const Duration(milliseconds: 150),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.brand.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.brand.withValues(alpha: 0.2)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.download_rounded, size: 14, color: AppTheme.brand),
                    const SizedBox(width: 4),
                    Text('CSV', style: TextStyle(fontSize: 11, color: AppTheme.brand, fontWeight: FontWeight.w600)),
                  ]),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Clear button
            GestureDetector(
              onTap: entries.isEmpty ? null : _clearHistory,
              child: AnimatedOpacity(
                opacity: entries.isEmpty ? 0.3 : 1.0,
                duration: const Duration(milliseconds: 150),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.red.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.red.withValues(alpha: 0.2)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.delete_outline_rounded, size: 14, color: AppTheme.red),
                    const SizedBox(width: 4),
                    Text('清空', style: TextStyle(fontSize: 11, color: AppTheme.red, fontWeight: FontWeight.w600)),
                  ]),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 4),
          Text('历次 gRPC 连接会话记录', style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.35))),
          const SizedBox(height: 16),

          // ── Statistics summary ──
          if (entries.isNotEmpty) ...[
            _StatsSummaryCard(entries: entries),
            const SizedBox(height: 12),
          ],

          if (entries.isEmpty)
            Expanded(
              child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.history_rounded, size: 48, color: cs.onSurface.withValues(alpha: 0.1)),
                  const SizedBox(height: 12),
                  Text('暂无记录', style: TextStyle(fontSize: 14, color: cs.onSurface.withValues(alpha: 0.3))),
                  const SizedBox(height: 4),
                  Text('连接机器人后将自动记录每次会话', style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.2))),
                ]),
              ),
            )
          else ...[
            // ── Bar chart for recent 10 sessions ──
            if (entries.length >= 2)
              SizedBox(
                height: 140,
                child: StatusCard(
                  title: '最近 ${entries.take(10).length} 次会话时长',
                  fillChildHeight: true,
                  child: _DurationBarChart(entries: entries.take(10).toList()),
                ),
              ),
            if (entries.length >= 2) const SizedBox(height: 12),

            // ── Session list ──
            Expanded(
              child: ListView.separated(
                itemCount: entries.length,
                separatorBuilder: (_, i) => Divider(
                  height: 1,
                  color: cs.onSurface.withValues(alpha: 0.06),
                  indent: 20,
                  endIndent: 20,
                ),
                itemBuilder: (_, i) => _SessionTile(entry: entries[i]),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// Statistics summary card
// ══════════════════════════════════════════════════════════════
class _StatsSummaryCard extends StatelessWidget {
  final List<RunEntry> entries;
  const _StatsSummaryCard({required this.entries});

  String _fmtDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final completed = entries.where((e) => e.disconnectedAt != null).toList();
    final totalDuration = entries.fold<Duration>(Duration.zero, (s, e) => s + e.duration);
    final longest = entries.isEmpty ? Duration.zero : entries.map((e) => e.duration).reduce((a, b) => a > b ? a : b);
    final avgDuration = completed.isEmpty ? Duration.zero
        : Duration(seconds: (completed.fold<int>(0, (s, e) => s + e.duration.inSeconds) / completed.length).round());

    final stats = [
      (Icons.history_rounded, '会话次数', '${entries.length} 次', AppTheme.brand),
      (Icons.timer_outlined, '总运行时长', _fmtDuration(totalDuration), AppTheme.teal),
      (Icons.emoji_events_outlined, '最长会话', _fmtDuration(longest), AppTheme.yellow),
      (Icons.bar_chart_rounded, '平均时长', completed.isEmpty ? '--' : _fmtDuration(avgDuration), AppTheme.green),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outline.withValues(alpha: 0.5)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8)],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: stats.map((s) => Expanded(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(s.$1, size: 16, color: s.$4.withValues(alpha: 0.7)),
            const SizedBox(height: 4),
            Text(s.$3, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: s.$4,
                fontFeatures: const [FontFeature.tabularFigures()])),
            const SizedBox(height: 2),
            Text(s.$2, style: TextStyle(fontSize: 9, color: cs.onSurface.withValues(alpha: 0.4))),
          ]),
        )).toList(),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// Duration bar chart (last 10 sessions)
// ══════════════════════════════════════════════════════════════

class _DurationBarChart extends StatelessWidget {
  final List<RunEntry> entries; // most-recent first

  const _DurationBarChart({required this.entries});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Reverse so oldest is left
    final reversed = entries.reversed.toList();
    final maxSecs = reversed.fold<double>(1.0, (m, e) => math.max(m, e.duration.inSeconds.toDouble()));

    return BarChart(
      BarChartData(
        maxY: maxSecs * 1.2,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: cs.onSurface.withValues(alpha: 0.05), strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 20,
              getTitlesWidget: (v, _) {
                final idx = v.toInt();
                if (idx < 0 || idx >= reversed.length) return const SizedBox();
                final e = reversed[idx];
                final d = e.connectedAt;
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '${d.month}/${d.day}',
                    style: TextStyle(fontSize: 8, color: cs.onSurface.withValues(alpha: 0.3)),
                  ),
                );
              },
            ),
          ),
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        barGroups: List.generate(reversed.length, (i) {
          final isLive = reversed[i].disconnectedAt == null;
          return BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: reversed[i].duration.inSeconds.toDouble().clamp(0.5, double.infinity),
                color: isLive ? AppTheme.green : AppTheme.teal.withValues(alpha: 0.6),
                width: 14,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
              ),
            ],
          );
        }),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => cs.surface,
            getTooltipItem: (group, _, rod, r) {
              final e = reversed[group.x];
              return BarTooltipItem(
                e.durationLabel,
                TextStyle(fontSize: 10, color: cs.onSurface, fontWeight: FontWeight.w600),
              );
            },
          ),
        ),
      ),
      duration: Duration.zero,
    );
  }
}

// ══════════════════════════════════════════════════════════════
// Session list tile
// ══════════════════════════════════════════════════════════════

class _SessionTile extends StatelessWidget {
  final RunEntry entry;
  const _SessionTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isLive = entry.disconnectedAt == null;
    final connTime = entry.connectedAt;
    final dateStr =
        '${connTime.year}-${connTime.month.toString().padLeft(2, '0')}-${connTime.day.toString().padLeft(2, '0')} '
        '${connTime.hour.toString().padLeft(2, '0')}:${connTime.minute.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Icon(
          isLive ? Icons.circle : Icons.circle_outlined,
          size: 10,
          color: isLive ? AppTheme.green : cs.onSurface.withValues(alpha: 0.25),
        ),
        title: Row(children: [
          Text(
            '${entry.host}:${entry.port}',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurface),
          ),
          if (isLive) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text('当前会话', style: TextStyle(fontSize: 9, color: AppTheme.green, fontWeight: FontWeight.w600)),
            ),
          ],
        ]),
        subtitle: Text(dateStr, style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.4))),
        trailing: Text(
          entry.durationLabel,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
            color: isLive ? AppTheme.green : cs.onSurface.withValues(alpha: 0.5),
          ),
        ),
      ),
    );
  }
}

