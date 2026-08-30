part of 'admin_runtime.dart';

class _AdminBankQueueActions extends ConsumerWidget {
  const _AdminBankQueueActions({required this.rpcName, required this.onDone});

  final String rpcName;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identity = ref.watch(adminIdentityProvider).valueOrNull;
    final actions = <Widget>[];

    if (rpcName == 'admin_list_bank_destinations') {
      if (_adminHasPermission(identity, 'bank_details.propose')) {
        actions.add(
          FilledButton.icon(
            onPressed: () => _proposeDestination(context, ref),
            icon: const Icon(Icons.add_business_outlined),
            label: const Text('Propose bank details'),
          ),
        );
      }
      actions.add(
        OutlinedButton.icon(
          onPressed: () => context.go('/admin/bank-destination-requests'),
          icon: const Icon(Icons.fact_check_outlined),
          label: const Text('Approval queue'),
        ),
      );
    } else if (rpcName == 'admin_list_bank_destination_change_requests') {
      actions.add(
        OutlinedButton.icon(
          onPressed: () => context.go('/admin/bank-destinations'),
          icon: const Icon(Icons.account_balance_outlined),
          label: const Text('Bank details'),
        ),
      );
    } else if (rpcName == 'admin_list_bank_transactions' &&
        _adminHasPermission(identity, 'bank_allocations.propose')) {
      actions.add(
        FilledButton.icon(
          onPressed: () => _proposeAllocation(context, ref),
          icon: const Icon(Icons.rule_outlined),
          label: const Text('Propose manual allocation'),
        ),
      );
    } else if (rpcName == 'admin_list_reconciliation_runs' &&
        _adminHasPermission(identity, 'bank_reconciliation.manage')) {
      actions
        ..add(
          FilledButton.icon(
            onPressed: () => _importStatement(context, ref),
            icon: const Icon(Icons.upload_file_outlined),
            label: const Text('Import bank statement'),
          ),
        )
        ..add(
          OutlinedButton.icon(
            onPressed: () => _runReconciliation(context, ref),
            icon: const Icon(Icons.balance_outlined),
            label: const Text('Run reconciliation'),
          ),
        );
    }

