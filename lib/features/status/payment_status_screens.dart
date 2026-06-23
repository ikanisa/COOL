import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/utils/money_format.dart';
import '../../shared/models/collect_models.dart';
import '../../shared/providers/collect_app_state.dart';
import '../../shared/repositories/collect_repository.dart';
import '../../shared/utils/support_contact.dart';
import '../../shared/widgets/collect_components.dart';
import '../../shared/widgets/screen_scaffold.dart';
import '../collections/group_empty_state.dart';

class ReturnFromMomoWaitingScreen extends ConsumerStatefulWidget {
  const ReturnFromMomoWaitingScreen({
    required this.collectionId,
    required this.intentId,
    super.key,
  });

  final String collectionId;
  final String intentId;

  @override
  ConsumerState<ReturnFromMomoWaitingScreen> createState() =>
      _ReturnFromMomoWaitingScreenState();
}

class _ReturnFromMomoWaitingScreenState
    extends ConsumerState<ReturnFromMomoWaitingScreen> {
  bool _refreshing = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final repo = ref.read(collectRepositoryProvider.notifier);
    final collection = repo.maybeCollectionById(widget.collectionId);
    if (collection == null) return const MissingGroupStateScreen();
    final intent = _safeIntent(repo, widget.intentId);

    if (intent == null) {
      return ScreenScaffold(
        title: 'Payment not found',
        subtitle: collection.title,
        children: [
          const MinimalStatePanel(
            icon: CollectIcons.warning,
            title: 'Payment not on this device.',
            message: 'Start a fresh contribution or ask support to review it.',
            tone: CollectStatusTone.warning,
          ),
          CollectButton(
            label: 'Contribute again',
            icon: CollectIcons.momo,
            onPressed: () =>
                context.go('/groups/${widget.collectionId}/contribute'),
            expand: true,
          ),
          CollectButton(
            label: 'Get help',
            icon: CollectIcons.support,
            onPressed: () => context.go(
              '/groups/${widget.collectionId}/support/payment/${widget.intentId}',
            ),
            variant: CollectButtonVariant.secondary,
            expand: true,
          ),
        ],
      );
    }

    return ScreenScaffold(
      title: 'Waiting for SMS',
      subtitle: collection.title,
      actions: [
        IconButton.filledTonal(
          tooltip: 'Refresh payment status',
          onPressed: _refreshing ? null : _refreshStatus,
          icon: Icon(_refreshing ? CollectIcons.pending : CollectIcons.sync),
        ),
      ],
      children: [
        if (_error != null)
          InfoSecurityBanner(
            title: 'Refresh failed',
            message: _error!,
            tone: CollectStatusTone.warning,
          ),
        const _PaymentStatusHero(
          icon: CollectIcons.sms,
          title: 'Waiting for MoMo SMS',
          subtitle: 'Keep this phone online after approving MoMo.',
          tone: CollectStatusTone.info,
        ),
        PaymentIntentStatusCard(
          amountRwf: intent.expectedAmountRwf,
          receiverLabel: intent.receiverLabel,
          receiverMomoNumber: intent.receiverMomoNumber,
          status: intent.status,
        ),
        const PaymentPipelineIndicator(status: 'pending'),
        CollectCard(
          emphasis: CollectCardEmphasis.flat,
          child: Column(
            children: [
              CollectListTile(
                leading: CollectIcons.pending,
                title: 'Started',
                subtitle: _relativeAge(intent.createdAt),
              ),
              CollectListTile(
                leading: CollectIcons.warning,
                title: 'Expires',
                subtitle: _relativeExpiry(intent.expiresAt),
              ),
              const CollectListTile(
                leading: CollectIcons.privacy,
                title: 'Private review',
                subtitle: 'Support can review without pasted SMS text.',
              ),
            ],
          ),
        ),
        CollectButton(
          label: 'Refresh status',
          icon: CollectIcons.pending,
          onPressed: _refreshing ? null : _refreshStatus,
          expand: true,
        ),
        CollectButton(
          label: 'View status',
          icon: CollectIcons.ledger,
          onPressed: () => context.go(
            '/groups/${widget.collectionId}/pay/${widget.intentId}',
          ),
          variant: CollectButtonVariant.secondary,
          expand: true,
        ),
        CollectButton(
          label: 'Open MoMo again',
          icon: CollectIcons.momo,
          onPressed: _openMomoAgain,
          variant: CollectButtonVariant.secondary,
          expand: true,
        ),
        const CollectButton(
          label: 'Get help',
          icon: CollectIcons.support,
          onPressed: openCollectWhatsAppSupport,
          variant: CollectButtonVariant.subtle,
          expand: true,
        ),
      ],
    );
  }

  Future<void> _openMomoAgain() async {
    try {
      await launchUrl(_momoUssdUri(), mode: LaunchMode.externalApplication);
    } catch (_) {
      // Browser and desktop test shells often cannot handle tel: links.
    }
  }

  Future<void> _refreshStatus() async {
    setState(() {
      _refreshing = true;
      _error = null;
    });
    try {
      await ref
          .read(collectRepositoryProvider.notifier)
          .refreshPaymentIntent(widget.intentId);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }
}

