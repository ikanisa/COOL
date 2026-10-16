import 'dart:async';
import 'package:flutter/material.dart';
import '../../shared/widgets/collect_components.dart';
import '../shared/components/admin_empty_state.dart';
import '../shared/components/admin_loading_state.dart';
import '../shared/components/admin_page.dart';
import '../shared/components/admin_status_chip.dart';
import 'admin_privacy_review_controller.dart';
import 'admin_privacy_review_models.dart';

/// Business/operator pattern adaptation, using Collect's existing semantic
/// primitives and product typography. Inspected official bills-preview.png
/// supports quiet grouped review facts and contextual actions; a current
/// authenticated Business queue/detail comparator remains unverified.
class AdminPrivacyReviewView extends StatefulWidget {
  const AdminPrivacyReviewView({required this.controller, super.key});
  final AdminPrivacyReviewController controller;
  @override
  State<AdminPrivacyReviewView> createState() => _ViewState();
}

class _ViewState extends State<AdminPrivacyReviewView> {
  Timer? _clock;
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    _clock = Timer.periodic(const Duration(seconds: 1), (_) => _changed());
    unawaited(widget.controller.refresh());
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(AdminPrivacyReviewView old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
      unawaited(widget.controller.refresh());
    }
  }

  @override
  void dispose() {
    _clock?.cancel();
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  Widget _facts(String label, List<(String, String)> fields) => Semantics(
    container: true,
    label: label,
    child: Table(
      columnWidths: const {0: FlexColumnWidth(2), 1: FlexColumnWidth(3)},
      defaultVerticalAlignment: TableCellVerticalAlignment.top,
      border: TableBorder(
        horizontalInside: BorderSide(color: context.collectColors.border),
      ),
      children: [
        for (final field in fields)
          TableRow(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 10, 12, 10),
                child: Text(
                  field.$1,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: SelectableText(field.$2),
              ),
            ],
          ),
      ],
    ),
  );
  Widget _message(String message, {bool error = false}) => Semantics(
    liveRegion: true,
    child: Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: error
              ? context.collectColors.danger
              : context.collectColors.textPrimary,
        ),
      ),
    ),
  );
  String _date(DateTime value) => value
      .toUtc()
      .toIso8601String()
      .replaceFirst('T', ' ')
      .replaceFirst(RegExp(r'\.\d+Z$'), ' UTC');
  @override
  Widget build(BuildContext context) {
    final c = widget.controller,
        page = c.page,
        d = c.detail,
        item = d?.item,
        pending = c.pending;
    return AdminPage(
      title: 'Privacy requests',
      subtitle:
          'Review account-deletion requests and record the policy blocker.',
      trailing: CollectButton(
        label: 'Refresh reviews',
        icon: Icons.refresh,
        variant: CollectButtonVariant.secondary,
        onPressed: c.idle ? () => c.refresh() : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AdminStatusChip(
                  label: 'Waiting for approved policy',
                  tone: CollectStatusTone.warning,
                ),
                const SizedBox(height: 12),
                const Text(
                  'These requests need an approved retention and erasure policy before deletion can proceed. Starting a review or recording this blocker does not erase data, remove Auth access, or start processor deletion.',
                ),
                if (c.store == null) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'This platform does not provide the durable operation checkpoint required for actions. Current review evidence remains available.',
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (c.error != null) _message(c.error!, error: true),
          if (c.notice != null) _message(c.notice!),
          if (pending != null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const AdminStatusChip(
                    label: 'Original operation unresolved',
                    tone: CollectStatusTone.warning,
                  ),
                  _facts('Original operation evidence', [
                    ('Original operation identifier', pending.operationId),
                    ('Request identifier', pending.requestId),
                  ]),
                  const Text(
                    'Check this operation using its originating Admin session. A missing server observation does not prove the original action failed.',
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      CollectButton(
                        label: 'Check original operation',
                        variant: CollectButtonVariant.secondary,
                        onPressed: c.idle ? c.resolve : null,
                      ),
                      CollectButton(
                        label: 'Retry same operation',
                        variant: CollectButtonVariant.secondary,
                        onPressed: c.canRetry ? c.retryOriginal : null,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (c.loading)
            const AdminLoadingState(
              title: 'Loading privacy review evidence',
              message: 'Checking the current queue and selected request.',
            ),
          if (c.busy)
            const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: AdminLoadingState(
                title: 'Checking the original review operation',
                message:
                    'Keep this page open while the recorded response is verified.',
              ),
            ),
          if (page != null) ...[
            Semantics(
              header: true,
              child: Text(
                'Requests · page ${c.pageIndex + 1}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const SizedBox(height: 12),
            if (page.items.isEmpty)
              const AdminEmptyState(
                title: 'No privacy requests in this page',
                message:
                    'This is the current observed queue page. Refresh to check again.',
              ),
            if (page.items.isNotEmpty)
              Semantics(
                container: true,
                label: 'Privacy requests table, ${page.items.length} rows',
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    key: const Key('privacy-requests-table'),
                    headingRowColor: WidgetStatePropertyAll(
                      context.collectColors.surfaceRaised,
                    ),
                    dataRowMinHeight: 64,
                    dataRowMaxHeight: double.infinity,
                    columns: const [
                      DataColumn(label: Text('Request identifier')),
                      DataColumn(label: Text('State')),
                      DataColumn(label: Text('Accepted')),
                      DataColumn(label: Text('Open')),
                    ],
                    rows: [
                      for (final row in page.items)
                        DataRow(
                          cells: [
                            DataCell(Text(row.requestId, softWrap: false)),
                            DataCell(
                              AdminStatusChip(
                                label: row.state.label,
                                tone: CollectStatusTone.warning,
                              ),
                            ),
                            DataCell(
                              Text(_date(row.acceptedAt), softWrap: false),
                            ),
                            DataCell(
                              CollectButton(
                                label: 'Open request',
                                icon: Icons.arrow_forward,
                                variant: CollectButtonVariant.secondary,
                                key: ValueKey('privacy-open-${row.requestId}'),
                                onPressed: c.idle
                                    ? () => c.open(row.requestId)
                                    : null,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                CollectButton(
                  label: 'Previous requests',
                  variant: CollectButtonVariant.secondary,
                  onPressed: c.idle && c.hasPrevious ? c.previousPage : null,
                ),
                CollectButton(
                  label: 'Next requests',
                  variant: CollectButtonVariant.secondary,
                  onPressed: c.idle && c.hasNext ? c.nextPage : null,
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],
          if (d != null && item == null)
            const AdminEmptyState(
              title: 'Request not found',
              message:
                  'The server did not return a current request for this identifier.',
            ),
          if (d != null && item != null)
            Padding(
              key: const Key('privacy-selected-request'),
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      'Request review',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  const SizedBox(height: 12),
                  AdminStatusChip(
                    label: item.state.label,
                    tone: CollectStatusTone.warning,
                  ),
                  _facts('Selected request evidence', [
                    ('Request identifier', item.requestId),
                    ('Accepted', _date(item.acceptedAt)),
                    ('Observed revision', '${item.revision}'),
                    ('Evidence checked', _date(d.checkedAt)),
                    if (item.claimExpiresAt != null)
                      ('Review claim expires', _date(item.claimExpiresAt!)),
                    if (item.outcomeRecordedAt != null)
                      (
                        'Policy blocker recorded',
                        _date(item.outcomeRecordedAt!),
                      ),
                  ]),
                  if (!d.fresh(c.now()))
                    const Text(
                      'This evidence has expired. Refresh before taking an action.',
                    ),
                  if (item.state == AdminPrivacyReviewState.claimExpired ||
                      d.claimAuthorityCurrent && !d.canRecord(c.now()))
                    const Text(
                      'The review claim has expired. Historical claim evidence cannot record an outcome.',
                    ),
                  if (item.state == AdminPrivacyReviewState.claimActive &&
                      !d.claimAuthorityCurrent)
                    const Text(
                      'A review is already in progress. This Admin session does not own the current claim. Refresh after it expires.',
                    ),
                  if (item.state == AdminPrivacyReviewState.blocked)
                    const Text(
                      'The policy blocker is recorded. This request is waiting for approved policy; deletion has not been completed.',
                    ),
                  if (d.canRecord(c.now()))
                    const Text(
                      'Your current Admin session owns this unexpired review claim. The supported outcome is to record that approved policy is unavailable.',
                    ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      CollectButton(
                        label: 'Start review',
                        onPressed: c.canStart ? c.startReview : null,
                      ),
                      CollectButton(
                        label: 'Record policy blocker',
                        onPressed: c.canRecord ? c.recordPolicyBlocker : null,
                      ),
                    ],
                  ),
                  if (!c.checkpointReady && c.store != null) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'Actions are unavailable until the original-operation checkpoint can be verified. Refresh after browser storage recovers.',
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}
