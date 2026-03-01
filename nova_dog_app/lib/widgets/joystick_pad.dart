import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/grpc_service.dart';
import '../theme/app_theme.dart';

// ── Speed presets ──
enum WalkSpeed {
  slow(0.3, '慢'),
  normal(0.55, '标'),
  fast(1.0, '快');

  final double multiplier;
  final String label;
  const WalkSpeed(this.multiplier, this.label);
}

/// Joystick + rotation strip control panel that sends walk commands via [grpc].
class JoystickPanel extends StatefulWidget {
  final GrpcService grpc;
  /// Optional external speed controller; if provided the joystick both reads
  /// and writes this notifier so keyboard shortcuts can change the speed.
  final ValueNotifier<WalkSpeed>? speedNotifier;
  /// Optional set of currently pressed walk key labels (W/A/S/D/Q/E).
  final ValueNotifier<Set<String>>? keysNotifier;
  const JoystickPanel({super.key, required this.grpc, this.speedNotifier, this.keysNotifier});

  @override
  State<JoystickPanel> createState() => _JoystickPanelState();
}

/// Axis lock mode for the joystick.
enum _AxisLock { none, xOnly, yOnly }

class _JoystickPanelState extends State<JoystickPanel> {
  // Normalised [-1, 1] for each axis
  double _jx = 0, _jy = 0, _jz = 0;
  WalkSpeed _speed = WalkSpeed.normal;
  Timer? _ticker;
  bool _active = false; // joystick or rotation is being touched
  _AxisLock _axisLock = _AxisLock.none;

  @override
  void initState() {
    super.initState();
    if (widget.speedNotifier != null) {
      _speed = widget.speedNotifier!.value;
      widget.speedNotifier!.addListener(_onExternalSpeedChanged);
    }
  }

  void _onExternalSpeedChanged() {
    if (mounted) setState(() => _speed = widget.speedNotifier!.value);
  }

  void _setSpeed(WalkSpeed s) {
    setState(() => _speed = s);
    widget.speedNotifier?.value = s;
  }

  @override
  void dispose() {
    widget.speedNotifier?.removeListener(_onExternalSpeedChanged);
    _ticker?.cancel();
    super.dispose();
  }

