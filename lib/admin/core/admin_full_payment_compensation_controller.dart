import 'package:flutter/foundation.dart';
import 'admin_auth_guard.dart';
import 'admin_full_payment_compensation_models.dart';
import 'admin_full_payment_compensation_sdk.dart';
import 'admin_full_payment_compensation_checkpoint.dart';

class AdminFullPaymentCompensationController extends ChangeNotifier {
  AdminFullPaymentCompensationController({
    required this.api,
    required this.store,
    required this.actorId,
    required this.sessionId,
    required this.paymentId,
    required this.originalJournalEntryId,
    required this.originalSnapshotId,
    required this.collectionId,
    required this.memberRecordId,
    required this.isCurrent,
    required this.canRecord,
    required this.now,
    required this.newRequestId,
    this.onRecorded,
  });
  final AdminFullPaymentCompensationApi api;
  final AdminFullPaymentCompensationStore? store;
  final String actorId,
      sessionId,
      paymentId,
      originalJournalEntryId,
      originalSnapshotId,
      collectionId;
  final String? memberRecordId;
  final bool Function() isCurrent, canRecord;
  final DateTime Function() now;
  final String Function() newRequestId;
  final VoidCallback? onRecorded;
  AdminFullPaymentCompensationInspection? inspection;
  AdminFullPaymentCompensationIntent? pending;
  AdminFullPaymentCompensationResult? result;
  String? message;
  bool loading = false, busy = false, _closed = false;
  bool get current => !_closed && isCurrent();
  bool _matches(AdminFullPaymentCompensationInspection i) =>
      i.paymentId == paymentId &&
      (i.source == null ||
          i.source!.matches(
            paymentId,
            originalJournalEntryId,
            originalSnapshotId,
            collectionId,
            memberRecordId,
          ));
  bool get canSubmit =>
      current &&
      canRecord() &&
      store != null &&
      !loading &&
      !busy &&
      pending == null &&
      result == null &&
      inspection?.canRecord == true &&
      inspection!.fresh(now());
  void _current() {
    if (!current) throw const AdminSessionChanged();
  }

  void _changed() {
    if (!_closed) notifyListeners();
  }

  Future<void> refresh() async {
    if (busy || loading || !current) return;
    loading = true;
    inspection = null;
    message = null;
    _changed();
    try {
      final retained = await store?.pending(actorId, sessionId);
      _current();
      pending = retained;
      if (retained != null) {
        if (!_matches(retained.inspection)) {
          message =
              'An original compensation request for another payment requires investigation before a new action.';
          return;
        }
        message =
            'An original request is retained. Check its recorded outcome before any further action.';
        return;
      }
      final completed = await store?.lastCompleted(
        actorId,
        sessionId,
        paymentId,
      );
      _current();
      if (completed != null) {
        if (!_matches(completed.inspection)) compensationInvalid();
        pending = completed;
        final lookup = await api.recover(completed);
        _current();
        if (lookup.result != null) {
          pending = null;
          result = lookup.result;
          message = 'The original recorded compensation has been verified.';
        } else {
          message =
              'The retained completed original cannot currently be verified. Keep it for investigation.';
        }
        return;
      }
      final sample = await api.inspect(paymentId);
      _current();
      if (!_matches(sample)) compensationInvalid();
      inspection = sample;
    } catch (_) {
      inspection = null;
      message = current
          ? 'The current financial review is unavailable. Refresh the payment evidence.'
          : 'The operator session changed. Sign in and recheck current evidence.';
    } finally {
      loading = false;
      _changed();
    }
  }

  Future<void> submit(String reason) async {
    if (!canSubmit) return;
    final sample = inspection!, target = store!;
    AdminFullPaymentCompensationIntent original;
    try {
      original = AdminFullPaymentCompensationIntent.create(
        requestId: newRequestId(),
        actorId: actorId,
        sessionId: sessionId,
        inspection: sample,
        reason: reason,
      );
    } catch (_) {
      message = 'Enter a reason of 8–500 characters.';
      _changed();
      return;
    }
    busy = true;
    message = null;
    _changed();
    try {
      _current();
      await target.savePending(original);
      _current();
      final saved = await target.pending(actorId, sessionId);
      _current();
      if (saved?.fingerprint != original.fingerprint) compensationInvalid();
      pending = original;
      final recorded = await api.record(original);
      _current();
      await _complete(original, recorded);
    } catch (_) {
      // Even a lost local acknowledgement keeps the original identity. A fresh
      // read is required; absence is not authority to replace or retry it.
      try {
        final saved = await target.pending(actorId, sessionId);
        if (current) pending = saved ?? original;
      } catch (_) {
        if (current) pending = original;
      }
      inspection = null;
      message = current
          ? 'The outcome is uncertain. Check the retained original request; do not repeat the financial action.'
          : 'The session changed. The original request remains retained for its owner.';
    } finally {
      busy = false;
      _changed();
    }
  }

  Future<void> _complete(
    AdminFullPaymentCompensationIntent original,
    AdminFullPaymentCompensationResult recorded,
  ) async {
    _current();
    AdminFullPaymentCompensationResult.parse(recorded.row, original);
    await store!.complete(original, recorded);
    _current();
    pending = null;
    inspection = null;
    result = recorded;
    message = 'Full Collect ledger compensation recorded.';
    onRecorded?.call();
  }

  Future<void> recover() async {
    final original = pending;
    if (busy ||
        loading ||
        !current ||
        original == null ||
        !_matches(original.inspection)) {
      return;
    }
    busy = true;
    message = null;
    _changed();
    try {
      final lookup = await api.recover(original);
      _current();
      if (lookup.result != null) {
        await _complete(original, lookup.result!);
      } else {
        message = lookup.status == 'in_progress'
            ? 'The original request is still in progress. Check it again.'
            : 'No recorded result is currently visible. Keep this original request for investigation; this does not permit another financial action.';
      }
    } catch (_) {
      message = current
          ? 'The original request cannot currently be verified. Keep it retained and check access or connectivity.'
          : 'The session changed. The original request remains retained.';
    } finally {
      busy = false;
      _changed();
    }
  }

  @override
  void dispose() {
    _closed = true;
    super.dispose();
  }
}
