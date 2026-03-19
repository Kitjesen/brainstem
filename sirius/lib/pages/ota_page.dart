import 'package:flutter/material.dart';
import '../services/ota_service.dart';
import '../theme/app_theme.dart';
import '../utils/app_toast.dart';
import '../widgets/status_card.dart';

/// 截断设备 ID 为最多 [maxLen] 个字符，不足则原样返回。
String _truncateId(String id, {int maxLen = 12}) =>
    id.length <= maxLen ? id : id.substring(0, maxLen);

class OtaPage extends StatefulWidget {
  const OtaPage({super.key});

  @override
  State<OtaPage> createState() => _OtaPageState();
}

class _OtaPageState extends State<OtaPage> {
  final _ota = OtaService();
  int _tab = 0; // 0=设备 1=包 2=发布 3=任务 4=告警 5=健康
  String? _selectedDeviceId;
  int? _selectedReleaseId;
  bool _pushing = false;
  late final TextEditingController _urlCtrl;
  bool _editingUrl = false;
  List<OtaDeviceHealth> _fleetHealth = [];
  bool _healthLoading = false;

  @override
  void initState() {
    super.initState();
    _urlCtrl = TextEditingController(text: _ota.baseUrl);
    _ota.addListener(_onUpdate);
    _ota.refresh();
  }

  @override
  void dispose() {
    _ota.removeListener(_onUpdate);
    _ota.dispose();
    _urlCtrl.dispose();
    super.dispose();
  }

  void _onUpdate() { if (mounted) setState(() {}); }

  Future<void> _fetchHealth() async {
    setState(() => _healthLoading = true);
    try {
      _fleetHealth = await _ota.fetchFleetHealth();
    } catch (_) {
      // health is supplementary, don't block UI
    }
    if (mounted) setState(() => _healthLoading = false);
  }

  Future<void> _ackAlert(int alertId) async {
    try {
      await _ota.ackAlert(alertId);
      await _ota.refresh();
    } catch (e) {
      if (mounted) AppToast.showError(context, '确认告警失败：$e');
    }
  }

  Future<void> _rollbackRelease(int releaseId) async {
    try {
      await _ota.rollbackRelease(releaseId);
      if (mounted) AppToast.showSuccess(context, '已触发回滚');
      await _ota.refresh();
    } catch (e) {
      if (mounted) AppToast.showError(context, '回滚失败：$e');
    }
  }

