import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/exact_json_values.dart';
import '../shared/components/admin_loading_state.dart';
import 'admin_account_api.dart';
import 'admin_display_formatters.dart';
import 'admin_error_boundary.dart';
import 'cloudflare_admin_session.dart';

/// A bounded view of persisted assisted-SMS records, not delivery or uptime.
class CloudflareSmsOversight {
  const CloudflareSmsOversight._(this.checkedAt, this.counts);

  final DateTime checkedAt;
  final Map<String, int> counts;

  bool isFresh(DateTime now) =>
      !now.toUtc().isBefore(checkedAt.subtract(const Duration(seconds: 5))) &&
      now.toUtc().isBefore(checkedAt.add(const Duration(seconds: 60)));

  static const labels = <String, String>{
    'queued': 'Queued receipts',
    'claimed': 'Claimed receipts',
    'send_started': 'Send started',
    'uncertain': 'Send outcome unknown',
  };

  factory CloudflareSmsOversight.parse(Map<String, dynamic> value) {
    Never invalid() => throw const FormatException(
      'The SMS oversight sample could not be verified.',
    );
    if (value['contract_version'] is! int ||
        value['contract_version'] != 1 ||
        value['scope'] != 'admin_operational_health' ||
        value['metrics_scope'] != 'all_retained_rows' ||
        value['worker_heartbeat'] != 'not_recorded' ||
        value['external_services_checked'] != false) {
      invalid();
    }
    final rawTime = value['checked_at'];
    if (rawTime is! String ||
        !RegExp(
          r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?Z$',
        ).hasMatch(rawTime)) {
      invalid();
    }
    final checkedAt = exactJsonTimestamp(
      rawTime,
      field: 'SMS oversight timestamp',
    );
    final queues = value['queues'];
    if (queues is! Map || queues['assisted_sms'] is! Map) invalid();
    final sms = queues['assisted_sms'] as Map;
    if (sms['automatic_retry'] != false) invalid();
    final counts = <String, int>{};
    for (final key in labels.keys) {
      final count = sms[key];
      if (count is! int || count < 0 || count > 9007199254740991) invalid();
      counts[key] = count;
    }
    return CloudflareSmsOversight._(
      checkedAt.toUtc(),
      Map.unmodifiable(counts),
    );
  }
}

/// The BFF checks the account, linked principal and permission in its read
/// transaction. This local fence also rejects a superseded response.
Future<CloudflareSmsOversight> readCloudflareSmsOversight(
  CloudflareAdminSession session,
) async {
  final before = session.user;
  final fence = session.authorityFence;
  if (before == null ||
      !before.expiresAt.isAfter(DateTime.now()) ||
      !before.permissions.contains('system_health.read')) {
    throw const AdminAccountException(
      'SMS oversight is unavailable to this account.',
    );
  }
  final response = await session.request(
    'oversight/health',
    authenticated: true,
    expectedStatus: 200,
    responseCurrent: () => session.authorityFence == fence,
  );
  final after = session.user;
  if (session.authorityFence != fence ||
      after == null ||
      !after.expiresAt.isAfter(DateTime.now()) ||
      !after.permissions.contains('system_health.read')) {
    throw const AdminAccountException('Your sign-in changed. Try again.');
  }
  return CloudflareSmsOversight.parse(response);
}

final cloudflareSmsOversightProvider =
    FutureProvider.autoDispose<CloudflareSmsOversight>((ref) async {
      ref.watch(cloudflareAdminSessionProvider);
      return readCloudflareSmsOversight(
        ref.read(cloudflareAdminSessionProvider.notifier),
      );
    });

/// Current account workspace; no heartbeat or provider availability is inferred.
class CloudflareSmsOversightPanel extends ConsumerStatefulWidget {
  const CloudflareSmsOversightPanel({super.key});

  @override
  ConsumerState<CloudflareSmsOversightPanel> createState() =>
      _CloudflareSmsOversightPanelState();
}

class _CloudflareSmsOversightPanelState
    extends ConsumerState<CloudflareSmsOversightPanel> {
  Timer? _freshnessTimer;

  @override
  void initState() {
    super.initState();
    _freshnessTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _freshnessTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(cloudflareAdminSessionProvider).asData?.value;
    if (user == null || !user.permissions.contains('system_health.read')) {
      return const SizedBox.shrink();
    }
    final sample = ref.watch(cloudflareSmsOversightProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Assisted SMS receipts',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            IconButton(
              tooltip: 'Refresh SMS oversight',
              onPressed: () => ref.invalidate(cloudflareSmsOversightProvider),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        sample.when(
          skipLoadingOnRefresh: false,
          skipLoadingOnReload: false,
          loading: () =>
              const AdminLoadingState(title: 'Loading SMS oversight'),
          error: (error, _) => AdminSafeErrorPanel(
            error: error,
            onRetry: () => ref.invalidate(cloudflareSmsOversightProvider),
          ),
          data: (value) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Checked ${adminKigaliDateTime(value.checkedAt)}'),
              if (!value.isFresh(DateTime.now()))
                const Text('Sample expired. Refresh for current counts.')
              else
                for (final entry in CloudflareSmsOversight.labels.entries)
                  Text('${entry.value}: ${value.counts[entry.key]}'),
              const Text(
                'Operator heartbeat and receipt gate status are not recorded.',
              ),
              const Text(
                'These records do not confirm provider availability or handset delivery.',
              ),
            ],
          ),
        ),
      ],
    );
  }
}
