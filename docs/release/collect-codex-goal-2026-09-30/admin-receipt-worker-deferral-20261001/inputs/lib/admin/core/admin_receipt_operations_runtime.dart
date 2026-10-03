part of 'admin_runtime.dart';

class AdminReceiptOperationsDenied implements Exception {
  const AdminReceiptOperationsDenied();
}

final adminReceiptOperationsCheckpointStoreProvider =
    Provider<AdminReceiptOperationsCheckpointStore?>(
      (ref) => browserAdminReceiptOperationsCheckpointStore(),
    );

final adminReceiptOperationsPolicyProvider =
    FutureProvider.autoDispose<AdminReceiptOperationsPolicy>((ref) async {
      final scope = ref.watch(adminAuthSessionScopeProvider);
      ref.watch(_adminIdentityRevisionProvider);
      final repository = ref.watch(adminRepositoryProvider);
      var current = true;
      ref.onDispose(() => current = false);
      final identity = await ref.watch(adminIdentityProvider.future);
      if (!current) throw const AdminSessionChanged();
      if (scope == null ||
          identity?.userId != scope.key.userId ||
          !adminReceiptOperationsCanManage(identity)) {
        throw const AdminReceiptOperationsDenied();
      }
      try {
        final raw = await repository.receiptOperationsPolicy();
        if (!current) throw const AdminSessionChanged();
        return AdminReceiptOperationsPolicy.parse(raw);
      } on PostgrestException catch (error) {
        if (!current) throw const AdminSessionChanged();
        if (error.code == '42501') throw const AdminReceiptOperationsDenied();
        if ({'42883', 'PGRST202'}.contains(error.code)) {
          throw UnsupportedError(
            'Receipt operations policy service unavailable.',
          );
        }
        rethrow;
      } catch (_) {
        if (!current) throw const AdminSessionChanged();
        rethrow;
      }
    });

class AdminReceiptOperationsControlState {
  const AdminReceiptOperationsControlState({
    this.pending = const [],
    this.busy = false,
    this.storageBlocked = false,
    this.message,
  });
  final List<AdminReceiptOperationsCheckpoint> pending;
  final bool busy, storageBlocked;
  final String? message;
  bool get pendingStop => pending.any((p) => p.action == 'stop');
}