  Future<void> _pushUpgrade() async {
    final did = _selectedDeviceId;
    final rid = _selectedReleaseId;
    if (did == null || rid == null) return;
    setState(() => _pushing = true);
    try {
      final task = await _ota.createTask(did, rid);
      if (task != null && mounted) {
        AppToast.showSuccess(context, '升级任务已创建：#${task.id}');
        setState(() => _tab = 3);
        await _ota.refresh();
      }
    } catch (e) {
      if (mounted) AppToast.showError(context, '创建失败：$e');
    }
    if (mounted) setState(() => _pushing = false);
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final activeTasks = _ota.tasks.where((t) => t.isActive).toList();
    final canPush = _selectedDeviceId != null && _selectedReleaseId != null && !_pushing;

    final selRelease = _selectedReleaseId != null
        ? _ota.releases.where((r) => r.id == _selectedReleaseId).firstOrNull
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header ──────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('OTA 升级管理', style: tt.headlineLarge),
                const SizedBox(height: 4),
                Text('固件版本分发与升级追踪', style: tt.bodySmall),
              ]),
              const Spacer(),
              if (_ota.alertCount > 0) ...[
                _AlertBadge(count: _ota.alertCount),
                const SizedBox(width: 10),
              ],
              if (_ota.loading)
                SizedBox(
                  width: 14, height: 14,
                  child: CircularProgressIndicator(strokeWidth: 1.5, color: AppTheme.brand),
                ),
              const SizedBox(width: 10),
              _IconButton(
                icon: Icons.refresh_rounded,
                tooltip: '刷新',
                onTap: _ota.loading ? null : _ota.refresh,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // ── Server URL bar ──────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: _ServerBar(
            ota: _ota,
            ctrl: _urlCtrl,
            editing: _editingUrl,
            onEditToggle: () => setState(() => _editingUrl = !_editingUrl),
            onSave: () {
              _ota.baseUrl = _urlCtrl.text.trim(); // public field
              setState(() => _editingUrl = false);
              _ota.refresh();
            },
          ),
        ),
        const SizedBox(height: 14),

        // ── Tab bar ─────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(children: [
            _TabChip(label: '设备', count: _ota.devices.length, sel: _tab == 0,
                onTap: () => setState(() => _tab = 0)),
            const SizedBox(width: 6),
            _TabChip(label: '包', count: _ota.packages.length, sel: _tab == 1,
                onTap: () => setState(() => _tab = 1)),
            const SizedBox(width: 6),
            _TabChip(label: '发布', count: _ota.releases.length, sel: _tab == 2,
                onTap: () => setState(() => _tab = 2)),
            const SizedBox(width: 6),
            _TabChip(label: '任务', count: _ota.tasks.length, sel: _tab == 3,
                onTap: () => setState(() => _tab = 3), badge: activeTasks.length),
            const SizedBox(width: 6),
            _TabChip(label: '告警', count: _ota.alerts.length, sel: _tab == 4,
                onTap: () => setState(() => _tab = 4),
                badge: _ota.alerts.where((a) => !a.acknowledged).length),
            const SizedBox(width: 6),
            _TabChip(label: '健康', count: _fleetHealth.length, sel: _tab == 5,
                onTap: () {
                  setState(() => _tab = 5);
                  if (_fleetHealth.isEmpty && !_healthLoading) _fetchHealth();
                }),
          ]),
        ),
        const SizedBox(height: 10),

        // ── Error banner ─────────────────────────────────────────────────────
        if (_ota.error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.red.withValues(alpha: 0.08),
                border: Border.all(color: AppTheme.red.withValues(alpha: 0.3)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(children: [
                Icon(Icons.error_outline_rounded, size: 13, color: AppTheme.red),
                const SizedBox(width: 8),
                Expanded(child: Text(_ota.error!, style: tt.bodySmall?.copyWith(color: AppTheme.red))),
              ]),
            ),
          ),

        // ── Active tasks mini-strip ──────────────────────────────────────────
        if (activeTasks.isNotEmpty && _tab != 3)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: _ActiveStrip(tasks: activeTasks),
          ),

        // ── Tab content ──────────────────────────────────────────────────────
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: _buildTab(tt, cs),
          ),
        ),

        // ── Push action bar ──────────────────────────────────────────────────
        _PushBar(
          selectedDeviceId: _selectedDeviceId,
          selectedRelease: selRelease,
          canPush: canPush,
          pushing: _pushing,
          onPush: _pushUpgrade,
          cs: cs,
          tt: tt,
        ),
      ],
    );
  }

  Widget _buildTab(TextTheme tt, ColorScheme cs) {
    if (_ota.loading && _ota.devices.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          CircularProgressIndicator(strokeWidth: 1.5, color: AppTheme.brand),
          const SizedBox(height: 12),
          Text('正在连接 OTA 服务器…', style: tt.bodySmall?.copyWith(color: cs.onSurface.withValues(alpha: 0.4))),
        ]),
      );
    }
    switch (_tab) {
      case 0:
        return _DevicesTab(
          ota: _ota, selectedId: _selectedDeviceId,
          onSelect: (id) => setState(() => _selectedDeviceId = _selectedDeviceId == id ? null : id),
        );
      case 1:
        return _PackagesTab(ota: _ota);
      case 2:
        return _ReleasesTab(
          ota: _ota, selectedId: _selectedReleaseId,
          onSelect: (id) => setState(() => _selectedReleaseId = _selectedReleaseId == id ? null : id),
          onRollback: _rollbackRelease,
        );
      case 3:
        return _TasksTab(ota: _ota, releases: _ota.releases);
      case 4:
        return _AlertsTab(ota: _ota, onAck: _ackAlert);
      case 5:
        return _HealthTab(health: _fleetHealth, loading: _healthLoading, onRefresh: _fetchHealth);
      default:
        return const SizedBox.shrink();
    }
  }
}

// ── Server URL bar ────────────────────────────────────────────────────────────

class _ServerBar extends StatelessWidget {
  final OtaService ota;
  final TextEditingController ctrl;
  final bool editing;
  final VoidCallback onEditToggle;
  final VoidCallback onSave;