    if (actions.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        label: 'Bank transfer queue actions',
        child: Wrap(spacing: 12, runSpacing: 12, children: actions),
      ),
    );
  }

  Future<void> _proposeDestination(BuildContext context, WidgetRef ref) async {
    final beneficiary = TextEditingController();
    final iban = TextEditingController();
    final bic = TextEditingController();
    final bank = TextEditingController();
    final reason = TextEditingController();
    var supportsInstant = true;
    final submitted = await showDialog<bool>(
      context: context,
      animationStyle: CollectMotion.animationStyle(context),
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Propose EUR beneficiary'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: beneficiary,
                    decoration: const InputDecoration(
                      labelText: 'Beneficiary name',
                    ),
                  ),
                  TextField(
                    controller: iban,
                    autocorrect: false,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(labelText: 'IBAN'),
                  ),
                  TextField(
                    controller: bic,
                    autocorrect: false,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(labelText: 'BIC / SWIFT'),
                  ),
                  TextField(
                    controller: bank,
                    decoration: const InputDecoration(labelText: 'Bank name'),
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: supportsInstant,
                    onChanged: (value) =>
                        setDialogState(() => supportsInstant = value),
                    title: const Text('SEPA Instant supported'),
                  ),
                  TextField(
                    controller: reason,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Change reason',
                      helperText:
                          'At least 8 characters. A checker must approve.',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Submit proposal'),
            ),
          ],
        ),
      ),
    );
    if (submitted != true) {
      beneficiary.dispose();
      iban.dispose();
      bic.dispose();
      bank.dispose();
      reason.dispose();
      return;
    }
    try {
      await ref
          .read(adminRepositoryProvider)
          .action('admin_propose_bank_destination', {
            'p_beneficiary_name': beneficiary.text,
            'p_iban': iban.text,
            'p_bic': bic.text,
            'p_bank_name': bank.text,
            'p_supports_instant': supportsInstant,
            'p_reason': reason.text,
          });
      onDone();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bank details sent to the independent approval queue'),
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      _showBankActionError(context, error);
    } finally {
      beneficiary.dispose();
      iban.dispose();
      bic.dispose();
      bank.dispose();
      reason.dispose();
    }
  }

  Future<void> _proposeAllocation(BuildContext context, WidgetRef ref) async {
    final transactionId = TextEditingController();
    final intentId = TextEditingController();
    final reason = TextEditingController();
    final submitted = await showDialog<bool>(
      context: context,
      animationStyle: CollectMotion.animationStyle(context),
      builder: (dialogContext) => AlertDialog(
        title: const Text('Propose manual allocation'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: transactionId,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Bank transaction UUID',
                ),
              ),
              TextField(
                controller: intentId,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Transfer request UUID',
                ),
              ),
              TextField(
                controller: reason,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Allocation reason',
                  helperText:
                      'Amount and currency must match exactly. A checker must approve.',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Submit proposal'),
          ),
        ],
      ),
    );
    if (submitted != true) {
      transactionId.dispose();
      intentId.dispose();
      reason.dispose();
      return;
    }
    try {
      await ref
          .read(adminRepositoryProvider)
          .action('admin_propose_bank_allocation', {
            'p_bank_transaction_id': transactionId.text.trim(),
            'p_bank_transfer_intent_id': intentId.text.trim(),
            'p_reason': reason.text,
          });
      onDone();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Allocation sent for checker approval')),
      );
    } catch (error) {
      if (!context.mounted) return;
      _showBankActionError(context, error);
    } finally {
      transactionId.dispose();
      intentId.dispose();
      reason.dispose();
    }
  }

  Future<void> _runReconciliation(BuildContext context, WidgetRef ref) async {
    final runDate = TextEditingController(text: _bankDate(DateTime.now()));
    final reason = TextEditingController();
    final submitted = await _showDatedReasonDialog(
      context,
      title: 'Run daily reconciliation',
      actionLabel: 'Run reconciliation',
      dateController: runDate,
      reasonController: reason,
    );
    if (!submitted) {
      runDate.dispose();
      reason.dispose();
      return;
    }
    try {
      await ref.read(adminRepositoryProvider).action(
        'admin_run_bank_reconciliation',
        {'p_run_date': runDate.text.trim(), 'p_reason': reason.text},
      );
      onDone();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Daily reconciliation completed')),
      );
    } catch (error) {
      if (!context.mounted) return;
      _showBankActionError(context, error);
    } finally {
      runDate.dispose();
      reason.dispose();
    }
  }

  Future<void> _importStatement(BuildContext context, WidgetRef ref) async {
    final fileName = TextEditingController();
    final periodStart = TextEditingController(text: _bankDate(DateTime.now()));
    final periodEnd = TextEditingController(text: _bankDate(DateTime.now()));
    final content = TextEditingController();
    final reason = TextEditingController();
    var format = 'csv';
    final submitted = await showDialog<bool>(
      context: context,
      animationStyle: CollectMotion.animationStyle(context),
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Import EUR bank statement'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720, maxHeight: 680),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: fileName,
                    decoration: const InputDecoration(
                      labelText: 'Original file name',
                    ),
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: format,
                    decoration: const InputDecoration(labelText: 'Format'),
                    items: const [
                      DropdownMenuItem(value: 'csv', child: Text('CSV')),
                      DropdownMenuItem(value: 'json', child: Text('JSON')),
                      DropdownMenuItem(value: 'mt940', child: Text('MT940')),
                      DropdownMenuItem(
                        value: 'camt053',
                        child: Text('CAMT.053'),
                      ),
                    ],
                    onChanged: (value) =>
                        setDialogState(() => format = value ?? format),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: periodStart,
                          decoration: const InputDecoration(
                            labelText: 'Period start (YYYY-MM-DD)',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: periodEnd,
                          decoration: const InputDecoration(
                            labelText: 'Period end (YYYY-MM-DD)',
                          ),
                        ),
                      ),
                    ],
                  ),
                  TextField(
                    controller: content,
                    minLines: 8,
                    maxLines: 16,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Statement content',
                      helperText:
                          'Paste the exact bank-export content. Imports are hash-deduplicated.',
                    ),
                  ),
                  TextField(
                    controller: reason,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Import reason',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Import and reconcile'),
            ),
          ],
        ),
      ),
    );
    if (submitted != true) {
      fileName.dispose();
      periodStart.dispose();
      periodEnd.dispose();
      content.dispose();
      reason.dispose();
      return;
    }
    try {
      final client = ref.read(supabaseClientProvider);
      if (client == null) throw StateError('Supabase is not configured.');
      await client.functions.invoke(
        'ingest-bank-statement',
        body: {
          'file_name': fileName.text,
          'format': format,
          'content': content.text,
          'period_start': periodStart.text,
          'period_end': periodEnd.text,
          'reason': reason.text,
        },
      );
      onDone();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Statement imported and reconciled')),
      );
    } catch (error) {
      if (!context.mounted) return;
      _showBankActionError(context, error);
    } finally {
      fileName.dispose();
      periodStart.dispose();
      periodEnd.dispose();
      content.dispose();
      reason.dispose();
    }
  }
}

