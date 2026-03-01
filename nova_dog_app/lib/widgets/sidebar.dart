import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../l10n/app_localizations.dart';
import 'settings_panel.dart';

class NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String Function(BuildContext) labelBuilder;
  const NavItem(this.icon, this.activeIcon, this.labelBuilder);
}

/// 导航项列表（仅在进程生命周期内创建一次）。
final List<NavItem> _kNavItems = [
  NavItem(Icons.space_dashboard_outlined, Icons.space_dashboard_rounded, (ctx) => AppLocalizations.of(ctx).navDashboard),
  NavItem(Icons.monitor_heart_outlined, Icons.monitor_heart_rounded, (ctx) => AppLocalizations.of(ctx).navMonitor),
  NavItem(Icons.gamepad_outlined, Icons.gamepad_rounded, (ctx) => AppLocalizations.of(ctx).navControl),
  NavItem(Icons.tune_outlined, Icons.tune_rounded, (ctx) => AppLocalizations.of(ctx).navParams),
  NavItem(Icons.terminal_outlined,  Icons.terminal_rounded,  (ctx) => AppLocalizations.of(ctx).navProtocol),
  NavItem(Icons.explore_outlined,   Icons.explore_rounded,   (ctx) => AppLocalizations.of(ctx).navImu),
  NavItem(Icons.history_outlined,   Icons.history_rounded,   (ctx) => AppLocalizations.of(ctx).navHistory),
  NavItem(Icons.psychology_outlined, Icons.psychology_rounded, (ctx) => AppLocalizations.of(ctx).navBrain),
  NavItem(Icons.system_update_outlined, Icons.system_update_rounded, (ctx) => AppLocalizations.of(ctx).navOta),
];

/// 已废弃：请直接使用 [_kNavItems]（保留此函数供外部兼容）
List<NavItem> getNavItems() => _kNavItems;

class Sidebar extends StatelessWidget {
  static const double _collapsedWidth = 48;
  static const double _expandedWidth = 72;
  final int selectedIndex; final ValueChanged<int> onSelect;
  final bool isDark; final VoidCallback onToggleTheme;
  final bool isConnected; final String connectionInfo;
  final double textScale; final VoidCallback onScaleUp; final VoidCallback onScaleDown;
  final BrandColor brandColor; final ValueChanged<BrandColor> onChangeBrandColor;
  final VoidCallback onToggleLanguage;
  // Live stats for bottom status strip
  final String cmsState;
  final double historyHz;
  final double lastRttMs;
  // Collapse control
  final bool collapsed;
  final VoidCallback onToggleCollapse;
  // Notification badges: nav index → count
  final Map<int, int> badges;

  const Sidebar({super.key, required this.selectedIndex, required this.onSelect, required this.isDark, required this.onToggleTheme, required this.isConnected, required this.connectionInfo, required this.textScale, required this.onScaleUp, required this.onScaleDown, required this.brandColor, required this.onChangeBrandColor, required this.onToggleLanguage, this.cmsState = '', this.historyHz = 0, this.lastRttMs = 0, this.collapsed = false, required this.onToggleCollapse, this.badges = const {}});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final brand = brandColor.color;
    final navItems = _kNavItems;

