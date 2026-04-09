import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../core/theme/cool_foundations.dart';
import '../core/theme/theme_preference.dart';
import '../core/theme/theme_preference_provider.dart';
import '../core/theme/theme_system_chrome.dart';

class BootstrapShell extends StatelessWidget {
  const BootstrapShell({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'COOL',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      builder: (context, materialChild) =>
          ThemeSystemChrome(child: materialChild ?? const SizedBox.shrink()),
      home: child,
    );
  }
}

class BootstrapMessageCard extends StatelessWidget {
  const BootstrapMessageCard({
    required this.title,
    required this.message,
    required this.isBusy,
    required this.onRetry,
    super.key,
  });

  final String title;
  final String message;
  final bool isBusy;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;

    return Scaffold(
      backgroundColor: colors.appBackground,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.elevatedBackground,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: colors.borderStrong),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        isBusy
                            ? Icons.hourglass_top_rounded
                            : Icons.warning_amber_rounded,
                        color: isBusy ? colors.accent : colors.danger,
                        size: 32,
                      ),
                      const SizedBox(height: CoolSpace.x4),
                      Text(
                        title,
                        style: TextStyle(
                          color: colors.primaryText,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: CoolSpace.x3),
                      Text(
                        message,
                        style: TextStyle(
                          color: colors.secondaryText,
                          fontSize: 14,
                          height: 1.45,
                        ),
                      ),
                      if (isBusy) ...[
                        const SizedBox(height: CoolSpace.x4),
                        const Center(
                          child: CircularProgressIndicator.adaptive(),
                        ),
                      ],
                      if (!isBusy && onRetry != null) ...[
                        const SizedBox(height: CoolSpace.x5),
                        FilledButton(
                          onPressed: onRetry,
                          child: const Text('Retry startup'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ConfigErrorApp extends ConsumerWidget {
  const ConfigErrorApp({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themePreference = ref.watch(themePreferenceProvider);

    return MaterialApp(
      title: 'COOL',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themePreference.themeMode,
      builder: (context, child) =>
          ThemeSystemChrome(child: child ?? const SizedBox.shrink()),
      home: Builder(
        builder: (context) {
          final colors = context.coolSemanticColors;
          return Scaffold(
            backgroundColor: colors.appBackground,
            body: SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.elevatedBackground,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: colors.borderStrong),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.settings_rounded,
                              color: colors.danger,
                              size: 32,
                            ),
                            const SizedBox(height: CoolSpace.x4),
                            Text(
                              'Backend configuration required',
                              style: TextStyle(
                                color: colors.primaryText,
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: CoolSpace.x3),
                            Text(
                              message,
                              style: TextStyle(
                                color: colors.secondaryText,
                                fontSize: 14,
                                height: 1.45,
                              ),
                            ),
                            const SizedBox(height: CoolSpace.x4),
                            Text(
                              'Local runs usually need'
                              '--dart-define-from-file=.env.json',
                              style: TextStyle(
                                color: colors.tertiaryText,
                                fontSize: 13,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
