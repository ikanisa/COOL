part of 'admin_runtime.dart';

typedef AdminReceiptDeferralQuery = ({
  String exceptionId,
  AdminExceptionSource source,
  String sourceId,
  int minimumRevision,
});

final adminReceiptDeferralEvidenceProvider = FutureProvider.autoDispose
    .family<AdminReceiptDeferralEvidence, AdminReceiptDeferralQuery>((
      ref,
      query,
    ) async {
      final session = ref.watch(adminAuthSessionScopeProvider);
      ref.watch(_adminIdentityRevisionProvider);
      final repository = ref.watch(adminRepositoryProvider);
      var current = true;
      ref.onDispose(() => current = false);
      final identity = await ref.watch(adminIdentityProvider.future);
      if (!current) throw const AdminSessionChanged();
      if (session == null ||
          identity?.userId != session.key.userId ||
          !_exceptionCanRead(identity) ||
          !query.source.isReceiptDeferral) {
        throw const AdminExceptionDenied();
      }
      final raw = await repository
          .receiptDeferralEvidence(query.exceptionId)
          .timeout(const Duration(seconds: 15));
      if (!current) throw const AdminSessionChanged();
      final evidence = AdminReceiptDeferralEvidence.parse(
        raw,
        query.exceptionId,
      );
      if (evidence.source != query.source ||
          evidence.sourceId != query.sourceId ||
          evidence.revision < query.minimumRevision) {
        exceptionInvalid();
      }
      return evidence;
    });

Future<void> _showAdminReceiptDeferralEvidence(
  BuildContext context,
  _AdminActionScope scope,
  AdminExceptionRow row,
) async {
  if (!scope.isCurrent || !row.source.isReceiptDeferral) return;
  await _showAdminFormDialog<void>(
    context: context,
    builder: (dialogContext) => _AdminSessionDialog(
      scope: scope,
      child: Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AdminReceiptDeferralCard(
                    row: row,
                    onOpenReceipt: (receiptId) {
                      if (!scope.isCurrent) return;
                      final router = GoRouter.of(context);
                      Navigator.pop(dialogContext);
                      router.go('/admin/sms-receipts/$receiptId');
                    },
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('Close receipt evidence'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class AdminReceiptDeferralCard extends ConsumerStatefulWidget {
  const AdminReceiptDeferralCard({
    required this.row,
    this.onOpenReceipt,
    super.key,
  });
  final AdminExceptionRow row;
  final ValueChanged<String>? onOpenReceipt;
  @override
  ConsumerState<AdminReceiptDeferralCard> createState() =>
      _AdminReceiptDeferralCardState();
}

class _AdminReceiptDeferralCardState
    extends ConsumerState<AdminReceiptDeferralCard> {
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
    final session = ref.watch(adminAuthSessionScopeProvider);
    final identityState = ref.watch(adminIdentityProvider);
    final identity = _adminResolvedIdentity(identityState);
    if (identityState.isLoading) {
      return const Text('Checking receipt evidence access…');
    }
    if (session == null ||
        identity?.userId != session.key.userId ||
        !_exceptionCanRead(identity) ||
        !widget.row.source.isReceiptDeferral) {
      return const Text('Current receipt exception access is required.');
    }
    final query = (
      exceptionId: widget.row.id,
      source: widget.row.source,
      sourceId: widget.row.sourceId,
      minimumRevision: widget.row.revision,
    );
    final state = ref.watch(adminReceiptDeferralEvidenceProvider(query));
    final evidence = state.isLoading ? null : state.asData?.value;
    final fresh = evidence?.isFresh(ref.watch(adminClockProvider)()) == true;
    final scope = _AdminActionScope(ref);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            'Receipt work evidence',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'This records receipt business handling. Message transport and delivery require separate attempt and callback evidence.',
        ),
        const SizedBox(height: 12),
        if (state.isLoading)
          const Text('Checking the current receipt source…')
        else if (state.hasError)
          const Text(
            'Receipt evidence could not be verified. Refresh and check current access.',
          )
        else if (!fresh)
          const Text(
            'Receipt evidence expired. Refresh its source before using links.',
          )
        else if (evidence != null) ...[
          Text(evidence.dispositionLabel),
          Text(
            evidence.businessHandled
                ? 'Business handling: durably recorded'
                : 'Business handling: not durably recorded',
          ),
          Text(
            evidence.active
                ? 'Recorded exception: active'
                : 'Recorded exception: cleared',
          ),
          Text(
            '${evidence.source.label} · exception revision ${evidence.revision}',
          ),
          if (evidence.sourceVersion != null)
            Text(
              'Source version ${evidence.sourceVersion} · ${evidence.eventKind}',
            ),
          if (evidence.originalLabel != null)
            Text('Original result: ${evidence.originalLabel}'),
          if (evidence.currentLabel != null)
            Text('Current result: ${evidence.currentLabel}'),
          Text('Checked ${_exceptionTime(evidence.checkedAt)}'),
          const SizedBox(height: 12),
          if (evidence.receiptId != null)
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () {
                  if (!scope.isCurrent ||
                      !evidence.isFresh(ref.read(adminClockProvider)())) {
                    if (mounted) setState(() {});
                    return;
                  }
                  if (widget.onOpenReceipt != null) {
                    widget.onOpenReceipt!(evidence.receiptId!);
                  } else {
                    context.go('/admin/sms-receipts/${evidence.receiptId}');
                  }
                },
                icon: const Icon(Icons.open_in_new_outlined),
                label: const Text('Open recorded SMS receipt'),
              ),
            ),
          const Text('Source ID'),
          SelectableText(evidence.sourceId),
        ],
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: state.isLoading
                ? null
                : () => ref.invalidate(
                    adminReceiptDeferralEvidenceProvider(query),
                  ),
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh receipt evidence'),
          ),
        ),
      ],
    );
  }
}
