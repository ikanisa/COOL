import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../profile/member_profile_gate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/payments/momo_ussd_launcher.dart';
import '../../core/payments/momo_ussd_intent_guard.dart';
import '../../core/payments/rwf_submission_amount.dart';
import '../../core/utils/money_format.dart';
import '../../core/utils/date_format.dart';
import '../../l10n/collect_localizations.dart';
import '../../shared/models/collect_models.dart';
import '../../shared/repositories/collect_repository.dart';
import '../../shared/repositories/payment_help_pending_store.dart';
import '../../shared/widgets/collect_components.dart';
import '../../shared/widgets/collect_form_viewport.dart' as forms;
import '../../shared/widgets/screen_scaffold.dart';
import '../collections/group_empty_state.dart';
import 'contribution_amount_widgets.dart';

part 'contribution_flow_widgets.dart';

String _receiptTimestamp(DateTime value) {
  final offsetMinutes = value.toLocal().timeZoneOffset.inMinutes;
  final sign = offsetMinutes < 0 ? '-' : '+';
  final hours = (offsetMinutes.abs() ~/ 60).toString().padLeft(2, '0');
  final minutes = (offsetMinutes.abs() % 60).toString().padLeft(2, '0');
  return '${formatCollectDateTime(value)} (UTC$sign$hours:$minutes)';
}

class ContributionFlowScreen extends ConsumerWidget {
  const ContributionFlowScreen({required this.collectionId, super.key});

