import 'dart:math' as math;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../services/data_recorder.dart';
import '../services/grpc_service.dart';
import '../theme/app_theme.dart';
import '../utils/app_toast.dart';
import '../widgets/status_card.dart';

class ImuPage extends StatefulWidget {
  final GrpcService grpc;
  final DataRecorder recorder;
  const ImuPage({super.key, required this.grpc, required this.recorder});

  @override
  State<ImuPage> createState() => _ImuPageState();
}

class _ImuPageState extends State<ImuPage> {
  static const int _maxPts = 200;
  final List<double> _gx = [], _gy = [], _gz = [];
  // Preview buffer: last 300 frames of joint positions (leg 0 = FR hip)
  static const int _maxPreview = 300;
  final List<List<double>> _previewJoints = List.generate(3, (_) => []); // FR hip/thigh/calf

  @override
  void initState() {
    super.initState();
    widget.grpc.addListener(_onData);
    widget.recorder.addListener(_onRecorderChanged);
  }

  @override
  void dispose() {
    widget.grpc.removeListener(_onData);
    widget.recorder.removeListener(_onRecorderChanged);
    super.dispose();
  }

  void _onRecorderChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _toggleRecording() async {
    final rec = widget.recorder;
    if (rec.isRecording) {
      // Stop + pick save path
      final defaultPath = await DataRecorder.defaultSavePath();
      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: '保存录制数据',
        fileName: defaultPath.split(RegExp(r'[/\\]')).last,
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );
      if (savePath == null) {
        rec.cancelRecording();
        if (mounted) AppToast.showError(context, '录制已取消');
        return;
      }
      try {
        final frames = rec.frameCount;
        await rec.stopAndSave(savePath);
        if (mounted) {
          AppToast.showSuccess(context, '已保存 $frames 帧');
          // Show recording preview dialog
          _showRecordingPreview(frames, savePath);
        }
      } catch (e) {
        if (mounted) AppToast.showError(context, '保存失败: $e');
      }
    } else {
      rec.startRecording();
      if (mounted) AppToast.showSuccess(context, '录制已开始');
    }
  }

  void _showRecordingPreview(int frames, String path) {
    final snap = List.generate(3, (i) => List<double>.from(_previewJoints[i]));
    for (final s in snap) { if (s.isEmpty) return; } // no data to show
    final cs = Theme.of(context).colorScheme;
    const colors = [Color(0xFF6366F1), Color(0xFF34D399), Color(0xFFF472B6)];
    const labels = ['FR 髋', 'FR 大腿', 'FR 小腿'];

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: cs.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          Icon(Icons.bar_chart_rounded, size: 18, color: AppTheme.brand),
          const SizedBox(width: 8),
          Text('录制预览 — $frames 帧', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        ]),
        content: SizedBox(
          width: 420, height: 200,
          child: LineChart(LineChartData(
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: 0.5,
              getDrawingHorizontalLine: (_) => FlLine(color: cs.onSurface.withValues(alpha: 0.05), strokeWidth: 1),
            ),
            titlesData: const FlTitlesData(show: false),
            borderData: FlBorderData(show: false),
            lineTouchData: const LineTouchData(enabled: false),
            lineBarsData: List.generate(3, (i) => LineChartBarData(
              spots: List.generate(snap[i].length, (x) => FlSpot(x.toDouble(), snap[i][x])),
              isCurved: true,
              curveSmoothness: 0.3,
              color: colors[i],
              barWidth: 1.5,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(show: true, color: colors[i].withValues(alpha: 0.05)),
            )),
          )),
        ),
        actions: [
          Row(children: [
            ...List.generate(3, (i) => Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 10, height: 10, decoration: BoxDecoration(color: colors[i], borderRadius: BorderRadius.circular(2))),
                const SizedBox(width: 4),
                Text(labels[i], style: TextStyle(fontSize: 10, color: cs.onSurface.withValues(alpha: 0.5))),
              ]),
            )),
            const Spacer(),
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('关闭')),
          ]),
        ],
      ),
    );
  }

  void _onData() {
    final imu = widget.grpc.latestImu;
    if (imu != null && imu.hasGyroscope()) {
      _gx.add(imu.gyroscope.x);
      if (_gx.length > _maxPts) _gx.removeAt(0);
      _gy.add(imu.gyroscope.y);
      if (_gy.length > _maxPts) _gy.removeAt(0);
      _gz.add(imu.gyroscope.z);
      if (_gz.length > _maxPts) _gz.removeAt(0);
    }
    // Accumulate preview joint data (FR leg: indices 0,1,2)
    if (widget.recorder.isRecording) {
      final j = widget.grpc.latestJoints;
      if (j != null && j.position.values.length >= 3) {
        for (int i = 0; i < 3; i++) {
          _previewJoints[i].add(j.position.values[i]);
          if (_previewJoints[i].length > _maxPreview) _previewJoints[i].removeAt(0);
        }
      }
    }
    if (mounted) setState(() {});
  }

  /// Derive roll/pitch/yaw in degrees from quaternion.
  (double, double, double) _rpy() {
    final q = widget.grpc.latestImu?.quaternion;
    if (q == null) return (0, 0, 0);
    final roll = math.atan2(2 * (q.w * q.x + q.y * q.z), 1 - 2 * (q.x * q.x + q.y * q.y)) * 180 / math.pi;
    final sp = 2 * (q.w * q.y - q.z * q.x);
    final pitch = (sp.abs() >= 1 ? (math.pi / 2) * sp.sign : math.asin(sp)) * 180 / math.pi;
    final yaw = math.atan2(2 * (q.w * q.z + q.x * q.y), 1 - 2 * (q.y * q.y + q.z * q.z)) * 180 / math.pi;
    return (roll, pitch, yaw);
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.grpc;
    final cs = Theme.of(context).colorScheme;
    final (roll, pitch, yaw) = _rpy();
    final grav = g.latestHistory?.hasProjectedGravity() == true
        ? g.latestHistory!.projectedGravity
        : null;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──
          Row(children: [
            Text('IMU / 姿态', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: cs.onSurface)),
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
            const Spacer(),
            // Recording control
            _RecordBtn(
              recorder: widget.recorder,
              enabled: g.connected,
              onToggle: _toggleRecording,
            ),
            const SizedBox(width: 12),
            Text('IMU  ${g.imuHz.toStringAsFixed(1)} Hz',
                style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.4))),
          ]),
          const SizedBox(height: 4),
          Text('实时陀螺仪与四元数姿态可视化', style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.35))),
          const SizedBox(height: 16),

          // ── Row 1: Gauges + Gyro chart ──
          Expanded(
            flex: 5,
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              // Attitude gauges
              Expanded(
                flex: 4,
                child: StatusCard(
                  title: '姿态角',
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _AttitudeGauge(label: 'Roll', value: roll, color: AppTheme.teal),
                      _AttitudeGauge(label: 'Pitch', value: pitch, color: AppTheme.orange),
                      _AttitudeGauge(label: 'Yaw', value: yaw, color: AppTheme.yellow),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Gyroscope time-series chart
              Expanded(
                flex: 7,
                child: StatusCard(
                  title: '陀螺仪 (rad/s)',
                  fillChildHeight: true,
                  child: _GyroChart(gx: _gx, gy: _gy, gz: _gz),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 12),

          // ── Row 2: Artificial horizon + Gravity indicator ──
          Expanded(
            flex: 4,
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              // Artificial horizon
              Expanded(
                child: StatusCard(
                  title: '人工地平仪',
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: 1.6,
                      child: _ArtificialHorizon(roll: roll, pitch: pitch),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Projected gravity indicator
              Expanded(
                child: StatusCard(
                  title: '投影重力向量',
                  trailing: grav != null
                      ? Text(
                          'x:${grav.x.toStringAsFixed(2)} y:${grav.y.toStringAsFixed(2)}',
                          style: TextStyle(fontSize: 10, color: cs.onSurface.withValues(alpha: 0.4)),
                        )
                      : null,
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: _GravityIndicator(
                        gx: grav?.x ?? 0,
                        gy: grav?.y ?? 0,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Sensor numeric overview
              SizedBox(
                width: 240,
                child: _SensorOverview(
                  roll: roll, pitch: pitch, yaw: yaw,
                  imu: g.latestImu,
                  grav: grav,
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// Sensor numeric overview panel (3×3 grid)
// ══════════════════════════════════════════════════════════════
class _SensorOverview extends StatelessWidget {
  final double roll, pitch, yaw;
  final dynamic imu;    // Imu proto message or null
  final dynamic grav;   // Vector3 proto or null

  const _SensorOverview({
    required this.roll, required this.pitch, required this.yaw,
    required this.imu, required this.grav,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final gyro = imu?.hasGyroscope() == true ? imu!.gyroscope : null;

    final groups = [
      (
        title: '姿态角 (°)',
        color: AppTheme.teal,
        items: [('R', roll), ('P', pitch), ('Y', yaw)],
      ),
      (
        title: '陀螺仪 (rad/s)',
        color: AppTheme.orange,
        items: [('Gx', gyro?.x ?? 0.0), ('Gy', gyro?.y ?? 0.0), ('Gz', gyro?.z ?? 0.0)],
      ),
      (
        title: '投影重力',
        color: const Color(0xFF8B5CF6),
        items: [('gx', grav?.x ?? 0.0), ('gy', grav?.y ?? 0.0), ('gz', 0.0)],
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outline.withValues(alpha: 0.5)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.grid_on_rounded, size: 12, color: cs.onSurface.withValues(alpha: 0.3)),
          const SizedBox(width: 5),
          Text('传感器总览', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: cs.onSurface)),
        ]),
        const SizedBox(height: 10),
        ...groups.map((g) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: g.color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
              child: Text(g.title, style: TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: g.color)),
            ),
            const SizedBox(height: 5),
            Row(children: g.items.map((item) => Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.$1, style: TextStyle(fontSize: 8, color: cs.onSurface.withValues(alpha: 0.35))),
                Text(
                  item.$2.toStringAsFixed(2),
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: cs.onSurface,
                      fontFeatures: const [FontFeature.tabularFigures()]),
                ),
              ],
            ))).toList()),
          ]),
        )),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// Attitude gauge (arc dial)
// ══════════════════════════════════════════════════════════════

class _AttitudeGauge extends StatelessWidget {
  final String label;
  final double value; // degrees
  final Color color;
  final double warnAt;   // |value| threshold for orange
  final double critAt;   // |value| threshold for red

  const _AttitudeGauge({required this.label, required this.value, required this.color,
    this.warnAt = 20.0, this.critAt = 35.0});

  Color _activeColor() {
    final abs = value.abs();
    if (abs >= critAt) return AppTheme.red;
    if (abs >= warnAt) return AppTheme.orange;
    return color;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final activeColor = _activeColor();
    final isWarning = value.abs() >= warnAt;

    return SizedBox(
      width: 110,
      height: 110,
      child: CustomPaint(
        painter: _GaugePainter(value: value, color: activeColor, cs: cs),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (isWarning)
              Icon(Icons.warning_amber_rounded, size: 10, color: activeColor),
            Text(
              '${value.toStringAsFixed(1)}°',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: isWarning ? activeColor : cs.onSurface,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            Text(label, style: TextStyle(fontSize: 10, color: cs.onSurface.withValues(alpha: 0.45))),
          ]),
        ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double value;  // -90 to +90 degrees
  final Color color;
  final ColorScheme cs;

  const _GaugePainter({required this.value, required this.color, required this.cs});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 8;
    // Arc from 150° to 30° (going clockwise) = 240° sweep
    const arcStart = math.pi * 5 / 6;       // 150°
    const arcSweep = math.pi * 4 / 3;       // 240°

    // Background arc
    final bgPaint = Paint()
      ..color = cs.onSurface.withValues(alpha: 0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      arcStart, arcSweep, false, bgPaint,
    );

    // Foreground arc — clamped value
    final clamped = value.clamp(-90.0, 90.0);
    final fraction = (clamped + 90) / 180; // 0.0 .. 1.0
    final fgSweep = fraction * arcSweep;

    final fgPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      arcStart, fgSweep, false, fgPaint,
    );

    // Zero tick
    final zeroAngle = arcStart + arcSweep / 2;
    final tickStart = Offset(
      center.dx + (radius - 10) * math.cos(zeroAngle),
      center.dy + (radius - 10) * math.sin(zeroAngle),
    );
    final tickEnd = Offset(
      center.dx + (radius + 2) * math.cos(zeroAngle),
      center.dy + (radius + 2) * math.sin(zeroAngle),
    );
    canvas.drawLine(tickStart, tickEnd,
        Paint()..color = cs.onSurface.withValues(alpha: 0.25)..strokeWidth = 1.5);
  }

  @override
  bool shouldRepaint(_GaugePainter old) => old.value != value || old.color != color;
}

// ══════════════════════════════════════════════════════════════
// Gyroscope time-series chart
// ══════════════════════════════════════════════════════════════

class _GyroChart extends StatelessWidget {
  final List<double> gx, gy, gz;

  const _GyroChart({required this.gx, required this.gy, required this.gz});

  List<FlSpot> _spots(List<double> data) => List.generate(
      data.length, (i) => FlSpot(i.toDouble(), data[i]));

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (gx.isEmpty) {
      return Center(
        child: Text('等待 IMU 数据...', style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.3))),
      );
    }

    return LineChart(
      LineChartData(
        minY: -5,
        maxY: 5,
        clipData: const FlClipData.all(),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => FlLine(color: cs.onSurface.withValues(alpha: 0.05), strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 32,
              interval: 2.5,
              getTitlesWidget: (v, _) => Text(v.toStringAsFixed(1),
                  style: TextStyle(fontSize: 8, color: cs.onSurface.withValues(alpha: 0.35))),
            ),
          ),
          bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        lineBarsData: [
          _line(gx, AppTheme.teal, 'Gx'),
          _line(gy, AppTheme.green, 'Gy'),
          _line(gz, AppTheme.orange, 'Gz'),
        ],
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => cs.surface,
            getTooltipItems: (spots) => spots.map((s) {
              const labels = ['Gx', 'Gy', 'Gz'];
              const colors = [AppTheme.teal, AppTheme.green, AppTheme.orange];
              return LineTooltipItem(
                '${labels[s.barIndex]}: ${s.y.toStringAsFixed(3)}',
                TextStyle(fontSize: 10, color: colors[s.barIndex], fontWeight: FontWeight.w600),
              );
            }).toList(),
          ),
        ),
      ),
      duration: Duration.zero,
    );
  }

  LineChartBarData _line(List<double> data, Color color, String label) => LineChartBarData(
        spots: _spots(data),
        isCurved: false,
        color: color,
        barWidth: 1.5,
        dotData: const FlDotData(show: false),
        belowBarData: BarAreaData(
          show: true,
          color: color.withValues(alpha: 0.06),
        ),
      );
}