  void _startTicker() {
    _ticker ??= Timer.periodic(const Duration(milliseconds: 33), (_) {
      // 30 Hz
      if (widget.grpc.connected) {
        widget.grpc.walk(
          _jx * _speed.multiplier,
          _jy * _speed.multiplier,
          _jz * _speed.multiplier * 0.6,
        );
      }
    });
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  void _onJoyStart() {
    _active = true;
    _startTicker();
  }

  void _onJoyChange(double x, double y) {
    final lx = _axisLock == _AxisLock.yOnly ? 0.0 : x;
    final ly = _axisLock == _AxisLock.xOnly ? 0.0 : y;
    setState(() { _jx = lx; _jy = ly; });
  }

  void _onJoyEnd() {
    setState(() { _jx = 0; _jy = 0; });
    if (!_active) return;
    // If rotation also zeroed, stop ticker
    if (_jz == 0) _stopTicker();
  }

  void _onRotChange(double z) {
    final wasZero = _jz == 0;
    setState(() => _jz = z);
    if (wasZero && z != 0) _startTicker();
  }

  void _onRotEnd() {
    setState(() => _jz = 0);
    if (_jx == 0 && _jy == 0) _stopTicker();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final canWalk = widget.grpc.connected;

    // Live command display
    final sx = (_jx * _speed.multiplier).toStringAsFixed(2);
    final sy = (_jy * _speed.multiplier).toStringAsFixed(2);
    final sz = (_jz * _speed.multiplier * 0.6).toStringAsFixed(2);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outline.withValues(alpha: 0.5)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Row(children: [
          Text('行走控制', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
              color: cs.onSurface.withValues(alpha: 0.7))),
          const SizedBox(width: 8),
          if (!canWalk)
            Text('未连接', style: TextStyle(fontSize: 10, color: cs.onSurface.withValues(alpha: 0.3))),
          const Spacer(),
          // Live cmd
          if (canWalk)
            Text(
              '前 $sx  侧 $sy  转 $sz',
              style: TextStyle(fontSize: 10, fontFeatures: const [FontFeature.tabularFigures()],
                  color: (_jx != 0 || _jy != 0 || _jz != 0)
                      ? AppTheme.brand
                      : cs.onSurface.withValues(alpha: 0.3)),
            ),
          // Axis lock toggle
          const SizedBox(width: 8),
          _AxisLockButton(
            current: _axisLock,
            onToggle: (mode) => setState(() => _axisLock = mode),
          ),
          // WASD key indicators
          if (widget.keysNotifier != null) ...[
            const SizedBox(width: 8),
            ValueListenableBuilder<Set<String>>(
              valueListenable: widget.keysNotifier!,
              builder: (_, keys, __) => Row(mainAxisSize: MainAxisSize.min, children: [
                for (final k in ['W', 'A', 'S', 'D', 'Q', 'E'])
                  _KeyPill(label: k, active: keys.contains(k)),
              ]),
            ),
          ],
        ]),
        const SizedBox(height: 10),

        // Main controls row
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          // XY Joystick
          Opacity(
            opacity: canWalk ? 1.0 : 0.35,
            child: _JoystickCircle(
              enabled: canWalk,
              onStart: _onJoyStart,
              onChange: _onJoyChange,
              onEnd: _onJoyEnd,
            ),
          ),
          const SizedBox(width: 16),

          // Rotation strip
          Opacity(
            opacity: canWalk ? 1.0 : 0.35,
            child: _RotationStrip(
              enabled: canWalk,
              value: _jz,
              onChange: _onRotChange,
              onEnd: _onRotEnd,
            ),
          ),
          const SizedBox(width: 16),

          // Speed selector
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('速度', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700,
                  color: cs.onSurface.withValues(alpha: 0.3), letterSpacing: 0.5)),
              const SizedBox(height: 6),
              ...WalkSpeed.values.map((s) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: GestureDetector(
                  onTap: () => _setSpeed(s),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: _speed == s
                          ? AppTheme.brand.withValues(alpha: 0.12)
                          : cs.onSurface.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(8),
                      border: _speed == s
                          ? Border.all(color: AppTheme.brand.withValues(alpha: 0.3))
                          : null,
                    ),
                    child: Text(s.label, style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w600,
                      color: _speed == s ? AppTheme.brand : cs.onSurface.withValues(alpha: 0.4),
                    )),
                  ),
                ),
              )),
            ],
          ),
          const SizedBox(width: 16),
          // Speedometer gauge
          _Speedometer(
            value: _jx * _speed.multiplier,       // forward component
            maxSpeed: WalkSpeed.fast.multiplier,
            cs: cs,
          ),
        ]),
      ]),
    );
  }
}

// ── XY Joystick Circle ──────────────────────────────────────────
class _JoystickCircle extends StatefulWidget {
  final bool enabled;
  final VoidCallback onStart;
  final void Function(double x, double y) onChange;
  final VoidCallback onEnd;
  const _JoystickCircle(
      {required this.enabled,
      required this.onStart,
      required this.onChange,
      required this.onEnd});

  @override
  State<_JoystickCircle> createState() => _JoystickCircleState();
}

class _JoystickCircleState extends State<_JoystickCircle> {
  static const double _size = 130;
  static const double _radius = _size / 2;
  static const double _thumbR = 22;

  Offset _thumb = Offset.zero; // relative to center, clamped
  bool _dragging = false;

  Offset _clamp(Offset raw) {
    final dist = raw.distance;
    final maxD = _radius - _thumbR;
    if (dist > maxD) return raw / dist * maxD;
    return raw;
  }

