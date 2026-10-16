import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../app/theme/collect_colors.dart';
import '../../app/theme/collect_motion.dart';
import '../../app/theme/collect_radius.dart';
import '../../app/theme/collect_typography.dart';
import '../../app/theme/collect_universal_tokens.dart';
import '../../core/security/phone_normalizer.dart';
import '../../core/data/exact_json_values.dart';
import '../../core/supabase/realtime_invalidation.dart';
import '../../core/supabase/supabase_module.dart';
import '../../shared/widgets/collect_state_panels.dart';
import 'admin_display_formatters.dart';
import 'admin_list_paging.dart';
import '../shared/components/admin_confirm_dialog.dart';
import '../shared/components/admin_data_table.dart';
import '../shared/components/admin_data_listing.dart';
import '../shared/components/admin_empty_state.dart';
import '../shared/components/admin_filter_bar.dart';
import '../shared/components/admin_loading_state.dart';
import '../shared/components/admin_page.dart';
import '../shared/components/admin_sensitive_data_gate.dart';
import '../shared/components/admin_status_chip.dart';
import 'admin_auth_guard.dart';
import 'admin_read_contracts.dart';
import 'admin_action_contracts.dart';
import 'admin_error_boundary.dart';
import 'admin_repository_base.dart';
import 'admin_review_credentials.dart';
import 'admin_reconciliation_step_up.dart';
import 'admin_roster_import.dart';
import 'admin_roster_dialog.dart';
import 'admin_operational_health.dart';
import 'admin_receipt_overview.dart';
import 'admin_sms_queue_health.dart';
import 'admin_shadow_runs.dart';
import 'admin_transaction_lifecycle.dart';
import 'admin_investigation.dart';
import 'admin_investigation_view.dart';
import 'admin_email_otp.dart';
import 'admin_operator_approval.dart';
import 'admin_gateway_contracts.dart';
import 'admin_gateway_models.dart';
import 'admin_automatic_gateway_models.dart';
import 'admin_automatic_gateway_view.dart';
import 'admin_gateway_checkpoint.dart';
import 'admin_receipt_cancel_models.dart';
import 'admin_receipt_cancel_checkpoint.dart';
import 'admin_exception_models.dart';
import 'admin_exception_workflow_models.dart';
import 'admin_exception_followup_v2_models.dart';
import 'admin_receipt_deferral_models.dart';
import 'admin_receipt_worker_health.dart';
import 'admin_receipt_operational_telemetry.dart';
import 'admin_receipt_callback_deadline_view.dart';
import 'admin_receipt_operational_history_models.dart';
import 'admin_receipt_operational_history_sdk.dart';
import 'admin_receipt_worker_transport_models.dart';
import 'admin_exception_checkpoint.dart';
import 'admin_entity_audit.dart';
import 'admin_exception_history_v2_models.dart';
import 'admin_exception_escalation_inbox_v2_models.dart';
import 'admin_operating_policy_models.dart';
import 'admin_receipt_operations_models.dart';
import 'admin_receipt_operations_checkpoint.dart';
import 'admin_receipt_principal_models.dart';
import 'admin_receipt_principal_checkpoint.dart';
import 'admin_receipt_principal_controller.dart';
import 'admin_governed_settings_models.dart';
import 'admin_governed_settings_sdk.dart';
import 'admin_governed_settings_checkpoint.dart';
import 'admin_governed_settings_controller.dart';
import 'admin_sender_retention_host.dart';
import 'admin_receipt_notice_content_host.dart';
import 'admin_receipt_notice_dispatch_host.dart';
import 'admin_sender_picker.dart';
import 'admin_existing_member_allocation.dart';
import 'admin_transaction_details.dart';
import 'admin_member_allocation_dialog.dart';

export 'admin_live_updates.dart';

