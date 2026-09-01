import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/payments/revolut_launcher.dart';
import '../../core/payments/momo_ussd_launcher.dart';
import '../../core/utils/money_format.dart';
import '../../shared/models/collect_models.dart';
import '../../shared/repositories/collect_repository.dart';
import '../../shared/widgets/collect_components.dart';
import '../../shared/widgets/screen_scaffold.dart';
import '../collections/group_empty_state.dart';

class ContributionFlowScreen extends ConsumerWidget {
  const ContributionFlowScreen({required this.collectionId, super.key});

  final String collectionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(collectRepositoryProvider).currentProfile;
    return profile?.isRwanda == true
        ? _RwandaMomoContributionFlow(collectionId: collectionId)
        : _DiasporaBankContributionFlow(collectionId: collectionId);
  }
}

class _RwandaMomoContributionFlow extends ConsumerStatefulWidget {
  const _RwandaMomoContributionFlow({required this.collectionId});

  final String collectionId;

  @override
  ConsumerState<_RwandaMomoContributionFlow> createState() =>
      _RwandaMomoContributionFlowState();
}

class _RwandaMomoContributionFlowState
    extends ConsumerState<_RwandaMomoContributionFlow> {
  final _amount = TextEditingController();
  PaymentIntentModel? _intent;
  bool _working = false;
  bool _ussdOpened = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repository = ref.read(collectRepositoryProvider.notifier);
    final collection = repository.maybeCollectionById(widget.collectionId);
    if (collection == null) return const MissingGroupStateScreen();
    if (collection.isArchived) {
      return ArchivedGroupStateScreen(
        collectionId: widget.collectionId,
        groupTitle: collection.title,
      );
    }
    final profile = ref.watch(collectRepositoryProvider).currentProfile;
    final isMember =
        profile != null &&
        (collection.creatorUserId == profile.id ||
            collection.isCurrentUserMember);
    if (!collection.isPublic && !isMember) {
      return ScreenScaffold(
        title: 'Join required',
        subtitle: collection.title,
        compact: true,
        children: [
          MinimalStatePanel(
            icon: CollectIcons.people,
            title: 'Join this group before contributing.',
            message:
                'Membership links your MoMo receipt to the correct private group ledger.',
            tone: CollectStatusTone.warning,
            primaryAction: CollectButton(
              label: 'Open group',
              icon: CollectIcons.arrowForward,
              onPressed: () => context.go('/groups/${widget.collectionId}'),
              expand: true,
            ),
          ),
        ],
      );
    }
    final receiver =
        _intent?.receiverMomoNumber ?? collection.receiverMomoNumber ?? '';
    return ScreenScaffold(
      title: _intent == null ? 'MoMo contribution' : 'Confirm in MoMo',
      subtitle: collection.title,
      compact: true,
      bottomAction: BottomActionSurface(
        children: [
          if (_intent == null)
            CollectButton(
              label: _working ? 'Preparing MoMo' : 'Continue to MoMo',
              icon: CollectIcons.arrowForward,
              onPressed: _working ? null : _prepare,
              expand: true,
            )
          else
            CollectButton(
              label: _working ? 'Opening MoMo' : 'Open MoMo USSD',
              icon: CollectIcons.momo,
              onPressed: _working ? null : _openUssd,
              expand: true,
            ),
          if (_intent != null)
            CollectButton(
              label: 'Edit amount',
              icon: CollectIcons.tune,
              onPressed: _working
                  ? null
                  : () => setState(() {
                      _intent = null;
                      _ussdOpened = false;
                      _error = null;
                    }),
              variant: CollectButtonVariant.secondary,
              expand: true,
            ),
        ],
      ),
      children: [
        _ContributionHeader(
          title: collection.title,
          stepLabel: _intent == null
              ? 'Step 1 of 2 · RWF amount'
              : 'Step 2 of 2 · MoMo approval',
          onBack: () => context.go('/groups/${widget.collectionId}'),
        ),
        if (_intent == null)
          CollectCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Contribution amount',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                CollectSpacing.gap12,
                TextField(
                  controller: _amount,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    prefixText: 'RWF ',
                    hintText: '10,000',
                    helperText: 'Enter whole Rwanda francs.',
                    errorText: _error == 'Enter an amount above RWF 0.'
                        ? _error
                        : null,
                  ),
                  onSubmitted: (_) => _prepare(),
                ),
                CollectSpacing.gap16,
                CollectListTile(
                  leading: CollectIcons.momo,
                  title: receiver.isEmpty
                      ? collection.receiverDisplayLabel
                      : receiver,
                  subtitle: collection.receiverNetwork == 'airtel_money'
                      ? 'Airtel Money receiver'
                      : 'MTN MoMo receiver',
                ),
              ],
            ),
          )
        else ...[
          CollectCard(
            emphasis: CollectCardEmphasis.glow,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  formatRwf(_intent!.expectedAmountRwf),
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                CollectSpacing.gap12,
                CollectListTile(
                  leading: CollectIcons.momo,
                  title: receiver,
                  subtitle: 'Exact group receiver',
                ),
              ],
            ),
          ),
          const InfoSecurityBanner(
            title: 'Approve only inside MoMo',
            message:
                'Collect opens the USSD request with the exact receiver and amount. Review it and enter your PIN only in the mobile-network prompt.',
            tone: CollectStatusTone.privacy,
          ),
          if (_ussdOpened)
            const InfoSecurityBanner(
              title: 'Waiting for the receipt SMS',
              message:
                  'The contribution stays pending until the consented Android receipt is parsed and allocated, or an administrator reconciles an exception.',
              tone: CollectStatusTone.info,
            ),
        ],
        if (_error != null && _error != 'Enter an amount above RWF 0.')
          InfoSecurityBanner(
            title: 'MoMo could not continue',
            message: _error!,
            tone: CollectStatusTone.warning,
          ),
      ],
    );
  }

  Future<void> _prepare() async {
    final amount = int.tryParse(_amount.text.replaceAll(RegExp(r'\D'), ''));
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter an amount above RWF 0.');
      return;
    }
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final intent = await ref
          .read(collectRepositoryProvider.notifier)
          .createPaymentIntent(
            PaymentIntentDraft(
              collectionId: widget.collectionId,
              amountRwf: amount,
            ),
          );
      if (mounted) setState(() => _intent = intent);
    } catch (error) {
      if (mounted) setState(() => _error = _safeFlowError(error));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _openUssd() async {
    final intent = _intent;
    if (intent == null) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final receiver = intent.receiverMomoNumber.replaceAll(RegExp(r'\D'), '');
      final opened = await const MomoUssdLauncher().launch(
        receiver: receiver,
        amountRwf: intent.expectedAmountRwf,
        provider: intent.momoNetwork,
      );
      if (!opened) throw StateError('MoMo USSD could not open.');
      if (mounted) setState(() => _ussdOpened = true);
    } catch (error) {
      if (mounted) setState(() => _error = _safeFlowError(error));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  String _safeFlowError(Object error) {
    if (error is StateError) return error.message.toString();
    if (error is FormatException) return error.message.toString();
    return 'Check your connection and try again.';
  }
}

class _DiasporaBankContributionFlow extends ConsumerStatefulWidget {
  const _DiasporaBankContributionFlow({required this.collectionId});

  final String collectionId;

  @override
  ConsumerState<_DiasporaBankContributionFlow> createState() =>
      _DiasporaBankContributionFlowState();
}

class _DiasporaBankContributionFlowState
    extends ConsumerState<_DiasporaBankContributionFlow> {
  static const _invalidAmountMessage = 'Enter a valid amount above EUR 0.00.';

  final _amount = TextEditingController();
  BankTransferDestination? _destination;
  PaymentIntentModel? _intent;
  bool _loadingDestination = true;
  bool _working = false;
  bool _handoffOpened = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDestination();
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repository = ref.read(collectRepositoryProvider.notifier);
    final collection = repository.maybeCollectionById(widget.collectionId);
    if (collection == null) return const MissingGroupStateScreen();
    if (collection.isArchived) {
      return ArchivedGroupStateScreen(
        collectionId: widget.collectionId,
        groupTitle: collection.title,
      );
    }
    final profile = ref.watch(collectRepositoryProvider).currentProfile;
    final isMember =
        profile != null &&
        (collection.creatorUserId == profile.id ||
            collection.isCurrentUserMember);
    if (!collection.isPublic && !isMember) {
      return ScreenScaffold(
        title: 'Join required',
        subtitle: collection.title,
        compact: true,
        children: [
          MinimalStatePanel(
            icon: CollectIcons.people,
            title: 'Join this group before contributing.',
            message:
                'Membership links your bank transfer request to the correct group ledger.',
            tone: CollectStatusTone.warning,
            primaryAction: CollectButton(
              label: 'Open group',
              icon: CollectIcons.arrowForward,
              onPressed: () => context.go('/groups/${widget.collectionId}'),
              expand: true,
            ),
          ),
        ],
      );
    }
    final destination = _intent?.destination ?? _destination;
    final unavailable =
        destination == null ||
        !destination.enabled ||
        destination.isPlaceholder;
    return ScreenScaffold(
      title: _intent == null ? 'Bank transfer' : 'Review transfer',
      subtitle: collection.title,
      compact: true,
      bottomAction: _loadingDestination || unavailable
          ? null
          : BottomActionSurface(
              children: _intent == null
                  ? [
                      CollectButton(
                        label: _working
                            ? 'Preparing transfer'
                            : 'Review transfer',
                        icon: CollectIcons.arrowForward,
                        onPressed: _working ? null : _prepareTransfer,
                        expand: true,
                      ),
                    ]
                  : [
                      CollectButton(
                        label: _working ? 'Opening Revolut' : 'Open Revolut',
                        icon: Icons.open_in_new_rounded,
                        onPressed: _working ? null : _openRevolut,
                        expand: true,
                      ),
                      CollectButton(
                        label: 'Edit amount',
                        icon: CollectIcons.tune,
                        onPressed: _working
                            ? null
                            : () => setState(() {
                                _intent = null;
                                _handoffOpened = false;
                                _error = null;
                              }),
                        variant: CollectButtonVariant.secondary,
                        expand: true,
                      ),
                    ],
            ),
      children: [
        _ContributionHeader(
          title: collection.title,
          stepLabel: _intent == null
              ? 'Step 1 of 2 · Amount'
              : 'Step 2 of 2 · Review',
          onBack: () => context.go('/groups/${widget.collectionId}'),
        ),
        if (_loadingDestination)
          const CollectScreenLoadingState(
            title: 'Loading bank details',
            message: 'Checking the approved beneficiary version.',
            icon: Icons.account_balance_rounded,
          )
        else if (unavailable)
          const MinimalStatePanel(
            icon: Icons.account_balance_rounded,
            title: 'Bank transfers are not active yet.',
            message:
                'The beneficiary shown in settings is a non-routable placeholder. Transfers stay disabled until two administrators approve real bank details.',
            tone: CollectStatusTone.warning,
          )
        else if (_intent == null) ...[
          CollectCard(
            emphasis: CollectCardEmphasis.normal,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Contribution amount',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                CollectSpacing.gap12,
                TextField(
                  controller: _amount,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                      RegExp(r'^\d{0,9}([.,]\d{0,2})?'),
                    ),
                  ],
                  decoration: InputDecoration(
                    prefixText: 'EUR ',
                    hintText: '0.00',
                    helperText: 'Enter euros and cents.',
                    errorText: _error == _invalidAmountMessage ? _error : null,
                  ),
                  onSubmitted: (_) => _prepareTransfer(),
                ),
              ],
            ),
          ),
          _BeneficiaryCard(destination: destination),
        ] else ...[
          _TransferReviewCard(intent: _intent!, onCopy: _copy),
          const InfoSecurityBanner(
            title: 'Confirm inside your bank app',
            message:
                'Collect opens Revolut only. Select the saved beneficiary, enter the exact amount and reference, then review and approve the transfer in Revolut. Collect never initiates or signs it.',
            tone: CollectStatusTone.privacy,
          ),
          if (_handoffOpened)
            const InfoSecurityBanner(
              title: 'Waiting for bank confirmation',
              message:
                  'Your request remains pending. A bank notification creates evidence; the contribution is confirmed only after statement reconciliation.',
              tone: CollectStatusTone.info,
            ),
        ],
        if (_error != null && _error != _invalidAmountMessage)
          InfoSecurityBanner(
            title: 'Transfer could not continue',
            message: _error!,
            tone: CollectStatusTone.warning,
          ),
      ],
    );
  }

  Future<void> _loadDestination() async {
    try {
      final destination = await ref
          .read(collectRepositoryProvider.notifier)
          .getBankTransferDestination();
      if (mounted) {
        setState(() {
          _destination = destination;
          _loadingDestination = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadingDestination = false;
          _error = 'Approved bank details could not be loaded. Try again.';
        });
      }
    }
  }

  Future<void> _prepareTransfer() async {
    final amountMinor = parseEuroMinor(_amount.text);
    if (amountMinor == null || amountMinor <= 0) {
      setState(() => _error = _invalidAmountMessage);
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final intent = await ref
          .read(collectRepositoryProvider.notifier)
          .createPaymentIntent(
            PaymentIntentDraft(
              collectionId: widget.collectionId,
              amountRwf: amountMinor,
            ),
          );
      if (mounted) {
        setState(() {
          _intent = intent;
          _working = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _working = false;
          _error = _safeError(error);
        });
      }
    }
  }

  Future<void> _openRevolut() async {
    final intent = _intent;
    if (intent == null) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await ref
          .read(collectRepositoryProvider.notifier)
          .markBankTransferHandoffOpened(intent.id);
      final opened = await const RevolutLauncher().launch();
      if (!opened) {
        throw StateError('Revolut could not open on this device.');
      }
      if (mounted) {
        setState(() {
          _working = false;
          _handoffOpened = true;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _working = false;
          _error = _safeError(error);
        });
      }
    }
  }

  Future<void> _copy(String label, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$label copied')));
  }

  String _safeError(Object error) {
    if (error is StateError) return error.message.toString();
    if (error is FormatException) return error.message.toString();
    return 'Check your connection and try again.';
  }
}

