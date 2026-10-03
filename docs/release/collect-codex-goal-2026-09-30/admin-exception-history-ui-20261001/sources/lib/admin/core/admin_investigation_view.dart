import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/theme/collect_colors.dart';
import '../../app/theme/collect_radius.dart';
import '../shared/components/admin_status_chip.dart';
import 'admin_auth_guard.dart';
import 'admin_display_formatters.dart';
import 'admin_investigation.dart';
import 'admin_entity_audit.dart';
import 'admin_runtime.dart';
import 'admin_transaction_lifecycle.dart';

typedef AdminInvestigationTarget = ({String kind, String id});

class AdminInvestigationDenied implements Exception {
  const AdminInvestigationDenied();
}

final adminInvestigationProvider = FutureProvider.autoDispose
    .family<AdminInvestigationSnapshot, AdminInvestigationTarget>((
      ref,
      target,
    ) async {
      final scope = ref.watch(adminAuthSessionScopeProvider);
      final repository = ref.watch(adminRepositoryProvider);
      var current = true;
      ref.onDispose(() => current = false);
      final identity = await ref.watch(adminIdentityProvider.future);
      if (!current) throw const AdminSessionChanged();
      final permission = target.kind == 'transaction'
          ? 'payments.read'
          : 'notifications.read';
      if (identity?.permissions.contains(permission) != true) {
        throw const AdminInvestigationDenied();
      }
      Map<String, dynamic> raw;
      try {
        raw = await repository.investigation(kind: target.kind, id: target.id);
      } on PostgrestException catch (error) {
        if (!current) throw const AdminSessionChanged();
        if (error.code == '42501') throw const AdminInvestigationDenied();
        if (error.code == 'PGRST202' || error.code == '42883') {
          throw UnsupportedError(
            'Joined investigation service is unavailable.',
          );
        }
        rethrow;
      }
      if (!current ||
          ref.read(adminAuthSessionScopeProvider) != scope ||
          !identical(ref.read(adminRepositoryProvider), repository)) {
        throw const AdminSessionChanged();
      }
      final snapshot = AdminInvestigationSnapshot.parse(raw);
      if (snapshot.kind != target.kind || snapshot.targetId != target.id) {
        throw const FormatException('Investigation target did not match.');
      }
      return snapshot;
    });

/// Separate from the existing privileged raw-message reveal. Refresh reads
/// evidence. A separate governed cancellation card can stop only unstarted
/// receipt transport; the investigation evidence itself remains read-only.
class AdminInvestigationView extends ConsumerStatefulWidget {
  const AdminInvestigationView({
    required this.kind,
    required this.id,
    super.key,
  });
  final String kind, id;
  @override
  ConsumerState<AdminInvestigationView> createState() =>
      _AdminInvestigationViewState();
}

class _AdminInvestigationViewState
    extends ConsumerState<AdminInvestigationView> {
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

  @override
  Widget build(BuildContext context) {
    final target = (kind: widget.kind, id: widget.id);
    final identity = ref.watch(adminIdentityProvider);
    final permission = widget.kind == 'transaction'
        ? 'payments.read'
        : 'notifications.read';
    if (identity.isLoading) {
      return const _InvestigationMessage(
        'Loading investigation',
        'Checking the current Admin session.',
      );
    }
    if (identity.hasError ||
        identity.valueOrNull?.permissions.contains(permission) != true) {
      return const _InvestigationMessage(
        'Investigation access denied',
        'Current read permission and backend platform-owner authority are required.',
      );
    }
    final read = ref.watch(adminInvestigationProvider(target));
    return _InvestigationPanel(
      title: 'Payment and receipt investigation',
      children: [
        const Text('Read-only evidence · Times in Africa/Kigali'),
        const SizedBox(height: 12),
        read.when(
          skipLoadingOnRefresh: false,
          loading: () => const _InvestigationMessage(
            'Loading investigation',
            'Reading linked payment, posting and operator records.',
          ),
          error: (error, _) => _InvestigationMessage(
            error is AdminInvestigationDenied
                ? 'Investigation access denied'
                : error is UnsupportedError
                ? 'Investigation unavailable'
                : error is AdminSessionChanged
                ? 'Admin session changed'
                : 'Investigation read failed',
            error is AdminInvestigationDenied
                ? 'The backend did not authorize this read.'
                : error is UnsupportedError
                ? 'The joined investigation service is not configured on this backend.'
                : error is AdminSessionChanged
                ? 'Reopen the detail with your current Admin session.'
                : 'Linked evidence could not be read or validated. Existing record metadata remains separate.',
          ),
          data: (snapshot) => !snapshot.isFresh(ref.watch(adminClockProvider)())
              ? const _InvestigationMessage(
                  'Investigation stale',
                  'Refresh to read current receipt state and balances. Older measurements are hidden.',
                )
              : _InvestigationEvidence(
                  snapshot: snapshot,
                  permissions: identity.valueOrNull!.permissions.toSet(),
                ),
        ),
        if (widget.kind == 'receipt' ||
            (read.asData?.value.isFresh(ref.watch(adminClockProvider)()) ==
                    true &&
                read.asData?.value.receipt != null)) ...[
          const SizedBox(height: 20),
          AdminReceiptCancelCard(
            outboxId: widget.kind == 'receipt'
                ? widget.id
                : read.asData!.value.receipt!.id,
            onRecorded: () =>
                ref.invalidate(adminInvestigationProvider(target)),
          ),
        ],
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: read.isLoading
                ? null
                : () => ref.invalidate(adminInvestigationProvider(target)),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Refresh investigation'),
          ),
        ),
      ],
    );
  }
}