    const borderRadius = BorderRadius.only(
      topRight: Radius.circular(20),
      bottomRight: Radius.circular(20),
    );
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      width: collapsed ? _collapsedWidth : _expandedWidth,
      child: ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          decoration: BoxDecoration(
            color: (dark ? Colors.black : Colors.white).withValues(alpha: dark ? 0.4 : 0.7),
            borderRadius: borderRadius,
            border: Border.all(
              color: (dark ? Colors.white : Colors.black).withValues(alpha: 0.08),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: dark ? 0.3 : 0.06),
                blurRadius: dark ? 16 : 12,
                offset: Offset(0, dark ? 4 : 2),
              ),
            ],
          ),
          child: Column(children: [
            const SizedBox(height: 16),
            // 导航项：可滚动，避免窗口较小时溢出
            Flexible(
              child: SingleChildScrollView(
                physics: const NeverScrollableScrollPhysics(),
                child: Column(
                  children: List.generate(navItems.length, (i) => _NavItem(
                    item: navItems[i], sel: i == selectedIndex,
                    onTap: () => onSelect(i), brand: brand,
                    context: context, collapsed: collapsed, badge: badges[i] ?? 0,
                  )),
                ),
              ),
            ),
            // 设置区固定在底部
            if (!collapsed) ...[
              const SizedBox(height: 8),
              // Settings button (includes theme, language, text size)
              _HoverIcon(
                icon: Icons.settings_outlined,
                onTap: () {
                  SettingsPanel.toggle(
                    context,
                    isDark: isDark,
                    onToggleTheme: onToggleTheme,
                    onToggleLanguage: onToggleLanguage,
                    textScale: textScale,
                    onScaleUp: onScaleUp,
                    onScaleDown: onScaleDown,
                  );
                },
                brand: brand,
              ),
              const SizedBox(height: 6),
              // Color picker button
              _ColorPickerButton(current: brandColor, onSelect: onChangeBrandColor, brand: brand),
              const SizedBox(height: 6),
              _StatusStrip(
                isConnected: isConnected,
                cmsState: cmsState,
                historyHz: historyHz,
                lastRttMs: lastRttMs,
                brand: brand,
              ),
            ] else ...[
              // Collapsed: just the connected dot
              const Spacer(),
              Container(
                width: 8, height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isConnected ? AppTheme.green : AppTheme.red,
                  boxShadow: [BoxShadow(color: (isConnected ? AppTheme.green : AppTheme.red).withValues(alpha: 0.5), blurRadius: 4)],
                ),
              ),
            ],
            // Collapse toggle button
            const SizedBox(height: 6),
            _HoverIcon(
              icon: collapsed ? Icons.chevron_right_rounded : Icons.chevron_left_rounded,
              onTap: onToggleCollapse,
              brand: brand,
            ),
            const SizedBox(height: 8),
          ]),
        ),
      ),
    ));
  }
}

class _ColorPickerButton extends StatefulWidget {
  final BrandColor current;
  final ValueChanged<BrandColor> onSelect;
  final Color brand;
  const _ColorPickerButton({required this.current, required this.onSelect, required this.brand});

  @override
  State<_ColorPickerButton> createState() => _ColorPickerButtonState();
}

class _ColorPickerButtonState extends State<_ColorPickerButton> {
  bool _hov = false;

