import 'dart:async';

import 'package:flutter/foundation.dart';

import '../logging/app_logger.dart';

enum CollectStartupStage { loading, failed, ready }

/// A rejected initializer whose cleanup result determines safe retry.
class CollectStartupFailure implements Exception {
  const CollectStartupFailure({required this.retryAllowed});

  final bool retryAllowed;

  @override
  String toString() => 'Collect initialization failed';
}

/// Owns one initialization operation. A display deadline does not cancel that
/// operation or permit another initializer to overlap it.
class CollectStartupController<T> extends ChangeNotifier {
  CollectStartupController({
    required this.initialize,
    required this.diagnostics,
    this.displayDeadline = const Duration(seconds: 15),
  }) {
    if (displayDeadline <= Duration.zero) {
      throw ArgumentError.value(displayDeadline, 'displayDeadline');
    }
  }

  final Future<T> Function() initialize;
  final CollectDiagnostics diagnostics;
  final Duration displayDeadline;
  Future<T>? _inFlight;
  Timer? _deadline;
  T? _value;
  bool _started = false;
  bool _disposed = false;
  bool _fatalFailure = false;
  bool _retryAllowed = true;
  int _attempt = 0;
  CollectStartupStage _stage = CollectStartupStage.loading;

  CollectStartupStage get stage => _stage;
  bool get canRetry => _stage == CollectStartupStage.failed && _retryAllowed;
  bool get initializationInFlight => _inFlight != null;

  T get value {
    if (_stage != CollectStartupStage.ready) {
      throw StateError('Collect initialization is not ready');
    }
    return _value as T;
  }

  void start() {
    if (_started || _disposed) return;
    _started = true;
    _begin();
  }

  void retry() {
    if (!canRetry || _disposed) return;
    if (_inFlight != null) {
      _attempt += 1;
      _stage = CollectStartupStage.loading;
      diagnostics.record(
        CollectDiagnosticCode.startupWaiting,
        attempt: _attempt,
      );
      _armDeadline();
      notifyListeners();
      return;
    }
    _begin();
  }

  void reportApplicationFailure() {
    if (_disposed || _fatalFailure) return;
    _fatalFailure = true;
    _retryAllowed = false;
    _deadline?.cancel();
    _stage = CollectStartupStage.failed;
    notifyListeners();
  }

  void _begin() {
    _attempt += 1;
    _stage = CollectStartupStage.loading;
    _retryAllowed = true;
    diagnostics.record(CollectDiagnosticCode.startupStarted, attempt: _attempt);
    final operation = Future<T>.sync(initialize);
    _inFlight = operation;
    _armDeadline();
    notifyListeners();
    unawaited(
      operation.then<void>(
        (value) {
          if (_disposed || !identical(_inFlight, operation)) return;
          _inFlight = null;
          _deadline?.cancel();
          if (_fatalFailure) return;
          _value = value;
          _stage = CollectStartupStage.ready;
          diagnostics.record(
            CollectDiagnosticCode.startupReady,
            attempt: _attempt,
          );
          notifyListeners();
        },
        onError: (Object error, StackTrace stack) {
          if (_disposed || !identical(_inFlight, operation)) return;
          _inFlight = null;
          _deadline?.cancel();
          if (_fatalFailure) return;
          _retryAllowed = error is! CollectStartupFailure || error.retryAllowed;
          _stage = CollectStartupStage.failed;
          diagnostics.record(
            CollectDiagnosticCode.startupFailed,
            attempt: _attempt,
          );
          notifyListeners();
        },
      ),
    );
  }

  void _armDeadline() {
    _deadline?.cancel();
    _deadline = Timer(displayDeadline, () {
      if (_disposed || _fatalFailure || _inFlight == null) return;
      _stage = CollectStartupStage.failed;
      diagnostics.record(
        CollectDiagnosticCode.startupTimedOut,
        attempt: _attempt,
      );
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _deadline?.cancel();
    super.dispose();
  }
}
