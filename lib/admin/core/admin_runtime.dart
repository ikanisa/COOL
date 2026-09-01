import 'dart:async';
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
import '../shared/components/admin_confirm_dialog.dart';
import '../shared/components/admin_data_table.dart';
import '../shared/components/admin_empty_state.dart';
import '../shared/components/admin_filter_bar.dart';
import '../shared/components/admin_loading_state.dart';
import '../shared/components/admin_page.dart';
import '../shared/components/admin_sensitive_data_gate.dart';
import '../shared/components/admin_status_chip.dart';
import 'admin_auth_guard.dart';
import 'admin_error_boundary.dart';
import 'admin_repository_base.dart';
import 'admin_review_credentials.dart';

part 'admin_login_runtime.dart';
part 'admin_overview_runtime.dart';
part 'admin_list_specs.dart';
part 'admin_list_runtime.dart';
part 'admin_operation_tables.dart';
part 'admin_group_runtime.dart';
part 'admin_payee_runtime.dart';
part 'admin_detail_specs.dart';
part 'admin_detail_runtime.dart';
part 'admin_detail_formatters.dart';
part 'bank_transfer_admin_runtime.dart';

final adminRepositoryProvider = Provider<AdminRepositoryBase>((ref) {
  return AdminRepository(ref.watch(supabaseClientProvider));
});

final adminIdentityProvider = FutureProvider<AdminIdentity?>((ref) {
  return ref.watch(adminRepositoryProvider).currentIdentity();
});

final adminRealtimeTickProvider = StateProvider<int>((_) => 0);

enum AdminCountryScope { all, rwanda, malta, other }

extension AdminCountryScopeDisplay on AdminCountryScope {
  String get label => switch (this) {
    AdminCountryScope.all => 'All countries',
    AdminCountryScope.rwanda => 'Rwanda',
    AdminCountryScope.malta => 'Malta',
    AdminCountryScope.other => 'Other countries',
  };

  IconData get icon => switch (this) {
    AdminCountryScope.all => Icons.public_outlined,
    AdminCountryScope.rwanda => Icons.cell_tower_outlined,
    AdminCountryScope.malta => Icons.account_balance_outlined,
    AdminCountryScope.other => Icons.travel_explore_outlined,
  };

  String? get rpcCode => switch (this) {
    AdminCountryScope.all => null,
    AdminCountryScope.rwanda => 'RW',
    AdminCountryScope.malta => 'MT',
    AdminCountryScope.other => 'OTHER',
  };
}

final adminCountryScopeProvider = StateProvider<AdminCountryScope>(
  (_) => AdminCountryScope.all,
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
  if (scope == AdminCountryScope.all) return true;
  final explicit = '${row.extra['country_code'] ?? ''}'.trim().toUpperCase();
  final rail = '${row.extra['rail'] ?? ''}'.trim().toLowerCase();
  final country = explicit.isNotEmpty
      ? explicit
      : rail == 'rw_momo'
      ? 'RW'
      : rail == 'diaspora_account'
      ? 'OTHER'
      : '';
  return switch (scope) {
    AdminCountryScope.all => true,
    AdminCountryScope.rwanda => country == 'RW',
    AdminCountryScope.malta => country == 'MT',
    AdminCountryScope.other =>
      country.isNotEmpty && country != 'RW' && country != 'MT',
  };
}

final adminRuntimeConfigProvider = FutureProvider<AdminRuntimeConfig?>((ref) {
  ref.watch(adminRealtimeTickProvider);
  return ref.watch(adminRepositoryProvider).runtimeConfig();
});

final adminRealtimeSubscriptionProvider = Provider.autoDispose<void>((ref) {
  final client = ref.watch(supabaseClientProvider);
  if (client == null || client.auth.currentUser == null) return;
  final subscription = RealtimeInvalidationSubscription(
    client: client,
    topic: 'collect:admin:invalidation',
    areas: collectAdminRealtimeAreas,
    onInvalidate: () {
      ref.read(adminRealtimeTickProvider.notifier).state += 1;
      ref.invalidate(adminIdentityProvider);
    },
  )..start();
  ref.onDispose(() => unawaited(subscription.dispose()));
});

class AdminRepository extends AdminRepositoryBase {
  const AdminRepository(this._supabase);