  const _ServerBar({
    required this.ota, required this.ctrl, required this.editing,
    required this.onEditToggle, required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.outline.withValues(alpha: 0.5), width: 0.5),
      ),
      child: Row(children: [
        Icon(Icons.dns_rounded, size: 13, color: cs.onSurface.withValues(alpha: 0.35)),
        const SizedBox(width: 8),
        if (editing)
          Expanded(
            child: TextField(
              controller: ctrl,
              style: tt.bodySmall,
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.zero,
                border: InputBorder.none,
              ),
              autofocus: true,
              onSubmitted: (_) => onSave(),
            ),
          )
        else
          Expanded(
            child: Text(ota.baseUrl, style: tt.bodySmall?.copyWith(color: cs.onSurface.withValues(alpha: 0.6))),
          ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: editing ? onSave : onEditToggle,
          child: Text(
            editing ? '保存' : '编辑',
            style: tt.labelSmall?.copyWith(color: AppTheme.brand),
          ),
        ),
      ]),
    );
  }
}

// ── Alert badge ───────────────────────────────────────────────────────────────

class _AlertBadge extends StatelessWidget {
  final int count;
  const _AlertBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.red.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppTheme.red.withValues(alpha: 0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.warning_amber_rounded, size: 12, color: AppTheme.red),
        const SizedBox(width: 4),
        Text('$count 个告警', style: tt.labelSmall?.copyWith(color: AppTheme.red)),
      ]),
    );
  }
}

// ── Active tasks strip ───────────────────────────────────────────────────────

class _ActiveStrip extends StatelessWidget {
  final List<OtaTask> tasks;
  const _ActiveStrip({required this.tasks});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.brand.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.brand.withValues(alpha: 0.2)),
      ),
      child: Row(children: [
        SizedBox(
          width: 12, height: 12,
          child: CircularProgressIndicator(strokeWidth: 1.5, color: AppTheme.brand),
        ),
        const SizedBox(width: 10),
        Text(
          '${tasks.length} 个升级任务进行中',
          style: tt.bodySmall?.copyWith(color: AppTheme.brand, fontWeight: FontWeight.w600),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            tasks.map((t) => '${_truncateId(t.deviceId)}…${t.progressPercent}%').join(' · '),
            style: tt.labelSmall?.copyWith(color: cs.onSurface.withValues(alpha: 0.5)),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ]),
    );
  }
}

// ── Tab chip ──────────────────────────────────────────────────────────────────

class _TabChip extends StatelessWidget {
  final String label;
  final int count;
  final bool sel;
  final VoidCallback onTap;
  final int badge;

  const _TabChip({
    required this.label, required this.count, required this.sel,
    required this.onTap, this.badge = 0,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: sel ? AppTheme.brand.withValues(alpha: 0.12) : cs.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: sel ? AppTheme.brand.withValues(alpha: 0.4) : cs.outline.withValues(alpha: 0.4),
                width: sel ? 1.5 : 0.5,
              ),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(label, style: tt.labelMedium?.copyWith(
                  color: sel ? AppTheme.brand : cs.onSurface.withValues(alpha: 0.6),
                  fontWeight: sel ? FontWeight.w700 : FontWeight.w500)),
              if (count > 0) ...[
                const SizedBox(width: 6),
                Text('$count', style: tt.labelSmall?.copyWith(
                    color: sel ? AppTheme.brand.withValues(alpha: 0.7) : cs.onSurface.withValues(alpha: 0.35))),
              ],
            ]),
          ),
          if (badge > 0)
            Positioned(
              top: -4, right: -4,
              child: Container(
                constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
                padding: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  color: AppTheme.orange,
                  borderRadius: BorderRadius.circular(7),
                  boxShadow: [BoxShadow(color: AppTheme.orange.withValues(alpha: 0.4), blurRadius: 4)],
                ),
                child: Text('$badge', style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: Colors.white), textAlign: TextAlign.center),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Icon button ───────────────────────────────────────────────────────────────

