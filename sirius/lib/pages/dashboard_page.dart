import 'dart:async';

import 'package:flutter/material.dart';
import '../services/device_registry.dart';
import '../services/grpc_service.dart';
import '../services/lan_scanner.dart';
import '../theme/app_theme.dart';
import '../utils/app_toast.dart';
import '../utils/validators.dart';
import '../widgets/joystick_pad.dart';

class DashboardPage extends StatefulWidget {
  final GrpcService grpc;
  final DeviceRegistry registry;
  final ValueNotifier<WalkSpeed>? speedNotifier;
  final ValueNotifier<Set<String>>? keysNotifier;
  const DashboardPage({super.key, required this.grpc, required this.registry, this.speedNotifier, this.keysNotifier});
  @override State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final _hC = TextEditingController(text: '192.168.66.192');
  final _pC = TextEditingController(text: '13145');
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _hC.text = widget.grpc.host;
    _pC.text = widget.grpc.port.toString();
    // Restore last connected address if not already connected
    if (!widget.grpc.connected) {
      GrpcService.loadLastConnected().then((saved) {
        if (saved != null && mounted) {
          setState(() {
            _hC.text = saved.host;
            _pC.text = saved.port.toString();
          });
        }
      });
    }
  }

  @override void dispose() { _hC.dispose(); _pC.dispose(); super.dispose(); }

  static Color _dotColor(GrpcService g, ColorScheme cs) {
    if (g.isReconnecting || (g.connected && g.isStale)) return AppTheme.orange;
    if (g.connected) return AppTheme.green;
    return cs.onSurface.withValues(alpha: 0.12);
  }

  Future<void> _connect() async {
    final host = _hC.text.trim();
    final portStr = _pC.text.trim();

    // Validate IP address
    if (!Validators.isValidIP(host)) {
      AppToast.showError(context, 'IP 地址格式错误');
      return;
    }

    // Validate port
    if (!Validators.isValidPort(portStr)) {
      AppToast.showError(context, '端口号必须在 1-65535 之间');
      return;
    }

    setState(() => _busy = true);
    await widget.grpc.connect(host, int.parse(portStr));
    if (!mounted) return;
    setState(() => _busy = false);
    if (widget.grpc.connected) {
      AppToast.showSuccess(context, '已连接 ${widget.grpc.host}:${widget.grpc.port}');
    } else if (widget.grpc.error != null) {
      AppToast.showError(context, '连接失败: ${widget.grpc.error}');
    }
  }

  void _showScanSheet(BuildContext ctx) {
    final port = int.tryParse(_pC.text.trim()) ?? 13145;
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _LanScanSheet(
        port: port,
        registry: widget.registry,
        onSelect: (ip) {
          _hC.text = ip;
          Navigator.of(ctx).pop();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.grpc;
    final cs = Theme.of(context).colorScheme;
    const gap = SizedBox(height: 14);
    const hg = SizedBox(width: 14);

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(children: [
        Row(children: [
          Text('仪表盘', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: cs.onSurface, letterSpacing: -0.5)),
          const Spacer(),
          _connBar(context, g),
        ]),
        _AlarmStrip(grpc: g),
        // Onboarding guide — fixed at top, only when disconnected
        if (!g.connected && !g.isReconnecting) ...[gap, const _OnboardingGuide()],
        gap,
        Expanded(child: SingleChildScrollView(child: Column(children: [
          // Walk control (joystick)
          JoystickPanel(grpc: g, speedNotifier: widget.speedNotifier, keysNotifier: widget.keysNotifier),
          gap,
          // 4 stat cards
          Row(children: [
            Expanded(child: _StatCard(icon: Icons.memory_rounded, label: '状态', value: g.cmsState)),
            hg, Expanded(child: _StatCard(icon: Icons.speed_rounded, label: '推理频率', value: g.historyHz.toStringAsFixed(1), unit: 'Hz')),
            hg, Expanded(child: _StatCard(icon: Icons.explore_rounded, label: 'IMU 频率', value: g.imuHz.toStringAsFixed(1), unit: 'Hz')),
            hg, Expanded(child: _StatCard(icon: Icons.precision_manufacturing_rounded, label: '关节频率', value: g.jointHz.toStringAsFixed(1), unit: 'Hz')),
          ]),
          gap,
          // Device identity card (only when connected)
          if (g.connected) ...[_DeviceInfoCard(grpc: g), gap],
          // State bar + Actions + System badge (single compact row)
          _controlRow(context, g),
          gap,
          // Quick params panel (collapsible, only when connected)
          if (g.connected) ...[_QuickParamsPanel(grpc: g), gap],
          // 4 leg cards
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: _LegCard(grpc: g, leg: 'FR', indices: const [0, 1, 2, 12])),
            hg, Expanded(child: _LegCard(grpc: g, leg: 'FL', indices: const [3, 4, 5, 13])),
          ]),
          gap,
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: _LegCard(grpc: g, leg: 'RR', indices: const [6, 7, 8, 14])),
            hg, Expanded(child: _LegCard(grpc: g, leg: 'RL', indices: const [9, 10, 11, 15])),
          ]),
          const SizedBox(height: 20),
        ]))),
      ]),
    );
  }

  // ── Connection bar ──
  Widget _connBar(BuildContext c, GrpcService g) {
    final cs = Theme.of(c).colorScheme;
    final dotColor = _dotColor(g, cs);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: cs.outline.withValues(alpha: 0.5)), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8)]),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(width: 8),
        Container(width: 7, height: 7, decoration: BoxDecoration(shape: BoxShape.circle, color: dotColor)),
        const SizedBox(width: 4),
        // Health status label
        if (g.isReconnecting || (g.connected && g.isStale))
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Text(
              g.healthStatus,
              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: AppTheme.orange),
            ),
          ),
        const SizedBox(width: 4),
        SizedBox(width: 120, child: _inp(c, _hC, 'IP', !g.connected && !g.isReconnecting)),
        const SizedBox(width: 5),
        SizedBox(width: 56, child: _inp(c, _pC, 'Port', !g.connected && !g.isReconnecting)),
        const SizedBox(width: 4),
        if (!g.connected && !g.isReconnecting)
          _ScanBtn(onTap: () => _showScanSheet(c)),
        const SizedBox(width: 2),
        _FavBtn(
          grpc: g,
          registry: widget.registry,
          currentIp: _hC.text.trim(),
          currentPort: int.tryParse(_pC.text.trim()) ?? 13145,
          onSelect: (ip, port) {
            setState(() { _hC.text = ip; _pC.text = port.toString(); });
          },
        ),
        const SizedBox(width: 5),
        _ConnBtn(
          label: g.connected ? '断开' : (g.isReconnecting ? '取消' : '连接'),
          filled: !g.connected && !g.isReconnecting,
          onTap: g.connected
              ? () { widget.grpc.disconnect(); AppToast.showSuccess(context, '已断开'); }
              : g.isReconnecting
                  ? () { widget.grpc.disconnect(); AppToast.showSuccess(context, '已取消重连'); }
                  : (_busy ? null : _connect),
        ),
      ]),
    );
  }

  Widget _inp(BuildContext c, TextEditingController ctrl, String h, bool on) {
    final cs = Theme.of(c).colorScheme;
    return TextField(controller: ctrl, enabled: on, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: cs.onSurface), decoration: InputDecoration(hintText: h, hintStyle: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.2)), isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6), filled: true, fillColor: cs.onSurface.withValues(alpha: 0.03), border: OutlineInputBorder(borderRadius: BorderRadius.circular(7), borderSide: BorderSide.none), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(7), borderSide: BorderSide.none), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(7), borderSide: BorderSide(color: AppTheme.brand.withValues(alpha: 0.3)))));
  }

  // ── Control Row: State pills + Action buttons + System badge ──
  Widget _controlRow(BuildContext c, GrpcService g) {
    final cs = Theme.of(c).colorScheme;
    final state = g.cmsState;
    // 5 CMS states matching han_dog_brain S class: Zero->Grounded, StandUp(transitioning), Standing, Walking, SitDown(transitioning)
    const states = ['Grounded', 'StandUp', 'Standing', 'Walking', 'SitDown'];
    const stateLabels = ['待机', '起立', '站立', '行走', '坐下'];
    const stateIcons = [Icons.pause_circle_outlined, Icons.publish_rounded, Icons.accessibility_new_rounded, Icons.directions_walk_rounded, Icons.get_app_rounded];
    Color sc(String s) { switch (s) { case 'Walking': return AppTheme.brand; case 'StandUp': return AppTheme.green; case 'Standing': return AppTheme.brand; case 'SitDown': return AppTheme.orange; case 'Grounded': return cs.onSurface.withValues(alpha: 0.3); default: return AppTheme.red; } }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: cs.outline.withValues(alpha: 0.5)), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8)]),
      child: Row(children: [
        // State pills
        ...List.generate(states.length, (i) {
          final active = states[i] == state;
          return Padding(padding: const EdgeInsets.only(right: 6), child: Container(
            padding: EdgeInsets.symmetric(horizontal: active ? 14 : 10, vertical: 6),
            decoration: BoxDecoration(
              color: active ? sc(states[i]) : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(stateIcons[i], size: 14, color: active ? Colors.white : cs.onSurface.withValues(alpha: 0.2)),
              const SizedBox(width: 5),
              Text(stateLabels[i], style: TextStyle(fontSize: 11, fontWeight: active ? FontWeight.w600 : FontWeight.w400, color: active ? Colors.white : cs.onSurface.withValues(alpha: 0.25))),
            ]),
          ));
        }),

        const Spacer(),

        // Action buttons
        _ActBtn(label: '使能', icon: Icons.power_settings_new_rounded, color: AppTheme.green, onTap: g.connected ? g.enable : null),
        const SizedBox(width: 6),
        _ActBtn(label: '禁用', icon: Icons.block_rounded, color: AppTheme.red, onTap: g.connected ? g.disable : null),
        const SizedBox(width: 6),
        _ActBtn(label: '站立', icon: Icons.arrow_upward_rounded, color: AppTheme.teal, onTap: g.connected ? g.standUp : null),
        const SizedBox(width: 6),
        _ActBtn(label: '坐下', icon: Icons.arrow_downward_rounded, color: AppTheme.orange, onTap: g.connected ? g.sitDown : null),

        const SizedBox(width: 14),

        // System badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(color: cs.onSurface.withValues(alpha: 0.03), borderRadius: BorderRadius.circular(10)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text('系统', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: cs.onSurface.withValues(alpha: 0.3), letterSpacing: 0.5)),
            const SizedBox(width: 8),
            Text(g.params != null && g.params!.hasRobot() ? g.params!.robot.type.name : '--', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: cs.onSurface)),
            const SizedBox(width: 8),
            Icon(Icons.smart_toy_rounded, size: 14, color: cs.onSurface.withValues(alpha: 0.3)),
          ]),
        ),
      ]),
    );
  }

}

