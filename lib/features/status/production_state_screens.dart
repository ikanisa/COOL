import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/utils/date_format.dart';
import '../../core/utils/money_format.dart';
import '../../shared/models/collect_models.dart';
import '../../shared/providers/collect_app_state.dart';
import '../../shared/repositories/collect_repository.dart';
import '../../shared/utils/support_contact.dart';
import '../../shared/widgets/collect_components.dart';
import '../../shared/widgets/screen_scaffold.dart';
import '../collections/group_share_service.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  int _step = 0;

  @override
  Widget build(BuildContext context) {
    final accepted = ref.watch(legalConsentAcceptedProvider);
    const steps = [
      (
        icon: CollectIcons.shield,
        title: 'MoMo groups, verified by SMS.',
        message:
            'Create or join a group, contribute through MoMo, and let Collect post confirmed payments to the ledger with your private Collect ID.',
        tone: CollectStatusTone.privacy,
      ),
      (
        icon: CollectIcons.privacy,
        title: 'Private by default.',
        message:
            'Public screens use Collect IDs, safe amounts, and status labels. Credentials, private message content, and receiver evidence stay off public surfaces.',
        tone: CollectStatusTone.privacy,
      ),
      (
        icon: CollectIcons.tune,
        title: 'Set up only what is needed.',
        message:
            'WhatsApp sign-in, MoMo profile, and Android owner SMS access are requested only when the flow needs them.',
        tone: CollectStatusTone.info,
      ),
    ];
    final current = steps[_step];
    return ScreenScaffold(
      title: 'Collect',
      subtitle: 'Step ${_step + 1} of ${steps.length}',
      bottomAction: BottomActionSurface(
        children: [
          CollectButton(
            label: _step == steps.length - 1
                ? accepted
                      ? 'Get started'
                      : 'Review terms'
                : 'Continue',
            icon: _step == steps.length - 1
                ? CollectIcons.arrowForward
                : CollectIcons.check,
            onPressed: () {
              if (_step < steps.length - 1) {
                setState(() => _step += 1);
                return;
              }
              if (!accepted) {
                context.go('/onboarding/legal');
                return;
              }
              ref.read(onboardingCompleteProvider.notifier).state = true;
              context.go('/auth');
            },
            expand: true,
          ),
          if (_step > 0)
            CollectButton(
              label: 'Back',
              icon: CollectIcons.chevron,
              variant: CollectButtonVariant.secondary,
              onPressed: () => setState(() => _step -= 1),
              expand: true,
            ),
        ],
      ),
      children: [
        CollectWizardProgress(
          labels: const ['Product', 'Privacy', 'Setup'],
          currentStep: _step,
        ),
        MinimalStatePanel(
          icon: current.icon,
          title: current.title,
          message: current.message,
          tone: current.tone,
        ),
        const _StepList(
          steps: [
            'Sign in with WhatsApp',
            'Confirm your Collect ID',
            'Link MoMo',
            'Join or create a group',
            'Pay through MoMo USSD',
          ],
        ),
        if (!accepted)
          CollectListTile(
            leading: CollectIcons.info,
            title: 'Terms and privacy',
            subtitle: 'Required before sign-in.',
            onTap: () => context.go('/onboarding/legal'),
          ),
      ],
    );
  }
}

class LegalConsentScreen extends ConsumerWidget {
  const LegalConsentScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accepted = ref.watch(legalConsentAcceptedProvider);
    return ScreenScaffold(
      title: 'Terms and privacy',
      bottomAction: BottomActionSurface(
        children: [
          CollectButton(
            label: accepted ? 'Continue' : 'Accept and continue',
            icon: CollectIcons.check,
            onPressed: () {
              ref.read(legalConsentAcceptedProvider.notifier).state = true;
              ref.read(onboardingCompleteProvider.notifier).state = true;
              context.go('/auth');
            },
            expand: true,
          ),
          CollectButton(
            label: 'Read privacy policy',
            icon: CollectIcons.privacy,
            onPressed: () => context.go('/settings/legal/privacy'),
            variant: CollectButtonVariant.secondary,
            expand: true,
          ),
        ],
      ),
      children: const [
        MinimalStatePanel(
          icon: CollectIcons.shield,
          title: 'Accept before using Collect.',
          message:
              'Collect supports group contributions, MoMo verification, and privacy-bounded support review. Keep payment credentials and private confirmation messages out of public group spaces.',
          tone: CollectStatusTone.privacy,
        ),
        InfoSecurityBanner(
          title: 'Required acknowledgement',
          message:
              'By continuing you agree to the Collect terms and privacy policy effective 6 June 2026.',
          tone: CollectStatusTone.info,
        ),
      ],
    );
  }
}

class AuthResultScreen extends StatelessWidget {
  const AuthResultScreen({required this.success, super.key});

  final bool success;

  @override
  Widget build(BuildContext context) {
    return ScreenScaffold(
      title: success ? 'OTP verified' : 'OTP failed',
      children: [
        MinimalStatePanel(
          icon: success ? CollectIcons.check : CollectIcons.error,
          title: success ? 'WhatsApp verified.' : 'Code not verified.',
          message: success
              ? 'Your Collect session is active. Finish profile setup so MoMo contributions can be verified safely.'
              : 'Use the latest WhatsApp code or request a fresh one before trying again.',
          tone: success ? CollectStatusTone.success : CollectStatusTone.danger,
          primaryAction: CollectButton(
            label: success ? 'Profile setup' : 'Try again',
            icon: success ? CollectIcons.profile : CollectIcons.sms,
            onPressed: () =>
                context.go(success ? '/settings/profile' : '/auth'),
            expand: true,
          ),
        ),
      ],
    );
  }
}

class ProfileReadinessScreen extends ConsumerWidget {
  const ProfileReadinessScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final readiness = ref.watch(profileReadinessProvider);
    return ScreenScaffold(
      title: readiness.readyForGroupCreation
          ? 'Profile ready'
          : 'Finish profile',
      children: [
        if (readiness.collectId != null)
          CollectIdDisplay(publicId: readiness.collectId!),
        _ReadinessRows(
          rows: [
            _ReadinessRow(
              label: readiness.collectId == null
                  ? 'Profile'
                  : readiness.collectId!,
              ready: readiness.hasProfile,
            ),
            _ReadinessRow(label: 'MoMo saved', ready: readiness.hasMomoNumber),
          ],
        ),
        CollectButton(
          label: readiness.readyForGroupCreation
              ? 'Open groups'
              : 'Add MoMo number',
          icon: readiness.readyForGroupCreation
              ? CollectIcons.collections
              : CollectIcons.momo,
          onPressed: () => context.go(
            readiness.readyForGroupCreation ? '/groups' : '/settings/profile',
          ),
          expand: true,
        ),
      ],
    );
  }
}

