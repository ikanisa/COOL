import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_performance/firebase_performance.dart';
import 'package:flutter/foundation.dart';

/// Wraps [FirebasePerformance] with named-trace helpers for key flows.
///
/// Call [initialize] once after Firebase is ready. All trace methods
/// silently no-op when Performance is unavailable.
class PerformanceService {
  FirebasePerformance? _performance;
  bool _didInit = false;

  final Map<String, Trace> _activeTraces = {};

  /// Must be called after [Firebase.initializeApp].
  Future<void> initialize() async {
    if (_didInit) {
      return;
    }

    _didInit = true;

    if (Firebase.apps.isEmpty) {
      return;
    }

    try {
      _performance = FirebasePerformance.instance;
      // Disable in debug to avoid noise during development.
      await _performance!.setPerformanceCollectionEnabled(!kDebugMode);
    } catch (_) {
      _performance = null;
    }
  }

  /// Starts a custom trace with the given [name].
  ///
  /// Common trace names for this app:
  /// - `auth_cold_start`
  /// - `momo_ussd_to_confirmation`
  /// - `mobility_search`
  /// - `ticket_purchase`
  /// - `group_contribution`
  void startTrace(String name) {
    if (_performance == null) {
      return;
    }

    try {
      final trace = _performance!.newTrace(name);
      trace.start();
      _activeTraces[name] = trace;
    } catch (e) {
      debugPrint('[Perf] Failed to start trace "$name": $e');
    }
  }

  /// Stops (and submits) the trace with the given [name].
  ///
  /// Optionally set [metrics] key-value pairs and [attributes] before
  /// stopping.
  Future<void> stopTrace(
    String name, {
    Map<String, int>? metrics,
    Map<String, String>? attributes,
  }) async {
    final trace = _activeTraces.remove(name);
    if (trace == null) {
      return;
    }

    try {
      metrics?.forEach((key, value) => trace.setMetric(key, value));
      attributes?.forEach((key, value) => trace.putAttribute(key, value));
      await trace.stop();
    } catch (e) {
      debugPrint('[Perf] Failed to stop trace "$name": $e');
    }
  }

  /// Convenience for tracing an async operation end-to-end.
  Future<T> traceAsync<T>(
    String name,
    Future<T> Function() operation, {
    Map<String, String>? attributes,
  }) async {
    startTrace(name);
    try {
      final result = await operation();
      await stopTrace(name, attributes: attributes);
      return result;
    } catch (e) {
      await stopTrace(
        name,
        attributes: {...?attributes, 'error': e.runtimeType.toString()},
      );
      rethrow;
    }
  }

  bool get isAvailable => _performance != null;
}