// ══════════════════════════════════════
// Hover Card wrapper (lift + shadow on hover)
// ══════════════════════════════════════
class _HoverCard extends StatefulWidget {
  final Widget child;
  const _HoverCard({required this.child});
  @override State<_HoverCard> createState() => _HoverCardState();
}
class _HoverCardState extends State<_HoverCard> {
  bool _hov = false;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return MouseRegion(
      onEnter: (_) => setState(() => _hov = true),
      onExit: (_) => setState(() => _hov = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        transform: _hov ? Matrix4.translationValues(0.0, -2.0, 0.0) : Matrix4.identity(),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _hov ? AppTheme.brand.withValues(alpha: 0.2) : cs.outline.withValues(alpha: 0.5)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: _hov ? 0.08 : 0.03), blurRadius: _hov ? 20 : 8, offset: Offset(0, _hov ? 8 : 2))],
        ),
        clipBehavior: Clip.antiAlias,
        child: widget.child,
      ),
    );
  }
}

// ══════════════════════════════════════
// Stat Card with hover
// ══════════════════════════════════════
class _StatCard extends StatefulWidget {
  final IconData icon; final String label; final String value; final String? unit;
  const _StatCard({required this.icon, required this.label, required this.value, this.unit});
  @override State<_StatCard> createState() => _StatCardState();
}
class _StatCardState extends State<_StatCard> {
  bool _hov = false;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return MouseRegion(
      onEnter: (_) => setState(() => _hov = true),
      onExit: (_) => setState(() => _hov = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        transform: _hov ? Matrix4.translationValues(0.0, -2.0, 0.0) : Matrix4.identity(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _hov ? AppTheme.brand.withValues(alpha: 0.3) : cs.outline.withValues(alpha: 0.5)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: _hov ? 0.08 : 0.03), blurRadius: _hov ? 20 : 8, offset: Offset(0, _hov ? 8 : 2))],
        ),
        child: Row(children: [
          Container(width: 40, height: 40, decoration: BoxDecoration(color: cs.onSurface.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(12)), child: Icon(widget.icon, size: 20, color: cs.onSurface.withValues(alpha: 0.5))),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(widget.label, style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.5))),
            const SizedBox(height: 2),
            Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
              Flexible(child: Text(widget.value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: cs.onSurface, fontFeatures: const [FontFeature.tabularFigures()]), overflow: TextOverflow.ellipsis)),
              if (widget.unit != null) Text(' ${widget.unit}', style: TextStyle(fontSize: 10, color: cs.onSurface.withValues(alpha: 0.25))),
            ]),
          ])),
        ]),
      ),
    );
  }
}

