import 'dart:async';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../app/theme/collect_motion.dart';
import '../shared/components/admin_data_listing.dart';
import 'admin_display_formatters.dart';
import 'admin_receipt_successor_models.dart';
import 'admin_receipt_successor_controller.dart';
import 'admin_receipt_successor_sdk.dart';
import 'admin_receipt_successor_execution_host.dart';
import 'admin_receipt_successor_execution_sdk.dart';

/// The parent supplies one session-bound controller and current role flags.
/// Replace it on auth/repository/identity changes. The SDK rechecks that scope
/// before and after every await; this view never calls an arbitrary RPC.
class AdminReceiptSuccessorView extends StatefulWidget {
  const AdminReceiptSuccessorView({
    required this.outboxId,
    required this.sourceSnapshotId,
    required this.controller,
    required this.canRead,
    required this.canManage,
    required this.now,
    this.onRecorded,
    this.selectedApprovalId,
    super.key,
  });
  final String outboxId, sourceSnapshotId;
  final String? selectedApprovalId;
  final AdminReceiptSuccessorController controller;
  final bool canRead, canManage;
  final DateTime Function() now;
  final VoidCallback? onRecorded;
  @override
  State<AdminReceiptSuccessorView> createState() => _SuccessorViewState();
}

class _SuccessorViewState extends State<AdminReceiptSuccessorView> {
  AdminReceiptClosureInspection? _closure;
  AdminReceiptSuccessorInspection? _inspection;
  final List<AdminReceiptSuccessorApproval> _history = [];
  int? _next;
  int _generation = 0;
  bool _loading = false, _historyBusy = false, _retryBusy = false;
  String? _error;
  String? _seenReceipt;
  String? _selectedApprovalId;
  bool _explicitReady = false;
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    if (widget.canRead) _refresh();
  }

  @override
  void didUpdateWidget(AdminReceiptSuccessorView old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
    if (old.controller != widget.controller ||
        old.outboxId != widget.outboxId ||
        old.sourceSnapshotId != widget.sourceSnapshotId ||
        old.canRead != widget.canRead ||
        old.canManage != widget.canManage ||
        old.selectedApprovalId != widget.selectedApprovalId) {
      _generation++;
      _closure = null;
      _inspection = null;
      _history.clear();
      _selectedApprovalId = null;
      _explicitReady = false;
      _next = null;
      _error = null;
      _seenReceipt = null;
      _loading = false;
      _historyBusy = false;
      _retryBusy = false;
      if (widget.canRead) _refresh();
    }
  }

  @override
  void dispose() {
    _generation++;
    _timer?.cancel();
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    final request = widget.controller.receipt?.row['request_id'] as String?;
    if (request != null && request != _seenReceipt) {
      _seenReceipt = request;
      widget.onRecorded?.call();
      unawaited(_refresh());
    } else {
      setState(() {});
    }
  }

  Future<void> _refresh() async {
    if (!widget.canRead) return;
    final generation = ++_generation;
    final api = widget.controller.api;
    setState(() {
      _loading = true;
      _historyBusy = false;
      _retryBusy = false;
      _closure = null;
      _inspection = null;
      _history.clear();
      _selectedApprovalId = null;
      _explicitReady = false;
      _next = null;
      _error = null;
    });
    try {
      final values = await Future.wait<Object>([
        api.closure(widget.outboxId),
        api.inspect(widget.outboxId, widget.sourceSnapshotId),
        api.history(widget.outboxId),
      ]);
      if (!mounted || generation != _generation || !widget.canRead) return;
      final history = values[2] as AdminReceiptSuccessorHistory;
      setState(() {
        _closure = values[0] as AdminReceiptClosureInspection;
        _inspection = values[1] as AdminReceiptSuccessorInspection;
        _history.addAll(history.items);
        _explicitReady = widget.selectedApprovalId != null;
        _next = history.nextAfter;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(
        () => _error =
            'Current receipt review could not be loaded. Check access and refresh.',
      );
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _more() async {
    final next = _next;
    if (next == null || _historyBusy || !widget.canRead) return;
    final generation = _generation;
    setState(() => _historyBusy = true);
    try {
      final page = await widget.controller.api.history(
        widget.outboxId,
        after: next,
      );
      if (!mounted || generation != _generation || !widget.canRead) return;
      final ids = _history.map((a) => a.id).toSet();
      if (page.items.any((a) => ids.contains(a.id))) successorInvalid();
      setState(() {
        _history.addAll(page.items);
        _next = page.nextAfter;
      });
    } catch (failure) {
      if (mounted && generation == _generation) {
        final denied =
            executionAccessDenied(failure) ||
            failure is AdminReceiptSuccessorRejected && failure.code == '42501';
        setState(() {
          if (denied) {
            _generation++;
            _closure = null;
            _inspection = null;
            _history.clear();
            _selectedApprovalId = null;
            _explicitReady = false;
            _next = null;
            _historyBusy = false;
            _retryBusy = false;
          }
          _error = denied
              ? 'Current receipt review access is denied. Refresh after restoring access.'
              : 'More receipt history could not be loaded.';
        });
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _historyBusy = false);
      }
    }
  }

  Future<void> _inspectRetry(AdminReceiptSuccessorApproval approval) async {
    final originalController = widget.controller;
    final api = originalController.api;
    if (!widget.canRead ||
        !widget.canManage ||
        !originalController.canSubmit ||
        _loading ||
        _retryBusy ||
        approval.status != 'revoked' ||
        api is! AdminReceiptSuccessorRetryApi) {
      return;
    }
    final generation = ++_generation;
    setState(() {
      _retryBusy = true;
      _historyBusy = false;
      _inspection = null;
      _error = null;
    });
    try {
      final inspection = await (api as AdminReceiptSuccessorRetryApi)
          .inspectRetry(widget.outboxId, widget.sourceSnapshotId, approval.id);
      if (!mounted ||
          generation != _generation ||
          originalController != widget.controller ||
          !widget.canRead ||
          !widget.canManage) {
        return;
      }
      setState(() => _inspection = inspection);
    } catch (failure) {
      if (!mounted || generation != _generation) return;
      final denied =
          executionAccessDenied(failure) ||
          failure is AdminReceiptSuccessorExecutionDenied ||
          failure is AdminReceiptSuccessorRejected && failure.code == '42501';
      setState(() {
        _inspection = null;
        if (denied) {
          _closure = null;
          _history.clear();
          _selectedApprovalId = null;
          _explicitReady = false;
          _next = null;
        }
        _error = denied
            ? 'Current receipt review access is denied. Refresh after restoring access.'
            : 'A stopped predecessor could not be verified. Refresh and investigate its execution before another retry.';
      });
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _retryBusy = false);
      }
    }
  }

  Future<void> _review(
    String action, {
    AdminReceiptSuccessorApproval? approval,
  }) async {
    final originalController = widget.controller;
    final generation = _generation;
    if (!widget.canManage || !originalController.canSubmit || _retryBusy) {
      return;
    }
    final inspection = _inspection, closure = _closure;
    final validUntil = action == 'approve_successor'
        ? inspection?.validUntil
        : action == 'close_unarmed'
        ? closure?.validUntil
        : widget.now().toUtc().add(const Duration(seconds: 60));
    final title = switch (action) {
      'close_unarmed' => 'Close original receipt',
      'approve_successor' =>
        inspection?.isRetiredRetry == true
            ? 'Approve next retry'
            : 'Approve replacement receipt',
      _ => 'Revoke approval',
    };
    final reason = await showDialog<String>(
      context: context,
      animationStyle: CollectMotion.animationStyle(context),
      builder: (context) => _SuccessorReasonDialog(
        title: title,
        valid: () =>
            mounted &&
            generation == _generation &&
            originalController == widget.controller &&
            widget.canRead &&
            widget.canManage &&
            originalController.canSubmit &&
            validUntil != null &&
            widget.now().toUtc().isBefore(validUntil),
        preview: action == 'approve_successor' ? inspection?.preview : null,
        explanation: action == 'close_unarmed'
            ? 'This original receipt will remain closed. A replacement requires a separate review.'
            : action == 'approve_successor'
            ? 'Retain this exact text and recipient for up to 15 minutes. This review action does not authorize a send.'
            : 'Preserve the recorded approval and stop its pending execution.',
      ),
    );
    if (reason == null ||
        !mounted ||
        generation != _generation ||
        originalController != widget.controller ||
        !widget.canManage ||
        !originalController.canSubmit) {
      return;
    }
    try {
      final request = const Uuid().v4();
      final intent = switch (action) {
        'close_unarmed' => originalController.api.prepareClosure(
          request,
          closure!,
          reason,
        ),
        'approve_successor' => originalController.api.prepareApproval(
          request,
          inspection!,
          reason,
        ),
        _ => originalController.api.prepareRevocation(
          request,
          approval!,
          reason,
        ),
      };
      await originalController.submit(intent);
      if (!mounted ||
          generation != _generation ||
          originalController != widget.controller) {
        return;
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(
          () => _error =
              'The review expired or current access changed. Refresh evidence before another review.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.canRead) {
      return const AdminDataSection(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text('Current receipt review access is required.'),
        ),
      );
    }
    final controller = widget.controller, now = widget.now();
    final closure = _closure, inspection = _inspection;
    final closureFresh = closure?.fresh(now) == true,
        previewFresh = inspection?.fresh(now) == true;
    final manage =
        widget.canManage && controller.canSubmit && !_loading && !_retryBusy;
    return AdminDataSection(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                'Replacement receipt review',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Close an original that has never been armed, then review its replacement. A later retry requires proof that earlier attempts were permanently stopped before sending. Payment records and receipt history remain retained.',
            ),
            const SizedBox(height: 16),
            if (_loading || _retryBusy)
              Semantics(
                label: 'Loading current receipt review',
                child: const LinearProgressIndicator(),
              )
            else if (_error != null)
              Semantics(liveRegion: true, child: Text(_error!))
            else ...[
              if (closureFresh && closure != null)
                Text(_closureLabel(closure.reason))
              else
                const Text(
                  'Closure inspection expired. Refresh before review.',
                ),
              if (previewFresh && inspection != null) ...[
                const SizedBox(height: 12),
                Text(_previewLabel(inspection.reason)),
                if (inspection.isRetiredRetry && inspection.retiredJobs != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '${inspection.retiredJobs} prior ${inspection.retiredJobs == 1 ? 'attempt was' : 'attempts were'} permanently stopped before sending. This review binds the retained predecessor proof.',
                    ),
                  ),
                if (inspection.preview != null)
                  _SuccessorPreview(preview: inspection.preview!),
                if (inspection.row['configuration_enabled'] == false)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'Sending is disabled. A retained approval does not enable the gateway.',
                    ),
                  ),
              ] else
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text(
                    'Replacement inspection expired. Refresh to see current evidence.',
                  ),
                ),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                OutlinedButton.icon(
                  onPressed: _loading || _retryBusy || controller.busy
                      ? null
                      : _refresh,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh evidence'),
                ),
                if (widget.canManage &&
                    closureFresh &&
                    closure?.canClose == true)
                  FilledButton(
                    onPressed: manage ? () => _review('close_unarmed') : null,
                    child: const Text('Review closure'),
                  ),
                if (widget.canManage &&
                    previewFresh &&
                    inspection?.canApprove == true)
                  FilledButton(
                    onPressed: manage
                        ? () => _review('approve_successor')
                        : null,
                    child: Text(
                      inspection!.isRetiredRetry
                          ? 'Review next retry'
                          : 'Review replacement',
                    ),
                  ),
              ],
            ),
            if (controller.store == null || controller.storageFailed)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'Verified tab recovery storage is required before recording an action.',
                ),
              ),
            if (controller.busy) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
            if (controller.message != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Semantics(
                  liveRegion: true,
                  child: Text(controller.message!),
                ),
              ),
            if (controller.pending != null) ...[
              const SizedBox(height: 8),
              SelectableText(
                'Original request ID: ${controller.pending!.requestId}',
              ),
              if (controller.pending!.expected['outbox_id'] != widget.outboxId)
                const Text(
                  'This recovered original belongs to another receipt. Its outcome must be checked before a new action.',
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton(
                  onPressed: controller.busy ? null : controller.recover,
                  child: const Text('Check original request'),
                ),
              ),
            ],
            if (controller.receipt != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Recorded ${adminKigaliDateTime(controller.receipt!.recordedAt)} · No financial or send action.',
                ),
              ),
            const SizedBox(height: 20),
            Semantics(
              header: true,
              child: Text(
                'Reviewed approvals',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (!_loading && _history.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('No reviewed replacement approvals.'),
              ),
            for (final item in _history)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Approval ${item.sequence} · ${item.status == 'pending' && !now.isBefore(item.expiresAt) ? 'expired' : item.status}',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    Text(
                      'Recorded ${adminKigaliDateTime(item.recordedAt)} · Expires ${adminKigaliDateTime(item.expiresAt)}',
                    ),
                    Text('Reason: ${item.row['reason']}'),
                    _SuccessorPreview(preview: item.preview),
                    for (final event in item.events)
                      Text('${event['event_kind']} · ${event['reason']}'),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton(
                        onPressed: () => setState(() {
                          _selectedApprovalId = _selectedApprovalId == item.id
                              ? null
                              : item.id;
                        }),
                        child: Text(
                          _selectedApprovalId == item.id
                              ? 'Close investigation'
                              : 'Investigate execution',
                        ),
                      ),
                    ),
                    if (widget.canManage &&
                        item.status == 'revoked' &&
                        controller.api is AdminReceiptSuccessorRetryApi)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton(
                          onPressed: manage ? () => _inspectRetry(item) : null,
                          child: const Text('Inspect retry after stop'),
                        ),
                      ),
                    if (widget.canManage && item.status != 'revoked')
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton(
                          onPressed: manage
                              ? () =>
                                    _review('revoke_successor', approval: item)
                              : null,
                          child: const Text('Review revocation'),
                        ),
                      ),
                  ],
                ),
              ),
            if ((_selectedApprovalId != null &&
                    _history.any((item) => item.id == _selectedApprovalId)) ||
                (_explicitReady &&
                    widget.selectedApprovalId != null &&
                    widget.canRead &&
                    previewFresh)) ...[
              const SizedBox(height: 16),
              AdminReceiptSuccessorExecutionHost(
                key: ValueKey((
                  widget.outboxId,
                  _selectedApprovalId ?? widget.selectedApprovalId,
                )),
                approvalId: _selectedApprovalId ?? widget.selectedApprovalId!,
                primaryReceiptId: widget.outboxId,
              ),
            ],
            if (_next != null)
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton(
                  onPressed: _historyBusy ? null : _more,
                  child: Text(
                    _historyBusy ? 'Loading history…' : 'Load more approvals',
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

String _closureLabel(String reason) => switch (reason) {
  'unarmed_eligible' =>
    'The original can be permanently closed before replacement review.',
  'already_closed' => 'The original is permanently closed.',
  'original_already_armed' || 'assisted_transport_present' =>
    'Existing transport evidence prevents closure. Investigate its outcome.',
  'state_not_queued' => 'The original is no longer queued.',
  'source_evidence_invalid' => 'The financial evidence no longer qualifies.',
  'revision_exhausted' => 'The receipt revision limit prevents further action.',
  _ => 'The original is unavailable for closure.',
};
String _previewLabel(String reason) => switch (reason) {
  'retry_eligible' =>
    'Review the exact replacement text and recorded member balance.',
  'approval_pending' => 'A replacement approval is already pending.',
  'irreversible_closure_required' =>
    'Close the original before reviewing its replacement.',
  'consent_missing' => 'Current member consent is required.',
  'policy_disabled' => 'The current receipt policy is disabled.',
  'contact_missing' => 'An eligible current member contact is required.',
  'transport_proof_changed' ||
  'predecessor_transport_refused' ||
  'predecessor_proof_invalid' =>
    'Transport evidence changed. Investigate before another action.',
  'predecessor_revocation_required' =>
    'Permanently stop the earlier unarmed attempt before another retry.',
  'predecessor_not_latest' =>
    'A later attempt exists. Refresh history and investigate that attempt.',
  'lineage_limit' => 'The retained retry limit prevents another attempt.',
  'predecessor_unavailable' =>
    'The stopped predecessor is unavailable. Refresh its execution evidence.',
  _ => 'A replacement is unavailable from the current evidence.',
};

class _SuccessorPreview extends StatelessWidget {
  const _SuccessorPreview({required this.preview});
  final AdminReceiptSuccessorPreview preview;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminDataFieldRow(label: 'Recipient', value: preview.recipient),
        AdminDataFieldRow(
          label: 'Language',
          value: switch (preview.language) {
            'rw' => 'Kinyarwanda',
            'fr' => 'French',
            _ => 'English',
          },
        ),
        AdminDataFieldRow(
          label: 'Recorded member balance',
          value: adminFormatRwfAmount(
            'RWF ${preview.row['member_balance_recorded_rwf']}',
          ),
        ),
        const SizedBox(height: 8),
        Semantics(
          label: 'Exact receipt text. ${preview.body}',
          child: AdminDataFieldRow(label: 'Receipt text', value: preview.body),
        ),
      ],
    ),
  );
}

