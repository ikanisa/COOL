import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_performance/firebase_performance.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config/env_config.dart';
import 'core/services/app_check_service.dart';
import 'core/services/firebase_bootstrap_service.dart';
import 'core/theme/app_theme.dart';

Future<void> main() async {
  // ── Run everything inside runZonedGuarded so the binding, init, and
  //    runApp all share the same zone — prevents zone mismatch errors
  //    that break touch event delivery. ───────────────────────────────
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

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

      // ── System chrome ───────────────────────────────────────────────
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          systemNavigationBarColor: Color(0xFF0A0A0F),
          systemNavigationBarIconBrightness: Brightness.light,
        ),
      );

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
      await Hive.initFlutter();

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
                    SizedBox(height: 16),
                    Text(
                      'Something went wrong',
                      style: TextStyle(
                        color: Color(0xFFF0F0F5),
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    SizedBox(height: 8),
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

      // ── Launch app ──────────────────────────────────────────────────
      runApp(
        ProviderScope(
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

class ConfigErrorApp extends StatelessWidget {
  const ConfigErrorApp({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cool',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: Scaffold(
        backgroundColor: const Color(0xFF0A0A0F),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xFF141421),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF2A2A3A)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.settings_rounded,
                          color: Color(0xFFFF4D6A),
                          size: 32,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Backend configuration required',
                          style: TextStyle(
                            color: Color(0xFFF0F0F5),
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          message,
                          style: const TextStyle(
                            color: Color(0xFFB8B8C8),
                            fontSize: 14,
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Local runs usually need: flutter run '
                          '--dart-define-from-file=.env.json',
                          style: TextStyle(
                            color: Color(0xFF8888A0),
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
      ),
    );
  }
}