// ══════════════════════════════════════
// Leg Card with hover
// ══════════════════════════════════════
class _LegCard extends StatefulWidget {
  final GrpcService grpc; final String leg; final List<int> indices;
  const _LegCard({required this.grpc, required this.leg, required this.indices});
  @override State<_LegCard> createState() => _LegCardState();
}
class _LegCardState extends State<_LegCard> {
  bool _hov = false;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final j = widget.grpc.latestJoints;
    const joints = ['髋', '大腿', '小腿', '足'];
    final legNames = {'FR': '前右', 'FL': '前左', 'RR': '后右', 'RL': '后左'};

    return MouseRegion(
      onEnter: (_) => setState(() => _hov = true),
      onExit: (_) => setState(() => _hov = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        transform: _hov ? Matrix4.translationValues(0.0, -2.0, 0.0) : Matrix4.identity(),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _hov ? AppTheme.brand.withValues(alpha: 0.3) : cs.outline.withValues(alpha: 0.5)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: _hov ? 0.08 : 0.03), blurRadius: _hov ? 20 : 8, offset: Offset(0, _hov ? 8 : 2))],
        ),
        child: Row(children: [
          Container(width: 4, color: cs.onSurface.withValues(alpha: 0.12)),
          Expanded(child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('${widget.leg} 腿', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: cs.onSurface)),
            const SizedBox(width: 6),
            Text(legNames[widget.leg] ?? '', style: TextStyle(fontSize: 9, color: cs.onSurface.withValues(alpha: 0.3))),
            const Spacer(),
            Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: cs.onSurface.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(4)), child: Text(widget.grpc.connected ? '激活' : '待机', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w600, color: cs.onSurface.withValues(alpha: 0.5)))),
          ]),
          const SizedBox(height: 4),
          Divider(color: cs.onSurface.withValues(alpha: 0.04), height: 8),
          Row(children: [
            SizedBox(width: 50, child: Text('关节', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: cs.onSurface.withValues(alpha: 0.2), letterSpacing: 0.5))),
            Expanded(child: Text('位置', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: cs.onSurface.withValues(alpha: 0.2), letterSpacing: 0.5), textAlign: TextAlign.center)),
            Expanded(child: Text('速度', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: cs.onSurface.withValues(alpha: 0.2), letterSpacing: 0.5), textAlign: TextAlign.center)),
            Expanded(child: Text('力矩', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: cs.onSurface.withValues(alpha: 0.2), letterSpacing: 0.5), textAlign: TextAlign.center)),
            const SizedBox(width: 40),
          ]),
          const SizedBox(height: 4),
          ...List.generate(4, (ji) {
            final idx = widget.indices[ji];
            final pos = j != null && j.position.values.length > idx ? j.position.values[idx] : 0.0;
            final vel = j != null && j.velocity.values.length > idx ? j.velocity.values[idx] : 0.0;
            final trq = j != null && j.torque.values.length > idx ? j.torque.values[idx] : 0.0;
            return Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(children: [
              SizedBox(width: 50, child: Text(joints[ji], style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: cs.onSurface))),
              Expanded(child: Text(pos.toStringAsFixed(2), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: cs.onSurface, fontFeatures: const [FontFeature.tabularFigures()]), textAlign: TextAlign.center)),
              Expanded(child: Text(vel.toStringAsFixed(1), style: TextStyle(fontSize: 10, color: cs.onSurface.withValues(alpha: 0.5), fontFeatures: const [FontFeature.tabularFigures()]), textAlign: TextAlign.center)),
              Expanded(child: Text(trq.toStringAsFixed(1), style: TextStyle(fontSize: 10, color: trq.abs() > 5 ? AppTheme.red : cs.onSurface.withValues(alpha: 0.5), fontWeight: trq.abs() > 5 ? FontWeight.w600 : FontWeight.w400, fontFeatures: const [FontFeature.tabularFigures()]), textAlign: TextAlign.center)),
              SizedBox(width: 40, child: ClipRRect(borderRadius: BorderRadius.circular(2), child: LinearProgressIndicator(value: (trq.abs() / 10.0).clamp(0.0, 1.0), minHeight: 6, backgroundColor: cs.onSurface.withValues(alpha: 0.04), valueColor: AlwaysStoppedAnimation(trq.abs() > 5 ? AppTheme.red : cs.onSurface.withValues(alpha: 0.3))))),
            ]));
          }),
        ]),
          )),
        ]),
      ),
    );
  }
}

