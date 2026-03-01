import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../services/grpc_service.dart';
import '../theme/app_theme.dart';
import '../utils/motor_status.dart';

class MonitorPage extends StatefulWidget {
  final GrpcService grpc;
  const MonitorPage({super.key, required this.grpc});
  @override State<MonitorPage> createState() => _MonitorPageState();
}

class _MonitorPageState extends State<MonitorPage> {
  static const int _maxPts = 200;
  final List<List<double>> _jHist = List.generate(16, (_) => []);
  int _selLeg = 0; // 0=FR, 1=FL, 2=RR, 3=RL
  String _logFilter = 'all'; // 'all' | 'error' | 'warn'
  DateTime? _lastUiUpdate;

  @override
  void initState() { super.initState(); widget.grpc.addListener(_onData); }
  @override
  void dispose() { widget.grpc.removeListener(_onData); super.dispose(); }

  void _onData() {
    final h = widget.grpc.latestHistory;
    if (h != null && h.hasJointPosition()) {
      for (int i = 0; i < 16 && i < h.jointPosition.values.length; i++) {
        _jHist[i].add(h.jointPosition.values[i]);
        if (_jHist[i].length > _maxPts) _jHist[i].removeAt(0);
      }
    }
    final now = DateTime.now();
    if (_lastUiUpdate == null ||
        now.difference(_lastUiUpdate!).inMilliseconds >= 50) {
      _lastUiUpdate = now;
      if (mounted) setState(() {});
    }
  }

