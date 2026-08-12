import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/payments/momo_ussd_launcher.dart';
import '../../core/security/momo_receiver_normalizer.dart';
import '../../shared/models/collect_models.dart';
import '../../shared/repositories/collect_repository.dart';
import '../../shared/widgets/collect_components.dart';
import '../../shared/widgets/screen_scaffold.dart';
import '../collections/group_empty_state.dart';

const _mobileEvidenceMode = bool.fromEnvironment(
  'COLLECT_MOBILE_EVIDENCE_MODE',
  defaultValue: false,
);

class ContributionFlowScreen extends ConsumerStatefulWidget {
  const ContributionFlowScreen({required this.collectionId, super.key});

  final String collectionId;

  @override
  ConsumerState<ContributionFlowScreen> createState() =>
      _ContributionFlowScreenState();
}

class _ContributionFlowScreenState
    extends ConsumerState<ContributionFlowScreen> {
  final _amount = TextEditingController();
  final _scrollController = ScrollController();
  String? _error;
  bool _reviewing = false;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _amount.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final collection = ref
        .read(collectRepositoryProvider.notifier)
        .maybeCollectionById(widget.collectionId);
    if (collection == null) return const MissingGroupStateScreen();
    if (collection.isArchived) {
      return ArchivedGroupStateScreen(
        collectionId: widget.collectionId,
        groupTitle: collection.title,
      );
    }
    final profile = ref.watch(collectRepositoryProvider).currentProfile;
    final amount = _reviewing ? _amountValue : 0;
    final activeIntent = _reviewing && amount > 0
        ? _activePendingIntent(amountRwf: amount)
        : null;
    final expiredIntent = _reviewing && amount > 0
        ? _latestExpiredIntent(amountRwf: amount)
        : null;
    if (profile == null || profile.momoNumber?.trim().isNotEmpty != true) {
      return ScreenScaffold(
        title: 'Profile required',
        subtitle: collection.title,
        showHeader: false,
        compact: true,
        children: [
          _ContributionHeader(
            title: collection.title,
            stepLabel: 'Setup needed',
            onBack: () => context.go('/groups/${widget.collectionId}'),
          ),
          MinimalStatePanel(
            icon: CollectIcons.momo,
            title: 'Link your MoMo number first.',
            message:
                'Collect needs your profile MoMo number before starting a group contribution.',
            tone: CollectStatusTone.warning,
            primaryAction: CollectButton(
              label: 'Link MoMo number',
              icon: CollectIcons.momo,
              onPressed: () => context.go('/settings/profile'),
              expand: true,
            ),
          ),
        ],
      );
    }
    return ScreenScaffold(
      title: _reviewing ? 'Review' : 'Contribute',
      subtitle: collection.title,
      showHeader: false,
      compact: true,
      scrollController: _scrollController,
      bottomAction: _ContributionActionSurface(
        children: _reviewing
            ? [
                CollectButton(
                  label: _creating
                      ? 'Opening MoMo'
                      : activeIntent == null
                      ? 'Contribute with MoMo'
                      : 'Continue existing contribution',
                  icon: CollectIcons.momo,
                  onPressed: _creating ? null : _createIntent,
                  expand: true,
                ),
                CollectButton(
                  label: 'Edit amount',
                  icon: CollectIcons.tune,
                  onPressed: _creating
                      ? null
                      : () {
                          setState(() {
                            _reviewing = false;
                            _error = null;
                          });
                          _showStartOfCurrentStep();
                        },
                  variant: CollectButtonVariant.secondary,
                  expand: true,
                ),
              ]
            : [
                CollectButton(
                  label: 'Review contribution',
                  icon: CollectIcons.arrowForward,
                  onPressed: _reviewContribution,
                  expand: true,
                ),
              ],
      ),
      children: [
        _ContributionHeader(
          title: collection.title,
          stepLabel: _reviewing
              ? 'Step 2 of 2 · Review'
              : 'Step 1 of 2 · Amount',
          onBack: () => context.go('/groups/${widget.collectionId}'),
        ),
        if (!_reviewing) ...[
          AmountEntryPanel(
            controller: _amount,
            amount: _amountValue,
            quickAmounts: const [],
            error: _error,
            label: 'Contribution amount',
            detail:
                'For ${collection.title}. You will confirm the MoMo destination next.',
            showCurrencyChip: true,
            showQuickAmounts: false,
            onQuickAmount: (_) {},
            onSubmitted: _reviewContribution,
          ),
        ] else ...[
          PaymentReviewSummary(
            amountRwf: amount,
            groupTitle: collection.title,
            receiverLabel: collection.receiverDisplayLabel,
            receiverMomoNumber:
                collection.receiverMomoNumber ?? 'Not configured',
            showFullReceiverNumber: !_mobileEvidenceMode,
            onEdit: () {
              setState(() {
                _reviewing = false;
                _error = null;
              });
              _showStartOfCurrentStep();
            },
          ),
          if (activeIntent != null)
            const InfoSecurityBanner(
              title: 'Contribution already pending',
              message:
                  'Collect will reuse the active request for this group and amount instead of creating a duplicate ledger entry.',
              tone: CollectStatusTone.info,
            )
          else if (expiredIntent != null)
            const InfoSecurityBanner(
              title: 'Previous request expired',
              message:
                  'Continuing creates a fresh contribution request. The expired request will not be added to the confirmed ledger.',
              tone: CollectStatusTone.warning,
            ),
          if (_error != null)
            InfoSecurityBanner(
              title: 'Could not start contribution',
              message: _error!,
              tone: CollectStatusTone.warning,
            ),
          const InfoSecurityBanner(
            title: 'What happens next',
            message:
                'Collect opens the MoMo payment prompt. Your group ledger updates only after the payment is confirmed.',
            tone: CollectStatusTone.privacy,
          ),
        ],
      ],
    );
  }

  void _reviewContribution() {
    final enteredAmount = _amountValue;
    if (enteredAmount <= 0) {
      setState(() => _error = 'Enter an amount above zero.');
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _reviewing = true;
      _error = null;
    });
    _showStartOfCurrentStep();
  }

  Future<void> _createIntent() async {
    final amount = _amountValue;
    if (amount <= 0) {
      setState(() {
        _reviewing = false;
        _error = 'Enter an amount above zero.';
      });
      return;
    }
    setState(() => _creating = true);
    try {
      final collection = ref
          .read(collectRepositoryProvider.notifier)
          .maybeCollectionById(widget.collectionId);
      final receiverCode = collection?.receiverMomoNumber?.trim();
      if (receiverCode == null || receiverCode.isEmpty) {
        throw StateError('Group has no MoMo receiver.');
      }
      final ussdUri = momoUssdUri(
        receiverCode: receiverCode,
        amountRwf: amount,
      );
      final activeIntent = _activePendingIntent(amountRwf: amount);
      if (activeIntent != null) {
        if (!mounted) return;
        final messenger = ScaffoldMessenger.of(context);
        context.go('/groups/${widget.collectionId}');
        unawaited(_launchMomoDialer(messenger, ussdUri));
        return;
      }
      await ref
          .read(collectRepositoryProvider.notifier)
          .createPaymentIntent(
            PaymentIntentDraft(
              collectionId: widget.collectionId,
              amountRwf: amount,
            ),
          );
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      context.go('/groups/${widget.collectionId}');
      unawaited(_launchMomoDialer(messenger, ussdUri));
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _creating = false;
        _error = _safeContributionError(error);
      });
    }
  }

  Future<void> _launchMomoDialer(
    ScaffoldMessengerState messenger,
    Uri ussdUri,
  ) async {
    var opened = false;
    try {
      opened = await MomoUssdLauncher().launch(ussdUri);
    } catch (_) {
      // Unsupported platforms and denied Android phone access leave the group
      // as the source of truth until creator SMS parsing confirms payment.
    }
    if (!opened && messenger.mounted) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('MoMo could not open. Try again from this group.'),
        ),
      );
    }
  }

  PaymentIntentModel? _activePendingIntent({int? amountRwf}) {
    for (final intent in ref.read(collectRepositoryProvider).paymentIntents) {
      if (intent.collectionId != widget.collectionId) continue;
      if (intent.status != 'pending') continue;
      if (DateTime.now().isAfter(intent.expiresAt)) continue;
      if (amountRwf != null && intent.expectedAmountRwf != amountRwf) continue;
      return intent;
    }
    return null;
  }

  PaymentIntentModel? _latestExpiredIntent({required int amountRwf}) {
    PaymentIntentModel? latest;
    for (final intent in ref.read(collectRepositoryProvider).paymentIntents) {
      if (intent.collectionId != widget.collectionId) continue;
      if (intent.expectedAmountRwf != amountRwf) continue;
      final expired =
          intent.status == 'expired' ||
          (intent.status == 'pending' &&
              !DateTime.now().isBefore(intent.expiresAt));
      if (!expired) continue;
      if (latest == null || intent.createdAt.isAfter(latest.createdAt)) {
        latest = intent;
      }
    }
    return latest;
  }

  String _safeContributionError(Object error) {
    if (error is FormatException) return error.message.toString();
    if (error is StateError) return error.message.toString();
    return 'Contribution setup failed. Check your connection and try again.';
  }

  int get _amountValue =>
      int.tryParse(_amount.text.replaceAll(RegExp(r'\D'), '')) ?? 0;

  void _showStartOfCurrentStep() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.minScrollExtent);
    });
  }
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
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final usesAccessibilityText =
        MediaQuery.textScalerOf(context).scale(1) >= 1.3;
    final foreground = CollectRuntimeTokens.chromeForeground(colors);
    final control = CollectRuntimeTokens.chromeControl(colors);
    final border = CollectRuntimeTokens.chromeControlBorder(colors);
    return Row(
      children: [
        IconButton.filledTonal(
          tooltip: 'Back to group',
          style: IconButton.styleFrom(
            backgroundColor: control,
            foregroundColor: foreground,
            side: BorderSide(color: border),
            fixedSize: const Size(44, 44),
            minimumSize: const Size(44, 44),
            padding: EdgeInsets.zero,
          ),
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back_rounded, size: 22),
        ),
        CollectSpacing.gapW12,
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                stepLabel.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: CollectTypography.eyebrowLabel(
                  foreground.withValues(alpha: 0.72),
                ),
              ),
              Semantics(
                header: true,
                child: Text(
                  title,
                  maxLines: usesAccessibilityText ? 2 : 1,
                  softWrap: usesAccessibilityText,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: foreground,
                    fontWeight: CollectTypography.weightBold,
                    height: CollectTypography.leadingSolid,
                    letterSpacing: CollectTypography.trackingDefault,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ContributionActionSurface extends StatelessWidget {
  const _ContributionActionSurface({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var index = 0; index < children.length; index++) ...[
          children[index],
          if (index != children.length - 1) CollectSpacing.gap12,
        ],
      ],
    );
  }
}

@visibleForTesting
Uri momoUssdUri({required String receiverCode, required int amountRwf}) {
  if (amountRwf <= 0) {
    throw const FormatException('Contribution amount must be above zero.');
  }
  final normalizedCode = MomoReceiverNormalizer.normalizePayCode(receiverCode);
  final ussdCode = '*182**8*1*$normalizedCode*$amountRwf#';
  return Uri.parse('tel:${Uri.encodeComponent(ussdCode)}');
}