// ══════════════════════════════════════
// Action Button with hover + press
// ══════════════════════════════════════
class _ActBtn extends StatefulWidget {
  final String label; final IconData icon; final Color color; final VoidCallback? onTap;
  const _ActBtn({required this.label, required this.icon, required this.color, this.onTap});
  @override State<_ActBtn> createState() => _ActBtnState();
}
class _ActBtnState extends State<_ActBtn> {
  bool _hov = false; bool _press = false;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final on = widget.onTap != null;
    return MouseRegion(
      onEnter: on ? (_) => setState(() => _hov = true) : null,
      onExit: on ? (_) => setState(() => _hov = false) : null,
      child: GestureDetector(
        onTapDown: on ? (_) => setState(() => _press = true) : null,
        onTapUp: on ? (_) => setState(() => _press = false) : null,
        onTapCancel: on ? () => setState(() => _press = false) : null,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          transform: _press ? Matrix4.diagonal3Values(0.95, 0.95, 1.0) : Matrix4.identity(),
          transformAlignment: Alignment.center,
          decoration: BoxDecoration(
            color: _hov ? widget.color.withValues(alpha: 0.08) : cs.onSurface.withValues(alpha: 0.02),
            borderRadius: BorderRadius.circular(20),
            border: _hov ? Border.all(color: widget.color.withValues(alpha: 0.2)) : null,
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(widget.icon, size: 14, color: on ? (_hov ? widget.color : cs.onSurface.withValues(alpha: 0.4)) : cs.onSurface.withValues(alpha: 0.1)),
            const SizedBox(width: 5),
            Text(widget.label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: on ? (_hov ? widget.color : cs.onSurface.withValues(alpha: 0.5)) : cs.onSurface.withValues(alpha: 0.15))),
          ]),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════
// Quick Params Panel (collapsible Kp/Kd tuner)
// ══════════════════════════════════════
class _QuickParamsPanel extends StatefulWidget {
  final GrpcService grpc;
  const _QuickParamsPanel({required this.grpc});
  @override State<_QuickParamsPanel> createState() => _QuickParamsPanelState();
}

class _QuickParamsPanelState extends State<_QuickParamsPanel> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final p = widget.grpc.params;

    // Build key param summary strings (read from server params)
    final items = <(String, String)>[];
    if (p != null) {
      if (p.hasRobot()) {
        items.add(('型号', p.robot.type.name));
        final pos = p.robot.initialJointPosition.values;
        final vel = p.robot.initialJointVelocity.values;
        if (pos.isNotEmpty) items.add(('初始关节数', '${pos.length} 个'));
        if (vel.isNotEmpty) {
          final avgVel = vel.reduce((a, b) => a + b) / vel.length;
          items.add(('初始均速', avgVel.toStringAsFixed(3)));
        }
      }
      // Session-derived metrics
      items.add(('行走指令', '${widget.grpc.walkCmdCount} 次'));
      if (widget.grpc.maxTorqueEver > 0) {
        items.add(('峰值力矩', '${widget.grpc.maxTorqueEver.toStringAsFixed(1)} Nm'));
      }
      items.add(('推理频率', '${widget.grpc.historyHz.toStringAsFixed(1)} Hz'));
      items.add(('IMU 频率', '${widget.grpc.imuHz.toStringAsFixed(1)} Hz'));
    }

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outline.withValues(alpha: 0.5)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8)],
      ),
      child: Column(children: [
        // Header
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(children: [
              Icon(Icons.tune_rounded, size: 14, color: AppTheme.brand),
              const SizedBox(width: 8),
              Text('当前参数', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.onSurface)),
              const SizedBox(width: 8),
              if (items.isNotEmpty)
                Text('${items.length} 项', style: TextStyle(fontSize: 10, color: cs.onSurface.withValues(alpha: 0.35))),
              const Spacer(),
              Icon(_expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                  size: 18, color: cs.onSurface.withValues(alpha: 0.4)),
            ]),
          ),
        ),
        // Expanded read-only view
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          child: _expanded
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                  child: p == null
                      ? Text('参数未加载', style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.35)))
                      : Wrap(
                          spacing: 10,
                          runSpacing: 8,
                          children: items.map((item) => Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: cs.onSurface.withValues(alpha: 0.04),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Text(item.$1, style: TextStyle(fontSize: 9, color: cs.onSurface.withValues(alpha: 0.4), fontWeight: FontWeight.w600)),
                              const SizedBox(width: 6),
                              Text(item.$2, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: cs.onSurface, fontFeatures: const [FontFeature.tabularFigures()])),
                            ]),
                          )).toList(),
                        ),
                )
              : const SizedBox.shrink(),
        ),
      ]),
    );
  }
}

// ══════════════════════════════════════
// Device Identity Card
// ══════════════════════════════════════
class _DeviceInfoCard extends StatefulWidget {
  final GrpcService grpc;
  const _DeviceInfoCard({required this.grpc});
  @override State<_DeviceInfoCard> createState() => _DeviceInfoCardState();
}

