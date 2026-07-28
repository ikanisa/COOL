import 'package:flutter/material.dart';

import 'collect_runtime_typography.dart';

class CollectTypography {
  const CollectTypography._();

  static const fontFamily = CollectRuntimeTypography.fontFamily;

  // This is the only approved text weight scale. Inter is variable, but the
  // product deliberately limits runtime typography to these four roles so
  // browser defaults and one-off screen weights cannot drift into the UI.
  static const FontWeight weightRegular = FontWeight.w400;
  static const FontWeight weightMedium = FontWeight.w500;
  static const FontWeight weightSemibold = FontWeight.w600;
  static const FontWeight weightBold = FontWeight.w700;

  // Shared size roles used by responsive components whose dimensions cannot
  // be represented by a fixed Material TextTheme slot.
  static const double sizeMicro = 9;
  static const double sizeNavigation = 10;
  static const double sizeNavigationSelected = 10.5;
  static const double sizeLabelSmall = 11;
  static const double sizeLabel = 12;
  static const double sizeBodySmall = 14;
  static const double sizeBodyCompact = 15;
  static const double sizeBody = 16;
  static const double sizeBodyLarge = 18;
  static const double sizeTitle = 20;
  static const double sizeLead = 21;
  static const double sizeTitleLarge = 24;
  static const double sizeMetric = 28;
  static const double sizeAction = 30;
  static const double sizePreviewAmount = 32;
  static const double sizePageCompact = 38;
  static const double sizeHeroCompact = 42;
  static const double sizeAmountEntry = 44;
  static const double sizeHero = 48;
  static const double sizePolicyHero = 58;
  static const double sizePublicHero = 68;
  static const double sizeMarketingHero = 72;

  // Shared leading and tracking roles. Text widgets may change colour or
  // decoration locally, but type metrics must come from this layer.
  static const double leadingDense = 0.98;
  static const double leadingSolid = 1;
  static const double leadingDisplay = 1.02;
  static const double leadingDisplayRelaxed = 1.05;
  static const double leadingTitle = 1.08;
  static const double leadingCollectId = 1.12;
  static const double leadingTitleRelaxed = 1.15;
  static const double leadingHero = 1.17;
  static const double leadingCompact = 1.2;
  static const double leadingLabel = 1.25;
  static const double leadingMeta = 1.3;
  static const double leadingLabelCompact = 1.33;
  static const double leadingFine = 1.34;
  static const double leadingSupporting = 1.35;
  static const double leadingSupportingRelaxed = 1.38;
  static const double leadingCard = 1.4;
  static const double leadingResponsiveBody = 1.42;
  static const double leadingIntro = 1.44;
  static const double leadingBody = 1.45;
  static const double leadingBodyComfortable = 1.5;
  static const double leadingBodyLarge = 1.56;

  static const double trackingDefault = 0;
  static const double trackingMeta = 0.5;
  static const double trackingLabel = 0.6;
  static const double trackingEyebrow = 0.8;
  static const double trackingCollectId = 2;

  static const _tabular = <FontFeature>[FontFeature.tabularFigures()];

  static TextTheme textTheme(Color textPrimary, Color textSecondary) {
    return TextTheme(
      displaySmall: _displayStyle(
        sizeHero,
        leadingHero,
        weightBold,
        textPrimary,
      ),
      headlineLarge: _displayStyle(
        sizePreviewAmount,
        leadingLabel,
        weightSemibold,
        textPrimary,
      ),
      headlineMedium: _displayStyle(
        sizeTitleLarge,
        leadingLabelCompact,
        weightSemibold,
        textPrimary,
      ),
      headlineSmall: _displayStyle(
        sizeTitle,
        leadingCard,
        weightSemibold,
        textPrimary,
      ),
      titleLarge: _displayStyle(
        sizeTitle,
        leadingCard,
        weightSemibold,
        textPrimary,
      ),
      titleMedium: _style(
        sizeBody,
        leadingBodyComfortable,
        weightSemibold,
        textPrimary,
      ),
      titleSmall: _style(
        sizeBodySmall,
        leadingBody,
        weightSemibold,
        textPrimary,
      ),
      bodyLarge: _style(
        sizeBodyLarge,
        leadingBodyLarge,
        weightRegular,
        textPrimary,
      ),
      bodyMedium: _style(
        sizeBody,
        leadingBodyComfortable,
        weightRegular,
        textSecondary,
      ),
      bodySmall: _style(
        sizeBodySmall,
        leadingBody,
        weightRegular,
        textSecondary,
      ),
      labelLarge: _style(
        sizeBodySmall,
        leadingMeta,
        weightSemibold,
        textPrimary,
      ),
      labelMedium: _label(sizeLabel, leadingLabelCompact, textSecondary),
      labelSmall: _label(sizeLabelSmall, leadingMeta, textSecondary),
    );
  }

  static TextStyle amountHero(Color color) => _displayStyle(
    sizeHeroCompact,
    leadingDisplay,
    weightBold,
    color,
  ).copyWith(fontFeatures: _tabular);

  static TextStyle amountDisplay(Color color) => _displayStyle(
    sizeHero,
    leadingSolid,
    weightBold,
    color,
  ).copyWith(fontFeatures: _tabular);

  static TextStyle amountLarge(Color color) => _displayStyle(
    sizeMetric,
    leadingTitle,
    weightBold,
    color,
  ).copyWith(fontFeatures: _tabular);

  static TextStyle amountCompact(Color color) => _style(
    sizeBodyCompact,
    leadingLabel,
    weightBold,
    color,
  ).copyWith(fontFeatures: _tabular);

  static TextStyle mono(Color color) => _style(
    sizeLabel,
    leadingLabelCompact,
    weightMedium,
    color,
  ).copyWith(fontFeatures: _tabular, letterSpacing: trackingLabel);

  static TextStyle collectIdDisplay(Color color) => _style(
    sizeMetric,
    leadingCollectId,
    weightBold,
    color,
  ).copyWith(fontFeatures: _tabular, letterSpacing: trackingCollectId);

  static TextStyle transactionMeta(Color color) => _style(
    sizeLabel,
    leadingSupporting,
    weightMedium,
    color,
  ).copyWith(fontFeatures: _tabular, letterSpacing: trackingMeta);

  static TextStyle eyebrowLabel(Color color) => _style(
    sizeLabelSmall,
    leadingMeta,
    weightBold,
    color,
  ).copyWith(letterSpacing: trackingEyebrow);

  static TextStyle responsiveSize(TextStyle base, double size) {
    return base.copyWith(fontFamily: fontFamily, fontSize: size);
  }

  static TextStyle _label(double size, double height, Color color) {
    return _style(
      size,
      height,
      weightMedium,
      color,
    ).copyWith(letterSpacing: trackingLabel);
  }

  static TextStyle _style(
    double size,
    double height,
    FontWeight weight,
    Color color,
  ) {
    return TextStyle(
      fontFamily: CollectRuntimeTypography.fontFamily,
      fontSize: size,
      height: height,
      fontWeight: weight,
      color: color,
      letterSpacing: trackingDefault,
    );
  }

  static TextStyle _displayStyle(
    double size,
    double height,
    FontWeight weight,
    Color color,
  ) {
    return TextStyle(
      fontFamily: CollectRuntimeTypography.displayFontFamily,
      fontSize: size,
      height: height,
      fontWeight: weight,
      color: color,
      letterSpacing: trackingDefault,
    );
  }
}
