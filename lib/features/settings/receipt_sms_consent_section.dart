import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/models/collect_models.dart';
import '../../shared/models/receipt_sms_consent.dart';
import '../../shared/repositories/collect_repository.dart';
import '../../shared/widgets/collect_components.dart';

/// Purpose-specific member choice inside the existing notification settings.
/// Service support and saved status must both be observed; no optimistic toggle.
class ReceiptSmsConsentSection extends ConsumerStatefulWidget {
  const ReceiptSmsConsentSection({super.key});
  @override
  ConsumerState<ReceiptSmsConsentSection> createState() =>
      _ReceiptSmsConsentSectionState();
}

class _ReceiptSmsConsentSectionState
    extends ConsumerState<ReceiptSmsConsentSection> {
  String? _group;
  String? _selectionError;
  int _operation = 0;
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(collectRepositoryProvider),
        repository = ref.read(collectRepositoryProvider.notifier);
    final groups = state.collections
        .where((g) => g.isCurrentUserMember && !g.isArchived)
        .toList(growable: false);
    final selected = groups.where((g) => g.id == _group).firstOrNull;
    if (_group != null && selected == null) {
      final removed = _group;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _group == removed) {
          setState(() {
            _group = null;
            _operation++;
            _selectionError =
                'Your group membership changed. Choose a current group.';
          });
        }
      });
    }
    final view = selected == null
        ? const ReceiptSmsConsentView()
        : repository.receiptSmsConsentFor(selected.id);
    final consent = view.consent;
    final currentPending = selected == null
        ? null
        : repository.receiptSmsCurrentPending(selected.id);
    final pending = currentPending ?? view.pending;
    final hasPending = view.recovery.pending.isNotEmpty;
    final canRecover =
        selected != null &&
        hasPending &&
        currentPending == null &&
        !view.busy &&
        !view.needsRefresh &&
        view.storageAvailable &&
        !view.supportUnavailable &&
        consent != null &&
        !state.usingStaleCache;
    final hasFenced =
        consent != null &&
        view.recovery.pending.any(
          (r) => r.expectedDecisionRevision < consent.decisionRevision,
        );
    final sameSession =
        selected != null &&
        repository.receiptSmsPendingBelongsToCurrentSession(selected.id);
    final canEdit =
        selected != null &&
        !view.busy &&
        !view.needsRefresh &&
        view.storageAvailable &&
        !view.supportUnavailable &&
        !hasPending &&
        consent != null &&
        !state.usingStaleCache;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CollectHeadingText(
          title: 'Contribution receipt SMS',
          level: 2,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: context.collectColors.textPrimary,
            fontWeight: CollectTypography.weightSemibold,
            letterSpacing: CollectTypography.trackingDefault,
          ),
          maxLines: null,
          softWrap: true,
          overflow: TextOverflow.visible,
        ),
        const Text(
          'Choose separately for each group. This uses your verified phone and does not change push notifications or your MoMo details. SMS delivery is not confirmed.',
        ),
        CollectSpacing.gap12,
        if (state.currentProfile == null)
          const Text('Sign in to view your receipt SMS choices.')
        else if (groups.isEmpty)
          const Text('There are no current groups to manage here.')
        else ...[
          if (state.usingStaleCache)
            const Text(
              'Cached groups are shown. Connect and refresh your groups before changing receipt SMS.',
            ),
          CollectButton(
            key: const ValueKey('receipt-sms-group'),
            label: selected == null ? 'Choose group' : 'Change group',
            variant: CollectButtonVariant.secondary,
            expand: true,
            onPressed: () => _select(groups),
          ),
          if (_selectionError != null)
            Semantics(liveRegion: true, child: Text(_selectionError!)),
          if (selected != null)
            CollectCard(
              emphasis: CollectCardEmphasis.normal,
              padding: const EdgeInsets.all(CollectSpacing.x3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      selected.title,
                      key: const ValueKey('receipt-sms-group-title'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  CollectSpacing.gap12,
                  if (view.busy)
                    const LinearProgressIndicator(
                      semanticsLabel: 'Loading or saving receipt SMS status',
                    ),
                  if (consent != null) ...[
                    Text(
                      '${view.needsRefresh ? 'Last read choice' : 'Saved choice'}: ${consent.optIn ? 'On' : 'Off'}',
                      key: const ValueKey('receipt-sms-saved-choice'),
                    ),
                    Text(_status(consent)),
                  ] else if (!view.busy)
                    const Text(
                      'Current choice has not been loaded. No receipt SMS preference is assumed.',
                    ),
                  if (view.error != null)
                    Semantics(liveRegion: true, child: Text(view.error!)),
                  if (view.recordedRevision != null)
                    Semantics(
                      liveRegion: true,
                      child: const Text(
                        'Decision recorded. Refresh to check its current status.',
                      ),
                    ),
                  if (pending != null) ...[
                    CollectSpacing.gap12,
                    Text(
                      'Unconfirmed choice: ${pending.optIn ? 'Allow receipt SMS' : 'Withdraw receipt SMS'}',
                    ),
                    if (!sameSession)
                      const Text(
                        'Earlier sign-ins have unresolved requests for this group. You can explicitly withdraw consent using this sign-in; earlier outcomes stay unconfirmed.',
                      )
                    else
                      const Text(
                        'Refreshing status does not resolve the original request. Retry the same retained change to check its recorded outcome.',
                      ),
                  ],
                  if (view.recovery.pending.length > 1)
                    Text(
                      '${view.recovery.pending.length} unresolved request identities are retained.',
                    ),
                  if (view.recovery.superseded.isNotEmpty)
                    Text(
                      '${view.recovery.superseded.length} earlier request${view.recovery.superseded.length == 1 ? '' : 's'} set aside after a later decision. Their original outcomes remain unconfirmed.',
                    ),
                  if (hasPending && !sameSession)
                    CollectButton(
                      key: const ValueKey('receipt-sms-withdraw-recover'),
                      label: 'Withdraw consent and recover',
                      variant: CollectButtonVariant.secondary,
                      expand: true,
                      onPressed: canRecover
                          ? () => _withdrawAndRecover(selected.id)
                          : null,
                    ),
                  if (hasFenced) ...[
                    const Text(
                      'A later recorded decision prevents older requests from making a new change. Their original outcomes remain unconfirmed.',
                    ),
                    CollectButton(
                      key: const ValueKey('receipt-sms-supersede'),
                      label: 'Set aside fenced requests',
                      variant: CollectButtonVariant.secondary,
                      expand: true,
                      onPressed:
                          view.busy ||
                              view.needsRefresh ||
                              !view.storageAvailable ||
                              state.usingStaleCache
                          ? null
                          : () => _supersede(selected.id),
                    ),
                  ],
                  CollectSpacing.gap12,
                  CollectButton(
                    key: const ValueKey('receipt-sms-refresh'),
                    label: 'Refresh status',
                    icon: CollectIcons.sync,
                    variant: CollectButtonVariant.secondary,
                    expand: true,
                    onPressed: view.busy ? null : () => _refresh(selected.id),
                  ),
                  if (pending != null && sameSession)
                    CollectButton(
                      key: const ValueKey('receipt-sms-retry'),
                      label: 'Retry original change',
                      variant: CollectButtonVariant.secondary,
                      expand: true,
                      onPressed:
                          view.busy ||
                              view.needsRefresh ||
                              !view.refreshedPending ||
                              !view.storageAvailable ||
                              view.supportUnavailable
                          ? null
                          : () => _retry(selected.id),
                    ),
                  if (consent != null && !hasPending) ...[
                    if (!consent.effective)
                      CollectButton(
                        key: const ValueKey('receipt-sms-opt-in'),
                        label: consent.optIn
                            ? 'Reconfirm receipt SMS'
                            : 'Allow receipt SMS',
                        expand: true,
                        onPressed: canEdit && consent.optInAvailable
                            ? () => _save(selected.id, true)
                            : null,
                      ),
                    if (consent.optIn)
                      CollectButton(
                        key: const ValueKey('receipt-sms-withdraw'),
                        label: 'Withdraw receipt SMS',
                        variant: CollectButtonVariant.secondary,
                        expand: true,
                        onPressed: canEdit
                            ? () => _save(selected.id, false)
                            : null,
                      ),
                  ],
                ],
              ),
            ),
        ],
      ],
    );
  }

  String _status(ReceiptSmsConsent value) {
    if (value.unavailableReason == 'direct_recipient_verification_required') {
      return 'Direct member phone verification is pending. It cannot be completed on this screen.';
    }
    return switch (value.authorization) {
      ReceiptSmsAuthorization.active =>
        'Your choice is active for this group. This is not confirmation of SMS delivery.',
      ReceiptSmsAuthorization.disabled =>
        value.optInAvailable
            ? 'No receipt SMS authorization is active. You can choose to allow it for this group.'
            : 'No receipt SMS authorization is active. A current phone verification and active membership are required to opt in.',
      ReceiptSmsAuthorization.blockedPhone =>
        'Your saved choice is still On, but its phone binding is not current. Receipt SMS is not active. Refresh after signing in with your current phone, or withdraw the saved choice.',
      ReceiptSmsAuthorization.blockedMembership =>
        'Your saved choice is still On, but the group or membership is inactive. You can withdraw the saved choice.',
      ReceiptSmsAuthorization.directPending =>
        'Direct member phone verification is pending. Receipt SMS is not active.',
    };
  }

  Future<void> _select(List<CollectCollection> groups) async {
    final repository = ref.read(collectRepositoryProvider.notifier),
        generation = repository.sessionGeneration;
    final user = ref.read(collectRepositoryProvider).currentProfile?.id;
    final selected = await showModalBottomSheet<String>(
      context: context,
      sheetAnimationStyle: CollectMotion.animationStyle(context),
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(CollectSpacing.x3),
                child: Text(
                  'Choose group for receipt SMS',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              for (final group in groups)
                ListTile(
                  title: Text(group.title),
                  selected: group.id == _group,
                  onTap: () => Navigator.of(context).pop(group.id),
                ),
            ],
          ),
        ),
      ),
    );
    if (!mounted ||
        selected == null ||
        repository.sessionGeneration != generation ||
        ref.read(collectRepositoryProvider).currentProfile?.id != user) {
      return;
    }
    final current = ref
        .read(collectRepositoryProvider)
        .collections
        .any((g) => g.id == selected && g.isCurrentUserMember && !g.isArchived);
    if (!current) {
      setState(
        () => _selectionError =
            'Group membership changed. Choose a current group.',
      );
      return;
    }
    setState(() {
      _group = selected;
      _selectionError = null;
      _operation++;
    });
    await _refresh(selected);
  }

  Future<void> _run(
    String group,
    Future<void> Function(CollectRepository) operation,
  ) async {
    final epoch = ++_operation;
    final repository = ref.read(collectRepositoryProvider.notifier);
    setState(() => _selectionError = null);
    try {
      await operation(repository);
    } catch (_) {
      if (mounted && epoch == _operation && _group == group) {
        setState(
          () => _selectionError =
              repository.receiptSmsConsentFor(group).error == null
              ? 'Receipt SMS could not be checked or changed. Connect and refresh current status before continuing.'
              : null,
        );
      }
    }
  }

  Future<void> _refresh(String group) =>
      _run(group, (r) => r.refreshReceiptSmsConsent(group));
  Future<void> _save(String group, bool choice) =>
      _run(group, (r) => r.setReceiptSmsConsent(group, optIn: choice));
  Future<void> _retry(String group) =>
      _run(group, (r) => r.retryReceiptSmsConsent(group));
  Future<void> _withdrawAndRecover(String group) =>
      _run(group, (r) => r.withdrawReceiptSmsAndRecover(group));
  Future<void> _supersede(String group) =>
      _run(group, (r) => r.supersedeReceiptSmsRequests(group));
}
