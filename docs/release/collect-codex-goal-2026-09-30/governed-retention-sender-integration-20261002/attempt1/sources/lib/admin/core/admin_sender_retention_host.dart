import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'admin_auth_guard.dart';
import 'admin_runtime.dart';
import 'admin_sender_retention_sdk.dart';
import 'admin_sender_retention_controller.dart';
import 'admin_sender_retention_checkpoint.dart';
import 'admin_sender_retention_view.dart';

final adminRetentionStoreProvider = Provider<AdminRetentionStore?>(
  (ref) => browserAdminRetentionStore(),
);
final adminRetentionControllerProvider =
    Provider.autoDispose<AdminRetentionController?>((ref) {
      final scope = ref.watch(adminAuthSessionScopeProvider),
          identityState = ref.watch(adminIdentityProvider),
          repository = ref.watch(adminRepositoryProvider);
      final identity = identityState.isLoading || identityState.hasError
          ? null
          : identityState.asData?.value;
      if (scope == null ||
          identity == null ||
          identity.userId != scope.key.userId ||
          !identity.roles.contains('platform_owner') ||
          !{
            'admin_users.manage',
            'notifications.manage',
            'system_health.read',
            'settings.read',
          }.every(identity.permissions.contains) ||
          repository is! AdminRepository) {
        return null;
      }
      var current = true;
      ref.listen(adminAuthSessionScopeProvider, (_, _) => current = false);
      ref.listen(adminIdentityProvider, (_, _) => current = false);
      bool isCurrent() =>
          current &&
          ref.read(adminAuthSessionScopeProvider) == scope &&
          identical(ref.read(adminRepositoryProvider), repository);
      final now = ref.watch(adminClockProvider);
      final api = AdminRetentionSdk(
        rpc: (name, params) =>
            repository.rpcMap(name, params: params, automaticRetry: false),
        actorId: scope.key.userId,
        sessionId: scope.key.sessionId,
        isCurrent: isCurrent,
        now: now,
      );
      final c = AdminRetentionController(
        api: api,
        actorId: scope.key.userId,
        sessionId: scope.key.sessionId,
        store: ref.watch(adminRetentionStoreProvider),
        now: now,
        isCurrent: isCurrent,
        newRequestId: () => const Uuid().v4(),
      );
      ref.onDispose(() {
        current = false;
        c.dispose();
      });
      return c;
    });

/// Root-owned Settings mount remains separate from this private consumer.
class AdminSenderRetentionHost extends ConsumerWidget {
  const AdminSenderRetentionHost({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(adminRetentionControllerProvider);
    return c == null
        ? const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'Current email-owner access and Settings read permission are required.',
              ),
            ),
          )
        : AdminSenderRetentionView(key: ValueKey(c), controller: c);
  }
}