/// One user-initiated attempt; durable bookmarks contain no mutation payload.
/// A lookup can close uncertainty but cannot replay, recreate or extend it.
class AdminReceiptOperationsController
    extends StateNotifier<AdminReceiptOperationsControlState> {
  AdminReceiptOperationsController({
    required this.ownerDigest,
    required this.store,
    required this.now,
    required this.isCurrent,
    required this.send,
    required this.lookup,
  }) : super(const AdminReceiptOperationsControlState()) {
    reload();
  }
  final String ownerDigest;
  final AdminReceiptOperationsCheckpointStore? store;
  final DateTime Function() now;
  final bool Function() isCurrent;
  final Future<Map<String, dynamic>> Function(AdminReceiptOperationsIntent)
  send;
  final Future<Map<String, dynamic>> Function(String) lookup;
  bool _departed = false;
  bool get _current => !_departed && isCurrent();
  @override
  void dispose() {
    _departed = true;
    super.dispose();
  }

  void reload() {
    if (!_current || state.busy) return;
    try {
      if (store == null) {
        throw const FormatException('Recovery storage unavailable.');
      }
      final rows = store!.read(ownerDigest);
      if (rows.length > 50) operationsInvalid();
      final pending = rows
          .map(
            (row) => AdminReceiptOperationsCheckpoint.parse(row, ownerDigest),
          )
          .toList();
      if (pending.map((p) => p.requestId).toSet().length != pending.length) {
        operationsInvalid();
      }
      state = AdminReceiptOperationsControlState(
        pending: List.unmodifiable(pending),
        message: state.message,
      );
    } catch (_) {
      state = AdminReceiptOperationsControlState(
        pending: state.pending,
        storageBlocked: true,
        message:
            'Recovery storage could not be verified. No new policy request can be sent.',
      );
    }
  }

  Future<void> submit(AdminReceiptOperationsIntent intent) async {
    if (!_current ||
        state.busy ||
        state.storageBlocked ||
        store == null ||
        (state.pending.isNotEmpty &&
            (intent.action != 'stop' || state.pendingStop))) {
      return;
    }
    if (!intent.expiresAt.isAfter(now()) ||
        intent.createdAt.isAfter(now().add(const Duration(seconds: 5)))) {
      state = AdminReceiptOperationsControlState(
        pending: state.pending,
        message:
            'The request window expired. Refresh policy before preparing an action.',
      );
      return;
    }
    final checkpoint = AdminReceiptOperationsCheckpoint.fromIntent(
      ownerDigest,
      intent,
    );
    final pending = List<AdminReceiptOperationsCheckpoint>.unmodifiable([
      ...state.pending,
      checkpoint,
    ]);
    try {
      store!.write(ownerDigest, intent.requestId, checkpoint.encode());
      if (!store!.read(ownerDigest).contains(checkpoint.encode())) {
        operationsInvalid();
      }
    } catch (_) {
      state = AdminReceiptOperationsControlState(
        pending: pending,
        storageBlocked: true,
        message:
            'The recovery bookmark could not be saved and verified. The request was not sent.',
      );
      return;
    }
    if (!_current) return;
    if (!intent.expiresAt.isAfter(now())) {
      state = AdminReceiptOperationsControlState(
        pending: pending,
        message:
            'The retained request deadline expired before submission. The request was not sent. Check its original ID.',
      );
      return;
    }
    state = AdminReceiptOperationsControlState(
      pending: pending,
      busy: true,
      message: 'Checking the original policy request…',
    );
    try {
      final raw = await send(intent).timeout(const Duration(seconds: 15));
      if (!_current) return;
      final receipt = AdminReceiptOperationsReceipt.parse(raw);
      receipt.validateIntent(intent);
      checkpoint.validateReceipt(receipt);
      if (receipt.recordedAt.isAfter(now().add(const Duration(seconds: 5)))) {
        operationsInvalid();
      }
      store!.resolve(checkpoint, 'recorded');
      state = AdminReceiptOperationsControlState(
        pending: pending.where((p) => p.requestId != intent.requestId).toList(),
        message:
            'Policy request recorded. Refresh to verify the current policy.',
      );
    } catch (_) {
      if (!_current) return;
      state = AdminReceiptOperationsControlState(
        pending: pending,
        message:
            'The policy outcome is unknown. Check the original request; it will not be resubmitted.',
      );
    }
  }

  Future<void> reconcile(AdminReceiptOperationsCheckpoint checkpoint) async {
    if (!_current ||
        state.busy ||
        checkpoint.ownerDigest != ownerDigest ||
        !state.pending.any(
          (p) =>
              p.requestId == checkpoint.requestId &&
              p.digest == checkpoint.digest,
        )) {
      return;
    }
    final pending = state.pending;
    state = AdminReceiptOperationsControlState(
      pending: pending,
      busy: true,
      storageBlocked: state.storageBlocked,
      message: 'Looking up the original request…',
    );
    try {
      final raw = await lookup(
        checkpoint.requestId,
      ).timeout(const Duration(seconds: 15));
      if (!_current) return;
      final observation = AdminReceiptOperationsLookup.parse(
        raw,
        requestId: checkpoint.requestId,
      );
      if (!observation.isFresh(now())) operationsInvalid();
      String? resolution;
      if (observation.status == 'recorded') {
        checkpoint.validateReceipt(observation.receipt!);
        resolution = 'recorded';
      } else if (observation.status == 'not_recorded' &&
          !observation.checkedAt.isBefore(checkpoint.expiresAt)) {
        resolution = 'not_recorded_after_deadline';
      }
      if (resolution != null) {
        if (store == null) operationsInvalid();
        store!.resolve(checkpoint, resolution);
        state = AdminReceiptOperationsControlState(
          pending: pending
              .where((p) => p.requestId != checkpoint.requestId)
              .toList(),
          message: resolution == 'recorded'
              ? 'Original request recorded. Refresh current policy.'
              : 'Original request was not recorded after its deadline. No request was replayed.',
        );
      } else {
        state = AdminReceiptOperationsControlState(
          pending: pending,
          message: observation.status == 'in_progress'
              ? 'The original request is still in progress. Check again manually.'
              : 'No result is recorded yet. The original request window is still open; its outcome remains unknown.',
        );
      }
    } catch (_) {
      if (!_current) return;
      state = AdminReceiptOperationsControlState(
        pending: pending,
        message:
            'Original request outcome could not be verified. Keep the request ID and check again manually.',
      );
    }
  }
}

final adminReceiptOperationsControllerProvider =
    StateNotifierProvider.autoDispose<
      AdminReceiptOperationsController,
      AdminReceiptOperationsControlState
    >((ref) {
      final scope = ref.watch(adminAuthSessionScopeProvider);
      final identity = _adminResolvedIdentity(ref.watch(adminIdentityProvider));
      final identityRevision = ref.watch(_adminIdentityRevisionProvider);
      final repository = ref.watch(adminRepositoryProvider);
      final store = ref.watch(adminReceiptOperationsCheckpointStoreProvider);
      final clock = ref.watch(adminClockProvider);
      final enabled =
          scope != null &&
          identity?.userId == scope.key.userId &&
          adminReceiptOperationsCanManage(identity);
      var current = true;
      ref.onDispose(() => current = false);
      return AdminReceiptOperationsController(
        ownerDigest: enabled
            ? adminReceiptOperationsOwnerDigest(scope.key.userId)
            : '',
        store: enabled ? store : null,
        now: clock,
        isCurrent: () =>
            enabled &&
            current &&
            ref.read(adminAuthSessionScopeProvider) == scope &&
            ref.read(_adminIdentityRevisionProvider) == identityRevision &&
            adminReceiptOperationsCanManage(
              _adminResolvedIdentity(ref.read(adminIdentityProvider)),
            ),
        send: repository.configureReceiptOperations,
        lookup: repository.receiptOperationsOwnerRequest,
      );
    });
