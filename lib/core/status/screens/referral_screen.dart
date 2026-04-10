import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/auth/models/user_profile.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/core_detail_scaffold.dart';
import '../../../shared/widgets/share_card.dart';
import '../../config/deep_link_config.dart';
import '../../providers/referral_providers.dart';
import '../../theme/cool_foundations.dart';

class ReferralScreen extends ConsumerWidget {
  const ReferralScreen({super.key});

  static const _campaignId = 'cool_referral';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.coolSemanticColors;
    final space = context.coolSpace;
    final theme = Theme.of(context);
    final user = ref.watch(currentUserProvider);

    return CoreDetailScaffold(
      title: Text(
        'Invite friends to COOL',
        style: context.coolText.displayCondensed(
          theme.textTheme.headlineSmall,
          fontWeight: FontWeight.w900,
        ),
      ),
      subtitle: Text(
        'Share a tracked invite link so friends join with your code and finish their first activity.',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: colors.secondaryText,
        ),
      ),
      child: ListView(
        padding: EdgeInsets.only(bottom: space.x8),
        children: [
          if (user == null) ...[
            CoolCard(
              child: Text(
                'Sign in to generate a referral invite.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.primaryText,
                ),
              ),
            ),
          ] else ...[
            _ReferralRewardCard(user: user),
            SizedBox(height: space.x4),
            _ReferralCodeCard(inviteCode: _inviteCodeFor(user)),
            SizedBox(height: space.x4),
            ShareCard(
              title: 'Share your referral link',
              subtitle:
                  'Your friend earns 50 points after their first qualifying activity. You earn 150.',
              shareUrl: _inviteUriFor(user).toString(),
              shareText:
                  'Join COOL with my invite code ${_inviteCodeFor(user)}',
              sheetTitle: 'Share your referral invite',
              sheetSubtitle: 'Scan the QR code or share your tracked link',
              analyticsTargetType: 'referral',
              resolveShareUrl: () => _createTrackedInviteUrl(ref, user),
            ),
          ],
        ],
      ),
    );
  }

  static Future<String> _createTrackedInviteUrl(
    WidgetRef ref,
    UserProfile user,
  ) async {
    final inviteCode = _inviteCodeFor(user);
    final invite = await ref
        .read(referralRepositoryProvider)
        .createInviteLink(
          inviteCode: inviteCode,
          baseUri: _inviteUriFor(user),
          shareChannel: 'app_share',
          campaignId: _campaignId,
        );
    return invite.uri.toString();
  }

  static Uri _inviteUriFor(UserProfile user) {
    final inviteCode = _inviteCodeFor(user);
    return DeepLinkConfig.inviteUri(
      inviteCode,
      queryParameters: <String, String>{'code': inviteCode},
    );
  }

  static String _inviteCodeFor(UserProfile user) {
    final seed =
        (user.persistedPublicUserId.isNotEmpty
                ? user.persistedPublicUserId
                : user.displayUserId)
            .toUpperCase()
            .replaceAll(RegExp(r'[^A-Z0-9]'), '');

    final fallback = user.id.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final merged = '${seed}COOL$fallback';
    return merged.substring(0, merged.length >= 8 ? 8 : merged.length);
  }
}

class _ReferralRewardCard extends StatelessWidget {
  const _ReferralRewardCard({required this.user});

  final UserProfile user;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);

    return CoolCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Referral rewards',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: colors.primaryText,
            ),
          ),
          const SizedBox(height: CoolSpace.x3),
          Text(
            '${user.fullName.trim().isEmpty ? 'You' : user.fullName.trim()} can share a tracked invite link. When a friend signs up and completes their first activity, rewards are credited through the referral backend.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.secondaryText,
            ),
          ),
          const SizedBox(height: CoolSpace.x4),
          const Row(
            children: [
              _RewardPill(label: 'You', value: '150 pts'),
              SizedBox(width: CoolSpace.x3),
              _RewardPill(label: 'Friend', value: '50 pts'),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReferralCodeCard extends StatelessWidget {
  const _ReferralCodeCard({required this.inviteCode});

  final String inviteCode;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);

    return CoolCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Invite code',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: colors.primaryText,
            ),
          ),
          const SizedBox(height: CoolSpace.x2),
          Text(
            inviteCode,
            style: context.coolText.mono(
              theme.textTheme.headlineSmall,
              fontWeight: FontWeight.w900,
              color: colors.accent,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: CoolSpace.x2),
          Text(
            'Every shared link keeps this invite code and adds referral attribution for tracking.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.tertiaryText,
            ),
          ),
        ],
      ),
    );
  }
}

class _RewardPill extends StatelessWidget {
  const _RewardPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);

    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(CoolSpace.x3),
        decoration: BoxDecoration(
          color: colors.accent.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(CoolRadii.md),
          border: Border.all(color: colors.accent.withValues(alpha: 0.18)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: context.coolText.mono(
                theme.textTheme.labelSmall,
                fontWeight: FontWeight.w700,
                color: colors.secondaryText,
              ),
            ),
            const SizedBox(height: CoolSpace.x1),
            Text(
              value,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
                color: colors.primaryText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