class _InvestigationEvidence extends StatelessWidget {
  const _InvestigationEvidence({
    required this.snapshot,
    required this.permissions,
  });
  final AdminInvestigationSnapshot snapshot;
  final Set<String> permissions;

  @override
  Widget build(BuildContext context) {
    final payment = snapshot.payment, receipt = snapshot.receipt;
    final lifecycle = payment?.lifecycle;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          snapshot.scope == 'rwanda_momo'
              ? 'Scope: Rwanda MoMo'
              : 'Scope: unclassified',
        ),
        if (snapshot.scope == 'unclassified') ...[
          const SizedBox(height: 8),
          const Text(
            'Supported Rwanda receiving-wallet scope could not be established. No Rwanda financial or receipt evidence is inferred.',
          ),
        ],
        Text('Checked ${_evidenceTime(snapshot.checkedAt)}'),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            if (payment?.rawSmsId != null &&
                permissions.contains('payments.read'))
              _InvestigationLink(
                'Open transaction',
                '/admin/transactions/momo:${payment!.rawSmsId}',
              ),
            if (receipt != null && permissions.contains('notifications.read'))
              _InvestigationLink(
                'Open SMS receipt',
                '/admin/sms-receipts/${receipt.id}',
              ),
            if (receipt != null)
              AdminEntityAuditLink(
                kind: AdminAuditEntityKind.receipt,
                id: receipt.id,
              ),
            if ((payment?.collectionId ?? receipt?.collectionId) != null &&
                permissions.contains('collections.read'))
              _InvestigationLink(
                'Open group',
                '/admin/groups/${payment?.collectionId ?? receipt!.collectionId}',
              ),
            if ((payment?.memberId ?? receipt?.memberId) != null &&
                permissions.contains('members.read'))
              _InvestigationLink(
                'Open member',
                '/admin/members/${payment?.memberId ?? receipt!.memberId}',
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (payment == null)
          _InvestigationMessage(
            snapshot.paymentState == 'denied'
                ? 'Payment evidence access required'
                : snapshot.paymentState == 'unsupported'
                ? 'Payment evidence unsupported'
                : 'Payment evidence missing',
            snapshot.paymentState == 'denied'
                ? 'Payment read permission is required for ledger and current balance evidence.'
                : snapshot.paymentState == 'unsupported'
                ? 'The target does not have authoritative supported Rwanda receiving-wallet scope.'
                : 'No linked transaction evidence was found for this target.',
          )
        else ...[
          if (lifecycle == null)
            const _InvestigationMessage(
              'Lifecycle unavailable',
              'This payment has no linked ingested MoMo message.',
            )
          else
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                for (final row in [
                  ('Verification', lifecycle.verification),
                  ('Allocation', lifecycle.allocation),
                  ('Ledger', lifecycle.ledger),
                  ('Notification', lifecycle.notification),
                ])
                  _EvidenceState(label: row.$1, state: row.$2),
              ],
            ),
          const SizedBox(height: 12),
          const Text(
            'Recorded provider confirmation is not external settlement proof. Parsed-event and allocation-record times describe stored records; no parser completion time is attested.',
          ),
          const SizedBox(height: 16),
          const _InvestigationHeading('Posting snapshots'),
          if (payment.journals.isEmpty)
            const Text('No immutable journal posting snapshot was found.'),
          for (final journal in payment.journals) ...[
            const SizedBox(height: 10),
            Text(
              '${journal.entryType == 'receipt' ? 'Receipt' : 'Reversal'} journal · ${adminFormatRwfAmount('RWF ${journal.amountRwf}')}',
            ),
            Text('Journal posted ${_evidenceTime(journal.postedAt)}'),
            if (journal.snapshot == null)
              const Text('Posting balance snapshot unavailable.')
            else ...[
              Text(
                'Member balance at this posting: ${_amount(journal.snapshot!.memberRwf)}',
              ),
              Text(
                'Group balance at this posting: ${_amount(journal.snapshot!.groupRwf)}',
              ),
              Text(
                'Snapshot captured ${_evidenceTime(journal.snapshot!.capturedAt)}',
              ),
            ],
          ],
          const SizedBox(height: 16),
          const _InvestigationHeading('Current recorded balances'),
          Text(
            'Member: ${_amount(payment.currentBalances.memberRwf)} · Updated ${_evidenceTime(payment.currentBalances.memberUpdatedAt)}',
          ),
          Text(
            'Group: ${_amount(payment.currentBalances.groupRwf)} · Updated ${_evidenceTime(payment.currentBalances.groupUpdatedAt)}',
          ),
          const Text(
            'Current recorded balances may differ from the immutable balances at posting.',
          ),
        ],
        const SizedBox(height: 20),
        const _InvestigationHeading('Feature-phone SMS receipt'),
        if (receipt == null)
          _InvestigationMessage(
            snapshot.receiptState == 'denied'
                ? 'Receipt evidence access required'
                : snapshot.receiptState == 'unsupported'
                ? 'Receipt evidence unsupported'
                : 'No receipt evidence',
            snapshot.receiptState == 'denied'
                ? 'Notification read permission is required for receipt content and operator attempts.'
                : snapshot.receiptState == 'unsupported'
                ? 'Receipt interpretation is unavailable for an unclassified target.'
                : 'A receipt has not been created for this payment. No recipient or historical consent is inferred.',
          )
        else ...[
          const SizedBox(height: 10),
          _EvidenceState(label: 'Receipt state', state: receipt.state),
          const SizedBox(height: 10),
          Text('Masked destination: ${receipt.maskedDestination}'),
          const Text('Template: buri_munsi.payment_received · Version 1'),
          const SizedBox(height: 10),
          const _InvestigationHeading('Masked snapshot reconstruction'),
          if (receipt.maskedSnapshotPreview == null)
            const Text(
              'The matching immutable posting snapshot is unavailable; no message reconstruction is shown.',
            )
          else ...[
            Text(
              receipt.maskedSnapshotPreview!,
              key: const Key('masked-snapshot-preview'),
            ),
            const SizedBox(height: 6),
            Text(
              'Derived from the immutable posting snapshot captured ${_evidenceTime(receipt.snapshotCapturedAt)}. The reference is replaced with an opaque snapshot alias.',
            ),
          ],
          const Text(
            'This reconstruction does not establish the original sent message. The original body and destination remain protected by the current fenced operator claim.',
          ),
          const SizedBox(height: 16),
          const _InvestigationHeading('Operator approval records'),
          if (receipt.approvals.isEmpty)
            const Text('No operator approval records.'),
          for (final approval in receipt.approvals) ...[
            const SizedBox(height: 8),
            Text('Approval ${approval.id}'),
            Text('Approved ${_evidenceTime(approval.approvedAt)}'),
            Text(
              'Expiry ${_evidenceTime(approval.expiresAt)} · Consumed ${_evidenceTime(approval.consumedAt)}',
            ),
          ],
          const SizedBox(height: 16),
          const _InvestigationHeading('Operator send attempts'),
          if (receipt.attempts.isEmpty)
            const Text('No operator send attempt records.'),
          for (final attempt in receipt.attempts) ...[
            const SizedBox(height: 10),
            Text('Attempt ${attempt.number} · ${attempt.id}'),
            _EvidenceState(label: 'Outcome', state: attempt.state),
            Text(
              'Started ${_evidenceTime(attempt.startedAt)} · Outcome recorded ${_evidenceTime(attempt.outcomeAt)}',
            ),
          ],
          if (receipt.partialHistory) ...[
            const SizedBox(height: 12),
            Text(
              'Partial history: newest ${receipt.approvals.length} of ${receipt.approvalTotal} approvals and ${receipt.attempts.length} of ${receipt.attemptTotal} attempts. This view is bounded at 50 records per history.',
            ),
          ],
          const SizedBox(height: 12),
          const Text(
            'Operator observed sent is UI readback only. Unknown send outcomes remain unknown. Carrier delivery, provider callback and sender journal evidence are unavailable from this service.',
          ),
        ],
        const SizedBox(height: 20),
        const _InvestigationHeading('Recorded timeline'),
        const Text(
          'Each time retains its source meaning. Device and provider times may precede ingestion; expiry is an approval deadline.',
        ),
        const SizedBox(height: 8),
        for (final event in _timeline(payment, receipt))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Text('${_evidenceTime(event.$1)} · ${event.$2}'),
          ),
      ],
    );
  }

  static String _amount(String? value) =>
      value == null ? 'Unavailable' : adminFormatRwfAmount('RWF $value');
  static List<(DateTime, String)> _timeline(
    AdminInvestigationPayment? payment,
    AdminInvestigationReceipt? receipt,
  ) {
    const labels = {
      'received_at_device': 'Message received at device',
      'ingested_at': 'Message ingested',
      'parsed_recorded_at': 'Parsed event recorded',
      'allocation_recorded_at': 'Allocation record created',
      'provider_confirmed_at': 'Provider confirmation reported time',
      'confirmation_recorded_at': 'Provider confirmation record created',
      'rejection_occurred_at': 'Provider rejection reported time',
      'rejection_recorded_at': 'Provider rejection record created',
      'payment_posted_at': 'Payment posting field recorded time',
    };
    final events = <(DateTime, String)>[
      if (payment != null)
        for (final entry in payment.times.entries)
          if (entry.value != null) (entry.value!, labels[entry.key]!),
      if (payment != null)
        for (final journal in payment.journals) ...[
          (journal.postedAt, '${journal.entryType} journal posted'),
          if (journal.snapshot != null)
            (
              journal.snapshot!.capturedAt,
              '${journal.entryType} balance snapshot captured',
            ),
        ],
      if (receipt != null) ...[
        (receipt.createdAt, 'SMS receipt created'),
        (receipt.updatedAt, 'SMS receipt last updated'),
        if (receipt.observedSentAt != null)
          (receipt.observedSentAt!, 'Operator observed sent recorded'),
        for (final approval in receipt.approvals) ...[
          (approval.approvedAt, 'Operator approval recorded'),
          if (approval.consumedAt != null)
            (approval.consumedAt!, 'Operator approval consumed'),
        ],
        for (final attempt in receipt.attempts) ...[
          (attempt.startedAt, 'Attempt ${attempt.number} send started'),
          if (attempt.outcomeAt != null)
            (
              attempt.outcomeAt!,
              'Attempt ${attempt.number}: ${AdminTransactionLifecycle.label(attempt.state)} recorded',
            ),
        ],
      ],
    ];
    events.sort((a, b) {
      final time = a.$1.compareTo(b.$1);
      return time == 0 ? a.$2.compareTo(b.$2) : time;
    });
    return events;
  }
}

