import 'package:flutter/foundation.dart';
import 'admin_receipt_notice_content_models.dart';
import 'admin_receipt_notice_content_sdk.dart';
import 'admin_receipt_notice_content_checkpoint.dart';

class AdminReceiptNoticeContentController extends ChangeNotifier {
  AdminReceiptNoticeContentController({
    required this.api,
    required this.actorId,
    required this.sessionId,
    required this.collectionId,
    required this.policy,
    required this.store,
    required this.now,
    required this.isCurrent,
    required this.canManage,
    required this.newRequestId,
    this.outboxId,
    this.sourceSnapshotId,
    this.onRecorded,
    this.preserveRecordedContent,
  });
  final AdminReceiptNoticeContentApi api;
  final String actorId, sessionId, collectionId;
  final bool policy;
  final String? outboxId, sourceSnapshotId;
  final AdminReceiptNoticeContentStore? store;
  final DateTime Function() now;
  final bool Function() isCurrent, canManage;
  final String Function() newRequestId;
  final VoidCallback? onRecorded;
  final Future<void> Function(
    AdminReceiptNoticeIntent original,
    AdminReceiptNoticeRequest recorded,
  )?
  preserveRecordedContent;
  AdminReceiptNoticeInspection? inspection;
  AdminReceiptNoticeIntent? pending;
  AdminReceiptNoticeRequest? receipt;
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
    inspection = null;
    pending = null;
    receipt = null;
    busy = false;
    loading = false;
    error =
        'Current email-owner access is required. Restore access before continuing.';
    _emit();
  }

  bool get canRecord =>
      !loading &&
      !busy &&
      pending == null &&
      store != null &&
      (policy || preserveRecordedContent != null) &&
      isCurrent() &&
      canManage() &&
      inspection != null &&
      inspection!.fresh(now()) &&
      (policy || inspection!.canPrepare);
  Future<void> refresh({
    required AdminReceiptNoticeFamily family,
    String language = 'rw',
    bool enabled = true,
    String? sourceOverride,
  }) async {
    if (_disposed || !isCurrent() || busy) return;
    final g = ++_generation;
    loading = true;
    inspection = null;
    receipt = null;
    error = null;
    _emit();
    try {
      final retained = await store?.read(actorId, sessionId);
      if (!_valid(g)) return;
      if (retained != null) {
        if (retained.actorId != actorId || retained.sessionId != sessionId) {
          noticeInvalid();
        }
        pending = retained;
      }
      if (pending != null) {
        error =
            'Recover the retained original request before recording another change.';
        return;
      }
      final value = policy
          ? await api.inspectPolicy(collectionId, family, language, enabled)
          : await api.inspectContent(
              outboxId!,
              sourceOverride ?? sourceSnapshotId!,
              collectionId,
              family,
            );
      if (!_valid(g)) return;
      inspection = value;
    } catch (e) {
      if (noticeDenied(e)) {
        _redact(g);
        return;
      }
      if (_valid(g)) {
        inspection = null;
        error = 'The notice preview could not be loaded. Refresh to try again.';
      }
    } finally {
      if (_valid(g)) {
        loading = false;
        _emit();
      }
    }
  }

  void invalidatePreview() {
    if (_disposed || busy) return;
    _generation++;
    inspection = null;
    receipt = null;
    error = null;
    loading = false;
    _emit();
  }

  Future<void> record(String reason) async {
    if (!canRecord) return;
    final g = _generation;
    busy = true;
    error = null;
    _emit();
    try {
      final i = AdminReceiptNoticeIntent.create(
        inspection: inspection!,
        requestId: newRequestId(),
        actorId: actorId,
        sessionId: sessionId,
        reason: reason,
        now: now(),
      );
      pending = i;
      await store!.write(i);
      if (!_valid(g)) return;
      if ((await store!.read(actorId, sessionId))?.fingerprint !=
          i.fingerprint) {
        noticeInvalid();
      }
      if (!_valid(g)) return;
      final value = await api.record(i);
      if (!_valid(g)) return;
      receipt = value;
      if (!policy) {
        final preserve = preserveRecordedContent;
        if (preserve == null) noticeInvalid();
        await preserve(i, value);
        if (!_valid(g)) return;
      }
      await store!.clear(i);
      if (!_valid(g)) return;
      pending = null;
      inspection = null;
      error = policy
          ? 'Notice policy recorded. Refresh for current values.'
          : 'Immutable notice content recorded. Sending approval remains separate.';
      onRecorded?.call();
    } catch (e) {
      if (noticeDenied(e)) {
        _redact(g);
        return;
      }
      if (_valid(g)) {
        error = pending == null
            ? 'Enter a reason of 8–500 characters before recording.'
            : 'The original request requires recovery. Its identifier is retained.';
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
      final value = await api.recover(i);
      if (!_valid(g)) return;
      receipt = value;
      if (value.recorded) {
        if (!i.policy) {
          final preserve = preserveRecordedContent;
          if (preserve == null) noticeInvalid();
          await preserve(i, value);
          if (!_valid(g)) return;
        }
        await store!.clear(i);
        if (!_valid(g)) return;
        pending = null;
        inspection = null;
        error =
            'The original request was recovered. Refresh for current values.';
        onRecorded?.call();
      } else {
        error =
            'The original request is not recorded. Its outcome remains unresolved; replacement requests are blocked.';
      }
    } catch (e) {
      if (noticeDenied(e)) {
        _redact(g);
        return;
      }
      if (_valid(g)) {
        error =
            'Original-request recovery is unavailable. The checkpoint remains retained.';
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
