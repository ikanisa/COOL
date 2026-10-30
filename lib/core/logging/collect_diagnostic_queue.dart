import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'app_logger.dart';

enum CollectDiagnosticDelivery { accepted, retry, discard }

abstract interface class CollectDiagnosticQueueStore {
  Future<String?> read();
  Future<void> write(String? value);
}

/// Only validated safe events and a one-way local session fence are retained.
/// This namespace never contains credentials, raw identities or error text.
class CollectPreferenceDiagnosticStore implements CollectDiagnosticQueueStore {
  CollectPreferenceDiagnosticStore(CollectDiagnosticSurface surface)
    : _key = 'collect.diagnostics.v1.${surface.name}';

  final String _key;
  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();

  @override
  Future<String?> read() => _preferences.getString(_key);
  @override
  Future<void> write(String? value) => value == null
      ? _preferences.remove(_key)
      : _preferences.setString(_key, value);
}

String collectDiagnosticFingerprint(Map<String, Object?> event) => sha256
    .convert(
      utf8.encode(
        [
          'collect.diagnostic.v1',
          event['surface'],
          event['environment'],
          event['build_version'],
          event['source_revision'],
          event['code'],
        ].join('|'),
      ),
    )
    .toString();

String collectDiagnosticSessionFence(String identity) => sha256
    .convert(utf8.encode('collect.diagnostic.custody.v1|$identity'))
    .toString();

String _severity(CollectDiagnosticCode code) => switch (code) {
  CollectDiagnosticCode.frameworkFailure ||
  CollectDiagnosticCode.platformFailure ||
  CollectDiagnosticCode.startupFailed => 'error',
  CollectDiagnosticCode.startupTimedOut ||
  CollectDiagnosticCode.diagnosticsSuppressed => 'warning',
  _ => 'info',
};

const _safeFields = {
  'collect_diagnostic',
  'code',
  'severity',
  'surface',
  'environment',
  'build_version',
  'attempt',
  'elapsed_ms',
};
const _reportFields = {
  ..._safeFields,
  'source_revision',
  'fingerprint',
  'report_id',
  'occurrences',
};
bool _keys(Map<Object?, Object?> value, Set<String> fields) =>
    value.length == fields.length && value.keys.every(fields.contains);
bool _number(Object? value, int minimum, int maximum) =>
    value is int && value >= minimum && value <= maximum;
bool _safeEvent(Map<Object?, Object?> value) {
  final code = CollectDiagnosticCode.values
      .where((c) => c.name == value['code'])
      .firstOrNull;
  return code != null &&
      value['collect_diagnostic'] == 1 &&
      value['severity'] == _severity(code) &&
      const {'member', 'admin'}.contains(value['surface']) &&
      const {
        'local',
        'development',
        'staging',
        'production',
        'unknown',
      }.contains(value['environment']) &&
      value['build_version'] is String &&
      (value['build_version'] as String).length <= 32 &&
      RegExp(
        r'^(?:unknown|\d+\.\d+\.\d+(?:\+\d+)?)$',
      ).hasMatch(value['build_version'] as String) &&
      _number(value['attempt'], 1, 1000) &&
      _number(value['elapsed_ms'], 0, 86400000);
}

bool _source(Object? value) =>
    value is String &&
    RegExp(r'^(?:unknown|[a-f0-9]{40}|[a-f0-9]{64})$').hasMatch(value);
bool _report(Map<Object?, Object?> value) =>
    _keys(value, _reportFields) &&
    _safeEvent(value) &&
    _source(value['source_revision']) &&
    value['report_id'] is String &&
    RegExp(
      r'^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$',
    ).hasMatch(value['report_id'] as String) &&
    _number(value['occurrences'], 1, 64) &&
    value['fingerprint'] ==
        collectDiagnosticFingerprint(Map<String, Object?>.from(value));

class _QueuedDiagnostic {
  _QueuedDiagnostic(this.report, this.queuedAt, {this.frozen = false});
  final Map<String, Object?> report;
  final int queuedAt;
  bool frozen;
}

/// Best-effort authenticated delivery. The synchronous sink never waits for
/// storage/network, and its failures are deliberately not reported recursively.
/// Anonymous startup events stay in the existing console boundary only.
class CollectDiagnosticQueue {
  CollectDiagnosticQueue({
    required this.surface,
    required this.store,
    String sourceRevision = const String.fromEnvironment(
      'COLLECT_BUILD_SOURCE_ID',
      defaultValue: 'unknown',
    ),
    DateTime Function()? clock,
    String Function()? newId,
    this.initialDelay = const Duration(seconds: 3),
    this.requestTimeout = const Duration(seconds: 10),
  }) : sourceRevision = _source(sourceRevision) ? sourceRevision : 'unknown',
       _clock = clock ?? DateTime.now,
       _newId = newId ?? const Uuid().v4;