// ══════════════════════════════════════════════════════════════
// Artificial horizon
// ══════════════════════════════════════════════════════════════

class _ArtificialHorizon extends StatelessWidget {
  final double roll;  // degrees
  final double pitch; // degrees

  const _ArtificialHorizon({required this.roll, required this.pitch});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: CustomPaint(
        painter: _HorizonPainter(roll: roll, pitch: pitch, cs: cs),
      ),
    );
  }
}

class _HorizonPainter extends CustomPainter {
  final double roll, pitch;
  final ColorScheme cs;

  const _HorizonPainter({required this.roll, required this.pitch, required this.cs});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final cx = w / 2, cy = h / 2;

    // Pitch offset: 1 degree ≈ h/90 * 0.5 pixels (gentle)
    final pitchOffset = pitch * h / 120;

    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(roll * math.pi / 180);
    canvas.translate(-cx, -cy);

    // Sky (top half, shifted by pitch)
    final skyPaint = Paint()..color = const Color(0xFF1E40AF).withValues(alpha: 0.25);
    canvas.drawRect(Rect.fromLTWH(0, 0, w, cy + pitchOffset), skyPaint);

    // Ground (bottom half, shifted by pitch)
    final groundPaint = Paint()..color = const Color(0xFF78350F).withValues(alpha: 0.25);
    canvas.drawRect(Rect.fromLTWH(0, cy + pitchOffset, w, h - (cy + pitchOffset)), groundPaint);

