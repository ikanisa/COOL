import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_performance/firebase_performance.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config/env_config.dart';
import 'core/services/app_check_service.dart';
import 'core/services/firebase_bootstrap_service.dart';
import 'core/services/hive_runtime.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/cool_foundations.dart';
import 'core/theme/theme_preference.dart';
import 'core/theme/theme_preference_provider.dart';
import 'core/theme/theme_preference_store.dart';
import 'core/theme/theme_system_chrome.dart';
import 'core/l10n/l10n.dart';

Future<void> main() async {
  // ── Run everything inside runZonedGuarded so the binding, init, and
  //    runApp all share the same zone — prevents zone mismatch errors
  //    that break touch event delivery. ───────────────────────────────
  runZonedGuarded(
    () async {
      final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
      FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

      // ── Disable runtime font fetching (fonts bundled in assets) ──────
      GoogleFonts.config.allowRuntimeFetching = false;

      // ── Env validation ──────────────────────────────────────────────
      EnvConfig.logWarnings();

      // ── Firebase (deterministic init) ───────────────────────────────
      await FirebaseBootstrapService.ensureInitialized();

      // ── App Check (attestation) ─────────────────────────────────────
      await AppCheckService.initialize();

      // ── Cold start performance trace ────────────────────────────────
      Trace? coldStartTrace;
      if (Firebase.apps.isNotEmpty && !kDebugMode) {
        try {
          coldStartTrace = FirebasePerformance.instance.newTrace(
            'app_cold_start',
          );
          await coldStartTrace.start();
        } catch (_) {}
      }

      // ── Crashlytics error handlers ──────────────────────────────────
      if (Firebase.apps.isNotEmpty) {
        FlutterError.onError = (details) {
          FlutterError.presentError(details);
          if (!kDebugMode) {
            FirebaseCrashlytics.instance.recordFlutterFatalError(details);
          }
        };
        PlatformDispatcher.instance.onError = (error, stack) {
          if (kDebugMode) {
            return false;
          }
          FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
          return true;
        };
      }

      // Intentional: portrait-only for mobile-first finance app.
      // This is a product decision — financial flows (MoMo, credit, wallet)
      // are designed for single-column portrait layout. Landscape would
      // require significant adaptive layout work with minimal user value.
      // Decision documented in docs/PERFORMANCE_BUDGETS.md § Portrait Lock.
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);

      final configError = EnvConfig.criticalConfigurationError;
      if (configError == null) {
        await Supabase.initialize(
          url: EnvConfig.supabaseUrl,
          anonKey: EnvConfig.supabaseAnonKey,
        );
      } else {
        debugPrint('[EnvConfig] ❌ $configError');
      }

      // ── Hive (local storage) ────────────────────────────────────────
      await initializeHiveRuntime();
      final themePreferenceStore = HiveThemePreferenceStore(
        openBox: openHiveBox<String>,
      );
      final initialPreference = await themePreferenceStore.read();

      // ── Stop cold start trace ───────────────────────────────────────
      try {
        await coldStartTrace?.stop();
      } catch (_) {}

      // ── Branded error widget (replaces red screen in release) ───────
      if (!kDebugMode) {
        ErrorWidget.builder = (FlutterErrorDetails details) {
          return const Material(
            color: Color(0xFF0A0A0F),
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 48,
                      color: Color(0xFFFF4D6A),
                    ),
                    SizedBox(height: CoolSpace.x4),
                    Text(
                      'Something went wrong',
                      style: TextStyle(
                        color: Color(0xFFF0F0F5),
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    SizedBox(height: CoolSpace.x2),
                    Text(
                      'Please restart the app.',
                      style: TextStyle(
                        color: Color(0xFF8888A0),
                        fontSize: 14,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        };
      }

      // ── Remove native splash ───────────────────────────────────────
      FlutterNativeSplash.remove();

      // ── Launch app ──────────────────────────────────────────────────
      runApp(
        ProviderScope(
          overrides: [
            themePreferenceStoreProvider.overrideWithValue(
              themePreferenceStore,
            ),
            initialThemePreferenceProvider.overrideWithValue(initialPreference),
          ],
          child: configError == null
              ? const CoolApp()
              : ConfigErrorApp(message: configError),
        ),
      );
    },
    (error, stack) {
      debugPrint('[Uncaught] $error\n$stack');
      if (Firebase.apps.isNotEmpty) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      }
    },
  );
}

class ConfigErrorApp extends ConsumerWidget {
  const ConfigErrorApp({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themePreference = ref.watch(themePreferenceProvider);

    return MaterialApp(
      title: context.l10n.cool,
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
