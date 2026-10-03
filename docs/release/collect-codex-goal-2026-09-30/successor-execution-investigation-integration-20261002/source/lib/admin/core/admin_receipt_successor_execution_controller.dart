import 'package:flutter/foundation.dart';
import 'admin_receipt_cancel_models.dart';
import 'admin_receipt_successor_execution_models.dart';
import 'admin_receipt_successor_execution_sdk.dart';

/// One current owner/session and immutable approval/root target. Historical
/// pages retain the first summary cutoff; refresh explicitly starts a new read.
class AdminReceiptSuccessorExecutionController extends ChangeNotifier {
  AdminReceiptSuccessorExecutionController({
    required this.api,
    required this.approvalId,
    required this.primaryReceiptId,
    required this.isCurrent,
  }) {
    cancelUuid(approvalId);
    cancelUuid(primaryReceiptId);
  }
  final AdminReceiptSuccessorExecutionApi api;
  final String approvalId, primaryReceiptId;
  final bool Function() isCurrent;
  AdminReceiptSuccessorExecutionSnapshot? snapshot;
  List<Map<String, dynamic>> observations = const [];
  int? next;
  bool loading = false, historyBusy = false, _disposed = false;
  String? error;
  int _generation = 0;
  bool _valid(int generation) =>
      !_disposed && generation == _generation && isCurrent();
  void _publish() {
    if (!_disposed && isCurrent()) notifyListeners();
  }

  // Clear this owned generation even when a server session denial precedes a
  // local identity update. A departed generation cannot affect a new read.
  void _forget(int generation, String message) {
    if (_disposed || generation != _generation) return;
    _generation++;
    snapshot = null;
    observations = const [];
    next = null;
    loading = false;
    historyBusy = false;
    error = message;
    notifyListeners();
  }

  bool _denied(Object error) =>
      error is AdminReceiptSuccessorExecutionDenied ||
      executionAccessDenied(error);

  Future<void> refresh() async {
    if (_disposed || !isCurrent()) return;
    final generation = ++_generation;
    loading = true;
    historyBusy = false;
    error = null;
    snapshot = null;
    observations = const [];
    next = null;
    _publish();
    try {
      final current = await api.inspect(approvalId, primaryReceiptId);
      if (!_valid(generation)) return;
      AdminReceiptSuccessorObservationPage? page;
      if (current.available) page = await api.observations(current);
      if (!_valid(generation)) return;
      snapshot = current;
      if (page != null) {
        if (!page.available) {
          throw StateError('Receipt execution became unavailable.');
        }
        observations = List.unmodifiable(page.items);
        next = page.next;
      }
    } catch (failure) {
      if (_denied(failure)) {
        _forget(
          generation,
          'Current access to receipt execution evidence is denied. Refresh after restoring access.',
        );
        return;
      }
      if (!_valid(generation)) return;
      snapshot = null;
      observations = const [];
      next = null;
      error =
          'Receipt execution evidence could not be loaded. Refresh to try again.';
    } finally {
      if (_valid(generation)) {
        loading = false;
        _publish();
      }
    }
  }

  Future<void> more() async {
    final current = snapshot, after = next, generation = _generation;
    if (_disposed ||
        !isCurrent() ||
        loading ||
        historyBusy ||
        current == null ||
        after == null) {
      return;
    }
    historyBusy = true;
    error = null;
    _publish();
    try {
      final page = await api.observations(current, after: after);
      if (!_valid(generation) || !identical(snapshot, current)) return;
      if (!page.available) {
        _forget(
          generation,
          'This approval’s execution evidence is unavailable.',
        );
        return;
      }
      final existing = observations.map((r) => r['request_id']).toSet();
      if (page.items.any((r) => existing.contains(r['request_id']))) {
        executionInvalid();
      }
      observations = List.unmodifiable([...observations, ...page.items]);
      next = page.next;
    } catch (failure) {
      if (_denied(failure)) {
        _forget(
          generation,
          'Current access to receipt execution evidence is denied. Refresh after restoring access.',
        );
        return;
      }
      if (!_valid(generation)) return;
      error =
          'More callback evidence could not be loaded. The current page is retained.';
    } finally {
      if (_valid(generation)) {
        historyBusy = false;
        _publish();
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