class _IconButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  const _IconButton({required this.icon, required this.tooltip, this.onTap});
  @override State<_IconButton> createState() => _IconButtonState();
}
class _IconButtonState extends State<_IconButton> {
  bool _hov = false;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hov = true),
        onExit: (_) => setState(() => _hov = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: _hov && widget.onTap != null ? cs.onSurface.withValues(alpha: 0.06) : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(widget.icon, size: 16,
                color: widget.onTap == null ? cs.onSurface.withValues(alpha: 0.25) : AppTheme.brand),
          ),
        ),
      ),
    );
  }
}

// ── Push bar ──────────────────────────────────────────────────────────────────

class _PushBar extends StatelessWidget {
  final String? selectedDeviceId;
  final OtaRelease? selectedRelease;
  final bool canPush;
  final bool pushing;
  final VoidCallback onPush;
  final ColorScheme cs;
  final TextTheme tt;

  const _PushBar({
    required this.selectedDeviceId, required this.selectedRelease,
    required this.canPush, required this.pushing, required this.onPush,
    required this.cs, required this.tt,
  });

  @override
  Widget build(BuildContext context) {
    final hint = selectedDeviceId == null
        ? '在「设备」选择目标设备'
        : selectedRelease == null
            ? '在「发布」选择目标版本'
            : '${_truncateId(selectedDeviceId!, maxLen: 16)}  →  v${selectedRelease!.version}  (${selectedRelease!.channel})';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: cs.outline.withValues(alpha: 0.15))),
      ),
      child: Row(children: [
        Icon(
          canPush ? Icons.rocket_launch_rounded : Icons.cloud_upload_rounded,
          size: 13,
          color: canPush ? AppTheme.brand : cs.onSurface.withValues(alpha: 0.25),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(hint, style: tt.bodySmall?.copyWith(
              color: canPush ? cs.onSurface.withValues(alpha: 0.7) : cs.onSurface.withValues(alpha: 0.35))),
        ),
        GestureDetector(
          onTap: canPush ? onPush : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
            decoration: BoxDecoration(
              color: canPush ? AppTheme.brand.withValues(alpha: 0.12) : cs.onSurface.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: canPush ? AppTheme.brand.withValues(alpha: 0.4) : cs.outline.withValues(alpha: 0.2),
              ),
            ),
            child: pushing
                ? SizedBox(width: 14, height: 14,
                    child: CircularProgressIndicator(strokeWidth: 1.5, color: AppTheme.brand))
                : Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.rocket_launch_rounded, size: 13,
                        color: canPush ? AppTheme.brand : cs.onSurface.withValues(alpha: 0.25)),
                    const SizedBox(width: 6),
                    Text('推送升级', style: tt.labelMedium?.copyWith(
                        color: canPush ? AppTheme.brand : cs.onSurface.withValues(alpha: 0.3))),
                  ]),
          ),
        ),
      ]),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// 设备 tab
// ════════════════════════════════════════════════════════════════════════════

class _DevicesTab extends StatelessWidget {
  final OtaService ota;
  final String? selectedId;
  final ValueChanged<String> onSelect;

  const _DevicesTab({required this.ota, required this.selectedId, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    if (ota.devices.isEmpty) {
      return Center(child: Text('暂无设备数据', style: tt.bodySmall?.copyWith(color: cs.onSurface.withValues(alpha: 0.3))));
    }
    return ListView.builder(
      itemCount: ota.devices.length,
      itemBuilder: (_, i) {
        final d = ota.devices[i];
        final sel = selectedId == d.id;
        return _DeviceRow(device: d, selected: sel, onTap: () => onSelect(d.id));
      },
    );
  }
}

class _DeviceRow extends StatefulWidget {
  final OtaDevice device;
  final bool selected;
  final VoidCallback onTap;
  const _DeviceRow({required this.device, required this.selected, required this.onTap});
  @override State<_DeviceRow> createState() => _DeviceRowState();
}
class _DeviceRowState extends State<_DeviceRow> {
  bool _hov = false;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final d = widget.device;
    final dotColor = d.online ? AppTheme.green : cs.onSurface.withValues(alpha: 0.2);

