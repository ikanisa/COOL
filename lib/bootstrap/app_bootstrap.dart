import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_performance/firebase_performance.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app.dart';
import '../core/config/env_config.dart';
import '../core/services/app_check_service.dart';
import '../core/services/firebase_bootstrap_service.dart';
import '../core/services/hive_runtime.dart';
import '../core/theme/cool_foundations.dart';
import '../core/theme/theme_preference.dart';
import '../core/theme/theme_preference_provider.dart';
import '../core/theme/theme_preference_store.dart';
import 'bootstrap_ui.dart';

class AppBootstrap extends StatefulWidget {
  const AppBootstrap({super.key});

  @override
  State<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapResult {
  const _AppBootstrapResult({
    required this.themePreferenceStore,
    required this.initialPreference,
    required this.configError,
  });

  final ThemePreferenceStore themePreferenceStore;
  final ({AppThemePreference preference, DateTime? updatedAt})
  initialPreference;
  final String? configError;
}

class _AppBootstrapState extends State<AppBootstrap> {
  static const _defaultThemePreference = AppThemePreference.dark;

  String _currentStep = 'Starting app';
  String? _errorMessage;
  _AppBootstrapResult? _result;
  int _bootstrapGeneration = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    final generation = ++_bootstrapGeneration;
    setState(() {
      _currentStep = 'Starting app';
      _errorMessage = null;
      _result = null;
    });

    try {
      final result = await _performBootstrap();
      if (!mounted || generation != _bootstrapGeneration) {
        return;
      }
      setState(() {
        _result = result;
      });
    } catch (error, stack) {
      debugPrint('[Bootstrap] Startup failed: $error\n$stack');
      if (!mounted || generation != _bootstrapGeneration) {
        return;
      }
      setState(() {
        _errorMessage = _describeBootstrapFailure(error);
      });
    }
  }