class SmsPermissionEducationScreen extends ConsumerWidget {
  const SmsPermissionEducationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ScreenScaffold(
      title: 'SMS access',
      bottomAction: CollectButton(
        label: 'Enable SMS access',
        icon: CollectIcons.check,
        onPressed: () async {
          final granted = await ref
              .read(collectRepositoryProvider.notifier)
              .setSmsAccess(true);
          if (!context.mounted) return;
          context.go(granted ? '/groups/create' : '/permissions/sms-denied');
        },
        expand: true,
      ),
      children: const [
        MinimalStatePanel(
          icon: CollectIcons.sms,
          title: 'Keep MoMo checks on this phone.',
          message: 'Android owner setup for verified group ledgers.',
          tone: CollectStatusTone.privacy,
        ),
        CollectCard(
          emphasis: CollectCardEmphasis.flat,
          child: Column(
            children: [
              CollectListTile(
                leading: CollectIcons.sms,
                title: 'MoMo confirmations',
                subtitle: 'Matched to group payments on device.',
              ),
              CollectListTile(
                leading: CollectIcons.ledger,
                title: 'Ledger updates',
                subtitle: 'Confirmed payments move into the group ledger.',
              ),
              CollectListTile(
                leading: CollectIcons.lock,
                title: 'Private by default',
                subtitle:
                    'Payment credentials and message bodies stay private.',
              ),
            ],
          ),
        ),
        InfoSecurityBanner(
          title: 'Android permission',
          message:
              'iPhone members can join and contribute. Group owner verification uses Android SMS access.',
          tone: CollectStatusTone.info,
        ),
      ],
    );
  }
}

class SmsPermissionDeniedScreen extends StatelessWidget {
  const SmsPermissionDeniedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ScreenScaffold(
      title: 'SMS access needed',
      children: [
        const CollectPermissionRecoveryPanel(
          icon: CollectIcons.warning,
          title: 'SMS access required.',
          message:
              'Enable SMS access on Android before creating owner-managed groups.',
          settingsMessage:
              'Open app settings if Android keeps blocking SMS access for Collect.',
        ),
        CollectButton(
          label: 'Try again',
          icon: CollectIcons.sync,
          onPressed: () => context.go('/permissions/sms'),
          expand: true,
        ),
        CollectButton(
          label: 'App settings',
          icon: CollectIcons.settings,
          onPressed: () => context.go('/settings'),
          variant: CollectButtonVariant.secondary,
          expand: true,
        ),
      ],
    );
  }
}

class IphoneCreateUnavailableScreen extends StatelessWidget {
  const IphoneCreateUnavailableScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ScreenScaffold(
      title: 'Create group',
      children: [
        const MinimalStatePanel(
          icon: CollectIcons.momo,
          title: 'Group creation is available only on Android',
          message:
              'You can still join groups and contribute from iPhone. Group creation needs Android SMS capture for owner-side MoMo verification.',
          tone: CollectStatusTone.info,
        ),
        CollectButton(
          label: 'Scan QR',
          icon: CollectIcons.qr,
          onPressed: () => context.go('/groups/scan'),
          expand: true,
        ),
        CollectButton(
          label: 'Groups',
          icon: CollectIcons.collections,
          onPressed: () => context.go('/groups'),
          variant: CollectButtonVariant.secondary,
          expand: true,
        ),
      ],
    );
  }
}

class GroupCreatedSuccessScreen extends ConsumerWidget {
  const GroupCreatedSuccessScreen({required this.collectionId, super.key});

  final String collectionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collection = _safeCollection(ref, collectionId);
    return ScreenScaffold(
      title: 'Group created',
      children: [
        _StateHero(
          icon: CollectIcons.check,
          title: collection?.title ?? 'Group ready.',
          tone: CollectStatusTone.success,
        ),
        CollectButton(
          label: 'Share',
          icon: CollectIcons.share,
          onPressed: collection == null
              ? null
              : () => shareGroupDeepLink(
                  context: context,
                  ref: ref,
                  collection: collection,
                ),
          expand: true,
        ),
        CollectButton(
          label: 'Open group',
          icon: CollectIcons.collections,
          onPressed: () => context.go('/groups/$collectionId'),
          variant: CollectButtonVariant.secondary,
          expand: true,
        ),
      ],
    );
  }
}

class JoinGroupConfirmationScreen extends ConsumerWidget {
  const JoinGroupConfirmationScreen({required this.collectionId, super.key});

