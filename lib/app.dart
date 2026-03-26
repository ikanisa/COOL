import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/brand/app_brand.dart';
import 'core/providers/app_lifecycle_providers.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_preference.dart';
import 'core/theme/theme_preference_provider.dart';
import 'core/theme/theme_system_chrome.dart';
import 'l10n/app_localizations.dart';

/// Root application widget.
///
/// Sets up [MaterialApp.router] with:
/// - GoRouter navigation
/// - App theme mode via [themePreferenceProvider]
/// - English-only localizations (Rwanda market)
class CoolApp extends ConsumerWidget {
  const CoolApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(appLifecycleBindingProvider);

    final brand = ref.watch(appBrandProvider);
    final router = ref.watch(appRouterProvider);
    final themePreference = ref.watch(themePreferenceProvider);

    return MaterialApp.router(
      title: brand.appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themePreference.themeMode,
      builder: (context, child) =>
          ThemeSystemChrome(child: child ?? const SizedBox.shrink()),
      routerConfig: router,
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    );
  }
}
