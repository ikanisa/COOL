import 'dart:async';
import 'package:flutter/material.dart';
import '../shared/components/admin_data_listing.dart';
import 'admin_receipt_notice_content_models.dart';
import 'admin_receipt_notice_content_controller.dart';

class AdminReceiptNoticeContentView extends StatefulWidget {
  const AdminReceiptNoticeContentView({
    required this.controller,
    this.reversalSnapshotId,
    super.key,
  });
  final AdminReceiptNoticeContentController controller;
  final String? reversalSnapshotId;
  @override
  State<AdminReceiptNoticeContentView> createState() => _ViewState();
}

class _ViewState extends State<AdminReceiptNoticeContentView> {
  final _reason = TextEditingController();
  AdminReceiptNoticeFamily _family = AdminReceiptNoticeFamily.duplicateCopy;
  String _language = 'rw';
  bool _enabled = true;
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    unawaited(_refresh());
  }

  Future<void> _refresh() => widget.controller.refresh(
    family: _family,
    language: _language,
    enabled: _enabled,
    sourceOverride:
        !widget.controller.policy &&
            _family == AdminReceiptNoticeFamily.reversalNotice
        ? widget.reversalSnapshotId
        : null,
  );
  bool get _sourceAvailable =>
      widget.controller.policy ||
      _family != AdminReceiptNoticeFamily.reversalNotice ||
      widget.reversalSnapshotId != null;
  @override
  void didUpdateWidget(AdminReceiptNoticeContentView old) {
    super.didUpdateWidget(old);
    if (!identical(old.controller, widget.controller)) {
      old.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
      _reason.clear();
      _family = AdminReceiptNoticeFamily.duplicateCopy;
      _language = 'rw';
      _enabled = true;
      unawaited(_refresh());
    }
  }

  void _changed() {
    if (!mounted) return;
    if (widget.controller.inspection == null) _reason.clear();
    setState(() {});
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.controller.removeListener(_changed);
    _reason.dispose();
    super.dispose();
  }

  Widget _value(String label, String value) =>
      AdminDataFieldRow(label: label, value: value);
  String _blocked(String reason) => switch (reason) {
    'correction_source_unavailable' =>
      'Correction requires verified source evidence before content can be prepared.',
    'approved_resend_resolution_unavailable' =>
      'Resolve the original send outcome before an approved resend can be considered.',
    'notice_policy_inactive' =>
      'Approve an active notice policy for this group and language in Settings.',
    'notice_content_review_cap_exhausted' =>
      'The retained content-review limit has been reached. Review the existing records.',
    'current_consent_missing' =>
      'Current receipt consent is required for this member.',
    'original_recipient_changed' =>
      'The current contact differs from the original recipient. Review contact evidence.',
    'transport_uncertain' ||
    'transport_unreconciled' ||
    'transport_topology_unavailable' =>
      'Reconcile the original transport evidence before preparing a copy.',
    _ =>
      'The recorded source evidence does not permit this notice. Investigate the payment and original receipt.',
  };
  @override
  Widget build(BuildContext context) {
    final c = widget.controller,
        s = c.inspection,
        p = s?.candidate,
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
                    c.policy
                        ? 'Receipt notice policy'
                        : 'Receipt notice content',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                OutlinedButton(
                  onPressed: c.busy || c.loading || !_sourceAvailable
                      ? null
                      : _refresh,
                  child: const Text('Refresh preview'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              c.policy
                  ? 'Approve the notice language, historical disclosure and original-member recipient rule for this group.'
                  : 'Review immutable content derived from the recorded financial evidence and current receipt consent.',
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<AdminReceiptNoticeFamily>(
              initialValue: _family,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Notice purpose'),
              items: [
                for (final f in AdminReceiptNoticeFamily.values.where(
                  (f) => !c.policy || f.contentSupported,
                ))
                  DropdownMenuItem(value: f, child: Text(f.label)),
              ],
              onChanged: locked
                  ? null
                  : (v) {
                      if (v == null) return;
                      setState(() => _family = v);
                      c.invalidatePreview();
                    },
            ),
            if (c.policy) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _language,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Notice language'),
                items: const [
                  DropdownMenuItem(value: 'rw', child: Text('Kinyarwanda')),
                  DropdownMenuItem(value: 'en', child: Text('English')),
                  DropdownMenuItem(value: 'fr', child: Text('French')),
                ],
                onChanged: locked
                    ? null
                    : (v) {
                        if (v == null) return;
                        setState(() => _language = v);
                        c.invalidatePreview();
                      },
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Approve active notice policy'),
                subtitle: const Text(
                  'Policy approval and prepared content do not authorize sending.',
                ),
                value: _enabled,
                onChanged: locked
                    ? null
                    : (v) {
                        setState(() => _enabled = v);
                        c.invalidatePreview();
                      },
              ),
            ],
            if (!c.policy && !_sourceAvailable)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Verified compensation snapshot evidence is required to preview a ledger compensation notice.',
                ),
              ),
            if (c.loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: LinearProgressIndicator(
                  semanticsLabel: 'Loading notice evidence',
                ),
              ),
            if (c.error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Semantics(liveRegion: true, child: Text(c.error!)),
              ),
            if (s != null) ...[
              _value(
                'Preview valid until',
                s.validUntil.toUtc().toIso8601String(),
              ),
              if (!s.fresh(c.now()))
                const Text(
                  'This preview has expired. Refresh before recording.',
                ),
              if (c.policy) ...[
                _value(
                  'Policy revision',
                  p!['expected_policy_revision'].toString(),
                ),
                _value('Recorded policy', switch (p['current_policy_status']) {
                  'approved_active' => 'Approved and active',
                  'approved_inactive' => 'Approved and inactive',
                  _ => 'Approval unavailable',
                }),
                _value(
                  'Recipient',
                  'Same original member; current receipt consent required',
                ),
                _value(
                  'Disclosure',
                  _family == AdminReceiptNoticeFamily.duplicateCopy
                      ? 'Original recorded receipt facts only'
                      : 'Collect ledger compensation facts only',
                ),
                _value(
                  'Immutable wording',
                  (p['template'] as Map)['body_frame'] as String,
                ),
              ] else if (s.canPrepare) ...[
                _value('Recorded notice language', switch (p!['language']) {
                  'rw' => 'Kinyarwanda',
                  'en' => 'English',
                  _ => 'French',
                }),
                _value('Original recipient', p['destination_masked'] as String),
                _value('Immutable notice preview', p['body'] as String),
                _value('SMS segments', p['segment_count'].toString()),
                _value(
                  'Historical financial evidence',
                  'Recorded values are preserved. Current balances are not substituted; bank settlement and delivery are not inferred.',
                ),
                _value(
                  'Policy / content revision',
                  '${p['policy_revision']} / ${p['content_review_revision']}',
                ),
              ] else ...[
                _value(
                  'Preparation blocked',
                  _blocked(p!['reason_code'] as String),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _reason,
                enabled: c.canRecord,
                maxLength: 500,
                minLines: 1,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Reason for recording',
                  helperText:
                      '8–500 characters; retained with the original request',
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: c.canRecord ? () => c.record(_reason.text) : null,
                child: Text(
                  c.policy
                      ? 'Record notice policy'
                      : 'Save immutable notice content',
                ),
              ),
            ],
            if (c.store == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Durable browser recovery is unavailable. Recording is disabled.',
                ),
              ),
            if (!c.policy && c.preserveRecordedContent == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Notice approval recovery is unavailable in this session. Content preparation is disabled.',
                ),
              ),
            if (!c.canManage())
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Current notification manage permission is required to record a change.',
                ),
              ),
            if (c.pending != null) ...[
              const SizedBox(height: 16),
              Semantics(
                header: true,
                child: Text(
                  'Original request recovery',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              _value('Original request', c.pending!.requestId),
              _value('Retained purpose', c.pending!.inspection.family.label),
              if (!c.pending!.policy)
                _value('Original receipt', c.pending!.inspection.outboxId!),
              const Text(
                'Unknown and not-recorded outcomes remain blocked. Recover this identifier before another change.',
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: c.busy ? null : c.recover,
                child: const Text('Recover original request'),
              ),
            ],
            if (c.receipt?.recorded == true) ...[
              const SizedBox(height: 16),
              _value(
                'Recorded original request',
                c.receipt!.result!['request_id'] as String,
              ),
              _value('Audit record', c.receipt!.result!['audit_id'] as String),
            ],
            const SizedBox(height: 12),
            const Text(
              'Sending approval remains separate. Original receipts and financial evidence are retained.',
            ),
          ],
        ),
      ),
    );
  }
}
