import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'admin_runtime.dart';
import 'admin_auth_guard.dart';
import 'admin_full_payment_compensation_sdk.dart';
import 'admin_full_payment_compensation_checkpoint.dart';
import 'admin_full_payment_compensation_controller.dart';
import 'admin_full_payment_compensation_view.dart';

class AdminFullPaymentCompensationAccess {
  const AdminFullPaymentCompensationAccess({
    required this.api,
    required this.actorId,
    required this.sessionId,
    required this.isCurrent,
    required this.canRecord,
  });
  final AdminFullPaymentCompensationApi api;
  final String actorId, sessionId;
  final bool Function() isCurrent, canRecord;
}

final adminFullPaymentCompensationStoreProvider =
    Provider<AdminFullPaymentCompensationStore?>(
      (ref) => browserFullPaymentCompensationStore(),
    );
final adminFullPaymentCompensationAccessProvider =
    Provider.autoDispose<AdminFullPaymentCompensationAccess?>((ref) {
      final scope = ref.watch(adminAuthSessionScopeProvider),
          repository = ref.watch(adminRepositoryProvider),
          state = ref.watch(adminIdentityProvider);
      final identity = state.isLoading || state.hasError
          ? null
          : state.asData?.value;
      if (scope == null ||
          identity == null ||
          identity.userId != scope.key.userId ||
          !identity.roles.contains('platform_owner') ||
          !identity.permissions.contains('payments.read') ||
          repository is! AdminRepository) {
        return null;
      }
      var current = true;
      ref.onDispose(() => current = false);
      ref.listen(adminAuthSessionScopeProvider, (_, _) => current = false);
      ref.listen(adminIdentityProvider, (_, _) => current = false);
      bool valid() =>
          current &&
          ref.read(adminAuthSessionScopeProvider) == scope &&
          identical(ref.read(adminRepositoryProvider), repository);
      bool permitted() =>
          valid() &&
          ref
                  .read(adminIdentityProvider)
                  .asData
                  ?.value
                  ?.permissions
                  .contains('payments.allocate') ==
              true;
      return AdminFullPaymentCompensationAccess(
        api: AdminFullPaymentCompensationSdk(
          rpc: (name, params) =>
              repository.rpcMap(name, params: params, automaticRetry: false),
          actorId: scope.key.userId,
          sessionId: scope.key.sessionId,
          isCurrent: valid,
          canRecord: permitted,
          now: ref.watch(adminClockProvider),
        ),
        actorId: scope.key.userId,
        sessionId: scope.key.sessionId,
        isCurrent: valid,
        canRecord: permitted,
      );
    });

class AdminFullPaymentCompensationHost extends ConsumerWidget {
  const AdminFullPaymentCompensationHost({
    required this.paymentId,
    required this.originalJournalEntryId,
    required this.originalSnapshotId,
    required this.collectionId,
    required this.memberRecordId,
    this.onRecorded,
    super.key,
  });
  final String paymentId,
      originalJournalEntryId,
      originalSnapshotId,
      collectionId;
  final String? memberRecordId;
  final VoidCallback? onRecorded;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(adminFullPaymentCompensationAccessProvider),
        store = ref.watch(adminFullPaymentCompensationStoreProvider),
        now = ref.watch(adminClockProvider);
    if (access == null) {
      return const Text(
        'Full ledger compensation requires a current owner session and payment-read permission.',
      );
    }
    return _Host(
      access: access,
      store: store,
      now: now,
      paymentId: paymentId,
      originalJournalEntryId: originalJournalEntryId,
      originalSnapshotId: originalSnapshotId,
      collectionId: collectionId,
      memberRecordId: memberRecordId,
      onRecorded: onRecorded,
      key: ValueKey(
        '${access.actorId}.${access.sessionId}.$paymentId.$originalJournalEntryId.$originalSnapshotId.$collectionId.$memberRecordId',
      ),
    );
  }
}

class _Host extends StatefulWidget {
  const _Host({
    required this.access,
    required this.store,
    required this.now,
    required this.paymentId,
    required this.originalJournalEntryId,
    required this.originalSnapshotId,
    required this.collectionId,
    required this.memberRecordId,
    this.onRecorded,
    super.key,
  });
  final AdminFullPaymentCompensationAccess access;
  final AdminFullPaymentCompensationStore? store;
  final DateTime Function() now;
  final String paymentId,
      originalJournalEntryId,
      originalSnapshotId,
      collectionId;
  final String? memberRecordId;
  final VoidCallback? onRecorded;
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late AdminFullPaymentCompensationController _controller;
  void _create() {
    _controller = AdminFullPaymentCompensationController(
      api: widget.access.api,
      store: widget.store,
      actorId: widget.access.actorId,
      sessionId: widget.access.sessionId,
      paymentId: widget.paymentId,
      originalJournalEntryId: widget.originalJournalEntryId,
      originalSnapshotId: widget.originalSnapshotId,
      collectionId: widget.collectionId,
      memberRecordId: widget.memberRecordId,
      isCurrent: widget.access.isCurrent,
      canRecord: widget.access.canRecord,
      now: widget.now,
      newRequestId: () => const Uuid().v4(),
      onRecorded: widget.onRecorded,
    );
  }

  @override
  void initState() {
    super.initState();
    _create();
  }

  @override
  void didUpdateWidget(_Host old) {
    super.didUpdateWidget(old);
    if (!identical(old.access, widget.access) ||
        !identical(old.store, widget.store)) {
      _controller.dispose();
      _create();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      AdminFullPaymentCompensationView(controller: _controller);
}
