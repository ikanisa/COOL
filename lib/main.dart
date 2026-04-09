import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_performance/firebase_performance.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
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

Future<void> main() async {
  // ── Run everything inside runZonedGuarded so the binding, init, and
  //    runApp all share the same zone — prevents zone mismatch errors
  //    that break touch event delivery. ───────────────────────────────
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      if (kIsWeb) {
        usePathUrlStrategy();
      }

      // ── Disable runtime font fetching (fonts bundled in assets) ──────
      GoogleFonts.config.allowRuntimeFetching = false;

      // Launch a lightweight Flutter bootstrap immediately so async startup
      // cannot strand the user on the native splash.
      runApp(const _AppBootstrap());
    },
    (error, stack) {
      debugPrint('[Uncaught] $error\n$stack');
      if (Firebase.apps.isNotEmpty) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      }
    },
  );
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

class _AppBootstrap extends StatefulWidget {
  const _AppBootstrap();

  @override
  State<_AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<_AppBootstrap> {
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
      debugPrint('[Bootstrap] ❌ Startup failed: $error\n$stack');
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
      debugPrint('[EnvConfig] ❌ $configError');
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
            '[Bootstrap] ⚠️ Cold-start trace stop failed: $error\n$stack',
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
    final firebaseProjectId =
        Firebase.apps.isNotEmpty ? Firebase.app().options.projectId : 'none';
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
    debugPrint('[Bootstrap] ➜ $label');

    try {
      final result = await action().timeout(timeout);
      debugPrint('[Bootstrap] ✓ $label (${stopwatch.elapsedMilliseconds}ms)');
      return result;
    } on TimeoutException {
      debugPrint(
        '[Bootstrap] ⚠️ $label timed out after ${stopwatch.elapsedMilliseconds}ms',
      );
      return null;
    } catch (error, stack) {
      debugPrint(
        '[Bootstrap] ⚠️ $label failed after ${stopwatch.elapsedMilliseconds}ms: '
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
    debugPrint('[Bootstrap] ➜ $label');

    try {
      final result = await action().timeout(timeout);
      debugPrint('[Bootstrap] ✓ $label (${stopwatch.elapsedMilliseconds}ms)');
      return result;
    } on TimeoutException {
      throw StateError(
        '$label timed out after ${timeout.inSeconds}s. '
        'The app never reached the first frame.',
      );
    } catch (error, stack) {
      debugPrint(
        '[Bootstrap] ❌ $label failed after ${stopwatch.elapsedMilliseconds}ms: '
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

    return _BootstrapShell(
      child: _errorMessage == null
          ? _BootstrapMessageCard(
              title: 'Preparing COOL',
              message: _currentStep,
              isBusy: true,
              onRetry: null,
            )
          : _BootstrapMessageCard(
              title: 'Startup blocked',
              message: _errorMessage!,
              isBusy: false,
              onRetry: _bootstrap,
            ),
    );
  }
}

class _BootstrapShell extends StatelessWidget {
  const _BootstrapShell({required this.child});

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

class _BootstrapMessageCard extends StatelessWidget {
  const _BootstrapMessageCard({
    required this.title,
    required this.message,
    required this.isBusy,
    required this.onRetry,
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
