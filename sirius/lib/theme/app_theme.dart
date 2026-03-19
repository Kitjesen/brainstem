import 'package:flutter/material.dart';

/// Brand color presets — minimal, clean palette.
enum BrandColor {
  graphite('Graphite', Color(0xFF334155)),  // Default — stone blue-gray
  slate('Slate', Color(0xFF64748B)),        // Professional gray
  blue('Blue', Color(0xFF3B82F6)),          // Clean blue
  teal('Teal', Color(0xFF14B8A6)),          // Modern teal
  green('Green', Color(0xFF059669)),         // Emerald green
  purple('Purple', Color(0xFF8B5CF6));      // Elegant purple

  final String label;
  final Color color;
  const BrandColor(this.label, this.color);
}

class AppTheme {
  AppTheme._();

  /// Current brand color — mutable, changed via sidebar.
  static Color brand = BrandColor.graphite.color;

  // ── Status colors (semantic) ──────────────────────────────────
  static const Color green  = Color(0xFF059669);  // Success / Online
  static const Color red    = Color(0xFFDC2626);  // Error / Offline
  static const Color orange = Color(0xFFEA580C);  // Warning
  static const Color yellow = Color(0xFFFBBF24);  // Caution
  static const Color teal   = Color(0xFF14B8A6);  // Info accent
  static const Color purple = Color(0xFF8B5CF6);  // Accent

  // ── Light theme — clean white (Linear / Apple style) ─────────
  static const _lBg     = Color(0xFFFAFAFA);  // Near white background
  static const _lCard   = Color(0xFFFFFFFF);  // Pure white cards
  static const _lText   = Color(0xFF0F172A);  // Slate 900 — deep ink
  static const _lGray   = Color(0xFF94A3B8);  // Slate 400 — cool muted
  static const _lBorder = Color(0xFFE2E8F0);  // Slate 200 — subtle cool border
  static const _lHover  = Color(0xFFF1F5F9);  // Slate 100 — light hover

  // ── Dark theme — deep slate ──────────────────────────────────
  static const _dBg     = Color(0xFF0F172A);  // Slate 900 background
  static const _dCard   = Color(0xFF1E293B);  // Slate 800 card
  static const _dText   = Color(0xFFF1F5F9);  // Slate 100 text
  static const _dGray   = Color(0xFF94A3B8);  // Slate 400 muted
  static const _dBorder = Color(0xFF334155);  // Slate 700 border
  static const _dHover  = Color(0xFF283548);  // Slightly lighter hover

  // ── Status colors — dark mode variants ───────────────────────
  static const Color greenDark  = Color(0xFF34D399);
  static const Color redDark    = Color(0xFFF87171);
  static const Color orangeDark = Color(0xFFFBBF24);
  static const Color infoDark   = Color(0xFF60A5FA);

  /// Leg colors — shared constant for all pages (monitor, params, imu).
  static const List<Color> legColors = [
    Color(0xFF059669),  // FL — emerald
    Color(0xFF3B82F6),  // FR — blue
    Color(0xFFEA580C),  // RL — orange
    Color(0xFF8B5CF6),  // RR — purple
  ];

  static const _fallback = ['Microsoft YaHei UI', 'PingFang SC', 'Noto Sans SC', 'sans-serif'];

  static BoxDecoration cardDeco(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return BoxDecoration(
      color: dark ? _dCard : _lCard,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: dark ? _dBorder.withValues(alpha: 0.5) : _lBorder,
        width: 1,
      ),
      boxShadow: dark
        ? const []
        : [
            BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 1)),
            BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 2, offset: const Offset(0, 1)),
          ],
    );
  }

  static ThemeData light([Color? brandOverride]) =>
      _make(Brightness.light, _lBg, _lCard, _lText, _lGray, _lBorder, _lHover, brandOverride ?? brand);
  static ThemeData dark([Color? brandOverride]) =>
      _make(Brightness.dark, _dBg, _dCard, _dText, _dGray, _dBorder, _dHover, brandOverride ?? brand);

  static ThemeData _make(Brightness b, Color bg, Color card, Color text, Color gray,
      Color border, Color hover, Color brandC) {
    final isL = b == Brightness.light;
    return ThemeData(
      brightness: b,
      useMaterial3: true,
      fontFamily: 'Inter',
      fontFamilyFallback: _fallback,
      scaffoldBackgroundColor: bg,
      colorScheme: (isL ? const ColorScheme.light() : const ColorScheme.dark()).copyWith(
        primary: brandC,
        onPrimary: Colors.white,
        surface: card,
        onSurface: text,
        outline: border,
        surfaceContainerHighest: hover,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: EdgeInsets.zero,
      ),
      dividerColor: border,
      textTheme: TextTheme(
        headlineLarge:  TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: text, fontFamilyFallback: _fallback),
        headlineMedium: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: text, fontFamilyFallback: _fallback),
        headlineSmall:  TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: text, fontFamilyFallback: _fallback),
        titleLarge:     TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: text, fontFamilyFallback: _fallback),
        titleMedium:    TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: text, fontFamilyFallback: _fallback),
        bodyLarge:      TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: text, fontFamilyFallback: _fallback),
        bodyMedium:     TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: gray, fontFamilyFallback: _fallback),
        bodySmall:      TextStyle(fontSize: 11, fontWeight: FontWeight.w400, color: gray, fontFamilyFallback: _fallback),
        labelLarge:     TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: text, fontFamilyFallback: _fallback),
        labelMedium:    TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: gray, fontFamilyFallback: _fallback),
        labelSmall:     TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: gray, letterSpacing: 0.5, fontFamilyFallback: _fallback),
      ),
    );
  }
}