part 'admin_governed_settings_runtime.dart';
part 'admin_governed_settings_page.dart';
part 'admin_login_runtime.dart';
part 'admin_overview_runtime.dart';
part 'admin_overview_components.dart';
part 'admin_list_specs.dart';
part 'admin_list_runtime.dart';
part 'admin_reconciliation_runtime.dart';
part 'admin_operation_tables.dart';
part 'admin_operation_components.dart';
part 'admin_group_runtime.dart';
part 'admin_payee_runtime.dart';
part 'admin_payee_workspace.dart';
part 'admin_detail_specs.dart';
part 'admin_detail_runtime.dart';
part 'admin_transaction_detail_supplement.dart';
part 'admin_staff_workspace.dart';
part 'admin_operator_draft_owner.dart';
part 'admin_platform_access.dart';
part 'admin_gateway_dialogs.dart';
part 'admin_gateway_runtime.dart';
part 'admin_automatic_gateway_runtime.dart';
part 'admin_gateway_page.dart';
part 'admin_receipt_cancel_runtime.dart';
part 'admin_receipt_cancel_card.dart';
part 'admin_exception_runtime.dart';
part 'admin_exception_page.dart';
part 'admin_exception_workflow_card.dart';
part 'admin_exception_assignment_dialog.dart';
part 'admin_receipt_deferral_card.dart';
part 'admin_receipt_worker_card.dart';
part 'admin_receipt_telemetry_card.dart';
part 'admin_receipt_operational_history_runtime.dart';
part 'admin_receipt_operational_history_view.dart';
part 'admin_receipt_worker_transport_card.dart';
part 'admin_receipt_principal_runtime.dart';
part 'admin_receipt_principal_card.dart';
part 'admin_entity_audit_runtime.dart';
part 'admin_exception_history_runtime.dart';
part 'admin_entity_audit_page.dart';
part 'admin_entity_audit_link.dart';
part 'admin_operating_policy_runtime.dart';
part 'admin_operating_policy_card.dart';
part 'admin_receipt_operations_runtime.dart';
part 'admin_receipt_operations_card.dart';
part 'admin_detail_formatters.dart';
part 'admin_receipt_repository.dart';
part 'admin_exception_repository.dart';
part 'admin_member_allocation_runtime.dart';
part 'admin_detail_actions.dart';
part 'admin_reconciliation_dialogs.dart';
part 'admin_repository_runtime.dart';

final adminRepositoryProvider = Provider<AdminRepositoryBase>((ref) {
  ref.watch(adminAuthUserIdProvider);
  final scope = ref.watch(adminAuthSessionScopeProvider);
  final client = ref.watch(supabaseClientProvider);
  var current = true;
  ref.onDispose(() => current = false);
  return AdminRepository(
    client,
    isCurrent: () =>
        current &&
        scope != null &&
        adminSessionKey(client?.auth.currentSession) == scope.key,
  );
});

final adminIdentityProvider = FutureProvider<AdminIdentity?>((ref) async {
  final userId = ref.watch(adminAuthUserIdProvider);
  if (userId == null) return null;
  final identity = await ref.watch(adminRepositoryProvider).currentIdentity();
  return identity?.userId == userId ? identity : null;
});

// AsyncData may retain a prior value while isLoading is true. That value is
// display history, not current authority for a protected control or intent.
AdminIdentity? _adminResolvedIdentity(AsyncValue<AdminIdentity?> value) =>
    value.isLoading || value.hasError ? null : value.asData?.value;

class _AdminIdentityRevision {
  int value = 0;
  void changed() => value += 1;
}

// Observe every capability/loading transition, including A-B-A between frames.
// The counter changes synchronously without notifying another provider while
// identity is being rebuilt. The derived provider below invalidates through its
// identity dependency; an immediate read returns the current counter.
final _adminIdentityRevisionCounterProvider = Provider<_AdminIdentityRevision>((
  ref,
) {
  final revision = _AdminIdentityRevision();
  ref.listen(adminIdentityProvider, (_, _) => revision.changed());
  return revision;
});

final _adminIdentityRevisionProvider = Provider<int>((ref) {
  final revision = ref.watch(_adminIdentityRevisionCounterProvider);
  ref.watch(adminIdentityProvider);
  return revision.value;
});

final adminRealtimeTickProvider = StateProvider<int>((_) => 0);
final adminClockProvider = Provider<DateTime Function()>((_) => DateTime.now);
final adminLastSuccessfulRefreshProvider = StateProvider<DateTime?>((ref) {
  // Freshness belongs to the signed-in session, including replacement logins
  // by the same person. A previous session's refresh cannot certify this one.
  ref.watch(adminAuthSessionScopeProvider);
  ref.watch(adminAuthUserIdProvider);
  return null;
});

enum AdminCountryScope { rwanda }