  void _update(Offset localPos) {
    final center = const Offset(_radius, _radius);
    final rel = localPos - center;
    final clamped = _clamp(rel);
    setState(() => _thumb = clamped);
    final maxD = _radius - _thumbR;
    // x = forward (up on screen), y = strafe (right on screen)
    widget.onChange(-clamped.dy / maxD, clamped.dx / maxD);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onPanStart: widget.enabled
          ? (d) {
              setState(() => _dragging = true);
              widget.onStart();
              _update(d.localPosition);
            }
          : null,
      onPanUpdate: widget.enabled ? (d) => _update(d.localPosition) : null,
      onPanEnd: widget.enabled
          ? (_) {
              setState(() { _dragging = false; _thumb = Offset.zero; });
              widget.onEnd();
            }
          : null,
      child: SizedBox(
        width: _size,
        height: _size,
        child: CustomPaint(
          painter: _JoystickPainter(
            thumb: _thumb,
            dragging: _dragging,
            cs: cs,
          ),
        ),
      ),
    );
  }
}

class _JoystickPainter extends CustomPainter {
  final Offset thumb;
  final bool dragging;
  final ColorScheme cs;
  const _JoystickPainter({required this.thumb, required this.dragging, required this.cs});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2;

    // Outer ring
    canvas.drawCircle(center, radius - 1,
        Paint()
          ..color = cs.onSurface.withValues(alpha: 0.06)
          ..style = PaintingStyle.fill);
    canvas.drawCircle(center, radius - 1,
        Paint()
          ..color = cs.outline.withValues(alpha: dragging ? 0.4 : 0.25)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);

    // Cross-hair
    final hairPaint = Paint()
      ..color = cs.onSurface.withValues(alpha: 0.08)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(center.dx, 8), Offset(center.dx, size.height - 8), hairPaint);
    canvas.drawLine(Offset(8, center.dy), Offset(size.width - 8, center.dy), hairPaint);

    // Inner dead-zone ring (dashed, ~15% radius) — return-to-center indicator
    final dzR = radius * 0.15;
    const dashCount = 12;
    const dashArc = 3.14159 * 2 / dashCount;
    for (int i = 0; i < dashCount; i += 2) {
      final startAngle = dashArc * i;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: dzR),
        startAngle, dashArc * 0.8,
        false,
        Paint()
          ..color = cs.onSurface.withValues(alpha: 0.18)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
    }

    // Direction rings (45% and 75%)
    for (final r in [radius * 0.45, radius * 0.75]) {
      canvas.drawCircle(center, r,
          Paint()
            ..color = cs.onSurface.withValues(alpha: 0.05)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1);
    }

    // Thumb
    final thumbCenter = center + thumb;
    final thumbColor = dragging ? AppTheme.brand : cs.onSurface.withValues(alpha: 0.45);

    canvas.drawCircle(thumbCenter, 22,
        Paint()..color = thumbColor.withValues(alpha: dragging ? 0.12 : 0.06));
    canvas.drawCircle(thumbCenter, 22,
        Paint()
          ..color = thumbColor.withValues(alpha: 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);
    canvas.drawCircle(thumbCenter, 8,
        Paint()..color = thumbColor.withValues(alpha: dragging ? 0.9 : 0.5));
  }

  @override
  bool shouldRepaint(_JoystickPainter old) =>
      old.thumb != thumb || old.dragging != dragging;
}

// ── Rotation vertical strip ─────────────────────────────────────
class _RotationStrip extends StatefulWidget {
  final bool enabled;
  final double value; // [-1, 1]
  final void Function(double) onChange;
  final VoidCallback onEnd;
  const _RotationStrip(
      {required this.enabled,
      required this.value,
      required this.onChange,
      required this.onEnd});

  @override
  State<_RotationStrip> createState() => _RotationStripState();
}

class _RotationStripState extends State<_RotationStrip> {
  static const double _height = 130;
  static const double _width = 44;
  bool _dragging = false;

