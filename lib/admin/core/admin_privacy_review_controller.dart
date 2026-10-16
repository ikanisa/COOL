import 'package:flutter/foundation.dart';
import 'admin_privacy_review_checkpoint.dart';
import 'admin_privacy_review_models.dart';
import 'admin_privacy_review_sdk.dart';

class AdminPrivacyReviewController extends ChangeNotifier {
  AdminPrivacyReviewController({
    required this.api,
    required this.actorId,
    required this.sessionId,
    required this.store,
    required this.now,
    required this.isCurrent,
    required this.newOperationId,
  });
  final AdminPrivacyReviewApi api;
  final String actorId, sessionId;
  final AdminPrivacyReviewStore? store;
  final DateTime Function() now;
  final bool Function() isCurrent;
  final String Function() newOperationId;
  AdminPrivacyReviewPage? page;
  AdminPrivacyReviewDetail? detail;
  AdminPrivacyReviewIntent? pending;
  String? selectedRequest, error, notice;
  bool loading = false, busy = false, denied = false, checkpointReady = false;
  bool _disposed = false;
  int _generation = 0, _journalGeneration = 0;
  final _cursors = <AdminPrivacyReviewCursor?>[null];
  int pageIndex = 0;
  bool _owns(int g) => !_disposed && g == _generation;
  bool _valid(int g) => _owns(g) && isCurrent();
  bool get hasPrevious => pageIndex > 0;
  bool get hasNext => page?.next != null;
  bool get idle => !_disposed && !busy && !loading && !denied && isCurrent();
  bool get canStart =>
      idle &&
      checkpointReady &&
      pending == null &&
      detail?.canStart(now()) == true;
  bool get canRecord =>
      idle &&
      checkpointReady &&
      pending == null &&
      detail?.canRecord(now()) == true;
  bool get canRetry =>
      idle &&
      checkpointReady &&
      pending != null &&
      detail != null &&
      pending!.applicable(detail!, now());
  void _emit() {
    if (!_disposed) notifyListeners();
  }

  void _redact(int g) {
    if (!_owns(g)) return;
    _generation++;
    page = null;
    detail = null;
    pending = null;
    selectedRequest = null;
    loading = false;
    busy = false;
    denied = true;
    checkpointReady = false;
    notice = null;
    error =
        'Current platform-owner access, users read and audit read permissions are required. Sign in again and reopen this page.';
    _emit();
  }

  void _failure(Object e, int g, String message) {
    if (privacyReviewDenied(e) || !isCurrent()) {
      _redact(g);
      return;
    }
    if (_valid(g)) error = message;
  }

  Future<bool> _checkpoint(int g) async {
    checkpointReady = false;
    if (store == null) return _valid(g);
    try {
      final saved = await store!.read(actorId, sessionId);
      if (!_valid(g)) return false;
      if (saved.pending != null &&
          (saved.pending!.actorId != actorId ||
              saved.pending!.sessionId != sessionId)) {
        privacyReviewInvalid();
      }
      _journalGeneration = saved.generation;
      pending = saved.pending;
      checkpointReady = true;
    } catch (_) {
      if (!_valid(g)) return false;
      error =
          'The original operation checkpoint could not be read. Review is available; actions require working browser storage.';
    }
    return _valid(g);
  }

  Future<void> refresh({bool firstPage = false}) async {
    if (!idle) return;
    final g = ++_generation;
    loading = true;
    error = null;
    notice = null;
    page = null;
    detail = null;
    if (firstPage) {
      pageIndex = 0;
      _cursors.removeRange(1, _cursors.length);
    }
    _emit();
    try {
      if (!await _checkpoint(g)) return;
      final p = await api.list(before: _cursors[pageIndex]);
      if (!_valid(g)) {
        _redact(g);
        return;
      }
      page = p;
      selectedRequest = pending?.requestId ?? selectedRequest;
      if (selectedRequest != null) {
        final d = await api.detail(selectedRequest!);
        if (!_valid(g)) {
          _redact(g);
          return;
        }
        detail = d;
      }
      if (pending != null) {
        notice =
            'An original operation is unresolved. Check its status before another action.';
      }
    } catch (e) {
      _failure(
        e,
        g,
        'Current privacy review evidence could not be verified. Refresh to try again.',
      );
    } finally {
      if (_valid(g)) {
        loading = false;
        _emit();
      }
    }
  }

  Future<void> open(String requestId) async {
    if (!idle) return;
    privacyReviewUuid(requestId);
    final g = ++_generation;
    loading = true;
    detail = null;
    error = null;
    notice = null;
    selectedRequest = requestId;
    _emit();
    try {
      if (!await _checkpoint(g)) return;
      final d = await api.detail(requestId);
      if (!_valid(g)) {
        _redact(g);
        return;
      }
      detail = d;
    } catch (e) {
      _failure(
        e,
        g,
        'This request could not be verified. Refresh the review evidence.',
      );
    } finally {
      if (_valid(g)) {
        loading = false;
        _emit();
      }
    }
  }

  Future<void> nextPage() async {
    if (!idle || !hasNext) return;
    final cursor = page!.next!;
    _cursors.removeRange(pageIndex + 1, _cursors.length);
    _cursors.add(cursor);
    pageIndex++;
    await refresh();
  }

  Future<void> previousPage() async {
    if (!idle || !hasPrevious) return;
    pageIndex--;
    await refresh();
  }