    return MouseRegion(
      onEnter: (_) => setState(() => _hov = true),
      onExit: (_) => setState(() => _hov = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: widget.selected
                ? AppTheme.brand.withValues(alpha: 0.08)
                : _hov
                    ? cs.onSurface.withValues(alpha: 0.03)
                    : cs.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: widget.selected
                  ? AppTheme.brand.withValues(alpha: 0.35)
                  : cs.outline.withValues(alpha: 0.4),
              width: widget.selected ? 1.5 : 0.5,
            ),
          ),
          child: Row(children: [
            // Online dot
            Container(
              width: 7, height: 7,
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: dotColor,
                boxShadow: d.online ? [BoxShadow(color: AppTheme.green.withValues(alpha: 0.4), blurRadius: 4)] : [],
              ),
            ),
            // Device info
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text(
                    d.id.length > 20 ? '${d.id.substring(0, 20)}…' : d.id,
                    style: tt.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 8),
                  _Chip(label: d.product, color: AppTheme.brand),
                  const SizedBox(width: 4),
                  _Chip(
                    label: d.channel,
                    color: d.channel == 'stable' ? AppTheme.green : d.channel == 'beta' ? AppTheme.orange : AppTheme.red,
                  ),
                ]),
                if (d.currentVersions.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Wrap(spacing: 8, children: d.currentVersions.entries.map((e) =>
                    Text('${e.key}: ${e.value}', style: tt.labelSmall?.copyWith(color: cs.onSurface.withValues(alpha: 0.5)))
                  ).toList()),
                ],
              ]),
            ),
            // Right: IP + status
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(
                d.online ? '在线' : '离线',
                style: tt.labelSmall?.copyWith(color: d.online ? AppTheme.green : cs.onSurface.withValues(alpha: 0.3)),
              ),
              if (d.ipAddress != null) ...[
                const SizedBox(height: 2),
                Text(d.ipAddress!, style: tt.labelSmall?.copyWith(color: cs.onSurface.withValues(alpha: 0.3))),
              ],
            ]),
            if (widget.selected) ...[
              const SizedBox(width: 10),
              Icon(Icons.check_circle_rounded, size: 14, color: AppTheme.brand),
            ],
          ]),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// 包 tab
// ════════════════════════════════════════════════════════════════════════════

class _PackagesTab extends StatelessWidget {
  final OtaService ota;
  const _PackagesTab({required this.ota});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    if (ota.packages.isEmpty) {
      return Center(child: Text('暂无固件包', style: tt.bodySmall?.copyWith(color: cs.onSurface.withValues(alpha: 0.3))));
    }
    // Group by package name
    final grouped = <String, List<OtaPackage>>{};
    for (final p in ota.packages) {
      grouped.putIfAbsent(p.name, () => []).add(p);
    }
    return ListView(
      children: grouped.entries.map((entry) => StatusCard(
        title: entry.key,
        trailing: Text('${entry.value.length} 个版本', style: tt.labelSmall?.copyWith(color: cs.onSurface.withValues(alpha: 0.4))),
        child: Column(
          children: entry.value.map((p) => _PackageRow(pkg: p)).toList(),
        ),
      )).toList(),
    );
  }
}

class _PackageRow extends StatelessWidget {
  final OtaPackage pkg;
  const _PackageRow({required this.pkg});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        Icon(Icons.inventory_2_rounded, size: 13, color: cs.onSurface.withValues(alpha: 0.3)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('v${pkg.version}', style: tt.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
              if (pkg.fileSizeLabel.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(pkg.fileSizeLabel, style: tt.labelSmall?.copyWith(color: cs.onSurface.withValues(alpha: 0.4))),
              ],
            ]),
            if (pkg.changelog != null && pkg.changelog!.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                pkg.changelog!,
                style: tt.labelSmall?.copyWith(color: cs.onSurface.withValues(alpha: 0.45)),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ]),
        ),
        if (pkg.createdAt != null)
          Text(_shortDate(pkg.createdAt!), style: tt.labelSmall?.copyWith(color: cs.onSurface.withValues(alpha: 0.3))),
      ]),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// 发布 tab
// ════════════════════════════════════════════════════════════════════════════

class _ReleasesTab extends StatelessWidget {
  final OtaService ota;
  final int? selectedId;
  final ValueChanged<int> onSelect;

  final Future<void> Function(int releaseId) onRollback;

