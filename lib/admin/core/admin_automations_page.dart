import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/widgets/collect_components.dart';
import '../shared/components/admin_page.dart';
import '../shared/components/admin_status_chip.dart';
import 'admin_auth_guard.dart';
import 'admin_display_formatters.dart';
import 'admin_error_boundary.dart';
import 'admin_operational_health.dart';
import 'admin_repository_base.dart';
import 'admin_shadow_runs.dart';
import 'admin_sms_queue_health.dart';

final adminSmsQueueHealthProvider =
    FutureProvider.autoDispose<AdminSmsQueueHealth>((ref) async {
      ref.watch(adminAuthSessionScopeProvider);
      ref.watch(adminRealtimeTickProvider);
      final repository = ref.watch(adminRepositoryProvider);
      var current = true;
      ref.onDispose(() => current = false);
      final identity = await ref.watch(adminIdentityProvider.future);
      if (!current) throw const AdminSessionChanged();
      if (identity?.permissions.contains('notifications.read') != true) {
        throw StateError('SMS queue read permission required.');
      }
      return AdminSmsQueueHealth.parse(await repository.smsQueueHealth());
    });

final adminAutomationHealthProvider =
    FutureProvider.autoDispose<AdminOperationalHealth>((ref) async {
      ref.watch(adminAuthSessionScopeProvider);
      ref.watch(adminRealtimeTickProvider);
      final repository = ref.watch(adminRepositoryProvider);
      var current = true;
      ref.onDispose(() => current = false);
      final identity = await ref.watch(adminIdentityProvider.future);
      if (!current) throw const AdminSessionChanged();
      if (identity?.permissions.contains('system_health.read') != true) {
        throw StateError('System health read permission required.');
      }
      return AdminOperationalHealth.parse(
        await repository.detail('admin_system_health', 'system'),
      );
    });

