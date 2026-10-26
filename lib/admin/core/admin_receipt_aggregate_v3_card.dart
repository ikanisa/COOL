import '../shared/components/admin_data_listing.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'admin_auth_guard.dart';
import 'admin_receipt_aggregate_v3_models.dart';
import 'admin_receipt_aggregate_v3_sdk.dart';
import 'admin_receipt_operational_telemetry.dart';
import 'admin_receipt_callback_deadline_models.dart';
import 'admin_receipt_cancel_models.dart';
import 'admin_runtime.dart';
import 'admin_receipt_aggregate_v2_card.dart' show AdminReceiptAggregateV2Card;

final adminReceiptAggregateV3ApiProvider =
    Provider.autoDispose<AdminReceiptAggregateV3Api?>((ref) {
      final scope = ref.watch(adminAuthSessionScopeProvider);
      final repository = ref.watch(adminRepositoryProvider);
      final state = ref.watch(adminIdentityProvider);
      final identity = state.isLoading || state.hasError
          ? null
          : state.asData?.value;
      if (scope == null ||
          identity == null ||
          identity.userId != scope.key.userId ||
          !identity.roles.contains('platform_owner') ||
          !{
            'payments.read',
            'notifications.read',
            'system_health.read',
          }.every(identity.permissions.contains) ||
          repository is! AdminRepository) {
        return null;
      }
      var current = true;
      ref.onDispose(() => current = false);
      ref.listen(adminIdentityProvider, (_, _) => current = false);
      ref.listen(adminAuthSessionScopeProvider, (_, _) => current = false);
      return AdminReceiptAggregateV3Api(
        rpc: (name, params) =>
            repository.rpcMap(name, params: params, automaticRetry: false),
        isCurrent: () =>
            current &&
            ref.read(adminAuthSessionScopeProvider) == scope &&
            identical(ref.read(adminRepositoryProvider), repository),
      );
    });

final adminReceiptAggregateV3SampleProvider = FutureProvider.autoDispose
    .family<AdminReceiptAggregateSampleV3, String>((ref, requestId) async {
      final api = ref.watch(adminReceiptAggregateV3ApiProvider);
      if (api == null) throw const AdminSessionChanged();
      return api.sample(requestId);
    });

