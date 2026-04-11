import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum AppBrand { cool }

@immutable
class AppBranding {
  const AppBranding({
    required this.brand,
    required this.appTitle,
    required this.welcomeTitle,
    required this.welcomeSubtitle,
    required this.splashTitle,
    required this.logoAssetPath,
    required this.logoTransparentAssetPath,
    required this.logoDarkAssetPath,
    required this.logoSemanticLabel,
    required this.primaryColor,
    required this.secondaryColor,
    required this.navSelectedColor,
  });

  const AppBranding.cool()
    : this(
        brand: AppBrand.cool,
        appTitle: 'Cool',
        welcomeTitle: 'Welcome to COOL',
        welcomeSubtitle: 'Pay, save, and move.',
        splashTitle: 'Cool',
        logoAssetPath: 'assets/images/cool_logo_mark.png',
        logoTransparentAssetPath: 'assets/images/cool_logo_mark_transparent.png',
        logoDarkAssetPath: 'assets/images/cool_logo_mark_dark.png',
        logoSemanticLabel: 'Cool app logo',
        primaryColor: const Color(0xFF6C63FF),
        secondaryColor: const Color(0xFF8982FF),
        navSelectedColor: const Color(0xFF6C63FF),
      );

  final AppBrand brand;
  final String appTitle;
  final String welcomeTitle;
  final String welcomeSubtitle;
  final String splashTitle;
  final String logoAssetPath;
  /// Logo on transparent background — for compositing.
  final String logoTransparentAssetPath;
  /// Logo on dark void background (#0D0A27) — for in-app dark surfaces.
  final String logoDarkAssetPath;
  final String logoSemanticLabel;
  final Color primaryColor;
  final Color secondaryColor;
  final Color navSelectedColor;
}

final appBrandProvider = Provider<AppBranding>(
  (_) => const AppBranding.cool(),
);