  // Count joints whose absolute position exceeds the safe range (1.5 rad ≈ 86°)
  static const _posLimit = 1.5;
  int _overLimitCount(GrpcService g) {
    final pos = g.latestHistory?.jointPosition.values;
    if (pos == null) return 0;
    int count = 0;
    for (final v in pos) { if (v.abs() > _posLimit) count++; }
    return count;
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.grpc;
    final cs = Theme.of(context).colorScheme;
    final overLimit = _overLimitCount(g);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Header ──
        Row(children: [
          Text('实时监控', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: cs.onSurface)),
          const SizedBox(width: 8),
          Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: (g.connected ? AppTheme.green : AppTheme.red).withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12), border: Border.all(color: (g.connected ? AppTheme.green : AppTheme.red).withValues(alpha: 0.2), width: 1)), child: Text(g.connected ? '在线' : '离线', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: g.connected ? AppTheme.green : AppTheme.red))),
          if (overLimit > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: AppTheme.red.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.red.withValues(alpha: 0.3))),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.warning_amber_rounded, size: 11, color: AppTheme.red),
                const SizedBox(width: 3),
                Text('$overLimit 轴超限', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppTheme.red)),
              ]),
            ),
          ],
          const Spacer(),
          // Quality grade badge
          if (g.connected) ...[
            _QualityBadge(grade: g.qualityGrade, description: g.qualityDescription),
            const SizedBox(width: 10),
          ],
          // Power / current overview
          _powerBar(context, g),
        ]),
        const SizedBox(height: 4),
        Text('系统状态: ${g.connected ? "正常" : "--"} • 延迟: ${g.connected && g.lastRttMs > 0 ? "${g.lastRttMs.toStringAsFixed(0)} ms" : "--"}', style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.35))),
        const SizedBox(height: 16),

        // ── Main content: 8:4 ──
        Expanded(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // Left column (8/12)
          Expanded(flex: 2, child: Column(children: [
            // Joint angles chart
            Expanded(flex: 4, child: _chartCard(context, g)),
            const SizedBox(height: 12),
            // RTT latency chart
            _rttCard(context, g),
            const SizedBox(height: 12),
            // System logs
            Expanded(flex: 5, child: _logsCard(context, g)),
          ])),
          const SizedBox(width: 12),
          // Right column (4/12) - heatmap + 4 leg cards
          SizedBox(width: 320, child: SingleChildScrollView(child: Column(children: [
            _heatmapCard(context, g),
            const SizedBox(height: 10),
            _legCard(context, g, 'FR Leg', 0, const Color(0xFF3B82F6)),
            const SizedBox(height: 10),
            _legCard(context, g, 'FL Leg', 3, const Color(0xFF10B981)),
            const SizedBox(height: 10),
            _legCard(context, g, 'RR Leg', 6, const Color(0xFFF59E0B)),
            const SizedBox(height: 10),
            _legCard(context, g, 'RL Leg', 9, const Color(0xFF8B5CF6)),
          ]))),
        ])),
      ]),
    );
  }

  // ══════════════════════════════════════════════
  // Joint Torque Heatmap
  // ══════════════════════════════════════════════
  // Rows: FR/FL/RR/RL  Cols: 髋/大腿/小腿/足
  // Indices: FR[0,1,2,12] FL[3,4,5,13] RR[6,7,8,14] RL[9,10,11,15]
  static const _hmLeg = ['FR', 'FL', 'RR', 'RL'];
  static const _hmJoint = ['髋', '大腿', '小腿', '足'];
  static const _hmIdx = [
    [0, 1, 2, 12],
    [3, 4, 5, 13],
    [6, 7, 8, 14],
    [9, 10, 11, 15],
  ];

  Color _heatColor(double trqAbs) {
    // 0→green, 5→yellow, 10+→red
    if (trqAbs <= 0) return AppTheme.green.withValues(alpha: 0.15);
    final t = (trqAbs / 10.0).clamp(0.0, 1.0);
    if (t <= 0.5) {
      return Color.lerp(AppTheme.green, AppTheme.orange, t * 2)!.withValues(alpha: 0.25 + t * 0.5);
    } else {
      return Color.lerp(AppTheme.orange, AppTheme.red, (t - 0.5) * 2)!.withValues(alpha: 0.55 + t * 0.3);
    }
  }

  Widget _heatmapCard(BuildContext ctx, GrpcService g) {
    final cs = Theme.of(ctx).colorScheme;
    final j = g.latestJoints;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outline.withValues(alpha: 0.5)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.grid_view_rounded, size: 14, color: cs.onSurface.withValues(alpha: 0.35)),
          const SizedBox(width: 6),
          Text('关节热图', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.onSurface)),
          const Spacer(),
          // Gait phase lamps: 4 circles for FR/FL/RR/RL torque load
          _GaitLamps(joints: j),
          const SizedBox(width: 8),
          Text('力矩 Nm', style: TextStyle(fontSize: 9, color: cs.onSurface.withValues(alpha: 0.3))),
        ]),
        const SizedBox(height: 10),
        // Column headers
        Row(children: [
          const SizedBox(width: 28),
          ...List.generate(4, (c) => Expanded(child: Center(
            child: Text(_hmJoint[c], style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: cs.onSurface.withValues(alpha: 0.35))),
          ))),
        ]),
        const SizedBox(height: 6),
        // Rows
        ...List.generate(4, (r) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(children: [
            SizedBox(width: 28, child: Text(_hmLeg[r], style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: cs.onSurface.withValues(alpha: 0.4)))),
            ...List.generate(4, (c) {
              final idx = _hmIdx[r][c];
              final trq = (j != null && j.torque.values.length > idx)
                  ? j.torque.values[idx].abs()
                  : 0.0;
              final pos = g.latestHistory?.jointPosition.values;
              final posAbs = (pos != null && pos.length > idx) ? pos[idx].abs() : 0.0;
              final isOverLimit = posAbs > _posLimit;
              final cellColor = _heatColor(trq);
              return Expanded(child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: AspectRatio(
                  aspectRatio: 1.6,
                  child: Container(
                    decoration: BoxDecoration(
                      color: isOverLimit ? AppTheme.red.withValues(alpha: 0.18) : cellColor,
                      borderRadius: BorderRadius.circular(6),
                      border: isOverLimit ? Border.all(color: AppTheme.red.withValues(alpha: 0.6), width: 1.5) : null,
                    ),
                    child: Center(
                      child: Text(
                        trq < 0.1 ? '--' : trq.toStringAsFixed(1),
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: isOverLimit ? AppTheme.red : trq > 5 ? Colors.white : cs.onSurface.withValues(alpha: 0.6),
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                ),
              ));
            }),
          ]),
        )),
        // Legend
        Row(children: [
          const SizedBox(width: 28),
          _LegendBar(),
          const SizedBox(width: 8),
          Text('0', style: TextStyle(fontSize: 8, color: cs.onSurface.withValues(alpha: 0.3))),
          const Spacer(),
          Text('10+', style: TextStyle(fontSize: 8, color: cs.onSurface.withValues(alpha: 0.3))),
        ]),
      ]),
    );
  }

  // ══════════════════════════════════════════════
  // Power / Current bar
  // ══════════════════════════════════════════════
  Widget _powerBar(BuildContext ctx, GrpcService g) {
    final cs = Theme.of(ctx).colorScheme;
    const legs = ['FR', 'FL', 'RR', 'RL'];
    const colors = [Color(0xFF3B82F6), Color(0xFF10B981), Color(0xFFF59E0B), Color(0xFF8B5CF6)];
    final j = g.latestJoints;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: cs.outline.withValues(alpha: 0.5), width: 1), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8)]),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        // Power indicator
        Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: AppTheme.orange.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)), child: Icon(Icons.bolt_rounded, size: 18, color: AppTheme.orange)),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('总功率', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: cs.onSurface.withValues(alpha: 0.3), letterSpacing: 0.8)),
          Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
            Text('24.5', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: cs.onSurface, fontFeatures: const [FontFeature.tabularFigures()])),
            Text(' V', style: TextStyle(fontSize: 10, color: cs.onSurface.withValues(alpha: 0.3))),
          ]),
        ]),
        Container(width: 1, height: 30, margin: const EdgeInsets.symmetric(horizontal: 14), color: cs.onSurface.withValues(alpha: 0.06)),
        // Per-leg current
        ...List.generate(4, (i) {
          final torqueSum = j != null && j.torque.values.length > i * 3 + 2 ? (j.torque.values[i * 3].abs() + j.torque.values[i * 3 + 1].abs() + j.torque.values[i * 3 + 2].abs()) / 3 : 0.0;
          return Padding(padding: const EdgeInsets.only(left: 10), child: Column(children: [
            Text(legs[i], style: TextStyle(fontSize: 9, fontWeight: FontWeight.w500, color: cs.onSurface.withValues(alpha: 0.35), fontFeatures: const [FontFeature.tabularFigures()])),
            Text('${torqueSum.toStringAsFixed(1)}A', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: cs.onSurface.withValues(alpha: 0.7), fontFeatures: const [FontFeature.tabularFigures()])),
            const SizedBox(height: 3),
            SizedBox(width: 40, height: 3, child: ClipRRect(borderRadius: BorderRadius.circular(2), child: LinearProgressIndicator(value: (torqueSum / 5).clamp(0.0, 1.0), backgroundColor: cs.onSurface.withValues(alpha: 0.04), valueColor: AlwaysStoppedAnimation(colors[i])))),
          ]));
        }),
      ]),
    );
  }

  // ══════════════════════════════════════════════
  // Joint Angles Chart
  // ══════════════════════════════════════════════
  Widget _chartCard(BuildContext ctx, GrpcService g) {
    final cs = Theme.of(ctx).colorScheme;
    const legNames = ['FR', 'FL', 'RR', 'RL'];
    final baseIdx = _selLeg * 3;
    const legColors = [Color(0xFF6366F1), Color(0xFF34D399), Color(0xFFF472B6)];
    const jointSuffix = ['_hip', '_thigh', '_calf'];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: cs.outline.withValues(alpha: 0.5), width: 1), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8)]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.show_chart_rounded, size: 16, color: cs.onSurface.withValues(alpha: 0.3)),
          const SizedBox(width: 6),
          Text('关节角度 (rad)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurface)),
          const Spacer(),
          // Leg selector
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(color: cs.onSurface.withValues(alpha: 0.04), borderRadius: BorderRadius.circular(8)),
            child: Row(children: List.generate(4, (i) => GestureDetector(
              onTap: () => setState(() => _selLeg = i),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: _selLeg == i ? cs.surface : Colors.transparent, borderRadius: BorderRadius.circular(6), boxShadow: _selLeg == i ? [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4)] : []),
                child: Text(legNames[i], style: TextStyle(fontSize: 11, fontWeight: _selLeg == i ? FontWeight.w600 : FontWeight.w400, color: _selLeg == i ? AppTheme.brand : cs.onSurface.withValues(alpha: 0.35))),
              ),
            ))),
          ),
        ]),
        const SizedBox(height: 12),
        // Chart
        Expanded(child: _jHist[baseIdx].isEmpty
          ? Center(child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: AppTheme.green)),
              const SizedBox(width: 6),
              Text('正在接收数据流', style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.3))),
            ]))
          : LineChart(LineChartData(
              lineBarsData: List.generate(3, (ji) {
                final data = _jHist[baseIdx + ji];
                return LineChartBarData(spots: List.generate(data.length, (x) => FlSpot(x.toDouble(), data[x])), isCurved: true, curveSmoothness: 0.2, color: legColors[ji], barWidth: 2, dotData: const FlDotData(show: false));
              }),
              gridData: FlGridData(show: true, drawVerticalLine: false, horizontalInterval: 0.5, getDrawingHorizontalLine: (v) => FlLine(color: cs.onSurface.withValues(alpha: 0.04), strokeWidth: 1)),
              titlesData: FlTitlesData(leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 36, getTitlesWidget: (v, _) => Text(v.toStringAsFixed(1), style: TextStyle(fontSize: 9, color: cs.onSurface.withValues(alpha: 0.25))))), bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)), topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)), rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false))),
              borderData: FlBorderData(show: false),
              lineTouchData: const LineTouchData(enabled: false),
            ), duration: Duration.zero),
        ),
        // Legend
        Row(children: List.generate(3, (ji) => Padding(padding: const EdgeInsets.only(right: 16), child: Row(mainAxisSize: MainAxisSize.min, children: [Container(width: 8, height: 3, decoration: BoxDecoration(color: legColors[ji], borderRadius: BorderRadius.circular(2))), const SizedBox(width: 4), Text('${legNames[_selLeg]}${jointSuffix[ji]}', style: TextStyle(fontSize: 9, color: cs.onSurface.withValues(alpha: 0.35)))])))),
      ]),
    );
  }

  // ══════════════════════════════════════════════
  // System Logs
  // ══════════════════════════════════════════════
  // ══════════════════════════════════════════════
  // RTT latency mini-chart
  // ══════════════════════════════════════════════
  Widget _rttCard(BuildContext ctx, GrpcService g) {
    final cs = Theme.of(ctx).colorScheme;
    final hist = g.rttHistory;
    final hasData = hist.isNotEmpty && g.connected;
    final currentMs = g.lastRttMs;
    final minMs = hasData ? hist.reduce((a, b) => a < b ? a : b) : 0.0;
    final maxMs = hasData ? hist.reduce((a, b) => a > b ? a : b) : 0.0;
    final avgMs = hasData ? hist.reduce((a, b) => a + b) / hist.length : 0.0;

    // Histogram: 10 buckets of 10ms each (0-10, 10-20, ..., 90+)
    final buckets = List.filled(10, 0);
    if (hasData) {
      for (final ms in hist) {
        final b = (ms / 10).floor().clamp(0, 9);
        buckets[b]++;
      }
    }
    final maxBucket = buckets.isEmpty ? 1 : buckets.reduce(math.max);

    Color rttColor(double ms) {
      if (ms < 20) return AppTheme.green;
      if (ms < 60) return AppTheme.orange;
      return AppTheme.red;
    }

    Color bucketColor(int idx) {
      if (idx < 2) return AppTheme.green;
      if (idx < 6) return AppTheme.orange;
      return AppTheme.red;
    }

    final color = hasData ? rttColor(currentMs) : cs.onSurface.withValues(alpha: 0.2);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outline.withValues(alpha: 0.5)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Title
        Row(children: [
          Icon(Icons.network_ping_rounded, size: 13, color: cs.onSurface.withValues(alpha: 0.35)),
          const SizedBox(width: 5),
          Text('网络诊断', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.onSurface)),
          const Spacer(),
          Text('${hist.length} 样本', style: TextStyle(fontSize: 9, color: cs.onSurface.withValues(alpha: 0.3))),
        ]),
        const SizedBox(height: 10),
        // Top row: value + stats + trend
        SizedBox(height: 60, child: Row(children: [
          // Current RTT value
          SizedBox(width: 72, child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
            Text('当前', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: cs.onSurface.withValues(alpha: 0.3), letterSpacing: 0.5)),
            Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
              Text(hasData ? currentMs.toStringAsFixed(0) : '--',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: color, fontFeatures: const [FontFeature.tabularFigures()])),
              Text(' ms', style: TextStyle(fontSize: 10, color: cs.onSurface.withValues(alpha: 0.3))),
            ]),
          ])),
          const SizedBox(width: 10),
          if (hasData) ...[
            Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
              _rttStat('最小', minMs, cs),
              const SizedBox(height: 3),
              _rttStat('平均', avgMs, cs),
              const SizedBox(height: 3),
              _rttStat('最大', maxMs, cs),
            ]),
            const SizedBox(width: 10),
          ],
          // Trend line chart
          Expanded(child: !hasData
            ? Center(child: Text('等待数据...', style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.25))))
            : LineChart(LineChartData(
                gridData: const FlGridData(show: false),
                titlesData: const FlTitlesData(show: false),
                borderData: FlBorderData(show: false),
                minY: 0,
                maxY: (maxMs * 1.3).clamp(10, 200),
                lineTouchData: const LineTouchData(enabled: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: List.generate(hist.length, (i) => FlSpot(i.toDouble(), hist[i])),
                      isCurved: true,
                      curveSmoothness: 0.3,
                      color: color,
                      barWidth: 1.5,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        color: color.withValues(alpha: 0.08),
                      ),
                    ),
                  ],
                )),
          ),
        ])),
        const SizedBox(height: 10),
        // Histogram: 10 buckets × 10ms
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          ...List.generate(10, (i) {
            final frac = maxBucket > 0 ? buckets[i] / maxBucket : 0.0;
            return Expanded(child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  height: (frac * 28).clamp(2.0, 28.0),
                  decoration: BoxDecoration(
                    color: hasData ? bucketColor(i).withValues(alpha: 0.5 + frac * 0.4) : cs.onSurface.withValues(alpha: 0.06),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
                  ),
                ),
                const SizedBox(height: 2),
                Text('${i * 10}', style: TextStyle(fontSize: 7, color: cs.onSurface.withValues(alpha: 0.25))),
              ]),
            ));
          }),
        ]),
        const SizedBox(height: 2),
        Text('延迟分布 (ms)', style: TextStyle(fontSize: 8, color: cs.onSurface.withValues(alpha: 0.25))),
      ]),
    );
  }

  Widget _rttStat(String label, double ms, ColorScheme cs) {
    return Row(children: [
      SizedBox(width: 24, child: Text(label, style: TextStyle(fontSize: 8, color: cs.onSurface.withValues(alpha: 0.3)))),
      Text('${ms.toStringAsFixed(0)} ms',
          style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600,
              color: cs.onSurface.withValues(alpha: 0.55),
              fontFeatures: const [FontFeature.tabularFigures()])),
    ]);
  }

  // Classify a log entry into 'error' | 'warn' | 'info'
  static String _logLevel(ProtocolLogEntry e) {
    final combined = '${e.direction} ${e.method} ${e.summary}'.toLowerCase();
    if (combined.contains('error') || combined.contains('fault') ||
        combined.contains('fail') || e.direction == '⚠') return 'error';
    if (combined.contains('warn') || combined.contains('stale') ||
        combined.contains('reconnect')) return 'warn';
    return 'info';
  }

  Color _levelColor(String level, ColorScheme cs) {
    if (level == 'error') return AppTheme.red;
    if (level == 'warn') return AppTheme.orange;
    return AppTheme.teal;
  }

  Widget _logsCard(BuildContext ctx, GrpcService g) {
    final cs = Theme.of(ctx).colorScheme;
    final allLog = g.protocolLog;
    final log = _logFilter == 'all'
        ? allLog
        : allLog.where((e) => _logLevel(e) == _logFilter).toList();

    final errorCount = allLog.where((e) => _logLevel(e) == 'error').length;
    final warnCount = allLog.where((e) => _logLevel(e) == 'warn').length;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: cs.outline.withValues(alpha: 0.5), width: 1), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8)]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Row(children: [
          Icon(Icons.receipt_long_rounded, size: 16, color: cs.onSurface.withValues(alpha: 0.3)),
          const SizedBox(width: 6),
          Text('系统日志', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurface)),
          const Spacer(),
          // Filter chips
          _LogFilterChip(label: '全部', count: allLog.length, active: _logFilter == 'all',
              color: cs.onSurface, onTap: () => setState(() => _logFilter = 'all')),
          const SizedBox(width: 4),
          _LogFilterChip(label: '错误', count: errorCount, active: _logFilter == 'error',
              color: AppTheme.red, onTap: () => setState(() => _logFilter = 'error')),
          const SizedBox(width: 4),
          _LogFilterChip(label: '警告', count: warnCount, active: _logFilter == 'warn',
              color: AppTheme.orange, onTap: () => setState(() => _logFilter = 'warn')),
        ]),
        const SizedBox(height: 10),
        Expanded(child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: cs.onSurface.withValues(alpha: 0.02), borderRadius: BorderRadius.circular(10), border: Border.all(color: cs.onSurface.withValues(alpha: 0.04), width: 1)),
          child: log.isEmpty
            ? Center(child: Text(_logFilter == 'all' ? '暂无日志' : '无此类型日志',
                style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.15))))
            : ListView.builder(
                itemCount: log.length,
                itemBuilder: (_, i) {
                  final e = log[i];
                  final lvl = _logLevel(e);
                  final lvlColor = _levelColor(lvl, cs);
                  final t = '${e.time.hour.toString().padLeft(2, "0")}:${e.time.minute.toString().padLeft(2, "0")}:${e.time.second.toString().padLeft(2, "0")}';
                  final label = lvl == 'error' ? 'ERR' : lvl == 'warn' ? 'WRN' : 'INF';
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1),
                    child: Container(
                      decoration: lvl != 'info'
                          ? BoxDecoration(
                              color: lvlColor.withValues(alpha: 0.04),
                              borderRadius: BorderRadius.circular(3),
                            )
                          : null,
                      padding: lvl != 'info' ? const EdgeInsets.symmetric(horizontal: 3, vertical: 1) : EdgeInsets.zero,
                      child: Text.rich(TextSpan(children: [
                        TextSpan(text: '[$t] ', style: TextStyle(fontSize: 10, color: cs.onSurface.withValues(alpha: 0.25), fontFeatures: const [FontFeature.tabularFigures()])),
                        TextSpan(text: label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: lvlColor)),
                        TextSpan(text: ' ${e.method}', style: TextStyle(fontSize: 10, color: cs.onSurface.withValues(alpha: 0.5))),
                        if (e.summary.isNotEmpty) TextSpan(text: '  ${e.summary}', style: TextStyle(fontSize: 10, color: lvl != 'info' ? lvlColor.withValues(alpha: 0.7) : cs.onSurface.withValues(alpha: 0.35))),
                      ])),
                    ),
                  );
                },
              ),
        )),
      ]),
    );
  }

  // ══════════════════════════════════════════════
  // Leg Detail Card
  // ══════════════════════════════════════════════
  Widget _legCard(BuildContext ctx, GrpcService g, String title, int baseIdx, Color accent) {
    final cs = Theme.of(ctx).colorScheme;
    final j = g.latestJoints;
    const joints = ['Hip', 'Thigh', 'Calf'];

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outline.withValues(alpha: 0.5), width: 1),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8)],
      ),
      child: Row(children: [
        Container(width: 4, color: accent),
        Expanded(child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Row(children: [
          Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: accent)),
          const Spacer(),
          Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: accent.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(4)), child: Text('激活', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w600, color: accent))),
        ]),
        Divider(color: cs.onSurface.withValues(alpha: 0.06), height: 16),
        // Table header
        Row(children: [
          SizedBox(width: 48, child: Text('关节', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: cs.onSurface.withValues(alpha: 0.25), letterSpacing: 0.5))),
          SizedBox(width: 56, child: Text('弧度', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: cs.onSurface.withValues(alpha: 0.25), letterSpacing: 0.5), textAlign: TextAlign.right)),
          Expanded(child: Text('速度/力矩', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: cs.onSurface.withValues(alpha: 0.25), letterSpacing: 0.5), textAlign: TextAlign.center)),
          SizedBox(width: 52, child: Text('状态', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: cs.onSurface.withValues(alpha: 0.25), letterSpacing: 0.5), textAlign: TextAlign.right)),
        ]),
        const SizedBox(height: 4),
        // 3 joint rows
        ...List.generate(3, (ji) {
          final idx = baseIdx + ji;
          final pos = j != null && j.position.values.length > idx ? j.position.values[idx] : 0.0;
          final vel = j != null && j.velocity.values.length > idx ? j.velocity.values[idx] : 0.0;
          final torque = j != null && j.torque.values.length > idx ? j.torque.values[idx] : 0.0;
          // 电机状态码（G6620 协议）
          final statusCode = j != null && j.status.values.length > idx ? j.status.values[idx] : 0;
          final statusLabel = decodeMotorStatus(statusCode);
          final statusColor = motorStatusColor(statusCode);

          // Mini sparkline from history
          final hist = _jHist[idx];
          final sparkLen = math.min(hist.length, 20);

          return Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: ji < 2 ? BoxDecoration(border: Border(bottom: BorderSide(color: cs.onSurface.withValues(alpha: 0.04)))) : null,
            child: Row(children: [
              SizedBox(width: 48, child: Text(joints[ji], style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: cs.onSurface.withValues(alpha: 0.6)))),
              SizedBox(width: 56, child: Text(pos.toStringAsFixed(2), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: cs.onSurface.withValues(alpha: 0.4), fontFeatures: const [FontFeature.tabularFigures()]), textAlign: TextAlign.right)),
              const SizedBox(width: 10),
              // Sparkline
              SizedBox(width: 60, height: 20, child: sparkLen > 1
                ? CustomPaint(painter: _SparkPainter(data: hist.sublist(hist.length - sparkLen), color: accent.withValues(alpha: 0.5)))
                : Container(height: 1, color: cs.onSurface.withValues(alpha: 0.06))),
              const Spacer(),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('${vel.toStringAsFixed(1)} r/s', style: TextStyle(fontSize: 9, color: cs.onSurface.withValues(alpha: 0.3), fontFeatures: const [FontFeature.tabularFigures()])),
                Text('${torque.toStringAsFixed(1)} Nm', style: TextStyle(fontSize: 9, color: cs.onSurface.withValues(alpha: 0.3), fontFeatures: const [FontFeature.tabularFigures()])),
              ]),
              const SizedBox(width: 6),
              // 电机状态彩色标签
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: statusColor.withValues(alpha: 0.35), width: 0.8),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(fontSize: 8, fontWeight: FontWeight.w600, color: statusColor),
                ),
              ),
            ]),
          );
        }),
      ]),
        )),
      ]),
    );
  }
}