class _DeviceInfoCardState extends State<_DeviceInfoCard> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) { if (mounted) setState(() {}); });
  }

  @override
  void dispose() { _timer?.cancel(); super.dispose(); }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.grpc;
    final cs = Theme.of(context).colorScheme;
    final robotType = (g.params != null && g.params!.hasRobot())
        ? g.params!.robot.type.name
        : '未知型号';
    final serverUp = g.serverStartTime != null
        ? _fmt(DateTime.now().difference(g.serverStartTime!))
        : '--';
    final sessionDur = g.connectTime != null
        ? _fmt(DateTime.now().difference(g.connectTime!))
        : '--';
    final rtt = g.lastRttMs > 0 ? '${g.lastRttMs.toStringAsFixed(0)} ms' : '-- ms';
    final rttColor = g.lastRttMs < 20
        ? AppTheme.green
        : g.lastRttMs < 60
            ? AppTheme.orange
            : AppTheme.red;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outline.withValues(alpha: 0.5)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8)],
      ),
      child: Row(children: [
        // Robot icon + type + address
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: AppTheme.brand.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(Icons.smart_toy_rounded, size: 18, color: AppTheme.brand),
        ),
        const SizedBox(width: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(robotType, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: cs.onSurface)),
          Text('${g.host}:${g.port}', style: TextStyle(fontSize: 10, color: cs.onSurface.withValues(alpha: 0.4))),
        ]),
        const SizedBox(width: 20),
        Container(width: 1, height: 28, color: cs.outline.withValues(alpha: 0.3)),
        const SizedBox(width: 20),
        // Metrics
        _InfoChip(label: '服务运行', value: serverUp),
        const SizedBox(width: 20),
        _InfoChip(label: '本次连接', value: sessionDur),
        const SizedBox(width: 20),
        _InfoChip(label: '延迟', value: rtt, valueColor: rttColor),
        const SizedBox(width: 20),
        Container(width: 1, height: 28, color: cs.outline.withValues(alpha: 0.3)),
        const SizedBox(width: 20),
        // Session statistics
        _InfoChip(
          label: '行走时间',
          value: g.walkActiveMs > 0 ? _fmt(Duration(milliseconds: g.walkActiveMs)) : '--',
        ),
        const SizedBox(width: 20),
        _InfoChip(
          label: '峰值力矩',
          value: g.maxTorqueEver > 0 ? '${g.maxTorqueEver.toStringAsFixed(1)} Nm' : '-- Nm',
          valueColor: g.maxTorqueEver > 8 ? AppTheme.red : g.maxTorqueEver > 5 ? AppTheme.orange : null,
        ),
        const Spacer(),
        // Profile badge (if any)
        if (g.hasProfiles)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.brand.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.psychology_outlined, size: 12, color: AppTheme.brand),
              const SizedBox(width: 4),
              Text(g.currentProfile, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.brand)),
            ]),
          ),
      ]),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  const _InfoChip({required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: cs.onSurface.withValues(alpha: 0.3), letterSpacing: 0.5)),
      const SizedBox(height: 2),
      Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: valueColor ?? cs.onSurface, fontFeatures: const [FontFeature.tabularFigures()])),
    ]);
  }
}

// ══════════════════════════════════════
// Alarm Strip
// ══════════════════════════════════════
const double _torqueWarnNm = 8.0; // Nm threshold for joint torque alarm

class _AlarmStrip extends StatefulWidget {
  final GrpcService grpc;
  const _AlarmStrip({required this.grpc});
  @override
  State<_AlarmStrip> createState() => _AlarmStripState();
}

class _AlarmStripState extends State<_AlarmStrip> {
  final Set<String> _dismissed = {};

  @override
  Widget build(BuildContext context) {
    final g = widget.grpc;
    final alarms = _buildAlarms(g);
    final visible = alarms.where((a) => !_dismissed.contains(a.id)).toList();
    if (visible.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        children: visible.map((a) => _AlarmChip(
          alarm: a,
          onDismiss: () => setState(() => _dismissed.add(a.id)),
        )).toList(),
      ),
    );
  }

  List<_Alarm> _buildAlarms(GrpcService g) {
    final alarms = <_Alarm>[];

    // Stale connection (data stream timeout)
    if (g.connected && g.isStale) {
      alarms.add(const _Alarm(
        id: 'stale',
        level: _AlarmLevel.warning,
        message: '数据流超时：超过 5 秒未收到机器人数据',
        icon: Icons.signal_wifi_statusbar_connected_no_internet_4_rounded,
      ));
    }

    // Reconnecting with many attempts
    if (g.isReconnecting && g.reconnectAttempts >= 3) {
      alarms.add(_Alarm(
        id: 'reconnect',
        level: _AlarmLevel.warning,
        message: '重连中，已尝试 ${g.reconnectAttempts} 次',
        icon: Icons.sync_problem_rounded,
      ));
    }

    // High joint torque
    final joints = g.latestJoints;
    if (joints != null && g.connected) {
      double maxTrq = 0;
      int maxIdx = 0;
      final vals = joints.torque.values;
      for (int i = 0; i < vals.length; i++) {
        if (vals[i].abs() > maxTrq) { maxTrq = vals[i].abs(); maxIdx = i; }
      }
      if (maxTrq > _torqueWarnNm) {
        const legNames = ['前右', '前右', '前右', '前右', '前左', '前左', '前左', '前左',
            '后右', '后右', '后右', '后右', '后左', '后左', '后左', '后左'];
        const jNames = ['髋', '大腿', '小腿', '足', '髋', '大腿', '小腿', '足',
            '髋', '大腿', '小腿', '足', '髋', '大腿', '小腿', '足'];
        alarms.add(_Alarm(
          id: 'torque_$maxIdx',
          level: maxTrq > 12 ? _AlarmLevel.critical : _AlarmLevel.warning,
          message: '关节力矩过高：${legNames[maxIdx]}-${jNames[maxIdx]}  ${maxTrq.toStringAsFixed(1)} Nm',
          icon: Icons.warning_amber_rounded,
        ));
      }
    }

    return alarms;
  }
}

enum _AlarmLevel { warning, critical }

class _Alarm {
  final String id;
  final _AlarmLevel level;
  final String message;
  final IconData icon;
  const _Alarm({required this.id, required this.level, required this.message, required this.icon});
}

class _AlarmChip extends StatelessWidget {
  final _Alarm alarm;
  final VoidCallback onDismiss;
  const _AlarmChip({required this.alarm, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final isCritical = alarm.level == _AlarmLevel.critical;
    final color = isCritical ? AppTheme.red : AppTheme.orange;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(children: [
          Icon(alarm.icon, size: 14, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(alarm.message,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: color)),
          ),
          GestureDetector(
            onTap: onDismiss,
            child: Icon(Icons.close_rounded, size: 14,
                color: color.withValues(alpha: 0.6)),
          ),
        ]),
      ),
    );
  }
}

// ══════════════════════════════════════
// Favourites Button
// ══════════════════════════════════════
class _FavBtn extends StatefulWidget {
  final GrpcService grpc;
  final DeviceRegistry registry;
  final String currentIp;
  final int currentPort;
  final void Function(String ip, int port) onSelect;

