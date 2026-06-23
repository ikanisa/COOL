part of 'payment_status_screens.dart';

class PaymentSupportReviewScreen extends ConsumerStatefulWidget {
  const PaymentSupportReviewScreen({
    required this.collectionId,
    required this.intentId,
    super.key,
  });

  final String collectionId;
  final String intentId;

  @override
  ConsumerState<PaymentSupportReviewScreen> createState() =>
      _PaymentSupportReviewScreenState();
}

class _PaymentSupportReviewScreenState
    extends ConsumerState<PaymentSupportReviewScreen> {
  final _note = TextEditingController();
  String _issueType = 'Missing confirmation';
  bool _submitting = false;
  bool _submitted = false;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.read(collectRepositoryProvider.notifier);
    final collection = _safeCollection(ref, widget.collectionId);
    final intent = _safeIntent(repo, widget.intentId);
    return ScreenScaffold(
      title: 'Payment review',
      subtitle: collection?.title,
      bottomAction: BottomActionSurface(
        children: [
          CollectButton(
            label: _submitted
                ? 'Open ledger'
                : _submitting
                ? 'Submitting'
                : 'Submit review',
            icon: _submitted ? CollectIcons.ledger : CollectIcons.support,
            onPressed: _submitting
                ? null
                : _submitted
                ? () => context.go('/groups/${widget.collectionId}/ledger')
                : _submit,
            expand: true,
          ),
          CollectButton(
            label: 'Payment status',
            icon: CollectIcons.pending,
            onPressed: () => context.go(
              '/groups/${widget.collectionId}/pay/${widget.intentId}',
            ),
            variant: CollectButtonVariant.secondary,
            expand: true,
          ),
        ],
      ),
      children: [
        if (_submitted)
          const MinimalStatePanel(
            icon: CollectIcons.check,
            title: 'Review submitted.',
            message:
                'Support can review the payment without public confirmation text or payment credentials.',
            tone: CollectStatusTone.success,
          )
        else ...[
          MinimalStatePanel(
            icon: CollectIcons.support,
            title: 'Safe note',
            message: intent == null
                ? 'This payment is not on this device. Support can still review the group context.'
                : 'Amount ${formatRwf(intent.expectedAmountRwf)} is ${paymentStatusLabel(intent.status).toLowerCase()}.',
            tone: CollectStatusTone.warning,
          ),
          CollectCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Safe note',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                CollectSpacing.gap8,
                Text(
                  'Issue type',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                CollectSpacing.gap8,
                Wrap(
                  spacing: CollectSpacing.x2,
                  runSpacing: CollectSpacing.x2,
                  children: [
                    for (final issue in const [
                      'Missing confirmation',
                      'Wrong amount',
                      'Duplicate payment',
                      'Other',
                    ])
                      ChoiceChip(
                        label: Text(issue),
                        selected: _issueType == issue,
                        onSelected: (_) => setState(() => _issueType = issue),
                      ),
                  ],
                ),
                CollectSpacing.gap16,
                CollectTextInput(
                  controller: _note,
                  label: 'Safe note',
                  helper:
                      'Do not paste payment credentials or full message text.',
                  maxLines: 4,
                  textInputAction: TextInputAction.newline,
                  textCapitalization: TextCapitalization.sentences,
                  autocorrect: true,
                ),
              ],
            ),
          ),
          if (_error != null)
            InfoSecurityBanner(
              title: 'Review failed',
              message: _error!,
              tone: CollectStatusTone.warning,
            ),
        ],
      ],
    );
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref
          .read(collectRepositoryProvider.notifier)
          .createPaymentSupportReview(
            collectionId: widget.collectionId,
            intentId: widget.intentId,
            issueType: _issueType,
            note: _note.text,
          );
      if (mounted) setState(() => _submitted = true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}

class FreshLinkRequestScreen extends ConsumerStatefulWidget {
  const FreshLinkRequestScreen({required this.slug, super.key});

  final String slug;

  @override
  ConsumerState<FreshLinkRequestScreen> createState() =>
      _FreshLinkRequestScreenState();
}

class _FreshLinkRequestScreenState
    extends ConsumerState<FreshLinkRequestScreen> {
  final _reason = TextEditingController();
  bool _submitting = false;
  bool _submitted = false;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScreenScaffold(
      title: 'Fresh link',
      bottomAction: BottomActionSurface(
        children: [
          CollectButton(
            label: _submitted
                ? 'Open groups'
                : _submitting
                ? 'Requesting'
                : 'Request fresh link',
            icon: _submitted ? CollectIcons.collections : CollectIcons.sync,
            onPressed: _submitting
                ? null
                : _submitted
                ? () => context.go('/groups')
                : _submit,
            expand: true,
          ),
          CollectButton(
            label: 'Scan QR',
            icon: CollectIcons.qr,
            onPressed: () => context.go('/groups/scan'),
            variant: CollectButtonVariant.secondary,
            expand: true,
          ),
        ],
      ),
      children: [
        MinimalStatePanel(
          icon: _submitted ? CollectIcons.check : CollectIcons.sync,
          title: _submitted ? 'Request sent.' : 'Ask for a fresh group link.',
          message: _submitted
              ? 'Support can help the group owner issue a new privacy-safe link.'
              : 'Expired links do not reveal receiver information. Ask support or the group owner for a new link.',
          tone: _submitted ? CollectStatusTone.success : CollectStatusTone.info,
        ),
        if (!_submitted)
          FormSectionCard(
            errorTitle: 'Request failed',
            errorMessage: _error,
            children: [
              CollectTextInput(
                controller: _reason,
                label: 'Reason, optional',
                maxLines: 3,
                textInputAction: TextInputAction.newline,
                textCapitalization: TextCapitalization.sentences,
                autocorrect: true,
              ),
            ],
          ),
      ],
    );
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref
          .read(collectRepositoryProvider.notifier)
          .requestFreshGroupLink(slug: widget.slug, reason: _reason.text);
      if (mounted) setState(() => _submitted = true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}
