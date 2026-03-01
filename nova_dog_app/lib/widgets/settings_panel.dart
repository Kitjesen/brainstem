import 'dart:ui';
import 'package:flutter/material.dart';

/// Settings panel with glassmorphism effect - shows as a card in bottom-right corner.
class SettingsPanel extends StatefulWidget {
  final bool isDark;
  final VoidCallback onToggleTheme;
  final VoidCallback onToggleLanguage;
  final double textScale;
  final VoidCallback onScaleUp;
  final VoidCallback onScaleDown;

  const SettingsPanel({
    super.key,
    required this.isDark,
    required this.onToggleTheme,
    required this.onToggleLanguage,
    required this.textScale,
    required this.onScaleUp,
    required this.onScaleDown,
  });

  static OverlayEntry? _overlayEntry;

  static void toggle(BuildContext context, {
    required bool isDark,
    required VoidCallback onToggleTheme,
    required VoidCallback onToggleLanguage,
    required double textScale,
    required VoidCallback onScaleUp,
    required VoidCallback onScaleDown,
  }) {
    if (_overlayEntry != null) {
      hide();
      return;
    }

    _overlayEntry = OverlayEntry(
      builder: (ctx) => Positioned(
        left: 88, // Next to sidebar (72px width + 16px margin)
        bottom: 16,
        child: Material(
          color: Colors.transparent,
          child: SettingsPanel(
            isDark: isDark,
            onToggleTheme: onToggleTheme,
            onToggleLanguage: onToggleLanguage,
            textScale: textScale,
            onScaleUp: onScaleUp,
            onScaleDown: onScaleDown,
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  static void hide() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  @override
  State<SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends State<SettingsPanel> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _scaleAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final locale = Localizations.localeOf(context);
    final isChinese = locale.languageCode == 'zh';

    return FadeTransition(
      opacity: _fadeAnimation,
      child: ScaleTransition(
        scale: _scaleAnimation,
        alignment: Alignment.bottomLeft,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              width: 320,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: (widget.isDark ? Colors.black : Colors.white).withValues(alpha: widget.isDark ? 0.5 : 0.7),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: (widget.isDark ? Colors.white : Colors.black).withValues(alpha: 0.08),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 30,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: cs.onSurface.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.settings_rounded,
                          color: cs.onSurface.withValues(alpha: 0.6),
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          isChinese ? '设置' : 'Settings',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: cs.onSurface,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => SettingsPanel.hide(),
                        icon: Icon(
                          Icons.close,
                          color: cs.onSurface.withValues(alpha: 0.5),
                          size: 20,
                        ),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Theme setting
                  _SettingItem(
                    icon: widget.isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                    title: isChinese ? '主题' : 'Theme',
                    subtitle: widget.isDark ? (isChinese ? '深色' : 'Dark') : (isChinese ? '浅色' : 'Light'),
                    trailing: Switch.adaptive(
                      value: widget.isDark,
                      onChanged: (_) => widget.onToggleTheme(),
                      activeColor: cs.primary,
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Language setting
                  _SettingItem(
                    icon: Icons.language_rounded,
                    title: isChinese ? '语言' : 'Language',
                    subtitle: isChinese ? '中文' : 'English',
                    trailing: TextButton(
                      onPressed: widget.onToggleLanguage,
                      style: TextButton.styleFrom(
                        backgroundColor: cs.onSurface.withValues(alpha: 0.08),
                        foregroundColor: cs.onSurface,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        minimumSize: const Size(50, 32),
                      ),
                      child: Text(
                        isChinese ? 'EN' : '中',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Text scale setting
                  _SettingItem(
                    icon: Icons.text_fields_rounded,
                    title: isChinese ? '文字大小' : 'Text Size',
                    subtitle: '${(widget.textScale * 100).toInt()}%',
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          onPressed: widget.textScale > 0.8 ? widget.onScaleDown : null,
                          icon: const Icon(Icons.remove_circle_outline),
                          color: cs.onSurface.withValues(alpha: 0.6),
                          iconSize: 18,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          onPressed: widget.textScale < 1.4 ? widget.onScaleUp : null,
                          icon: const Icon(Icons.add_circle_outline),
                          color: cs.onSurface.withValues(alpha: 0.6),
                          iconSize: 18,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget trailing;

  const _SettingItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.onSurface.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: cs.onSurface.withValues(alpha: 0.06),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: cs.onSurface.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              icon,
              color: cs.onSurface.withValues(alpha: 0.5),
              size: 16,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 10,
                    color: cs.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
          trailing,
        ],
      ),
    );
  }
}
