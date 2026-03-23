import 'package:flutter/material.dart';

import '../../../../core/theme/cool_foundations.dart';
import '../../../../core/theme/rs_colors.dart';
import '../models/rs_models.dart';

/// Categories for club support initiatives.
enum InitiativeCategory { community, infrastructure, youth, matchday, charity }

/// Rayon Sports FC design helpers.
///
/// Maps domain enums (tiers, categories) to branded colours and labels.
abstract final class RsTheme {
  // ── Tier → colour ──────────────────────────────────────────────────

  /// Returns the accent colour for a membership tier.
  static Color tierColor(FanTier tier) => switch (tier) {
    FanTier.platinum => const Color(0xFFC8DCFF),
    FanTier.gold => RsColors.rsGoldLight,
    FanTier.silver => const Color(0xFFC8C8E0),
    FanTier.blue => RsColors.rsBlueLight,
  };

  /// Returns a semi-transparent background tinted to [tier].
  static Color tierBackground(FanTier tier) =>
      tierColor(tier).withValues(alpha: 0.12);

  /// Returns a display label for [tier], e.g. "PLATINUM".
  static String tierLabel(FanTier tier) => switch (tier) {
    FanTier.platinum => 'PLATINUM',
    FanTier.gold => 'GOLD',
    FanTier.silver => 'SILVER',
    FanTier.blue => 'BLUE',
  };

  // ── Initiative category → colour ───────────────────────────────────

  /// Returns the accent colour for an initiative category.
  static Color categoryColor(InitiativeCategory cat) => switch (cat) {
    InitiativeCategory.community => CoolSemanticColors.light.accent,
    InitiativeCategory.infrastructure => CoolSemanticColors.light.info,
    InitiativeCategory.youth => CoolSemanticColors.light.teamSurface,
    InitiativeCategory.matchday => CoolSemanticColors.light.warning,
    InitiativeCategory.charity => RsColors.rsGold,
  };

  /// Returns a semi-transparent background tinted to [cat].
  static Color categoryBackground(InitiativeCategory cat) =>
      categoryColor(cat).withValues(alpha: 0.12);

  /// Parses a raw category string into [InitiativeCategory].
  ///
  /// Falls back to [InitiativeCategory.community] for unknown values.
  static InitiativeCategory parseCategory(String? value) {
    if (value == null || value.isEmpty) return InitiativeCategory.community;
    return InitiativeCategory.values.firstWhere(
      (c) => c.name == value,
      orElse: () => InitiativeCategory.community,
    );
  }
}