extension AdminCountryScopeDisplay on AdminCountryScope {
  String get label => 'Rwanda';
  IconData get icon => Icons.cell_tower_outlined;
  String get rpcCode => 'RW';
}

final adminCountryScopeProvider = StateProvider<AdminCountryScope>(
  (_) => AdminCountryScope.rwanda,
);

bool adminRpcUsesCountryScope(String rpcName) => switch (rpcName) {
  'admin_list_collections' ||
  'admin_list_members' ||
  'admin_list_users' ||
  'admin_list_non_member_users' ||
  'admin_list_collect_payees' ||
  'admin_list_collect_transactions' ||
  'admin_list_collect_reconciliations' ||
  'admin_list_collect_ledgers' ||
  'admin_list_notifications' => true,
  _ => false,
};

bool adminRowMatchesCountryScope(
  AdminTableRowData row,
  AdminCountryScope scope,
) {
  final explicit = '${row.extra['country_code'] ?? ''}'.trim().toUpperCase();
  final rail = '${row.extra['rail'] ?? ''}'.trim().toLowerCase();
  return explicit == 'RW' || (explicit.isEmpty && rail == 'rw_momo');
}

class _AdminPrivateReadDenied implements Exception {
  const _AdminPrivateReadDenied();
}

String? _adminDetailReadPermission(String rpc) => switch (rpc) {
  'admin_get_collection' || 'admin_get_receiver' => 'collections.read',
  'admin_get_user' || 'admin_get_member_record' => 'users.read',
  'admin_get_collect_transaction' ||
  'admin_get_payment' ||
  'admin_get_payment_event' ||
  'admin_get_payment_intent' => 'payments.read',
  'admin_get_hybrid_sms_receipt' ||
  'admin_get_notification' => 'notifications.read',
  'admin_get_sms_metadata' => 'sms.metadata.read',
  'admin_get_admin_user' || 'admin_get_staff_user_v1' => 'admin_users.read',
  'admin_system_health' => 'system_health.read',
  _ => null,
};

final adminRuntimeConfigProvider = FutureProvider<AdminRuntimeConfig?>((
  ref,
) async {
  ref.watch(adminAuthSessionScopeProvider);
  final repository = ref.watch(adminRepositoryProvider);
  var current = true;
  ref.onDispose(() => current = false);
  final identity = await ref.watch(adminIdentityProvider.future);
  if (!current) throw const AdminSessionChanged();
  if (identity == null) throw const _AdminPrivateReadDenied();
  final result = await repository.runtimeConfig();
  if (!current) throw const AdminSessionChanged();
  return result;
});

final adminDetailRecordProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, ({String rpc, String id})>((ref, key) async {
      ref.watch(adminAuthSessionScopeProvider);
      ref.watch(adminRealtimeTickProvider);
      final repository = ref.watch(adminRepositoryProvider);
      var current = true;
      ref.onDispose(() => current = false);
      final identity = await ref.watch(adminIdentityProvider.future);
      if (!current) throw const AdminSessionChanged();
      final permission = _adminDetailReadPermission(key.rpc);
      if (permission == null ||
          identity?.permissions.contains(permission) != true) {
        throw const _AdminPrivateReadDenied();
      }
      final result = await repository.detail(key.rpc, key.id);
      if (!current) throw const AdminSessionChanged();
      return result;
    });

final adminRealtimeSubscriptionProvider = Provider.autoDispose<void>((ref) {
  final scope = ref.watch(adminAuthSessionScopeProvider);
  final client = ref.watch(supabaseClientProvider);
  if (client == null || scope == null) return;
  var current = true;
  final subscription = RealtimeInvalidationSubscription(
    client: client,
    // The locked SDK routes data frames by topic rather than join_ref. A new
    // provider scope needs its own topic to exclude departed scope frames.
    topic: 'collect:admin:invalidation:${const Uuid().v4()}',
    areas: collectAdminRealtimeAreas,
    onStatus: (status, _) {
      if (!current ||
          adminSessionKey(client.auth.currentSession) != scope.key) {
        return;
      }
      ref.read(adminLiveUpdateStatusProvider.notifier).state =
          adminLiveUpdateStatusFor(status);
    },
    onInvalidateAreas: (areas) {
      if (!current ||
          adminSessionKey(client.auth.currentSession) != scope.key) {
        return;
      }
      if (areas.contains('admin_roles')) ref.invalidate(adminIdentityProvider);
      if (areas.any({'settings', 'feature_flags'}.contains)) {
        ref.invalidate(adminRuntimeConfigProvider);
      }
    },
    onInvalidate: () {
      if (!current ||
          adminSessionKey(client.auth.currentSession) != scope.key) {
        return;
      }
      ref.read(adminRealtimeTickProvider.notifier).state += 1;
    },
  )..start();
  ref.onDispose(() {
    current = false;
    unawaited(subscription.dispose());
  });
});