  static const maximumReports = 64;
  static const maximumStoredBytes = 65536;
  static const retention = Duration(hours: 24);
  final CollectDiagnosticSurface surface;
  final String sourceRevision;
  final CollectDiagnosticQueueStore store;
  final DateTime Function() _clock;
  final String Function() _newId;
  final Duration initialDelay, requestTimeout;
  final _queue = <_QueuedDiagnostic>[];
  Future<void>? _storageWork;
  Future<void>? _storageObservation;
  bool _storageDirty = false;
  String? _pendingStorage;
  String? _fence;
  bool Function()? _current;
  Future<CollectDiagnosticDelivery> Function(Map<String, Object?>)? _send;
  Timer? _timer;
  int _generation = 0, _failures = 0;
  bool _disposed = false, _sending = false, _activated = false;
  DateTime? _nextAttempt;
  int get pendingCount => _queue.length;

  bool _authorized() {
    try {
      return _current?.call() == true;
    } catch (_) {
      return false;
    }
  }

  void activate({
    required String? fence,
    required bool Function() current,
    required Future<CollectDiagnosticDelivery> Function(Map<String, Object?>)
    send,
  }) {
    if (_disposed) return;
    if (fence != null && !RegExp(r'^[a-f0-9]{64}$').hasMatch(fence)) return;
    _current = current;
    _send = send;
    if (fence == _fence) {
      wake();
      return;
    }
    final first = !_activated;
    _activated = true;
    ++_generation;
    _fence = fence;
    _queue.clear();
    _timer?.cancel();
    _timer = null;
    _sending = false;
    _failures = 0;
    _nextAttempt = null;
    if (first && fence != null) {
      unawaited(_restore(_generation));
    } else {
      unawaited(_persist());
    }
  }

  Future<void> _restore(int generation) async {
    try {
      final raw = await store.read().timeout(const Duration(seconds: 2));
      if (_disposed ||
          generation != _generation ||
          raw == null ||
          utf8.encode(raw).length > maximumStoredBytes) {
        return;
      }
      final value = jsonDecode(raw);
      if (value is! Map ||
          !_keys(value, {'version', 'fence', 'reports'}) ||
          value['version'] != 1 ||
          value['fence'] != _fence ||
          value['reports'] is! List) {
        return;
      }
      final entries = value['reports'] as List;
      if (entries.length > maximumReports) return;
      final seen = _queue.map((e) => e.report['report_id']).toSet();
      for (final entry in entries) {
        if (entry is! Map ||
            !_keys(entry, {'queued_at', 'report'}) ||
            entry['report'] is! Map ||
            !_number(entry['queued_at'], 0, _clock().millisecondsSinceEpoch)) {
          continue;
        }
        final report = entry['report'] as Map;
        if (!_report(report) ||
            report['surface'] != surface.name ||
            !seen.add(report['report_id'])) {
          continue;
        }
        if (_clock().millisecondsSinceEpoch - (entry['queued_at'] as int) >
            retention.inMilliseconds) {
          continue;
        }
        if (_queue.length >= maximumReports) break;
        _queue.add(
          _QueuedDiagnostic(
            Map<String, Object?>.from(report),
            entry['queued_at'] as int,
            frozen: true,
          ),
        );
      }
    } catch (_) {
      /* Malformed/unavailable storage never becomes telemetry. */
    } finally {
      if (!_disposed && generation == _generation) {
        unawaited(_persist());
        wake();
      }
    }
  }

  void add(String safeEvent) {
    if (_disposed ||
        _fence == null ||
        !_authorized() ||
        safeEvent.length > 1024) {
      return;
    }
    try {
      final value = jsonDecode(safeEvent);
      if (value is! Map ||
          !_keys(value, _safeFields) ||
          !_safeEvent(value) ||
          value['surface'] != surface.name) {
        return;
      }
      _expire();
      final event = <String, Object?>{
        ...Map<String, Object?>.from(value),
        'source_revision': sourceRevision,
      };
      final fingerprint = collectDiagnosticFingerprint(event);
      final matching = _queue
          .where(
            (e) =>
                !e.frozen &&
                e.report['fingerprint'] == fingerprint &&
                (e.report['occurrences'] as int) < 64,
          )
          .firstOrNull;
      if (matching != null) {
        matching.report['occurrences'] =
            (matching.report['occurrences'] as int) + 1;
      } else {
        if (_queue.length >= maximumReports) return;
        event.addAll({
          'fingerprint': fingerprint,
          'report_id': _newId(),
          'occurrences': 1,
        });
        if (!_report(event)) return;
        _queue.add(_QueuedDiagnostic(event, _clock().millisecondsSinceEpoch));
      }
      unawaited(_persist());
      wake();
    } catch (_) {
      /* No raw sink value or caught error is retained. */
    }
  }