  final String collectionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collection = _safeCollection(ref, collectionId);
    return ScreenScaffold(
      title: 'Group joined',
      children: [
        CollectBottomSheet(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _StateHero(
                icon: CollectIcons.check,
                title: collection?.title ?? 'Joined.',
                tone: CollectStatusTone.success,
              ),
              CollectSpacing.gap16,
              CollectButton(
                label: 'Open group',
                icon: CollectIcons.collections,
                onPressed: () => context.go('/groups/$collectionId'),
                expand: true,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class SharedLinkProblemScreen extends StatelessWidget {
  const SharedLinkProblemScreen({required this.expired, super.key});

  final bool expired;

  @override
  Widget build(BuildContext context) {
    return ScreenScaffold(
      title: expired ? 'Link expired' : 'Link unavailable',
      children: [
        _StateHero(
          icon: CollectIcons.error,
          title: expired ? 'Link expired.' : 'Link unavailable.',
          tone: CollectStatusTone.danger,
        ),
        const InfoSecurityBanner(
          title: 'Receiver privacy',
          message:
              'Invalid and expired public links never reveal receiver information. Receiver setup stays inside the contribution review step.',
          tone: CollectStatusTone.privacy,
        ),
        CollectButton(
          label: 'Scan QR',
          icon: CollectIcons.qr,
          onPressed: () => context.go('/groups/scan'),
          expand: true,
        ),
        CollectButton(
          label: 'Open groups',
          icon: CollectIcons.collections,
          onPressed: () => context.go('/groups'),
          variant: CollectButtonVariant.secondary,
          expand: true,
        ),
        if (expired)
          CollectButton(
            label: 'Request fresh link',
            icon: CollectIcons.sync,
            onPressed: () => context.go('/share/expired/request'),
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
}

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
    final collection = repo.collectionById(widget.collectionId);
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
  try {
    return repo.intentById(intentId);
  } on StateError {
    return null;
  }
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
            title: 'Send a privacy-safe review.',
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

enum OwnerLifecycleAction { leave, close, transferOwner, removeMember }

class OwnerLifecycleActionScreen extends ConsumerStatefulWidget {
  const OwnerLifecycleActionScreen({
    required this.collectionId,
    required this.action,
    super.key,
  });

  final String collectionId;
  final OwnerLifecycleAction action;

  @override
  ConsumerState<OwnerLifecycleActionScreen> createState() =>
      _OwnerLifecycleActionScreenState();
}

class _OwnerLifecycleActionScreenState
    extends ConsumerState<OwnerLifecycleActionScreen> {
  final _input = TextEditingController();
  bool _submitting = false;
  bool _submitted = false;
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final collection = _safeCollection(ref, widget.collectionId);
    final config = _ownerActionConfig(widget.action);
    return ScreenScaffold(
      title: config.title,
      subtitle: collection?.title,
      bottomAction: BottomActionSurface(
        children: [
          CollectButton(
            label: _submitted
                ? widget.action == OwnerLifecycleAction.leave ||
                          widget.action == OwnerLifecycleAction.close
                      ? 'Open groups'
                      : 'Open group'
                : _submitting
                ? 'Submitting'
                : config.submitLabel,
            icon: _submitted ? CollectIcons.collections : config.icon,
            variant: config.danger && !_submitted
                ? CollectButtonVariant.danger
                : CollectButtonVariant.primary,
            onPressed: _submitting
                ? null
                : _submitted
                ? () => context.go(
                    widget.action == OwnerLifecycleAction.leave ||
                            widget.action == OwnerLifecycleAction.close
                        ? '/groups'
                        : '/groups/${widget.collectionId}',
                  )
                : _confirmAndSubmit,
            expand: true,
          ),
          CollectButton(
            label: 'Cancel',
            icon: CollectIcons.chevron,
            onPressed: () =>
                context.go('/groups/${widget.collectionId}/manage'),
            variant: CollectButtonVariant.secondary,
            expand: true,
          ),
        ],
      ),
      children: [
        MinimalStatePanel(
          icon: _submitted ? CollectIcons.check : config.icon,
          title: _submitted ? 'Request completed.' : config.heroTitle,
          message: _submitted ? config.successMessage : config.message,
          tone: _submitted
              ? CollectStatusTone.success
              : config.danger
              ? CollectStatusTone.danger
              : CollectStatusTone.warning,
        ),
        if (!_submitted && config.inputLabel != null)
          FormSectionCard(
            errorTitle: 'Action failed',
            errorMessage: _error,
            children: [
              CollectTextInput(
                controller: _input,
                label: config.inputLabel!,
                maxLines: config.multiline ? 4 : 1,
                textInputAction: config.multiline
                    ? TextInputAction.newline
                    : TextInputAction.done,
                textCapitalization: TextCapitalization.sentences,
                autocorrect: true,
              ),
            ],
          )
        else if (_error != null)
          InfoSecurityBanner(
            title: 'Action failed',
            message: _error!,
            tone: CollectStatusTone.warning,
          ),
      ],
    );
  }

  Future<void> _confirmAndSubmit() async {
    final config = _ownerActionConfig(widget.action);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => CollectConfirmationDialog(
        title: config.confirmTitle,
        message: config.confirmMessage,
        confirmLabel: config.submitLabel,
        confirmIcon: config.icon,
        danger: config.danger,
      ),
    );
    if (confirmed == true) await _submit();
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    final repo = ref.read(collectRepositoryProvider.notifier);
    try {
      switch (widget.action) {
        case OwnerLifecycleAction.leave:
          await repo.leaveGroup(collectionId: widget.collectionId);
          break;
        case OwnerLifecycleAction.close:
          await repo.closeGroup(
            collectionId: widget.collectionId,
            reason: _input.text,
          );
          break;
        case OwnerLifecycleAction.transferOwner:
          await repo.transferGroupOwner(
            collectionId: widget.collectionId,
            newOwnerCollectId: _input.text,
          );
          break;
        case OwnerLifecycleAction.removeMember:
          await repo.removeGroupMember(
            collectionId: widget.collectionId,
            memberCollectId: _input.text,
          );
          break;
      }
      if (mounted) setState(() => _submitted = true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}

class _OwnerActionConfig {
  const _OwnerActionConfig({
    required this.title,
    required this.heroTitle,
    required this.message,
    required this.successMessage,
    required this.submitLabel,
    required this.confirmTitle,
    required this.confirmMessage,
    required this.icon,
    required this.danger,
    this.inputLabel,
    this.multiline = false,
  });

  final String title;
  final String heroTitle;
  final String message;
  final String successMessage;
  final String submitLabel;
  final String confirmTitle;
  final String confirmMessage;
  final IconData icon;
  final bool danger;
  final String? inputLabel;
  final bool multiline;
}

_OwnerActionConfig _ownerActionConfig(OwnerLifecycleAction action) {
  return switch (action) {
    OwnerLifecycleAction.leave => const _OwnerActionConfig(
      title: 'Leave group',
      heroTitle: 'Leave this group?',
      message: 'You can leave the group without exposing receiver details.',
      successMessage: 'The group was removed from this device.',
      submitLabel: 'Leave group',
      confirmTitle: 'Leave group?',
      confirmMessage: 'Leave this group on this device?',
      icon: CollectIcons.error,
      danger: true,
    ),
    OwnerLifecycleAction.close => const _OwnerActionConfig(
      title: 'Close group',
      heroTitle: 'Request group closure.',
      message: 'Closure is auditable and may retain ledger records.',
      successMessage: 'The closure request was recorded.',
      submitLabel: 'Close group',
      confirmTitle: 'Close group?',
      confirmMessage:
          'This is a destructive owner action. Ledger records may be retained.',
      icon: CollectIcons.lock,
      danger: true,
      inputLabel: 'Closure reason',
      multiline: true,
    ),
    OwnerLifecycleAction.transferOwner => const _OwnerActionConfig(
      title: 'Transfer owner',
      heroTitle: 'Transfer ownership safely.',
      message:
          'Enter the new owner Collect ID. Support can verify the handoff.',
      successMessage: 'The transfer request was submitted.',
      submitLabel: 'Transfer owner',
      confirmTitle: 'Transfer owner?',
      confirmMessage: 'Submit this owner transfer request for support review?',
      icon: CollectIcons.profile,
      danger: false,
      inputLabel: 'New owner Collect ID',
    ),
    OwnerLifecycleAction.removeMember => const _OwnerActionConfig(
      title: 'Remove member',
      heroTitle: 'Remove a member by Collect ID.',
      message: 'Use Collect ID only. Do not enter phone numbers or MoMo data.',
      successMessage: 'The member removal request was submitted.',
      submitLabel: 'Remove member',
      confirmTitle: 'Remove member?',
      confirmMessage: 'Submit this member removal request for support review?',
      icon: CollectIcons.people,
      danger: true,
      inputLabel: 'Member Collect ID',
    ),
  };
}

class PermissionRecoveryScreen extends ConsumerWidget {
  const PermissionRecoveryScreen({required this.kind, super.key});

  final String kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isCamera = kind == 'camera';
    return ScreenScaffold(
      title: isCamera ? 'Camera access' : 'Notifications',
      bottomAction: BottomActionSurface(
        children: [
          CollectButton(
            label: isCamera ? 'Try scan again' : 'Enable in Collect',
            icon: isCamera ? CollectIcons.qr : CollectIcons.pending,
            onPressed: () {
              if (isCamera) {
                ref.read(cameraPermissionStatusProvider.notifier).state =
                    CollectDevicePermissionStatus.granted;
                context.go('/groups/scan');
              } else {
                ref.read(notificationPermissionStatusProvider.notifier).state =
                    CollectDevicePermissionStatus.granted;
                context.go('/permissions/device');
              }
            },
            expand: true,
          ),
          CollectButton(
            label: 'App settings',
            icon: CollectIcons.settings,
            onPressed: () => context.go('/settings'),
            variant: CollectButtonVariant.secondary,
            expand: true,
          ),
        ],
      ),
      children: [
        CollectPermissionRecoveryPanel(
          icon: isCamera ? CollectIcons.qr : CollectIcons.pending,
          title: isCamera
              ? 'Camera permission was blocked.'
              : 'Notification permission was blocked.',
          message: isCamera
              ? 'Allow camera access to scan group QR codes. You can still join by opening a valid group link.'
              : 'Allow notifications for payment reminders, group updates, and security notices.',
          settingsMessage: isCamera
              ? 'Open app settings if the OS keeps blocking camera access.'
              : 'Open app settings if notification permission remains denied.',
        ),
      ],
    );
  }
}

class OfflineStateScreen extends StatelessWidget {
  const OfflineStateScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ScreenScaffold(
      title: 'Connection issue',
      children: [
        const MinimalStatePanel(
          icon: CollectIcons.warning,
          title: 'Connection issue.',
          message:
              'Collect could not reach the service. Check the connection, then retry to refresh groups, payment status, and ledger updates.',
          tone: CollectStatusTone.warning,
        ),
        const InfoSecurityBanner(
          title: 'Offline-safe behavior',
          message:
              'Existing group, payment, and ledger screens stay visible on this device. Starting contributions and live payment verification need a stable connection.',
          tone: CollectStatusTone.info,
        ),
        CollectButton(
          label: 'Retry sync',
          icon: CollectIcons.sync,
          onPressed: () => context.go('/sync'),
          expand: true,
        ),
      ],
    );
  }
}

class SyncStatusScreen extends ConsumerWidget {
  const SyncStatusScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(realtimeSyncStatusProvider);
    final title = switch (status) {
      RealtimeSyncStatus.current => 'Realtime current',
      RealtimeSyncStatus.syncing => 'Syncing',
      RealtimeSyncStatus.needsAttention => 'Sync issue',
    };
    return _SimpleStateScreen(
      title: 'Sync status',
      heroTitle: title,
      message: status == RealtimeSyncStatus.current
          ? 'Groups, payments, and ledger data are current on this device.'
          : status == RealtimeSyncStatus.syncing
          ? 'Collect is refreshing groups, payments, and ledger updates.'
          : 'Collect could not refresh all live updates. Retry when the connection is stable.',
      icon: status == RealtimeSyncStatus.current
          ? CollectIcons.check
          : CollectIcons.sync,
      tone: status == RealtimeSyncStatus.needsAttention
          ? CollectStatusTone.warning
          : CollectStatusTone.info,
    );
  }
}

class NotificationPermissionScreen extends ConsumerWidget {
  const NotificationPermissionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final smsStatus = ref.watch(smsPermissionStatusProvider);
    final smsGranted = smsStatus == SmsPermissionStatus.granted;
    final notificationStatus = ref.watch(notificationPermissionStatusProvider);
    final notificationGranted =
        notificationStatus == CollectDevicePermissionStatus.granted;
    return ScreenScaffold(
      title: 'App permissions',
      bottomAction: CollectButton(
        label: 'Finish setup',
        icon: CollectIcons.check,
        onPressed: () => context.go('/home'),
        expand: true,
      ),
      children: [
        const MinimalStatePanel(
          icon: CollectIcons.shield,
          title: 'Permission use',
          message: 'Only the access needed for group payment verification.',
          tone: CollectStatusTone.privacy,
        ),
        CollectCard(
          emphasis: CollectCardEmphasis.glow,
          accentColor: smsGranted
              ? context.collectColors.statusForeground(
                  CollectStatusTone.success,
                )
              : context.collectColors.actionCrimson,
          child: Column(
            children: [
              _PermissionSettingRow(
                icon: CollectIcons.sms,
                title: 'SMS access',
                status: smsGranted
                    ? 'Allowed'
                    : smsStatus == SmsPermissionStatus.denied
                    ? 'Denied'
                    : smsStatus == SmsPermissionStatus.unavailable
                    ? 'Android only'
                    : 'Not enabled',
                active: smsGranted,
                onTap: () => context.go('/permissions/sms'),
              ),
              _PermissionSettingRow(
                icon: CollectIcons.pending,
                title: 'Notifications',
                status: notificationGranted
                    ? 'Allowed'
                    : notificationStatus == CollectDevicePermissionStatus.denied
                    ? 'Denied'
                    : 'Not enabled',
                active: notificationGranted,
                onTap: () {
                  if (notificationStatus ==
                      CollectDevicePermissionStatus.denied) {
                    context.go('/permissions/notifications-denied');
                    return;
                  }
                  ref
                          .read(notificationPermissionStatusProvider.notifier)
                          .state =
                      CollectDevicePermissionStatus.granted;
                },
              ),
              _PermissionSettingRow(
                icon: CollectIcons.privacy,
                title: 'Privacy',
                status: 'Protected',
                active: true,
                onTap: () => context.go('/settings/legal/privacy'),
              ),
            ],
          ),
        ),
        const InfoSecurityBanner(
          title: 'Privacy boundary',
          message:
              'Permissions support contribution confirmations, payment reminders, group updates, and security notices.',
          tone: CollectStatusTone.privacy,
        ),
        const CollectCard(
          emphasis: CollectCardEmphasis.flat,
          child: Column(
            children: [
              CollectListTile(
                leading: CollectIcons.money,
                title: 'Contribution confirmations',
                subtitle: 'Notify members when ledger updates land.',
              ),
              CollectListTile(
                leading: CollectIcons.pending,
                title: 'Payment reminders',
                subtitle: 'Surface pending MoMo checks without exposing proof.',
              ),
              CollectListTile(
                leading: CollectIcons.sms,
                title: 'SMS access details',
                subtitle: 'Android owner verification only.',
              ),
              CollectListTile(
                leading: CollectIcons.warning,
                title: 'Security notices',
                subtitle: 'Warn when sync, links, or payment review need care.',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PermissionSettingRow extends StatelessWidget {
  const _PermissionSettingRow({
    required this.icon,
    required this.title,
    required this.status,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String status;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return InkWell(
      borderRadius: CollectRadius.cardBorder,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: CollectSpacing.x3),
        child: Row(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: colors.actionCrimson.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: SizedBox(
                width: 52,
                height: 52,
                child: Icon(icon, color: colors.actionCrimson),
              ),
            ),
            CollectSpacing.gapW12,
            Expanded(
              child: Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            CollectStatusChip(
              label: status,
              tone: active ? CollectStatusTone.success : CollectStatusTone.info,
            ),
          ],
        ),
      ),
    );
  }
}

class PrivacyDataScreen extends StatelessWidget {
  const PrivacyDataScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ScreenScaffold(
      title: 'Privacy and data',
      children: [
        const MinimalStatePanel(
          icon: CollectIcons.privacy,
          title: 'Collect ID first.',
          message:
              'Public group surfaces use Collect IDs, safe amounts, and status labels.',
          tone: CollectStatusTone.privacy,
        ),
        CollectCard(
          emphasis: CollectCardEmphasis.glow,
          accentColor: context.collectColors.statusForeground(
            CollectStatusTone.privacy,
          ),
          child: const Column(
            children: [
              CollectListTile(
                leading: CollectIcons.public,
                title: 'Public group links',
                subtitle: 'Group name, QR, Collect IDs, and safe status only.',
              ),
              CollectListTile(
                leading: CollectIcons.lock,
                title: 'Private payment data',
                subtitle: 'Receiver numbers and support evidence stay bounded.',
              ),
              CollectListTile(
                leading: CollectIcons.ledger,
                title: 'Ledger records',
                subtitle:
                    'Retained where audit, dispute, or security needs it.',
              ),
            ],
          ),
        ),
        CollectCard(
          emphasis: CollectCardEmphasis.flat,
          child: Column(
            children: [
              const CollectListTile(
                leading: CollectIcons.profile,
                title: 'Member identity',
                subtitle: 'Public group activity uses Collect ID only.',
              ),
              const CollectListTile(
                leading: CollectIcons.momo,
                title: 'MoMo data',
                subtitle:
                    'Receiver numbers stay inside payment and owner flows.',
              ),
              const CollectListTile(
                leading: CollectIcons.sms,
                title: 'SMS evidence',
                subtitle: 'Used for payment matching and support review only.',
              ),
              CollectListTile(
                leading: CollectIcons.privacy,
                title: 'Privacy policy',
                subtitle: 'Full data handling policy.',
                onTap: () => context.go('/settings/legal/privacy'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class NotificationCenterScreen extends ConsumerWidget {
  const NotificationCenterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(collectRepositoryProvider);
    final latestContribution = state.contributions.isEmpty
        ? null
        : state.contributions.first;
    final pendingCount = state.paymentIntents
        .where((item) => item.status == 'pending')
        .length;
    final reviewCount = state.paymentIntents
        .where((item) => item.status == 'needs_review')
        .length;
    final permissionStatus = ref.watch(notificationPermissionStatusProvider);
    final notificationsGranted =
        permissionStatus == CollectDevicePermissionStatus.granted;
    return ScreenScaffold(
      title: 'Notifications',
      children: [
        if (!notificationsGranted)
          CollectCard(
            emphasis: CollectCardEmphasis.glow,
            accentColor: context.collectColors.statusForeground(
              CollectStatusTone.warning,
            ),
            child: CollectListTile(
              leading: CollectIcons.pending,
              title: 'Notifications not enabled',
              subtitle:
                  'Enable payment reminders, group updates, and security notices.',
              onTap: () {
                if (permissionStatus == CollectDevicePermissionStatus.denied) {
                  context.go('/permissions/notifications-denied');
                  return;
                }
                ref.read(notificationPermissionStatusProvider.notifier).state =
                    CollectDevicePermissionStatus.granted;
              },
            ),
          ),
        CollectCard(
          emphasis: CollectCardEmphasis.glow,
          accentColor: pendingCount > 0
              ? context.collectColors.statusForeground(CollectStatusTone.info)
              : context.collectColors.statusForeground(
                  CollectStatusTone.success,
                ),
          child: Row(
            children: [
              CollectStatusChip(
                label: pendingCount > 0 ? '$pendingCount pending' : 'Current',
                tone: pendingCount > 0
                    ? CollectStatusTone.info
                    : CollectStatusTone.success,
                icon: pendingCount > 0
                    ? CollectIcons.pending
                    : CollectIcons.check,
              ),
              CollectSpacing.gapW12,
              Expanded(
                child: Text(
                  reviewCount > 0
                      ? '$reviewCount payment review item${reviewCount == 1 ? '' : 's'} need attention.'
                      : 'Group updates and payment alerts are ready.',
                  style: Theme.of(context).textTheme.titleSmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        if (state.contributions.isEmpty && pendingCount == 0)
          const MinimalStatePanel(
            icon: CollectIcons.pending,
            title: 'No updates yet.',
            message:
                'Contribution confirmations, pending payment reminders, and security notices will appear here.',
            tone: CollectStatusTone.neutral,
          )
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeader(
                title: 'Today',
                actionLabel: pendingCount > 0 ? '$pendingCount pending' : null,
              ),
              CollectCard(
                emphasis: CollectCardEmphasis.flat,
                child: Column(
                  children: [
                    if (latestContribution != null)
                      NotificationUpdateRow(
                        title: 'Contribution confirmed',
                        message:
                            '${formatRwf(latestContribution.amountRwf)} was recorded on the ledger.',
                        meta: formatCollectDateTime(
                          latestContribution.createdAt,
                        ),
                        tone: CollectStatusTone.success,
                      ),
                    if (pendingCount > 0)
                      NotificationUpdateRow(
                        title: 'Payment verification pending',
                        message:
                            '$pendingCount payment${pendingCount == 1 ? '' : 's'} waiting for MoMo SMS verification.',
                        meta: 'Now',
                        tone: CollectStatusTone.info,
                      ),
                    if (reviewCount > 0)
                      NotificationUpdateRow(
                        title: 'Payment review',
                        message:
                            '$reviewCount payment${reviewCount == 1 ? '' : 's'} need support review.',
                        meta: 'Review',
                        tone: CollectStatusTone.warning,
                      ),
                    const NotificationUpdateRow(
                      title: 'Security notice',
                      message:
                          'Collect keeps receiver information inside payment and owner flows, not public share links.',
                      meta: 'Protected',
                      tone: CollectStatusTone.privacy,
                    ),
                  ],
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class HelpSupportScreen extends StatelessWidget {
  const HelpSupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ScreenScaffold(
      title: 'WhatsApp support',
      children: [
        MinimalStatePanel(
          icon: CollectIcons.support,
          title: 'Support',
          message: '+250795588248',
          tone: CollectStatusTone.info,
        ),
        CollectButton(
          label: 'Open WhatsApp',
          icon: CollectIcons.support,
          onPressed: openCollectWhatsAppSupport,
          expand: true,
        ),
      ],
    );
  }
}

class LegalScreen extends StatelessWidget {
  const LegalScreen({required this.kind, super.key});

  final String kind;

  @override
  Widget build(BuildContext context) {
    final isPrivacy = kind == 'privacy';
    final sections = isPrivacy ? _privacyPolicySections : _termsSections;
    return ScreenScaffold(
      title: isPrivacy ? 'Privacy Policy' : 'Terms & Conditions',
      children: [
        MinimalStatePanel(
          icon: isPrivacy ? CollectIcons.privacy : CollectIcons.info,
          title: isPrivacy ? 'Collect Privacy Policy' : 'Collect Terms',
          message: isPrivacy
              ? 'Effective 6 June 2026. This policy explains how Collect handles profile, group, payment, and permission data.'
              : 'Effective 6 June 2026. These terms explain how Collect supports group contributions, MoMo verification, and group administration.',
          tone: isPrivacy ? CollectStatusTone.privacy : CollectStatusTone.info,
        ),
        CollectCard(
          emphasis: CollectCardEmphasis.flat,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [for (final section in sections) _LegalText(section)],
          ),
        ),
        InfoSecurityBanner(
          title: isPrivacy ? 'Public boundary' : 'Security responsibility',
          message: isPrivacy
              ? 'Private message content, receiver MoMo numbers, and support evidence are not public group content. Public screens use Collect IDs, amounts, group names, and safe status labels.'
              : 'Confirm the group, receiver label, and amount before approving MoMo. Collect support messages do not request payment credentials or sign-in secrets.',
          tone: isPrivacy
              ? CollectStatusTone.privacy
              : CollectStatusTone.warning,
        ),
      ],
    );
  }
}

class _LegalSection {
  const _LegalSection({required this.title, required this.body});

  final String title;
  final String body;
}

class _LegalText extends StatelessWidget {
  const _LegalText(this.section);

  final _LegalSection section;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: CollectSpacing.x3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            section.title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          CollectSpacing.gap8,
          Text(
            section.body,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

const _privacyPolicySections = [
  _LegalSection(
    title: 'Data we collect',
    body:
        'Collect stores your Collect ID, WhatsApp sign-in phone, optional MoMo account, group memberships, group profile details, payment requests, contribution records, and permission status. Group owners may allow Collect to process MoMo SMS evidence for payment matching.',
  ),
  _LegalSection(
    title: 'How we use data',
    body:
        'We use this data to create and join groups, verify contributions, keep ledgers accurate, show notifications, prevent misuse, provide support, and maintain audit records for payment disputes.',
  ),
  _LegalSection(
    title: 'What stays private',
    body:
        'Receiver MoMo numbers, private confirmation text, sign-in phones, and support evidence are not shown on public group cards or public share links. Member-facing screens use Collect IDs and safe payment status.',
  ),
  _LegalSection(
    title: 'Sharing',
    body:
        'We share only what is needed with service providers that operate authentication, hosting, storage, messaging, support, analytics, or payment verification. We do not sell personal data.',
  ),
  _LegalSection(
    title: 'Choices and retention',
    body:
        'You can update your MoMo account, request account deletion, leave groups where supported, and contact support for correction requests. Ledger records may be retained where needed for audit, security, dispute, and legal reasons.',
  ),
];

const _termsSections = [
  _LegalSection(
    title: 'Using Collect',
    body:
        'Collect helps groups organize contributions, create payment requests, scan or share group QR codes, and maintain a verified contribution ledger. You must use accurate group, receiver, and payment information.',
  ),
  _LegalSection(
    title: 'MoMo payments',
    body:
        'Payments are approved outside Collect through MoMo or the mobile money flow shown on your device. Collect does not ask for payment credentials or sign-in secrets.',
  ),
  _LegalSection(
    title: 'Group ownership',
    body:
        'Group owners are responsible for group profile details, receiver setup, recurring settings, member management, and permission readiness. Android SMS access may be required for owner-side payment verification.',
  ),
  _LegalSection(
    title: 'Disputes and corrections',
    body:
        'If a payment is missing, duplicated, incorrect, or needs review, contact support. Collect may use payment status, transaction references, SMS evidence, and audit logs to investigate.',
  ),
  _LegalSection(
    title: 'Acceptable use',
    body:
        'Do not create misleading groups, impersonate another person, abuse QR links, submit false payment claims, or use Collect to request illegal or unauthorized payments.',
  ),
];

class AccountSessionScreen extends ConsumerWidget {
  const AccountSessionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(
      collectRepositoryProvider.select((state) => state.currentProfile),
    );
    return ScreenScaffold(
      title: 'Account',
      subtitle: profile == null ? 'No active profile' : profile.publicId,
      children: [
        CollectCard(
          child: Column(
            children: [
              CollectListTile(
                leading: CollectIcons.profile,
                title: 'Profile',
                subtitle: profile?.publicId,
                onTap: () => context.go('/settings/profile'),
              ),
              CollectListTile(
                leading: CollectIcons.momo,
                title: 'Linked MoMo',
                subtitle: profile?.momoNumber ?? 'Not linked',
                onTap: () => context.go('/settings/profile'),
              ),
              CollectListTile(
                leading: CollectIcons.error,
                title: 'Delete data',
                subtitle: 'Auditable request.',
                onTap: () => context.go('/settings/account/delete'),
              ),
              CollectListTile(
                leading: CollectIcons.lock,
                title: 'Sign out',
                subtitle: 'End session.',
                onTap: () => _confirmSignOut(context, ref),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'End this Collect session on this device. Group ledgers and verified records stay available after you sign in again.',
        ),
        actions: [
          CollectButton(
            label: 'Cancel',
            icon: CollectIcons.chevron,
            variant: CollectButtonVariant.secondary,
            onPressed: () => Navigator.of(context).pop(false),
          ),
          CollectButton(
            label: 'Sign out',
            icon: CollectIcons.lock,
            variant: CollectButtonVariant.danger,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await ref.read(collectRepositoryProvider.notifier).signOut();
    if (context.mounted) context.go('/auth');
  }
}

class DeleteAccountRequestScreen extends ConsumerStatefulWidget {
  const DeleteAccountRequestScreen({super.key});

  @override
  ConsumerState<DeleteAccountRequestScreen> createState() =>
      _DeleteAccountRequestScreenState();
}

class _DeleteAccountRequestScreenState
    extends ConsumerState<DeleteAccountRequestScreen> {
  final _reason = TextEditingController();
  bool _submitted = false;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScreenScaffold(
      title: 'Delete request',
      children: [
        if (_error != null)
          InfoSecurityBanner(
            title: 'Request failed',
            message: _error!,
            tone: CollectStatusTone.warning,
          ),
        const InfoSecurityBanner(
          title: 'Auditable',
          message: 'Some records may be retained.',
          tone: CollectStatusTone.privacy,
        ),
        if (_submitted)
          const _StateHero(
            icon: CollectIcons.check,
            title: 'Request submitted.',
            tone: CollectStatusTone.success,
          )
        else
          CollectCard(
            child: Column(
              children: [
                CollectTextInput(
                  controller: _reason,
                  label: 'Reason, optional',
                  maxLines: 4,
                  textInputAction: TextInputAction.newline,
                  textCapitalization: TextCapitalization.sentences,
                  autocorrect: true,
                ),
                CollectSpacing.gap16,
                CollectButton(
                  label: _submitting ? 'Submitting' : 'Submit',
                  icon: CollectIcons.error,
                  variant: CollectButtonVariant.danger,
                  onPressed: _submitting ? null : _confirmAndSubmit,
                  expand: true,
                ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _confirmAndSubmit() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Submit delete request?'),
        content: const Text(
          'This creates an auditable data deletion request. Some ledger, security, dispute, and legal records may be retained.',
        ),
        actions: [
          CollectButton(
            label: 'Cancel',
            icon: CollectIcons.chevron,
            variant: CollectButtonVariant.secondary,
            onPressed: () => Navigator.of(context).pop(false),
          ),
          CollectButton(
            label: 'Submit',
            icon: CollectIcons.error,
            variant: CollectButtonVariant.danger,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref
          .read(collectRepositoryProvider.notifier)
          .requestAccountDeletion(reason: _reason.text);
      if (mounted) setState(() => _submitted = true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}

class GroupMembersScreen extends ConsumerStatefulWidget {
  const GroupMembersScreen({required this.collectionId, super.key});

  final String collectionId;

  @override
  ConsumerState<GroupMembersScreen> createState() => _GroupMembersScreenState();
}

class _GroupMembersScreenState extends ConsumerState<GroupMembersScreen> {
  final _search = TextEditingController();
  String _query = '';
  _MemberFilter _filter = _MemberFilter.all;
  _MemberSort _sort = _MemberSort.contribution;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final members = ref.watch(groupMembersProvider(widget.collectionId));
    final contributions = ref.watch(
      contributionsForCollectionProvider(widget.collectionId),
    );
    final contributionTotals = <String, int>{};
    for (final contribution in contributions) {
      contributionTotals.update(
        contribution.supporterLabel,
        (amount) => amount + contribution.amountRwf,
        ifAbsent: () => contribution.amountRwf,
      );
    }
    return ScreenScaffold(
      title: 'Members',
      children: [
        SearchWithClearField(
          controller: _search,
          label: 'Search Collect ID',
          onChanged: (value) => setState(() => _query = value),
        ),
        members.when(
          data: (items) {
            final query = _query.trim().toLowerCase();
            final visible = query.isEmpty
                ? items
                : [
                    for (final item in items)
                      if (item.safeLabel.toLowerCase().contains(query) ||
                          item.role.toLowerCase().contains(query))
                        item,
                  ];
            final filtered =
                visible.where((item) {
                  return switch (_filter) {
                    _MemberFilter.all => true,
                    _MemberFilter.owner => item.role == 'owner',
                    _MemberFilter.active => item.status == 'active',
                  };
                }).toList()..sort(
                  (left, right) =>
                      _compareMembers(left, right, _sort, contributionTotals),
                );
            if (items.isEmpty) {
              return const EmptyIllustrationState(
                icon: CollectIcons.people,
                title: 'No members yet',
                message:
                    'Members appear after they join from a group QR or deep link.',
              );
            }
            if (filtered.isEmpty) {
              return EmptySearchState(
                title: 'No members found',
                message: 'No Collect ID or role matches that search.',
                onClear: () => setState(() {
                  _search.clear();
                  _query = '';
                }),
              );
            }
            final totalRaised = filtered.fold<int>(
              0,
              (sum, item) => sum + (contributionTotals[item.safeLabel] ?? 0),
            );
            final ownerCount = items
                .where((item) => item.role == 'owner')
                .length;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _MemberSummaryStrip(
                  visibleCount: filtered.length,
                  totalCount: items.length,
                  ownerCount: ownerCount,
                  totalRaised: totalRaised,
                ),
                CollectSpacing.gap12,
                CollectCard(
                  emphasis: CollectCardEmphasis.compact,
                  padding: const EdgeInsets.all(CollectSpacing.x4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'View',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ),
                          _MemberSortButton(
                            label: _memberSortLabel(_sort),
                            onTap: _showMemberSortSheet,
                          ),
                        ],
                      ),
                      CollectSpacing.gap12,
                      Wrap(
                        spacing: CollectSpacing.x2,
                        runSpacing: CollectSpacing.x2,
                        children: [
                          for (final filter in _MemberFilter.values)
                            _MemberFilterChip(
                              label: _memberFilterLabel(filter),
                              selected: _filter == filter,
                              onTap: () => setState(() => _filter = filter),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                CollectSpacing.gap12,
                SectionHeader(
                  title: 'Roster',
                  actionLabel: '${filtered.length}',
                ),
                CollectCard(
                  emphasis: CollectCardEmphasis.flat,
                  child: Column(
                    children: [
                      for (final member in filtered)
                        FinancialListRow(
                          title: compactCollectIdLabel(member.safeLabel),
                          amountRwf: contributionTotals[member.safeLabel] ?? 0,
                          meta: formatCollectDateTime(member.joinedAt),
                          subtitle: _memberSubtitle(member),
                          leading: CollectIcons.profile,
                          tone: member.role == 'owner'
                              ? CollectStatusTone.privacy
                              : CollectStatusTone.success,
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
          loading: () => const LoadingStatePanel(
            title: 'Loading members',
            message: 'Fetching group members and Collect ID roles.',
            icon: CollectIcons.people,
            lines: 4,
          ),
          error: (error, _) => CollectErrorState(
            title: 'Could not load members',
            message: error.toString(),
          ),
        ),
      ],
    );
  }

  void _showMemberSortSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return CollectBottomSheet(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Sort members',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              CollectSpacing.gap12,
              for (final sort in _MemberSort.values)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    _sort == sort ? CollectIcons.check : CollectIcons.filter,
                  ),
                  title: Text(_memberSortLabel(sort)),
                  onTap: () {
                    setState(() => _sort = sort);
                    Navigator.of(context).pop();
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}

class _MemberSummaryStrip extends StatelessWidget {
  const _MemberSummaryStrip({
    required this.visibleCount,
    required this.totalCount,
    required this.ownerCount,
    required this.totalRaised,
  });

  final int visibleCount;
  final int totalCount;
  final int ownerCount;
  final int totalRaised;

  @override
  Widget build(BuildContext context) {
    return CollectCard(
      emphasis: CollectCardEmphasis.glow,
      accentColor: context.collectColors.statusForeground(
        CollectStatusTone.success,
      ),
      child: Wrap(
        spacing: CollectSpacing.x2,
        runSpacing: CollectSpacing.x2,
        children: [
          CollectStatusChip(
            label: '$visibleCount shown',
            tone: CollectStatusTone.success,
            icon: CollectIcons.people,
          ),
          CollectStatusChip(
            label: '$totalCount total',
            tone: CollectStatusTone.info,
            icon: CollectIcons.collections,
          ),
          CollectStatusChip(
            label: '$ownerCount owner${ownerCount == 1 ? '' : 's'}',
            tone: CollectStatusTone.privacy,
            icon: CollectIcons.shield,
          ),
          CollectStatusChip(
            label: formatRwf(totalRaised),
            tone: CollectStatusTone.success,
            icon: CollectIcons.money,
          ),
        ],
      ),
    );
  }
}

class _MemberFilterChip extends StatelessWidget {
  const _MemberFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: selected ? colors.actionCrimson : colors.surfaceRaised,
        borderRadius: CollectRadius.pillBorder,
        child: InkWell(
          borderRadius: CollectRadius.pillBorder,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: CollectSpacing.x4,
              vertical: CollectSpacing.x2,
            ),
            child: Center(
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: selected ? Colors.white : colors.textPrimary,
                  fontWeight: FontWeight.w900,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MemberSortButton extends StatelessWidget {
  const _MemberSortButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Tooltip(
      message: 'Sort members',
      child: Material(
        color: colors.surfaceRaised,
        borderRadius: CollectRadius.pillBorder,
        child: InkWell(
          borderRadius: CollectRadius.pillBorder,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: CollectSpacing.x3,
              vertical: CollectSpacing.x2,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(CollectIcons.filter, size: 18),
                CollectSpacing.gapW8,
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _MemberFilter { all, owner, active }

enum _MemberSort { contribution, newest, collectId }

String _memberFilterLabel(_MemberFilter filter) {
  return switch (filter) {
    _MemberFilter.all => 'All',
    _MemberFilter.owner => 'Owner',
    _MemberFilter.active => 'Active',
  };
}

String _memberSortLabel(_MemberSort sort) {
  return switch (sort) {
    _MemberSort.contribution => 'Top',
    _MemberSort.newest => 'Newest',
    _MemberSort.collectId => 'Collect ID',
  };
}

int _compareMembers(
  CollectMember left,
  CollectMember right,
  _MemberSort sort,
  Map<String, int> totals,
) {
  return switch (sort) {
    _MemberSort.contribution => (totals[right.safeLabel] ?? 0).compareTo(
      totals[left.safeLabel] ?? 0,
    ),
    _MemberSort.newest => right.joinedAt.compareTo(left.joinedAt),
    _MemberSort.collectId => left.publicId.compareTo(right.publicId),
  };
}

String _memberSubtitle(CollectMember member) {
  final role = member.role == 'owner' ? 'Owner' : 'Member';
  final status = member.status == 'active' ? 'Active' : member.status;
  return '$role · $status';
}

class _SimpleStateScreen extends StatelessWidget {
  const _SimpleStateScreen({
    required this.title,
    required this.heroTitle,
    required this.message,
    required this.icon,
    required this.tone,
  });

  final String title;
  final String heroTitle;
  final String message;
  final IconData icon;
  final CollectStatusTone tone;

  @override
  Widget build(BuildContext context) {
    return ScreenScaffold(
      title: title,
      children: [
        _StateHero(icon: icon, title: heroTitle, tone: tone),
        CollectCard(
          emphasis: CollectCardEmphasis.flat,
          child: Text(message, style: Theme.of(context).textTheme.bodyMedium),
        ),
      ],
    );
  }
}

class _StateHero extends StatelessWidget {
  const _StateHero({
    required this.icon,
    required this.title,
    this.tone = CollectStatusTone.info,
  });

  final IconData icon;
  final String title;
  final CollectStatusTone tone;

  @override
  Widget build(BuildContext context) {
    return CollectCard(
      padding: CollectSpacing.cardPaddingComfortable,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CollectStatusChip(label: title, tone: tone, icon: icon),
          CollectSpacing.gap20,
          Text(title, style: Theme.of(context).textTheme.headlineMedium),
        ],
      ),
    );
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
    return CollectCard(
      emphasis: CollectCardEmphasis.glow,
      accentColor: context.collectColors.statusForeground(tone),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CollectStatusChip(label: title, tone: tone, icon: icon),
          CollectSpacing.gapW12,
          Expanded(
            child: Text(
              subtitle,
              style: Theme.of(context).textTheme.titleSmall,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _StepList extends StatelessWidget {
  const _StepList({required this.steps});

  final List<String> steps;

  @override
  Widget build(BuildContext context) {
    return CollectCard(
      child: Column(
        children: [
          for (var index = 0; index < steps.length; index++)
            CollectListTile(
              leading: CollectIcons.check,
              title: steps[index],
              trailing: Text(
                '${index + 1}'.padLeft(2, '0'),
                style: CollectTypography.mono(context.collectColors.textMuted),
              ),
            ),
        ],
      ),
    );
  }
}

class _ReadinessRows extends StatelessWidget {
  const _ReadinessRows({required this.rows});

  final List<_ReadinessRow> rows;

  @override
  Widget build(BuildContext context) {
    return CollectCard(
      child: Column(
        children: [
          for (final row in rows)
            CollectListTile(
              leading: row.ready ? CollectIcons.check : CollectIcons.warning,
              title: row.label,
              trailing: CollectStatusChip(
                label: row.ready ? 'Ready' : 'Needs action',
                tone: row.ready
                    ? CollectStatusTone.success
                    : CollectStatusTone.warning,
              ),
            ),
        ],
      ),
    );
  }
}

class _ReadinessRow {
  const _ReadinessRow({required this.label, required this.ready});

  final String label;
  final bool ready;
}

CollectCollection? _safeCollection(WidgetRef ref, String collectionId) {
  try {
    return ref
        .read(collectRepositoryProvider.notifier)
        .collectionById(collectionId);
  } catch (_) {
    return null;
  }
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
