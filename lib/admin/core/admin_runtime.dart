import 'dart:async';
import 'dart:convert';
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
import '../shared/components/admin_metric_card.dart';
import '../shared/components/admin_page.dart';
import '../shared/components/admin_sensitive_data_gate.dart';
import 'admin_auth_guard.dart';
import 'admin_repository_base.dart';

final adminRepositoryProvider = Provider<AdminRepository>((ref) {
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

  Future<void> sendOtp({required String phone}) async {
    final normalizedPhone = _normalizeAdminPhone(phone);
    await _requireClient().auth.signInWithOtp(
      phone: normalizedPhone,
      channel: OtpChannel.whatsapp,
    );
  }

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
    await client.rpc<dynamic>('admin_bootstrap_whatsapp_operator');
    return currentIdentity();
  }

  Future<void> signOut() async => _supabase?.auth.signOut();

  Future<AdminIdentity?> currentIdentity() async {
    final client = _supabase;
    if (client == null) return null;
    final row = await client.rpc<dynamic>('admin_current_user');
    if (row == null) return null;
    final data = Map<String, dynamic>.from(row as Map);
    if (data.isEmpty) return null;
    return AdminIdentity.fromJson(data);
  }

  Future<List<AdminMetric>> overviewMetrics() async {
    final row = await rpcMap('admin_overview');
    final metrics = row['metrics'];
    if (metrics is! List) return const [];
    return [
      for (final metric in metrics)
        AdminMetric.fromJson(Map<String, dynamic>.from(metric as Map)),
    ];
  }

  Future<AdminListResult> list(
    String rpcName, {
    String? search,
    String? status,
  }) async {
    final row = await rpcMap(
      rpcName,
      params: {
        'p_search': search?.trim().isEmpty == true ? null : search?.trim(),
        'p_status': status?.trim().isEmpty == true ? null : status?.trim(),
      },
    );
    return AdminListResult.fromJson(row);
  }

  Future<Map<String, dynamic>> detail(String rpcName, String id) {
    return rpcMap(rpcName, params: {'p_id': id});
  }

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
}

class AdminLoginPage extends ConsumerStatefulWidget {
  const AdminLoginPage({super.key});

  @override
  ConsumerState<AdminLoginPage> createState() => _AdminLoginPageState();
}

