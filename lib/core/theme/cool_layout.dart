import 'package:flutter/material.dart';

import 'cool_foundations.dart';

/// Centralized layout constants for the premium COOL mobile system.
abstract final class CoolLayout {
  // ── Margins & Padding ───────────────────────────────────────────────

  /// Standard horizontal page padding.
  static const double horizontalPagePadding = CoolSpace.x6;

  /// Standard vertical page padding.
  static const double verticalPagePadding = CoolSpace.x6;

  /// Standard gutter between cards or large sections.
  static const double gutter = 28.0;

  /// Standard small spacing between elements within a card.
  static const double smallSpacing = CoolSpace.x4;

  // ── Section & List Spacing ──────────────────────────────────────────

  /// Spacing between major screen sections (hero → quick actions → list).
  static const double sectionSpacing = CoolSpace.x6;

  /// Spacing between sibling cards in a vertical list.
  static const double cardListSpacing = CoolSpace.x3;

  /// Spacing between dense list items (e.g., settings rows, ledger entries).
  static const double denseListSpacing = CoolSpace.x2;

  /// Spacing between related inline elements (icon → label, label → value).
  static const double inlineSpacing = CoolSpace.x2;

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

  // ── Content Width Constraints ───────────────────────────────────────

  /// Maximum content width for tablet and desktop breakpoints.
  static const double maxContentWidth = 600.0;

  /// Maximum card width (slightly tighter for dense card grids).
  static const double maxCardWidth = 540.0;

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
  static const double cardRadius = CoolRadii.xl;

  /// Standard border radius for small interactive elements.
  static const double elementRadius = CoolRadii.md;
}

