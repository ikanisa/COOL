import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
    await _requireClient().auth.signInWithOtp(
      phone: PhoneNormalizer.normalizeInternational(phone),
      channel: OtpChannel.whatsapp,
    );
  }

  Future<AdminIdentity?> verifyOtp({
    required String phone,
    required String otp,
  }) async {
    await _requireClient().auth.verifyOTP(
      phone: PhoneNormalizer.normalizeInternational(phone),
      token: otp.trim(),
      type: OtpType.sms,
    );
    return currentIdentity();
  }

  Future<void> signOut() async => _supabase?.auth.signOut();

  Future<AdminIdentity?> currentIdentity() async {
    final client = _supabase;
    if (client?.auth.currentUser == null) return null;
    final row = await client!.rpc<dynamic>('admin_current_user');
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
}

class AdminLoginPage extends ConsumerStatefulWidget {
  const AdminLoginPage({super.key});

  @override
  ConsumerState<AdminLoginPage> createState() => _AdminLoginPageState();
}

class _AdminLoginPageState extends ConsumerState<AdminLoginPage> {
  final _phone = TextEditingController(text: '+');
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
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final cardWidth = math.max(
              0.0,
              math.min(320.0, constraints.maxWidth - 32),
            );
            final isCompact = constraints.maxWidth < 600;
            return Align(
              alignment: isCompact ? Alignment.centerLeft : Alignment.center,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: cardWidth,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Collect admin login',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Sign in with the WhatsApp number attached to your admin profile.',
                          ),
                          const SizedBox(height: 18),
                          TextField(
                            controller: _phone,
                            keyboardType: TextInputType.phone,
                            decoration: const InputDecoration(
                              labelText: 'WhatsApp phone',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          if (_otpSent) ...[
                            const SizedBox(height: 12),
                            TextField(
                              controller: _otp,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'OTP code',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ],
                          if (_error != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              _error!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ],
                          const SizedBox(height: 18),
                          FilledButton.icon(
                            onPressed: _isBusy ? null : _submit,
                            icon: Icon(
                              _otpSent ? Icons.verified_user : Icons.sms,
                            ),
                            label: Text(
                              _otpSent ? 'Verify code' : 'Send WhatsApp OTP',
                            ),
                          ),
                        ],
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
        ref.invalidate(adminIdentityProvider);
        if (!mounted) return;
        if (identity == null) {
          setState(() => _error = 'This account is not authorized for admin.');
        } else {
          context.go('/admin');
        }
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
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