@visibleForTesting
int? parseEuroMinor(String value) {
  final normalized = value.trim().replaceAll(' ', '').replaceAll(',', '.');
  if (!RegExp(r'^\d{1,9}(?:\.\d{1,2})?$').hasMatch(normalized)) return null;
  final parts = normalized.split('.');
  final whole = int.tryParse(parts[0]);
  if (whole == null) return null;
  final cents = parts.length == 1 ? 0 : int.parse(parts[1].padRight(2, '0'));
  final result = whole * 100 + cents;
  return result > 0 ? result : null;
}

class _BeneficiaryCard extends StatelessWidget {
  const _BeneficiaryCard({required this.destination});

  final BankTransferDestination destination;

  @override
  Widget build(BuildContext context) => CollectCard(
    emphasis: CollectCardEmphasis.flat,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Approved beneficiary',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        CollectSpacing.gap12,
        _BankField(label: 'Name', value: destination.beneficiaryName),
        _BankField(label: 'IBAN', value: destination.ibanMasked),
        _BankField(label: 'BIC', value: destination.bic),
        _BankField(label: 'Bank', value: destination.bankName),
        _BankField(
          label: 'Scheme',
          value: destination.supportsInstant
              ? 'SEPA · Instant supported'
              : 'SEPA credit transfer',
        ),
      ],
    ),
  );
}

