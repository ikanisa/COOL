import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/l10n/l10n.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/cool_foundations.dart';
import '../core/theme/theme_preference.dart';
import '../core/theme/theme_preference_provider.dart';
import '../core/theme/theme_system_chrome.dart';
import '../l10n/app_localizations.dart';
import '../shared/widgets/startup_loading_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// BootstrapShell — minimal MaterialApp used before ProviderScope is ready.
// ─────────────────────────────────────────────────────────────────────────────

class BootstrapShell extends StatelessWidget {
  const BootstrapShell({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final appTitle = lookupAppLocalizations(
      const Locale('en'),
    ).bootstrapCoolTitle;
    return MaterialApp(
      title: appTitle,
      debugShowCheckedModeBanner: false,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      builder: (context, materialChild) =>
          ThemeSystemChrome(child: materialChild ?? const SizedBox.shrink()),
      home: child,
    );
  }
}

class BootstrapStageTransition extends StatelessWidget {
  const BootstrapStageTransition({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final duration = CoolMotion.resolve(context, CoolMotion.standard);
    final enterCurve = CoolMotion.resolveCurve(context, CoolMotion.enterCurve);
    final exitCurve = CoolMotion.resolveCurve(context, CoolMotion.exitCurve);

    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: enterCurve,
      switchOutCurve: exitCurve,
      layoutBuilder: (currentChild, previousChildren) => Stack(
        fit: StackFit.expand,
        children: [
          ...previousChildren,
          ...?(currentChild == null ? null : <Widget>[currentChild]),
        ],
      ),
      transitionBuilder: (child, animation) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: enterCurve,
          reverseCurve: exitCurve,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.02),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

class BootstrapResultReveal extends StatefulWidget {
  const BootstrapResultReveal({required this.child, super.key});

  final Widget child;

  @override
  State<BootstrapResultReveal> createState() => _BootstrapResultRevealState();
}

class _BootstrapResultRevealState extends State<BootstrapResultReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  late final Animation<double> _opacity = CurvedAnimation(
    parent: _controller,
    curve: CoolMotion.enterCurve,
  );

  bool _didStart = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (CoolMotion.isReducedMotion(context)) {
      _controller.value = 1;
      return;
    }
    if (_didStart) {
      return;
    }
    _didStart = true;
    unawaited(_controller.forward());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: StartupLoadingScreen.nativeSplashBackgroundColor,
      child: FadeTransition(opacity: _opacity, child: widget.child),
    );
  }
}

class BootstrapHoldScreen extends StatefulWidget {
  const BootstrapHoldScreen({
    required this.statusLabel,
    required this.onSurfaceReady,
    super.key,
  });

  final String statusLabel;
  final VoidCallback onSurfaceReady;

  @override
  State<BootstrapHoldScreen> createState() => _BootstrapHoldScreenState();
}

class _BootstrapHoldScreenState extends State<BootstrapHoldScreen> {
  bool _didPrepareSurface = false;
  bool _didNotifySurfaceReady = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didPrepareSurface) {
      return;
    }
    _didPrepareSurface = true;
    unawaited(_prepareSurface());
  }

  Future<void> _prepareSurface() async {
    try {
      const imageProvider = AssetImage(
        'assets/images/cool_logo_mark_splash_transparent.png',
      );
      await precacheImage(imageProvider, context);
    } catch (_) {
      // If asset precaching fails, still release the native splash after the
      // first Flutter frame so startup cannot deadlock behind the launch theme.
    }
    if (!mounted || _didNotifySurfaceReady) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _didNotifySurfaceReady) {
        return;
      }
      _didNotifySurfaceReady = true;
      widget.onSurfaceReady();
    });
  }

  @override
  Widget build(BuildContext context) {
    return StartupLoadingScreen(
      statusLabel: widget.statusLabel,
      matchNativeSplash: true,
    );
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
      icon: CoolIcons.warning,
      title: context.l10n.bootstrapStartupBlocked,
      message: message,
      footer: FilledButton(
        onPressed: onRetry,
        child: Text(context.l10n.bootstrapRetryStartup),
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
    final appTitle = lookupAppLocalizations(
      const Locale('en'),
    ).bootstrapCoolTitle;

    return MaterialApp(
      title: appTitle,
      debugShowCheckedModeBanner: false,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themePreference.themeMode,
      builder: (context, child) =>
          ThemeSystemChrome(child: child ?? const SizedBox.shrink()),
      home: Builder(
        builder: (context) => _ErrorCardScaffold(
          icon: CoolIcons.settingsRounded,
          title: context.l10n.bootstrapBackendConfigurationRequired,
          message: message,
          footer: Text(
            context.l10n.bootstrapLocalRunsNeedEnv,
            style: context.coolText
                .mobiLabel(color: context.coolSemanticColors.tertiaryText)
                .copyWith(height: 1.4),
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