  void _update(double localY) {
    final clamped = localY.clamp(0.0, _height);
    // Top = +1 (rotate right), bottom = -1 (rotate left)
    final norm = 1.0 - (clamped / _height) * 2.0;
    widget.onChange(norm);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.rotate_right_rounded, size: 13, color: cs.onSurface.withValues(alpha: 0.3)),
      const SizedBox(height: 4),
      GestureDetector(
        onPanStart: widget.enabled
            ? (d) {
                setState(() => _dragging = true);
                _update(d.localPosition.dy);
              }
            : null,
        onPanUpdate: widget.enabled ? (d) => _update(d.localPosition.dy) : null,
        onPanEnd: widget.enabled
            ? (_) {
                setState(() => _dragging = false);
                widget.onEnd();
              }
            : null,
        child: SizedBox(
          width: _width,
          height: _height,
          child: CustomPaint(
            painter: _RotationPainter(value: widget.value, dragging: _dragging, cs: cs),
          ),
        ),
      ),
      const SizedBox(height: 4),
      Icon(Icons.rotate_left_rounded, size: 13, color: cs.onSurface.withValues(alpha: 0.3)),
    ]);
  }
}

class _RotationPainter extends CustomPainter {
  final double value; // [-1, 1]
  final bool dragging;
  final ColorScheme cs;
  const _RotationPainter({required this.value, required this.dragging, required this.cs});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final trackColor = cs.onSurface.withValues(alpha: 0.06);
    final activeColor = dragging ? AppTheme.brand : cs.onSurface.withValues(alpha: 0.45);

    // Track background
    final rr = RRect.fromRectAndRadius(Rect.fromLTWH(cx - 10, 0, 20, size.height),
        const Radius.circular(10));
    canvas.drawRRect(rr, Paint()..color = trackColor);

    // Active fill from center
    final mid = size.height / 2;
    final thumbY = mid - value * mid; // map [-1,1] to [height..0]
    final fillTop = math.min(mid, thumbY);
    final fillBottom = math.max(mid, thumbY);
    final fillRr = RRect.fromRectAndRadius(
        Rect.fromLTRB(cx - 10, fillTop, cx + 10, fillBottom), const Radius.circular(4));
    canvas.drawRRect(fillRr, Paint()..color = activeColor.withValues(alpha: 0.25));

    // Center mark
    canvas.drawLine(Offset(cx - 8, mid), Offset(cx + 8, mid),
        Paint()..color = cs.onSurface.withValues(alpha: 0.15)..strokeWidth = 1);

    // Thumb circle
    canvas.drawCircle(Offset(cx, thumbY), 12,
        Paint()..color = activeColor.withValues(alpha: dragging ? 0.12 : 0.06));
    canvas.drawCircle(Offset(cx, thumbY), 12,
        Paint()
          ..color = activeColor.withValues(alpha: 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);
    canvas.drawCircle(Offset(cx, thumbY), 5,
        Paint()..color = activeColor.withValues(alpha: dragging ? 0.9 : 0.5));
  }

  @override
  bool shouldRepaint(_RotationPainter old) =>
      old.value != value || old.dragging != dragging;
}

// ── Speedometer Arc Gauge ─────────────────────────────────────────
class _Speedometer extends StatelessWidget {
  final double value;     // signed forward speed (negative = backward)
  final double maxSpeed;  // max positive speed
  final ColorScheme cs;
  const _Speedometer({required this.value, required this.maxSpeed, required this.cs});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 100,
      height: 100,
      child: CustomPaint(
        painter: _SpeedometerPainter(value: value, maxSpeed: maxSpeed, cs: cs),
      ),
    );
  }
}

class _SpeedometerPainter extends CustomPainter {
  final double value;
  final double maxSpeed;
  final ColorScheme cs;
  const _SpeedometerPainter({required this.value, required this.maxSpeed, required this.cs});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 6;
    const startAngle = math.pi * 0.75;   // 135°
    const sweepMax = math.pi * 1.5;       // 270° arc total