class _LogFilterChip extends StatelessWidget {
  final String label;
  final int count;
  final bool active;
  final Color color;
  final VoidCallback onTap;
  const _LogFilterChip({required this.label, required this.count, required this.active, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.12) : cs.onSurface.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: active ? color.withValues(alpha: 0.3) : Colors.transparent),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: active ? color : cs.onSurface.withValues(alpha: 0.4))),
          if (count > 0) ...[
            const SizedBox(width: 3),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(color: color.withValues(alpha: active ? 0.2 : 0.08), borderRadius: BorderRadius.circular(4)),
              child: Text('$count', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: color.withValues(alpha: active ? 1.0 : 0.5))),
            ),
          ],
        ]),
      ),
    );
  }
}

// ── Sparkline painter ──
class _SparkPainter extends CustomPainter {
  final List<double> data; final Color color;
  _SparkPainter({required this.data, required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2) return;
    final mn = data.reduce(math.min); final mx = data.reduce(math.max);
    final range = mx - mn == 0 ? 1.0 : mx - mn;
    final path = Path();
    for (int i = 0; i < data.length; i++) {
      final x = i / (data.length - 1) * size.width;
      final y = size.height - ((data[i] - mn) / range * size.height);
      if (i == 0) path.moveTo(x, y); else path.lineTo(x, y);
    }
    canvas.drawPath(path, Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 1.5..strokeCap = StrokeCap.round);
  }
  @override
  bool shouldRepaint(covariant _SparkPainter old) =>
      data.length != old.data.length ||
      (data.isNotEmpty && data.last != old.data.last);
}

