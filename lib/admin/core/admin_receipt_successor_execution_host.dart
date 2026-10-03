import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'admin_auth_guard.dart';
import 'admin_runtime.dart';
import 'admin_receipt_successor_execution_controller.dart';
import 'admin_receipt_successor_execution_sdk.dart';
import 'admin_receipt_successor_execution_view.dart';

final adminReceiptSuccessorExecutionApiProvider =
    Provider.autoDispose<AdminReceiptSuccessorExecutionApi?>((ref) {
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
      ref.listen(adminIdentityProvider, (_, _) => current = false);
      ref.listen(adminAuthSessionScopeProvider, (_, _) => current = false);
      return AdminReceiptSuccessorExecutionSdk(
        rpc: (name, params) =>
            repository.rpcMap(name, params: params, automaticRetry: false),
        isCurrent: () =>
            current &&
            ref.read(adminAuthSessionScopeProvider) == scope &&
            identical(ref.read(adminRepositoryProvider), repository),
        now: ref.watch(adminClockProvider),
      );
    });
final adminReceiptSuccessorExecutionControllerProvider = Provider.autoDispose
    .family<AdminReceiptSuccessorExecutionController?, (String, String)>((
      ref,
      target,
    ) {
      final api = ref.watch(adminReceiptSuccessorExecutionApiProvider);
      if (api == null) return null;
      var current = true;
      final controller = AdminReceiptSuccessorExecutionController(
        api: api,
        primaryReceiptId: target.$1,
        approvalId: target.$2,
        isCurrent: () =>
            current &&
            identical(ref.read(adminReceiptSuccessorExecutionApiProvider), api),
      );
      ref.onDispose(() {
        current = false;
        controller.dispose();
      });
      return controller;
    });

/// Root mounts only on an already validated approval belonging to the current
/// original investigation. No mutation, checkpoint or execution authority.
class AdminReceiptSuccessorExecutionHost extends ConsumerWidget {
  const AdminReceiptSuccessorExecutionHost({
    required this.approvalId,
    required this.primaryReceiptId,
    super.key,
  });
  final String approvalId, primaryReceiptId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(
      adminReceiptSuccessorExecutionControllerProvider((
        primaryReceiptId,
        approvalId,
      )),
    );
    if (controller == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text(
            'Current email-owner access is required to investigate receipt execution.',
          ),
        ),
      );
    }
    return AdminReceiptSuccessorExecutionView(
      controller: controller,
      now: ref.watch(adminClockProvider),
    );
  }
}
