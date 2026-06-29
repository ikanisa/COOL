class CollectRuntimeTypography {
  const CollectRuntimeTypography._();

  static const collectFamily = 'Collect Runtime';
  static const fallbackFamilies = <String>['Hanken Grotesk', 'Inter', 'Roboto'];
  static const monoFallbackFamilies = <String>['JetBrains Mono', 'Roboto Mono'];

  static const requiredBlockerKeys = <String>[
    'collect_font_files',
    'collect_font_license_metadata',
  ];

  static const collectFontAssetRoot = 'assets/fonts/collect/';

  static const fontFamily = collectFamily;
  static const fontFamilyFallback = fallbackFamilies;
  static const monoFontFamilyFallback = monoFallbackFamilies;
}
