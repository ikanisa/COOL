import 'package:flutter/material.dart';
import '../profile/member_profile_gate.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/payments/revolut_launcher.dart';
import '../../core/payments/momo_ussd_launcher.dart';
import '../../core/utils/money_format.dart';
import '../../l10n/collect_localizations.dart';
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
    final repository = ref.read(collectRepositoryProvider.notifier);
    final collection = repository.maybeCollectionById(collectionId);
    if (collection == null) return const MissingGroupStateScreen();
    final profile = ref.watch(collectRepositoryProvider).currentProfile;
    return switch (collection.contributionRailFor(profile)) {
      'rwanda_momo' => _RwandaMomoContributionFlow(collectionId: collectionId),
      'diaspora_bank' => _DiasporaBankContributionFlow(
        collectionId: collectionId,
      ),
      _ => _UnavailableContributionRoute(collection: collection),
    };
  }
}

class _UnavailableContributionRoute extends StatelessWidget {
  const _UnavailableContributionRoute({required this.collection});

  final CollectCollection collection;

  @override
  Widget build(BuildContext context) {
    final l10n = CollectLocalizations.of(context);
    return ScreenScaffold(
      title: l10n.text('contributionUnavailable'),
      subtitle: collection.title,
      compact: true,
      children: [
        MinimalStatePanel(
          icon: CollectIcons.momo,
          title: l10n.text('noActivePaymentRoute'),
          message: l10n.text('noApprovedDestination'),
          tone: CollectStatusTone.warning,
          primaryAction: CollectButton(
            label: l10n.text('backToGroup'),
            icon: Icons.arrow_back_rounded,
            onPressed: () => context.go('/groups/${collection.id}'),
            expand: true,
          ),
        ),
      ],
    );
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
    final l10n = CollectLocalizations.of(context);
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
        title: l10n.text('joinRequired'),
        subtitle: collection.title,
        compact: true,
        children: [
          MinimalStatePanel(
            icon: CollectIcons.people,
            title: l10n.text('joinBeforeContributing'),
            message: l10n.text('privateMembershipMomo'),
            tone: CollectStatusTone.warning,
            primaryAction: CollectButton(
              label: l10n.text('openGroup'),
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
    final receiverNetworkLabel = collection.receiverNetwork == 'airtel_money'
        ? l10n.text('airtelReceiver')
        : l10n.text('mtnReceiver');
    final isAmountStep = _intent == null;
    final amountError = _error == l10n.text('enterAmountAboveZero')
        ? _error
        : null;
    final flowError = _error != null && amountError == null ? _error : null;
    return Scaffold(
      backgroundColor: context.collectColors.canvas,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              key: const ValueKey('native_momo_contribution_flow'),
              width: constraints.maxWidth.clamp(0, 430).toDouble(),
              height: constraints.maxHeight,
              child: Column(
                children: [
                  _NativeContributionAppBar(
                    title: collection.title,
                    onBack: () => context.go('/groups/${widget.collectionId}'),
                  ),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: ListView(
                        key: ValueKey(isAmountStep),
                        padding: const EdgeInsets.fromLTRB(
                          CollectSpacing.x5,
                          CollectSpacing.x6,
                          CollectSpacing.x5,
                          CollectSpacing.x8,
                        ),
                        children: [
                          if (isAmountStep) ...[
                            _NativeAmountEntry(
                              controller: _amount,
                              errorText: amountError,
                              onSubmitted: _prepare,
                              onPreset: _setAmount,
                              onChanged: () => setState(() => _error = null),
                            ),
                          ] else ...[
                            _NativeAmountReview(
                              amountRwf: _intent!.expectedAmountRwf,
                            ),
                          ],
                          CollectSpacing.gap32,
                          Text(
                            l10n.text('payingTo'),
                            style: CollectTypography.eyebrowLabel(
                              context.collectColors.textMuted,
                            ),
                          ),
                          CollectSpacing.gap12,
                          _NativeMomoReceiverTile(
                            name: collection.receiverDisplayLabel,
                            network: receiverNetworkLabel,
                            receiver: receiver,
                          ),
                          if (!isAmountStep) ...[
                            CollectSpacing.gap20,
                            _NativeMomoTrustNote(
                              title: l10n.text('approveInMomo'),
                              message: l10n.text(
                                'approveOnlyInsideMomoMessage',
                              ),
                            ),
                          ],
                          if (_ussdOpened) ...[
                            CollectSpacing.gap16,
                            _NativeMomoStatus(
                              title: l10n.text('waitingForReceipt'),
                              message: l10n.text('waitingForReceiptMessage'),
                            ),
                          ],
                          if (flowError != null) ...[
                            CollectSpacing.gap16,
                            _NativeMomoStatus(
                              title: l10n.text('momoCouldNotContinue'),
                              message: flowError,
                              isError: true,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  _NativeContributionBottomBar(
                    primaryLabel: isAmountStep
                        ? (_working
                              ? l10n.text('preparingMomo')
                              : l10n.text('continueToMomo'))
                        : (_working
                              ? l10n.text('openingMomo')
                              : l10n.text('openMomoUssd')),
                    primaryIcon: isAmountStep
                        ? CollectIcons.arrowForward
                        : CollectIcons.momo,
                    onPrimary: _working
                        ? null
                        : isAmountStep
                        ? _prepare
                        : _openUssd,
                    secondaryLabel: isAmountStep
                        ? null
                        : l10n.text('editAmount'),
                    onSecondary: _working || isAmountStep
                        ? null
                        : () => setState(() {
                            _intent = null;
                            _ussdOpened = false;
                            _error = null;
                          }),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _setAmount(int amount) {
    setState(() {
      final text = amount.toString();
      _amount.value = const RwfAmountInputFormatter().formatEditUpdate(
        _amount.value,
        TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        ),
      );
      _error = null;
    });
  }

  Future<void> _prepare() async {
    if (ref.read(collectRepositoryProvider).currentProfile == null) {
      context.go(
        Uri(
          path: '/auth',
          queryParameters: {
            'next': '/groups/${widget.collectionId}/contribute',
          },
        ).toString(),
      );
      return;
    }
    final amount = int.tryParse(_amount.text.replaceAll(RegExp(r'\D'), ''));
    if (amount == null || amount <= 0) {
      setState(
        () => _error = CollectLocalizations.of(
          context,
        ).text('enterAmountAboveZero'),
      );
      return;
    }
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await requireMemberProfileReady(context, ref);
      if (!mounted) return;
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
    return CollectLocalizations.of(context).text('checkConnection');
  }
}

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
    required this.errorText,
    required this.onSubmitted,
    required this.onPreset,
    required this.onChanged,
  });

  final TextEditingController controller;
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
          child: Semantics(
            textField: true,
            label: l10n.text('contributionAmount'),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  'RWF',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: colors.textMuted,
                    fontWeight: CollectTypography.weightSemibold,
                  ),
                ),
                CollectSpacing.gapW12,
                Expanded(
                  child: TextField(
                    controller: controller,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    inputFormatters: const [RwfAmountInputFormatter()],
                    onChanged: (_) => onChanged(),
                    style: CollectTypography.amountHero(colors.textPrimary),
                    decoration: InputDecoration(
                      hintText: '0',
                      hintStyle: CollectTypography.amountHero(colors.textMuted),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                    onSubmitted: (_) => onSubmitted(),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (errorText != null) ...[
          CollectSpacing.gap8,
          Text(
            errorText!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colors.dangerForeground,
              fontWeight: CollectTypography.weightSemibold,
            ),
          ),
        ],
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
  const _NativeAmountReview({required this.amountRwf});

  final int amountRwf;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final l10n = CollectLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.text('reviewContribution'),
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            color: colors.textPrimary,
            fontWeight: CollectTypography.weightBold,
          ),
        ),
        CollectSpacing.gap8,
        Text(
          l10n.text('youWillContribute'),
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
        ),
        CollectSpacing.gap16,
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            formatRwf(amountRwf),
            style: CollectTypography.amountHero(colors.textPrimary),
          ),
        ),
      ],
    );
  }
}

class _NativeMomoReceiverTile extends StatelessWidget {
  const _NativeMomoReceiverTile({
    required this.name,
    required this.network,
    required this.receiver,
  });

  final String name;
  final String network;
  final String receiver;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Semantics(
      container: true,
      label: '$name, $network, $receiver',
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
                    CollectSpacing.gap4,
                    Text(
                      receiver.isEmpty ? network : '$network · $receiver',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
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
    return Container(
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
            color: isError ? colors.dangerForeground : colors.infoForeground,
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

class _DiasporaBankContributionFlow extends ConsumerStatefulWidget {
  const _DiasporaBankContributionFlow({required this.collectionId});

  final String collectionId;

  @override
  ConsumerState<_DiasporaBankContributionFlow> createState() =>
      _DiasporaBankContributionFlowState();
}

class _DiasporaBankContributionFlowState
    extends ConsumerState<_DiasporaBankContributionFlow> {
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
    final l10n = CollectLocalizations.of(context);
    final invalidAmountMessage = l10n.text('enterEuroAboveZero');
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
        title: l10n.text('joinRequired'),
        subtitle: collection.title,
        compact: true,
        children: [
          MinimalStatePanel(
            icon: CollectIcons.people,
            title: l10n.text('joinBeforeContributing'),
            message: l10n.text('privateMembershipBank'),
            tone: CollectStatusTone.warning,
            primaryAction: CollectButton(
              label: l10n.text('openGroup'),
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
    final isAmountStep = _intent == null;
    return Scaffold(
      backgroundColor: context.collectColors.canvas,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              key: const ValueKey('native_bank_contribution_flow'),
              width: constraints.maxWidth.clamp(0, 430).toDouble(),
              height: constraints.maxHeight,
              child: Column(
                children: [
                  _NativeContributionAppBar(
                    title: collection.title,
                    onBack: () => context.go('/groups/${widget.collectionId}'),
                  ),
                  Expanded(
                    child: ListView(
                      key: ValueKey(isAmountStep),
                      padding: const EdgeInsets.fromLTRB(
                        CollectSpacing.x5,
                        CollectSpacing.x6,
                        CollectSpacing.x5,
                        CollectSpacing.x8,
                      ),
                      children: [
                        if (_loadingDestination)
                          CollectScreenLoadingState(
                            title: l10n.text('loadingBankDetails'),
                            message: l10n.text('checkingApprovedBeneficiary'),
                            icon: Icons.account_balance_rounded,
                          )
                        else if (unavailable)
                          MinimalStatePanel(
                            icon: Icons.account_balance_rounded,
                            title: l10n.text('bankTransfersInactive'),
                            message: l10n.text('bankTransfersInactiveMessage'),
                            tone: CollectStatusTone.warning,
                          )
                        else if (isAmountStep) ...[
                          _NativeEuroAmountEntry(
                            controller: _amount,
                            working: _working,
                            errorText: _error == invalidAmountMessage
                                ? _error
                                : null,
                            onSubmitted: _prepareTransfer,
                            onChanged: () => setState(() => _error = null),
                          ),
                          CollectSpacing.gap32,
                          _BeneficiaryCard(destination: destination),
                        ] else ...[
                          Text(
                            l10n.text('reviewTransfer'),
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          CollectSpacing.gap16,
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              formatMoneyMinor(
                                _intent!.expectedAmountMinor,
                                currency: _intent!.currency,
                                localeName: 'en',
                              ),
                              style: CollectTypography.amountHero(
                                context.collectColors.textPrimary,
                              ),
                            ),
                          ),
                          CollectSpacing.gap24,
                          _TransferReviewCard(intent: _intent!, onCopy: _copy),
                          CollectSpacing.gap20,
                          _NativeMomoTrustNote(
                            title: l10n.text('confirmInsideBankApp'),
                            message: l10n.text('confirmInsideBankAppMessage'),
                          ),
                          if (_handoffOpened) ...[
                            CollectSpacing.gap16,
                            _NativeMomoStatus(
                              title: l10n.text('waitingForBankConfirmation'),
                              message: l10n.text(
                                'waitingForBankConfirmationMessage',
                              ),
                            ),
                          ],
                        ],
                        if (_error != null &&
                            _error != invalidAmountMessage) ...[
                          CollectSpacing.gap16,
                          _NativeMomoStatus(
                            title: l10n.text('transferCouldNotContinue'),
                            message: _error!,
                            isError: true,
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (!_loadingDestination && !unavailable)
                    _NativeContributionBottomBar(
                      primaryLabel: isAmountStep
                          ? (_working
                                ? l10n.text('preparingTransfer')
                                : l10n.text('reviewTransfer'))
                          : (_working
                                ? l10n.text('openingRevolut')
                                : l10n.text('openRevolut')),
                      primaryIcon: isAmountStep
                          ? CollectIcons.arrowForward
                          : Icons.open_in_new_rounded,
                      onPrimary: _working
                          ? null
                          : isAmountStep
                          ? _prepareTransfer
                          : _openRevolut,
                      secondaryLabel: isAmountStep
                          ? null
                          : l10n.text('editAmount'),
                      onSecondary: _working || isAmountStep
                          ? null
                          : () => setState(() {
                              _intent = null;
                              _handoffOpened = false;
                              _error = null;
                            }),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
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
          _error = CollectLocalizations.of(
            context,
          ).text('bankDetailsCouldNotLoad');
        });
      }
    }
  }

  Future<void> _prepareTransfer() async {
    if (_working || _loadingDestination || _intent != null) return;
    final amountMinor = parseEuroMinor(_amount.text);
    if (amountMinor == null || amountMinor <= 0) {
      setState(
        () => _error = CollectLocalizations.of(
          context,
        ).text('enterEuroAboveZero'),
      );
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await requireMemberProfileReady(context, ref);
      if (!mounted) return;
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
    if (_working) return;
    final intent = _intent;
    if (intent == null) return;
    final revolutCouldNotOpen = CollectLocalizations.of(
      context,
    ).text('revolutCouldNotOpen');
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
        throw StateError(revolutCouldNotOpen);
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$label ${CollectLocalizations.of(context).text('copied')}',
        ),
      ),
    );
  }

  String _safeError(Object error) {
    if (error is StateError) return error.message.toString();
    if (error is FormatException) return error.message.toString();
    return CollectLocalizations.of(context).text('checkConnection');
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

/// Reject invalid edits as a whole: never turn a pasted amount into a different
/// valid amount by stripping its suffix or excess decimal places.
class EuroAmountInputFormatter extends TextInputFormatter {
  const EuroAmountInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) => RegExp(r'^\d{0,9}(?:[.,]\d{0,2})?$').hasMatch(newValue.text)
      ? newValue
      : oldValue;
}

class _NativeEuroAmountEntry extends StatelessWidget {
  const _NativeEuroAmountEntry({
    required this.controller,
    required this.working,
    required this.errorText,
    required this.onSubmitted,
    required this.onChanged,
  });

  final TextEditingController controller;
  final bool working;
  final String? errorText;
  final VoidCallback onSubmitted;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final l10n = CollectLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.text('howMuch'),
          style: Theme.of(context).textTheme.headlineMedium,
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
          child: Semantics(
            textField: true,
            label: l10n.text('contributionAmount'),
            child: Row(
              children: [
                Text(
                  'EUR',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: colors.textMuted,
                    fontWeight: CollectTypography.weightSemibold,
                  ),
                ),
                CollectSpacing.gapW12,
                Expanded(
                  child: TextField(
                    controller: controller,
                    autofocus: true,
                    readOnly: working,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    textInputAction: TextInputAction.done,
                    inputFormatters: const [EuroAmountInputFormatter()],
                    style: CollectTypography.amountHero(colors.textPrimary),
                    decoration: InputDecoration(
                      hintText: '0.00',
                      hintStyle: CollectTypography.amountHero(colors.textMuted),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                    onChanged: (_) => onChanged(),
                    onSubmitted: (_) => onSubmitted(),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (errorText != null) ...[
          CollectSpacing.gap8,
          Text(
            errorText!,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.dangerForeground),
          ),
        ],
      ],
    );
  }
}

class _BeneficiaryCard extends StatelessWidget {
  const _BeneficiaryCard({required this.destination});

  final BankTransferDestination destination;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        CollectLocalizations.of(context).text('approvedBeneficiary'),
        style: CollectTypography.eyebrowLabel(context.collectColors.textMuted),
      ),
      CollectSpacing.gap12,
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(CollectSpacing.x4),
        decoration: BoxDecoration(
          color: context.collectColors.surfaceReadable,
          borderRadius: CollectRadius.cardLargeBorder,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              destination.beneficiaryName,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            CollectSpacing.gap8,
            Text(destination.bankName),
            Text(destination.ibanMasked),
            CollectSpacing.gap8,
            Text(
              destination.supportsInstant
                  ? CollectLocalizations.of(context).text('sepaInstant')
                  : CollectLocalizations.of(context).text('sepaCreditTransfer'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: context.collectColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class _TransferReviewCard extends StatelessWidget {
  const _TransferReviewCard({required this.intent, required this.onCopy});

  final PaymentIntentModel intent;
  final Future<void> Function(String, String) onCopy;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(CollectSpacing.x4),
    decoration: BoxDecoration(
      color: context.collectColors.surfaceReadable,
      borderRadius: CollectRadius.cardLargeBorder,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CopyBankField(
          label: CollectLocalizations.of(context).text('beneficiary'),
          value: intent.destination.beneficiaryName,
          onCopy: onCopy,
        ),
        _CopyBankField(
          label: CollectLocalizations.of(context).text('iban'),
          value: intent.destination.iban,
          onCopy: onCopy,
        ),
        _CopyBankField(
          label: CollectLocalizations.of(context).text('bic'),
          value: intent.destination.bic,
          onCopy: onCopy,
        ),
        _CopyBankField(
          label: CollectLocalizations.of(context).text('exactReference'),
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
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: context.collectColors.textMuted,
          ),
        ),
        CollectSpacing.gap4,
        Text(value, style: Theme.of(context).textTheme.bodyMedium),
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
