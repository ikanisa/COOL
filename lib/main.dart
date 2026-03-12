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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── Env validation ──────────────────────────────────────────────────
  EnvConfig.logWarnings();

  // ── Firebase (guaranteed init) ────────────────────────────────────
  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint('[Firebase] ⚠️ Init failed: $e — continuing without Firebase');
  }

  // ── App Check (attestation) ───────────────────────────────────────
  await AppCheckService.initialize();

  // ── Cold start performance trace ─────────────────────────────────
  Trace? coldStartTrace;
  if (Firebase.apps.isNotEmpty && !kDebugMode) {
    try {
      coldStartTrace = FirebasePerformance.instance.newTrace('app_cold_start');
      await coldStartTrace.start();
    } catch (_) {}
  }

  // ── Crashlytics error handlers ────────────────────────────────────
  if (Firebase.apps.isNotEmpty) {
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
  }

  // ── System chrome ─────────────────────────────────────────────────
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
  // are designed for single-column portrait layout. Landscape would require
  // significant adaptive layout work with minimal user value.
  // Decision documented in docs/PERFORMANCE_BUDGETS.md § Portrait Lock.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  await Supabase.initialize(
    url: EnvConfig.supabaseUrl,
    anonKey: EnvConfig.supabaseAnonKey,
  );

  // ── Hive (local storage) ──────────────────────────────────────────
  await Hive.initFlutter();

  // ── Stop cold start trace ─────────────────────────────────────────
  try {
    await coldStartTrace?.stop();
  } catch (_) {}

  // ── Branded error widget (replaces red screen in release) ──────────
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

  // ── Run app (with async error catching) ───────────────────────────
  runZonedGuarded(
    () {
      runApp(
        const ProviderScope(
          child: CoolApp(),
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