  void _expire() {
    final before = _queue.length;
    _queue.removeWhere(
      (e) =>
          _clock().millisecondsSinceEpoch - e.queuedAt >
          retention.inMilliseconds,
    );
    if (_queue.length != before) unawaited(_persist());
  }

  Future<void> _persist() {
    final encoded = _fence == null
        ? null
        : jsonEncode({
            'version': 1,
            'fence': _fence,
            'reports': _queue
                .map((e) => {'queued_at': e.queuedAt, 'report': e.report})
                .toList(),
          });
    final safe =
        encoded != null && utf8.encode(encoded).length > maximumStoredBytes
        ? null
        : encoded;
    _pendingStorage = safe;
    _storageDirty = true;
    if (_storageWork != null) return _storageObservation!;
    final done = Completer<void>();
    _storageWork = done.future;
    // Share one bounded observation for this drain. Repeated timeout wrappers
    // would retain another listener on the same unresolved plugin operation.
    final observed = done.future.timeout(
      const Duration(seconds: 3),
      onTimeout: () {},
    );
    _storageObservation = observed;
    unawaited(_drainStorage(done));
    return observed;
  }

  Future<void> _drainStorage(Completer<void> done) async {
    while (_storageDirty) {
      _storageDirty = false;
      final value = _pendingStorage;
      try {
        // A Future timeout cannot cancel a plugin write. Keep its original
        // ownership until it settles so a late old-session write cannot race a
        // newer snapshot, and a stalled plugin retains at most one raw write.
        // Callers bound their observation separately; only the newest pending
        // snapshot is kept while this operation remains unresolved.
        await store.write(value);
      } catch (_) {
        /* Best effort. */
      }
    }
    _storageWork = null;
    _storageObservation = null;
    done.complete();
  }

  void wake() {
    if (_disposed ||
        _fence == null ||
        _sending ||
        _timer != null ||
        !_authorized()) {
      return;
    }
    _expire();
    if (_queue.isEmpty) return;
    final remaining = _nextAttempt?.difference(_clock());
    final delay = remaining != null && remaining > Duration.zero
        ? remaining
        : initialDelay;
    _timer = Timer(delay, () {
      _timer = null;
      unawaited(flush());
    });
  }

  Future<void> flush() async {
    if (_disposed ||
        _sending ||
        _fence == null ||
        !_authorized() ||
        _send == null) {
      return;
    }
    if (_nextAttempt != null && _clock().isBefore(_nextAttempt!)) {
      wake();
      return;
    }
    _timer?.cancel();
    _timer = null;
    _expire();
    if (_queue.isEmpty) return;
    final generation = _generation,
        send = _send!,
        current = _current!,
        batch = _queue.take(8).toList();
    for (final item in batch) {
      item.frozen = true;
    }
    _sending = true;
    var outcome = CollectDiagnosticDelivery.retry;
    try {
      try {
        await _persist();
      } catch (_) {
        /* Delivery can continue without persistence. */
      }
      if (_disposed || generation != _generation || !current()) return;
      final reports = batch
          .map((e) => Map<String, Object?>.unmodifiable(e.report))
          .toList(growable: false);
      outcome = await send({
        'contract_version': 1,
        'reports': reports,
      }).timeout(requestTimeout);
    } catch (_) {
      /* Never report a reporter failure. */
    } finally {
      if (!_disposed && generation == _generation) {
        _sending = false;
        if (outcome != CollectDiagnosticDelivery.retry) {
          final ids = batch.map((e) => e.report['report_id']).toSet();
          _queue.removeWhere((e) => ids.contains(e.report['report_id']));
          _failures = 0;
          _nextAttempt = null;
        } else {
          _failures = min(_failures + 1, 7);
          _nextAttempt = _clock().add(
            Duration(seconds: min(300, 5 * (1 << (_failures - 1)))),
          );
        }
        unawaited(_persist());
        wake();
      }
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    ++_generation;
    _timer?.cancel();
    _timer = null;
    _send = null;
    _current = null;
    try {
      await _storageWork?.timeout(const Duration(seconds: 2));
    } catch (_) {
      // Disposal is bounded without pretending the original write was
      // cancelled. Its owned drain may still persist the final safe snapshot.
    }
  }
}
