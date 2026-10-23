part of 'contribution_flow_screen.dart';

class _NativeContributionAppBar extends StatelessWidget {
  const _NativeContributionAppBar({required this.title, required this.onBack});

  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CollectSpacing.x2,
        CollectSpacing.x2,
        CollectSpacing.x4,
        CollectSpacing.x2,
      ),
      child: Row(
        children: [
          SizedBox.square(
            dimension: CollectSpacing.target,
            child: IconButton(
              tooltip: 'Back',
              onPressed: onBack,
              icon: const Icon(CollectIcons.back),
            ),
          ),
          CollectSpacing.gapW8,
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: colors.textPrimary,
                fontWeight: CollectTypography.weightBold,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _NativeAmountEntry extends StatelessWidget {
  const _NativeAmountEntry({
    required this.controller,
    required this.focusNode,
    required this.errorText,
    required this.onSubmitted,
    required this.onPreset,
    required this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String? errorText;
  final VoidCallback onSubmitted;
  final ValueChanged<int> onPreset;
  final VoidCallback onChanged;

  static const _presets = [1000, 2000, 5000, 10000];

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final l10n = CollectLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.text('howMuch'),
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            color: colors.textPrimary,
            fontWeight: CollectTypography.weightBold,
          ),
        ),
        CollectSpacing.gap24,
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: CollectSpacing.x5,
            vertical: CollectSpacing.x3,
          ),
          decoration: BoxDecoration(
            color: colors.surfaceReadable,
            borderRadius: CollectRadius.cardLargeBorder,
          ),
          child: ContributionAmountInput(
            controller: controller,
            focusNode: focusNode,
            label: l10n.text('contributionAmount'),
            errorText: errorText,
            onChanged: onChanged,
            onSubmitted: onSubmitted,
          ),
        ),
        CollectSpacing.gap20,
        Text(
          l10n.text('quickAmounts'),
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: colors.textMuted,
            fontWeight: CollectTypography.weightSemibold,
          ),
        ),
        CollectSpacing.gap12,
        Wrap(
          spacing: CollectSpacing.x2,
          runSpacing: CollectSpacing.x2,
          children: [
            for (final amount in _presets)
              _NativeAmountPreset(
                amount: amount,
                selected:
                    controller.text.replaceAll(',', '') == amount.toString(),
                onTap: () => onPreset(amount),
              ),
          ],
        ),
      ],
    );
  }
}

class _PaymentHelpSheet extends ConsumerStatefulWidget {
  const _PaymentHelpSheet({
    required this.intent,
    required this.groupTitle,
    required this.repository,
    required this.isCurrent,
  });
  final PaymentIntentModel intent;
  final String groupTitle;
  final CollectRepository repository;
  final bool Function() isCurrent;
  @override
  ConsumerState<_PaymentHelpSheet> createState() => _PaymentHelpSheetState();
}