    // Background arc
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle, sweepMax, false,
      Paint()
        ..color = cs.onSurface.withValues(alpha: 0.07)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round,
    );

    // Filled arc — clamp to [-maxSpeed, maxSpeed], map to [0, sweepMax]
    final norm = (value / maxSpeed).clamp(-1.0, 1.0);
    // Center at sweepMax/2; positive = forward (right half), negative = backward (left half)
    final center_ = sweepMax / 2;
    final arcStart = startAngle + center_;
    final arcSweep = norm * (sweepMax / 2);
    if (arcSweep.abs() > 0.01) {
      final paintColor = value >= 0 ? AppTheme.brand : AppTheme.orange;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        arcStart, arcSweep, false,
        Paint()
          ..color = paintColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 8
          ..strokeCap = StrokeCap.round,
      );
    }

    // Center dot
    canvas.drawCircle(center, 4, Paint()..color = cs.onSurface.withValues(alpha: 0.15));

    // Speed value text
    final absVal = value.abs();
    final textPainter = TextPainter(
      text: TextSpan(
        children: [
          TextSpan(
            text: absVal < 0.01 ? '0' : absVal.toStringAsFixed(2),
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: cs.onSurface, fontFeatures: const [FontFeature.tabularFigures()]),
          ),
        ],
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(canvas, center + Offset(-textPainter.width / 2, 8));

    // "m/s" label
    final unitPainter = TextPainter(
      text: TextSpan(text: 'm/s', style: TextStyle(fontSize: 8, color: cs.onSurface.withValues(alpha: 0.3))),
      textDirection: TextDirection.ltr,
    )..layout();
    unitPainter.paint(canvas, center + Offset(-unitPainter.width / 2, 28));
  }

  @override
  bool shouldRepaint(_SpeedometerPainter old) => old.value != value;
}

// ── Key indicator pill ─────────────────────────────────────────────
class _KeyPill extends StatelessWidget {
  final String label;
  final bool active;
  const _KeyPill({required this.label, required this.active});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 80),
      margin: const EdgeInsets.symmetric(horizontal: 2),
      width: 20,
      height: 18,
      decoration: BoxDecoration(
        color: active ? AppTheme.brand.withValues(alpha: 0.18) : cs.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: active ? AppTheme.brand.withValues(alpha: 0.5) : cs.outline.withValues(alpha: 0.3)),
      ),
      child: Center(
        child: Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: active ? AppTheme.brand : cs.onSurface.withValues(alpha: 0.25))),
      ),
    );
  }
}

// ── Axis Lock Toggle Button ───────────────────────────────────────
class _AxisLockButton extends StatelessWidget {
  final _AxisLock current;
  final ValueChanged<_AxisLock> onToggle;
  const _AxisLockButton({required this.current, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      _LockChip(label: 'X锁', active: current == _AxisLock.xOnly, cs: cs,
          onTap: () => onToggle(current == _AxisLock.xOnly ? _AxisLock.none : _AxisLock.xOnly)),
      const SizedBox(width: 3),
      _LockChip(label: 'Y锁', active: current == _AxisLock.yOnly, cs: cs,
          onTap: () => onToggle(current == _AxisLock.yOnly ? _AxisLock.none : _AxisLock.yOnly)),
    ]);
  }
}

class _LockChip extends StatelessWidget {
  final String label;
  final bool active;
  final ColorScheme cs;
  final VoidCallback onTap;
  const _LockChip({required this.label, required this.active, required this.cs, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: active ? AppTheme.orange.withValues(alpha: 0.15) : cs.onSurface.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: active ? AppTheme.orange.withValues(alpha: 0.5) : cs.outline.withValues(alpha: 0.2)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(active ? Icons.lock_rounded : Icons.lock_open_rounded, size: 9,
              color: active ? AppTheme.orange : cs.onSurface.withValues(alpha: 0.25)),
          const SizedBox(width: 3),
          Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600,
              color: active ? AppTheme.orange : cs.onSurface.withValues(alpha: 0.3))),
        ]),
      ),
    );
  }
}
