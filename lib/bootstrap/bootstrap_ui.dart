import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../core/theme/cool_foundations.dart';
import '../core/theme/theme_preference.dart';
import '../core/theme/theme_preference_provider.dart';
import '../core/theme/theme_system_chrome.dart';

// ─────────────────────────────────────────────────────────────────────────────
// BootstrapShell — minimal MaterialApp used before ProviderScope is ready.
// ─────────────────────────────────────────────────────────────────────────────

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

// ─────────────────────────────────────────────────────────────────────────────
// BootstrapHoldScreen — opaque dark screen shown while the native splash
// covers bootstrap. Never visible to the user in the normal flow.
// ─────────────────────────────────────────────────────────────────────────────

class BootstrapHoldScreen extends StatelessWidget {
  const BootstrapHoldScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Match the native splash background (#0D0A27) exactly so there
    // is zero visual discontinuity if the native splash is removed
    // before the CoolApp is ready (edge case on very fast devices).
    return const ColoredBox(color: Color(0xFF0D0A27));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BootstrapErrorCard — shown only when startup fails.
// The native splash has already been removed at this point.
// ─────────────────────────────────────────────────────────────────────────────

class BootstrapErrorCard extends StatelessWidget {
  const BootstrapErrorCard({
    required this.message,
    required this.onRetry,
    super.key,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return _ErrorCardScaffold(
      icon: Icons.warning_amber_rounded,
      title: 'Startup blocked',
      message: message,
      footer: FilledButton(
        onPressed: onRetry,
        child: const Text('Retry startup'),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ConfigErrorApp — shown when env config is missing/invalid (dev builds).
// ─────────────────────────────────────────────────────────────────────────────

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
        builder: (context) => _ErrorCardScaffold(
          icon: Icons.settings_rounded,
          title: 'Backend configuration required',
          message: message,
          footer: Text(
            'Local runs usually need '
            '--dart-define-from-file=.env.json',
            style: context.coolText.mobiLabel(
              color: context.coolSemanticColors.tertiaryText,
            ).copyWith(height: 1.4),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _ErrorCardScaffold — shared layout for all pre-app error surfaces.
// ─────────────────────────────────────────────────────────────────────────────

class _ErrorCardScaffold extends StatelessWidget {
  const _ErrorCardScaffold({
    required this.icon,
    required this.title,
    required this.message,
    this.footer,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? footer;

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
                      Icon(icon, color: colors.danger, size: 32),
                      const SizedBox(height: CoolSpace.x4),
                      Text(
                        title,
                        style: context.coolText.display(
                          null,
                          color: colors.primaryText,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: CoolSpace.x3),
                      Text(
                        message,
                        style: context.coolText.manrope(
                          null,
                          color: colors.secondaryText,
                          height: 1.45,
                        ),
                      ),
                      if (footer != null) ...[
                        const SizedBox(height: CoolSpace.x5),
                        footer!,
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
