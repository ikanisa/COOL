class RevolutBorrowedTypography {
  const RevolutBorrowedTypography._();

  static const borrowedFamily = 'Revolut Borrowed';
  static const fallbackFamilies = <String>['Hanken Grotesk', 'Inter', 'Roboto'];
  static const monoFallbackFamilies = <String>['JetBrains Mono', 'Roboto Mono'];

  static const requiredBlockerKeys = <String>[
    'revolut_font_files',
    'revolut_font_license_metadata',
  ];

  static const borrowedFontAssetRoot = 'assets/fonts/revolut/';

  static const fontFamily = borrowedFamily;
  static const fontFamilyFallback = fallbackFamilies;
  static const monoFontFamilyFallback = monoFallbackFamilies;
}
