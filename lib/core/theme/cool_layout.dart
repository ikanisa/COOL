import 'package:flutter/material.dart';

/// Centralized layout constants following the Rule of 4 and 
/// Soft Liquid Glass design system.
abstract final class CoolLayout {
  // ── Margins & Padding ───────────────────────────────────────────────
  
  /// Standard horizontal page padding (18px based on home screen).
  static const double horizontalPagePadding = 18.0;
  
  /// Standard vertical page padding (18px based on home screen).
  static const double verticalPagePadding = 18.0;
  
  /// Standard gutter between cards or large sections (rule of 4: 16px or 24px).
  static const double gutter = 24.0;
  
  /// Standard small spacing between elements within a card (12px).
  static const double smallSpacing = 12.0;

  // ── Bottom Navigation Clearances ─────────────────────────────────────
  
  /// Height of the bottom navigation bar chrome (standard 72px).
  static const double bottomNavHeight = 72.0;
  
  /// Additional margin to ensure content doesn't touch the nav bar (38px).
  static const double bottomNavMargin = 38.0;
  
  /// Total clearance required at the bottom of root scroll views (110px).
  /// Combines [bottomNavHeight] + [bottomNavMargin].
  static const double rootBottomClearance = bottomNavHeight + bottomNavMargin;

  /// Height from bottom where Floating Action Buttons should sit to
  /// clear the bottom navigation (80px).
  static const double fabBottomClearance = 80.0;

  // ── Convenience Helpers ──────────────────────────────────────────────
  
  /// Root-level list padding (Left, Top, Right, Bottom).
  /// Use this for primary scroll views in the 5 main tabs.
  static const EdgeInsets rootPagePadding = EdgeInsets.fromLTRB(
    horizontalPagePadding,
    verticalPagePadding,
    horizontalPagePadding,
    rootBottomClearance,
  );

  /// Standard border radius for large cards (28px).
  static const double cardRadius = 28.0;

  /// Standard border radius for small interactive elements (14px).
  static const double elementRadius = 14.0;
}
