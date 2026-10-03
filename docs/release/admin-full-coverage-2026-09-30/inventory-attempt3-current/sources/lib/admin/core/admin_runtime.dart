import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/theme/collect_colors.dart';
import '../../app/theme/collect_motion.dart';
import '../../app/theme/collect_radius.dart';
import '../../app/theme/collect_typography.dart';
import '../../app/theme/collect_universal_tokens.dart';
import '../../core/security/phone_normalizer.dart';
import '../../core/supabase/realtime_invalidation.dart';
import '../../core/supabase/supabase_module.dart';
import '../../core/utils/money_format.dart';
import '../../shared/widgets/collect_state_panels.dart';
import 'admin_display_formatters.dart';
import 'admin_list_paging.dart';
import '../shared/components/admin_confirm_dialog.dart';
import '../shared/components/admin_data_table.dart';
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
import 'admin_sms_queue_health.dart';

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
part 'admin_detail_specs.dart';
part 'admin_detail_runtime.dart';
part 'admin_platform_access.dart';
part 'admin_detail_formatters.dart';

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

class _AdminIdentityRevision extends StateNotifier<int> {
  _AdminIdentityRevision() : super(0);
  void changed() => state += 1;
}

// Keep observed capability/loading transitions, including A-B-A, even when an
// action is awaiting its response and its reason dialog has already closed.
final _adminIdentityRevisionProvider =
    StateNotifierProvider<_AdminIdentityRevision, int>((ref) {
      final revision = _AdminIdentityRevision();
      ref.listen(adminIdentityProvider, (_, _) => revision.changed());
      return revision;
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

final adminRuntimeConfigProvider = FutureProvider<AdminRuntimeConfig?>((ref) {
  ref.watch(adminRealtimeTickProvider);
  return ref.watch(adminRepositoryProvider).runtimeConfig();
});

final adminDetailRecordProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, ({String rpc, String id})>((ref, key) {
      ref.watch(adminRealtimeTickProvider);
      return ref.watch(adminRepositoryProvider).detail(key.rpc, key.id);
    });

final adminRealtimeSubscriptionProvider = Provider.autoDispose<void>((ref) {
  final scope = ref.watch(adminAuthSessionScopeProvider);
  final client = ref.watch(supabaseClientProvider);
  if (client == null || scope == null) return;
  var current = true;
  final subscription = RealtimeInvalidationSubscription(
    client: client,
    topic: 'collect:admin:invalidation',
    areas: collectAdminRealtimeAreas,
    onInvalidate: () {
      if (!current ||
          adminSessionKey(client.auth.currentSession) != scope.key) {
        return;
      }
      ref.read(adminRealtimeTickProvider.notifier).state += 1;
      ref.invalidate(adminIdentityProvider);
    },
  )..start();
  ref.onDispose(() {
    current = false;
    unawaited(subscription.dispose());
  });
});

class AdminRepository extends AdminRepositoryBase {
  const AdminRepository(this._supabase, {this.isCurrent});

  final SupabaseClient? _supabase;
  final bool Function()? isCurrent;

  Future<T> _withSession<T>(
    Future<T> Function(AdminRequestSession) operation, {
    bool reconciliation = false,
  }) async {
    Never changed() => throw reconciliation
        ? const AdminReconciliationStepUpException(
            'session_changed',
            'Your sign-in changed. Reopen reconciliation and try again.',
          )
        : const AdminSessionChanged();
    if (isCurrent?.call() == false) changed();
    final session = AdminRequestSession(_requireClient());
    void check() {
      try {
        session.checkCurrent();
      } on AdminSessionChanged {
        changed();
      }
      if (isCurrent?.call() == false) changed();
    }

    try {
      final result = await operation(session);
      check();
      return result;
    } catch (_) {
      check();
      rethrow;
    } finally {
      await session.dispose();
      check();
    }
  }

  @override
  Future<void> sendOtp({required String phone}) async {
    final normalizedPhone = _normalizeAdminPhone(phone);
    await _requireClient().auth.signInWithOtp(
      phone: normalizedPhone,
      channel: OtpChannel.whatsapp,
      shouldCreateUser: false,
    );
  }

  @override
  Future<AdminIdentity?> verifyOtp({
    required String phone,
    required String otp,
  }) async {
    final client = _requireClient();
    final normalizedPhone = _normalizeAdminPhone(phone);
    final response = await client.auth.verifyOTP(
      phone: normalizedPhone,
      token: otp.trim(),
      type: OtpType.sms,
    );
    if (response.session == null) {
      throw const AuthException(
        'Admin OTP verification did not create a session.',
      );
    }
    // A successful OTP creates a new provider generation. Read that new
    // identity without reusing the signed-out repository's lifetime fence.
    return AdminRepository(client).currentIdentity();
  }

  @override
  Future<void> signOut() async => _supabase?.auth.signOut();

  @override
  Future<AdminIdentity?> currentIdentity() async {
    final client = _supabase;
    if (client == null) return null;
    if (client.auth.currentSession == null) return null;
    return _withSession((session) async {
      final row = await client
          .rpc<dynamic>('admin_current_user')
          .setHeader('Authorization', 'Bearer ${session.token}');
      return parseAdminIdentity(row, actorId: session.key!.userId);
    });
  }

  @override
  Future<List<AdminMetric>> overviewMetrics() async {
    return parseAdminOverview(await rpcMap('admin_overview'));
  }

  @override
  Future<AdminListResult> list(
    String rpcName, {
    String? search,
    String? status,
    int? limit,
    int? offset,
    String? sortBy,
    String? countryCode,
  }) async {
    final pageSize = limit ?? 25;
    final pageOffset = offset ?? 0;
    if (pageSize < 1 || pageSize > 100) {
      throw RangeError.range(pageSize, 1, 100, 'limit');
    }
    if (pageOffset < 0) throw RangeError.range(pageOffset, 0, null, 'offset');
    final trimmedSearch = search?.trim();
    final trimmedStatus = status?.trim();
    final trimmedSort = sortBy?.trim();
    final normalizedCountry = countryCode?.trim().toUpperCase();
    final scoped =
        normalizedCountry?.isNotEmpty == true &&
        adminRpcUsesCountryScope(rpcName);
    // Every list request is a server window. A missing paged RPC must fail;
    // fetching an unpaged legacy batch and slicing it can conceal records.
    final row = await rpcMap(
      scoped ? 'admin_list_country_scoped' : rpcName,
      params: {
        if (scoped) 'p_rpc_name': rpcName,
        if (scoped) 'p_country': normalizedCountry,
        'p_search': trimmedSearch?.isEmpty == true ? null : trimmedSearch,
        'p_status': trimmedStatus?.isEmpty == true ? null : trimmedStatus,
        'p_limit': pageSize,
        'p_offset': pageOffset,
        'p_sort': trimmedSort == null || trimmedSort.isEmpty
            ? 'created_at_desc'
            : trimmedSort,
      },
    );
    final result = AdminListResult.fromJson(
      row,
    ).validateWindow(limit: pageSize, offset: pageOffset);
    // The scoped RPC promises an explicit country on every row. Verify the
    // server result here as well as in the page widget so overview and other
    // repository callers cannot accidentally publish an unscoped row.
    if (scoped &&
        normalizedCountry == 'RW' &&
        result.rows.any(
          (item) =>
              '${item.extra['country_code'] ?? ''}'.trim().toUpperCase() !=
              'RW',
        )) {
      throw const FormatException(
        'Admin list returned rows outside the requested country.',
      );
    }
    return result;
  }

  @override
  Future<Map<String, dynamic>> detail(String rpcName, String id) async {
    validateAdminDetailRequest(rpcName, id);
    return validateAdminDetail(
      rpcName,
      id,
      await rpcMap(rpcName, params: {'p_id': id}),
    );
  }

  @override
  Future<Map<String, dynamic>> smsQueueHealth() => _withSession((
    session,
  ) async {
    final response = await _requireClient().functions.invoke(
      'collect-notification-operator',
      body: const {'action': 'health'},
      headers: {'Authorization': 'Bearer ${session.token}'},
    );
    final raw = response.data is String
        ? jsonDecode(response.data as String)
        : response.data;
    if (response.status != 200 ||
        raw is! Map ||
        raw.length != 3 ||
        raw['ok'] != true ||
        raw['action'] != 'health' ||
        raw['result'] is! Map) {
      throw const FormatException('SMS queue health could not be validated.');
    }
    final data = Map<String, dynamic>.from(raw['result'] as Map);
    AdminSmsQueueHealth.parse(data);
    return data;
  });

  @override
  Future<AdminQueueSla?> queueSla(String queueKey) async {
    if (_supabase == null) return null;
    final normalized = validateAdminQueueSlaRequest(queueKey);
    try {
      return await _withSession(
        (session) async => parseAdminQueueSla(
          await _requireClient()
              .rpc<dynamic>(
                'admin_get_queue_sla',
                params: {'p_queue_key': normalized},
              )
              .setHeader('Authorization', 'Bearer ${session.token}'),
          queueKey: normalized,
        ),
      );
    } on PostgrestException catch (error) {
      if (!_isLegacySlaSignatureError(error)) rethrow;
      return null;
    }
  }

  @override
  Future<AdminRuntimeConfig?> runtimeConfig() async {
    if (_supabase == null) return null;
    try {
      final row = await rpcMap('admin_runtime_config');
      return parseAdminRuntimeConfig(row);
    } on PostgrestException catch (error) {
      if (!_isMissingRuntimeConfigError(error)) rethrow;
      return null;
    }
  }

  @override
  Future<Map<String, dynamic>> action(
    String rpcName,
    Map<String, dynamic> params,
  ) async {
    final frozen = Map<String, dynamic>.unmodifiable(params);
    final result = await rpcMap(rpcName, params: frozen);
    validateAdminActionReceipt(rpcName, frozen, result);
    return result;
  }

  @override
  AdminRosterGateway openRosterImport() =>
      SupabaseAdminRosterGateway(_requireClient());

  @override
  Future<Map<String, dynamic>> prepareRosterImport(
    Map<String, dynamic> body,
  ) async {
    final response = await _withSession(
      (session) => _requireClient().functions.invoke(
        'prepare-roster-import',
        body: body,
        headers: {'Authorization': 'Bearer ${session.token}'},
      ),
    );
    final data = response.data;
    final decoded = data is String ? jsonDecode(data) : data;
    if (decoded is! Map) {
      throw StateError(
        'prepare-roster-import returned ${decoded.runtimeType}, expected map',
      );
    }
    final result = Map<String, dynamic>.from(decoded);
    final error = '${result['error'] ?? ''}'.trim();
    if (error.isNotEmpty) throw StateError(error);
    return result;
  }

  @override
  Future<AdminListResult> paymentReconciliationReviews(
    String? paymentId, {
    int limit = 25,
    int offset = 0,
  }) async {
    if (paymentId != null) _requireReconciliationUuid(paymentId);
    if (limit < 1 || limit > 100 || offset < 0 || offset > 100000) {
      throw const FormatException('Invalid reconciliation page.');
    }
    final scope = _captureReconciliationSession();
    final result = await rpcMap(
      'list_payment_reconciliations_v2',
      params: {'p_payment_id': paymentId, 'p_limit': limit, 'p_offset': offset},
    );
    _checkReconciliationSession(scope);
    final rows = result['rows'];
    if (result['total'] is! int || rows is! List) {
      throw const FormatException('Invalid evidence review response.');
    }
    for (final raw in rows) {
      if (raw is! Map || !_validReconciliationReview(raw, paymentId)) {
        throw const FormatException('Invalid evidence review response.');
      }
    }
    return AdminListResult.fromJson(
      result,
    ).validateWindow(limit: limit, offset: offset);
  }

  @override
  Future<Map<String, dynamic>> paymentReconciliationDetail(
    String reviewId, {
    required String paymentId,
  }) async {
    _requireReconciliationUuid(reviewId);
    _requireReconciliationUuid(paymentId);
    final scope = _captureReconciliationSession();
    final result = await rpcMap(
      'get_payment_reconciliation_v2',
      params: {'p_review_id': reviewId},
    );
    _checkReconciliationSession(scope);
    if (result['id'] != reviewId ||
        result['payment_id'] != paymentId ||
        result.containsKey('proposed_session_id') ||
        result.containsKey('approved_session_id') ||
        ['audit', 'journals', 'receiver_routes'].any(
          (key) =>
              result[key] is! List ||
              (result[key] as List).any((row) => row is! Map),
        )) {
      throw const FormatException('Invalid evidence lineage response.');
    }
    return result;
  }

  String _captureReconciliationSession() {
    final key = _reconciliationSessionKey(_requireClient().auth.currentSession);
    if (key == null) {
      throw const AdminReconciliationStepUpException(
        'session_changed',
        'Your sign-in changed. Reopen reconciliation and try again.',
      );
    }
    return key;
  }

  void _checkReconciliationSession(String expected) {
    if (_reconciliationSessionKey(_requireClient().auth.currentSession) !=
        expected) {
      throw const AdminReconciliationStepUpException(
        'session_changed',
        'Your sign-in changed. Reopen reconciliation and try again.',
      );
    }
  }

  @override
  Future<String> proposePaymentReconciliation(
    Map<String, dynamic> evidence,
  ) async {
    final scope = _captureReconciliationSession();
    final result = await _withSession(
      (session) => _requireClient()
          .rpc<dynamic>('propose_payment_reconciliation_v2', params: evidence)
          .setHeader('Authorization', 'Bearer ${session.token}'),
      reconciliation: true,
    );
    _checkReconciliationSession(scope);
    if (result is! String || !_reconciliationUuid.hasMatch(result)) {
      throw const FormatException(
        'Reconciliation proposal was not acknowledged.',
      );
    }
    return result;
  }

  @override
  Future<void> approvePaymentReconciliation(
    String reviewId,
    String reason,
  ) async {
    _requireReconciliationUuid(reviewId);
    if (reason.trim().length < 10 || reason.trim().length > 500) {
      throw const FormatException('Use a reason of 10 to 500 characters.');
    }
    final scope = _captureReconciliationSession();
    final result = await _withSession(
      (session) => _requireClient()
          .rpc<dynamic>(
            'approve_payment_reconciliation_v2',
            params: {'p_review_id': reviewId, 'p_reason': reason},
          )
          .setHeader('Authorization', 'Bearer ${session.token}'),
      reconciliation: true,
    );
    _checkReconciliationSession(scope);
    if (result != true) {
      throw const FormatException(
        'Reconciliation approval was not acknowledged.',
      );
    }
  }

  @override
  Future<AdminReconciliationFinalization> finalizePaymentReconciliation(
    String reviewId, {
    required String paymentId,
  }) async {
    _requireReconciliationUuid(reviewId);
    _requireReconciliationUuid(paymentId);
    final scope = _captureReconciliationSession();
    final response = await _withSession(
      (session) => _requireClient().functions.invoke(
        'reconciliation-finalize',
        body: {'review_id': reviewId},
        headers: {'Authorization': 'Bearer ${session.token}'},
      ),
      reconciliation: true,
    );
    _checkReconciliationSession(scope);
    final value = response.data;
    final decoded = value is String ? jsonDecode(value) : value;
    if (response.status != 200 || decoded is! Map) {
      throw StateError(
        'Reconciliation finalization could not be acknowledged.',
      );
    }
    return AdminReconciliationFinalization.fromJson(
      Map<String, dynamic>.from(decoded),
      reviewId: reviewId,
      paymentId: paymentId,
    );
  }

  Future<Map<String, dynamic>> rpcMap(
    String rpcName, {
    Map<String, dynamic>? params,
  }) async {
    final response = await _withSession(
      (session) => _requireClient()
          .rpc<dynamic>(rpcName, params: params)
          .setHeader('Authorization', 'Bearer ${session.token}'),
      reconciliation: const {
        'list_payment_reconciliations_v2',
        'get_payment_reconciliation_v2',
      }.contains(rpcName),
    );
    if (response == null) return const {};
    if (response is Map) return Map<String, dynamic>.from(response);
    throw StateError('$rpcName returned ${response.runtimeType}, expected map');
  }

  SupabaseClient _requireClient() {
    final client = _supabase;
    if (client == null) {
      throw StateError('Supabase is not configured for the admin app.');
    }
    return client;
  }

  String _normalizeAdminPhone(String phone) {
    return PhoneNormalizer.normalizeRwanda(phone);
  }

  bool _isLegacySlaSignatureError(PostgrestException error) {
    return error.code == 'PGRST202' ||
        error.code == '42883' ||
        (error.code == 'P0001' &&
            error.message.toLowerCase().startsWith(
              'unsupported admin queue sla key:',
            ));
  }

  bool _isMissingRuntimeConfigError(PostgrestException error) {
    return error.code == '42883' || error.code == 'PGRST202';
  }
}

class _AdminActionScope {
  _AdminActionScope(this.ref)
    : repository = ref.read(adminRepositoryProvider),
      session = ref.read(adminAuthSessionScopeProvider),
      actorId = ref.read(adminIdentityProvider).asData?.value?.userId,
      identityRevision = ref.read(_adminIdentityRevisionProvider),
      roles = Set.of(
        ref.read(adminIdentityProvider).asData?.value?.roles ??
            const <String>[],
      ),
      permissions = Set.of(
        ref.read(adminIdentityProvider).asData?.value?.permissions ??
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
    final identity = ref.read(adminIdentityProvider).asData?.value;
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
