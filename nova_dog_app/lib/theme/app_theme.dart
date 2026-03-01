import 'package:flutter/material.dart';

/// Available brand color presets - minimal, professional palette.
enum BrandColor {
  slate('Slate', Color(0xFF64748B)),      // Professional gray-blue
  blue('Blue', Color(0xFF3B82F6)),        // Clean blue
  teal('Teal', Color(0xFF14B8A6)),        // Modern teal
  green('Green', Color(0xFF10B981)),      // Fresh green
  orange('Orange', Color(0xFFF97316)),    // Warm orange
  purple('Purple', Color(0xFF8B5CF6));    // Elegant purple

  final String label;
  final Color color;
  const BrandColor(this.label, this.color);
}

class AppTheme {
  AppTheme._();

  /// Current brand color — mutable, changed via sidebar.
  static Color brand = BrandColor.slate.color;

  // Minimal status colors - only essential states
  static const Color green = Color(0xFF10B981);   // Success/Online
  static const Color red = Color(0xFFEF4444);     // Error/Offline
  static const Color orange = Color(0xFFF97316);  // Warning
  static const Color yellow = Color(0xFFFBBF24);  // Caution
  static const Color teal = Color(0xFF14B8A6);    // Info
  static const Color purple = Color(0xFF8B5CF6);  // Accent

  // Soft background colors - not pure white/black
  static const _lBg = Color(0xFFF5F7FA);      // Soft gray-blue instead of pure white
  static const _lCard = Color(0xFFFAFBFC);    // Very light gray instead of white
  static const _lText = Color(0xFF1A1D1F);    // Soft black instead of pure black
  static const _lGray = Color(0xFF6B7280);    // Medium gray
  static const _dBg = Color(0xFF0F1419);      // Slightly lighter than pure black
  static const _dCard = Color(0xFF1A1F2E);    // Soft dark blue-gray
  static const _dText = Color(0xFFE8EAED);    // Soft white instead of pure white
  static const _dGray = Color(0xFF9CA3AF);    // Light gray

  static const _fallback = ['Microsoft YaHei UI', 'PingFang SC', 'Noto Sans SC', 'sans-serif'];

  static BoxDecoration cardDeco(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return BoxDecoration(
      color: dark ? _dCard : _lCard,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        color: dark
          ? Colors.white.withValues(alpha: 0.05)
          : Colors.black.withValues(alpha: 0.04),
        width: 1,
      ),
      boxShadow: dark
        ? [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ]
        : [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 2),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
    );
  }

  static ThemeData light([Color? brandOverride]) => _make(Brightness.light, _lBg, _lCard, _lText, _lGray, brandOverride ?? brand);
  static ThemeData dark([Color? brandOverride]) => _make(Brightness.dark, _dBg, _dCard, _dText, _dGray, brandOverride ?? brand);

  static ThemeData _make(Brightness b, Color bg, Color card, Color text, Color gray, Color brandC) {
    final isL = b == Brightness.light;
    return ThemeData(
      brightness: b,
      useMaterial3: true,
      fontFamily: 'Inter',
      fontFamilyFallback: _fallback,
      scaffoldBackgroundColor: bg,
      colorScheme: (isL ? const ColorScheme.light() : const ColorScheme.dark()).copyWith(
        primary: brandC, onPrimary: Colors.white, surface: card, onSurface: text,
        outline: isL ? const Color(0xFFE5E7EB) : const Color(0xFF374151),
        surfaceContainerHighest: isL ? _lCard : _dCard,
      ),
      cardTheme: CardThemeData(elevation: 0, color: card, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), margin: EdgeInsets.zero),
      dividerColor: isL ? const Color(0xFFE5E7EB) : const Color(0xFF374151),
      textTheme: TextTheme(
        headlineLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: text, fontFamilyFallback: _fallback),
        headlineMedium: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: text, fontFamilyFallback: _fallback),
        headlineSmall: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: text, fontFamilyFallback: _fallback),
        titleLarge: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: text, fontFamilyFallback: _fallback),
        titleMedium: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: text, fontFamilyFallback: _fallback),
        bodyLarge: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: text, fontFamilyFallback: _fallback),
        bodyMedium: TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: gray, fontFamilyFallback: _fallback),
        bodySmall: TextStyle(fontSize: 11, fontWeight: FontWeight.w400, color: gray, fontFamilyFallback: _fallback),
        labelLarge: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: text, fontFamilyFallback: _fallback),
        labelMedium: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: gray, fontFamilyFallback: _fallback),
        labelSmall: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: gray, letterSpacing: 0.5, fontFamilyFallback: _fallback),
      ),
    );
  }
}