class _SuccessorReasonDialog extends StatefulWidget {
  const _SuccessorReasonDialog({
    required this.title,
    required this.explanation,
    required this.valid,
    this.preview,
  });
  final String title, explanation;
  final AdminReceiptSuccessorPreview? preview;
  final bool Function() valid;
  @override
  State<_SuccessorReasonDialog> createState() => _SuccessorReasonDialogState();
}

class _SuccessorReasonDialogState extends State<_SuccessorReasonDialog> {
  final _text = TextEditingController();
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(
    BuildContext context,
  ) => ValueListenableBuilder<TextEditingValue>(
    valueListenable: _text,
    builder: (context, value, _) => AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!widget.valid())
                const Text(
                  'Review expired or current receipt access changed. Close this dialog and refresh current evidence.',
                )
              else ...[
                Text(widget.explanation),
                if (widget.preview != null)
                  _SuccessorPreview(preview: widget.preview!),
                const SizedBox(height: 16),
                TextField(
                  controller: _text,
                  autofocus: true,
                  minLines: 2,
                  maxLines: 4,
                  maxLength: 500,
                  decoration: const InputDecoration(
                    labelText: 'Reason for this review',
                    helperText: 'Describe the review in at least 8 characters.',
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Back'),
        ),
        FilledButton(
          onPressed:
              widget.valid() &&
                  value.text.trim().length >= 8 &&
                  value.text.trim().length <= 500
              ? () => Navigator.of(context).pop(value.text.trim())
              : null,
          child: Text(widget.title),
        ),
      ],
    ),
  );
}
