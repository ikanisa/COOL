class RevolutBorrowedAssets {
  const RevolutBorrowedAssets._();

  static const borrowedAssetRoot = 'assets/brand/revolut_borrowed';
  static const logoAssetRoot = '$borrowedAssetRoot/logos';
  static const appIconAssetRoot = '$borrowedAssetRoot/app_icons';
  static const splashAssetRoot = '$borrowedAssetRoot/splash';
  static const iconAssetRoot = '$borrowedAssetRoot/icons';
  static const mediaAssetRoot = '$borrowedAssetRoot/media';
  static const fallbackBrandRoot = 'assets/brand';

  static const expectedWordmarkPath = '$logoAssetRoot/wordmark.png';
  static const expectedAppIconPath = '$appIconAssetRoot/app_icon.png';
  static const expectedSplashMarkPath = '$splashAssetRoot/splash_mark.png';
  static const expectedSplashBackgroundPath =
      '$splashAssetRoot/splash_background.png';
  static const expectedWebManifestIconPath = '$appIconAssetRoot/web-512.png';
  static const expectedSharePreviewPath = '$mediaAssetRoot/share-preview.png';

  static const wordmarkAssetPath = expectedWordmarkPath;
  static const appIconAssetPath = expectedAppIconPath;
  static const splashMarkAssetPath = expectedSplashMarkPath;

  static const currentWebManifestIconPath = 'web/icons/collect-admin.png';
  static const currentAndroidSplashLogoPath =
      'android/app/src/main/res/drawable/collect_splash_logo.png';
  static const currentAndroidLauncherIconPath =
      'android/app/src/main/res/drawable/collect_launcher_icon.png';
  static const currentIosAppIconSetPath =
      'ios/Runner/Assets.xcassets/AppIcon.appiconset';
  static const currentIosLaunchImageSetPath =
      'ios/Runner/Assets.xcassets/LaunchImage.imageset';

  static const requiredBlockerKeys = <String>[
    'revolut_logo_wordmark_assets',
    'revolut_platform_icon_assets',
    'revolut_splash_launch_assets',
    'revolut_icon_set_mapping',
    'revolut_component_tokens',
    'revolut_route_reference_matrix',
    'revolut_public_web_assets',
  ];
}
