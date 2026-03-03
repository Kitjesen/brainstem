import 'package:flutter/material.dart';

/// Common spacing constants to ensure consistency.
class AppSpacing {
  AppSpacing._();

  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 20.0;
  static const double xxl = 24.0;
  static const double xxxl = 32.0;
}

/// Common border radius constants.
class AppRadius {
  AppRadius._();

  static const double sm = 6.0;
  static const double md = 10.0;
  static const double lg = 14.0;
  static const double xl = 16.0;
  static const double xxl = 20.0;

  static BorderRadius get smBorderRadius => BorderRadius.circular(sm);
  static BorderRadius get mdBorderRadius => BorderRadius.circular(md);
  static BorderRadius get lgBorderRadius => BorderRadius.circular(lg);
  static BorderRadius get xlBorderRadius => BorderRadius.circular(xl);
  static BorderRadius get xxlBorderRadius => BorderRadius.circular(xxl);
}

/// Common animation durations.
class AppDuration {
  AppDuration._();

  static const Duration fast = Duration(milliseconds: 100);
  static const Duration normal = Duration(milliseconds: 200);
  static const Duration slow = Duration(milliseconds: 300);
}

/// Common size boxes for spacing.
class AppGaps {
  AppGaps._();

  static const SizedBox xs = SizedBox(width: AppSpacing.xs, height: AppSpacing.xs);
  static const SizedBox sm = SizedBox(width: AppSpacing.sm, height: AppSpacing.sm);
  static const SizedBox md = SizedBox(width: AppSpacing.md, height: AppSpacing.md);
  static const SizedBox lg = SizedBox(width: AppSpacing.lg, height: AppSpacing.lg);
  static const SizedBox xl = SizedBox(width: AppSpacing.xl, height: AppSpacing.xl);
  static const SizedBox xxl = SizedBox(width: AppSpacing.xxl, height: AppSpacing.xxl);
  static const SizedBox xxxl = SizedBox(width: AppSpacing.xxxl, height: AppSpacing.xxxl);

  static const SizedBox hXs = SizedBox(width: AppSpacing.xs);
  static const SizedBox hSm = SizedBox(width: AppSpacing.sm);
  static const SizedBox hMd = SizedBox(width: AppSpacing.md);
  static const SizedBox hLg = SizedBox(width: AppSpacing.lg);
  static const SizedBox hXl = SizedBox(width: AppSpacing.xl);
  static const SizedBox hXxl = SizedBox(width: AppSpacing.xxl);

  static const SizedBox vXs = SizedBox(height: AppSpacing.xs);
  static const SizedBox vSm = SizedBox(height: AppSpacing.sm);
  static const SizedBox vMd = SizedBox(height: AppSpacing.md);
  static const SizedBox vLg = SizedBox(height: AppSpacing.lg);
  static const SizedBox vXl = SizedBox(height: AppSpacing.xl);
  static const SizedBox vXxl = SizedBox(height: AppSpacing.xxl);
}
