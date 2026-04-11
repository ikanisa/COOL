part of 'cool_foundations.dart';

@immutable
class CoolTextStyles {
  const CoolTextStyles._({
    required TextTheme textTheme,
    required Color defaultColor,
  }) : _textTheme = textTheme,
       _defaultColor = defaultColor;

  final TextTheme _textTheme;
  final Color _defaultColor;

  TextTheme get theme => _textTheme;

  TextStyle mono(
    TextStyle? base, {
    Color? color,
    FontWeight? fontWeight,
    double? letterSpacing,
    double? height,
  }) {
    final resolvedBase =
        base ??
        _textTheme.bodyLarge ??
        const TextStyle(fontSize: 18, fontWeight: FontWeight.w700);
    return resolvedBase.copyWith(
      fontFamily: 'DM Mono',
      color: color ?? resolvedBase.color ?? _defaultColor,
      fontWeight: fontWeight ?? resolvedBase.fontWeight,
      letterSpacing: letterSpacing ?? resolvedBase.letterSpacing,
      height: height ?? resolvedBase.height,
    );
  }

  TextStyle mobiLabel({Color? color}) {
    final resolvedBase =
        _textTheme.labelSmall ??
        const TextStyle(
          fontFamily: 'Inter',
          fontSize: 14,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.0,
          height: 1.2,
        );
    final resolvedWeight = resolvedBase.fontWeight;
    final clampedWeight =
        resolvedWeight != null && resolvedWeight.index >= FontWeight.w500.index
        ? resolvedWeight
        : FontWeight.w500;
    final resolvedSize = resolvedBase.fontSize ?? 14;
    return resolvedBase.copyWith(
      fontSize: resolvedSize < 14 ? 14 : resolvedSize,
      fontWeight: clampedWeight,
      color: color ?? resolvedBase.color ?? _defaultColor,
      letterSpacing: resolvedBase.letterSpacing ?? 1.0,
      height: resolvedBase.height ?? 1.2,
    );
  }

  TextStyle mobiValue({Color? color}) {
    return TextStyle(
      fontFamily: 'Manrope',
      fontSize: 14,
      fontWeight: FontWeight.w500,
      color: color ?? _defaultColor,
      letterSpacing: 0.0,
      height: 1.3,
    );
  }

  TextStyle heroNumber({Color? color}) {
    return TextStyle(
      fontFamily: 'Space Grotesk',
      fontSize: 48,
      fontWeight: FontWeight.w800,
      color: color ?? _defaultColor,
      letterSpacing: -1.5,
      height: 0.9,
    );
  }

  /// Space Grotesk — headline authority font.
  /// Use for large-scale labels (w800+) where maximum visual impact is needed.
  TextStyle headline(
    TextStyle? base, {
    Color? color,
    FontWeight? fontWeight,
    double? letterSpacing,
    double? height,
  }) {
    final resolvedBase =
        base ??
        _textTheme.headlineMedium ??
        const TextStyle(fontSize: 28, fontWeight: FontWeight.w800);
    return resolvedBase.copyWith(
      fontFamily: 'Space Grotesk',
      color: color ?? resolvedBase.color ?? _defaultColor,
      fontWeight: fontWeight ?? resolvedBase.fontWeight ?? FontWeight.w800,
      letterSpacing: letterSpacing ?? resolvedBase.letterSpacing ?? -0.5,
      height: height ?? resolvedBase.height,
    );
  }

  /// Manrope — premium editorial font for Title/Body roles.
  /// Geometric nature complements the rounded clay surfaces.
  TextStyle manrope(
    TextStyle? base, {
    Color? color,
    FontWeight? fontWeight,
    double? letterSpacing,
    double? height,
  }) {
    final resolvedBase =
        base ??
        _textTheme.bodyLarge ??
        const TextStyle(fontSize: 16, fontWeight: FontWeight.w500);
    return resolvedBase.copyWith(
      fontFamily: 'Manrope',
      color: color ?? resolvedBase.color ?? _defaultColor,
      fontWeight: fontWeight ?? resolvedBase.fontWeight ?? FontWeight.w500,
      letterSpacing: letterSpacing ?? resolvedBase.letterSpacing,
      height: height ?? resolvedBase.height,
    );
  }

  /// Display — Manrope for structural/editorial body text.
  /// Use for financial values, card titles, and key data points.
  TextStyle display(
    TextStyle? base, {
    Color? color,
    FontWeight? fontWeight,
    double? letterSpacing,
    double? height,
  }) {
    final resolvedBase =
        base ??
        _textTheme.bodyLarge ??
        const TextStyle(fontSize: 18, fontWeight: FontWeight.w500);
    return resolvedBase.copyWith(
      fontFamily: 'Space Grotesk',
      color: color ?? resolvedBase.color ?? _defaultColor,
      fontWeight: fontWeight ?? resolvedBase.fontWeight ?? FontWeight.w500,
      letterSpacing: letterSpacing ?? resolvedBase.letterSpacing,
      height: height ?? resolvedBase.height,
    );
  }

  /// Legacy alias — delegates to [headline] (Space Grotesk).
  /// Prefer [headline] directly for new code.
  TextStyle displayCondensed(
    TextStyle? base, {
    Color? color,
    FontWeight? fontWeight,
    double? letterSpacing,
    double? height,
  }) => headline(
    base,
    color: color,
    fontWeight: fontWeight ?? FontWeight.w800,
    letterSpacing: letterSpacing,
    height: height,
  );
}