  void _showColorMenu(BuildContext context) {
    final RenderBox button = context.findRenderObject() as RenderBox;
    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final RelativeRect position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(button.size.bottomRight(Offset.zero), ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );

    showMenu<BrandColor>(
      context: context,
      position: position,
      items: BrandColor.values.map((color) {
        return PopupMenuItem<BrandColor>(
          value: color,
          child: Row(
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: color.color,
                  shape: BoxShape.circle,
                  border: color == widget.current ? Border.all(color: Colors.white, width: 2) : null,
                ),
              ),
              const SizedBox(width: 12),
              Text(color.label),
            ],
          ),
        );
      }).toList(),
    ).then((selected) {
      if (selected != null) {
        widget.onSelect(selected);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return MouseRegion(
      onEnter: (_) => setState(() => _hov = true),
      onExit: (_) => setState(() => _hov = false),
      child: GestureDetector(
        onTap: () => _showColorMenu(context),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: _hov ? cs.onSurface.withValues(alpha: 0.06) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: widget.current.color,
              shape: BoxShape.circle,
              border: Border.all(
                color: _hov ? widget.brand : cs.onSurface.withValues(alpha: 0.25),
                width: 2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatefulWidget {
  final NavItem item; final bool sel; final VoidCallback onTap; final Color brand; final BuildContext context;
  final bool collapsed;
  final int badge;
  const _NavItem({required this.item, required this.sel, required this.onTap, required this.brand, required this.context, this.collapsed = false, this.badge = 0});
  @override State<_NavItem> createState() => _NavItemState();

  static const double _collapsedItemW = 36, _collapsedItemH = 36;
  static const double _expandedItemW = 56, _expandedItemH = 52;
}
class _NavItemState extends State<_NavItem> {
  bool _hov = false; bool _press = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = widget.sel;
    final b = widget.brand;
    final label = widget.item.labelBuilder(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Tooltip(
        message: widget.collapsed ? label : '',
        preferBelow: false,
        child: MouseRegion(
          onEnter: (_) => setState(() => _hov = true),
          onExit: (_) => setState(() => _hov = false),
          child: GestureDetector(
            onTapDown: (_) => setState(() => _press = true),
            onTapUp: (_) => setState(() => _press = false),
            onTapCancel: () => setState(() => _press = false),
            onTap: widget.onTap,
            child: Stack(
              alignment: Alignment.center,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  width: widget.collapsed ? _NavItem._collapsedItemW : _NavItem._expandedItemW,
                  height: widget.collapsed ? _NavItem._collapsedItemH : _NavItem._expandedItemH,
                  transform: _press ? Matrix4.diagonal3Values(0.92, 0.92, 1.0) : Matrix4.identity(),
                  transformAlignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: s ? b.withValues(alpha: 0.12) : _hov ? cs.onSurface.withValues(alpha: 0.06) : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(s ? widget.item.activeIcon : widget.item.icon, size: 18, color: s ? b : _hov ? cs.onSurface.withValues(alpha: 0.65) : cs.onSurface.withValues(alpha: 0.3)),
                      if (!widget.collapsed) ...[
                        const SizedBox(height: 3),
                        Text(label, style: TextStyle(fontSize: 9, fontWeight: s ? FontWeight.w700 : FontWeight.w500, color: s ? b : _hov ? cs.onSurface.withValues(alpha: 0.6) : cs.onSurface.withValues(alpha: 0.28))),
                      ],
                    ],
                  ),
                ),
                // Badge dot
                if (widget.badge > 0)
                  Positioned(
                    top: widget.collapsed ? 4 : 6,
                    right: widget.collapsed ? 4 : 8,
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 12, minHeight: 12),
                      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppTheme.red,
                        borderRadius: BorderRadius.circular(6),
                        boxShadow: [BoxShadow(color: AppTheme.red.withValues(alpha: 0.4), blurRadius: 4)],
                      ),
                      child: Text(
                        widget.badge > 9 ? '9+' : '${widget.badge}',
                        style: const TextStyle(fontSize: 7, fontWeight: FontWeight.w700, color: Colors.white),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HoverIcon extends StatefulWidget {
  final IconData icon; final VoidCallback onTap; final Color brand;
  const _HoverIcon({required this.icon, required this.onTap, required this.brand});
  @override State<_HoverIcon> createState() => _HoverIconState();
}
class _HoverIconState extends State<_HoverIcon> {
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
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: _hov ? cs.onSurface.withValues(alpha: 0.06) : Colors.transparent, borderRadius: BorderRadius.circular(10)),
          child: Icon(widget.icon, size: 18, color: _hov ? widget.brand : cs.onSurface.withValues(alpha: 0.25)),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════
// Sidebar bottom status strip
// ══════════════════════════════════════
class _StatusStrip extends StatelessWidget {
  final bool isConnected;
  final String cmsState;
  final double historyHz;
  final double lastRttMs;
  final Color brand;
  const _StatusStrip({required this.isConnected, required this.cmsState, required this.historyHz, required this.lastRttMs, required this.brand});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dotColor = isConnected ? AppTheme.green : AppTheme.red;

    // RTT color
    final rttColor = lastRttMs <= 0
        ? cs.onSurface.withValues(alpha: 0.2)
        : lastRttMs < 20
            ? AppTheme.green
            : lastRttMs < 60
                ? AppTheme.orange
                : AppTheme.red;

    return Container(
      width: 56,
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      decoration: BoxDecoration(
        color: cs.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Connected dot
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 6, height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: dotColor,
              boxShadow: [BoxShadow(color: dotColor.withValues(alpha: 0.5), blurRadius: 4)],
            ),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              isConnected ? (cmsState.isEmpty ? '...' : cmsState) : '断开',
              style: TextStyle(fontSize: 7.5, fontWeight: FontWeight.w600, color: isConnected ? cs.onSurface.withValues(alpha: 0.7) : cs.onSurface.withValues(alpha: 0.3)),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ]),
        const SizedBox(height: 4),
        // Hz
        _StripRow(
          label: 'Hz',
          value: isConnected && historyHz > 0 ? historyHz.toStringAsFixed(0) : '--',
          color: isConnected ? brand.withValues(alpha: 0.8) : cs.onSurface.withValues(alpha: 0.2),
        ),
        const SizedBox(height: 2),
        // RTT
        _StripRow(
          label: 'ms',
          value: isConnected && lastRttMs > 0 ? lastRttMs.toStringAsFixed(0) : '--',
          color: rttColor,
        ),
      ]),
    );
  }
}

class _StripRow extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StripRow({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: 7, color: cs.onSurface.withValues(alpha: 0.3))),
        Text(value, style: TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: color,
            fontFeatures: const [FontFeature.tabularFigures()])),
      ],
    );
  }
}