  const _ReleasesTab({required this.ota, required this.selectedId, required this.onSelect, required this.onRollback});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    if (ota.releases.isEmpty) {
      return Center(child: Text('暂无发布版本', style: tt.bodySmall?.copyWith(color: cs.onSurface.withValues(alpha: 0.3))));
    }
    return ListView.builder(
      itemCount: ota.releases.length,
      itemBuilder: (_, i) {
        final r = ota.releases[i];
        final sel = selectedId == r.id;
        return _ReleaseRow(release: r, selected: sel, onTap: () => onSelect(r.id), onRollback: () => onRollback(r.id));
      },
    );
  }
}

class _ReleaseRow extends StatefulWidget {
  final OtaRelease release;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onRollback;
  const _ReleaseRow({required this.release, required this.selected, required this.onTap, required this.onRollback});
  @override State<_ReleaseRow> createState() => _ReleaseRowState();
}
class _ReleaseRowState extends State<_ReleaseRow> {
  bool _hov = false;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final r = widget.release;
    final statusColor = r.isActive ? AppTheme.green : AppTheme.red;

    return MouseRegion(
      onEnter: (_) => setState(() => _hov = true),
      onExit: (_) => setState(() => _hov = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: widget.selected
                ? AppTheme.brand.withValues(alpha: 0.08)
                : _hov
                    ? cs.onSurface.withValues(alpha: 0.03)
                    : cs.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: widget.selected ? AppTheme.brand.withValues(alpha: 0.35) : cs.outline.withValues(alpha: 0.4),
              width: widget.selected ? 1.5 : 0.5,
            ),
          ),
          child: Row(children: [
            // Version
            SizedBox(
              width: 90,
              child: Text('v${r.version}', style: tt.bodySmall?.copyWith(fontWeight: FontWeight.w700)),
            ),
            // Channel + rollout chips
            _Chip(
              label: r.channel,
              color: r.channel == 'stable' ? AppTheme.green : r.channel == 'beta' ? AppTheme.orange : AppTheme.red,
            ),
            const SizedBox(width: 6),
            if (r.rolloutPercent < 100)
              _Chip(label: '${r.rolloutPercent}%', color: AppTheme.yellow),
            const Spacer(),
            // Status
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                r.isActive ? '有效' : '已回滚',
                style: tt.labelSmall?.copyWith(color: statusColor),
              ),
            ),
            const SizedBox(width: 10),
            if (r.createdAt != null)
              Text(_shortDate(r.createdAt!), style: tt.labelSmall?.copyWith(color: cs.onSurface.withValues(alpha: 0.3))),
            if (r.isActive) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: widget.onRollback,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: AppTheme.orange.withValues(alpha: 0.3)),
                  ),
                  child: Text('回滚', style: tt.labelSmall?.copyWith(color: AppTheme.orange, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
            if (widget.selected) ...[
              const SizedBox(width: 10),
              Icon(Icons.check_circle_rounded, size: 14, color: AppTheme.brand),
            ],
          ]),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// 任务 tab
// ════════════════════════════════════════════════════════════════════════════

class _TasksTab extends StatelessWidget {
  final OtaService ota;
  final List<OtaRelease> releases;
  const _TasksTab({required this.ota, required this.releases});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    if (ota.tasks.isEmpty) {
      return Center(child: Text('暂无任务', style: tt.bodySmall?.copyWith(color: cs.onSurface.withValues(alpha: 0.3))));
    }
    return ListView.builder(
      itemCount: ota.tasks.length,
      itemBuilder: (_, i) {
        final t = ota.tasks[i];
        final ver = releases.where((r) => r.id == t.releaseId).firstOrNull?.version;
        return _TaskRow(task: t, releaseVersion: ver);
      },
    );
  }
}

class _TaskRow extends StatelessWidget {
  final OtaTask task;
  final String? _releaseVersion;
  const _TaskRow({required this.task, String? releaseVersion})
      : _releaseVersion = releaseVersion;

  static const _statusLabel = {
    'pending': '等待中',
    'downloading': '下载中',
    'installing': '安装中',
    'success': '已完成',
    'failed': '失败',
    'rolled_back': '已回滚',
  };

