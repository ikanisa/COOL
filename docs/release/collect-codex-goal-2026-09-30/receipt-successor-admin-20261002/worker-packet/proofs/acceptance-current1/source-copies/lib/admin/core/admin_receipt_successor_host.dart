import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'admin_auth_guard.dart';
import 'admin_runtime.dart';
import 'admin_receipt_successor_sdk.dart';
import 'admin_receipt_successor_checkpoint.dart';
import 'admin_receipt_successor_controller.dart';
import 'admin_receipt_successor_view.dart';

final adminReceiptSuccessorStoreProvider =
    Provider<AdminReceiptSuccessorCheckpointStore?>(
      (ref) => browserReceiptSuccessorCheckpointStore(),
    );
final adminReceiptSuccessorApiProvider =
    Provider.autoDispose<AdminReceiptSuccessorApi?>((ref) {
      final scope = ref.watch(adminAuthSessionScopeProvider),
          repository = ref.watch(adminRepositoryProvider);
      final state = ref.watch(adminIdentityProvider);
      final identity = state.isLoading || state.hasError
          ? null
          : state.asData?.value;
      if (scope == null ||
          identity == null ||
          identity.userId != scope.key.userId ||
          !identity.roles.contains('platform_owner') ||
          !{
            'payments.read',
            'notifications.read',
            'system_health.read',
          }.every(identity.permissions.contains) ||
          repository is! AdminRepository) {
        return null;
      }
      var current = true;
      ref.onDispose(() => current = false);
      // Sticky even if role/session state temporarily changes and returns to A.
      ref.listen(adminIdentityProvider, (_, _) => current = false);
      ref.listen(adminAuthSessionScopeProvider, (_, _) => current = false);
      bool valid() =>
          current &&
          ref.read(adminAuthSessionScopeProvider) == scope &&
          identical(ref.read(adminRepositoryProvider), repository);
      return AdminReceiptSuccessorSdk(
        rpc: (name, parameters) =>
            repository.rpcMap(name, params: parameters, automaticRetry: false),
        isCurrent: valid,
        currentSession: () =>
            valid() ? ref.read(adminAuthSessionScopeProvider)?.key : null,
        canManage: () =>
            valid() &&
            !ref.read(adminIdentityProvider).isLoading &&
            !ref.read(adminIdentityProvider).hasError &&
            ref
                    .read(adminIdentityProvider)
                    .asData
                    ?.value
                    ?.permissions
                    .contains('notifications.manage') ==
                true,
        now: ref.watch(adminClockProvider),
      );
    });
final adminReceiptSuccessorControllerProvider =
    Provider.autoDispose<AdminReceiptSuccessorController?>((ref) {
      final api = ref.watch(adminReceiptSuccessorApiProvider),
          scope = ref.watch(adminAuthSessionScopeProvider);
      final store = ref.watch(adminReceiptSuccessorStoreProvider);
      if (api == null || scope == null) return null;
      var current = true;
      ref.onDispose(() => current = false);
      final controller = AdminReceiptSuccessorController(
        api: api,
        ownerDigest: successorOwnerDigest(scope.key.userId),
        store: store,
        isCurrent: () =>
            current &&
            ref.read(adminAuthSessionScopeProvider) == scope &&
            identical(ref.read(adminReceiptSuccessorApiProvider), api),
      );
      ref.onDispose(controller.dispose);
      return controller;
    });

/// Canonical integration needs only a detail-page import and this host bound
/// to the investigation's validated original receipt/snapshot identifiers.
class AdminReceiptSuccessorHost extends ConsumerWidget {
  const AdminReceiptSuccessorHost({
    required this.outboxId,
    required this.sourceSnapshotId,
    this.onRecorded,
    super.key,
  });
  final String outboxId, sourceSnapshotId;
  final VoidCallback? onRecorded;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(adminReceiptSuccessorControllerProvider),
        state = ref.watch(adminIdentityProvider);
    if (controller == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            state.isLoading
                ? 'Checking receipt review access…'
                : 'Current email-owner receipt review access is required.',
          ),
        ),
      );
    }
    final identity = state.isLoading || state.hasError
        ? null
        : state.asData?.value;
    return AdminReceiptSuccessorView(
      outboxId: outboxId,
      sourceSnapshotId: sourceSnapshotId,
      controller: controller,
      canRead: identity != null,
      canManage: identity?.permissions.contains('notifications.manage') == true,
      now: ref.watch(adminClockProvider),
      onRecorded: onRecorded,
    );
  }
}
