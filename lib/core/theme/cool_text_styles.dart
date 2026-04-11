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
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
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
      letterSpacing: resolvedBase.letterSpacing ?? 0,
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
      fontFamily: 'Manrope',
      fontSize: 36,
      fontWeight: FontWeight.w700,
      color: color ?? _defaultColor,
      letterSpacing: -0.8,
      height: 1.0,
    );
  }

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
        const TextStyle(fontSize: 20, fontWeight: FontWeight.w600);
    return resolvedBase.copyWith(
      fontFamily: 'Manrope',
      color: color ?? resolvedBase.color ?? _defaultColor,
      fontWeight: fontWeight ?? resolvedBase.fontWeight ?? FontWeight.w600,
      letterSpacing: letterSpacing ?? resolvedBase.letterSpacing ?? -0.1,
      height: height ?? resolvedBase.height,
    );
  }

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
      fontFamily: 'Manrope',
      color: color ?? resolvedBase.color ?? _defaultColor,
      fontWeight: fontWeight ?? resolvedBase.fontWeight ?? FontWeight.w600,
      letterSpacing: letterSpacing ?? resolvedBase.letterSpacing,
      height: height ?? resolvedBase.height,
    );
  }

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
