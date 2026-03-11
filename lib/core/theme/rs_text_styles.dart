import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// Rayon Sports FC typography scale.
///
/// Uses Barlow Condensed (weight 800–900) for headings and stats,
/// consistent with the club's strong, condensed branding.
abstract final class RsTextStyles {
  /// Hero / display heading — 48 w900 uppercase.
  static TextStyle display({Color? color}) => GoogleFonts.barlowCondensed(
    fontSize: 48,
    fontWeight: FontWeight.w900,
    color: color ?? AppColors.text,
    height: 1,
  );

  /// Club name heading — 28 w900 uppercase, 1px letter-spacing.
  static TextStyle clubName({Color? color}) => GoogleFonts.barlowCondensed(
    fontSize: 28,
    fontWeight: FontWeight.w900,
    color: color ?? AppColors.text,
    letterSpacing: 1,
    height: 1.1,
  );

  /// Section title — 18 w800 uppercase, 0.5px letter-spacing.
  static TextStyle sectionTitle({Color? color}) => GoogleFonts.barlowCondensed(
    fontSize: 18,
    fontWeight: FontWeight.w800,
    color: color ?? AppColors.text,
    letterSpacing: 0.5,
    height: 1.2,
  );

  /// Match team name — 22 w900 uppercase, tight line-height.
  static TextStyle matchTeam({Color? color}) => GoogleFonts.barlowCondensed(
    fontSize: 22,
    fontWeight: FontWeight.w900,
    color: color ?? AppColors.text,
    height: 1,
  );

  /// Stat value — 22 w800.
  static TextStyle statValue({Color? color}) => GoogleFonts.barlowCondensed(
    fontSize: 22,
    fontWeight: FontWeight.w800,
    color: color ?? AppColors.text,
    height: 1.1,
  );

  /// Badge label — 11 w800 uppercase, 0.5px letter-spacing.
  static TextStyle badge({Color? color}) => GoogleFonts.barlowCondensed(
    fontSize: 11,
    fontWeight: FontWeight.w800,
    color: color ?? AppColors.text,
    letterSpacing: 0.5,
    height: 1.2,
  );
}
