import 'package:flutter/material.dart';

/// Maps emoji strings (from DB / JSON) to Material Design icons.
///
/// Used at render time so models can keep their `String emoji` field
/// for DB compatibility while the UI displays crisp vector icons.
abstract final class IconMapper {
  /// Returns a [IconData] for the given emoji string.
  /// Falls back to [Icons.star_rounded] for unrecognised values.
  static IconData from(String emoji) => switch (emoji) {
    // ── People & social ──────────────────────────────────────
    '👤' => Icons.person_rounded,
    '👥' => Icons.group_rounded,
    '🤝' => Icons.handshake_rounded,

    // ── Activities & sport ───────────────────────────────────
    '⚽' => Icons.sports_soccer_rounded,
    '🏟️' || '🏟' => Icons.stadium_rounded,
    '🏅' => Icons.military_tech_rounded,
    '🏆' => Icons.emoji_events_rounded,
    '🎯' => Icons.gps_fixed_rounded,

    // ── Vehicles & mobility ─────────────────────────────────
    '🚗' || '🚙' => Icons.directions_car_rounded,
    '🚘' => Icons.directions_car_filled_rounded,
    '🏍️' || '🏍' => Icons.two_wheeler_rounded,
    '🚌' => Icons.directions_bus_rounded,
    '🚐' => Icons.airport_shuttle_rounded,
    '🚛' || '🚚' => Icons.local_shipping_rounded,
    '🛺' => Icons.electric_rickshaw_rounded,
    '🚲' || '🚴' => Icons.pedal_bike_rounded,

    // ── Finance & commerce ──────────────────────────────────
    '💰' => Icons.savings_rounded,
    '💳' => Icons.credit_card_rounded,
    '🏦' => Icons.account_balance_rounded,
    '📲' => Icons.account_balance_wallet_rounded,

    // ── Communication & media ───────────────────────────────
    '📋' => Icons.assignment_rounded,
    '📣' => Icons.campaign_rounded,
    '📱' => Icons.phone_android_rounded,
    '📈' => Icons.trending_up_rounded,
    '📍' => Icons.pin_drop_rounded,
    '📅' => Icons.calendar_month_rounded,

    // ── Objects & symbols ───────────────────────────────────
    '⚡' => Icons.bolt_rounded,
    '⚙️' || '⚙' => Icons.settings_rounded,
    '🌍' => Icons.public_rounded,
    '🔗' => Icons.link_rounded,
    '🔥' => Icons.local_fire_department_rounded,
    '⭐' => Icons.star_rounded,
    '🎫' => Icons.confirmation_number_rounded,
    '🛍️' || '🛍' => Icons.shopping_bag_rounded,
    '🪪' => Icons.badge_rounded,

    // ── Fallback ─────────────────────────────────────────────
    _ => Icons.star_rounded,
  };
}
