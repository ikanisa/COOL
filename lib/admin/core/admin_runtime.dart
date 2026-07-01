import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/theme/collect_colors.dart';
import '../../app/theme/collect_radius.dart';
import '../../core/security/phone_normalizer.dart';
import '../../core/supabase/realtime_invalidation.dart';
import '../../core/supabase/supabase_module.dart';
import '../shared/components/admin_confirm_dialog.dart';
import '../shared/components/admin_data_table.dart';
import '../shared/components/admin_empty_state.dart';
import '../shared/components/admin_filter_bar.dart';
import '../shared/components/admin_loading_state.dart';
import '../shared/components/admin_metric_card.dart';
import '../shared/components/admin_page.dart';
import '../shared/components/admin_sensitive_data_gate.dart';
import '../shared/components/admin_status_chip.dart';
import 'admin_auth_guard.dart';
import 'admin_error_boundary.dart';
import 'admin_repository_base.dart';

part 'admin_login_runtime.dart';
part 'admin_list_specs.dart';
part 'admin_list_export.dart';
part 'admin_list_workflow.dart';
part 'admin_list_runtime.dart';
part 'admin_detail_specs.dart';
part 'admin_detail_runtime.dart';
part 'admin_detail_formatters.dart';

final adminRepositoryProvider = Provider<AdminRepositoryBase>((ref) {
  return AdminRepository(ref.watch(supabaseClientProvider));
});

final adminIdentityProvider = FutureProvider<AdminIdentity?>((ref) {
  return ref.watch(adminRepositoryProvider).currentIdentity();
});

final _adminOverviewProvider = FutureProvider<List<AdminMetric>>((ref) {
  ref.watch(adminRealtimeTickProvider);
  return ref.watch(adminRepositoryProvider).overviewMetrics();
});

final adminRealtimeTickProvider = StateProvider<int>((_) => 0);

const _collectAdminWhatsAppPhone = '+250788767816';

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
  }) async {
    final trimmedSearch = search?.trim();
    final normalizedSearch = trimmedSearch?.isEmpty == true
        ? null
        : trimmedSearch;
    final normalizedStatus = status?.trim().isEmpty == true
        ? null
        : status?.trim();
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
    final normalized = PhoneNormalizer.normalizeInternational(phone);
    if (normalized != _collectAdminWhatsAppPhone) {
      throw const FormatException('Use the registered admin WhatsApp number.');
    }
    return normalized;
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

  bool _isLegacySlaSignatureError(PostgrestException error) {
    final message =
        '${error.message} ${error.details ?? ''} ${error.hint ?? ''}'
            .toLowerCase();
    return message.contains('p_queue_key') ||
        message.contains('admin_get_queue_sla') ||
        message.contains('function') && message.contains('not found') ||
        error.code == 'PGRST202';
  }
}

class AdminDeniedPage extends StatelessWidget {
  const AdminDeniedPage({this.requiredPermission, super.key});

  final String? requiredPermission;

  @override
  Widget build(BuildContext context) {
    final permission = requiredPermission;
    return AdminPage(
      title: 'Admin access required',
      subtitle: permission == null
          ? 'Admin permission missing.'
          : 'Missing $permission.',
    );
  }
}

class AdminOverviewContent extends ConsumerWidget {
  const AdminOverviewContent({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metrics = ref.watch(_adminOverviewProvider);
    return AdminPage(
      title: 'Operations overview',
      subtitle: 'Live queues. Private data gated.',
      child: metrics.when(
        loading: () => const AdminLoadingState(
          title: 'Loading operations overview',
          message: 'Refreshing queues.',
        ),
        error: (error, _) => AdminSafeErrorPanel(error: error),
        data: (items) {
          if (items.isEmpty) {
            return const AdminEmptyState(
              title: 'No admin metrics yet',
              message: 'Metrics appear after the platform has live activity.',
            );
          }
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final item in items) AdminMetricCard(metric: item),
              const _AdminOverviewSignalCard(),
            ],
          );
        },
      ),
    );
  }
}
