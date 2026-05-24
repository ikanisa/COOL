import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/env/app_env.dart';
import 'core/logging/app_logger.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final env = AppEnv.fromEnvironment();
  AppLogger.instance.i('Collect starting in ${env.environmentName} mode');

  runApp(
    ProviderScope(
      overrides: [appEnvProvider.overrideWithValue(env)],
      child: const CollectApp(),
    ),
  );
}
