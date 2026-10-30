import 'dart:convert';

import 'package:flutter/foundation.dart';

enum CollectDiagnosticSurface { member, admin }

enum CollectDiagnosticCode {
  startupStarted,
  startupWaiting,
  startupTimedOut,
  startupFailed,
  startupReady,
  frameworkFailure,
  platformFailure,
  diagnosticsSuppressed,
}

/// An allowlisted diagnostic boundary. Exceptions, stacks, URLs, session IDs,
/// receipt bodies and caller-supplied maps cannot enter this API.
class CollectDiagnostics {
  CollectDiagnostics({
    required this.surface,
    required String environmentName,
    String buildVersion = const String.fromEnvironment(
      'COLLECT_BUILD_VERSION',
      defaultValue: 'unknown',
    ),
    void Function(String)? sink,
    this.elapsed,
  }) : environment = switch (environmentName.trim().toLowerCase()) {
         'local' => 'local',
         'dev' || 'development' => 'development',
         'stage' ||
         'staging' ||
         'qualification' ||
         'cloudflare-preview' => 'staging',
         'prod' ||
         'production' ||
         'supabase-platform' ||
         'cloudflare-platform' => 'production',
         _ => 'unknown',
       },
       build =
           buildVersion.length <= 32 &&
               RegExp(r'^\d+\.\d+\.\d+(?:\+\d+)?$').hasMatch(buildVersion)
           ? buildVersion
           : 'unknown',
       _sink = sink ?? _writeSafeEvent {
    _clock.start();
  }

  final CollectDiagnosticSurface surface;
  final String environment;
  final String build;
  final void Function(String) _sink;
  final Duration Function()? elapsed;
  final Stopwatch _clock = Stopwatch();
  Duration _windowStart = Duration.zero;
  int _windowEvents = 0;
  bool _suppressionReported = false;

  static void _writeSafeEvent(String event) => debugPrint(event);

  void record(CollectDiagnosticCode code, {int attempt = 1}) {
    final elapsed = this.elapsed?.call() ?? _clock.elapsed;
    if (elapsed - _windowStart >= const Duration(minutes: 1)) {
      _windowStart = elapsed;
      _windowEvents = 0;
      _suppressionReported = false;
    }
    if (_windowEvents >= 64) {
      if (_suppressionReported) return;
      _suppressionReported = true;
      code = CollectDiagnosticCode.diagnosticsSuppressed;
    }
    _windowEvents += 1;
    final severity = switch (code) {
      CollectDiagnosticCode.frameworkFailure ||
      CollectDiagnosticCode.platformFailure ||
      CollectDiagnosticCode.startupFailed => 'error',
      CollectDiagnosticCode.startupTimedOut ||
      CollectDiagnosticCode.diagnosticsSuppressed => 'warning',
      _ => 'info',
    };
    final event = jsonEncode({
      'collect_diagnostic': 1,
      'code': code.name,
      'severity': severity,
      'surface': surface.name,
      'environment': environment,
      'build_version': build,
      'attempt': attempt.clamp(1, 1000),
      'elapsed_ms': elapsed.inMilliseconds.clamp(0, 86400000),
    });
    // Diagnostics must never interrupt a financial or recovery operation.
    try {
      _sink(event);
    } catch (_) {
      // A broken sink cannot recursively report itself or expose its error.
    }
  }
}
