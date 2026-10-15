import 'package:flutter/foundation.dart';
import 'admin_receipt_notice_content_models.dart';
import 'admin_receipt_notice_content_sdk.dart';
import 'admin_receipt_notice_dispatch_models.dart';
import 'admin_receipt_notice_dispatch_sdk.dart';
import 'admin_receipt_notice_dispatch_checkpoint.dart';

class AdminReceiptNoticeDispatchController extends ChangeNotifier {
  AdminReceiptNoticeDispatchController({
    required this.api,
    required this.actorId,
    required this.sessionId,
    required this.isCurrent,
    required this.canManage,
    required this.now,
    required this.newRequestId,
    this.store,
    this.reference,
    this.onRecorded,
  });
  final AdminReceiptNoticeDispatchApi api;
  final String actorId, sessionId;
  final bool Function() isCurrent, canManage;
  final DateTime Function() now;
  final String Function() newRequestId;
  final AdminReceiptNoticeDispatchStore? store;
  final AdminReceiptNoticePreparedReference? reference;
  final VoidCallback? onRecorded;
  AdminReceiptNoticeDispatchInspection? inspection;
  AdminReceiptNoticeDispatchConfiguration? configuration;
  AdminReceiptNoticeDispatchIntent? pending;
  AdminReceiptNoticeDispatchRequest? receipt;
  Map<String, dynamic>? approval;
  String? error;
  bool loading = false, busy = false, _disposed = false;
  int _generation = 0;
  bool get configurationOnly => reference == null;
  bool _valid(int generation) =>
      !_disposed && generation == _generation && isCurrent();
  void _emit() {
    if (!_disposed) notifyListeners();
  }

  bool get canRecord =>
      !loading &&
      !busy &&
      pending == null &&
      store != null &&
      isCurrent() &&
      canManage() &&
      (configuration?.fresh(now()) ?? inspection?.fresh(now()) ?? false);
  bool get canApprove =>
      !configurationOnly && canRecord && inspection?.canApprove == true;
  bool get canRevoke =>
      !configurationOnly &&
      canRecord &&
      approval != null &&
      inspection?.revision == approval!['transport_revision'] &&
      const {
        'notice_approval_pending',
        'notice_already_materialized',
      }.contains(inspection?.reason);
  void _redact(int generation) {
    if (_disposed || generation != _generation) return;
    _generation++;
    inspection = null;
    configuration = null;
    pending = null;
    receipt = null;
    approval = null;
    loading = false;
    busy = false;
    error =
        'Current email-owner access is required. Restore access before continuing.';
    _emit();
  }

  Future<void> refresh() async {
    if (_disposed || !isCurrent() || busy) return;
    final generation = ++_generation;
    loading = true;
    inspection = null;
    configuration = null;
    receipt = null;
    approval = null;
    error = null;
    _emit();
    try {
      final retained = await store?.pending(actorId, sessionId);
      if (!_valid(generation)) return;
      pending = retained;
      if (pending != null) {
        error =
            'Recover the retained original request before recording another change.';
        return;
      }
      if (configurationOnly) {
        final sample = await api.configuration();
        if (!_valid(generation)) return;
        configuration = sample;
      } else {
        final ref = reference!;
        if (ref.actorId != actorId || ref.sessionId != sessionId) {
          noticeInvalid();
        }
        final saved = await store?.readPrepared(
          actorId,
          sessionId,
          ref.originalRequestId,
        );
        if (!_valid(generation)) return;
        if (store != null && saved?.fingerprint != ref.fingerprint) {
          noticeInvalid();
        }
        final sample = await api.inspect(ref);
        if (!_valid(generation)) return;
        final recordedApproval = await store?.approval(ref);
        if (!_valid(generation)) return;
        inspection = sample;
        approval = recordedApproval;
      }
    } catch (e) {
      if (noticeDenied(e)) {
        _redact(generation);
        return;
      }
      if (_valid(generation)) {
        error =
            'Current dispatch evidence or durable prepared handoff is unavailable. Refresh to try again.';
      }
    } finally {
      if (_valid(generation)) {
        loading = false;
        _emit();
      }
    }
  }

  Future<void> record(
    AdminReceiptNoticeDispatchAction action,
    String reason, {
    bool? enabled,
  }) async {
    if (!canRecord ||
        action == AdminReceiptNoticeDispatchAction.approve && !canApprove ||
        action == AdminReceiptNoticeDispatchAction.revoke && !canRevoke ||
        (action == AdminReceiptNoticeDispatchAction.configure) !=
            configurationOnly) {
      return;
    }
    final generation = _generation;
    busy = true;
    error = null;
    _emit();
    try {
      final intent = AdminReceiptNoticeDispatchIntent.create(
        action: action,
        actorId: actorId,
        sessionId: sessionId,
        requestId: newRequestId(),
        reason: reason,
        now: now(),
        reference: reference,
        inspection: inspection,
        configuration: configuration,
        enabled: enabled,
        approval: action == AdminReceiptNoticeDispatchAction.revoke
            ? approval
            : null,
      );
      pending = intent;
      await store!.savePending(intent);
      if (!_valid(generation)) return;
      if ((await store!.pending(actorId, sessionId))?.fingerprint !=
          intent.fingerprint) {
        noticeInvalid();
      }
      if (!_valid(generation)) return;
      final result = await api.record(intent);
      if (!_valid(generation)) return;
      await store!.complete(intent, result);
      if (!_valid(generation)) return;
      pending = null;
      receipt = result;
      inspection = null;
      configuration = null;
      approval = null;
      error =
          'Original request recorded. Refresh for current dispatch evidence.';
      onRecorded?.call();
    } catch (e) {
      if (noticeDenied(e)) {
        _redact(generation);
        return;
      }
      if (_valid(generation)) {
        error = pending == null
            ? 'Enter a reason of 8–500 characters before recording.'
            : 'The original request requires recovery. Its identifier remains retained.';
      }
    } finally {
      if (_valid(generation)) {
        busy = false;
        _emit();
      }
    }
  }

  Future<void> recover() async {
    final intent = pending;
    if (intent == null || busy || _disposed || !isCurrent() || store == null) {
      return;
    }
    final generation = _generation;
    busy = true;
    error = null;
    _emit();
    try {
      final result = await api.recover(intent);
      if (!_valid(generation)) return;
      if (result.recorded) {
        await store!.complete(intent, result);
        if (!_valid(generation)) return;
        pending = null;
        receipt = result;
        inspection = null;
        configuration = null;
        approval = null;
        error =
            'The original request was recovered. Refresh for current dispatch evidence.';
        onRecorded?.call();
      } else {
        error =
            'The original request is not recorded. Its outcome remains unresolved; replacement requests are blocked.';
      }
    } catch (e) {
      if (noticeDenied(e)) {
        _redact(generation);
        return;
      }
      if (_valid(generation)) {
        error =
            'Original-request recovery is unavailable. The checkpoint remains retained.';
      }
    } finally {
      if (_valid(generation)) {
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
