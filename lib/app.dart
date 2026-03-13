import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/providers/app_lifecycle_providers.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'l10n/app_localizations.dart';

/// Root application widget.
///
/// Sets up [MaterialApp.router] with:
/// - GoRouter navigation
/// - Dark theme via [AppTheme.dark]
/// - English-only localizations (Rwanda market)
class CoolApp extends ConsumerWidget {
  const CoolApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(appLifecycleBindingProvider);

    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'Cool',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      routerConfig: router,
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    );
  }
}
