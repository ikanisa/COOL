class CollectRuntimeTypography {
  const CollectRuntimeTypography._();

  static const String? fontFamily = null;
  static const String? displayFontFamily = null;
  static const fallbackFamilies = <String>['Inter', 'Roboto'];
  static const displayFallbackFamilies = <String>[
    'Inter Display',
    'Inter',
    'Roboto',
  ];
  static const monoFallbackFamilies = <String>['JetBrains Mono', 'Roboto Mono'];

  static const requiredBlockerKeys = <String>['universal_contract'];

  static const fontFamilyFallback = fallbackFamilies;
  static const displayFontFamilyFallback = displayFallbackFamilies;
  static const monoFontFamilyFallback = monoFallbackFamilies;
}