    // Horizon line
    final horizonPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.7)
      ..strokeWidth = 1.5;
    canvas.drawLine(Offset(0, cy + pitchOffset), Offset(w, cy + pitchOffset), horizonPaint);

    // Pitch ticks (every 10°)
    final tickPaint = Paint()..color = Colors.white.withValues(alpha: 0.4)..strokeWidth = 1;
    for (int deg = -30; deg <= 30; deg += 10) {
      if (deg == 0) continue;
      final ty = cy + pitchOffset + deg * h / 120;
      final tw = deg % 20 == 0 ? 30.0 : 16.0;
      canvas.drawLine(Offset(cx - tw, ty), Offset(cx + tw, ty), tickPaint);
    }

    canvas.restore();

    // Fixed crosshair (always centered, not rotated)
    final xhPaint = Paint()..color = cs.onSurface.withValues(alpha: 0.7)..strokeWidth = 2..strokeCap = StrokeCap.round;
    // Center dot
    canvas.drawCircle(Offset(cx, cy), 3, xhPaint);
    // Left arm
    canvas.drawLine(Offset(cx - 40, cy), Offset(cx - 12, cy), xhPaint);
    // Right arm
    canvas.drawLine(Offset(cx + 12, cy), Offset(cx + 40, cy), xhPaint);
  }

  @override
  bool shouldRepaint(_HorizonPainter old) => old.roll != roll || old.pitch != pitch;
}

