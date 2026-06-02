import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/utils/money_format.dart';
import '../../shared/models/collect_models.dart';
import '../../shared/providers/collect_app_state.dart';
import '../../shared/repositories/collect_repository.dart';
import '../../shared/widgets/collect_components.dart';
import '../../shared/widgets/screen_scaffold.dart';

class OnboardingScreen extends ConsumerWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ScreenScaffold(
      title: 'Collect',
      children: [
        const MinimalStatePanel(
          icon: CollectIcons.shield,
          title: 'MoMo groups, verified by SMS.',
          message:
              'Create or join a group, contribute through MoMo, and let Collect post confirmed payments to the ledger with your private Collect ID.',
          tone: CollectStatusTone.privacy,
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
        CollectButton(
          label: 'Get started',
          icon: CollectIcons.arrowForward,
          onPressed: () {
            ref.read(onboardingCompleteProvider.notifier).state = true;
            context.go('/auth');
          },
          expand: true,
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
                  : '#${readiness.collectId}',
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
      subtitle: 'Android owners only.',
      children: [
        const MinimalStatePanel(
          icon: CollectIcons.sms,
          title: 'Automate your group ledger.',
          message:
              'Collect reads MoMo confirmation SMS on an approved Android owner device so payments can be matched and posted without manual transaction IDs.',
          tone: CollectStatusTone.privacy,
        ),
        const InfoSecurityBanner(
          title: 'Privacy boundary',
          message:
              'SMS access is used for MoMo payment confirmations. Raw SMS details are never shown on public group or share screens.',
          tone: CollectStatusTone.privacy,
        ),
        CollectButton(
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
        const MinimalStatePanel(
          icon: CollectIcons.warning,
          title: 'SMS access required.',
          message:
              'Android group owners need SMS access so Collect can verify MoMo payments and keep the ledger current.',
          tone: CollectStatusTone.warning,
        ),
        CollectButton(
          label: 'Try again',
          icon: CollectIcons.sync,
          onPressed: () => context.go('/permissions/sms'),
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
          title: 'group creation is available only on Android',
          message:
              'You can still join groups and contribute from iPhone. Group creation needs Android SMS capture for owner-side MoMo verification.',
          tone: CollectStatusTone.info,
        ),
        CollectButton(
          label: 'Scan QR',
          icon: CollectIcons.qr,
          onPressed: () => context.go('/groups'),
          expand: true,
        ),
        CollectButton(
          label: 'Join with link',
          icon: CollectIcons.arrowForward,
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
          message:
              'The group is ready for members. Share the private link or open the group to review receiver and SMS readiness before contributions start.',
          tone: CollectStatusTone.success,
        ),
        CollectButton(
          label: 'Share',
          icon: CollectIcons.share,
          onPressed: () => context.go('/groups/$collectionId/share'),
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
                message:
                    'You can review the group and contribute by MoMo. Receiver details stay inside the payment review step.',
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
          message: 'Ask for a fresh link.',
          tone: CollectStatusTone.danger,
        ),
        CollectButton(
          label: 'Open groups',
          icon: CollectIcons.collections,
          onPressed: () => context.go('/groups'),
          expand: true,
        ),
      ],
    );
  }
}

class PaymentHandoffScreen extends StatelessWidget {
  const PaymentHandoffScreen({
    required this.collectionId,
    required this.intentId,
    super.key,
  });

  final String collectionId;
  final String intentId;

  @override
  Widget build(BuildContext context) {
    return ScreenScaffold(
      title: 'Open MoMo',
      children: [
        const MinimalStatePanel(
          icon: CollectIcons.momo,
          title: 'Confirm on your phone.',
          message:
              'Collect will open the system dialer for MoMo USSD. Enter your MoMo PIN outside Collect, then return here while the receiver SMS is verified.',
        ),
        const InfoSecurityBanner(
          title: 'USSD handoff',
          message:
              'This app opens the MoMo dialer through tel:. It does not ask you to paste SMS messages or transaction IDs.',
          tone: CollectStatusTone.privacy,
        ),
        CollectButton(
          label: 'Open MoMo USSD',
          icon: CollectIcons.momo,
          onPressed: () async {
            await launchUrl(
              _momoUssdUri(),
              mode: LaunchMode.externalApplication,
            );
            if (!context.mounted) return;
            context.go('/groups/$collectionId/pay/$intentId/waiting');
          },
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
            title: 'Payment reference unavailable.',
            message:
                'Collect could not find this payment intent on the current device. Start a fresh contribution or ask support to review the reference.',
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
            onPressed: () => context.go('/settings/help'),
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
        PaymentIntentStatusCard(
          amountRwf: intent.expectedAmountRwf,
          receiverLabel: intent.receiverLabel,
          receiverMomoNumber: intent.receiverMomoNumber,
          status: intent.status,
        ),
        const PaymentPipelineIndicator(status: 'pending'),
        InfoSecurityBanner(
          title: 'Listening for MoMo SMS',
          message:
              'Collect is waiting for receiver-side MoMo SMS verification for payment intent ${intent.id}. This usually appears within a few seconds after you approve the USSD prompt.',
          tone: CollectStatusTone.info,
        ),
        InfoSecurityBanner(
          title: 'Expected timing',
          message:
              'Started ${_relativeAge(intent.createdAt)}. This intent expires ${_relativeExpiry(intent.expiresAt)} if no matching SMS is received.',
          tone: CollectStatusTone.privacy,
        ),
        InfoSecurityBanner(
          title: 'Reference',
          message:
              'Group ${collection.title}. Reference ${intent.id}. Collect posts to the ledger automatically after SMS allocation.',
          tone: CollectStatusTone.privacy,
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
          onPressed: () => context.go(
            '/groups/${widget.collectionId}/pay/${widget.intentId}/handoff',
          ),
          variant: CollectButtonVariant.secondary,
          expand: true,
        ),
        CollectButton(
          label: 'Get help',
          icon: CollectIcons.support,
          onPressed: () => context.go('/settings/help'),
          variant: CollectButtonVariant.subtle,
          expand: true,
        ),
      ],
    );
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

class PaymentStateDetailScreen extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final (title, message, tone) = switch (state) {
      PaymentUiStatus.confirmed => (
        'Payment confirmed',
        'The MoMo SMS has been matched and this contribution is now recorded on the group ledger.',
        CollectStatusTone.success,
      ),
      PaymentUiStatus.expired => (
        'Payment expired',
        'Collect did not receive a matching MoMo confirmation before this payment intent expired. You can start a fresh contribution.',
        CollectStatusTone.danger,
      ),
      PaymentUiStatus.needsReview => (
        'Payment needs review',
        'Collect detected a payment signal that could not be matched automatically. Support can review the evidence without exposing public raw SMS details.',
        CollectStatusTone.warning,
      ),
      PaymentUiStatus.pending => (
        'Payment pending',
        'Collect is still waiting for receiver-side MoMo SMS verification. Refresh the status after returning from USSD.',
        CollectStatusTone.info,
      ),
    };
    return ScreenScaffold(
      title: title,
      children: [
        if (state == PaymentUiStatus.confirmed) ...[
          const PaymentVerifiedRing(),
          const PaymentPipelineIndicator(status: 'confirmed'),
        ] else
          MinimalStatePanel(
            icon: _iconForTone(tone),
            title: title,
            message: message,
            tone: tone,
          ),
        if (state != PaymentUiStatus.confirmed)
          PaymentPipelineIndicator(status: _statusForPipeline(state)),
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
      ],
    );
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

class OfflineStateScreen extends StatelessWidget {
  const OfflineStateScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _SimpleStateScreen(
      title: 'Connection issue',
      heroTitle: 'Connection issue.',
      message:
          'Collect could not reach the service. Check the connection, then retry to refresh groups, payment status, and ledger updates.',
      icon: CollectIcons.warning,
      tone: CollectStatusTone.warning,
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
          ? 'Groups, payment intents, and ledger data are current on this device.'
          : status == RealtimeSyncStatus.syncing
          ? 'Collect is refreshing groups, payment intents, and ledger updates.'
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
    return ScreenScaffold(
      title: 'Device permissions',
      children: [
        _StateHero(
          icon: CollectIcons.tune,
          title: smsStatus == SmsPermissionStatus.granted
              ? 'SMS active.'
              : 'Review readiness.',
          message: smsStatus == SmsPermissionStatus.granted
              ? 'SMS access is active for owner-side MoMo ledger automation.'
              : 'Review SMS and notification readiness for payment progress and ledger updates.',
          tone: smsStatus == SmsPermissionStatus.granted
              ? CollectStatusTone.success
              : CollectStatusTone.info,
        ),
        CollectButton(
          label: 'SMS access details',
          icon: CollectIcons.sms,
          onPressed: () => context.go('/permissions/sms'),
          expand: true,
        ),
      ],
    );
  }
}

class PrivacyDataScreen extends StatelessWidget {
  const PrivacyDataScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ScreenScaffold(
      title: 'Privacy and data',
      children: [
        MinimalStatePanel(
          icon: CollectIcons.privacy,
          title: 'Collect ID first.',
          message:
              'Collect represents members by a generated 6-digit Collect ID. The mobile app does not ask members for real names, display names, avatars, or anonymity choices.',
          tone: CollectStatusTone.privacy,
        ),
        InfoSecurityBanner(
          title: 'MoMo and SMS boundary',
          message:
              'Payment intents, receiver MoMo details, and receiver-side MoMo SMS evidence are used to verify ledger entries. Receiver details stay inside owner and payment flows.',
          tone: CollectStatusTone.privacy,
        ),
        InfoSecurityBanner(
          title: 'Public sharing',
          message:
              'Group links and QR codes let members join or contribute without exposing the receiver MoMo number on public share surfaces.',
          tone: CollectStatusTone.info,
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
    return ScreenScaffold(
      title: 'Updates',
      subtitle: 'Payments, groups, and security.',
      children: [
        if (state.contributions.isEmpty && pendingCount == 0)
          const MinimalStatePanel(
            icon: CollectIcons.pending,
            title: 'No updates yet.',
            message:
                'Contribution confirmations, pending payment reminders, and security notices will appear here.',
            tone: CollectStatusTone.neutral,
          )
        else
          CollectCard(
            emphasis: CollectCardEmphasis.flat,
            child: Column(
              children: [
                if (latestContribution != null)
                  NotificationUpdateRow(
                    title: 'Contribution confirmed',
                    message:
                        '${formatRwf(latestContribution.amountRwf)} was recorded on the ledger.',
                    meta: latestContribution.createdAt
                        .toLocal()
                        .toString()
                        .split('.')
                        .first,
                    tone: CollectStatusTone.success,
                  ),
                if (pendingCount > 0)
                  NotificationUpdateRow(
                    title: 'Payment verification pending',
                    message:
                        '$pendingCount payment intent${pendingCount == 1 ? '' : 's'} waiting for MoMo SMS verification.',
                    meta: 'Live status',
                    tone: CollectStatusTone.info,
                  ),
                const NotificationUpdateRow(
                  title: 'Security notice',
                  message:
                      'Collect keeps receiver MoMo details inside payment and owner flows, not public share links.',
                  meta: 'Privacy boundary',
                  tone: CollectStatusTone.privacy,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class HelpSupportScreen extends ConsumerStatefulWidget {
  const HelpSupportScreen({super.key});

  @override
  ConsumerState<HelpSupportScreen> createState() => _HelpSupportScreenState();
}

class _HelpSupportScreenState extends ConsumerState<HelpSupportScreen> {
  final _subject = TextEditingController();
  final _message = TextEditingController();
  bool _submitted = false;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _subject.dispose();
    _message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScreenScaffold(
      title: 'Help',
      children: [
        if (_error != null)
          InfoSecurityBanner(
            title: 'Request failed',
            message: _error!,
            tone: CollectStatusTone.warning,
          ),
        if (_submitted)
          const MinimalStatePanel(
            icon: CollectIcons.check,
            title: 'Request saved.',
            message:
                'Support can review the request without exposing public raw SMS or receiver MoMo details.',
            tone: CollectStatusTone.success,
          )
        else
          const CollectCard(
            emphasis: CollectCardEmphasis.flat,
            child: Column(
              children: [
                CollectListTile(
                  leading: CollectIcons.momo,
                  title: 'MoMo payments',
                  subtitle: 'USSD, pending verification, and retries.',
                ),
                CollectListTile(
                  leading: CollectIcons.sms,
                  title: 'SMS verification',
                  subtitle: 'How Collect posts confirmed payments.',
                ),
                CollectListTile(
                  leading: CollectIcons.privacy,
                  title: 'Privacy and data',
                  subtitle: 'Collect ID, receiver MoMo, and audit boundaries.',
                ),
              ],
            ),
          ),
        if (!_submitted)
          CollectCard(
            child: Column(
              children: [
                TextField(
                  controller: _subject,
                  decoration: collectInputDecoration(context, label: 'Subject'),
                ),
                CollectSpacing.gap12,
                TextField(
                  controller: _message,
                  maxLines: 4,
                  decoration: collectInputDecoration(context, label: 'Message'),
                ),
                CollectSpacing.gap16,
                CollectButton(
                  label: _submitting ? 'Sending' : 'Send',
                  icon: CollectIcons.support,
                  onPressed: _submitting
                      ? null
                      : () async {
                          final subject = _subject.text.trim();
                          final message = _message.text.trim();
                          if (subject.isEmpty || message.isEmpty) {
                            setState(() {
                              _error = subject.isEmpty
                                  ? 'Subject required.'
                                  : 'Message required.';
                            });
                            return;
                          }
                          setState(() {
                            _submitting = true;
                            _error = null;
                          });
                          try {
                            await ref
                                .read(collectRepositoryProvider.notifier)
                                .createSupportRequest(
                                  subject: subject,
                                  message: message,
                                );
                            if (mounted) setState(() => _submitted = true);
                          } catch (error) {
                            if (mounted) {
                              setState(() => _error = error.toString());
                            }
                          } finally {
                            if (mounted) setState(() => _submitting = false);
                          }
                        },
                  expand: true,
                ),
              ],
            ),
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
    final points = isPrivacy ? _privacyPolicyPoints : _termsPoints;
    return ScreenScaffold(
      title: isPrivacy ? 'Privacy policy' : 'Terms',
      children: [
        MinimalStatePanel(
          icon: isPrivacy ? CollectIcons.privacy : CollectIcons.info,
          title: isPrivacy ? 'Privacy policy' : 'Collect terms',
          message: isPrivacy
              ? 'Collect uses Collect IDs, MoMo profile details, payment intents, and SMS verification evidence to operate group ledgers.'
              : 'Collect supports group contributions through MoMo payment intents and automated SMS verification. Payment completion happens outside Collect in MoMo USSD.',
          tone: isPrivacy ? CollectStatusTone.privacy : CollectStatusTone.info,
        ),
        CollectCard(
          emphasis: CollectCardEmphasis.flat,
          child: Column(
            children: [
              for (final point in points)
                CollectListTile(
                  leading: point.icon,
                  title: point.title,
                  subtitle: point.message,
                ),
            ],
          ),
        ),
        InfoSecurityBanner(
          title: isPrivacy ? 'Public boundary' : 'Security responsibility',
          message: isPrivacy
              ? 'Raw SMS, receiver MoMo numbers, and support evidence are not public group content. Public screens use Collect IDs, amounts, group names, and safe status labels.'
              : 'Confirm the group, receiver label, and amount before approving MoMo. Collect will never ask for a MoMo PIN, OTP, or WhatsApp code inside support messages.',
          tone: isPrivacy
              ? CollectStatusTone.privacy
              : CollectStatusTone.warning,
        ),
      ],
    );
  }
}

class _LegalPoint {
  const _LegalPoint({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;
}

const _privacyPolicyPoints = [
  _LegalPoint(
    icon: CollectIcons.profile,
    title: 'Profile data',
    message:
        'Collect stores a generated Collect ID, WhatsApp sign-in phone, and optional MoMo number needed for payment readiness.',
  ),
  _LegalPoint(
    icon: CollectIcons.momo,
    title: 'Payment data',
    message:
        'Payment intents include group, amount, receiver label, status, expiry, and references needed to reconcile MoMo confirmations.',
  ),
  _LegalPoint(
    icon: CollectIcons.sms,
    title: 'SMS evidence',
    message:
        'Owner-side MoMo SMS evidence may be processed for allocation, support review, audit logs, and ledger integrity.',
  ),
  _LegalPoint(
    icon: CollectIcons.support,
    title: 'Support review',
    message:
        'Support requests can reference payment status and audit evidence without exposing raw SMS content on public member screens.',
  ),
];

const _termsPoints = [
  _LegalPoint(
    icon: CollectIcons.momo,
    title: 'MoMo approval',
    message:
        'The contributor approves payment in MoMo USSD. Collect records the contribution only after confirmation evidence is available.',
  ),
  _LegalPoint(
    icon: CollectIcons.ledger,
    title: 'Ledger status',
    message:
        'Confirmed, pending, expired, and review states describe verification progress. Pending or review states are not final ledger entries.',
  ),
  _LegalPoint(
    icon: CollectIcons.people,
    title: 'Group ownership',
    message:
        'Group owners are responsible for using the correct receiver account and keeping receiver-side SMS access aligned with local requirements.',
  ),
  _LegalPoint(
    icon: CollectIcons.support,
    title: 'Disputes and corrections',
    message:
        'If a payment does not match automatically, use support so the issue can be reviewed against available evidence and audit records.',
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
      subtitle: profile == null ? 'No active profile' : '#${profile.publicId}',
      children: [
        CollectCard(
          child: Column(
            children: [
              CollectListTile(
                leading: CollectIcons.profile,
                title: 'Profile',
                subtitle: profile == null ? null : '#${profile.publicId}',
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
        content: const Text('End this session.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sign out'),
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
            message: 'Collect will review it.',
            tone: CollectStatusTone.success,
          )
        else
          CollectCard(
            child: Column(
              children: [
                TextField(
                  controller: _reason,
                  maxLines: 4,
                  decoration: collectInputDecoration(
                    context,
                    label: 'Reason, optional',
                  ),
                ),
                CollectSpacing.gap16,
                CollectButton(
                  label: _submitting ? 'Submitting' : 'Submit',
                  icon: CollectIcons.error,
                  variant: CollectButtonVariant.danger,
                  onPressed: _submitting
                      ? null
                      : () async {
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
                            if (mounted) {
                              setState(() => _error = error.toString());
                            }
                          } finally {
                            if (mounted) setState(() => _submitting = false);
                          }
                        },
                  expand: true,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class OwnerSmsHealthScreen extends ConsumerWidget {
  const OwnerSmsHealthScreen({required this.collectionId, super.key});

  final String collectionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final health = ref.watch(ownerGroupHealthProvider(collectionId));
    final repo = ref.read(collectRepositoryProvider.notifier);
    final collection = _safeCollection(ref, collectionId);
    final summary = repo.summaryFor(collectionId);
    return ScreenScaffold(
      title: 'SMS health',
      subtitle: collection?.title,
      children: [
        MoneyHeroCard(
          amount: summary.amountRaisedRwf,
          label: 'Confirmed support',
          detail: '${summary.supporterCount} ledger entries',
        ),
        health.when(
          data: (item) => Column(
            children: [
              _ReadinessRows(
                rows: [
                  _ReadinessRow(
                    label: 'Receiver configured',
                    ready: item.receiverConfigured,
                  ),
                  _ReadinessRow(
                    label: 'SMS access',
                    ready: item.smsAccessEnabled,
                  ),
                  _ReadinessRow(
                    label: '${item.pendingPaymentIntents} pending intents',
                    ready: item.pendingPaymentIntents == 0,
                  ),
                  _ReadinessRow(
                    label: '${item.needsReviewEvents} review events',
                    ready: item.needsReviewEvents == 0,
                  ),
                ],
              ),
              InfoSecurityBanner(
                title: item.ready ? 'Automation ready' : 'Action needed',
                message: item.ready
                    ? 'Collect can use receiver-side MoMo SMS evidence to keep this ledger current.'
                    : 'Enable SMS access and confirm the receiver MoMo setup before relying on automated ledger updates.',
                tone: item.ready
                    ? CollectStatusTone.success
                    : CollectStatusTone.warning,
              ),
            ],
          ),
          loading: () => const LoadingSkeleton(lines: 4),
          error: (error, _) => CollectErrorState(
            title: 'Could not load health',
            message: error.toString(),
          ),
        ),
      ],
    );
  }
}

class OwnerReceiverManagementScreen extends ConsumerStatefulWidget {
  const OwnerReceiverManagementScreen({required this.collectionId, super.key});

  final String collectionId;

  @override
  ConsumerState<OwnerReceiverManagementScreen> createState() =>
      _OwnerReceiverManagementScreenState();
}

class _OwnerReceiverManagementScreenState
    extends ConsumerState<OwnerReceiverManagementScreen> {
  final _receiver = TextEditingController();
  final _label = TextEditingController(text: 'Primary');
  bool _synced = false;

  @override
  void dispose() {
    _receiver.dispose();
    _label.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final collection = _safeCollection(ref, widget.collectionId);
    if (!_synced && collection != null) {
      _receiver.text = collection.receiverMomoNumber ?? '';
      _label.text = collection.receiverDisplayLabel;
      _synced = true;
    }
    return ScreenScaffold(
      title: 'MoMo',
      subtitle: collection?.title,
      children: [
        CollectCard(
          child: Column(
            children: [
              TextField(
                controller: _label,
                decoration: collectInputDecoration(context, label: 'Name'),
              ),
              CollectSpacing.gap12,
              TextField(
                controller: _receiver,
                keyboardType: TextInputType.phone,
                decoration: collectInputDecoration(
                  context,
                  label: 'MoMo number',
                ),
              ),
              CollectSpacing.gap16,
              CollectButton(
                label: 'Save',
                icon: CollectIcons.check,
                onPressed: () async {
                  await ref
                      .read(collectRepositoryProvider.notifier)
                      .updateCollectionReceiver(
                        collectionId: widget.collectionId,
                        receiverMomoNumber: _receiver.text,
                        receiverLabel: _label.text,
                      );
                  if (!context.mounted) return;
                  context.go('/groups/${widget.collectionId}/manage');
                },
                expand: true,
              ),
            ],
          ),
        ),
      ],
    );
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

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final members = ref.watch(groupMembersProvider(widget.collectionId));
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
            if (items.isEmpty) {
              return const EmptyIllustrationState(
                icon: CollectIcons.people,
                title: 'No members yet',
                message:
                    'Members appear after they join this group with a Collect link, code, or QR.',
              );
            }
            if (visible.isEmpty) {
              return EmptySearchState(
                title: 'No members found',
                message: 'No Collect ID or role matches that search.',
                onClear: () => setState(() {
                  _search.clear();
                  _query = '';
                }),
              );
            }
            return CollectCard(
              emphasis: CollectCardEmphasis.flat,
              child: Column(
                children: [
                  for (final member in visible)
                    FinancialListRow(
                      title: compactCollectIdLabel(member.safeLabel),
                      meta: member.joinedAt
                          .toLocal()
                          .toString()
                          .split('.')
                          .first,
                      subtitle: '${member.role} · ${member.status}',
                      leading: CollectIcons.profile,
                      tone: member.role == 'owner'
                          ? CollectStatusTone.privacy
                          : CollectStatusTone.neutral,
                    ),
                ],
              ),
            );
          },
          loading: () => const LoadingSkeleton(lines: 4),
          error: (error, _) => CollectErrorState(
            title: 'Could not load members',
            message: error.toString(),
          ),
        ),
      ],
    );
  }
}

class GroupOwnerDashboardScreen extends ConsumerWidget {
  const GroupOwnerDashboardScreen({required this.collectionId, super.key});

  final String collectionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collection = _safeCollection(ref, collectionId);
    final repo = ref.read(collectRepositoryProvider.notifier);
    final summary = repo.summaryFor(collectionId);
    final health = ref.watch(ownerGroupHealthProvider(collectionId));
    return ScreenScaffold(
      title: 'Owner',
      subtitle: collection?.title,
      children: [
        MoneyHeroCard(
          amount: summary.amountRaisedRwf,
          label: 'Owner dashboard',
          detail: '${summary.supporterCount} confirmed ledger entries',
        ),
        health.when(
          data: (item) => CollectBentoGrid(
            primary: BentoMetricCell(
              label: 'Pending',
              value: '${item.pendingPaymentIntents}',
              detail: 'Payment intents',
              icon: CollectIcons.pending,
              tone: item.pendingPaymentIntents == 0
                  ? CollectStatusTone.neutral
                  : CollectStatusTone.info,
              emphasis: true,
            ),
            top: BentoMetricCell(
              label: 'Review',
              value: '${item.needsReviewEvents}',
              detail: 'Exceptions',
              icon: CollectIcons.warning,
              tone: item.needsReviewEvents == 0
                  ? CollectStatusTone.neutral
                  : CollectStatusTone.warning,
            ),
            bottom: BentoMetricCell(
              label: 'SMS',
              value: item.smsAccessEnabled ? 'On' : 'Off',
              detail: item.receiverConfigured
                  ? 'Receiver set'
                  : 'Receiver missing',
              icon: CollectIcons.sms,
              tone: item.ready
                  ? CollectStatusTone.success
                  : CollectStatusTone.warning,
            ),
          ),
          loading: () => const LoadingSkeleton(lines: 3),
          error: (error, _) => InfoSecurityBanner(
            title: 'Health unavailable',
            message: error.toString(),
            tone: CollectStatusTone.warning,
          ),
        ),
        CollectCard(
          child: Column(
            children: [
              CollectListTile(
                leading: CollectIcons.sms,
                title: 'SMS health',
                subtitle: 'Status.',
                onTap: () =>
                    context.go('/groups/$collectionId/owner/sms-health'),
              ),
              CollectListTile(
                leading: CollectIcons.momo,
                title: 'MoMo',
                subtitle: 'Owner only.',
                onTap: () => context.go('/groups/$collectionId/owner/receiver'),
              ),
              CollectListTile(
                leading: CollectIcons.people,
                title: 'Members',
                subtitle: 'Active.',
                onTap: () => context.go('/groups/$collectionId/members'),
              ),
              CollectListTile(
                leading: CollectIcons.share,
                title: 'Share',
                subtitle: 'Link, QR, chat.',
                onTap: () => context.go('/groups/$collectionId/share'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class ShareConfirmationScreen extends StatelessWidget {
  const ShareConfirmationScreen({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return _SimpleStateScreen(
      title: 'Share ready',
      heroTitle: message,
      message:
          'The share action is prepared without exposing receiver MoMo details on the public link.',
      icon: CollectIcons.check,
      tone: CollectStatusTone.success,
    );
  }
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
        _StateHero(icon: icon, title: heroTitle, message: message, tone: tone),
      ],
    );
  }
}

class _StateHero extends StatelessWidget {
  const _StateHero({
    required this.icon,
    required this.title,
    required this.message,
    this.tone = CollectStatusTone.info,
  });

  final IconData icon;
  final String title;
  final String message;
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
          if (message.trim().isNotEmpty) ...[
            CollectSpacing.gap8,
            Text(message, style: Theme.of(context).textTheme.bodyMedium),
          ],
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
