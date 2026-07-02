class CollectRuntimeTypography {
  const CollectRuntimeTypography._();

  static const collectFamily = 'Collect Runtime';
  static const collectDisplayFamily = 'Collect Display';
  static const fallbackFamilies = <String>['Inter', 'Roboto'];
  static const displayFallbackFamilies = <String>[
    'Aeonik Pro',
    'Aeonik',
    'Inter Display',
    'Inter',
    'Roboto',
  ];
  static const monoFallbackFamilies = <String>['JetBrains Mono', 'Roboto Mono'];

  static const requiredBlockerKeys = <String>[
    'runtime_font_files',
    'universal_contract',
  ];

  static const collectFontAssetRoot = 'assets/fonts/collect/';

  static const fontFamily = collectFamily;
  static const displayFontFamily = collectDisplayFamily;
  static const fontFamilyFallback = fallbackFamilies;
  static const displayFontFamilyFallback = displayFallbackFamilies;
  static const monoFontFamilyFallback = monoFallbackFamilies;
}
