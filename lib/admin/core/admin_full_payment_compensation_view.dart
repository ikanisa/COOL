import 'dart:async';
import 'package:flutter/material.dart';
import '../../shared/widgets/collect_components.dart';
import '../shared/components/admin_data_listing.dart';
import 'admin_full_payment_compensation_controller.dart';

class AdminFullPaymentCompensationView extends StatefulWidget {
  const AdminFullPaymentCompensationView({required this.controller, super.key});
  final AdminFullPaymentCompensationController controller;
  @override
  State<AdminFullPaymentCompensationView> createState() =>
      _CompensationViewState();
}

class _CompensationViewState extends State<AdminFullPaymentCompensationView> {
  final _reason = TextEditingController();
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    unawaited(widget.controller.refresh());
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(AdminFullPaymentCompensationView old) {
    super.didUpdateWidget(old);
    if (!identical(old.controller, widget.controller)) {
      old.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
      _reason.clear();
      unawaited(widget.controller.refresh());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.controller.removeListener(_changed);
    _reason.dispose();
    super.dispose();
  }

  Widget _value(String name, Object? value) =>
      AdminDataFieldRow(label: name, value: value?.toString() ?? 'Unavailable');
  String _explanation(String code) => switch (code) {
    'payment_already_reversed' =>
      'This payment already has a recorded ledger compensation.',
    'payment_unavailable' =>
      'The payment is unavailable for the current review.',
    'insufficient_recorded_balance' =>
      'The recorded balance does not permit this full compensation. Investigate subsequent ledger activity.',
    _ =>
      'The current financial source does not permit full compensation. Refresh and investigate its provider and ledger evidence.',
  };
  Future<void> _confirm() async {
    final c = widget.controller, s = c.inspection?.source;
    if (!c.canSubmit || s == null) return;
    final reason = _reason.text.trim();
    if (reason.runes.length < 8 || reason.runes.length > 500) {
      await c.submit(reason);
      return;
    }
    final accepted = await showDialog<bool>(
      context: context,
      animationStyle: CollectMotion.animationStyle(context),
      builder: (context) => AlertDialog(
        title: const Text('Record full ledger compensation?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Deduct ${s.amountRwf} RWF from the recorded Collect ${s.memberRecordId == null ? 'group balance' : 'member and group balances'}.',
              ),
              const SizedBox(height: 12),
              const Text(
                'This records compensating ledger entries. It does not refund the payer at the provider, recall an admitted SMS send, or send a new receipt.',
              ),
              const SizedBox(height: 12),
              SelectableText(
                'Payment: ${s.paymentId}\nOriginal journal: ${s.originalJournalEntryId}\nOriginal snapshot: ${s.originalSnapshotId}',
              ),
              const SizedBox(height: 12),
              Text('Reason: $reason'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep payment'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Record compensation'),
          ),
        ],
      ),
    );
    if (mounted && accepted == true && c.canSubmit) await c.submit(reason);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller,
        sample = c.inspection,
        source = sample?.source,
        locked = c.busy || c.loading || c.pending != null;
    return AdminDataSection(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 16,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    'Full ledger compensation',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                OutlinedButton(
                  onPressed: c.busy || c.loading ? null : c.refresh,
                  child: const Text('Refresh financial review'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'A human owner can record a full compensation of this payment in the Collect ledger. Provider refunds and receipt sending require their own authority.',
            ),
            if (c.loading)
              const Padding(
                padding: EdgeInsets.only(top: 16),
                child: LinearProgressIndicator(),
              ),
            if (c.message != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Semantics(liveRegion: true, child: Text(c.message!)),
              ),
            if (c.pending != null) ...[
              _value('Retained original request', c.pending!.requestId),
              OutlinedButton(
                onPressed: c.busy || c.loading ? null : c.recover,
                child: const Text('Check original compensation request'),
              ),
            ],
            if (c.result != null) ...[
              _value('Recorded original request', c.result!.row['request_id']),
              _value(
                'Compensation journal',
                c.result!.row['compensation_journal_entry_id'],
              ),
              _value(
                'Compensation snapshot',
                c.result!.row['compensation_snapshot_id'],
              ),
              _value(
                'Recorded group balance after compensation',
                '${c.result!.row['group_balance_after_compensation_rwf']} RWF',
              ),
              if (c.result!.row['member_record_id'] != null)
                _value(
                  'Recorded member balance after compensation',
                  '${c.result!.row['member_balance_after_compensation_rwf']} RWF',
                ),
            ],
            if (sample != null && !sample.canRecord)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_explanation(sample.row['reason_code'] as String)),
              ),
            if (source != null) ...[
              _value('Payment amount', '${source.amountRwf} RWF'),
              _value('Provider reference', source.row['reference']),
              _value('Original ledger snapshot', source.originalSnapshotId),
              _value(
                'Group balance recorded in the original snapshot',
                '${source.row['original_group_balance_recorded_rwf']} RWF',
              ),
              _value(
                'Group balance in this review',
                '${source.row['group_balance_current_rwf']} RWF',
              ),
              _value(
                'Group balance after this compensation',
                '${source.row['group_balance_after_compensation_rwf']} RWF',
              ),
              if (source.memberRecordId == null)
                const Text(
                  'This is a group-only payment. No member balance is attributed.',
                )
              else ...[
                _value(
                  'Member balance recorded in the original snapshot',
                  '${source.row['original_member_balance_recorded_rwf']} RWF',
                ),
                _value(
                  'Member balance in this review',
                  '${source.row['member_balance_current_rwf']} RWF',
                ),
                _value(
                  'Member balance after this compensation',
                  '${source.row['member_balance_after_compensation_rwf']} RWF',
                ),
              ],
              _value(
                'Financial review valid until',
                sample!.sampleValidUntil.toIso8601String(),
              ),
              if (!sample.fresh(c.now()))
                const Text(
                  'This financial review expired. Refresh it before recording.',
                ),
              const SizedBox(height: 12),
              TextField(
                controller: _reason,
                enabled: !locked && c.result == null,
                maxLength: 500,
                minLines: 2,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'Compensation reason',
                  helperText:
                      '8–500 characters. Describe the reason for full ledger compensation.',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: c.canSubmit ? _confirm : null,
                child: Text(
                  c.busy
                      ? 'Recording compensation…'
                      : 'Review full compensation',
                ),
              ),
            ],
            if (c.store == null)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'Recording requires durable browser storage and its exclusive journal lock. The financial review remains readable.',
                ),
              ),
          ],
        ),
      ),
    );
  }
}