class _TransferReviewCard extends StatelessWidget {
  const _TransferReviewCard({required this.intent, required this.onCopy});

  final PaymentIntentModel intent;
  final Future<void> Function(String, String) onCopy;

  @override
  Widget build(BuildContext context) => CollectCard(
    emphasis: CollectCardEmphasis.glow,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          formatMoneyMinor(
            intent.expectedAmountMinor,
            currency: intent.currency,
          ),
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        CollectSpacing.gap16,
        _CopyBankField(
          label: 'Beneficiary',
          value: intent.destination.beneficiaryName,
          onCopy: onCopy,
        ),
        _CopyBankField(
          label: 'IBAN',
          value: intent.destination.iban,
          onCopy: onCopy,
        ),
        _CopyBankField(
          label: 'BIC',
          value: intent.destination.bic,
          onCopy: onCopy,
        ),
        _CopyBankField(
          label: 'Exact reference',
          value: intent.transferReference,
          onCopy: onCopy,
        ),
      ],
    ),
  );
}

class _BankField extends StatelessWidget {
  const _BankField({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: CollectSpacing.x2),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 90,
          child: Text(label, style: Theme.of(context).textTheme.bodySmall),
        ),
        Expanded(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: CollectSpacing.iconTarget,
            ),
            child: Align(alignment: Alignment.centerLeft, child: Text(value)),
          ),
        ),
      ],
    ),
  );
}

class _CopyBankField extends StatelessWidget {
  const _CopyBankField({
    required this.label,
    required this.value,
    required this.onCopy,
  });
  final String label;
  final String value;
  final Future<void> Function(String, String) onCopy;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Expanded(
        child: _BankField(label: label, value: value),
      ),
      IconButton(
        tooltip: 'Copy $label',
        onPressed: () => onCopy(label, value),
        icon: const Icon(CollectIcons.copy),
      ),
    ],
  );
}

class _ContributionHeader extends StatelessWidget {
  const _ContributionHeader({
    required this.title,
    required this.stepLabel,
    required this.onBack,
  });
  final String title;
  final String stepLabel;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      IconButton.filledTonal(
        tooltip: 'Back to group',
        onPressed: onBack,
        icon: const Icon(Icons.arrow_back_rounded),
      ),
      CollectSpacing.gapW12,
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              stepLabel.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall,
            ),
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
          ],
        ),
      ),
    ],
  );
}
