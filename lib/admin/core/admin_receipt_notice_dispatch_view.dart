import 'dart:async';
import 'package:flutter/material.dart';
import '../shared/components/admin_data_listing.dart';
import 'admin_receipt_notice_dispatch_controller.dart';
import 'admin_receipt_notice_dispatch_models.dart';

class AdminReceiptNoticeDispatchView extends StatefulWidget {
  const AdminReceiptNoticeDispatchView({required this.controller, super.key});
  final AdminReceiptNoticeDispatchController controller;
  @override
  State<AdminReceiptNoticeDispatchView> createState() => _DispatchViewState();
}

class _DispatchViewState extends State<AdminReceiptNoticeDispatchView> {
  final _reason = TextEditingController();
  Timer? _timer;
  bool? _enabled;
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
    if (!mounted) return;
    if (widget.controller.configuration != null) {
      _enabled ??= widget.controller.configuration!.enabled;
    }
    if (widget.controller.inspection == null &&
        widget.controller.configuration == null) {
      _reason.clear();
      _enabled = null;
    }
    setState(() {});
  }

  @override
  void didUpdateWidget(AdminReceiptNoticeDispatchView old) {
    super.didUpdateWidget(old);
    if (!identical(old.controller, widget.controller)) {
      old.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
      _reason.clear();
      _enabled = null;
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

  Widget _value(String label, Object? value) => AdminDataFieldRow(
    label: label,
    value: value?.toString() ?? 'Unavailable',
  );
  String _reasonText(String reason) => switch (reason) {
    'notice_review_eligible' =>
      'The prepared review can be considered for a conditional approval.',
    'notice_approval_pending' =>
      'An approval is already recorded for this original receipt and purpose.',
    'notice_already_materialized' =>
      'A notice job is already recorded. This version permits one job per original receipt and purpose.',
    'prepared_source_changed' =>
      'Prepared source evidence or current consent/policy changed. Prepare and review current evidence.',
    _ =>
      'The current source does not permit dispatch approval. Investigate the original receipt and policy.',
  };
  @override
  Widget build(BuildContext context) {
    final c = widget.controller,
        sample = c.inspection,
        config = c.configuration,
        ref = c.reference;
    final locked = c.busy || c.loading || c.pending != null;
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
                    c.configurationOnly
                        ? 'Notice dispatch configuration'
                        : 'Notice dispatch review',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                OutlinedButton(
                  onPressed: c.busy || c.loading ? null : c.refresh,
                  child: const Text('Refresh dispatch evidence'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              c.configurationOnly
                  ? 'Review the current shared configuration revision before recording a change.'
                  : 'Review the exact immutable prepared notice before recording a conditional 15-minute approval. An approved gateway must independently satisfy current run, pause, quota, permission and health checks.',
            ),
            if (c.loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: LinearProgressIndicator(
                  semanticsLabel: 'Loading dispatch evidence',
                ),
              ),
            if (c.error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Semantics(liveRegion: true, child: Text(c.error!)),
              ),
            if (config != null && !config.fresh(c.now()) ||
                sample != null && !sample.fresh(c.now()))
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'The review sample expired. Refresh current dispatch evidence before recording a decision.',
                ),
              ),
            if (ref != null) ...[
              _value('Prepared review', ref.preparedReviewId),
              _value('Original content request', ref.originalRequestId),
              _value('Original receipt', ref.outboxId),
              _value('Notice purpose', ref.family.label),
            ],
            if (config != null) ...[
              _value('Current configuration revision', config.revision),
              _value('Configuration last updated', config.row['updated_at']!),
              _value('Configuration sampled at', config.row['checked_at']!),
              _value(
                'Review sample valid until',
                config.row['sample_valid_until']!,
              ),
              _value(
                'Current configured state',
                config.enabled ? 'Enabled' : 'Disabled',
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Permit approved notice dispatch'),
                subtitle: const Text(
                  'This setting persists until changed. The review sample has a separate 60-second validity window.',
                ),
                value: _enabled ?? config.enabled,
                onChanged: c.canRecord
                    ? (value) => setState(() => _enabled = value)
                    : null,
              ),
            ],
            if (sample != null) ...[
              _value('Review sampled at', sample.row['checked_at']!),
              _value(
                'Review sample valid until',
                sample.row['sample_valid_until']!,
              ),
              _value('Current transport revision', sample.revision),
              _value(
                'Dispatch configuration observed',
                sample.dispatchEnabled ? 'Enabled' : 'Disabled',
              ),
              _value('Review outcome', _reasonText(sample.reason)),
              if (sample.candidate['body'] != null) ...[
                _value('Immutable notice content', sample.candidate['body']!),
                _value('Body evidence hash', sample.candidate['body_sha256']!),
              ],
              if (c.approval != null) ...[
                _value('Recorded approval', c.approval!['approval_id']!),
                _value('Approval valid until', c.approval!['expires_at']!),
                const Text(
                  'Recorded approval metadata does not establish current send authority or delivery.',
                ),
              ],
            ],
            if (config != null || sample != null) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _reason,
                enabled: c.canRecord,
                maxLength: 500,
                minLines: 1,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Decision reason',
                  helperMaxLines: 3,
                  helperText: '8–500 characters',
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  if (c.configurationOnly)
                    FilledButton(
                      onPressed: c.canRecord
                          ? () => c.record(
                              AdminReceiptNoticeDispatchAction.configure,
                              _reason.text,
                              enabled: _enabled ?? config!.enabled,
                            )
                          : null,
                      child: const Text('Record dispatch configuration'),
                    ),
                  if (!c.configurationOnly)
                    FilledButton(
                      onPressed: c.canApprove
                          ? () => c.record(
                              AdminReceiptNoticeDispatchAction.approve,
                              _reason.text,
                            )
                          : null,
                      child: const Text('Record conditional approval'),
                    ),
                  if (!c.configurationOnly)
                    OutlinedButton(
                      onPressed: c.canRevoke
                          ? () => c.record(
                              AdminReceiptNoticeDispatchAction.revoke,
                              _reason.text,
                            )
                          : null,
                      child: const Text('Revoke unarmed approval'),
                    ),
                ],
              ),
            ],
            if (c.pending != null) ...[
              const SizedBox(height: 16),
              Semantics(
                header: true,
                child: Text(
                  'Original dispatch request recovery',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              _value('Original request', c.pending!.requestId),
              _value('Retained action', c.pending!.action.wire),
              const Text(
                'Unknown and not-recorded outcomes retain this original identifier. Replacement requests stay blocked.',
              ),
              OutlinedButton(
                onPressed: c.busy ? null : c.recover,
                child: const Text('Recover original dispatch request'),
              ),
            ],
            if (c.receipt?.recorded == true) ...[
              _value(
                'Recorded dispatch request',
                c.receipt!.result!['request_id']!,
              ),
              _value('Audit record', c.receipt!.result!['audit_id']!),
            ],
            if (c.store == null)
              const Text(
                'Durable browser recovery is unavailable. Recording is disabled.',
              ),
            if (!c.canManage())
              const Text(
                'Current notification manage permission is required to record a decision.',
              ),
            const SizedBox(height: 12),
            const Text(
              'No message is sent from this page. Original receipts and financial records are retained. Revocation is checked on the backend and cannot establish that an armed message was never sent.',
            ),
            if (locked) const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}