  Future<bool> _pendingCurrent(AdminPrivacyReviewIntent i, int g) async {
    final saved = await store!.read(actorId, sessionId);
    if (!_valid(g)) {
      _redact(g);
      return false;
    }
    if (saved.generation != _journalGeneration ||
        saved.pending?.fingerprint != i.fingerprint) {
      checkpointReady = false;
      error =
          'Another tab changed the original operation checkpoint. Refresh before continuing.';
      return false;
    }
    return true;
  }

  Future<void> _finish(
    AdminPrivacyReviewIntent i,
    Object receipt,
    int g,
  ) async {
    i.checkReceipt(receipt);
    if (!await _pendingCurrent(i, g)) return;
    await store!.complete(i, _journalGeneration, receipt);
    if (!_valid(g)) {
      _redact(g);
      return;
    }
    final saved = await store!.read(actorId, sessionId);
    if (!_valid(g)) {
      _redact(g);
      return;
    }
    if (saved.pending != null || saved.generation != _journalGeneration + 1) {
      privacyReviewInvalid();
    }
    _journalGeneration = saved.generation;
    pending = null;
    notice = i.kind == AdminPrivacyReviewOperationKind.claim
        ? 'Review start recorded. Current claim authority is checked again below.'
        : 'Policy blocker recorded. Deletion is waiting for approved policy; no data was erased.';
    detail = null;
    final d = await api.detail(i.requestId);
    if (!_valid(g)) {
      _redact(g);
      return;
    }
    selectedRequest = i.requestId;
    detail = d;
    final p = await api.list(before: _cursors[pageIndex]);
    if (!_valid(g)) {
      _redact(g);
      return;
    }
    page = p;
  }

  Future<void> startReview() => _begin(AdminPrivacyReviewOperationKind.claim);
  Future<void> recordPolicyBlocker() =>
      _begin(AdminPrivacyReviewOperationKind.outcome);
  Future<void> _begin(AdminPrivacyReviewOperationKind kind) async {
    if (kind == AdminPrivacyReviewOperationKind.claim
        ? !canStart
        : !canRecord) {
      return;
    }
    final g = _generation, d = detail!;
    busy = true;
    error = null;
    notice = null;
    _emit();
    try {
      final i = kind == AdminPrivacyReviewOperationKind.claim
          ? AdminPrivacyReviewIntent.claim(
              operationId: newOperationId(),
              actorId: actorId,
              sessionId: sessionId,
              detail: d,
            )
          : AdminPrivacyReviewIntent.outcome(
              operationId: newOperationId(),
              actorId: actorId,
              sessionId: sessionId,
              detail: d,
            );
      // Durable reservation and readback must finish before a server write.
      await store!.reserve(i, _journalGeneration);
      if (!_valid(g)) {
        _redact(g);
        return;
      }
      pending = i;
      _journalGeneration++;
      if (!await _pendingCurrent(i, g)) return;
      final receipt = await api.write(i, d);
      if (!_valid(g)) {
        _redact(g);
        return;
      }
      await _finish(i, receipt, g);
    } catch (e) {
      _failure(
        e,
        g,
        pending == null
            ? 'The original operation could not be reserved in browser storage. No server action was started. Refresh before trying again.'
            : 'The original operation needs a status check. Its identifier is retained; no replacement action is allowed.',
      );
    } finally {
      if (_valid(g)) {
        busy = false;
        _emit();
      }
    }
  }

  Future<void> resolve() async {
    if (!idle || pending == null || store == null) return;
    final g = _generation, i = pending!;
    busy = true;
    error = null;
    notice = null;
    _emit();
    try {
      // Lookup is read-only even when storage is temporarily unavailable. A
      // verified receipt still needs a successful compare-and-clear journal
      // operation before the retained original can be released.
      final observed = await api.resolve(i);
      if (!_valid(g)) {
        _redact(g);
        return;
      }
      if (observed.observed) {
        await _finish(i, observed.receipt!, g);
      } else {
        // A late original write may still arrive after this read. Unseen is
        // never treated as failure or permission to allocate a new UUID.
        final d = await api.detail(i.requestId);
        if (!_valid(g)) {
          _redact(g);
          return;
        }
        selectedRequest = i.requestId;
        detail = d;
        notice =
            'The original operation has not been observed yet. It may still arrive. Keep its identifier; an explicit retry uses the same operation.';
      }
    } catch (e) {
      _failure(
        e,
        g,
        'The original operation could not be resolved. Its identifier remains retained.',
      );
    } finally {
      if (_valid(g)) {
        busy = false;
        _emit();
      }
    }
  }

  Future<void> retryOriginal() async {
    if (!canRetry || store == null) return;
    final g = _generation, i = pending!;
    busy = true;
    error = null;
    notice = null;
    _emit();
    try {
      if (!await _pendingCurrent(i, g)) return;
      final observed = await api.resolve(i);
      if (!_valid(g)) {
        _redact(g);
        return;
      }
      if (observed.observed) {
        await _finish(i, observed.receipt!, g);
        return;
      }
      final d = await api.detail(i.requestId);
      if (!_valid(g)) {
        _redact(g);
        return;
      }
      selectedRequest = i.requestId;
      detail = d;
      if (!i.applicable(d, now())) {
        notice =
            'Current evidence does not allow a retry. Keep checking the original operation; an expired or changed claim cannot record a blocker.';
        return;
      }
      if (!await _pendingCurrent(i, g)) return;
      final receipt = await api.write(i, d);
      if (!_valid(g)) {
        _redact(g);
        return;
      }
      await _finish(i, receipt, g);
    } catch (e) {
      _failure(
        e,
        g,
        'The original retry remains unresolved. Keep the same operation identifier and check its status.',
      );
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
