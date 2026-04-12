import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';

import 'bootstrap/app_bootstrap.dart';

Future<void> main() async {
  // Release builds should not emit development console logging.
  if (kReleaseMode) {
    debugPrint = (String? message, {int? wrapWidth}) {};
  }

  runZonedGuarded(
    () async {
      final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
      // Android 12+ already keeps the launch splash visible until Flutter
      // draws its first frame. Preserving it manually on Android can leave
      // the native splash stuck on top of the in-app bootstrap shell.
      final shouldPreserveNativeSplash =
          !kIsWeb && defaultTargetPlatform != TargetPlatform.android;
      if (shouldPreserveNativeSplash) {
        FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
      }

      if (kIsWeb) {
        usePathUrlStrategy();
      }

      runApp(const AppBootstrap());
    },
    (error, stack) {
      debugPrint('[Uncaught] $error\n$stack');
      if (Firebase.apps.isNotEmpty) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      }
    },
  );
}