// ── Torque heatmap gradient legend ──────────────────────────────
class _LegendBar extends StatelessWidget {
  const _LegendBar();
  @override
  Widget build(BuildContext context) {
    return Expanded(child: Container(
      height: 6,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [AppTheme.green.withValues(alpha: 0.4), AppTheme.orange.withValues(alpha: 0.6), AppTheme.red.withValues(alpha: 0.9)]),
        borderRadius: BorderRadius.circular(3),
      ),
    ));
  }
}

// ══════════════════════════════════════
// Connection Quality Badge
// ══════════════════════════════════════
class _QualityBadge extends StatelessWidget {
  final String grade;
  final String description;
  const _QualityBadge({required this.grade, required this.description});

  Color _gradeColor() {
    switch (grade) {
      case 'A': return AppTheme.green;
      case 'B': return const Color(0xFF34D399);
      case 'C': return AppTheme.orange;
      case 'D': return const Color(0xFFF97316);
      default:  return AppTheme.red;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = _gradeColor();
    return Tooltip(
      message: '连接质量：$description',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text('质量', style: TextStyle(fontSize: 9, color: cs.onSurface.withValues(alpha: 0.4))),
          const SizedBox(width: 5),
          Text(grade, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: color, height: 1.0)),
        ]),
      ),
    );
  }
}

