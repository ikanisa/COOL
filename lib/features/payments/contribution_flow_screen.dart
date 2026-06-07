import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../shared/models/collect_models.dart';
import '../../shared/repositories/collect_repository.dart';
import '../../shared/widgets/collect_components.dart';
import '../../shared/widgets/screen_scaffold.dart';

class ContributionFlowScreen extends ConsumerStatefulWidget {
  const ContributionFlowScreen({required this.collectionId, super.key});

  final String collectionId;

  @override
  ConsumerState<ContributionFlowScreen> createState() =>
      _ContributionFlowScreenState();
}

class _ContributionFlowScreenState
    extends ConsumerState<ContributionFlowScreen> {
  final _amount = TextEditingController(text: '5000');
  String? _error;
  bool _reviewing = false;
  bool _creating = false;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final collection = ref
        .read(collectRepositoryProvider.notifier)
        .collectionById(widget.collectionId);
    final profile = ref.watch(collectRepositoryProvider).currentProfile;
    final amount = int.tryParse(_amount.text) ?? 0;
    if (profile == null || profile.momoNumber?.trim().isNotEmpty != true) {
      return ScreenScaffold(
        title: 'Profile required',
        subtitle: collection.title,
        children: [
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
      bottomAction: BottomActionSurface(
        children: _reviewing
            ? [
                CollectButton(
                  label: _creating ? 'Opening MoMo' : 'Pay with MoMo',
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
        if (!_reviewing) ...[
          AmountEntryPanel(
            controller: _amount,
            amount: amount,
            quickAmounts: const [1000, 5000, 10000, 20000],
            error: _error,
            onQuickAmount: (value) => setState(() {
              _amount.text = value.toString();
              _error = null;
            }),
          ),
        ] else ...[
          PaymentReviewSummary(
            amountRwf: amount,
            groupTitle: collection.title,
            receiverLabel: collection.receiverDisplayLabel,
            receiverMomoNumber:
                collection.receiverMomoNumber ?? 'Not configured',
            onEdit: () => setState(() => _reviewing = false),
          ),
        ],
      ],
    );
  }

  Future<void> _createIntent() async {
    final amount = int.tryParse(_amount.text) ?? 0;
    if (amount <= 0) {
      setState(() {
        _reviewing = false;
        _error = 'Enter an amount above zero.';
      });
      return;
    }
    setState(() => _creating = true);
    try {
      final intent = await ref
          .read(collectRepositoryProvider.notifier)
          .createPaymentIntent(
            PaymentIntentDraft(
              collectionId: widget.collectionId,
              amountRwf: amount,
            ),
          );
      if (!mounted) return;
      unawaited(_launchMomoDialer());
      if (!mounted) return;
      context.go('/groups/${widget.collectionId}/pay/${intent.id}/waiting');
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
      // Web and some desktops cannot handle tel: links; the waiting screen
      // still gives the user a recoverable payment state.
    }
  }
}

@visibleForTesting
Uri momoUssdUri() => Uri.parse('tel:${Uri.encodeComponent('*182#')}');