PaymentIntentModel? _safeIntent(CollectRepository repo, String intentId) {
  return repo.maybeIntentById(intentId);
}

String _relativeAge(DateTime startedAt) {
  final elapsed = DateTime.now().difference(startedAt);
  if (elapsed.inMinutes < 1) return 'just now';
  if (elapsed.inHours < 1) {
    return '${elapsed.inMinutes} minute${elapsed.inMinutes == 1 ? '' : 's'} ago';
  }
  if (elapsed.inDays < 1) {
    return '${elapsed.inHours} hour${elapsed.inHours == 1 ? '' : 's'} ago';
  }
  return '${elapsed.inDays} day${elapsed.inDays == 1 ? '' : 's'} ago';
}

String _relativeExpiry(DateTime expiresAt) {
  final remaining = expiresAt.difference(DateTime.now());
  if (remaining.isNegative) return 'now';
  if (remaining.inMinutes < 1) return 'in less than 1 minute';
  if (remaining.inHours < 1) {
    return 'in ${remaining.inMinutes} minute${remaining.inMinutes == 1 ? '' : 's'}';
  }
  if (remaining.inDays < 1) {
    return 'in ${remaining.inHours} hour${remaining.inHours == 1 ? '' : 's'}';
  }
  return 'in ${remaining.inDays} day${remaining.inDays == 1 ? '' : 's'}';
}

class PaymentStateDetailScreen extends ConsumerWidget {
  const PaymentStateDetailScreen({
    required this.collectionId,
    required this.intentId,
    required this.state,
    super.key,
  });

  final String collectionId;
  final String intentId;
  final PaymentUiStatus state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(collectRepositoryProvider.notifier);
    final collection = _safeCollection(ref, collectionId);
    final intent = _safeIntent(repo, intentId);
    final needsSupport =
        state == PaymentUiStatus.expired ||
        state == PaymentUiStatus.needsReview;
    final (title, message, tone) = switch (state) {
      PaymentUiStatus.confirmed => (
        'Payment confirmed',
        'Recorded on the group ledger.',
        CollectStatusTone.success,
      ),
      PaymentUiStatus.expired => (
        'Payment expired',
        'Start a fresh contribution.',
        CollectStatusTone.danger,
      ),
      PaymentUiStatus.needsReview => (
        'Payment needs review',
        'Support can review the payment safely.',
        CollectStatusTone.warning,
      ),
      PaymentUiStatus.pending => (
        'Payment pending',
        'Waiting for MoMo SMS verification.',
        CollectStatusTone.info,
      ),
    };

    if (intent == null) {
      return ScreenScaffold(
        title: title,
        subtitle: collection?.title,
        children: [
          MinimalStatePanel(
            icon: _iconForTone(tone),
            title: 'Payment not on this device.',
            message:
                'Open the ledger, start a fresh contribution, or contact support.',
            tone: tone,
          ),
          CollectButton(
            label: state == PaymentUiStatus.expired
                ? 'Contribute again'
                : 'Open ledger',
            icon: state == PaymentUiStatus.expired
                ? CollectIcons.momo
                : CollectIcons.ledger,
            onPressed: () => context.go(
              state == PaymentUiStatus.expired
                  ? '/groups/$collectionId/contribute'
                  : '/groups/$collectionId/ledger',
            ),
            expand: true,
          ),
          const CollectButton(
            label: 'Get help',
            icon: CollectIcons.support,
            onPressed: openCollectWhatsAppSupport,
            variant: CollectButtonVariant.secondary,
            expand: true,
          ),
        ],
      );
    }