class _AdminBankDetailActions extends ConsumerWidget {
  const _AdminBankDetailActions({
    required this.rpcName,
    required this.id,
    required this.data,
  });

  final String rpcName;
  final String id;
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identity = ref.watch(adminIdentityProvider).valueOrNull;
    Widget? child;
    if (rpcName == 'admin_get_bank_destination_change_request' &&
        data['status'] == 'pending' &&
        _adminHasPermission(identity, 'bank_details.approve')) {
      child = _AdminBankReviewButtons(
        approveLabel: 'Approve and activate',
        rejectLabel: 'Reject proposal',
        onReview: (approved) => _reviewDestination(context, ref, approved),
      );
    } else if (rpcName == 'admin_get_bank_allocation_request' &&
        data['status'] == 'pending' &&
        _adminHasPermission(identity, 'bank_allocations.approve')) {
      child = _AdminBankReviewButtons(
        approveLabel: 'Approve allocation',
        rejectLabel: 'Reject allocation',
        onReview: (approved) => _reviewAllocation(context, ref, approved),
      );
    } else if (rpcName == 'admin_get_reconciliation_exception' &&
        const {'open', 'reviewing'}.contains(data['status']) &&
        _adminHasPermission(identity, 'bank_reconciliation.manage')) {
      child = _AdminBankReviewButtons(
        approveLabel: 'Resolve exception',
        rejectLabel: 'Dismiss exception',
        onReview: (resolved) => _resolveException(context, ref, !resolved),
      );
    } else if (rpcName == 'admin_get_bank_evidence') {
      child = _adminHasPermission(identity, 'bank_evidence.raw.reveal')
          ? AdminSensitiveDataGate(
              label: 'Raw bank evidence',
              onReveal: (reason) async {
                final response = await ref.read(adminRepositoryProvider).action(
                  'admin_reveal_raw_bank_evidence',
                  {'p_event_id': id, 'p_reason': reason},
                );
                final body = response['body']?.toString() ?? '';
                final sender = response['sender']?.toString() ?? 'Bank';
                return '$sender\n$body';
              },
            )
          : const AdminEmptyState(
              title: 'Raw evidence restricted',
              message: 'A separately audited reveal permission is required.',
            );
    } else if (rpcName == 'admin_get_reconciliation_run' &&
        _adminHasPermission(identity, 'bank_reconciliation.manage')) {
      final dailyClose = data['daily_close'];
      if (dailyClose is Map &&
          const {'balanced', 'exception'}.contains(dailyClose['status'])) {
        child = OutlinedButton.icon(
          onPressed: () =>
              _reopenClose(context, ref, dailyClose['id']?.toString() ?? ''),
          icon: const Icon(Icons.lock_open_outlined),
          label: const Text('Reopen daily close'),
        );
      }
    }
    if (child == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: _AdminBankActionPanel(child: child),
    );
  }

  Future<void> _reviewDestination(
    BuildContext context,
    WidgetRef ref,
    bool approved,
  ) async {
    final note = await showAdminReasonDialog(
      context,
      title: approved ? 'Approve bank details' : 'Reject bank details',
      actionLabel: approved ? 'Approve and activate' : 'Reject',
    );
    if (note == null) return;
    if (!context.mounted) return;
    await _perform(
      context,
      ref,
      'admin_review_bank_destination_change',
      {'p_request_id': id, 'p_approve': approved, 'p_review_note': note},
      approved ? 'Bank details activated' : 'Bank proposal rejected',
    );
  }

  Future<void> _reviewAllocation(
    BuildContext context,
    WidgetRef ref,
    bool approved,
  ) async {
    final note = await showAdminReasonDialog(
      context,
      title: approved ? 'Approve allocation' : 'Reject allocation',
      actionLabel: approved ? 'Approve allocation' : 'Reject',
    );
    if (note == null) return;
    if (!context.mounted) return;
    await _perform(
      context,
      ref,
      'admin_review_bank_allocation',
      {'p_request_id': id, 'p_approve': approved, 'p_review_note': note},
      approved ? 'Allocation approved' : 'Allocation rejected',
    );
  }

  Future<void> _resolveException(
    BuildContext context,
    WidgetRef ref,
    bool dismiss,
  ) async {
    final note = await showAdminReasonDialog(
      context,
      title: dismiss ? 'Dismiss exception' : 'Resolve exception',
      actionLabel: dismiss ? 'Dismiss' : 'Resolve',
    );
    if (note == null) return;
    if (!context.mounted) return;
    await _perform(
      context,
      ref,
      'admin_resolve_reconciliation_exception',
      {'p_exception_id': id, 'p_resolution_note': note, 'p_dismiss': dismiss},
      dismiss ? 'Exception dismissed' : 'Exception resolved',
    );
  }

  Future<void> _reopenClose(
    BuildContext context,
    WidgetRef ref,
    String closeId,
  ) async {
    if (closeId.isEmpty) return;
    final reason = await showAdminReasonDialog(
      context,
      title: 'Reopen daily close',
      actionLabel: 'Reopen',
    );
    if (reason == null) return;
    if (!context.mounted) return;
    await _perform(context, ref, 'admin_reopen_daily_bank_close', {
      'p_close_id': closeId,
      'p_reason': reason,
    }, 'Daily close reopened');
  }

  Future<void> _perform(
    BuildContext context,
    WidgetRef ref,
    String rpcName,
    Map<String, dynamic> params,
    String success,
  ) async {
    try {
      await ref.read(adminRepositoryProvider).action(rpcName, params);
      ref.read(adminRealtimeTickProvider.notifier).state += 1;
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(success)));
    } catch (error) {
      _showBankActionError(context, error);
    }
  }
}