  final String collectionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _RwandaMomoContributionFlow(collectionId: collectionId);
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
    extends ConsumerState<_RwandaMomoContributionFlow>
    with WidgetsBindingObserver {
  final _amount = TextEditingController();
  final _amountFocus = FocusNode();
  PaymentIntentModel? _intent;
  ContributionCommandCheckpoint? _commandRecovery;
  Object? _recoveryOwnerKey;
  bool _restoringRecovery = true;
  bool _recoveryReadFailed = false;
  String? _preparedProfileId;
  CollectRepository? _preparedRepository;
  int? _preparedSessionGeneration;
  int _flowGeneration = 0;
  bool _working = false;
  bool _awaitingConfirmation = false;
  bool _momoRequestOpened = false;
  bool _manualInstructions = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(covariant _RwandaMomoContributionFlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.collectionId == widget.collectionId) return;
    // A route can reuse this state for a different group. Never expose the new
    // group's action until its protected request custody has been re-read.
    ++_flowGeneration;
    _recoveryOwnerKey = null;
    _commandRecovery = null;
    _restoringRecovery = true;
    _recoveryReadFailed = false;
    _intent = null;
    _preparedProfileId = null;
    _preparedRepository = null;
    _preparedSessionGeneration = null;
    _amount.clear();
    _working = false;
    _awaitingConfirmation = false;
    _momoRequestOpened = false;
    _manualInstructions = false;
    _error = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _intent != null &&
        _awaitingConfirmation &&
        !_working) {
      unawaited(_checkPayment());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
            _commandRecovery = null;
            _restoringRecovery = true;
            _recoveryReadFailed = false;
            _preparedProfileId = null;
            _preparedRepository = null;
            _preparedSessionGeneration = null;
            _amount.clear();
            _working = false;
            _awaitingConfirmation = false;
            _momoRequestOpened = false;
            _manualInstructions = false;
            _error = null;
          });
        }
      },
    );
    ref.listen<List<PaymentIntentModel>>(
      collectRepositoryProvider.select((state) => state.paymentIntents),
      (_, intents) {
        final current = _intent;
        if (current == null ||
            !identical(repository, _preparedRepository) ||
            repository.sessionGeneration != _preparedSessionGeneration) {
          return;
        }
        final updated = intents
            .where((item) => item.id == current.id)
            .firstOrNull;
        if (updated != null &&
            (!current.hasCommittedContribution ||
                updated.hasCommittedContribution)) {
          setState(() {
            _intent = updated;
            if (updated.confirmationStatus != 'awaiting_confirmation' ||
                !updated.isAwaitingTransfer) {
              _momoRequestOpened = false;
            }
            if (updated.confirmationStatus != 'awaiting_confirmation') {
              _awaitingConfirmation = true;
            }
          });
        }
      },
    );
    final l10n = CollectLocalizations.of(context);
    final collection = repository.maybeCollectionById(widget.collectionId);
    final profile = ref.watch(collectRepositoryProvider).currentProfile;
    final recoveryOwner = (
      repository,
      repository.sessionGeneration,
      profile?.id,
      widget.collectionId,
    );
    if (_recoveryOwnerKey != recoveryOwner) {
      _recoveryOwnerKey = recoveryOwner;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_restoreCommand());
      });
    }
    // Original request custody remains reachable after a group/route/member
    // change. This is a read/check path; it grants no new contribution authority.
    if (_restoringRecovery || _recoveryReadFailed || _commandRecovery != null) {
      return _buildCommandRecovery(collection?.title ?? 'Payment request');
    }
    if (collection == null) return const MissingGroupStateScreen();
    if (collection.isArchived) {
      return ArchivedGroupStateScreen(
        collectionId: widget.collectionId,
        groupTitle: collection.title,
      );
    }
    if (collection.contributionRailFor(profile) != 'rwanda_momo') {
      return _UnavailableContributionRoute(collection: collection);
    }
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
    final recent =
        ref
            .watch(collectRepositoryProvider)
            .paymentIntents
            .where((item) => item.collectionId == widget.collectionId)
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final resumable = recent.firstOrNull;
    final isAmountStep = _intent == null;
    final isCommitted = _intent?.hasCommittedContribution == true;
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
                      if (resumable != null) ...[
                        _NativeMomoStatus(
                          title: 'Your latest payment request',
                          message:
                              '${formatRwf(resumable.expectedAmountRwf)} · '
                              'Check its status before making another payment.',
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: _working
                                ? null
                                : () => _resume(resumable),
                            icon: const Icon(Icons.history_rounded),
                            label: const Text('Resume payment request'),
                          ),
                        ),
                        CollectSpacing.gap20,
                      ],
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
                        amountRwf: isCommitted
                            ? _intent!.creditedAmountRwf!
                            : _intent!.expectedAmountRwf,
                        title: isCommitted
                            ? (_intent!.confirmationStatus == 'reversed'
                                  ? 'Contribution reversed'
                                  : 'Contribution credited')
                            : _awaitingConfirmation
                            ? 'Payment status'
                            : null,
                        description: isCommitted
                            ? 'Recorded for this group'
                            : _awaitingConfirmation
                            ? 'Requested contribution'
                            : null,
                      ),
                    ],
                    CollectSpacing.gap32,
                    Text(
                      isCommitted ? 'PAID TO' : l10n.text('payingTo'),
                      style: CollectTypography.eyebrowLabel(
                        context.collectColors.textMuted,
                      ),
                    ),
                    CollectSpacing.gap12,
                    _NativeMomoReceiverTile(
                      name: _intent?.receiverLabel.isNotEmpty == true
                          ? _intent!.receiverLabel
                          : collection.receiverDisplayLabel,
                      receiver: receiver,
                    ),
                    if (!isAmountStep && !isCommitted) ...[
                      CollectSpacing.gap12,
                      Wrap(
                        spacing: CollectSpacing.x2,
                        children: [
                          TextButton.icon(
                            onPressed: receiver.isEmpty
                                ? null
                                : () => _openUssd(
                                    copyValue: receiver,
                                    copyLabel: 'MoMo number or code',
                                  ),
                            icon: const Icon(Icons.copy_rounded),
                            label: const Text('Copy payment code'),
                          ),
                          TextButton.icon(
                            onPressed: _working
                                ? null
                                : () => _openUssd(
                                    copyValue: '${_intent!.expectedAmountRwf}',
                                    copyLabel: 'Amount',
                                  ),
                            icon: const Icon(Icons.copy_rounded),
                            label: const Text('Copy amount'),
                          ),
                        ],
                      ),
                      if (!_awaitingConfirmation || _manualInstructions) ...[
                        CollectSpacing.gap20,
                        const _NativeMomoTrustNote(
                          title: 'Pay through MoMo',
                          message:
                              'Use your provider’s payment menu with this code and amount. '
                              'Confirm the recipient name before paying. Enter your PIN only in MoMo.',
                        ),
                      ],
                    ],
                    if (_awaitingConfirmation || isCommitted) ...[
                      CollectSpacing.gap16,
                      _NativeMomoStatus(
                        title: _confirmationTitle(_intent!),
                        message: _confirmationMessage(_intent!),
                      ),
                    ],
                    if (_intent != null && !isCommitted)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _working ? null : _showPaymentHelp,
                          icon: const Icon(CollectIcons.support),
                          label: const Text('Payment help'),
                        ),
                      ),
                    if (isCommitted) ...[
                      if (_intent!.balanceAfterContributionRwf != null) ...[
                        CollectSpacing.gap12,
                        Text(
                          'Balance after this contribution',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        Text(
                          formatRwf(_intent!.balanceAfterContributionRwf!),
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ],
                      if (_intent!.providerTransactionAt != null) ...[
                        CollectSpacing.gap12,
                        Text(
                          'Provider transaction ${_receiptTimestamp(_intent!.providerTransactionAt!)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                      CollectSpacing.gap12,
                      Text(
                        'Credited ${_receiptTimestamp(_intent!.postedAt!)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (_intent!.providerTransactionReference != null) ...[
                        CollectSpacing.gap8,
                        SelectableText(
                          'MoMo TX ID · ${_intent!.providerTransactionReference}',
                        ),
                      ],
                    ],
                    if (!isAmountStep && !_awaitingConfirmation && !isCommitted)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _working ? null : _checkPayment,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Check payment'),
                        ),
                      ),
                    if (flowError != null) ...[
                      CollectSpacing.gap16,
                      _NativeMomoStatus(
                        title: _awaitingConfirmation
                            ? 'Status could not refresh'
                            : l10n.text('momoCouldNotContinue'),
                        message: flowError,
                        isError: true,
                      ),
                    ],
                  ],
                ),
              ),
              actions: ValueListenableBuilder<TextEditingValue>(
                valueListenable: _amount,
                builder: (context, amountValue, _) =>
                    _NativeContributionBottomBar(
                      primaryLabel: isAmountStep
                          ? (_working
                                ? l10n.text('preparingMomo')
                                : l10n.text('continueToMomo'))
                          : isCommitted
                          ? 'View activity'
                          : _awaitingConfirmation
                          ? (_working ? 'Checking payment' : 'Check payment')
                          : (_working
                                ? l10n.text('openingMomo')
                                : l10n.text('openMomoUssd')),
                      primaryIcon: isAmountStep
                          ? CollectIcons.arrowForward
                          : isCommitted
                          ? CollectIcons.activity
                          : _awaitingConfirmation
                          ? Icons.refresh_rounded
                          : CollectIcons.momo,
                      onPrimary:
                          _working ||
                              (isAmountStep &&
                                  parseRwfSubmissionAmount(
                                        amountValue.text,
                                        isComposing:
                                            !amountValue.composing.isCollapsed,
                                      ) ==
                                      null)
                          ? null
                          : isAmountStep
                          ? _prepare
                          : isCommitted
                          ? () => context.go(
                              Uri(
                                path: '/groups/${widget.collectionId}/ledger',
                                queryParameters: {
                                  'payment_id': _intent!.paymentId!,
                                },
                              ).toString(),
                            )
                          : _awaitingConfirmation
                          ? _checkPayment
                          : _openUssd,
                      secondaryLabel: isAmountStep || isCommitted
                          ? null
                          : _awaitingConfirmation
                          ? 'Back to group'
                          : l10n.text('editAmount'),
                      onSecondary: _working || isAmountStep
                          ? null
                          : _awaitingConfirmation
                          ? () => context.go('/groups/${widget.collectionId}')
                          : () => setState(() {
                              _intent = null;
                              _preparedProfileId = null;
                              _preparedRepository = null;
                              _preparedSessionGeneration = null;
                              _awaitingConfirmation = false;
                              _momoRequestOpened = false;
                              _manualInstructions = false;
                              _error = null;
                            }),
                    ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _resume(PaymentIntentModel intent) {
    final repository = ref.read(collectRepositoryProvider.notifier);
    final profileId = ref.read(collectRepositoryProvider).currentProfile?.id;
    if (profileId == null || _working) return;
    setState(() {
      _intent = intent;
      _preparedProfileId = profileId;
      _preparedRepository = repository;
      _preparedSessionGeneration = repository.sessionGeneration;
      _awaitingConfirmation = true;
      _momoRequestOpened = false;
      _error = null;
    });
    unawaited(_checkPayment());
  }

  Future<void> _restoreCommand({bool preserveError = false}) async {
    final repository = ref.read(collectRepositoryProvider.notifier);
    final generation = repository.sessionGeneration;
    final profileId = ref.read(collectRepositoryProvider).currentProfile?.id;
    final operation = ++_flowGeneration;
    bool current() =>
        mounted &&
        operation == _flowGeneration &&
        identical(ref.read(collectRepositoryProvider.notifier), repository) &&
        repository.sessionGeneration == generation &&
        ref.read(collectRepositoryProvider).currentProfile?.id == profileId;
    if (profileId == null) {
      if (current()) setState(() => _restoringRecovery = false);
      return;
    }
    try {
      final recovery = await repository.restoreContributionCommand(
        widget.collectionId,
      );
      if (!current()) return;
      setState(() {
        _commandRecovery = recovery;
        _working = false;
        _restoringRecovery = false;
        _recoveryReadFailed = false;
        if (!preserveError) _error = null;
      });
    } catch (_) {
      if (current()) {
        setState(() {
          _working = false;
          _restoringRecovery = false;
          _recoveryReadFailed = true;
          _error =
              'Saved payment requests could not be read. Check again before another payment.';
        });
      }
    }
  }

  Future<void> _checkCommand() async {
    if (_working || _restoringRecovery) return;
    final recovery = _commandRecovery;
    if (recovery == null) {
      setState(() => _restoringRecovery = true);
      await _restoreCommand();
      return;
    }
    final repository = ref.read(collectRepositoryProvider.notifier);
    final generation = repository.sessionGeneration;
    final profileId = ref.read(collectRepositoryProvider).currentProfile?.id;
    final operation = ++_flowGeneration;
    bool current() =>
        mounted &&
        operation == _flowGeneration &&
        identical(ref.read(collectRepositoryProvider.notifier), repository) &&
        repository.sessionGeneration == generation &&
        ref.read(collectRepositoryProvider).currentProfile?.id == profileId;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final checked = await repository.checkContributionCommand(
        recovery.body.requestId,
      );
      if (!current()) return;
      setState(() => _commandRecovery = checked);
      final intentId = checked.intentId;
      if (intentId == null) {
        setState(
          () => _error =
              'The outcome is still unknown. This does not prove that no payment occurred.',
        );
        return;
      }
      final refreshed = await repository.refreshPaymentIntent(intentId);
      if (!current()) return;
      if (refreshed.id != intentId ||
          refreshed.collectionId != recovery.body.collectionId ||
          refreshed.expectedAmountRwf != recovery.body.amountRwf) {
        throw const FormatException(
          'Payment status does not match the original request.',
        );
      }
      if (refreshed.hasCommittedContribution) {
        await repository.acknowledgeCommittedContribution(refreshed);
      }
      if (!current()) return;
      setState(() {
        _commandRecovery = null;
        _intent = refreshed;
        _preparedRepository = repository;
        _preparedProfileId = profileId;
        _preparedSessionGeneration = generation;
        _awaitingConfirmation = true;
        _momoRequestOpened = false;
        _manualInstructions = false;
      });
    } catch (_) {
      if (current()) {
        setState(
          () => _error =
              'The original request remains saved. Check your connection and try again.',
        );
      }
    } finally {
      if (current()) setState(() => _working = false);
    }
  }

  Widget _buildCommandRecovery(String groupTitle) {
    final recovery = _commandRecovery;
    return Scaffold(
      backgroundColor: context.collectColors.canvas,
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: 430,
            height: double.infinity,
            child: forms.CollectFormViewport(
              maxWidth: 430,
              header: _NativeContributionAppBar(
                title: groupTitle,
                onBack: () => context.go('/groups/${widget.collectionId}'),
              ),
              bodyPadding: const EdgeInsets.all(CollectSpacing.x5),
              body: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _NativeMomoStatus(
                    title: _restoringRecovery
                        ? 'Checking saved requests'
                        : recovery == null
                        ? 'Saved requests unavailable'
                        : 'Check your original request',
                    message: _restoringRecovery
                        ? 'Loading protected payment recovery.'
                        : 'A payment outcome may be unknown. Check this request and your mobile money provider before another transfer.',
                  ),
                  if (recovery != null) ...[
                    CollectSpacing.gap20,
                    Text(
                      formatRwf(recovery.body.amountRwf),
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    CollectSpacing.gap12,
                    SelectableText('Request ${recovery.body.requestId}'),
                    TextButton.icon(
                      onPressed: _working
                          ? null
                          : () => _copy(
                              'Collect contribution request: ${recovery.body.requestId}\n'
                                  'Group: ${recovery.body.collectionId}\nAmount: ${recovery.body.amountRwf} RWF\n'
                                  'Outcome unknown; no new payment or support acknowledgement is confirmed.',
                              'Request details',
                            ),
                      icon: const Icon(Icons.copy_rounded),
                      label: const Text('Copy request details'),
                    ),
                    CollectSpacing.gap12,
                    const Text(
                      'For help, contact Collect at info@ikanisa.com or +250 795 588 248 and share these request details. '
                      'Copying details does not send a support request.',
                    ),
                  ],
                  if (_error != null) ...[
                    CollectSpacing.gap16,
                    _NativeMomoStatus(
                      title: 'Status could not be confirmed',
                      message: _error!,
                      isError: true,
                    ),
                  ],
                ],
              ),
              actions: _NativeContributionBottomBar(
                primaryLabel: _restoringRecovery || _working
                    ? 'Checking request'
                    : 'Check request',
                primaryIcon: Icons.refresh_rounded,
                onPrimary: _restoringRecovery || _working
                    ? null
                    : _checkCommand,
                secondaryLabel: 'Back to group',
                onSecondary: () => context.go('/groups/${widget.collectionId}'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _copy(String value, String label) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$label copied')));
  }

  Future<void> _checkPayment() async {
    final intent = _intent;
    final repository = _preparedRepository;
    if (_working || intent == null || repository == null) return;
    final sessionGeneration = _preparedSessionGeneration;
    final profileId = _preparedProfileId;
    final operation = ++_flowGeneration;
    bool current() =>
        mounted &&
        operation == _flowGeneration &&
        identical(ref.read(collectRepositoryProvider.notifier), repository) &&
        repository.sessionGeneration == sessionGeneration &&
        ref.read(collectRepositoryProvider).currentProfile?.id == profileId;
    if (!current()) return;
    setState(() {
      _working = true;
      _awaitingConfirmation = true;
      _momoRequestOpened = false;
      _error = null;
    });
    try {
      final refreshed = await repository.refreshPaymentIntent(intent.id);
      if (!current()) return;
      if (refreshed.id != intent.id ||
          refreshed.collectionId != intent.collectionId ||
          refreshed.expectedAmountRwf != intent.expectedAmountRwf ||
          (intent.hasCommittedContribution &&
              !refreshed.hasCommittedContribution)) {
        throw const FormatException('Payment status could not be verified');
      }
      setState(() => _intent = refreshed);
      // Balances and history are fetched from their existing authoritative
      // readers. A successful check never increments a local position.
      if (refreshed.hasCommittedContribution) {
        await repository.acknowledgeCommittedContribution(refreshed);
        if (current()) await repository.loadInitial();
      }
    } catch (_) {
      if (current()) {
        setState(
          () => _error =
              'Your last confirmed status is unchanged. Check your connection and try again.',
        );
      }
    } finally {
      if (current()) setState(() => _working = false);
    }
  }

  Future<void> _showPaymentHelp() async {
    final intent = _intent;
    if (intent == null) return;
    final repository = ref.read(collectRepositoryProvider.notifier);
    final generation = repository.sessionGeneration;
    final profileId = ref.read(collectRepositoryProvider).currentProfile?.id;
    bool current() =>
        mounted &&
        _intent?.id == intent.id &&
        identical(ref.read(collectRepositoryProvider.notifier), repository) &&
        repository.sessionGeneration == generation &&
        ref.read(collectRepositoryProvider).currentProfile?.id == profileId;
    if (profileId == null || !current()) return;
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: context.collectColors.transparent,
      sheetAnimationStyle: CollectMotion.animationStyle(context),
      builder: (_) => _PaymentHelpSheet(
        intent: intent,
        groupTitle: repository.collectionById(intent.collectionId).title,
        repository: repository,
        isCurrent: current,
      ),
    );
  }

  bool _canShowOpenedRequest(PaymentIntentModel intent) =>
      _momoRequestOpened &&
      intent.confirmationStatus == 'awaiting_confirmation' &&
      intent.isAwaitingTransfer;

  String _confirmationTitle(PaymentIntentModel intent) =>
      switch (intent.confirmationStatus) {
        'credited' when intent.hasCommittedContribution => 'Credited',
        'reversed' when intent.hasCommittedContribution => 'Reversed',
        'payment_received' => 'Payment record linked',
        'needs_review' => 'Needs help',
        _ when _canShowOpenedRequest(intent) => CollectLocalizations.of(
          context,
        ).text('momoRequestOpened'),
        _ => 'Awaiting confirmation',
      };

  String _confirmationMessage(
    PaymentIntentModel intent,
  ) => switch (intent.confirmationStatus) {
    'credited' when intent.hasCommittedContribution =>
      'Your contribution is recorded in Collect. View Activity for this group’s contribution history.',
    'reversed' when intent.hasCommittedContribution =>
      'A reversal was recorded for this contribution. View Activity for the linked history.',
    'payment_received' =>
      'A payment record is linked to this request. Your balance shows committed contributions.',
    'needs_review' =>
      'This payment request needs review. Your committed contributions remain available in Activity.',
    _ when DateTime.now().toUtc().isAfter(intent.expiresAt.toUtc()) =>
      'This request expired, but a payment can still arrive. Check its status before making another transfer.',
    _ when _canShowOpenedRequest(intent) => CollectLocalizations.of(
      context,
    ).text('momoRequestOpenedMessage'),
    _ =>
      'Waiting for confirmation. You can leave this screen and return to check your payment.',
  };

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
    final amountValue = _amount.value;
    final amount = parseRwfSubmissionAmount(
      amountValue.text,
      isComposing: !amountValue.composing.isCollapsed,
    );
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
      _momoRequestOpened = false;
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
      final intent = await repository.prepareContributionIntent(
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
    } on ContributionRecoveryRequired catch (recovery) {
      if (current()) {
        setState(() {
          _commandRecovery = recovery.checkpoint;
          _error = null;
        });
      }
    } catch (error) {
      if (current()) {
        setState(() => _error = _safeFlowError(error));
        await _restoreCommand(preserveError: true);
      }
    } finally {
      if (current()) setState(() => _working = false);
    }
  }

  Future<void> _openUssd({String? copyValue, String? copyLabel}) async {
    final intent = _intent;
    if (intent == null || _working) return;
    if (copyValue != null && _awaitingConfirmation) {
      await _copy(copyValue, copyLabel ?? 'Payment details');
      return;
    }
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
      _momoRequestOpened = false;
      _error = null;
    });
    var preflightConfirmed = false;
    try {
      if (!current()) {
        throw StateError('Account changed');
      }
      if (copyValue == null &&
          !kIsWeb &&
          defaultTargetPlatform == TargetPlatform.android) {
        final allowed = await const MomoUssdLauncher().ensurePermission();
        if (!current()) return;
        if (!allowed) {
          setState(() {
            _error =
                'Phone permission is required to open MoMo. '
                'You can use the payment details below instead.';
          });
          return;
        }
      }
      // Creation replay is historical. Only the separate current-review RPC
      // can supply this type, followed by durable provider-handoff custody.
      final review = await repository!.reviewContributionIntent(intent);
      if (!current()) return;
      if (!reviewedMomoIntentStillActionable(
        intent,
        review,
        now: DateTime.now(),
      )) {
        setState(() {
          _intent = null;
          _preparedProfileId = null;
          _preparedRepository = null;
          _preparedSessionGeneration = null;
          _error = CollectLocalizations.of(
            context,
          ).text('paymentDetailsChanged');
        });
        return;
      }
      final permit = await repository.claimContributionHandoff(intent, review);
      if (!current()) return;
      if (!permit.consume()) {
        setState(() {
          _intent = null;
          _error = CollectLocalizations.of(
            context,
          ).text('paymentDetailsUnavailable');
        });
        await _restoreCommand(preserveError: true);
        return;
      }
      preflightConfirmed = true;
      if (copyValue != null) {
        await _copy(copyValue, copyLabel ?? 'Payment details');
        if (current()) {
          setState(() {
            _awaitingConfirmation = true;
            _manualInstructions = true;
            _momoRequestOpened = false;
            _error =
                'Payment details copied. If you may have paid, check your provider before another transfer.';
          });
        }
        return;
      }
      final rechecked = permit.review.intent;
      final receiver = rechecked.receiverMomoNumber.replaceAll(
        RegExp(r'\D'),
        '',
      );
      final opened = await const MomoUssdLauncher().launch(
        receiver: receiver,
        amountRwf: rechecked.expectedAmountRwf,
        provider: rechecked.momoNetwork,
      );
      if (current()) {
        setState(() {
          _awaitingConfirmation = true;
          _momoRequestOpened = opened;
          _manualInstructions = !opened;
          if (!opened) {
            _error =
                'MoMo could not open on this device. '
                'Copy the code and amount above, then use your provider’s payment menu. '
                'This does not indicate a failed payment.';
          }
        });
      }
    } on ContributionRecoveryRequired catch (recovery) {
      if (current()) {
        setState(() {
          _intent = null;
          _commandRecovery = recovery.checkpoint;
          _error = null;
        });
      }
    } on ContributionReviewChanged {
      if (current()) {
        setState(() {
          _intent = null;
          _error = CollectLocalizations.of(
            context,
          ).text('paymentDetailsChanged');
        });
        await _restoreCommand(preserveError: true);
      }
    } catch (error) {
      if (current()) {
        setState(() {
          if (!preflightConfirmed) {
            _intent = null;
            _preparedProfileId = null;
            _preparedRepository = null;
            _preparedSessionGeneration = null;
          }
          _error = preflightConfirmed
              ? _safeFlowError(error)
              : CollectLocalizations.of(
                  context,
                ).text('paymentDetailsUnavailable');
        });
        if (!preflightConfirmed) await _restoreCommand(preserveError: true);
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