class _EvidenceState extends StatelessWidget {
  const _EvidenceState({required this.label, required this.state});
  final String label, state;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label),
      AdminStatusChip(
        label: AdminTransactionLifecycle.label(state),
        tone:
            {
              'evidence_conflict',
              'evidence_missing',
              'rejection_recorded',
              'failed_no_send',
              'parse_failed',
            }.contains(state)
            ? CollectStatusTone.danger
            : {
                'pending',
                'pending_parse',
                'queued',
                'awaiting_confirmation',
                'send_started',
                'uncertain',
                'unallocated',
                'ambiguous',
                'needs_review',
              }.contains(state)
            ? CollectStatusTone.warning
            : CollectStatusTone.info,
      ),
    ],
  );
}

class _InvestigationLink extends StatelessWidget {
  const _InvestigationLink(this.label, this.path);
  final String label, path;
  @override
  Widget build(BuildContext context) => TextButton.icon(
    onPressed: () => context.go(path),
    icon: const Icon(Icons.open_in_new_rounded),
    label: Text(label),
  );
}

class _InvestigationHeading extends StatelessWidget {
  const _InvestigationHeading(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
        color: context.collectColors.textPrimary,
      ),
    ),
  );
}

class _InvestigationMessage extends StatelessWidget {
  const _InvestigationMessage(this.title, this.message);
  final String title, message;
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        Text(message),
      ],
    ),
  );
}

class _InvestigationPanel extends StatelessWidget {
  const _InvestigationPanel({required this.title, required this.children});
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    explicitChildNodes: true,
    label: 'Linked payment and receipt investigation',
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.collectColors.surfaceReadable,
        borderRadius: CollectRadius.panelBorder,
        border: Border.all(color: context.collectColors.borderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _InvestigationHeading(title),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    ),
  );
}

// Evidence events can occur within the same minute; retain seconds while using
// the shared Kigali date/time adapters.
String _evidenceTime(DateTime? value) => value == null
    ? '—'
    : '${adminKigaliDate(value)} · ${adminKigaliTime(value)}:${value.toUtc().second.toString().padLeft(2, '0')} · Africa/Kigali';
