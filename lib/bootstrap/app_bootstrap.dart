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

import '../app.dart';
import '../core/config/country_catalog.dart';
import '../core/config/env_config.dart';
import '../core/providers/engagement_providers.dart';
import '../core/services/app_check_service.dart';
import '../core/services/firebase_bootstrap_service.dart';
import '../core/services/hive_runtime.dart';
import '../core/services/crashlytics_service.dart';
import '../core/services/performance_service.dart';
import '../core/theme/cool_foundations.dart';
import '../core/theme/theme_preference.dart';
import '../core/theme/theme_preference_provider.dart';
import '../core/theme/theme_preference_store.dart';
import '../l10n/app_localizations.dart';
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
    required this.crashlytics,
    required this.performance,
    required this.configError,
  });

  final ThemePreferenceStore themePreferenceStore;
  final ({AppThemePreference preference, DateTime? updatedAt})
  initialPreference;
  final CrashlyticsService crashlytics;
  final PerformanceService performance;
  final String? configError;
}

class _AppBootstrapState extends State<AppBootstrap> {
  static const _defaultThemePreference = AppThemePreference.dark;
  static const _startupSplashFailsafe = Duration(seconds: 3);

  String _currentStep = '';
  String? _errorMessage;
  _AppBootstrapResult? _result;
  int _bootstrapGeneration = 0;
  bool _startupSplashReleased = false;
  Timer? _startupSplashFailsafeTimer;

  AppLocalizations get _bootstrapL10n =>
      lookupAppLocalizations(const Locale('en'));