abstract class _OperationsClockState<T extends ConsumerStatefulWidget>
    extends ConsumerState<T> {
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

/// Persistent gate evidence, shared by the shell and Automations view.
/// It never interprets a worker heartbeat as a successful Codex run.
class AdminSmsDispatchBanner extends ConsumerStatefulWidget {
  const AdminSmsDispatchBanner({super.key});

  @override
  ConsumerState<AdminSmsDispatchBanner> createState() =>
      _AdminSmsDispatchBannerState();
}

class _AdminSmsDispatchBannerState
    extends _OperationsClockState<AdminSmsDispatchBanner> {
  @override
  Widget build(BuildContext context) {
    final identity = ref.watch(adminIdentityProvider).valueOrNull;
    if (identity?.permissions.contains('notifications.read') != true) {
      return const SizedBox.shrink();
    }
    final sample = ref.watch(adminSmsQueueHealthProvider);
    final now = ref.watch(adminClockProvider)();
    final health = sample.asData?.value;
    final fresh = health?.isFresh(now) == true;
    final title = sample.isLoading
        ? 'Checking SMS dispatch gate'
        : !fresh
        ? 'SMS dispatch gate unverified'
        : health!.enabled
        ? 'SMS receipt gate enabled'
        : 'New SMS receipt dispatch disabled';
    final message = sample.isLoading
        ? 'Loading the current SMS receipt queue status.'
        : !fresh
        ? 'Refresh to check the current gate. Payment ingestion has a separate status.'
        : health!.enabled
        ? 'Sending requires current gateway authorization and recorded attempt evidence. This does not confirm sender availability or delivery.'
        : 'The global receipt gate is closed. This cannot recall a message already handed off for sending.';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Semantics(
        liveRegion: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InfoSecurityBanner(
              title: title,
              message: message,
              tone: fresh && health!.enabled
                  ? CollectStatusTone.info
                  : CollectStatusTone.warning,
            ),
            if (!sample.isLoading && !fresh)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => ref.invalidate(adminSmsQueueHealthProvider),
                  child: const Text('Refresh gate'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class AdminAutomationsPage extends ConsumerStatefulWidget {
  const AdminAutomationsPage({super.key});

  @override
  ConsumerState<AdminAutomationsPage> createState() =>
      _AdminAutomationsPageState();
}

class _AdminAutomationsPageState
    extends _OperationsClockState<AdminAutomationsPage> {
  int _historyRefresh = 0;
  @override
  Widget build(BuildContext context) {
    final identity = ref.watch(adminIdentityProvider).valueOrNull;
    if (identity?.permissions.contains('system_health.read') != true) {
      return const AdminDeniedPage(requiredPermission: 'system_health.read');
    }
    final sms = identity!.permissions.contains('notifications.read')
        ? ref.watch(adminSmsQueueHealthProvider)
        : null;
    final push = ref.watch(adminAutomationHealthProvider);
    final now = ref.watch(adminClockProvider)();
    void refresh() {
      ref.invalidate(adminAutomationHealthProvider);
      ref.invalidate(adminReceiptOperationsPolicyProvider);
      ref.invalidate(adminOperatingPolicyProvider);
      ref.invalidate(adminReceiptWorkerHealthProvider);
      ref.invalidate(adminReceiptOperationalTelemetryProvider);
      ref.invalidate(adminReceiptHistoryPageProvider);
      ref.invalidate(adminReceiptOperationalRunProvider);
      ref.invalidate(adminReceiptPrincipalsProvider);
      ref.invalidate(adminReceiptPrincipalProvider);
      if (sms != null) ref.invalidate(adminSmsQueueHealthProvider);
      ref.invalidate(adminShadowRunsProvider(const AdminShadowRunsQuery()));
      setState(() => _historyRefresh++);
    }

    return AdminPage(
      title: 'Automations',
      subtitle: 'Rwanda · Platform operations · Africa/Kigali',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: push.isLoading || sms?.isLoading == true
                  ? null
                  : refresh,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh status'),
            ),
          ),
          const SizedBox(height: 16),
          const _OperationsSection(
            title: 'Receipt operating controls',
            icon: Icons.policy_outlined,
            child: AdminReceiptOperationsCard(),
          ),
          const SizedBox(height: 16),
          const _OperationsSection(
            title: 'Receipt signing identities',
            icon: Icons.key_outlined,
            child: AdminReceiptPrincipalCard(),
          ),
          const SizedBox(height: 16),
          const _OperationsSection(
            title: 'Receipt operations measurements',
            icon: Icons.insights_outlined,
            child: AdminReceiptTelemetryCard(embedded: true),
          ),
          const SizedBox(height: 16),
          const _OperationsSection(
            title: 'Receipt operational run history',
            icon: Icons.history_outlined,
            child: AdminReceiptOperationalHistoryCard(),
          ),
          const SizedBox(height: 16),
          const _OperationsSection(
            title: 'Receipt exception worker',
            icon: Icons.fact_check_outlined,
            child: AdminReceiptWorkerCard(),
          ),
          const SizedBox(height: 16),
          const _OperationsSection(
            title: 'Legacy policy preferences',
            icon: Icons.history_outlined,
            child: AdminOperatingPolicyCard(),
          ),
          const SizedBox(height: 16),
          _OperationsSection(
            title: 'SMS receipts',
            icon: Icons.sms_outlined,
            child: sms == null
                ? const Text('Your role does not allow viewing SMS receipts.')
                : sms.when(
                    skipLoadingOnRefresh: false,
                    loading: () =>
                        const _SampleLoading(label: 'Loading SMS queue'),
                    error: (error, _) => AdminSafeErrorPanel(
                      error: error,
                      onRetry: () =>
                          ref.invalidate(adminSmsQueueHealthProvider),
                    ),
                    data: (health) {
                      final fresh = health.isFresh(now);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AdminStatusChip(
                            label: !fresh
                                ? 'Sample expired'
                                : health.enabled
                                ? 'Receipt gate enabled'
                                : 'Dispatch disabled',
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Checked ${adminKigaliDateTime(health.observedAt)}',
                          ),
                          const SizedBox(height: 12),
                          if (!fresh)
                            const Text(
                              'Refresh for current queue counts. Previous measurements are hidden.',
                            )
                          else ...[
                            Wrap(
                              spacing: 24,
                              runSpacing: 16,
                              children: [
                                for (final entry
                                    in AdminSmsQueueHealth.countLabels.entries)
                                  _OperationMetric(
                                    label: entry.value,
                                    value: '${health.counts[entry.key]}',
                                  ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              health.oldestQueuedAt == null
                                  ? 'No queued receipts in this sample.'
                                  : 'Oldest queued receipt: ${adminKigaliDateTime(health.oldestQueuedAt)}',
                            ),
                          ],
                          const SizedBox(height: 12),
                          const Text(
                            'Recent heartbeats show operator activity. They do not establish a successful Codex run, telephony availability or handset delivery.',
                          ),
                          const SizedBox(height: 12),
                          TextButton.icon(
                            onPressed: () => context.go('/admin/sms-receipts'),
                            icon: const Icon(Icons.arrow_forward),
                            label: const Text(
                              'Review SMS receipts and investigate unknown outcomes',
                            ),
                          ),
                        ],
                      );
                    },
                  ),
          ),
          const SizedBox(height: 16),
          _OperationsSection(
            title: 'Push notification scheduler',
            icon: Icons.notifications_outlined,
            child: push.when(
              skipLoadingOnRefresh: false,
              loading: () =>
                  const _SampleLoading(label: 'Loading notification scheduler'),
              error: (error, _) => AdminSafeErrorPanel(
                error: error,
                onRetry: () => ref.invalidate(adminAutomationHealthProvider),
              ),
              data: (health) {
                final fresh = health.isFresh(now);
                final age = health.metrics['push_scheduler_age_seconds'];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AdminStatusChip(
                      label: !fresh
                          ? 'Sample expired'
                          : 'Schedule ${health.schedulerState}',
                    ),
                    const SizedBox(height: 12),
                    const Text('Schedule owner: Collect backend'),
                    Text('Checked ${adminKigaliDateTime(health.checkedAt)}'),
                    const SizedBox(height: 12),
                    if (!fresh)
                      const Text(
                        'Refresh for current scheduler measurements. Previous values are hidden.',
                      )
                    else ...[
                      Wrap(
                        spacing: 24,
                        runSpacing: 16,
                        children: [
                          _OperationMetric(
                            label: 'Notifications due',
                            value:
                                health.metrics['push_due']?.toString() ??
                                'Unmeasured',
                          ),
                          _OperationMetric(
                            label: 'Failed attempts in 24 hours',
                            value:
                                health.metrics['push_failed_24h']?.toString() ??
                                'Unmeasured',
                          ),
                          _OperationMetric(
                            label: 'Last successful schedule run',
                            value: age == null
                                ? 'Unmeasured'
                                : adminKigaliDateTime(
                                    health.checkedAt.subtract(
                                      Duration(seconds: age),
                                    ),
                                  ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                    const Text(
                      'Provider configuration is unverified. Provider acceptance does not establish delivery. This scheduler serves app notifications; SMS receipts have a separate governed gateway workflow.',
                    ),
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: () => context.go('/admin/system-health'),
                      icon: const Icon(Icons.arrow_forward),
                      label: const Text(
                        'Open receipt, payment and notification health',
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          _OperationsSection(
            title: 'Manual shadow monitoring',
            icon: Icons.manage_search_outlined,
            child: AdminShadowRunsView(
              key: ValueKey((
                ref.watch(adminAuthSessionScopeProvider),
                _historyRefresh,
              )),
              now: now,
            ),
          ),
        ],
      ),
    );
  }
}

class _OperationsSection extends StatelessWidget {
  const _OperationsSection({
    required this.title,
    required this.icon,
    required this.child,
  });
  final String title;
  final IconData icon;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceReadable,
        borderRadius: CollectRadius.cardBorder,
        border: Border.all(color: colors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, color: colors.textSecondary),
                const SizedBox(width: 10),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

class _OperationMetric extends StatelessWidget {
  const _OperationMetric({required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 210,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 4),
        Text(value, style: Theme.of(context).textTheme.titleLarge),
      ],
    ),
  );
}

class _SampleLoading extends StatelessWidget {
  const _SampleLoading({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Row(
      children: [
        const SizedBox.square(
          dimension: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(label)),
      ],
    ),
  );
}