class _PaymentHelpSheetState extends ConsumerState<_PaymentHelpSheet> {
  final _reference = TextEditingController(), _note = TextEditingController();
  PaymentHelpCheckpoint? _attempt;
  String? _error;
  bool _busy = false, _restoring = true, _recoveryFailed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_restore());
  }

  Future<void> _restore() async {
    if (!widget.isCurrent()) return;
    setState(() {
      _restoring = true;
      _error = null;
    });
    try {
      final saved = await widget.repository.paymentHelpForIntent(
        widget.intent.id,
      );
      if (!mounted || !widget.isCurrent()) return;
      setState(() {
        _attempt = saved;
        _recoveryFailed = false;
      });
    } catch (_) {
      if (mounted && widget.isCurrent()) {
        setState(() {
          _recoveryFailed = true;
          _error =
              'Saved payment help could not be restored. Try again before sending a request.';
        });
      }
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  @override
  void dispose() {
    _reference.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || _restoring || _recoveryFailed || !widget.isCurrent()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final receipt = await widget.repository.requestPaymentHelp(
        intentId: widget.intent.id,
        providerReference: _reference.text,
        note: _note.text,
      );
      if (!mounted || !widget.isCurrent()) return;
      setState(() => _attempt = receipt);
    } catch (error) {
      if (mounted && widget.isCurrent()) {
        try {
          _attempt = await widget.repository.paymentHelpForIntent(
            widget.intent.id,
          );
        } catch (_) {
          _recoveryFailed = true;
        }
        if (!mounted || !widget.isCurrent()) return;
        setState(
          () => _error = error is StateError
              ? error.message
              : 'The result is not confirmed. Retry the same request when connected. Your payment status is unchanged.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(collectRepositoryProvider);
    final current = widget.isCurrent();
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .9,
      ),
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: CollectBottomSheet(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Payment help',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close payment help',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                if (!current)
                  const Text('Account changed. Close and reopen payment help.')
                else ...[
                  Text(
                    '${widget.groupTitle} · ${formatRwf(widget.intent.expectedAmountRwf)}',
                  ),
                  CollectSpacing.gap12,
                  if (_restoring)
                    Semantics(
                      liveRegion: true,
                      child: const Text('Restoring payment help…'),
                    )
                  else if (_recoveryFailed) ...[
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        _error ?? 'Saved payment help could not be restored.',
                      ),
                    ),
                    CollectSpacing.gap16,
                    CollectButton(
                      label: 'Try recovery',
                      onPressed: _restore,
                      expand: true,
                    ),
                  ] else if (_attempt?.received == true) ...[
                    Text(
                      'Request received',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Text(
                      'Your request was saved for review. It does not confirm payment or credit a contribution.',
                    ),
                    CollectSpacing.gap12,
                    SelectableText('Request ID · ${_attempt!.requestId}'),
                  ] else ...[
                    Text(
                      _attempt == null
                          ? 'Ask for a check of this payment request. You can add the provider reference or an evidence note. Your payment status and balances stay unchanged.'
                          : 'Your original details are saved. You can retry this request. Your payment status and balances stay unchanged.',
                    ),
                    if (_attempt == null) ...[
                      TextField(
                        controller: _reference,
                        enabled: !_busy,
                        maxLength: 160,
                        decoration: const InputDecoration(
                          labelText: 'Reference',
                        ),
                      ),
                      TextField(
                        controller: _note,
                        enabled: !_busy,
                        maxLength: 2000,
                        minLines: 2,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: 'Evidence note',
                        ),
                      ),
                    ] else ...[
                      CollectSpacing.gap12,
                      if (_attempt!.reference?.isNotEmpty == true)
                        SelectableText('Reference · ${_attempt!.reference}'),
                      if (_attempt!.note?.isNotEmpty == true)
                        Text(_attempt!.note!),
                    ],
                    if (_error != null) ...[
                      CollectSpacing.gap12,
                      Semantics(liveRegion: true, child: Text(_error!)),
                    ],
                    CollectSpacing.gap16,
                    CollectButton(
                      label: _busy
                          ? 'Sending request'
                          : _attempt != null
                          ? 'Retry request'
                          : 'Request check',
                      onPressed: _busy ? null : _submit,
                      expand: true,
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NativeAmountPreset extends StatelessWidget {
  const _NativeAmountPreset({
    required this.amount,
    required this.selected,
    required this.onTap,
  });

  final int amount;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Semantics(
      button: true,
      selected: selected,
      label: 'RWF $amount',
      child: Material(
        color: selected ? colors.textPrimary : colors.surfaceRaised,
        borderRadius: CollectRadius.pillBorder,
        child: InkWell(
          onTap: onTap,
          borderRadius: CollectRadius.pillBorder,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: CollectSpacing.x4,
                vertical: CollectSpacing.x3,
              ),
              child: Text(
                formatRwf(amount).replaceFirst('RWF ', ''),
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: selected ? colors.canvas : colors.textPrimary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NativeAmountReview extends StatelessWidget {
  const _NativeAmountReview({
    required this.amountRwf,
    this.title,
    this.description,
  });

  final int amountRwf;
  final String? title, description;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final l10n = CollectLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title ?? l10n.text('reviewContribution'),
          style:
              (MediaQuery.textScalerOf(context).scale(1) >= 1.3
                      ? Theme.of(context).textTheme.titleLarge
                      : Theme.of(context).textTheme.headlineMedium)
                  ?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: CollectTypography.weightBold,
                  ),
        ),
        CollectSpacing.gap8,
        Text(
          description ?? l10n.text('youWillContribute'),
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
        ),
        CollectSpacing.gap16,
        ContributionAmountValue(amountRwf: amountRwf),
      ],
    );
  }
}

class _NativeMomoReceiverTile extends StatelessWidget {
  const _NativeMomoReceiverTile({required this.name, required this.receiver});

  final String name;
  final String receiver;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Semantics(
      container: true,
      label: receiver.isEmpty ? name : '$name, $receiver',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.all(CollectSpacing.x4),
          decoration: BoxDecoration(
            color: colors.surfaceReadable,
            borderRadius: CollectRadius.cardLargeBorder,
          ),
          child: Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.statusBackground(CollectStatusTone.info),
                  border: Border.all(
                    color: CollectRuntimeTokens.badgeBorder(
                      colors,
                      colors.statusForeground(CollectStatusTone.info),
                    ),
                  ),
                ),
                child: SizedBox.square(
                  dimension: 48,
                  child: Icon(
                    CollectIcons.momo,
                    color: colors.statusForeground(CollectStatusTone.info),
                    size: 23,
                  ),
                ),
              ),
              CollectSpacing.gapW12,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(
                                  color: colors.textPrimary,
                                  fontWeight: CollectTypography.weightBold,
                                ),
                          ),
                        ),
                        CollectSpacing.gapW4,
                        Icon(
                          CollectIcons.check,
                          size: 17,
                          color: colors.textSecondary,
                        ),
                      ],
                    ),
                    if (receiver.isNotEmpty) ...[
                      CollectSpacing.gap4,
                      Text(
                        receiver,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NativeMomoTrustNote extends StatelessWidget {
  const _NativeMomoTrustNote({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: colors.surfaceRaised,
            shape: BoxShape.circle,
          ),
          child: Icon(CollectIcons.lock, size: 18, color: colors.textPrimary),
        ),
        CollectSpacing.gapW12,
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: CollectTypography.weightBold,
                ),
              ),
              CollectSpacing.gap4,
              Text(
                message,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colors.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _NativeMomoStatus extends StatelessWidget {
  const _NativeMomoStatus({
    required this.title,
    required this.message,
    this.isError = false,
  });

  final String title;
  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Semantics(
      container: true,
      liveRegion: true,
      label: '$title. $message',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.all(CollectSpacing.x4),
          decoration: BoxDecoration(
            color: isError ? colors.dangerContainer : colors.infoContainer,
            borderRadius: CollectRadius.cardBorder,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                isError ? CollectIcons.warning : CollectIcons.sms,
                size: 20,
                color: isError
                    ? colors.dangerForeground
                    : colors.infoForeground,
              ),
              CollectSpacing.gapW12,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleSmall),
                    CollectSpacing.gap4,
                    Text(message, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NativeContributionBottomBar extends StatelessWidget {
  const _NativeContributionBottomBar({
    required this.primaryLabel,
    required this.primaryIcon,
    required this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
  });

  final String primaryLabel;
  final IconData primaryIcon;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return DecoratedBox(
      decoration: BoxDecoration(color: colors.canvas),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          CollectSpacing.x5,
          CollectSpacing.x3,
          CollectSpacing.x5,
          CollectSpacing.x4,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CollectButton(
              label: primaryLabel,
              icon: primaryIcon,
              onPressed: onPrimary,
              expand: true,
            ),
            if (secondaryLabel != null) ...[
              CollectSpacing.gap8,
              CollectButton(
                label: secondaryLabel!,
                onPressed: onSecondary,
                variant: CollectButtonVariant.subtle,
                expand: true,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