  Future<_AppBootstrapResult> _performBootstrap() async {
    EnvConfig.logWarnings();

    await _runOptionalBootStep(
      'Initializing Firebase',
      FirebaseBootstrapService.ensureInitialized,
      timeout: const Duration(seconds: 8),
    );

    await _runOptionalBootStep(
      'Recording runtime backend contract',
      _recordRuntimeConfiguration,
      timeout: const Duration(seconds: 4),
    );

    await _runOptionalBootStep(
      'Activating device attestation',
      AppCheckService.initialize,
      timeout: const Duration(seconds: 8),
    );

    Trace? coldStartTrace;
    if (Firebase.apps.isNotEmpty && !kDebugMode) {
      coldStartTrace = await _runOptionalBootStep<Trace>(
        'Starting cold-start trace',
        () async {
          final trace = FirebasePerformance.instance.newTrace('app_cold_start');
          await trace.start();
          return trace;
        },
        timeout: const Duration(seconds: 4),
      );
    }

    _configureErrorHandling();

    await _runOptionalBootStep(
      'Applying device orientation',
      () =>
          SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]),
      timeout: const Duration(seconds: 4),
    );

    final configError = EnvConfig.criticalConfigurationError;
    if (configError == null) {
      await _runRequiredBootStep(
        'Connecting backend',
        () => Supabase.initialize(
          url: EnvConfig.supabaseUrl,
          anonKey: EnvConfig.supabaseAnonKey,
        ),
        timeout: const Duration(seconds: 10),
      );
    } else {
      debugPrint('[EnvConfig] $configError');
    }

    await _runOptionalBootStep(
      'Preparing local storage',
      initializeHiveRuntime,
      timeout: const Duration(seconds: 6),
    );

    final themePreferenceStore = HiveThemePreferenceStore(
      openBox: openHiveBox<String>,
    );
    final initialPreference =
        await _runOptionalBootStep<
          ({AppThemePreference preference, DateTime? updatedAt})
        >(
          'Loading theme preference',
          themePreferenceStore.read,
          timeout: const Duration(seconds: 4),
        ) ??
        (preference: _defaultThemePreference, updatedAt: null);

    if (coldStartTrace != null) {
      unawaited(
        coldStartTrace.stop().catchError((error, stack) {
          debugPrint(
            '[Bootstrap] Cold-start trace stop failed: $error\n$stack',
          );
        }),
      );
    }

    return _AppBootstrapResult(
      themePreferenceStore: themePreferenceStore,
      initialPreference: initialPreference,
      configError: configError,
    );
  }

  Future<void> _recordRuntimeConfiguration() async {
    final firebaseProjectId = Firebase.apps.isNotEmpty
        ? Firebase.app().options.projectId
        : 'none';
    final summary =
        '[RuntimeConfig] flavor=${EnvConfig.flavor} '
        'backend=${EnvConfig.backendEnvironment} '
        'supabase=${EnvConfig.effectiveSupabaseProjectRef} '
        'firebase=$firebaseProjectId';
    debugPrint(summary);

    if (Firebase.apps.isEmpty) {
      return;
    }

    await FirebaseCrashlytics.instance.setCustomKey(
      'app_flavor',
      EnvConfig.flavor,
    );
    await FirebaseCrashlytics.instance.setCustomKey(
      'backend_environment',
      EnvConfig.backendEnvironment,
    );
    await FirebaseCrashlytics.instance.setCustomKey(
      'supabase_project_ref',
      EnvConfig.effectiveSupabaseProjectRef,
    );
    await FirebaseCrashlytics.instance.setCustomKey(
      'firebase_project_id',
      firebaseProjectId,
    );
    FirebaseCrashlytics.instance.log(summary);
  }

  Future<T?> _runOptionalBootStep<T>(
    String label,
    Future<T> Function() action, {
    required Duration timeout,
  }) async {
    _setStep(label);
    final stopwatch = Stopwatch()..start();
    debugPrint('[Bootstrap] -> $label');

    try {
      final result = await action().timeout(timeout);
      debugPrint('[Bootstrap] ok: $label (${stopwatch.elapsedMilliseconds}ms)');
      return result;
    } on TimeoutException {
      debugPrint(
        '[Bootstrap] timeout: $label (${stopwatch.elapsedMilliseconds}ms)',
      );
      return null;
    } catch (error, stack) {
      debugPrint(
        '[Bootstrap] failed: $label (${stopwatch.elapsedMilliseconds}ms): '
        '$error\n$stack',
      );
      return null;
    }
  }

  Future<T> _runRequiredBootStep<T>(
    String label,
    Future<T> Function() action, {
    required Duration timeout,
  }) async {
    _setStep(label);
    final stopwatch = Stopwatch()..start();
    debugPrint('[Bootstrap] -> $label');

    try {
      final result = await action().timeout(timeout);
      debugPrint('[Bootstrap] ok: $label (${stopwatch.elapsedMilliseconds}ms)');
      return result;
    } on TimeoutException {
      throw StateError(
        '$label timed out after ${timeout.inSeconds}s. '
        'The app never reached the first frame.',
      );
    } catch (error, stack) {
      debugPrint(
        '[Bootstrap] failed: $label (${stopwatch.elapsedMilliseconds}ms): '
        '$error\n$stack',
      );
      throw StateError('$label failed: $error');
    }
  }

  void _setStep(String step) {
    if (!mounted) {
      return;
    }
    setState(() {
      _currentStep = step;
    });
  }

  void _configureErrorHandling() {
    if (Firebase.apps.isEmpty) {
      return;
    }

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
  }

  String _describeBootstrapFailure(Object error) {
    if (error is StateError) {
      return error.toString().replaceFirst('Bad state: ', '');
    }
    return 'Startup failed while $_currentStep. Restart the app and try again.';
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    if (result != null) {
      return ProviderScope(
        overrides: [
          themePreferenceStoreProvider.overrideWithValue(
            result.themePreferenceStore,
          ),
          initialThemePreferenceProvider.overrideWithValue(
            result.initialPreference,
          ),
        ],
        child: result.configError == null
            ? const CoolApp()
            : ConfigErrorApp(message: result.configError!),
      );
    }

    return BootstrapShell(
      child: _errorMessage == null
          ? BootstrapMessageCard(
              title: 'Preparing COOL',
              message: _currentStep,
              isBusy: true,
              onRetry: null,
            )
          : BootstrapMessageCard(
              title: 'Startup blocked',
              message: _errorMessage!,
              isBusy: false,
              onRetry: _bootstrap,
            ),
    );
  }
}