class _AdminLoginPageState extends ConsumerState<AdminLoginPage> {
  final _phone = TextEditingController(text: _collectAdminWhatsAppPhone);
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
      backgroundColor: const Color(0xFFF7F8FA),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 600;
          final contentWidth = math.max(
            0.0,
            math.min(isCompact ? 430.0 : 460.0, constraints.maxWidth - 32),
          );
          return SafeArea(
            child: Align(
              alignment: Alignment.center,
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: isCompact ? 20 : 32,
                  vertical: 28,
                ),
                child: SizedBox(
                  width: contentWidth,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: const Color(0xFFE8EAF0)),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x140B1020),
                          blurRadius: 40,
                          offset: Offset(0, 22),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(isCompact ? 24 : 32),
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
                                  color: const Color(0xFF0D1117),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: const Icon(
                                  Icons.lock_outline,
                                  color: Colors.white,
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
                              color: const Color(0xFF101217),
                              fontWeight: FontWeight.w800,
                              height: 1.05,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Sign in with the registered admin WhatsApp number.',
                            style: textTheme.bodyLarge?.copyWith(
                              color: const Color(0xFF596070),
                              height: 1.45,
                            ),
                          ),
                          const SizedBox(height: 28),
                          Text(
                            'WhatsApp phone',
                            style: textTheme.labelLarge?.copyWith(
                              color: const Color(0xFF303541),
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
                                color: const Color(0xFF303541),
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
                          FilledButton.icon(
                            onPressed: _isBusy ? null : _submit,
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(58),
                              backgroundColor: const Color(0xFF111318),
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: const Color(0xFFE4E7EE),
                              disabledForegroundColor: const Color(0xFF8B93A3),
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
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Icon(
                                    _otpSent
                                        ? Icons.verified_user_outlined
                                        : Icons.chat_bubble_outline,
                                    size: 20,
                                  ),
                            label: Text(
                              _otpSent ? 'Verify code' : 'Send WhatsApp OTP',
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
    final message = error.toString();
    if (message.contains('status code returned from hook') ||
        message.contains('AuthRetryableFetchException') ||
        message.contains('WhatsApp OTP send failed')) {
      return 'WhatsApp could not send the OTP. Check the approved template and try again.';
    }
    if (message.contains('Token has expired or is invalid') ||
        message.contains('expired or is invalid') ||
        message.contains('Invalid token')) {
      return 'That code is expired or already used. Request a new WhatsApp OTP.';
    }
    if (message.contains('registered admin WhatsApp number')) {
      return 'Use the registered admin WhatsApp number.';
    }
    if (message.contains('admin_bootstrap_whatsapp_operator') ||
        message.contains('profile setup') ||
        message.contains('Platform owner role')) {
      return 'WhatsApp verified, but admin profile setup failed. Request a new OTP and try again.';
    }
    return 'Admin sign-in failed. Try again.';
  }
}

class _AdminPhoneInput extends StatelessWidget {
  const _AdminPhoneInput({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      textField: true,
      label: 'WhatsApp phone',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFFF5F7FA),
          borderRadius: BorderRadius.circular(CollectRadius.md),
          border: Border.all(color: const Color(0xFFDDE2EA)),
        ),
        child: Row(
          children: [
            Container(
              height: 58,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: const BoxDecoration(
                border: Border(right: BorderSide(color: Color(0xFFDDE2EA))),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'RW',
                    style: TextStyle(
                      color: Color(0xFF111318),
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                  SizedBox(width: 6),
                  Icon(
                    Icons.keyboard_arrow_down,
                    color: Color(0xFF596070),
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
                  color: const Color(0xFF111318),
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
    return Semantics(
      textField: true,
      label: 'OTP code',
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.done,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: const Color(0xFF111318),
          fontWeight: FontWeight.w700,
        ),
        decoration: InputDecoration(
          hintText: '6-digit code',
          filled: true,
          fillColor: const Color(0xFFF5F7FA),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 18,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(CollectRadius.md),
            borderSide: const BorderSide(color: Color(0xFFDDE2EA)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(CollectRadius.md),
            borderSide: const BorderSide(color: Color(0xFFDDE2EA)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(CollectRadius.md),
            borderSide: const BorderSide(color: Color(0xFF111318), width: 2),
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
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: const Color(0xFF6A7280),
      height: 1.35,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.verified_user_outlined,
          size: 18,
          color: Color(0xFF4F7D5C),
        ),
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
    return Semantics(
      liveRegion: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFFFFECE8),
          borderRadius: BorderRadius.circular(CollectRadius.md),
          border: Border.all(color: const Color(0xFFFFC6BA)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.error_outline,
                color: Color(0xFFB3261E),
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF8F251C),
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
  const AdminDeniedPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AdminPage(
      title: 'Admin access required',
      subtitle:
          'Your Supabase session is active, but this profile does not have platform admin permissions.',
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
      subtitle:
          'Live operational queues from Supabase. No raw SMS or private phone numbers are shown here.',
      child: metrics.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Text(error.toString()),
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
            children: [for (final item in items) AdminMetricCard(metric: item)],
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
  final _search = TextEditingController();
  var _status = '';
  late Future<AdminListResult> _future;
  var _lastRealtimeTick = 0;

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdminFilterBar(
            searchController: _search,
            status: _status,
            onStatusChanged: (value) => setState(() {
              _status = value;
              _future = _load();
            }),
            onRefresh: _refresh,
          ),
          const SizedBox(height: 16),
          FutureBuilder<AdminListResult>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) return Text(snapshot.error.toString());
              final rows = snapshot.data?.rows ?? const [];
              if (rows.isEmpty) {
                return AdminEmptyState(
                  title: 'No ${widget.title.toLowerCase()}',
                  message: 'Try another filter or refresh this queue.',
                );
              }
              return AdminDataTable(
                rows: rows,
                onOpen: _openRow,
                trailingBuilder: widget.actionKind == null
                    ? null
                    : (row) => _AdminRowActions(
                        row: row,
                        actionKind: widget.actionKind!,
                        onDone: _refresh,
                      ),
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
        .list(widget.rpcName, search: _search.text, status: _status);
  }

  void _refresh() {
    setState(() {
      _future = _load();
    });
  }

  void _openRow(AdminTableRowData row) {
    final prefix = widget.detailPathPrefix;
    if (prefix == null) return;
    context.go('$prefix/${row.id}');
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
    return Wrap(
      spacing: 8,
      children: switch (actionKind) {
        'payment_event_reparse' => [
          TextButton(
            onPressed: () => _reparse(context, ref),
            child: const Text('Reparse'),
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
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) return Text(snapshot.error.toString());
          final data = snapshot.data ?? const {};
          if (data.isEmpty) {
            return const AdminEmptyState(title: 'Record not found');
          }
          return _AdminJsonPanel(data: data);
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
    return AdminPage(
      title: 'SMS metadata',
      subtitle:
          'Raw SMS body stays hidden unless an authorized admin enters a reason.',
      child: FutureBuilder<Map<String, dynamic>>(
        future: ref
            .read(adminRepositoryProvider)
            .detail('admin_get_sms_metadata', id),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) return Text(snapshot.error.toString());
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _AdminJsonPanel(data: snapshot.data ?? const {}),
              const SizedBox(height: 16),
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
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AdminJsonPanel extends StatelessWidget {
  const _AdminJsonPanel({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SelectableText(
          const JsonEncoder.withIndent('  ').convert(data),
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(fontFamily: 'monospace'),
        ),
      ),
    );
  }
}