  static Color _statusColor(String s) {
    switch (s) {
      case 'success': return AppTheme.green;
      case 'failed': return AppTheme.red;
      case 'rolled_back': return AppTheme.orange;
      case 'pending': return AppTheme.yellow;
      default: return AppTheme.brand;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final t = task;
    final color = _statusColor(t.status);
    final label = _statusLabel[t.status] ?? t.status;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.outline.withValues(alpha: 0.4), width: 0.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('#${t.id}', style: tt.labelSmall?.copyWith(color: cs.onSurface.withValues(alpha: 0.35))),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _truncateId(t.deviceId, maxLen: 24),
              style: tt.bodySmall?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          if (_releaseVersion != null) ...[
            _Chip(label: 'v$_releaseVersion', color: AppTheme.teal),
            const SizedBox(width: 8),
          ],
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(label, style: tt.labelSmall?.copyWith(color: color)),
          ),
          const SizedBox(width: 8),
          if (t.startedAt != null)
            Text(_shortDate(t.startedAt!), style: tt.labelSmall?.copyWith(color: cs.onSurface.withValues(alpha: 0.3))),
        ]),
        if (t.isActive && t.progressPercent > 0) ...[
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: t.progressPercent / 100.0,
              backgroundColor: cs.onSurface.withValues(alpha: 0.08),
              valueColor: AlwaysStoppedAnimation(color),
              minHeight: 4,
            ),
          ),
          const SizedBox(height: 3),
          Text('${t.progressPercent}%', style: tt.labelSmall?.copyWith(color: color)),
        ] else if (t.isActive) ...[
          const SizedBox(height: 8),
          LinearProgressIndicator(
            backgroundColor: cs.onSurface.withValues(alpha: 0.08),
            valueColor: AlwaysStoppedAnimation(color),
            minHeight: 3,
          ),
        ],
        if (t.errorMessage != null && t.errorMessage!.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(t.errorMessage!, style: tt.labelSmall?.copyWith(color: AppTheme.red)),
        ],
      ]),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// 告警 tab
// ════════════════════════════════════════════════════════════════════════════

class _AlertsTab extends StatelessWidget {
  final OtaService ota;
  final Future<void> Function(int alertId) onAck;
  const _AlertsTab({required this.ota, required this.onAck});

  static const _severityIcon = {
    'critical': Icons.error_rounded,
    'warning': Icons.warning_amber_rounded,
    'info': Icons.info_outline_rounded,
  };

  static Color _severityColor(String s) {
    switch (s) {
      case 'critical': return AppTheme.red;
      case 'warning': return AppTheme.orange;
      default: return AppTheme.brand;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    if (ota.alerts.isEmpty) {
      return Center(child: Text('暂无告警', style: tt.bodySmall?.copyWith(color: cs.onSurface.withValues(alpha: 0.3))));
    }
    return ListView.builder(
      itemCount: ota.alerts.length,
      itemBuilder: (_, i) {
        final a = ota.alerts[i];
        final color = _severityColor(a.severity);
        final icon = _severityIcon[a.severity] ?? Icons.info_outline_rounded;
        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: a.acknowledged ? cs.surface : color.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: a.acknowledged ? cs.outline.withValues(alpha: 0.4) : color.withValues(alpha: 0.3),
              width: 0.5,
            ),
          ),
          child: Row(children: [
            Icon(icon, size: 14, color: a.acknowledged ? cs.onSurface.withValues(alpha: 0.3) : color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  _Chip(label: a.alertType, color: color),
                  const SizedBox(width: 6),
                  _Chip(label: a.severity, color: color),
                  if (a.deviceId != null) ...[
                    const SizedBox(width: 6),
                    Text(_truncateId(a.deviceId!, maxLen: 12),
                        style: tt.labelSmall?.copyWith(color: cs.onSurface.withValues(alpha: 0.4))),
                  ],
                ]),
                const SizedBox(height: 4),
                Text(a.message,
                    style: tt.bodySmall?.copyWith(
                        color: a.acknowledged ? cs.onSurface.withValues(alpha: 0.5) : cs.onSurface),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
              ]),
            ),
            const SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              if (a.createdAt != null)
                Text(_shortDate(a.createdAt!), style: tt.labelSmall?.copyWith(color: cs.onSurface.withValues(alpha: 0.3))),
              const SizedBox(height: 4),
              if (!a.acknowledged)
                GestureDetector(
                  onTap: () => onAck(a.id),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.brand.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(color: AppTheme.brand.withValues(alpha: 0.3)),
                    ),
                    child: Text('确认', style: tt.labelSmall?.copyWith(color: AppTheme.brand, fontWeight: FontWeight.w600)),
                  ),
                )
              else
                Text('已确认', style: tt.labelSmall?.copyWith(color: cs.onSurface.withValues(alpha: 0.3))),
            ]),
          ]),
        );
      },
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// 健康监控 tab
// ════════════════════════════════════════════════════════════════════════════