  const _FavBtn({
    required this.grpc,
    required this.registry,
    required this.currentIp,
    required this.currentPort,
    required this.onSelect,
  });

  @override
  State<_FavBtn> createState() => _FavBtnState();
}

class _FavBtnState extends State<_FavBtn> {
  bool _hov = false;

  bool get _isSaved =>
      widget.registry.isSaved(widget.currentIp, widget.currentPort);

  void _toggle(BuildContext ctx) {
    if (_isSaved) {
      widget.registry.remove(widget.currentIp, widget.currentPort);
    } else {
      _showSaveDialog(ctx);
    }
  }

  void _showSaveDialog(BuildContext ctx) {
    final nameCtrl = TextEditingController(text: widget.currentIp);
    showDialog(
      context: ctx,
      builder: (dCtx) => AlertDialog(
        title: const Text('保存设备', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${widget.currentIp}:${widget.currentPort}',
              style: TextStyle(fontSize: 11, color: Theme.of(dCtx).colorScheme.onSurface.withValues(alpha: 0.5))),
          const SizedBox(height: 12),
          TextField(
            controller: nameCtrl,
            autofocus: true,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              labelText: '设备名称',
              hintText: '例如：实验室机器人',
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              widget.registry.save(DeviceInfo(
                name: nameCtrl.text.trim().isEmpty ? widget.currentIp : nameCtrl.text.trim(),
                ip: widget.currentIp,
                port: widget.currentPort,
                lastConnected: widget.grpc.connected ? DateTime.now() : null,
              ));
              Navigator.pop(dCtx);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _showList(BuildContext ctx) {
    final devices = widget.registry.devices;
    if (devices.isEmpty) {
      _showSaveDialog(ctx);
      return;
    }
    showDialog(
      context: ctx,
      builder: (dCtx) => _FavListDialog(
        registry: widget.registry,
        currentIp: widget.currentIp,
        currentPort: widget.currentPort,
        grpc: widget.grpc,
        onSelect: widget.onSelect,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final saved = _isSaved;
    return MouseRegion(
      onEnter: (_) => setState(() => _hov = true),
      onExit: (_) => setState(() => _hov = false),
      child: GestureDetector(
        onTap: () {
          if (widget.registry.devices.isEmpty || !saved) {
            // If nothing saved or current not saved: show save/list
            _showList(context);
          } else {
            _toggle(context);
          }
        },
        onSecondaryTap: () => _showList(context), // right-click always shows list
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: saved
                ? AppTheme.brand.withValues(alpha: 0.08)
                : (_hov ? cs.onSurface.withValues(alpha: 0.05) : Colors.transparent),
            borderRadius: BorderRadius.circular(8),
            border: saved ? Border.all(color: AppTheme.brand.withValues(alpha: 0.2)) : null,
          ),
          child: Icon(
            saved ? Icons.star_rounded : Icons.star_outline_rounded,
            size: 16,
            color: saved ? AppTheme.brand : cs.onSurface.withValues(alpha: 0.35),
          ),
        ),
      ),
    );
  }
}

class _FavListDialog extends StatefulWidget {
  final DeviceRegistry registry;
  final String currentIp;
  final int currentPort;
  final GrpcService grpc;
  final void Function(String ip, int port) onSelect;
  const _FavListDialog({
    required this.registry,
    required this.currentIp,
    required this.currentPort,
    required this.grpc,
    required this.onSelect,
  });
  @override
  State<_FavListDialog> createState() => _FavListDialogState();
}

class _FavListDialogState extends State<_FavListDialog> {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final devices = widget.registry.devices;

    return AlertDialog(
      title: Row(children: [
        const Text('收藏设备', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        const Spacer(),
        // Add current
        if (widget.grpc.connected &&
            !widget.registry.isSaved(widget.currentIp, widget.currentPort))
          TextButton.icon(
            onPressed: () {
              Navigator.pop(context);
              final nameCtrl = TextEditingController(text: widget.currentIp);
              showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('保存当前设备', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  content: TextField(
                    controller: nameCtrl,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: '设备名称',
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
                    FilledButton(
                      onPressed: () {
                        widget.registry.save(DeviceInfo(
                          name: nameCtrl.text.trim().isEmpty ? widget.currentIp : nameCtrl.text.trim(),
                          ip: widget.currentIp,
                          port: widget.currentPort,
                          lastConnected: DateTime.now(),
                        ));
                        Navigator.pop(context);
                        setState(() {});
                      },
                      child: const Text('保存'),
                    ),
                  ],
                ),
              );
            },
            icon: const Icon(Icons.add_rounded, size: 14),
            label: const Text('保存当前', style: TextStyle(fontSize: 11)),
            style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
          ),
      ]),
      contentPadding: const EdgeInsets.fromLTRB(0, 8, 0, 0),
      content: SizedBox(
        width: 340,
        child: devices.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Text('暂无收藏设备',
                      style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.35))),
                ),
              )
            : ListView.builder(
                shrinkWrap: true,
                itemCount: devices.length,
                itemBuilder: (_, i) {
                  final d = devices[i];
                  final isCurrent = d.ip == widget.currentIp && d.port == widget.currentPort;
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
                    leading: Icon(
                      Icons.smart_toy_outlined,
                      size: 20,
                      color: isCurrent ? AppTheme.brand : cs.onSurface.withValues(alpha: 0.4),
                    ),
                    title: Text(d.name,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
                          color: isCurrent ? AppTheme.brand : cs.onSurface,
                        )),
                    subtitle: Text(
                      d.lastConnected != null
                          ? '${d.addressLabel}  ·  ${_ago(d.lastConnected!)}'
                          : d.addressLabel,
                      style: TextStyle(fontSize: 10, color: cs.onSurface.withValues(alpha: 0.4)),
                    ),
                    trailing: IconButton(
                      icon: Icon(Icons.delete_outline_rounded, size: 16,
                          color: cs.onSurface.withValues(alpha: 0.3)),
                      onPressed: () {
                        widget.registry.remove(d.ip, d.port);
                        setState(() {});
                      },
                    ),
                    onTap: () {
                      widget.onSelect(d.ip, d.port);
                      Navigator.pop(context);
                    },
                  );
                },
              ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭')),
      ],
    );
  }

  String _ago(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes}分钟前';
    if (diff.inDays < 1) return '${diff.inHours}小时前';
    return '${diff.inDays}天前';
  }
}

