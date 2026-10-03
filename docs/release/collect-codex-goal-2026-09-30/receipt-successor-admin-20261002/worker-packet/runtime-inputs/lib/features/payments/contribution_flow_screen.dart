import 'package:flutter/material.dart';
import '../profile/member_profile_gate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/payments/momo_ussd_launcher.dart';
import '../../core/payments/momo_ussd_intent_guard.dart';
import '../../core/utils/money_format.dart';
import '../../l10n/collect_localizations.dart';
import '../../shared/models/collect_models.dart';
import '../../shared/repositories/collect_repository.dart';
import '../../shared/widgets/collect_components.dart';
import '../../shared/widgets/collect_form_viewport.dart' as forms;
import '../../shared/widgets/screen_scaffold.dart';
import '../collections/group_empty_state.dart';
import 'contribution_amount_widgets.dart';

class ContributionFlowScreen extends ConsumerWidget {
  const ContributionFlowScreen({required this.collectionId, super.key});

  final String collectionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(collectRepositoryProvider);
    final repository = ref.watch(collectRepositoryProvider.notifier);
    final collection = repository.maybeCollectionById(collectionId);
    if (collection == null) return const MissingGroupStateScreen();
    return switch (collection.contributionRailFor(state.currentProfile)) {
      'rwanda_momo' => _RwandaMomoContributionFlow(collectionId: collectionId),
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
  final _amountFocus = FocusNode();
  PaymentIntentModel? _intent;
  String? _preparedProfileId;
  CollectRepository? _preparedRepository;
  int? _preparedSessionGeneration;
  int _flowGeneration = 0;
  bool _working = false;
  bool _ussdOpened = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _amountFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repository = ref.watch(collectRepositoryProvider.notifier);
    ref.listen<(CollectRepository, int, String?)>(
      collectRepositoryProvider.select(
        (state) => (
          repository,
          repository.sessionGeneration,
          state.currentProfile?.id,
        ),
      ),
      (previous, next) {
        if (previous != next) {
          ++_flowGeneration;
          setState(() {
            _intent = null;
            _preparedProfileId = null;
            _preparedRepository = null;
            _preparedSessionGeneration = null;
            _amount.clear();
            _working = false;
            _ussdOpened = false;
            _error = null;
          });
        }
      },
    );
    final l10n = CollectLocalizations.of(context);
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
    final isAmountStep = _intent == null;
    final amountError = _error == l10n.text('enterAmountAboveZero')
        ? _error
        : null;
    final flowError = _error != null && amountError == null ? _error : null;
    return Scaffold(
      backgroundColor: context.collectColors.canvas,
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            key: const ValueKey('native_momo_contribution_flow'),
            width: 430,
            height: double.infinity,
            child: forms.CollectFormViewport(
              maxWidth: 430,
              header: _NativeContributionAppBar(
                title: collection.title,
                onBack: () => context.go('/groups/${widget.collectionId}'),
              ),
              bodyPadding: const EdgeInsets.fromLTRB(
                CollectSpacing.x5,
                CollectSpacing.x6,
                CollectSpacing.x5,
                CollectSpacing.x8,
              ),
              body: AnimatedSwitcher(
                duration: CollectMotion.duration(context, CollectMotion.medium),
                child: Column(
                  key: ValueKey(isAmountStep),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (isAmountStep) ...[
                      _NativeAmountEntry(
                        controller: _amount,
                        focusNode: _amountFocus,
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
                      receiver: receiver,
                    ),
                    if (!isAmountStep) ...[
                      CollectSpacing.gap20,
                      _NativeMomoTrustNote(
                        title: l10n.text('approveInMomo'),
                        message: l10n.text('approveOnlyInsideMomoMessage'),
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
              actions: _NativeContributionBottomBar(
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
                onPrimary:
                    _working ||
                        (isAmountStep &&
                            (int.tryParse(_amount.text.replaceAll(',', '')) ??
                                    0) <=
                                0)
                    ? null
                    : isAmountStep
                    ? _prepare
                    : _openUssd,
                secondaryLabel: isAmountStep ? null : l10n.text('editAmount'),
                onSecondary: _working || isAmountStep
                    ? null
                    : () => setState(() {
                        _intent = null;
                        _preparedProfileId = null;
                        _preparedRepository = null;
                        _preparedSessionGeneration = null;
                        _ussdOpened = false;
                        _error = null;
                      }),
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
    if (_working || _intent != null) return;
    final repository = ref.read(collectRepositoryProvider.notifier);
    final sessionGeneration = repository.sessionGeneration;
    final preparedProfileId = ref
        .read(collectRepositoryProvider)
        .currentProfile
        ?.id;
    if (preparedProfileId == null) {
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
      _amountFocus.requestFocus();
      return;
    }
    setState(() {
      _working = true;
      _error = null;
    });
    final operation = ++_flowGeneration;
    bool current() =>
        mounted &&
        operation == _flowGeneration &&
        identical(ref.read(collectRepositoryProvider.notifier), repository) &&
        repository.sessionGeneration == sessionGeneration &&
        ref.read(collectRepositoryProvider).currentProfile?.id ==
            preparedProfileId;
    try {
      await requireMemberProfileReady(context, ref);
      if (!current()) return;
      final intent = await repository.createPaymentIntent(
        PaymentIntentDraft(
          collectionId: widget.collectionId,
          amountRwf: amount,
        ),
      );
      if (current()) {
        setState(() {
          _intent = intent;
          _preparedProfileId = preparedProfileId;
          _preparedRepository = repository;
          _preparedSessionGeneration = sessionGeneration;
        });
      }
    } catch (error) {
      if (current()) setState(() => _error = _safeFlowError(error));
    } finally {
      if (current()) setState(() => _working = false);
    }
  }

  Future<void> _openUssd() async {
    final intent = _intent;
    if (intent == null) return;
    final repository = _preparedRepository;
    final sessionGeneration = _preparedSessionGeneration;
    final preparedProfileId = _preparedProfileId;
    final operation = ++_flowGeneration;
    bool current() =>
        mounted &&
        operation == _flowGeneration &&
        repository != null &&
        preparedProfileId != null &&
        identical(ref.read(collectRepositoryProvider.notifier), repository) &&
        repository.sessionGeneration == sessionGeneration &&
        ref.read(collectRepositoryProvider).currentProfile?.id ==
            preparedProfileId;
    setState(() {
      _working = true;
      _error = null;
    });
    var preflightConfirmed = false;
    try {
      if (!current()) {
        throw StateError('Account changed');
      }
      // This live RPC rechecks account, membership, expiry and the active
      // receiver. The recent-intents history RPC intentionally retains old
      // receivers and cannot authorize opening a payment prompt.
      final rechecked = await repository!.createPaymentIntent(
        PaymentIntentDraft(
          collectionId: widget.collectionId,
          amountRwf: intent.expectedAmountRwf,
        ),
      );
      if (!current()) return;
      if (!preparedMomoIntentStillActionable(
        intent,
        rechecked,
        now: DateTime.now(),
      )) {
        setState(() {
          _intent = null;
          _preparedProfileId = null;
          _preparedRepository = null;
          _preparedSessionGeneration = null;
          _ussdOpened = false;
          _error = CollectLocalizations.of(
            context,
          ).text('paymentDetailsChanged');
        });
        return;
      }
      preflightConfirmed = true;
      final receiver = rechecked.receiverMomoNumber.replaceAll(
        RegExp(r'\D'),
        '',
      );
      final opened = await const MomoUssdLauncher().launch(
        receiver: receiver,
        amountRwf: rechecked.expectedAmountRwf,
        provider: rechecked.momoNetwork,
      );
      if (!opened) throw StateError('MoMo USSD could not open.');
      if (current()) setState(() => _ussdOpened = true);
    } catch (error) {
      if (current()) {
        setState(() {
          if (!preflightConfirmed) {
            _intent = null;
            _preparedProfileId = null;
            _preparedRepository = null;
            _preparedSessionGeneration = null;
            _ussdOpened = false;
          }
          _error = preflightConfirmed
              ? _safeFlowError(error)
              : CollectLocalizations.of(
                  context,
                ).text('paymentDetailsUnavailable');
        });
      }
    } finally {
      if (current()) setState(() => _working = false);
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
          l10n.text('youWillContribute'),
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