/// Uses the original request from a validated worker receipt. A read never
/// starts work, advances a sample clock or upgrades retained legacy evidence.
class AdminReceiptAggregateV3Card extends ConsumerWidget {
  const AdminReceiptAggregateV3Card({
    required this.source,
    this.compact = false,
    super.key,
  });
  final CallbackDeadlinePage? source;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.watch(adminReceiptAggregateV3ApiProvider);
    final now = ref.watch(adminClockProvider)();
    final page = source;
    final worker = page?.row['last_worker'] as Map?;
    final id = worker?['request_id'] as String?;
    final result = api == null || id == null || page?.fresh(now) != true
        ? null
        : ref.watch(adminReceiptAggregateV3SampleProvider(id));
    final sample = result?.isLoading == false ? result?.asData?.value : null;
    final measurement = sample?.measurement;
    final bindingMatches =
        sample?.available != true ||
        sample!.configurationRevision == worker?['configuration_revision'] &&
            sample.telemetryRevision == worker?['telemetry_revision'] &&
            sample.policyRevision == worker?['policy_revision'] &&
            sample.expiresAt == cancelInstant(worker?['expires_at']);
    final fresh = sample?.current(now) == true;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              'Latest recorded receipt measurement for all three send protocols',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const SizedBox(height: 8),
          if (api == null)
            const Text('Current receipt measurement access is required.')
          else if (id == null)
            const Text('No worker receipt is available for this measurement.')
          else if (page?.fresh(now) != true)
            const Text(
              'The worker read has expired. Refresh the worker evidence before viewing measurements.',
            )
          else if (result!.isLoading)
            Semantics(
              liveRegion: true,
              child: const Text('Loading the recorded receipt measurement…'),
            )
          else if (result.hasError || !bindingMatches)
            const Text(
              'The recorded measurement could not be verified. Refresh and check current access.',
            )
          else if (sample?.available != true) ...[
            const Text(
              'This original worker has no recorded measurement for all three send protocols. The retained original and successor measurement is shown below with its own scope.',
            ),
            AdminReceiptAggregateV2Card(source: source, compact: compact),
          ] else if (!fresh)
            Text(
              'This measurement has expired. Its original sample was recorded ${_sampleTime(sample!.recordedAt!)}. Refresh reads the same retained sample.',
            )
          else if (measurement?.admitted != true)
            Text(_aggregateUnavailable(measurement!.reasonCode))
          else ...[
            Text(
              'Original, successor and receipt-notice Android attempts · ${measurement!.metrics.configuredCollectionCount} configured ${measurement.metrics.configuredCollectionCount == 1 ? 'collection' : 'collections'}',
            ),
            Text(
              'Recorded mode ${measurement.metrics.mode} · Policy revision ${measurement.metrics.policyRevision}',
            ),
            if (measurement.metrics.emergencyStop)
              const Text('Emergency stop was active in this sample.'),
            Text('Sampled ${_sampleTime(measurement.metrics.checkedAt)}'),
            const SizedBox(height: 12),
            if (compact)
              _AggregateMetrics(
                dashboard: true,
                values: {
                  'unhandled_events':
                      measurement.metrics.backlog!['unhandled_events'],
                  'oldest_unhandled_age_seconds': measurement
                      .metrics
                      .backlog!['oldest_unhandled_age_seconds'],
                  'latency_p95_ms':
                      measurement.metrics.handling!['latency_p95_ms'],
                  'uncertain_attempts':
                      measurement.metrics.unknown!['uncertain_attempts'],
                },
              )
            else ...[
              _AggregateGroup(
                title: 'Backlog',
                values: measurement.metrics.backlog!,
              ),
              _AggregateGroup(
                title: 'Durable event handling',
                values: measurement.metrics.handling!,
              ),
              _AggregateGroup(
                title: 'Global UTC-day budget limits',
                values: {
                  for (final key in [
                    'actions_reserved',
                    'actions_cap',
                    'sms_segments_reserved',
                    'sms_segments_cap',
                  ])
                    key: measurement.metrics.budgets![key] as int,
                },
              ),
              _AggregateGroup(
                title: 'Authenticated callback observations',
                values: measurement.metrics.callbacks!,
              ),
              _AggregateGroup(
                title: 'Unknown outcomes and callback gaps',
                values: measurement.metrics.unknown!,
              ),
            ],
            const SizedBox(height: 8),
            const Text(
              'Receipt notices include historical copies and ledger-compensation notices. They do not count as additional payments. Unknown-outcome categories can overlap. Callback coverage does not confirm carrier delivery. Limits do not measure capacity. Costs remain unmeasured.',
            ),
          ],
          if (api != null && id != null && result != null) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: result.isLoading
                    ? null
                    : () => ref.invalidate(
                        adminReceiptAggregateV3SampleProvider(id),
                      ),
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh recorded measurement'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String _sampleTime(DateTime time) =>
    '${DateFormat('d MMM yyyy, HH:mm:ss').format(time.toUtc())} UTC';

String _aggregateUnavailable(String? reason) => switch (reason) {
  'telemetry_disabled' ||
  'admission_disabled' => 'Measurement is inactive for this worker receipt.',
  'no_configured_scope' =>
    'No collections were configured for this measurement.',
  'projection_seed_incomplete' || 'projection_dirty' =>
    'Measurement is unavailable while source observations are incomplete.',
  'measurement_timeout' => 'The original measurement timed out.',
  'collection_ceiling' ||
  'pending_ceiling' ||
  'created_ceiling' ||
  'handled_ceiling' ||
  'reservation_ceiling' ||
  'primary_recent_ceiling' ||
  'successor_recent_ceiling' ||
  'primary_unresolved_ceiling' ||
  'successor_unresolved_ceiling' ||
  'notice_recent_ceiling' ||
  'notice_unresolved_ceiling' =>
    'Measurement is unavailable because its complete source window exceeds a processing limit.',
  _ => 'The original measurement source was unavailable.',
};

class _AggregateGroup extends StatelessWidget {
  const _AggregateGroup({required this.title, required this.values});
  final String title;
  final Map<String, int?> values;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(title, style: Theme.of(context).textTheme.titleSmall),
        ),
        const SizedBox(height: 8),
        _AggregateMetrics(values: values),
      ],
    ),
  );
}

class _AggregateMetrics extends StatelessWidget {
  const _AggregateMetrics({required this.values, this.dashboard = false});
  final Map<String, int?> values;
  final bool dashboard;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (!dashboard) {
        return Column(
          children: [
            for (final metric in values.entries)
              AdminDataFieldRow(
                label:
                    AdminReceiptOperationalTelemetry.metricLabels[metric.key]!,
                value: metric.value == null
                    ? metric.key == 'oldest_unhandled_age_seconds'
                          ? 'No unhandled events'
                          : 'No handled events'
                    : '${metric.value}${metric.key.endsWith('_seconds')
                          ? ' seconds'
                          : metric.key.endsWith('_ms')
                          ? ' ms'
                          : ''}',
              ),
          ],
        );
      }
      final columns = constraints.maxWidth >= 900
          ? 4
          : constraints.maxWidth >= 500
          ? 2
          : 1;
      final width = (constraints.maxWidth - 16 * (columns - 1)) / columns;
      return Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          for (final metric in values.entries)
            SizedBox(
              width: width,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AdminReceiptOperationalTelemetry.metricLabels[metric.key]!,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    metric.value == null
                        ? metric.key == 'oldest_unhandled_age_seconds'
                              ? 'No unhandled events'
                              : 'No handled events'
                        : '${metric.value}${metric.key.endsWith('_seconds')
                              ? ' seconds'
                              : metric.key.endsWith('_ms')
                              ? ' ms'
                              : ''}',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ],
              ),
            ),
        ],
      );
    },
  );
}