class _HealthTab extends StatelessWidget {
  final List<OtaDeviceHealth> health;
  final bool loading;
  final VoidCallback onRefresh;
  const _HealthTab({required this.health, required this.loading, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    if (loading && health.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          CircularProgressIndicator(strokeWidth: 1.5, color: AppTheme.brand),
          const SizedBox(height: 12),
          Text('正在获取设备健康数据…', style: tt.bodySmall?.copyWith(color: cs.onSurface.withValues(alpha: 0.4))),
        ]),
      );
    }

    if (health.isEmpty) {
      return Center(child: Text('暂无健康数据', style: tt.bodySmall?.copyWith(color: cs.onSurface.withValues(alpha: 0.3))));
    }

    return ListView.builder(
      itemCount: health.length,
      itemBuilder: (_, i) {
        final h = health[i];
        final t = h.latest;
        final score = h.healthScore;
        final scoreColor = score == null
            ? cs.onSurface.withValues(alpha: 0.3)
            : score >= 80
                ? AppTheme.green
                : score >= 50
                    ? AppTheme.orange
                    : AppTheme.red;

        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: cs.outline.withValues(alpha: 0.4), width: 0.5),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(
                  h.deviceId.length > 24 ? '${h.deviceId.substring(0, 24)}…' : h.deviceId,
                  style: tt.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              if (score != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: scoreColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text('${score.toStringAsFixed(0)}分',
                      style: tt.labelSmall?.copyWith(color: scoreColor, fontWeight: FontWeight.w700)),
                ),
              ],
              if (h.lastSeen != null) ...[
                const SizedBox(width: 8),
                Text(_shortDate(h.lastSeen!), style: tt.labelSmall?.copyWith(color: cs.onSurface.withValues(alpha: 0.3))),
              ],
            ]),
            if (t != null) ...[
              const SizedBox(height: 8),
              Row(children: [
                _MetricChip(label: 'CPU', value: t.cpuLoad1m != null ? t.cpuLoad1m!.toStringAsFixed(1) : '-', cs: cs, tt: tt),
                const SizedBox(width: 8),
                _MetricChip(label: '温度', value: t.cpuTemp != null ? '${t.cpuTemp!.toStringAsFixed(0)}°' : '-', cs: cs, tt: tt),
                const SizedBox(width: 8),
                _MetricChip(label: '内存', value: t.memUsedPercent != null ? '${t.memUsedPercent!.toStringAsFixed(0)}%' : '-', cs: cs, tt: tt),
                const SizedBox(width: 8),
                _MetricChip(label: '磁盘', value: t.diskUsedPercent != null ? '${t.diskUsedPercent!.toStringAsFixed(0)}%' : '-', cs: cs, tt: tt),
                if (t.batteryPercent != null) ...[
                  const SizedBox(width: 8),
                  _MetricChip(label: '电池', value: '${t.batteryPercent!.toStringAsFixed(0)}%', cs: cs, tt: tt),
                ],
              ]),
            ],
            if (h.alerts.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 4, children: h.alerts.map((a) =>
                _Chip(label: a, color: AppTheme.orange),
              ).toList()),
            ],
          ]),
        );
      },
    );
  }
}

class _MetricChip extends StatelessWidget {
  final String label;
  final String value;
  final ColorScheme cs;
  final TextTheme tt;
  const _MetricChip({required this.label, required this.value, required this.cs, required this.tt});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: cs.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: tt.labelSmall?.copyWith(color: cs.onSurface.withValues(alpha: 0.4))),
        const SizedBox(width: 4),
        Text(value, style: tt.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

// ── Shared helpers ────────────────────────────────────────────────────────────

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  const _Chip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label, style: tt.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w600)),
    );
  }
}

String _shortDate(String iso) {
  try {
    final dt = DateTime.parse(iso).toLocal();
    return '${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  } catch (_) {
    return iso.length > 10 ? iso.substring(0, 10) : iso;
  }
}
