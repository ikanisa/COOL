import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'admin_receipt_operations_models.dart';
import 'admin_receipt_principal_checkpoint.dart';
import 'admin_receipt_principal_models.dart';

class AdminReceiptPrincipalControlState {
  const AdminReceiptPrincipalControlState({
    this.pending = const [],
    this.busy = false,
    this.storageBlocked = false,
    this.departed = false,
    this.message,
    this.receipt,
  });
  final List<AdminReceiptPrincipalCheckpoint> pending;
  final bool busy, storageBlocked, departed;
  final String? message;

  /// Validated point-in-time action evidence, never a current identity state.
  final AdminReceiptPrincipalReceipt? receipt;
}

/// A user-initiated, single attempt with durable metadata before transport.
/// Parents pass a sticky authority scope or call depart() on its first loss.
/// Restored bindings can only be looked up; they cannot reach send().
class AdminReceiptPrincipalController
    extends StateNotifier<AdminReceiptPrincipalControlState> {
  AdminReceiptPrincipalController({
    required this.ownerDigest,
    required this.store,
    required this.now,
    required this.isCurrent,
    required this.preflight,
    required this.send,
    required this.lookup,
    this.timeout = const Duration(seconds: 15),
  }) : super(const AdminReceiptPrincipalControlState(busy: true)) {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(ownerDigest) ||
        timeout <= Duration.zero ||
        timeout > const Duration(seconds: 15)) {
      operationsInvalid();
    }
    ready = reload();
  }

  final String ownerDigest;
  final AdminReceiptPrincipalCheckpointStore? store;
  final DateTime Function() now;
  final bool Function() isCurrent;

  /// Root validates a fresh current identity/key/expiry before activate/revoke;
  /// enrollment checks current owner authority. No mutation occurs here.
  final Future<bool> Function(AdminReceiptPrincipalIntent) preflight;
  final Future<Map<String, dynamic>> Function(AdminReceiptPrincipalIntent) send;
  final Future<Map<String, dynamic>> Function(AdminReceiptPrincipalBinding)
  lookup;
  final Duration timeout;
  late final Future<void> ready;
  final _inFlight = <String, AdminReceiptPrincipalBinding>{};
  final _checking = <String>{};
  bool _departed = false, _loading = false;

  bool get _current {
    if (_departed || !mounted) return false;
    if (!isCurrent()) {
      _departed = true;
      return false;
    }
    return true;
  }

  void depart() {
    _departed = true;
    if (mounted) {
      state = const AdminReceiptPrincipalControlState(departed: true);
    }
  }

  @override
  void dispose() {
    _departed = true;
    super.dispose();
  }

  void _emit({
    List<AdminReceiptPrincipalCheckpoint>? pending,
    bool? storageBlocked,
    String? message,
    AdminReceiptPrincipalReceipt? receipt,
  }) {
    if (!_current) return;
    state = AdminReceiptPrincipalControlState(
      pending: List.unmodifiable(pending ?? state.pending),
      busy: _loading || _inFlight.isNotEmpty || _checking.isNotEmpty,
      storageBlocked: storageBlocked ?? state.storageBlocked,
      message: message ?? state.message,
      receipt: receipt ?? state.receipt,
    );
  }

  Future<List<AdminReceiptPrincipalCheckpoint>> _readPending() async {
    if (store == null) operationsInvalid();
    final rows = await store!.read(ownerDigest).timeout(timeout);
    if (rows.length > adminReceiptPrincipalMaximumPending) operationsInvalid();
    final pending = rows
        .map((row) => AdminReceiptPrincipalCheckpoint.parse(row, ownerDigest))
        .toList();
    if (pending.map((p) => p.requestId).toSet().length != pending.length) {
      operationsInvalid();
    }
    return pending;
  }

  Future<void> reload() async {
    if (!_current || _loading || _inFlight.isNotEmpty || _checking.isNotEmpty) {
      return;
    }
    _loading = true;
    _emit();
    try {
      final pending = await _readPending();
      if (!_current) return;
      _emit(pending: pending, storageBlocked: false);
    } catch (_) {
      _emit(
        storageBlocked: true,
        message: 'Recovery storage could not be verified. No request was sent.',
      );
    } finally {
      _loading = false;
      _emit();
    }
  }

  bool canSubmit(AdminReceiptPrincipalBinding binding) {
    if (!_current ||
        _loading ||
        state.storageBlocked ||
        store == null ||
        _inFlight.length >= 2 ||
        _inFlight.containsKey(binding.requestId) ||
        _checking.contains(binding.requestId) ||
        !adminReceiptPrincipalMayPublish(state.pending, binding)) {
      return false;
    }
    if (binding.action != AdminReceiptPrincipalAction.revoke) {
      return _inFlight.isEmpty && _checking.isEmpty;
    }
    return canBeginRevocation(binding.principalId!);
  }

  /// A structural UI gate only. submit() still requires an exact fresh intent,
  /// current identity preflight and exclusive durable publication before HTTP.
  bool canBeginRevocation(String principalId) {
    if (!_current ||
        _loading ||
        state.storageBlocked ||
        store == null ||
        _inFlight.length >= 2 ||
        state.pending.length >= adminReceiptPrincipalMaximumPending) {
      return false;
    }
    try {
      operationsUuid(principalId);
    } catch (_) {
      return false;
    }
    return !state.pending.any(
          (p) =>
              p.binding.action == AdminReceiptPrincipalAction.revoke &&
              p.binding.principalId == principalId,
        ) &&
        !_inFlight.values.any(
          (p) =>
              p.action == AdminReceiptPrincipalAction.revoke &&
              p.principalId == principalId,
        );
  }

  List<AdminReceiptPrincipalCheckpoint> _merge(
    Iterable<AdminReceiptPrincipalCheckpoint> rows,
  ) {
    final values = {for (final p in state.pending) p.requestId: p};
    for (final row in rows) {
      final old = values[row.requestId];
      if (old != null && old.digest != row.digest) operationsInvalid();
      values[row.requestId] = row;
    }
    if (values.length > adminReceiptPrincipalMaximumPending) {
      operationsInvalid();
    }
    return values.values.toList();
  }

  Future<void> submit(AdminReceiptPrincipalIntent intent) async {
    await ready;
    if (!canSubmit(intent)) return;
    if (!intent.canSubmitAt(now())) {
      _emit(
        message: 'The original request window expired. No request was sent.',
      );
      return;
    }
    _inFlight[intent.requestId] = AdminReceiptPrincipalBinding.fromIntent(
      intent,
    );
    _emit(message: 'Checking current authority and identity…');
    try {
      final allowed = await preflight(intent).timeout(timeout);
      if (!_current) return;
      if (!allowed || !intent.canSubmitAt(now())) {
        _emit(
          message:
              'Current identity or request window could not be verified. No request was sent.',
        );
        return;
      }
      final original = AdminReceiptPrincipalCheckpoint.fromIntent(
        ownerDigest,
        intent,
      );
      var publicationOpen = true;
      try {
        await store!
            .write(
              ownerDigest,
              original.requestId,
              original.encode(),
              isCurrent: () => publicationOpen && _current,
            )
            .timeout(timeout);
        final pending = await _readPending();
        if (!_current) return;
        if (!pending.any((p) => p.digest == original.digest)) {
          operationsInvalid();
        }
        _emit(pending: _merge(pending));
      } catch (_) {
        _emit(
          pending: _merge([original]),
          storageBlocked: true,
          message:
              'The original bookmark could not be saved and read back. The request was not sent.',
        );
        return;
      } finally {
        publicationOpen = false;
      }
      if (!_current) return;
      if (!intent.canSubmitAt(now())) {
        _emit(
          message:
              'The retained deadline expired before submission. Check the original ID; the request was not sent.',
        );
        return;
      }
      try {
        final raw = await send(intent).timeout(timeout);
        if (!_current) return;
        final receipt = AdminReceiptPrincipalReceipt.parse(
          raw,
          binding: original.binding,
        );
        if (receipt.recordedAt.isAfter(
          now().add(const Duration(seconds: 10)),
        )) {
          operationsInvalid();
        }
        await _resolve(original, 'recorded', receipt);
      } catch (_) {
        _emit(
          message:
              'The outcome is unknown. Look up the original request; it will not be resubmitted.',
        );
      }
    } catch (_) {
      _emit(
        message:
            'Current authority or identity could not be verified. No request was sent.',
      );
    } finally {
      _inFlight.remove(intent.requestId);
      _emit();
    }
  }

  Future<void> _resolve(
    AdminReceiptPrincipalCheckpoint checkpoint,
    String status,
    AdminReceiptPrincipalReceipt? receipt,
  ) async {
    if (!_current || store == null) operationsInvalid();
    var resolutionOpen = true;
    try {
      await store!
          .resolve(
            checkpoint,
            status,
            isCurrent: () => resolutionOpen && _current,
          )
          .timeout(timeout);
      if (!_current) return;
      _emit(
        pending: state.pending
            .where((p) => p.requestId != checkpoint.requestId)
            .toList(),
        receipt: receipt,
        message: status == 'recorded'
            ? 'Original request recorded. Refresh to verify current identity.'
            : 'Original request was not recorded after its deadline. No request was replayed.',
      );
    } finally {
      resolutionOpen = false;
    }
  }

  Future<void> reconcile(AdminReceiptPrincipalCheckpoint checkpoint) async {
    await ready;
    if (!_current ||
        _loading ||
        _checking.contains(checkpoint.requestId) ||
        _inFlight.containsKey(checkpoint.requestId) ||
        checkpoint.ownerDigest != ownerDigest ||
        !state.pending.any((p) => p.digest == checkpoint.digest)) {
      return;
    }
    _checking.add(checkpoint.requestId);
    final started = now();
    _emit(message: 'Looking up the original request…');
    try {
      final raw = await lookup(checkpoint.binding).timeout(timeout);
      if (!_current) return;
      final observed = AdminReceiptPrincipalLookup.parse(
        raw,
        binding: checkpoint.binding,
      );
      if (!observed.isFresh(now()) ||
          observed.checkedAt.isBefore(
            started.subtract(const Duration(seconds: 10)),
          )) {
        operationsInvalid();
      }
      if (observed.status == 'recorded') {
        await _resolve(checkpoint, 'recorded', observed.receipt);
      } else if (observed.provesExpiredAbsence(now())) {
        await _resolve(checkpoint, 'not_recorded_after_deadline', null);
      } else {
        _emit(
          message: observed.status == 'in_progress'
              ? 'The original request is still in progress. Check again manually.'
              : 'The original request window is still open. Its outcome remains unknown.',
        );
      }
    } catch (_) {
      _emit(
        message:
            'The original outcome could not be verified. Keep its ID and look it up manually.',
      );
    } finally {
      _checking.remove(checkpoint.requestId);
      _emit();
    }
  }
}