// ══════════════════════════════════════════════════════════════
// Projected gravity 2D indicator
// ══════════════════════════════════════════════════════════════

class _GravityIndicator extends StatelessWidget {
  final double gx, gy; // projected gravity x/y components (-1..1 range)

  const _GravityIndicator({required this.gx, required this.gy});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return CustomPaint(
      painter: _GravityPainter(gx: gx, gy: gy, cs: cs),
    );
  }
}

class _GravityPainter extends CustomPainter {
  final double gx, gy;
  final ColorScheme cs;

  const _GravityPainter({required this.gx, required this.gy, required this.cs});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2, cy = size.height / 2;
    final r = math.min(cx, cy) - 12;

    // Outer ring
    final ringPaint = Paint()
      ..color = cs.onSurface.withValues(alpha: 0.1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawCircle(Offset(cx, cy), r, ringPaint);

    // Grid lines
    final gridPaint = Paint()..color = cs.onSurface.withValues(alpha: 0.06)..strokeWidth = 1;
    canvas.drawLine(Offset(cx - r, cy), Offset(cx + r, cy), gridPaint);
    canvas.drawLine(Offset(cx, cy - r), Offset(cx, cy + r), gridPaint);

    // Inner reference circle (0.5g)
    canvas.drawCircle(Offset(cx, cy), r * 0.5,
        Paint()..color = cs.onSurface.withValues(alpha: 0.06)..style = PaintingStyle.stroke..strokeWidth = 1);

    // Ball position (gx/gy clamped to ±1)
    final bx = cx + gx.clamp(-1.0, 1.0) * r;
    final by = cy + gy.clamp(-1.0, 1.0) * r;
    final dist = math.sqrt(gx * gx + gy * gy);
    final ballColor = dist < 0.15 ? AppTheme.green : (dist < 0.4 ? AppTheme.yellow : AppTheme.red);

    // Glow
    canvas.drawCircle(Offset(bx, by), 14,
        Paint()..color = ballColor.withValues(alpha: 0.15)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
    // Ball
    canvas.drawCircle(Offset(bx, by), 8, Paint()..color = ballColor);
    // Center dot reference
    canvas.drawCircle(Offset(cx, cy), 2,
        Paint()..color = cs.onSurface.withValues(alpha: 0.3));
  }

  @override
  bool shouldRepaint(_GravityPainter old) => old.gx != gx || old.gy != gy;
}

// ── Recording button ──────────────────────────────────────────
class _RecordBtn extends StatefulWidget {
  final DataRecorder recorder;
  final bool enabled;
  final VoidCallback onToggle;
  const _RecordBtn({required this.recorder, required this.enabled, required this.onToggle});
  @override
  State<_RecordBtn> createState() => _RecordBtnState();
}

class _RecordBtnState extends State<_RecordBtn> {
  bool _hov = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rec = widget.recorder;
    final isRec = rec.isRecording;
    final color = isRec ? AppTheme.red : AppTheme.brand;
    final label = isRec ? '停止录制 (${rec.frameCount}帧)' : '录制';

    return MouseRegion(
      onEnter: (_) => setState(() => _hov = true),
      onExit: (_) => setState(() => _hov = false),
      child: GestureDetector(
        onTap: widget.enabled ? widget.onToggle : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: isRec
                ? color.withValues(alpha: _hov ? 0.15 : 0.1)
                : (_hov && widget.enabled ? color.withValues(alpha: 0.08) : Colors.transparent),
            borderRadius: BorderRadius.circular(8),
            border: isRec
                ? Border.all(color: color.withValues(alpha: 0.3))
                : (_hov && widget.enabled ? Border.all(color: color.withValues(alpha: 0.2)) : null),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(
              isRec ? Icons.stop_circle_rounded : Icons.fiber_manual_record_rounded,
              size: 12,
              color: widget.enabled
                  ? (isRec ? color : color.withValues(alpha: 0.7))
                  : cs.onSurface.withValues(alpha: 0.2),
            ),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: widget.enabled
                      ? (isRec ? color : cs.onSurface.withValues(alpha: 0.5))
                      : cs.onSurface.withValues(alpha: 0.2),
                )),
          ]),
        ),
      ),
    );
  }
}