Future<T?> _showAdminFormDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) async {
  ModalRoute<T>? route;
  final result = await showDialog<T>(
    context: context,
    animationStyle: CollectMotion.animationStyle(context),
    builder: (dialogContext) {
      route = ModalRoute.of<T>(dialogContext);
      return builder(dialogContext);
    },
  );
  // push() resolves at pop; completed resolves after the closing transition
  // and overlay removal. External form controllers remain owned until then.
  await route?.completed;
  return result;
}

class _AdminActionScope {
  _AdminActionScope(this.ref)
    : repository = ref.read(adminRepositoryProvider),
      session = ref.read(adminAuthSessionScopeProvider),
      actorId = _adminResolvedIdentity(ref.read(adminIdentityProvider))?.userId,
      identityRevision = ref.read(_adminIdentityRevisionProvider),
      roles = Set.of(
        _adminResolvedIdentity(ref.read(adminIdentityProvider))?.roles ??
            const <String>[],
      ),
      permissions = Set.of(
        _adminResolvedIdentity(ref.read(adminIdentityProvider))?.permissions ??
            const <String>[],
      );
  final WidgetRef ref;
  final AdminRepositoryBase repository;
  final AdminSessionScope? session;
  final String? actorId;
  final int identityRevision;
  final Set<String> roles, permissions;
  bool _valid = true;

  bool get isCurrent {
    if (!_valid || !ref.context.mounted) {
      _valid = false;
      return false;
    }
    final identity = _adminResolvedIdentity(ref.read(adminIdentityProvider));
    final current =
        actorId != null &&
        ref.read(_adminIdentityRevisionProvider) == identityRevision &&
        identity?.userId == actorId &&
        identity!.roles.length == roles.length &&
        roles.containsAll(identity.roles) &&
        identity.permissions.length == permissions.length &&
        permissions.containsAll(identity.permissions) &&
        identical(repository, ref.read(adminRepositoryProvider)) &&
        ref.read(adminAuthSessionScopeProvider) == session;
    // Once an observed identity, capability or session change invalidates an
    // intent, a later restoration must not resurrect that old draft or ACK.
    if (!current) _valid = false;
    return _valid;
  }
}

class _AdminSessionDialog extends ConsumerWidget {
  const _AdminSessionDialog({required this.scope, required this.child});
  final _AdminActionScope scope;
  final Widget child;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(adminAuthSessionScopeProvider);
    ref.watch(adminRepositoryProvider);
    ref.watch(adminIdentityProvider);
    ref.watch(_adminIdentityRevisionProvider);
    final current = scope.isCurrent;
    if (!current) {
      final route = ModalRoute.of(context);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (route?.isActive == true) route!.navigator?.removeRoute(route);
      });
      // Clear draft contents immediately, before the route removal frame.
      return const SizedBox.shrink();
    }
    return child;
  }
}

class AdminDeniedPage extends StatelessWidget {
  const AdminDeniedPage({this.requiredPermission, super.key});

  final String? requiredPermission;

  @override
  Widget build(BuildContext context) {
    final permission = requiredPermission;
    final colors = context.collectColors;
    return Scaffold(
      backgroundColor: colors.canvas,
      body: ColoredBox(
        color: colors.canvas,
        child: AdminPage(
          title: 'Admin access required',
          subtitle: permission == null
              ? 'This account does not have Admin access.'
              : 'Permission required: $permission',
          child: Semantics(
            container: true,
            explicitChildNodes: true,
            label: 'Admin access recovery actions',
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                IconButton.filled(
                  tooltip: 'Return to operations',
                  onPressed: () => context.go('/admin'),
                  icon: const Icon(Icons.dashboard_outlined),
                ),
                IconButton.outlined(
                  tooltip: 'Admin sign-in',
                  onPressed: () => context.go('/admin/login'),
                  icon: const Icon(Icons.login_outlined),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