    return ScreenScaffold(
      title: title,
      subtitle: collection?.title,
      children: [
        if (state == PaymentUiStatus.confirmed)
          const PaymentVerifiedRing()
        else
          _PaymentStatusHero(
            icon: _iconForTone(tone),
            title: title,
            subtitle: message,
            tone: tone,
          ),
        PaymentIntentStatusCard(
          amountRwf: intent.expectedAmountRwf,
          receiverLabel: intent.receiverLabel,
          receiverMomoNumber: intent.receiverMomoNumber,
          status: _statusForPipeline(state),
        ),
        PaymentPipelineIndicator(status: _statusForPipeline(state)),
        CollectCard(
          emphasis: CollectCardEmphasis.flat,
          child: Column(
            children: [
              CollectListTile(
                leading: _iconForTone(tone),
                title: _stateDetailTitle(state),
                subtitle: message,
              ),
              CollectListTile(
                leading: CollectIcons.privacy,
                title: 'Private review',
                subtitle: state == PaymentUiStatus.confirmed
                    ? 'Receiver details stay inside owner and payment screens.'
                    : 'No pasted SMS text is shown in the group.',
              ),
            ],
          ),
        ),
        CollectButton(
          label: state == PaymentUiStatus.expired
              ? 'Contribute again'
              : 'Open ledger',
          icon: state == PaymentUiStatus.expired
              ? CollectIcons.momo
              : CollectIcons.ledger,
          onPressed: () => context.go(
            state == PaymentUiStatus.expired
                ? '/groups/$collectionId/contribute'
                : '/groups/$collectionId/ledger',
          ),
          expand: true,
        ),
        CollectButton(
          label: _secondaryStateActionLabel(state),
          icon: _secondaryStateActionIcon(state),
          onPressed: needsSupport
              ? () => context.go(
                  '/groups/$collectionId/support/payment/$intentId',
                )
              : () => context.go(_secondaryStateActionPath(state)),
          variant: CollectButtonVariant.secondary,
          expand: true,
        ),
      ],
    );
  }

  String _secondaryStateActionPath(PaymentUiStatus state) {
    return switch (state) {
      PaymentUiStatus.confirmed => '/groups/$collectionId',
      PaymentUiStatus.pending => '/groups/$collectionId/pay/$intentId',
      PaymentUiStatus.expired || PaymentUiStatus.needsReview => '/settings',
    };
  }
}

String _statusForPipeline(PaymentUiStatus state) {
  return switch (state) {
    PaymentUiStatus.confirmed => 'confirmed',
    PaymentUiStatus.expired => 'expired',
    PaymentUiStatus.needsReview => 'needs_review',
    PaymentUiStatus.pending => 'pending',
  };
}

String _stateDetailTitle(PaymentUiStatus state) {
  return switch (state) {
    PaymentUiStatus.confirmed => 'Ledger updated',
    PaymentUiStatus.expired => 'Expired',
    PaymentUiStatus.needsReview => 'Support review',
    PaymentUiStatus.pending => 'Waiting for SMS',
  };
}

String _secondaryStateActionLabel(PaymentUiStatus state) {
  return switch (state) {
    PaymentUiStatus.confirmed => 'Open group',
    PaymentUiStatus.pending => 'View status',
    PaymentUiStatus.expired || PaymentUiStatus.needsReview => 'Get help',
  };
}

IconData _secondaryStateActionIcon(PaymentUiStatus state) {
  return switch (state) {
    PaymentUiStatus.confirmed => CollectIcons.collections,
    PaymentUiStatus.pending => CollectIcons.pending,
    PaymentUiStatus.expired ||
    PaymentUiStatus.needsReview => CollectIcons.support,
  };
}

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

class _PaymentStatusHero extends StatelessWidget {
  const _PaymentStatusHero({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.tone,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final CollectStatusTone tone;

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    return CollectCard(
      emphasis: CollectCardEmphasis.glow,
      accentColor: context.collectColors.statusForeground(tone),
      child: textScale > 1.3
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CollectStatusChip(label: title, tone: tone, icon: icon),
                CollectSpacing.gap8,
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.titleSmall,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CollectStatusChip(label: title, tone: tone, icon: icon),
                CollectSpacing.gapW12,
                Expanded(
                  child: Text(
                    subtitle,
                    style: Theme.of(context).textTheme.titleSmall,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
    );
  }
}

CollectCollection? _safeCollection(WidgetRef ref, String collectionId) {
  return ref
      .read(collectRepositoryProvider.notifier)
      .maybeCollectionById(collectionId);
}

IconData _iconForTone(CollectStatusTone tone) {
  return switch (tone) {
    CollectStatusTone.success => CollectIcons.check,
    CollectStatusTone.warning => CollectIcons.warning,
    CollectStatusTone.danger => CollectIcons.error,
    CollectStatusTone.privacy => CollectIcons.privacy,
    CollectStatusTone.info => CollectIcons.info,
    CollectStatusTone.neutral => CollectIcons.info,
  };
}

Uri _momoUssdUri() => Uri.parse('tel:${Uri.encodeComponent('*182#')}');
