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
        logoSemanticLabel: 'Cool app logo',
        primaryColor: const Color(0xFF0047AB),
        secondaryColor: const Color(0xFF89AFFF),
        navSelectedColor: const Color(0xFF0047AB),
      );

  final AppBrand brand;
  final String appTitle;
  final String welcomeTitle;
  final String welcomeSubtitle;
  final String splashTitle;
  final String logoAssetPath;
  final String logoSemanticLabel;
  final Color primaryColor;
  final Color secondaryColor;
  final Color navSelectedColor;
}

final appBrandProvider = Provider<AppBranding>(
  (_) => const AppBranding.cool(),
);
