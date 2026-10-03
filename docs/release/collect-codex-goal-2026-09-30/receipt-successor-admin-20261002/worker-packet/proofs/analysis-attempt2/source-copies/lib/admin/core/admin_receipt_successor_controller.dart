import 'package:flutter/foundation.dart';
import 'admin_receipt_successor_models.dart';
import 'admin_receipt_successor_sdk.dart';
import 'admin_receipt_successor_checkpoint.dart';

/// Persists only request identity/proof bindings before mutation, never a body,
/// recipient, reason, credential or send capability. Unknown originals remain
/// blocked even when lookup says not_recorded; this API has no absence barrier.
class AdminReceiptSuccessorController extends ChangeNotifier {
  AdminReceiptSuccessorController({
    required this.api,
    required this.ownerDigest,
    required this.store,
    required this.isCurrent,
  }) {
    successorHash(ownerDigest);
    try {
      final raw = store?.read(ownerDigest);
      if (raw != null) {
        pending = AdminReceiptSuccessorCheckpoint.parse(
          raw,
          ownerDigest,
        ).binding;
        message =
            'An original request was recovered. Check its outcome before another action.';
      }
    } catch (_) {
      storageFailed = true;
      message = 'Recovery storage could not be read. Actions are unavailable.';
    }
  }
  final AdminReceiptSuccessorApi api;
  final String ownerDigest;
  final AdminReceiptSuccessorCheckpointStore? store;
  final bool Function() isCurrent;
  bool busy = false, storageFailed = false, _disposed = false;
  String? message;
  AdminReceiptSuccessorBinding? pending;
  AdminReceiptSuccessorReceipt? receipt;
  bool get canSubmit =>
      !busy &&
      !storageFailed &&
      store != null &&
      pending == null &&
      isCurrent() &&
      !_disposed;
  void _publish() {
    if (!_disposed && isCurrent()) notifyListeners();
  }

  void _clear() {
    store!.clear(ownerDigest);
    if (store!.read(ownerDigest) != null)
      throw StateError('Recovery clear did not persist.');
    pending = null;
  }

  Future<void> submit(AdminReceiptSuccessorIntent intent) async {
    if (!canSubmit)
      throw StateError('Resolve the original request before another action.');
    final encoded = AdminReceiptSuccessorCheckpoint(
      ownerDigest,
      intent.binding,
    ).encode();
    try {
      store!.write(ownerDigest, encoded);
      if (store!.read(ownerDigest) != encoded)
        throw StateError('Recovery write did not persist.');
    } catch (_) {
      storageFailed = true;
      message =
          'Recovery storage could not retain the original request. No action was submitted.';
      _publish();
      return;
    }
    if (!isCurrent() || _disposed) return;
    pending = intent.binding;
    busy = true;
    receipt = null;
    message = 'Recording the reviewed action…';
    _publish();
    try {
      final result = await api.submit(intent);
      if (!isCurrent() || _disposed) return;
      receipt = result;
      try {
        _clear();
        message =
            'The action was recorded. Sending remains governed separately.';
      } catch (_) {
        storageFailed = true;
        message =
            'The action was recorded, but recovery storage could not clear. Keep the original request ID.';
      }
    } on AdminReceiptSuccessorRejected catch (error) {
      if (!isCurrent() || _disposed) return;
      // A confirmed database error rolls back that exact RPC transaction.
      try {
        _clear();
        message = error.code == '42501'
            ? 'Current access was refused.'
            : 'The server refused the action. Refresh current evidence before review.';
      } catch (_) {
        storageFailed = true;
        message =
            'The server refused the action, but recovery storage could not clear.';
      }
    } catch (_) {
      if (!isCurrent() || _disposed) return;
      message =
          'The response is uncertain. Check the original request ID; do not submit another action.';
    } finally {
      if (!_disposed && isCurrent()) {
        busy = false;
        _publish();
      }
    }
  }

  Future<void> recover() async {
    final original = pending;
    if (original == null || busy || !isCurrent() || _disposed) return;
    busy = true;
    message = 'Checking the original request…';
    _publish();
    try {
      final lookup = await api.lookup(original);
      if (!isCurrent() || _disposed) return;
      if (lookup.status == 'recorded') {
        receipt = lookup.receipt;
        try {
          _clear();
          message =
              'The original action was recovered. No action was resubmitted.';
        } catch (_) {
          storageFailed = true;
          message =
              'The original outcome is recorded, but recovery storage could not clear.';
        }
      } else {
        message = lookup.status == 'in_progress'
            ? 'The original request is still in progress.'
            : 'The original request is not recorded yet. Its outcome remains unresolved; check again.';
      }
    } catch (_) {
      if (!isCurrent() || _disposed) return;
      message =
          'The original request could not be checked. Its identity remains retained.';
    } finally {
      if (!_disposed && isCurrent()) {
        busy = false;
        _publish();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