  final SupabaseClient? _supabase;

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
    return currentIdentity();
  }

  @override
  Future<void> signOut() async => _supabase?.auth.signOut();

  @override
  Future<AdminIdentity?> currentIdentity() async {
    final client = _supabase;
    if (client == null) return null;
    final row = await client.rpc<dynamic>('admin_current_user');
    if (row == null) return null;
    final data = Map<String, dynamic>.from(row as Map);
    if (data.isEmpty) return null;
    return AdminIdentity.fromJson(data);
  }

  @override
  Future<List<AdminMetric>> overviewMetrics() async {
    final row = await rpcMap('admin_overview');
    final metrics = row['metrics'];
    if (metrics is! List) return const [];
    return [
      for (final metric in metrics)
        AdminMetric.fromJson(Map<String, dynamic>.from(metric as Map)),
    ];
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
    final trimmedSearch = search?.trim();
    final normalizedSearch = trimmedSearch?.isEmpty == true
        ? null
        : trimmedSearch;
    final normalizedStatus = status?.trim().isEmpty == true
        ? null
        : status?.trim();
    final normalizedCountry = countryCode?.trim().toUpperCase();
    if (normalizedCountry?.isNotEmpty == true &&
        adminRpcUsesCountryScope(rpcName)) {
      try {
        final row = await rpcMap(
          'admin_list_country_scoped',
          params: {
            'p_rpc_name': rpcName,
            'p_country': normalizedCountry,
            'p_search': normalizedSearch,
            'p_status': normalizedStatus,
            'p_limit': limit ?? 25,
            'p_offset': offset ?? 0,
            'p_sort': sortBy?.trim().isEmpty == true
                ? 'created_at_desc'
                : sortBy?.trim() ?? 'created_at_desc',
          },
        );
        return AdminListResult.fromJson(row);
      } on PostgrestException catch (error) {
        if (!_isMissingCountryScopeRpcError(error)) rethrow;
      }
    }
    final wantsServerWindow =
        limit != null || offset != null || sortBy?.trim().isNotEmpty == true;
    if (wantsServerWindow) {
      try {
        final row = await rpcMap(
          rpcName,
          params: {
            'p_search': normalizedSearch,
            'p_status': normalizedStatus,
            'p_limit': limit,
            'p_offset': offset ?? 0,
            'p_sort': sortBy?.trim().isEmpty == true ? null : sortBy?.trim(),
          },
        );
        return AdminListResult.fromJson(row);
      } on PostgrestException catch (error) {
        if (!_isLegacyListSignatureError(error)) rethrow;
      }
    }
    final row = await rpcMap(
      rpcName,
      params: {'p_search': normalizedSearch, 'p_status': normalizedStatus},
    );
    final legacyResult = AdminListResult.fromJson(row);
    if (!wantsServerWindow || limit == null) return legacyResult;
    final start = (offset ?? 0).clamp(0, legacyResult.rows.length);
    final end = (start + limit).clamp(start, legacyResult.rows.length);
    return AdminListResult(
      rows: legacyResult.rows.sublist(start, end),
      total: legacyResult.total ?? legacyResult.rows.length,
    );
  }

  @override
  Future<Map<String, dynamic>> detail(String rpcName, String id) {
    return rpcMap(rpcName, params: {'p_id': id});
  }

  @override
  Future<AdminQueueSla?> queueSla(String queueKey) async {
    if (_supabase == null) return null;
    try {
      final row = await rpcMap(
        'admin_get_queue_sla',
        params: {'p_queue_key': queueKey},
      );
      if (row.isEmpty) return null;
      return AdminQueueSla.fromJson(row);
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
      if (row.isEmpty) return null;
      return AdminRuntimeConfig.fromJson(row);
    } on PostgrestException catch (error) {
      if (!_isMissingRuntimeConfigError(error)) rethrow;
      return null;
    }
  }

  @override
  Future<Map<String, dynamic>> action(
    String rpcName,
    Map<String, dynamic> params,
  ) {
    return rpcMap(rpcName, params: params);
  }

  Future<Map<String, dynamic>> rpcMap(
    String rpcName, {
    Map<String, dynamic>? params,
  }) async {
    final response = await _requireClient().rpc<dynamic>(
      rpcName,
      params: params,
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
    return PhoneNormalizer.normalizeInternational(phone);
  }

  bool _isLegacyListSignatureError(PostgrestException error) {
    final message =
        '${error.message} ${error.details ?? ''} ${error.hint ?? ''}'
            .toLowerCase();
    return message.contains('p_limit') ||
        message.contains('p_offset') ||
        message.contains('p_sort') ||
        message.contains('function') && message.contains('not found') ||
        error.code == 'PGRST202';
  }

  bool _isMissingCountryScopeRpcError(PostgrestException error) {
    final message =
        '${error.message} ${error.details ?? ''} ${error.hint ?? ''}'
            .toLowerCase();
    return message.contains('admin_list_country_scoped') ||
        message.contains('function') && message.contains('not found') ||
        error.code == '42883' ||
        error.code == 'PGRST202';
  }

  bool _isLegacySlaSignatureError(PostgrestException error) {
    final message =
        '${error.message} ${error.details ?? ''} ${error.hint ?? ''}'
            .toLowerCase();
    return message.contains('unsupported admin queue sla key') ||
        message.contains('p_queue_key') ||
        message.contains('admin_get_queue_sla') ||
        message.contains('function') && message.contains('not found') ||
        error.code == 'PGRST202';
  }

  bool _isMissingRuntimeConfigError(PostgrestException error) {
    final message =
        '${error.message} ${error.details ?? ''} ${error.hint ?? ''}'
            .toLowerCase();
    return message.contains('admin_runtime_config') ||
        message.contains('function') && message.contains('not found') ||
        error.code == '42883' ||
        error.code == 'PGRST202';
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
