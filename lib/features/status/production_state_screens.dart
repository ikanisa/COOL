import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

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
      subtitle: 'Group MoMo collections verified from SMS.',
      children: [
        const _StateHero(
          icon: CollectIcons.shield,
          title: 'Collect tracks group support without holding money.',
          message:
              'Create or join groups, contribute through MoMo, and let receiver SMS verification update the ledger.',
        ),
        const _StepList(
          steps: [
            'Sign in with WhatsApp OTP.',
            'Use your generated 6-digit Collect ID.',
            'Contribute through MoMo USSD.',
            'Wait for verified SMS allocation.',
          ],
        ),
        CollectButton(
          label: 'Start',
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
      title: success ? 'OTP verified' : 'OTP could not be verified',
      children: [
        _StateHero(
          icon: success ? CollectIcons.check : CollectIcons.error,
          title: success
              ? 'Your Collect session is active.'
              : 'Try the OTP again.',
          message: success
              ? 'Finish profile setup so your Collect ID and MoMo number are ready.'
              : 'Use the latest WhatsApp OTP. Collect does not need your real name.',
          tone: success ? CollectStatusTone.success : CollectStatusTone.danger,
        ),
        CollectButton(
          label: success ? 'Continue to profile' : 'Back to sign in',
          icon: success ? CollectIcons.profile : CollectIcons.sms,
          onPressed: () => context.go(success ? '/settings/profile' : '/auth'),
          expand: true,
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
          : 'Finish your profile',
      children: [
        _ReadinessRows(
          rows: [
            _ReadinessRow(
              label: readiness.collectId == null
                  ? 'Collect ID pending'
                  : 'Collect ID ${readiness.collectId}',
              ready: readiness.hasProfile,
            ),
            _ReadinessRow(
              label: 'MoMo number saved',
              ready: readiness.hasMomoNumber,
            ),
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
      subtitle: 'Required only for Android group owners.',
      children: [
        const _StateHero(
          icon: CollectIcons.sms,
          title: 'Collect reads approved receiver MoMo notifications.',
          message:
              'SMS access lets Collect upload official MoMo payment messages so the backend can verify group contributions.',
          tone: CollectStatusTone.privacy,
        ),
        const InfoSecurityBanner(
          title: 'Protected evidence',
          message:
              'Raw SMS is never shown in member screens and remains restricted for audit.',
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
        const _StateHero(
          icon: CollectIcons.warning,
          title: 'Group creation needs Android SMS access.',
          message:
              'Without SMS access, Collect cannot verify receiver MoMo notifications automatically.',
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
        const _StateHero(
          icon: CollectIcons.momo,
          title: 'group creation is available only on Android',
          message:
              'iPhone users can still join groups, contribute through MoMo, and view ledgers.',
          tone: CollectStatusTone.info,
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
          title: collection?.title ?? 'Your group is ready.',
          message: 'Share the group link or open the group workspace.',
          tone: CollectStatusTone.success,
        ),
        CollectButton(
          label: 'Share group',
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
        _StateHero(
          icon: CollectIcons.check,
          title: collection?.title ?? 'You joined this group.',
          message:
              'Your member identity is your Collect ID. Real names are not shown.',
          tone: CollectStatusTone.success,
        ),
        CollectButton(
          label: 'Open group',
          icon: CollectIcons.collections,
          onPressed: () => context.go('/groups/$collectionId'),
          expand: true,
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
          title: expired
              ? 'This group link has expired.'
              : 'This group link could not be opened.',
          message: 'Ask the group owner for a fresh Collect link.',
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
        const _StateHero(
          icon: CollectIcons.momo,
          title: 'Complete payment in MoMo.',
          message:
              'Collect has created the payment intent. Open the USSD menu, finish with your MoMo PIN, then return to Collect.',
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

class ReturnFromMomoWaitingScreen extends StatelessWidget {
  const ReturnFromMomoWaitingScreen({
    required this.collectionId,
    required this.intentId,
    super.key,
  });

  final String collectionId;
  final String intentId;

  @override
  Widget build(BuildContext context) {
    return ScreenScaffold(
      title: 'Waiting for SMS',
      children: [
        const _StateHero(
          icon: CollectIcons.pending,
          title: 'Collect is waiting for receiver MoMo SMS.',
          message:
              'The group ledger updates after backend parsing and allocation. You do not need to submit a reference.',
          tone: CollectStatusTone.info,
        ),
        CollectButton(
          label: 'View status',
          icon: CollectIcons.pending,
          onPressed: () => context.go('/groups/$collectionId/pay/$intentId'),
          expand: true,
        ),
      ],
    );
  }
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
        'The contribution is posted to the group ledger.',
        CollectStatusTone.success,
      ),
      PaymentUiStatus.expired => (
        'Payment intent expired',
        'Create a new contribution intent before paying again.',
        CollectStatusTone.danger,
      ),
      PaymentUiStatus.needsReview => (
        'Payment needs review',
        'Collect could not safely match the SMS yet. Admin review stays outside member confirmation.',
        CollectStatusTone.warning,
      ),
      PaymentUiStatus.pending => (
        'Payment pending',
        'Collect is still waiting for verified receiver MoMo SMS.',
        CollectStatusTone.info,
      ),
    };
    return ScreenScaffold(
      title: title,
      children: [
        _StateHero(
          icon: _iconForTone(tone),
          title: title,
          message: message,
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
      ],
    );
  }
}

class OfflineStateScreen extends StatelessWidget {
  const OfflineStateScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _SimpleStateScreen(
      title: 'Connection issue',
      heroTitle: 'Collect cannot reach the network right now.',
      message:
          'You can keep reviewing local information. Payment status refreshes when connection returns.',
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
      RealtimeSyncStatus.current => 'Realtime is current',
      RealtimeSyncStatus.syncing => 'Syncing Collect updates',
      RealtimeSyncStatus.needsAttention => 'Sync needs attention',
    };
    return _SimpleStateScreen(
      title: 'Sync status',
      heroTitle: title,
      message:
          'Collect refreshes profiles, groups, payment intents, allocations, ledgers, receivers, and SMS event state from Supabase realtime invalidations.',
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
              ? 'Android SMS access is active.'
              : 'Review device readiness.',
          message:
              'Push notifications are not required for this release. Android group owners need SMS access for receiver MoMo verification.',
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
    return const _SimpleStateScreen(
      title: 'Privacy and data',
      heroTitle: 'Collect ID is the public identity.',
      message:
          'Raw SMS, phone numbers, and receiver MoMo details stay restricted. Member screens use Collect IDs and safe ledger labels.',
      icon: CollectIcons.privacy,
      tone: CollectStatusTone.privacy,
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

  @override
  void dispose() {
    _subject.dispose();
    _message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScreenScaffold(
      title: 'Help and support',
      children: [
        if (_submitted)
          const _StateHero(
            icon: CollectIcons.check,
            title: 'Support request saved.',
            message:
                'The Collect team can review this without exposing raw SMS in member screens.',
            tone: CollectStatusTone.success,
          )
        else
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
                  label: 'Send support request',
                  icon: CollectIcons.support,
                  onPressed: () async {
                    await ref
                        .read(collectRepositoryProvider.notifier)
                        .createSupportRequest(
                          subject: _subject.text,
                          message: _message.text,
                        );
                    if (mounted) setState(() => _submitted = true);
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
    return _SimpleStateScreen(
      title: isPrivacy ? 'Privacy policy' : 'Terms',
      heroTitle: isPrivacy
          ? 'Privacy policy for Collect data.'
          : 'Terms for SMS-verified group collections.',
      message:
          'Collect records contribution evidence and protects sensitive fields. Full legal text can be backed by hosted policy links before release.',
      icon: isPrivacy ? CollectIcons.privacy : CollectIcons.info,
      tone: isPrivacy ? CollectStatusTone.privacy : CollectStatusTone.info,
    );
  }
}

class AccountSessionScreen extends ConsumerWidget {
  const AccountSessionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(
      collectRepositoryProvider.select((state) => state.currentProfile),
    );
    return ScreenScaffold(
      title: 'Account',
      subtitle: profile == null ? 'No active profile' : profile.safeAlias,
      children: [
        CollectCard(
          child: Column(
            children: [
              CollectListTile(
                leading: CollectIcons.profile,
                title: 'Profile',
                subtitle: 'Collect ID and MoMo number.',
                onTap: () => context.go('/settings/profile'),
              ),
              CollectListTile(
                leading: CollectIcons.error,
                title: 'Delete account or data request',
                subtitle: 'Submit an auditable request.',
                onTap: () => context.go('/settings/account/delete'),
              ),
              CollectListTile(
                leading: CollectIcons.lock,
                title: 'Sign out',
                subtitle: 'End this device session.',
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
        content: const Text('This ends the Collect session on this device.'),
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

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScreenScaffold(
      title: 'Delete account request',
      children: [
        const InfoSecurityBanner(
          title: 'Auditable request',
          message:
              'Ledger and payment evidence may need retention. Collect records deletion requests for review instead of unsafe immediate deletion.',
          tone: CollectStatusTone.privacy,
        ),
        if (_submitted)
          const _StateHero(
            icon: CollectIcons.check,
            title: 'Request submitted.',
            message: 'Collect will review the account/data request.',
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
                  label: 'Submit request',
                  icon: CollectIcons.error,
                  variant: CollectButtonVariant.danger,
                  onPressed: () async {
                    await ref
                        .read(collectRepositoryProvider.notifier)
                        .requestAccountDeletion(reason: _reason.text);
                    if (mounted) setState(() => _submitted = true);
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
    return ScreenScaffold(
      title: 'SMS automation health',
      children: [
        health.when(
          data: (item) => _ReadinessRows(
            rows: [
              _ReadinessRow(
                label: 'Receiver configured',
                ready: item.receiverConfigured,
              ),
              _ReadinessRow(
                label: 'SMS access enabled',
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
  final _label = TextEditingController(text: 'Primary MOMO receiver');
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
      title: 'Receiver MoMo',
      subtitle: collection?.title,
      children: [
        const InfoSecurityBanner(
          title: 'Owner-only receiver',
          message:
              'Receiver MoMo details stay out of normal member group screens.',
          tone: CollectStatusTone.privacy,
        ),
        CollectCard(
          child: Column(
            children: [
              TextField(
                controller: _label,
                decoration: collectInputDecoration(context, label: 'Label'),
              ),
              CollectSpacing.gap12,
              TextField(
                controller: _receiver,
                keyboardType: TextInputType.phone,
                decoration: collectInputDecoration(
                  context,
                  label: 'Receiver MoMo number',
                ),
              ),
              CollectSpacing.gap16,
              CollectButton(
                label: 'Save receiver',
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

class GroupMembersScreen extends ConsumerWidget {
  const GroupMembersScreen({required this.collectionId, super.key});

  final String collectionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final members = ref.watch(groupMembersProvider(collectionId));
    return ScreenScaffold(
      title: 'Group members',
      subtitle: 'Collect IDs only.',
      children: [
        members.when(
          data: (items) => items.isEmpty
              ? const EmptyIllustrationState(
                  icon: CollectIcons.people,
                  title: 'No members yet',
                  message: 'Members appear by Collect ID after joining.',
                )
              : CollectCard(
                  child: Column(
                    children: [
                      for (final member in items)
                        CollectListTile(
                          leading: CollectIcons.profile,
                          title: member.safeLabel,
                          subtitle: '${member.role} · ${member.status}',
                          trailing: const CollectStatusChip(
                            label: 'Private',
                            tone: CollectStatusTone.privacy,
                          ),
                        ),
                    ],
                  ),
                ),
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
    return ScreenScaffold(
      title: 'Owner dashboard',
      subtitle: collection?.title,
      children: [
        CollectCard(
          child: Column(
            children: [
              CollectListTile(
                leading: CollectIcons.sms,
                title: 'SMS automation health',
                subtitle:
                    'Receiver, consent, pending intents, and review state.',
                onTap: () =>
                    context.go('/groups/$collectionId/owner/sms-health'),
              ),
              CollectListTile(
                leading: CollectIcons.momo,
                title: 'Receiver MoMo',
                subtitle: 'Owner-side receiver configuration.',
                onTap: () => context.go('/groups/$collectionId/owner/receiver'),
              ),
              CollectListTile(
                leading: CollectIcons.people,
                title: 'Members',
                subtitle: 'Safe Collect ID member list.',
                onTap: () => context.go('/groups/$collectionId/members'),
              ),
              CollectListTile(
                leading: CollectIcons.share,
                title: 'Share group',
                subtitle: 'Link, QR, SMS, and chat apps.',
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
          'Group links do not include phone numbers, receiver MoMo details, or raw SMS.',
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
          CollectSpacing.gap8,
          Text(message, style: Theme.of(context).textTheme.bodyMedium),
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
              subtitle: 'Step ${index + 1}',
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
