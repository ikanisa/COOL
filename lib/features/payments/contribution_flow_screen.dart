import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../shared/models/collect_models.dart';
import '../../shared/repositories/collect_repository.dart';
import '../../shared/widgets/collect_components.dart';
import '../../shared/widgets/screen_scaffold.dart';
import '../collections/group_empty_state.dart';

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
  String? _error;
  bool _reviewing = false;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    _amount.addListener(_onAmountChanged);
  }

  @override
  void dispose() {
    _amount.removeListener(_onAmountChanged);
    _amount.dispose();
    super.dispose();
  }

  void _onAmountChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final collection = ref
        .read(collectRepositoryProvider.notifier)
        .maybeCollectionById(widget.collectionId);
    if (collection == null) return const MissingGroupStateScreen();
    final profile = ref.watch(collectRepositoryProvider).currentProfile;
    final amount = _amountValue;
    if (profile == null || profile.momoNumber?.trim().isNotEmpty != true) {
      return ScreenScaffold(
        title: 'Profile required',
        subtitle: collection.title,
        showHeader: false,
        compact: true,
        children: [
          _ContributionHeader(
            title: collection.title,
            onBack: () => context.go('/groups/${widget.collectionId}'),
          ),
          MinimalStatePanel(
            icon: CollectIcons.momo,
            title: 'Link your MoMo number first.',
            message:
                'Collect needs your profile MoMo number before starting a group payment.',
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
      bottomAction: _ContributionActionSurface(
        children: _reviewing
            ? [
                CollectButton(
                  label: _creating ? 'Opening MOMO' : 'Pay with MOMO',
                  icon: CollectIcons.momo,
                  onPressed: _creating ? null : _createIntent,
                  expand: true,
                ),
                CollectButton(
                  label: 'Edit amount',
                  icon: CollectIcons.tune,
                  onPressed: _creating
                      ? null
                      : () => setState(() => _reviewing = false),
                  variant: CollectButtonVariant.secondary,
                  expand: true,
                ),
              ]
            : [
                CollectButton(
                  label: 'Review contribution',
                  icon: CollectIcons.arrowForward,
                  onPressed: () {
                    if (amount <= 0) {
                      setState(() => _error = 'Enter an amount above zero.');
                      return;
                    }
                    setState(() {
                      _reviewing = true;
                      _error = null;
                    });
                  },
                  expand: true,
                ),
              ],
      ),
      children: [
        _ContributionHeader(
          title: collection.title,
          onBack: () => context.go('/groups/${widget.collectionId}'),
        ),
        if (!_reviewing) ...[
          AmountEntryPanel(
            controller: _amount,
            amount: amount,
            quickAmounts: const [],
            error: _error,
            showCurrencyChip: true,
            showQuickAmounts: false,
            onQuickAmount: (_) {},
          ),
        ] else ...[
          PaymentReviewSummary(
            amountRwf: amount,
            groupTitle: collection.title,
            receiverLabel: collection.receiverDisplayLabel,
            receiverMomoNumber:
                collection.receiverMomoNumber ?? 'Not configured',
            showFullReceiverNumber: true,
            onEdit: () => setState(() => _reviewing = false),
          ),
        ],
      ],
    );
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
      final activeIntent = _activePendingIntent(amountRwf: amount);
      if (activeIntent != null) {
        if (!mounted) return;
        context.go('/groups/${widget.collectionId}');
        unawaited(_launchMomoDialer());
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
      context.go('/groups/${widget.collectionId}');
      unawaited(_launchMomoDialer());
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _creating = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _launchMomoDialer() async {
    try {
      await launchUrl(momoUssdUri(), mode: LaunchMode.externalApplication);
    } catch (_) {
      // Web and some desktops cannot handle tel: links; the group remains the
      // source of truth until creator SMS parsing confirms the contribution.
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

  int get _amountValue =>
      int.tryParse(_amount.text.replaceAll(RegExp(r'\D'), '')) ?? 0;
}

class _ContributionHeader extends StatelessWidget {
  const _ContributionHeader({required this.title, required this.onBack});

  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final foreground = colors.onImagePrimary;
    return Row(
      children: [
        IconButton.filledTonal(
          tooltip: 'Back to group',
          style: IconButton.styleFrom(
            backgroundColor: foreground.withValues(alpha: 0.10),
            foregroundColor: foreground,
            side: BorderSide(color: foreground.withValues(alpha: 0.16)),
            fixedSize: const Size(44, 44),
            minimumSize: const Size(44, 44),
            padding: EdgeInsets.zero,
          ),
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back_rounded, size: 22),
        ),
        CollectSpacing.gapW12,
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w900,
              height: 1,
              letterSpacing: 0,
            ),
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
Uri momoUssdUri() => Uri.parse('tel:${Uri.encodeComponent('*182#')}');
