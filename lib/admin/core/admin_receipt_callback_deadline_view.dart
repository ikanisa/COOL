import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'admin_runtime.dart';
import 'admin_entity_audit.dart';
import 'admin_receipt_callback_deadline_models.dart';
import 'admin_receipt_callback_deadline_runtime.dart';

/// Collect operator adaptation of the selected Revolut grouped detail pattern.
/// Every navigation target comes from one validated immutable source binding.
class AdminReceiptCallbackDeadlineCard extends ConsumerWidget {
  const AdminReceiptCallbackDeadlineCard({this.onFollowUp, super.key});
  final Future<void> Function(String)? onFollowUp;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.watch(adminCallbackDeadlineApiProvider);
    if (api == null) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('Current receipt investigation access is required.'),
      );
    }
    return _DeadlineView(
      key: ValueKey(api),
      api: api,
      now: ref.watch(adminClockProvider),
      onFollowUp: onFollowUp,
    );
  }
}

class _DeadlineView extends StatefulWidget {
  const _DeadlineView({
    required this.api,
    required this.now,
    this.onFollowUp,
    super.key,
  });
  final CallbackDeadlineApi api;
  final DateTime Function() now;
  final Future<void> Function(String)? onFollowUp;
  @override
  State<_DeadlineView> createState() => _DeadlineViewState();
}

class _DeadlineViewState extends State<_DeadlineView> {
  late CallbackDeadlineController controller;
  Timer? timer;
  String family = 'primary_v2';
  @override
  void initState() {
    super.initState();
    controller = CallbackDeadlineController(widget.api)..addListener(_changed);
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    controller.load(CallbackDeadlineQuery());
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    timer?.cancel();
    controller.removeListener(_changed);
    controller.dispose();
    super.dispose();
  }

  void _refresh() => controller.load(CallbackDeadlineQuery(family: family));
  @override
  Widget build(BuildContext context) {
    final page = controller.page, fresh = page?.fresh(widget.now()) == true;
    final detail = controller.detail,
        detailFresh = detail?.fresh(widget.now()) == true;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              'Callback deadlines',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Missing callback observations need investigation. Callback coverage does not prove carrier delivery or permit sending again.',
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Original attempts'),
                selected: family == 'primary_v2',
                onSelected: controller.busy
                    ? null
                    : (_) {
                        setState(() => family = 'primary_v2');
                        _refresh();
                      },
              ),
              ChoiceChip(
                label: const Text('Successor attempts'),
                selected: family == 'receipt_successor',
                onSelected: controller.busy
                    ? null
                    : (_) {
                        setState(() => family = 'receipt_successor');
                        _refresh();
                      },
              ),
              OutlinedButton.icon(
                onPressed: controller.busy ? null : _refresh,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh'),
              ),
            ],
          ),
          if (controller.busy)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: LinearProgressIndicator(),
            ),
          if (controller.error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                controller.error is CallbackDeadlineDenied
                    ? 'Current investigation access is required.'
                    : 'Evidence could not be refreshed. Try again.',
              ),
            ),
          if (page != null) ...[
            const SizedBox(height: 12),
            Text(
              page.enabled
                  ? 'Callback publication is enabled for the configured worker.'
                  : 'Callback publication is inactive. Retained cases remain available.',
            ),
            Text(
              page.row['last_worker'] == null
                  ? 'No deadline worker receipt is available.'
                  : 'Latest worker evidence is retained separately from deferral completion.',
            ),
            const Text(
              'Automatic aggregate measurement is unavailable. Retained cases provide separate source observations.',
            ),
            if (!fresh)
              const Text(
                'This read has expired. Refresh before opening evidence or actions.',
              ),
            if (controller.rows.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'No retained cases in this page. This does not establish a completed callback sweep.',
                ),
              ),
            for (final item in controller.rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.rule == 'SEND_OUTCOME_UNKNOWN'
                                ? 'Send outcome investigation'
                                : 'Delivery callback gap',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        Text(item.active ? 'Needs review' : 'Not active'),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text('Attempt ${item.row['attempt_id']}'),
                    Text('Due ${item.row['due_at']}'),
                    Text(
                      'Source observed ${item.row['observed_at']}${item.pending ? ' · Refresh is pending' : ''}',
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        TextButton(
                          onPressed: fresh && !controller.busy
                              ? () => controller.inspect(item.id)
                              : null,
                          child: const Text('View observations'),
                        ),
                        TextButton(
                          onPressed: fresh && !controller.busy
                              ? () => context.push(item.receiptPath)
                              : null,
                          child: Text(
                            item.approval == null
                                ? 'Open original receipt'
                                : 'Open selected approval',
                          ),
                        ),
                        if (item.exception != null && widget.onFollowUp != null)
                          TextButton(
                            onPressed: fresh && !controller.busy
                                ? () => widget.onFollowUp!(item.exception!)
                                : null,
                            child: const Text('Investigate exception'),
                          ),
                        if (item.exception != null)
                          AdminEntityAuditLink(
                            kind: AdminAuditEntityKind.exception,
                            id: item.exception!,
                            enabled: fresh && !controller.busy,
                          ),
                      ],
                    ),
                    const Divider(),
                  ],
                ),
              ),
            if (page.next != null)
              OutlinedButton(
                onPressed: fresh && !controller.busy ? controller.more : null,
                child: const Text('Load more cases'),
              ),
          ],
          if (detail != null) ...[
            const SizedBox(height: 16),
            Semantics(
              header: true,
              child: Text(
                'Retained source observations',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Text('Case ${detail.head!.id} · History cutoff ${detail.cutoff}'),
            for (final raw in controller.observations)
              Builder(
                builder: (_) {
                  final o = raw as Map;
                  final s = o['source'] as Map;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'Revision ${o['revision']} · ${o['active'] == true ? 'Needs review' : 'Source cleared'}\n${s['sent_covered']}/${s['expected_segments']} sent and ${s['delivery_covered']}/${s['expected_segments']} delivery slots covered\nObserved ${o['observed_at']}',
                    ),
                  );
                },
              ),
            if (detail.next != null)
              OutlinedButton(
                onPressed: detailFresh && !controller.busy
                    ? () => controller.inspect(detail.head!.id, more: true)
                    : null,
                child: const Text('Load more source revisions'),
              ),
          ],
        ],
      ),
    );
  }
}
