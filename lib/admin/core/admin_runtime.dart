import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
}

class AdminLoginPage extends ConsumerStatefulWidget {
  const AdminLoginPage({super.key});

  @override
  ConsumerState<AdminLoginPage> createState() => _AdminLoginPageState();
}

class _AdminLoginPageState extends ConsumerState<AdminLoginPage> {
  final _phone = TextEditingController();
  final _otp = TextEditingController();
  var _otpSent = false;
  var _isBusy = false;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    _otp.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: colors.screenBase,
      body: DecoratedBox(
        decoration: BoxDecoration(gradient: colors.screenGradient),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final viewportWidth = MediaQuery.sizeOf(context).width;
            final layoutWidth = math.min(constraints.maxWidth, viewportWidth);
            final isCompact = layoutWidth < 600;
            final outerPadding = isCompact ? 16.0 : 32.0;
            final contentWidth = math.max(
              0.0,
              isCompact
                  ? layoutWidth - (outerPadding * 2)
                  : math.min(460.0, layoutWidth - (outerPadding * 2)),
            );
            return SafeArea(
              child: Align(
                alignment: Alignment.center,
                child: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                    horizontal: outerPadding,
                    vertical: 28,
                  ),
                  child: SizedBox(
                    width: contentWidth,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.surfaceReadable.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(color: colors.glassBorder),
                        boxShadow: [
                          BoxShadow(
                            color: CollectColors.inkPrimary.withValues(
                              alpha: 0.14,
                            ),
                            blurRadius: 48,
                            offset: const Offset(0, 24),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: EdgeInsets.all(isCompact ? 22 : 32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: CollectColors.inkPrimary,
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Icon(
                                    Icons.lock_outline,
                                    color: colors.surfaceReadable,
                                    size: 21,
                                  ),
                                ),
                                const Spacer(),
                                _AdminLoginStatusChip(colors: colors),
                              ],
                            ),
                            const SizedBox(height: 28),
                            Text(
                              'Collect admin login',
                              style: textTheme.headlineSmall?.copyWith(
                                color: colors.textPrimary,
                                fontWeight: FontWeight.w800,
                                height: 1.05,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Admin WhatsApp sign-in.',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.bodyLarge?.copyWith(
                                color: colors.textSecondary,
                                height: 1.45,
                              ),
                            ),
                            const SizedBox(height: 28),
                            Text(
                              'WhatsApp phone',
                              style: textTheme.labelLarge?.copyWith(
                                color: colors.textPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            _AdminPhoneInput(controller: _phone),
                            if (_otpSent) ...[
                              const SizedBox(height: 18),
                              Text(
                                'OTP code',
                                style: textTheme.labelLarge?.copyWith(
                                  color: colors.textPrimary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 8),
                              _AdminOtpInput(controller: _otp),
                            ],
                            if (_error != null) ...[
                              const SizedBox(height: 14),
                              _AdminLoginError(message: _error!),
                            ],
                            const SizedBox(height: 24),
                            Semantics(
                              button: true,
                              label: _otpSent
                                  ? 'Verify admin WhatsApp OTP'
                                  : 'Send admin WhatsApp OTP',
                              hint: _otpSent
                                  ? 'Submits the code.'
                                  : 'Sends the OTP.',
                              enabled: !_isBusy,
                              child: FilledButton.icon(
                                onPressed: _isBusy ? null : _submit,
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size.fromHeight(58),
                                  backgroundColor: CollectColors.inkPrimary,
                                  foregroundColor: colors.surfaceReadable,
                                  disabledBackgroundColor:
                                      colors.neutralContainer,
                                  disabledForegroundColor: colors.textMuted,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(
                                      CollectRadius.md,
                                    ),
                                  ),
                                  textStyle: textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                icon: _isBusy
                                    ? SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: colors.surfaceReadable,
                                        ),
                                      )
                                    : Icon(
                                        _otpSent
                                            ? Icons.verified_user_outlined
                                            : Icons.chat_bubble_outline,
                                        size: 20,
                                      ),
                                label: Text(
                                  _otpSent
                                      ? 'Verify code'
                                      : 'Send WhatsApp OTP',
                                ),
                              ),
                            ),
                            const SizedBox(height: 18),
                            const _AdminLoginAssuranceRow(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _submit() async {
    setState(() {
      _isBusy = true;
      _error = null;
    });
    try {
      final repository = ref.read(adminRepositoryProvider);
      if (!_otpSent) {
        await repository.sendOtp(phone: _phone.text);
        if (mounted) setState(() => _otpSent = true);
      } else {
        final identity = await repository.verifyOtp(
          phone: _phone.text,
          otp: _otp.text,
        );
        ref.invalidate(adminAuthGuardProvider);
        ref.invalidate(adminIdentityProvider);
        if (!mounted) return;
        if (identity == null) {
          setState(() => _error = 'This account is not authorized for admin.');
        } else {
          context.go('/admin');
        }
      }
    } catch (error) {
      if (mounted) setState(() => _error = _adminLoginErrorMessage(error));
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  String _adminLoginErrorMessage(Object error) {
    final message = error.toString().toLowerCase();
    if (message.contains('status code returned from hook') ||
        message.contains('authretryablefetchexception') ||
        message.contains('error sending confirmation') ||
        message.contains('send_sms') ||
        message.contains('hook') && message.contains('sms') ||
        message.contains('whatsapp otp delivery') ||
        message.contains('whatsapp otp send failed')) {
      return 'WhatsApp could not send the OTP. Check the approved template and try again.';
    }
    if (message.contains('token has expired or is invalid') ||
        message.contains('expired or is invalid') ||
        message.contains('invalid token')) {
      return 'That code is expired or already used. Request a new WhatsApp OTP.';
    }
    if (message.contains('registered admin whatsapp number')) {
      return 'Use the registered admin WhatsApp number.';
    }
    if (message.contains('not authorized') ||
        message.contains('overview.read') ||
        message.contains('platform admin')) {
      return 'WhatsApp verified, but this profile is not approved for admin access.';
    }
    return 'Admin sign-in failed. Try again.';
  }
}

class _AdminPhoneInput extends StatelessWidget {
  const _AdminPhoneInput({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Semantics(
      textField: true,
      label: 'WhatsApp phone',
      hint: 'Registered Rwanda WhatsApp number used for Collect admin sign-in.',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceMuted,
          borderRadius: BorderRadius.circular(CollectRadius.md),
          border: Border.all(color: colors.borderSoft),
        ),
        child: Row(
          children: [
            Container(
              height: 58,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                border: Border(right: BorderSide(color: colors.borderSoft)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'RW',
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.keyboard_arrow_down,
                    color: colors.textSecondary,
                    size: 18,
                  ),
                ],
              ),
            ),
            Expanded(
              child: TextField(
                controller: controller,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
                decoration: const InputDecoration(
                  hintText: '+250 7XX XXX XXX',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminOtpInput extends StatelessWidget {
  const _AdminOtpInput({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Semantics(
      textField: true,
      label: 'OTP code',
      hint: 'Six digit WhatsApp one-time password for admin sign-in.',
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.done,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: colors.textPrimary,
          fontWeight: FontWeight.w700,
        ),
        decoration: InputDecoration(
          hintText: '6-digit code',
          filled: true,
          fillColor: colors.surfaceMuted,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 18,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(CollectRadius.md),
            borderSide: BorderSide(color: colors.borderSoft),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(CollectRadius.md),
            borderSide: BorderSide(color: colors.borderSoft),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(CollectRadius.md),
            borderSide: const BorderSide(
              color: CollectColors.inkPrimary,
              width: 2,
            ),
          ),
        ),
      ),
    );
  }
}

class _AdminLoginStatusChip extends StatelessWidget {
  const _AdminLoginStatusChip({required this.colors});

  final CollectColors colors;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Secure admin area',
      hint: 'Restricted console with audited operator activity.',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.successContainer,
          borderRadius: CollectRadius.pillBorder,
          border: Border.all(color: colors.success.withValues(alpha: 0.18)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.shield_outlined, size: 16, color: colors.success),
              const SizedBox(width: 6),
              Text(
                'Secure',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: colors.success,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminLoginAssuranceRow extends StatelessWidget {
  const _AdminLoginAssuranceRow();

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final style = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: colors.textMuted, height: 1.35);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.verified_user_outlined, size: 18, color: colors.success),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Restricted to approved operators. Activity is logged for audit review.',
            style: style,
          ),
        ),
      ],
    );
  }
}

class _AdminLoginError extends StatelessWidget {
  const _AdminLoginError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Semantics(
      liveRegion: true,
      label: 'Admin sign-in error',
      value: message,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.dangerContainer,
          borderRadius: BorderRadius.circular(CollectRadius.md),
          border: Border.all(color: colors.danger.withValues(alpha: 0.2)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline, color: colors.danger, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.danger,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
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

class AdminRpcListPage extends ConsumerStatefulWidget {
  const AdminRpcListPage({
    required this.title,
    required this.rpcName,
    this.detailPathPrefix,
    this.actionKind,
    super.key,
  });

  final String title;
  final String rpcName;
  final String? detailPathPrefix;
  final String? actionKind;

  @override
  ConsumerState<AdminRpcListPage> createState() => _AdminRpcListPageState();
}

class _AdminRpcListPageState extends ConsumerState<AdminRpcListPage> {
  static const _pageSize = 25;

  final _search = TextEditingController();
  var _status = '';
  var _sortBy = 'created_at_desc';
  var _page = 0;
  late Future<AdminListResult> _future;
  var _lastRealtimeTick = 0;

  _AdminListSpec get _spec => _AdminListSpec.forRpc(widget.rpcName);

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final realtimeTick = ref.watch(adminRealtimeTickProvider);
    if (_lastRealtimeTick != realtimeTick) {
      _lastRealtimeTick = realtimeTick;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _refresh();
      });
    }
    return AdminPage(
      title: widget.title,
      subtitle: _spec.subtitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdminFilterBar(
            searchController: _search,
            status: _status,
            sortBy: _sortBy,
            statusOptions: _spec.statusOptions,
            sortOptions: _spec.sortOptions,
            onStatusChanged: (value) => setState(() {
              _status = value;
              _page = 0;
              _future = _load();
            }),
            onSortChanged: (value) => setState(() {
              _sortBy = value;
              _page = 0;
              _future = _load();
            }),
            onRefresh: () => _refresh(resetPage: true),
          ),
          const SizedBox(height: 16),
          _AdminQueueSummary(spec: _spec),
          const SizedBox(height: 16),
          FutureBuilder<AdminListResult>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return AdminLoadingState(
                  title: 'Loading ${widget.title.toLowerCase()}',
                  message: 'Fetching the latest rows and filters.',
                );
              }
              if (snapshot.hasError) {
                return AdminSafeErrorPanel(error: snapshot.error!);
              }
              final result = snapshot.data;
              final rows = result?.rows ?? const [];
              if (rows.isEmpty) {
                return AdminEmptyState(
                  title: 'No ${widget.title.toLowerCase()}',
                  message: 'Try another filter or refresh this queue.',
                );
              }
              final total = result?.total ?? rows.length;
              final maxPage = total == 0
                  ? 0
                  : ((total - 1) / _pageSize).floor();
              final page = _page.clamp(0, maxPage);
              final start = page * _pageSize;
              final end = (start + rows.length).clamp(0, total);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AdminDataTable(
                    rows: rows,
                    onOpen: _openRow,
                    trailingBuilder: widget.actionKind == null
                        ? null
                        : (row) => _AdminRowActions(
                            row: row,
                            actionKind: widget.actionKind!,
                            onDone: () => _refresh(),
                          ),
                  ),
                  const SizedBox(height: 12),
                  _AdminPaginationBar(
                    start: start + 1,
                    end: end,
                    total: total,
                    canGoBack: page > 0,
                    canGoNext: page < maxPage,
                    onPrevious: () => setState(() {
                      _page = page - 1;
                      _future = _load();
                    }),
                    onNext: () => setState(() {
                      _page = page + 1;
                      _future = _load();
                    }),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Future<AdminListResult> _load() {
    return ref
        .read(adminRepositoryProvider)
        .list(
          widget.rpcName,
          search: _search.text,
          status: _status,
          limit: _pageSize,
          offset: _page * _pageSize,
          sortBy: _sortBy,
        );
  }

  void _refresh({bool resetPage = false}) {
    setState(() {
      if (resetPage) _page = 0;
      _future = _load();
    });
  }

  void _openRow(AdminTableRowData row) {
    final prefix = widget.detailPathPrefix;
    if (prefix == null) return;
    context.go('$prefix/${row.id}');
  }
}

class _AdminListSpec {
  const _AdminListSpec({
    required this.title,
    required this.subtitle,
    required this.statusOptions,
    required this.sortOptions,
    this.prioritySignals = const [],
  });

  final String title;
  final String subtitle;
  final List<AdminFilterOption> statusOptions;
  final List<AdminFilterOption> sortOptions;
  final List<_AdminQueueSignal> prioritySignals;

  static const _defaultStatuses = [
    AdminFilterOption(value: '', label: 'All'),
    AdminFilterOption(value: 'pending', label: 'Pending'),
    AdminFilterOption(value: 'active', label: 'Active'),
    AdminFilterOption(value: 'needs_review', label: 'Review'),
  ];

  static const _defaultSorts = [
    AdminFilterOption(value: 'created_at_desc', label: 'Newest'),
    AdminFilterOption(value: 'created_at_asc', label: 'Oldest'),
  ];

  factory _AdminListSpec.forRpc(String rpcName) {
    return switch (rpcName) {
      'admin_list_payment_events' => const _AdminListSpec(
        title: 'SMS parsing',
        subtitle: 'Triage MoMo SMS events.',
        statusOptions: [
          AdminFilterOption(value: '', label: 'All'),
          AdminFilterOption(value: 'needs_review', label: 'Review'),
          AdminFilterOption(value: 'unallocated', label: 'Unallocated'),
          AdminFilterOption(value: 'ambiguous', label: 'Ambiguous'),
          AdminFilterOption(value: 'allocated', label: 'Allocated'),
        ],
        sortOptions: [
          AdminFilterOption(value: 'created_at_desc', label: 'Newest'),
          AdminFilterOption(value: 'created_at_asc', label: 'Oldest'),
          AdminFilterOption(value: 'amount_desc', label: 'Amount high'),
          AdminFilterOption(value: 'amount_asc', label: 'Amount low'),
        ],
        prioritySignals: [
          _AdminQueueSignal(Icons.rule_outlined, 'Ambiguous matches'),
          _AdminQueueSignal(Icons.replay_outlined, 'Reason required'),
          _AdminQueueSignal(Icons.privacy_tip_outlined, 'Raw SMS hidden'),
        ],
      ),
      'admin_list_allocations' => const _AdminListSpec(
        title: 'Allocations',
        subtitle: 'Review matched payments.',
        statusOptions: [
          AdminFilterOption(value: '', label: 'All'),
          AdminFilterOption(value: 'allocated', label: 'Allocated'),
          AdminFilterOption(value: 'needs_review', label: 'Review'),
        ],
        sortOptions: _defaultSorts,
        prioritySignals: [
          _AdminQueueSignal(Icons.account_tree_outlined, 'Matched events'),
          _AdminQueueSignal(Icons.history_outlined, 'Audit history first'),
        ],
      ),
      'admin_list_unallocated' => const _AdminListSpec(
        title: 'Exceptions',
        subtitle: 'Resolve open MoMo events.',
        statusOptions: [
          AdminFilterOption(value: '', label: 'Open'),
          AdminFilterOption(value: 'needs_review', label: 'Review'),
          AdminFilterOption(value: 'unallocated', label: 'Unallocated'),
          AdminFilterOption(value: 'ambiguous', label: 'Ambiguous'),
        ],
        sortOptions: [
          AdminFilterOption(value: 'created_at_desc', label: 'Newest'),
          AdminFilterOption(value: 'created_at_asc', label: 'Oldest'),
          AdminFilterOption(value: 'amount_desc', label: 'Amount high'),
          AdminFilterOption(value: 'amount_asc', label: 'Amount low'),
        ],
        prioritySignals: [
          _AdminQueueSignal(Icons.priority_high_outlined, 'Open exceptions'),
          _AdminQueueSignal(Icons.notes_outlined, 'Document decisions'),
          _AdminQueueSignal(Icons.lock_outline, 'No raw SMS in queue'),
        ],
      ),
      'admin_list_sms_metadata' => const _AdminListSpec(
        title: 'SMS metadata',
        subtitle: 'Review SMS metadata.',
        statusOptions: [
          AdminFilterOption(value: '', label: 'All'),
          AdminFilterOption(value: 'needs_review', label: 'Review'),
          AdminFilterOption(value: 'parsed', label: 'Parsed'),
          AdminFilterOption(value: 'failed', label: 'Failed'),
        ],
        sortOptions: _defaultSorts,
        prioritySignals: [
          _AdminQueueSignal(Icons.sms_outlined, 'Metadata only'),
          _AdminQueueSignal(Icons.verified_user_outlined, 'Reveal is audited'),
        ],
      ),
      _ => const _AdminListSpec(
        title: 'Admin queue',
        subtitle: 'Review records.',
        statusOptions: _defaultStatuses,
        sortOptions: _defaultSorts,
      ),
    };
  }
}

class _AdminQueueSignal {
  const _AdminQueueSignal(this.icon, this.label);

  final IconData icon;
  final String label;
}

class _AdminQueueSummary extends StatelessWidget {
  const _AdminQueueSummary({required this.spec});

  final _AdminListSpec spec;

  @override
  Widget build(BuildContext context) {
    if (spec.prioritySignals.isEmpty) return const SizedBox.shrink();
    final colors = context.collectColors;
    final maxChipWidth = math.max(
      0.0,
      math.min(260.0, MediaQuery.sizeOf(context).width - 48),
    );
    return Semantics(
      container: true,
      label: '${spec.title} operator workflow signals',
      hint: spec.subtitle,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.textPrimary.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: colors.surfaceReadable.withValues(alpha: 0.12),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final signal in spec.prioritySignals)
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.surfaceReadable.withValues(alpha: 0.11),
                    borderRadius: BorderRadius.circular(CollectRadius.md),
                    border: Border.all(
                      color: colors.surfaceReadable.withValues(alpha: 0.14),
                    ),
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxChipWidth),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            signal.icon,
                            size: 18,
                            color: colors.surfaceReadable,
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              signal.label,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelLarge
                                  ?.copyWith(
                                    color: colors.surfaceReadable,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminPaginationBar extends StatelessWidget {
  const _AdminPaginationBar({
    required this.start,
    required this.end,
    required this.total,
    required this.canGoBack,
    required this.canGoNext,
    required this.onPrevious,
    required this.onNext,
  });

  final int start;
  final int end;
  final int total;
  final bool canGoBack;
  final bool canGoNext;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceReadable.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.borderAccent),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Showing $start-$end of $total',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.textSecondary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Semantics(
              button: true,
              label: 'Previous admin results page',
              hint: canGoBack
                  ? 'Shows the previous page of admin queue results.'
                  : 'Unavailable on the first page.',
              enabled: canGoBack,
              child: IconButton.outlined(
                tooltip: 'Previous page',
                onPressed: canGoBack ? onPrevious : null,
                icon: const Icon(Icons.chevron_left),
              ),
            ),
            const SizedBox(width: 8),
            Semantics(
              button: true,
              label: 'Next admin results page',
              hint: canGoNext
                  ? 'Shows the next page of admin queue results.'
                  : 'Unavailable on the last page.',
              enabled: canGoNext,
              child: IconButton.outlined(
                tooltip: 'Next page',
                onPressed: canGoNext ? onNext : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminOverviewSignalCard extends StatelessWidget {
  const _AdminOverviewSignalCard();

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return SizedBox(
      width: 260,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceReadable.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: colors.borderAccent),
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.textPrimary,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: Icon(
                    Icons.privacy_tip_outlined,
                    color: colors.surfaceReadable,
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Sensitive data gated',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Raw details stay gated.',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colors.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminRowActions extends ConsumerWidget {
  const _AdminRowActions({
    required this.row,
    required this.actionKind,
    required this.onDone,
  });

  final AdminTableRowData row;
  final String actionKind;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identity = ref.watch(adminIdentityProvider).valueOrNull;
    return Wrap(
      spacing: 8,
      children: switch (actionKind) {
        'payment_event_reparse'
            when _adminHasPermission(identity, 'payment_events.reparse') =>
          [
            Semantics(
              container: true,
              button: true,
              label: 'Request SMS reparse for ${row.title}',
              hint: 'Opens a reason dialog before queuing a reparse action.',
              child: ExcludeSemantics(
                child: TextButton(
                  onPressed: () => _reparse(context, ref),
                  child: const Text('Reparse'),
                ),
              ),
            ),
          ],
        _ => const [],
      },
    );
  }

  Future<void> _reparse(BuildContext context, WidgetRef ref) async {
    final reason = await showAdminReasonDialog(
      context,
      title: 'Request SMS reparse',
      actionLabel: 'Request reparse',
    );
    if (reason == null) return;
    await ref.read(adminRepositoryProvider).action(
      'admin_reparse_payment_event',
      {'p_event_id': row.id, 'p_reason': reason},
    );
    onDone();
  }
}

class AdminDetailPage extends ConsumerWidget {
  const AdminDetailPage({
    required this.title,
    required this.rpcName,
    required this.id,
    super.key,
  });

  final String title;
  final String rpcName;
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(adminRealtimeTickProvider);
    return AdminPage(
      title: title,
      child: FutureBuilder<Map<String, dynamic>>(
        future: ref.read(adminRepositoryProvider).detail(rpcName, id),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return AdminLoadingState(
              title: 'Loading ${title.toLowerCase()}',
              message: 'Fetching record.',
            );
          }
          if (snapshot.hasError) {
            return AdminSafeErrorPanel(error: snapshot.error!);
          }
          final data = snapshot.data ?? const {};
          if (data.isEmpty) {
            return const AdminEmptyState(title: 'Record not found');
          }
          return _AdminRecordDetailPanel(
            title: title,
            rpcName: rpcName,
            id: id,
            data: data,
          );
        },
      ),
    );
  }
}

class AdminSmsDetailPage extends ConsumerWidget {
  const AdminSmsDetailPage({required this.id, super.key});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(adminRealtimeTickProvider);
    final identity = ref.watch(adminIdentityProvider).valueOrNull;
    return AdminPage(
      title: 'SMS metadata',
      subtitle: 'Raw SMS stays gated.',
      child: FutureBuilder<Map<String, dynamic>>(
        future: ref
            .read(adminRepositoryProvider)
            .detail('admin_get_sms_metadata', id),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const AdminLoadingState(
              title: 'Loading SMS metadata',
              message: 'Fetching metadata.',
            );
          }
          if (snapshot.hasError) {
            return AdminSafeErrorPanel(error: snapshot.error!);
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _AdminRecordDetailPanel(
                title: 'SMS metadata',
                rpcName: 'admin_get_sms_metadata',
                id: id,
                data: snapshot.data ?? const {},
              ),
              const SizedBox(height: 16),
              if (identity?.permissions.contains('sms.raw.reveal') == true)
                AdminSensitiveDataGate(
                  label: 'Raw SMS',
                  onReveal: (reason) async {
                    final response = await ref
                        .read(adminRepositoryProvider)
                        .action('admin_reveal_raw_sms', {
                          'p_sms_id': id,
                          'p_reason': reason,
                        });
                    return (response['message'] as String?) ?? '';
                  },
                )
              else
                const AdminEmptyState(
                  title: 'Raw SMS restricted',
                  message: 'Reveal permission missing.',
                ),
            ],
          );
        },
      ),
    );
  }
}

class _AdminRecordDetailPanel extends ConsumerWidget {
  const _AdminRecordDetailPanel({
    required this.title,
    required this.rpcName,
    required this.id,
    required this.data,
  });

  final String title;
  final String rpcName;
  final String id;
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spec = _AdminDetailSpec.forRpc(rpcName, title);
    final fields = _adminDetailFields(spec, data);
    final identity = ref.watch(adminIdentityProvider).valueOrNull;
    final colors = context.collectColors;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: '${spec.heading} detail panel',
      hint: spec.subtitle,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceReadable.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: colors.borderAccent),
          boxShadow: [
            BoxShadow(
              color: colors.textPrimary.withValues(alpha: 0.12),
              blurRadius: 28,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    spec.heading,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (_detailValue(data, const ['status']).isNotEmpty)
                    AdminStatusChip(
                      label: _detailValue(data, const ['status']),
                    ),
                ],
              ),
              if (spec.subtitle.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  spec.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
                ),
              ],
              if (_detailValue(data, const ['status']).isNotEmpty) ...[
                const SizedBox(height: 8),
                SelectableText(
                  '"status": "${_detailValue(data, const ['status'])}"',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final field in fields)
                    _AdminDetailFieldCard(
                      label: field.label,
                      value: field.value,
                    ),
                ],
              ),
              if (rpcName == 'admin_get_payment_event' &&
                  _adminHasPermission(identity, 'payment_events.reparse')) ...[
                const SizedBox(height: 18),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Semantics(
                    container: true,
                    button: true,
                    label: 'Request SMS payment event reparse',
                    hint:
                        'Opens a reason dialog before queuing this payment event for parser review.',
                    child: ExcludeSemantics(
                      child: FilledButton.icon(
                        onPressed: () => _requestReparse(context, ref),
                        icon: const Icon(Icons.replay_outlined),
                        label: const Text('Request reparse'),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _requestReparse(BuildContext context, WidgetRef ref) async {
    final reason = await showAdminReasonDialog(
      context,
      title: 'Request SMS reparse',
      actionLabel: 'Request reparse',
    );
    if (reason == null) return;
    await ref.read(adminRepositoryProvider).action(
      'admin_reparse_payment_event',
      {'p_event_id': id, 'p_reason': reason},
    );
  }
}

class _AdminDetailFieldCard extends StatelessWidget {
  const _AdminDetailFieldCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Semantics(
      label: label,
      value: value,
      readOnly: true,
      child: ExcludeSemantics(
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 220, maxWidth: 340),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surfaceMuted.withValues(alpha: 0.78),
              borderRadius: BorderRadius.circular(CollectRadius.md),
              border: Border.all(color: colors.borderAccent),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: colors.textSecondary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  SelectableText(
                    value,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AdminDetailSpec {
  const _AdminDetailSpec({
    required this.heading,
    required this.subtitle,
    required this.fields,
  });

  final String heading;
  final String subtitle;
  final List<_AdminDetailFieldSpec> fields;

  factory _AdminDetailSpec.forRpc(String rpcName, String fallbackTitle) {
    return switch (rpcName) {
      'admin_get_collection' => const _AdminDetailSpec(
        heading: 'Group operations profile',
        subtitle: 'Group support context.',
        fields: [
          _AdminDetailFieldSpec('Group ID', ['id']),
          _AdminDetailFieldSpec('Group name', ['name', 'title']),
          _AdminDetailFieldSpec('Public ID', ['public_id', 'collect_id']),
          _AdminDetailFieldSpec('Visibility', ['visibility']),
          _AdminDetailFieldSpec('Members', ['member_count', 'members_count']),
          _AdminDetailFieldSpec('Raised', ['total_raised', 'amount']),
          _AdminDetailFieldSpec('Created', ['created_at']),
        ],
      ),
      'admin_get_user' => const _AdminDetailSpec(
        heading: 'Member support profile',
        subtitle: 'Scoped member context.',
        fields: [
          _AdminDetailFieldSpec('User ID', ['id', 'user_id']),
          _AdminDetailFieldSpec('Collect ID', ['collect_id', 'public_id']),
          _AdminDetailFieldSpec('Display name', ['display_name', 'name']),
          _AdminDetailFieldSpec('Phone', ['phone_masked', 'phone']),
          _AdminDetailFieldSpec('Status', ['status']),
          _AdminDetailFieldSpec('Created', ['created_at']),
        ],
      ),
      'admin_get_payment' => const _AdminDetailSpec(
        heading: 'Payment intent review',
        subtitle: 'MoMo intent state.',
        fields: [
          _AdminDetailFieldSpec('Intent ID', ['id']),
          _AdminDetailFieldSpec('Group', ['collection_id', 'group_id']),
          _AdminDetailFieldSpec('Member', ['user_id', 'member_id']),
          _AdminDetailFieldSpec('Expected amount', [
            'amount',
            'expected_amount_rwf',
          ]),
          _AdminDetailFieldSpec('Status', ['status']),
          _AdminDetailFieldSpec('Expires', ['expires_at']),
          _AdminDetailFieldSpec('Created', ['created_at']),
        ],
      ),
      'admin_get_payment_event' => const _AdminDetailSpec(
        heading: 'SMS payment event review',
        subtitle: 'Parsed payment event.',
        fields: [
          _AdminDetailFieldSpec('Event ID', ['id']),
          _AdminDetailFieldSpec('Transaction', [
            'transaction_id',
            'momo_reference',
          ]),
          _AdminDetailFieldSpec('Amount', ['amount', 'amount_rwf']),
          _AdminDetailFieldSpec('Sender', ['sender_masked', 'payer_masked']),
          _AdminDetailFieldSpec('Receiver', [
            'receiver_masked',
            'receiver_momo_masked',
          ]),
          _AdminDetailFieldSpec('Payment intent', ['payment_intent_id']),
          _AdminDetailFieldSpec('Status', ['status']),
          _AdminDetailFieldSpec('Parsed', ['parsed_at', 'created_at']),
        ],
      ),
      'admin_get_receiver' => const _AdminDetailSpec(
        heading: 'Receiver route review',
        subtitle: 'MoMo receiver route.',
        fields: [
          _AdminDetailFieldSpec('Receiver ID', ['id']),
          _AdminDetailFieldSpec('Label', ['label', 'receiver_label']),
          _AdminDetailFieldSpec('MoMo route', ['momo_masked', 'phone_masked']),
          _AdminDetailFieldSpec('Group', ['collection_id', 'group_id']),
          _AdminDetailFieldSpec('Status', ['status']),
          _AdminDetailFieldSpec('Created', ['created_at']),
        ],
      ),
      'admin_get_sms_metadata' => const _AdminDetailSpec(
        heading: 'SMS metadata review',
        subtitle: 'Metadata only.',
        fields: [
          _AdminDetailFieldSpec('SMS ID', ['id']),
          _AdminDetailFieldSpec('Sender', ['sender_masked']),
          _AdminDetailFieldSpec('Receiver', ['receiver_masked']),
          _AdminDetailFieldSpec('Parser status', ['status', 'parser_status']),
          _AdminDetailFieldSpec('Received', ['received_at', 'created_at']),
        ],
      ),
      'admin_system_health' => const _AdminDetailSpec(
        heading: 'System health',
        subtitle: 'Platform readiness.',
        fields: [
          _AdminDetailFieldSpec('Status', ['status']),
          _AdminDetailFieldSpec('Database', ['database', 'db']),
          _AdminDetailFieldSpec('Edge functions', ['edge_functions']),
          _AdminDetailFieldSpec('Realtime', ['realtime']),
          _AdminDetailFieldSpec('Checked', ['checked_at', 'created_at']),
        ],
      ),
      _ => _AdminDetailSpec(
        heading: fallbackTitle,
        subtitle: 'Record fields.',
        fields: const [
          _AdminDetailFieldSpec('Record ID', ['id']),
          _AdminDetailFieldSpec('Status', ['status']),
          _AdminDetailFieldSpec('Created', ['created_at']),
        ],
      ),
    };
  }
}

class _AdminDetailFieldSpec {
  const _AdminDetailFieldSpec(this.label, this.keys);

  final String label;
  final List<String> keys;
}

class _AdminDetailFieldValue {
  const _AdminDetailFieldValue({required this.label, required this.value});

  final String label;
  final String value;
}

List<_AdminDetailFieldValue> _adminDetailFields(
  _AdminDetailSpec spec,
  Map<String, dynamic> data,
) {
  final usedKeys = <String>{};
  final fields = <_AdminDetailFieldValue>[];
  for (final field in spec.fields) {
    final value = _detailValue(data, field.keys, usedKeys: usedKeys);
    if (value.isNotEmpty) {
      fields.add(_AdminDetailFieldValue(label: field.label, value: value));
    }
  }
  final extras = data.entries
      .where((entry) {
        return !usedKeys.contains(entry.key) && _isSafeDetailKey(entry.key);
      })
      .take(6);
  for (final entry in extras) {
    final value = _formatDetailValue(entry.value);
    if (value.isNotEmpty) {
      fields.add(
        _AdminDetailFieldValue(
          label: _labelizeDetailKey(entry.key),
          value: value,
        ),
      );
    }
  }
  return fields;
}

String _detailValue(
  Map<String, dynamic> data,
  List<String> keys, {
  Set<String>? usedKeys,
}) {
  for (final key in keys) {
    if (!_isSafeDetailKey(key)) continue;
    if (!data.containsKey(key)) continue;
    final value = _formatDetailValue(data[key]);
    if (value.isEmpty) continue;
    usedKeys?.add(key);
    return value;
  }
  return '';
}

String _formatDetailValue(Object? value) {
  if (value == null) return '';
  if (value is DateTime) return _formatDetailDate(value);
  if (value is num) return value.toString();
  if (value is bool) return value ? 'Yes' : 'No';
  if (value is List) {
    return value.map(_formatDetailValue).where((v) => v.isNotEmpty).join(', ');
  }
  if (value is Map) return '';
  return value.toString().trim();
}

String _labelizeDetailKey(String key) {
  final words = key.split('_').where((word) => word.isNotEmpty).toList();
  if (words.isEmpty) return 'Field';
  final label = words.join(' ');
  return label[0].toUpperCase() + label.substring(1);
}

bool _isSafeDetailKey(String key) {
  final normalized = key.toLowerCase();
  return !normalized.contains('raw') &&
      !normalized.contains('secret') &&
      !normalized.contains('token') &&
      !normalized.contains('hash') &&
      !normalized.contains('body') &&
      !normalized.contains('pin');
}

String _formatDetailDate(DateTime value) {
  return '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}

bool _adminHasPermission(AdminIdentity? identity, String permission) {
  return identity?.permissions.contains(permission) == true;
}
