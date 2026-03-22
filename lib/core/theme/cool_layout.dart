import 'package:flutter/material.dart';

/// Centralized layout constants for the premium COOL mobile system.
abstract final class CoolLayout {
  // ── Margins & Padding ───────────────────────────────────────────────

  /// Standard horizontal page padding.
  static const double horizontalPagePadding = 24.0;

  /// Standard vertical page padding.
  static const double verticalPagePadding = 24.0;

  /// Standard gutter between cards or large sections.
  static const double gutter = 28.0;

  /// Standard small spacing between elements within a card.
  static const double smallSpacing = 16.0;

  // ── Bottom Navigation Clearances ─────────────────────────────────────

  /// Height of the bottom navigation bar chrome.
  static const double bottomNavHeight = 88.0;

  /// Additional margin to ensure content doesn't touch the nav bar.
  static const double bottomNavMargin = 40.0;

  /// Total clearance required at the bottom of root scroll views (110px).
  /// Combines [bottomNavHeight] + [bottomNavMargin].
  static const double rootBottomClearance = bottomNavHeight + bottomNavMargin;

  /// Height from bottom where Floating Action Buttons should sit.
  static const double fabBottomClearance = 92.0;

  // ── Convenience Helpers ──────────────────────────────────────────────

  /// Root-level list padding (Left, Top, Right, Bottom).
  /// Use this for primary scroll views in the 5 main tabs.
  static const EdgeInsets rootPagePadding = EdgeInsets.fromLTRB(
    horizontalPagePadding,
    verticalPagePadding,
    horizontalPagePadding,
    rootBottomClearance,
  );

  /// Standard border radius for large cards.
  static const double cardRadius = 32.0;

  /// Standard border radius for small interactive elements.
  static const double elementRadius = 20.0;
}
