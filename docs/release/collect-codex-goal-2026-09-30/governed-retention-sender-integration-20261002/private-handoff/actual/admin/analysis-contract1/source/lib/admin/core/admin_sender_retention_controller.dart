import 'package:flutter/foundation.dart';
import 'admin_sender_retention_models.dart';
import 'admin_sender_retention_sdk.dart';
import 'admin_sender_retention_checkpoint.dart';

class AdminRetentionController extends ChangeNotifier {
  AdminRetentionController({
    required this.api,
    required this.actorId,
    required this.sessionId,
    required this.store,
    required this.now,
    required this.isCurrent,
    required this.newRequestId,
  });
  final AdminRetentionApi api;
  final String actorId, sessionId;
  final AdminRetentionStore? store;
  final DateTime Function() now;
  final bool Function() isCurrent;
  final String Function() newRequestId;
  AdminRetentionSnapshot? snapshot;
  AdminRetentionIntent? pending;
  AdminRetentionRequest? receipt;
  bool loading = false, busy = false, _disposed = false;
  String? error;
  int _generation = 0;
  bool _owns(int g) => !_disposed && g == _generation;
  bool _valid(int g) => _owns(g) && isCurrent();
  void _emit() {
    if (!_disposed) notifyListeners();
  }

  void _redact(int g) {
    if (!_owns(g)) return;
    _generation++;
    snapshot = null;
    receipt = null;
    pending = null;
    loading = false;
    busy = false;
    error =
        'Current email-owner access is required. Restore access and refresh.';
    _emit();
  }

  bool get canApply =>
      !busy &&
      !loading &&
      pending == null &&
      store != null &&
      isCurrent() &&
      snapshot != null &&
      snapshot!.mutationAllowed &&
      snapshot!.fresh(now());
  Future<void> refresh() async {
    if (_disposed || !isCurrent() || busy) return;
    final g = ++_generation;
    loading = true;
    snapshot = null;
    receipt = null;
    error = null;
    _emit();
    try {
      final retained = await store?.read(actorId, sessionId);
      if (!_valid(g)) return;
      pending = retained;
      final value = await api.read();
      if (!_valid(g)) return;
      snapshot = value;
    } catch (e) {
      if (retentionDenied(e)) {
        _redact(g);
        return;
      }
      if (_valid(g)) {
        snapshot = null;
        error = 'Retention controls could not be loaded. Refresh to try again.';
      }
    } finally {
      if (_valid(g)) {
        loading = false;
        _emit();
      }
    }
  }

  Future<void> apply({
    required bool enabled,
    required int batchLimit,
    required int byteLimit,
    required String reason,
  }) async {
    if (!canApply) return;
    final g = _generation;
    busy = true;
    error = null;
    _emit();
    try {
      final i = AdminRetentionIntent.create(
        snapshot: snapshot!,
        requestId: newRequestId(),
        enabled: enabled,
        batchLimit: batchLimit,
        byteLimit: byteLimit,
        reason: reason,
        now: now(),
      );
      // Pending is retained even if durable write succeeds but readback fails.
      pending = i;
      await store!.write(i);
      if (!_valid(g)) return;
      if ((await store!.read(actorId, sessionId))?.fingerprint !=
          i.fingerprint) {
        retentionInvalid();
      }
      if (!_valid(g)) return;
      final r = await api.configure(i);
      if (!_valid(g)) return;
      receipt = r;
      await store!.clear(i);
      if (!_valid(g)) return;
      pending = null;
      snapshot = null;
      error =
          'Maintenance controls recorded. Refresh to observe current values.';
    } catch (e) {
      if (retentionDenied(e)) {
        _redact(g);
        return;
      }
      if (_valid(g)) {
        error =
            'The original request requires recovery. No replacement request has been sent.';
      }
    } finally {
      if (_valid(g)) {
        busy = false;
        _emit();
      }
    }
  }

  Future<void> recover() async {
    final i = pending;
    if (i == null || busy || _disposed || !isCurrent()) return;
    final g = _generation;
    busy = true;
    error = null;
    _emit();
    try {
      final r = await api.recover(i);
      if (!_valid(g)) return;
      receipt = r;
      if (r.recorded || !r.checkedAt!.isBefore(i.expiresAt)) {
        await store!.clear(i);
        if (!_valid(g)) return;
        pending = null;
        snapshot = null;
        error = r.recorded
            ? 'Original request recovered. Refresh current values.'
            : 'Expired original request was not recorded. Refresh before a new change.';
      } else {
        error =
            'Original request is not recorded yet. Keep its UUID and recover after its deadline.';
      }
    } catch (e) {
      if (retentionDenied(e)) {
        _redact(g);
        return;
      }
      if (_valid(g)) {
        error =
            'Original request recovery is unavailable. Its checkpoint is retained.';
      }
    } finally {
      if (_valid(g)) {
        busy = false;
        _emit();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