class _AdminBankActionPanel extends StatelessWidget {
  const _AdminBankActionPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceReadable.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: colors.borderAccent),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Semantics(
          container: true,
          explicitChildNodes: true,
          label: 'Controlled bank operation',
          child: child,
        ),
      ),
    );
  }
}

class _AdminBankReviewButtons extends StatelessWidget {
  const _AdminBankReviewButtons({
    required this.approveLabel,
    required this.rejectLabel,
    required this.onReview,
  });

  final String approveLabel;
  final String rejectLabel;
  final ValueChanged<bool> onReview;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        FilledButton.icon(
          onPressed: () => onReview(true),
          icon: const Icon(Icons.check_circle_outline),
          label: Text(approveLabel),
        ),
        OutlinedButton.icon(
          onPressed: () => onReview(false),
          icon: const Icon(Icons.cancel_outlined),
          label: Text(rejectLabel),
        ),
      ],
    );
  }
}

Future<bool> _showDatedReasonDialog(
  BuildContext context, {
  required String title,
  required String actionLabel,
  required TextEditingController dateController,
  required TextEditingController reasonController,
}) async {
  return await showDialog<bool>(
        context: context,
        animationStyle: CollectMotion.animationStyle(context),
        builder: (dialogContext) => AlertDialog(
          title: Text(title),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: dateController,
                  decoration: const InputDecoration(
                    labelText: 'Run date (YYYY-MM-DD)',
                  ),
                ),
                TextField(
                  controller: reasonController,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Reason',
                    helperText: 'At least 8 characters.',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(actionLabel),
            ),
          ],
        ),
      ) ??
      false;
}

String _bankDate(DateTime date) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${date.year}-${two(date.month)}-${two(date.day)}';
}

void _showBankActionError(BuildContext context, Object error) {
  if (!context.mounted) return;
  final raw = error.toString();
  final safe = raw
      .replaceAll(RegExp(r'https?://\S+'), '[endpoint]')
      .replaceAll(RegExp(r'eyJ[A-Za-z0-9._-]+'), '[token]');
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        safe.length > 240
            ? 'The controlled bank operation failed. Review the fields and try again.'
            : safe,
      ),
    ),
  );
}
