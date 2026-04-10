import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';

import 'bootstrap/app_bootstrap.dart';

Future<void> main() async {
  runZonedGuarded(
    () async {
      final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
      // Hold the native splash visible during bootstrap so the user
      // only sees one smooth transition: native splash → Flutter UI.
      FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

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