// ══════════════════════════════════════
// Scan Button (wifi search icon)
// ══════════════════════════════════════
class _ScanBtn extends StatefulWidget {
  final VoidCallback onTap;
  const _ScanBtn({required this.onTap});
  @override
  State<_ScanBtn> createState() => _ScanBtnState();
}

class _ScanBtnState extends State<_ScanBtn> {
  bool _hov = false;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return MouseRegion(
      onEnter: (_) => setState(() => _hov = true),
      onExit: (_) => setState(() => _hov = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: _hov ? AppTheme.brand.withValues(alpha: 0.08) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: _hov ? Border.all(color: AppTheme.brand.withValues(alpha: 0.2)) : null,
          ),
          child: Icon(Icons.wifi_find_rounded, size: 16,
              color: _hov ? AppTheme.brand : cs.onSurface.withValues(alpha: 0.35)),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════
// LAN Scan Bottom Sheet
// ══════════════════════════════════════
class _LanScanSheet extends StatefulWidget {
  final int port;
  final DeviceRegistry registry;
  final void Function(String ip) onSelect;
  const _LanScanSheet({required this.port, required this.registry, required this.onSelect});
  @override
  State<_LanScanSheet> createState() => _LanScanSheetState();
}

class _LanScanSheetState extends State<_LanScanSheet> {
  List<String> _subnets = [];
  String? _activeSubnet;
  final List<LanScanResult> _results = [];
  int _scanned = 0;
  bool _done = false;
  bool _cancelled = false;
  StreamSubscription<LanScanResult>? _sub;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final subnets = await LanScanner.localSubnets();
    if (!mounted) return;
    setState(() => _subnets = subnets);
    if (subnets.isNotEmpty) _startScan(subnets.first);
  }

  void _startScan(String subnet) {
    _sub?.cancel();
    setState(() {
      _activeSubnet = subnet;
      _results.clear();
      _scanned = 0;
      _done = false;
      _cancelled = false;
    });
    _sub = LanScanner.scan(subnet, widget.port, onProgress: (s, t) {
      if (mounted) setState(() => _scanned = s);
    }).listen(
      (r) { if (mounted) setState(() => _results.add(r)); },
      onDone: () { if (mounted) setState(() => _done = true); },
    );
  }

  void _cancel() {
    _sub?.cancel();
    setState(() { _cancelled = true; _done = true; });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final total = 254;
    final progress = _scanned / total;

    return Container(
      height: MediaQuery.of(context).size.height * 0.55,
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(color: cs.outline.withValues(alpha: 0.3)),
      ),
      child: Column(children: [
        // Handle
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Container(width: 36, height: 4,
              decoration: BoxDecoration(color: cs.onSurface.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(2))),
        ),
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
          child: Row(children: [
            Icon(Icons.wifi_find_rounded, size: 18, color: AppTheme.brand),
            const SizedBox(width: 8),
            Text('扫描局域网', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: cs.onSurface)),
            const Spacer(),
            if (_subnets.length > 1)
              DropdownButton<String>(
                value: _activeSubnet,
                underline: const SizedBox(),
                style: TextStyle(fontSize: 11, color: cs.onSurface),
                items: _subnets.map((s) => DropdownMenuItem(value: s, child: Text('${s}x'))).toList(),
                onChanged: (s) { if (s != null) _startScan(s); },
              ),
          ]),
        ),
        // Subnet + progress
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Row(children: [
            Text(
              _activeSubnet != null ? '${_activeSubnet}x : ${widget.port}' : '获取网络接口...',
              style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.45)),
            ),
            const Spacer(),
            Text(
              _done ? (_cancelled ? '已取消' : '完成，共 ${_results.length} 台') : '$_scanned / $total',
              style: TextStyle(fontSize: 11, color: _done ? cs.onSurface.withValues(alpha: 0.45) : AppTheme.brand),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: _done ? 1.0 : progress,
              minHeight: 4,
              backgroundColor: cs.onSurface.withValues(alpha: 0.06),
              valueColor: AlwaysStoppedAnimation(_done ? cs.onSurface.withValues(alpha: 0.2) : AppTheme.brand),
            ),
          ),
        ),
        const SizedBox(height: 10),
        // Results
        Expanded(
          child: _results.isEmpty
              ? Center(
                  child: Text(
                    _done ? '未发现设备' : '扫描中...',
                    style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.3)),
                  ),
                )
              : Builder(builder: (_) {
                  // Sort: robot+saved first, then saved-only, then rest
                  final reg = widget.registry;
                  final sorted = [..._results]..sort((a, b) {
                    int score(LanScanResult r) {
                      final saved = reg.isSaved(r.ip, widget.port);
                      if (r.isRobot && saved) return 0;
                      if (r.isRobot) return 1;
                      if (saved) return 2;
                      return 3;
                    }
                    return score(a).compareTo(score(b));
                  });
                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: sorted.length,
                    itemBuilder: (_, i) {
                      final r = sorted[i];
                      final saved = reg.devices.where((d) => d.ip == r.ip && d.port == widget.port).firstOrNull;
                      return _LanScanResultTile(
                        result: r,
                        savedName: saved?.name,
                        onConnect: () => widget.onSelect(r.ip),
                      );
                    },
                  );
                }),
        ),
        // Footer buttons
        Padding(
          padding: EdgeInsets.fromLTRB(20, 8, 20, MediaQuery.of(context).viewPadding.bottom + 16),
          child: Row(children: [
            if (!_done)
              TextButton.icon(
                onPressed: _cancel,
                icon: const Icon(Icons.stop_rounded, size: 14),
                label: const Text('停止', style: TextStyle(fontSize: 12)),
              ),
            if (_done && !_cancelled && _activeSubnet != null)
              TextButton.icon(
                onPressed: () => _startScan(_activeSubnet!),
                icon: const Icon(Icons.refresh_rounded, size: 14),
                label: const Text('重新扫描', style: TextStyle(fontSize: 12)),
              ),
            const Spacer(),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭', style: TextStyle(fontSize: 12)),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _LanScanResultTile extends StatelessWidget {
  final LanScanResult result;
  final String? savedName;
  final VoidCallback onConnect;
  const _LanScanResultTile({required this.result, this.savedName, required this.onConnect});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final r = result;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: r.isRobot ? AppTheme.brand.withValues(alpha: 0.04) : cs.onSurface.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: r.isRobot ? AppTheme.brand.withValues(alpha: 0.2) : cs.outline.withValues(alpha: 0.3),
        ),
      ),
      child: Row(children: [
        // Dot
        Container(
          width: 8, height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: r.isRobot ? AppTheme.brand : cs.onSurface.withValues(alpha: 0.25),
          ),
        ),
        const SizedBox(width: 10),
        // IP + hostname + saved name
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(r.ip, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurface,
                fontFeatures: const [FontFeature.tabularFigures()])),
            if (savedName != null) ...[
              const SizedBox(width: 5),
              Icon(Icons.star_rounded, size: 11, color: Colors.amber.shade600),
            ],
          ]),
          if (savedName != null) ...[
            const SizedBox(height: 1),
            Text(savedName!, style: TextStyle(fontSize: 10, color: Colors.amber.shade700, fontWeight: FontWeight.w500)),
          ] else if (r.hostname != r.ip) ...[
            const SizedBox(height: 2),
            Text(r.hostname, style: TextStyle(fontSize: 10, color: cs.onSurface.withValues(alpha: 0.45))),
          ],
        ])),
        // Badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: (r.isRobot ? AppTheme.brand : cs.onSurface).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Text(
            r.isRobot ? '机器人' : 'TCP',
            style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600,
                color: r.isRobot ? AppTheme.brand : cs.onSurface.withValues(alpha: 0.4)),
          ),
        ),
        const SizedBox(width: 8),
        // Connect button
        TextButton(
          onPressed: onConnect,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            backgroundColor: AppTheme.brand.withValues(alpha: 0.08),
            foregroundColor: AppTheme.brand,
          ),
          child: const Text('连接', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }
}