// ══════════════════════════════════════
// Gait Phase Lamps
// ══════════════════════════════════════
/// Shows 4 small colored circles for FR/FL/RR/RL.
/// Color = average absolute torque of 3 joints in that leg:
///   <1 Nm  → green  (swing / unloaded)
///   1-5 Nm → amber  (mid)
///   >5 Nm  → brand  (stance / loaded)
class _GaitLamps extends StatelessWidget {
  final dynamic joints; // AllJoints proto or null
  const _GaitLamps({required this.joints});

  // indices: FR[0,1,2] FL[3,4,5] RR[6,7,8] RL[9,10,11]
  static const _labels = ['FR', 'FL', 'RR', 'RL'];
  static const _starts = [0, 3, 6, 9];

  Color _lampColor(double avg) {
    if (avg < 1.0) return AppTheme.green;
    if (avg < 5.0) return AppTheme.orange;
    return AppTheme.brand;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text('步态', style: TextStyle(fontSize: 8, color: cs.onSurface.withValues(alpha: 0.3))),
      const SizedBox(width: 5),
      ...List.generate(4, (i) {
        final start = _starts[i];
        double avg = 0;
        if (joints != null && joints!.torque.values.length > start + 2) {
          avg = (joints!.torque.values[start].abs() +
                 joints!.torque.values[start + 1].abs() +
                 joints!.torque.values[start + 2].abs()) / 3;
        }
        final color = _lampColor(avg);
        return Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Tooltip(
            message: '${_labels[i]}: ${avg.toStringAsFixed(1)} Nm',
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 10, height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: joints != null ? color : cs.onSurface.withValues(alpha: 0.08),
                  boxShadow: joints != null
                      ? [BoxShadow(color: color.withValues(alpha: 0.45), blurRadius: 4)]
                      : [],
                ),
              ),
              const SizedBox(height: 2),
              Text(_labels[i], style: TextStyle(fontSize: 7, color: cs.onSurface.withValues(alpha: 0.3))),
            ]),
          ),
        );
      }),
    ]);
  }
}
