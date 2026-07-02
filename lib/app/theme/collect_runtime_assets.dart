class CollectRuntimeAssets {
  const CollectRuntimeAssets._();

  static const collectAssetRoot = 'assets/runtime/collect_runtime';
  static const logoAssetRoot = '$collectAssetRoot/logos';
  static const appIconAssetRoot = '$collectAssetRoot/app_icons';
  static const splashAssetRoot = '$collectAssetRoot/splash';
  static const iconAssetRoot = '$collectAssetRoot/icons';
  static const mediaAssetRoot = '$collectAssetRoot/media';
  static const expectedWordmarkPath = '$logoAssetRoot/wordmark.png';
  static const expectedAppIconPath = '$appIconAssetRoot/app_icon.png';
  static const expectedSplashMarkPath = '$splashAssetRoot/splash_mark.png';
  static const expectedSplashBackgroundPath =
      '$splashAssetRoot/splash_background.png';
  static const expectedWebManifestIconPath =
      '$appIconAssetRoot/collect-web-512.png';
  static const expectedSharePreviewPath = '$mediaAssetRoot/share-preview.png';
  static const wordmarkAssetPath = expectedWordmarkPath;
  static const appIconAssetPath = expectedAppIconPath;
  static const splashMarkAssetPath = expectedSplashMarkPath;

  static const currentWebManifestIconPath = 'web/icons/collect-web-512.png';
  static const currentAndroidSplashLogoPath =
      'android/app/src/main/res/drawable/collect_splash_logo.png';
  static const currentAndroidLauncherIconPath =
      'android/app/src/main/res/drawable/collect_launcher_icon.png';
  static const currentIosAppIconSetPath =
      'ios/Runner/Assets.xcassets/AppIcon.appiconset';
  static const currentIosLaunchImageSetPath =
      'ios/Runner/Assets.xcassets/LaunchImage.imageset';

  static const requiredBlockerKeys = <String>[
    'runtime_wordmark_asset',
    'runtime_platform_icon_asset',
    'runtime_splash_launch_asset',
    'runtime_public_web_asset',
    'universal_contract',
  ];
}