// ══════════════════════════════════════
// Connect Button with hover + press
// ══════════════════════════════════════
class _ConnBtn extends StatefulWidget {
  final String label; final bool filled; final VoidCallback? onTap;
  const _ConnBtn({required this.label, this.filled = true, this.onTap});
  @override State<_ConnBtn> createState() => _ConnBtnState();
}
class _ConnBtnState extends State<_ConnBtn> {
  bool _hov = false; bool _press = false;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final on = widget.onTap != null;
    return MouseRegion(
      onEnter: on ? (_) => setState(() => _hov = true) : null,
      onExit: on ? (_) => setState(() => _hov = false) : null,
      child: GestureDetector(
        onTapDown: on ? (_) => setState(() => _press = true) : null,
        onTapUp: on ? (_) => setState(() => _press = false) : null,
        onTapCancel: on ? () => setState(() => _press = false) : null,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          transform: _press ? Matrix4.diagonal3Values(0.95, 0.95, 1.0) : Matrix4.identity(),
          transformAlignment: Alignment.center,
          decoration: BoxDecoration(
            color: widget.filled ? (_hov ? AppTheme.brand.withValues(alpha: 0.85) : AppTheme.brand) : (_hov ? cs.onSurface.withValues(alpha: 0.06) : cs.onSurface.withValues(alpha: 0.03)),
            borderRadius: BorderRadius.circular(8),
            boxShadow: widget.filled ? [BoxShadow(color: AppTheme.brand.withValues(alpha: _hov ? 0.35 : 0.2), blurRadius: _hov ? 10 : 6, offset: const Offset(0, 2))] : [],
          ),
          child: Text(widget.label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: widget.filled ? Colors.white : cs.onSurface.withValues(alpha: 0.5))),
        ),
      ),
    );
  }
}

// ── Onboarding Guide Card ─────────────────────────────────────────────────────
class _OnboardingGuide extends StatelessWidget {
  const _OnboardingGuide();

  static const _steps = [
    (Icons.wifi_rounded,         '连接机器人',   '在上方输入 IP 和端口，点击「连接」'),
    (Icons.monitor_heart_rounded,'实时监控',     '连接后可在「监控」页查看关节数据与日志'),
    (Icons.gamepad_rounded,      '遥控操作',     '「控制」页提供虚拟摇杆与行为按钮'),
    (Icons.tune_rounded,         '参数配置',     '「参数」页调整刚度、阻尼与推理模型'),
    (Icons.psychology_rounded,   '智脑策略',     '「智脑」页管理运动策略并查看推理状态'),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.brand.withValues(alpha: 0.15)),
        boxShadow: [BoxShadow(color: AppTheme.brand.withValues(alpha: 0.04), blurRadius: 16)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: AppTheme.brand.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.rocket_launch_rounded, size: 16, color: AppTheme.brand),
          ),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('欢迎使用 Nova Dog', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: cs.onSurface)),
            Text('连接机器人后即可开始', style: TextStyle(fontSize: 10, color: cs.onSurface.withValues(alpha: 0.4))),
          ]),
        ]),
        const SizedBox(height: 14),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: _steps.map((s) => SizedBox(
            width: 180,
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(s.$1, size: 14, color: AppTheme.brand.withValues(alpha: 0.6)),
              const SizedBox(width: 6),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.$2, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cs.onSurface.withValues(alpha: 0.8))),
                Text(s.$3, style: TextStyle(fontSize: 9, color: cs.onSurface.withValues(alpha: 0.4))),
              ])),
            ]),
          )).toList(),
        ),
      ]),
    );
  }
}