  @override
  void initState() {
    super.initState();
    _currentStep = _bootstrapL10n.bootstrapStartingApp;
    _startupSplashFailsafeTimer = Timer(
      _startupSplashFailsafe,
      _releaseStartupSplash,
    );
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    _startupSplashFailsafeTimer?.cancel();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final generation = ++_bootstrapGeneration;
    setState(() {
      _currentStep = _bootstrapL10n.bootstrapStartingApp;
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
      _scheduleStartupSplashRelease();
    } catch (error, stack) {
      debugPrint('[Bootstrap] Startup failed: $error\n$stack');
      if (!mounted || generation != _bootstrapGeneration) {
        return;
      }
      setState(() {
        _errorMessage = _describeBootstrapFailure(error);
      });
      _scheduleStartupSplashRelease();
    }
  }

  Future<_AppBootstrapResult> _performBootstrap() async {
    EnvConfig.logWarnings();

    await _runOptionalBootStep(
      _bootstrapL10n.bootstrapInitializingFirebase,
      FirebaseBootstrapService.ensureInitialized,
      timeout: const Duration(seconds: 8),
    );

    await _runOptionalBootStep(
      _bootstrapL10n.bootstrapRecordingRuntimeBackendContract,
      _recordRuntimeConfiguration,
      timeout: const Duration(seconds: 4),
    );

    await _runOptionalBootStep(
      _bootstrapL10n.bootstrapActivatingDeviceAttestation,
      AppCheckService.initialize,
      timeout: const Duration(seconds: 8),
    );

    Trace? coldStartTrace;
    if (Firebase.apps.isNotEmpty && !kDebugMode) {
      coldStartTrace = await _runOptionalBootStep<Trace>(
        _bootstrapL10n.bootstrapStartingColdStartTrace,
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
      _bootstrapL10n.bootstrapApplyingDeviceOrientation,
      () =>
          SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]),
      timeout: const Duration(seconds: 4),
    );

    final configError = EnvConfig.criticalConfigurationError;
    if (configError == null) {
      // Guard against duplicate initialization — Supabase.initialize() is not
      // idempotent.  On a bootstrap retry (e.g. after a transient network
      // failure in a later step) the client may already be initialized.
      final alreadyInitialized = _isSupabaseInitialized();
      if (!alreadyInitialized) {
        await _runRequiredBootStep(
          _bootstrapL10n.bootstrapConnectingBackend,
          () => Supabase.initialize(
            url: EnvConfig.supabaseUrl,
            anonKey: EnvConfig.supabaseAnonKey,
          ),
          timeout: const Duration(seconds: 10),
        );
      } else {
        debugPrint('[Bootstrap] Supabase already initialized — skipping');
      }
    } else {
      debugPrint('[EnvConfig] $configError');
    }

    await _runOptionalBootStep(
      _bootstrapL10n.bootstrapPreparingLocalStorage,
      initializeHiveRuntime,
      timeout: const Duration(seconds: 6),
    );

    await _runOptionalBootStep(
      'Verifying local storage schema',
      ensureHiveSchemaVersion,
      timeout: const Duration(seconds: 4),
    );

    await _runRequiredBootStep('Loading regional configuration', () async {
      final jsonString = await rootBundle.loadString('assets/countries.json');
      await CoolCountryCatalog.initialize(jsonString);
    }, timeout: const Duration(seconds: 5));

    final themePreferenceStore = HiveThemePreferenceStore(
      openBox: openHiveBox<String>,
    );
    final initialPreference =
        await _runOptionalBootStep<
          ({AppThemePreference preference, DateTime? updatedAt})
        >(
          _bootstrapL10n.bootstrapLoadingThemePreference,
          themePreferenceStore.read,
          timeout: const Duration(seconds: 4),
        ) ??
        (preference: _defaultThemePreference, updatedAt: null);

    final crashlytics = CrashlyticsService();
    final performance = PerformanceService();
    await crashlytics.initialize();
    await performance.initialize();

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
      crashlytics: crashlytics,
      performance: performance,
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
        _bootstrapL10n.bootstrapTimedOut(label, timeout.inSeconds),
      );
    } catch (error, stack) {
      debugPrint(
        '[Bootstrap] failed: $label (${stopwatch.elapsedMilliseconds}ms): '
        '$error\n$stack',
      );
      throw StateError(_bootstrapL10n.bootstrapStepFailed(label, '$error'));
    }
  }

  void _setStep(String step) {
    if (!mounted) {
      _currentStep = step;
      return;
    }

    setState(() {
      _currentStep = step;
    });
  }

  void _releaseStartupSplash() {
    if (_startupSplashReleased) {
      return;
    }
    _startupSplashReleased = true;
    _startupSplashFailsafeTimer?.cancel();
    FlutterNativeSplash.remove();
  }

  void _scheduleStartupSplashRelease() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _releaseStartupSplash();
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
        final l10n = _bootstrapL10n;
        return Material(
          color: const Color(0xFF0A0A0F),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    CoolIcons.warning,
                    size: 48,
                    color: Color(0xFFFF4D6A),
                  ),
                  const SizedBox(height: CoolSpace.x4),
                  Text(
                    l10n.bootstrapSomethingWentWrong,
                    style: const TextStyle(
                      color: Color(0xFFF0F0F5),
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const SizedBox(height: CoolSpace.x2),
                  Text(
                    l10n.bootstrapPleaseRestartApp,
                    style: const TextStyle(
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

  /// Returns `true` when [Supabase.instance] is usable.
  ///
  /// [Supabase.initialize] is not idempotent — calling it twice throws.
  /// This helper lets the bootstrap retry path skip re-initialization.
  bool _isSupabaseInitialized() {
    try {
      // Accessing `.client` throws if not yet initialized.
      final _ = Supabase.instance.client;
      return true;
    } catch (_) {
      return false;
    }
  }

  String _describeBootstrapFailure(Object error) {
    if (error is StateError) {
      return error.toString().replaceFirst('Bad state: ', '');
    }
    return _bootstrapL10n.bootstrapFailedWhile(_currentStep);
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    if (result != null) {
      return BootstrapResultReveal(
        child: ProviderScope(
          overrides: [
            crashlyticsServiceProvider.overrideWithValue(result.crashlytics),
            performanceServiceProvider.overrideWithValue(result.performance),
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
        ),
      );
    }

    return BootstrapShell(
      child: BootstrapStageTransition(
        child: _errorMessage == null
            ? BootstrapHoldScreen(
                key: const ValueKey('bootstrap-loading'),
                statusLabel: _currentStep,
                onSurfaceReady: _scheduleStartupSplashRelease,
              )
            : BootstrapErrorCard(
                key: const ValueKey('bootstrap-error'),
                message: _errorMessage!,
                onRetry: _bootstrap,
              ),
      ),
    );
  }
}
