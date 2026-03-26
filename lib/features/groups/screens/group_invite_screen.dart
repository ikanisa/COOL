import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/providers/engagement_providers.dart';
import '../../../core/providers/referral_providers.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_error_view.dart';
import '../../../shared/widgets/cool_screen_background.dart';
import '../../../shared/widgets/cool_skeleton.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/group_detail.dart';
import '../providers/groups_provider.dart';
import '../widgets/group_detail/group_detail_helpers.dart';

class GroupInviteScreen extends ConsumerStatefulWidget {
  const GroupInviteScreen({
    required this.inviteCode,
    this.referralParameters = const <String, String>{},
    super.key,
  });

  final String inviteCode;
  final Map<String, String> referralParameters;

  @override
  ConsumerState<GroupInviteScreen> createState() => _GroupInviteScreenState();
}

class _GroupInviteScreenState extends ConsumerState<GroupInviteScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      ref.read(groupsProvider.notifier).clearInvitePreviewState();
      ref.read(groupsProvider.notifier).clearJoinGroupState();
      await ref
          .read(groupsProvider.notifier)
          .loadInvitePreview(widget.inviteCode);
      await ref
          .read(engagementTrackerProvider)
          .trackInviteOpened(
            inviteCode: widget.inviteCode,
            queryParameters: widget.referralParameters,
          );
    });
  }

  Future<void> _handlePrimaryAction(GroupDetail detail) async {
    if (detail.isMember) {
      final groupId = detail.group.id;
      if (groupId != null && groupId.isNotEmpty) {
        context.go('/groups/$groupId');
      }
      return;
    }

    final authState = ref.read(authProvider);
    if (authState.session == null) {
      // Sign in anonymously first, then retry.
      await ref.read(authProvider.notifier).signInAnonymously();
      if (!mounted) return;
      final updatedState = ref.read(authProvider);
      if (updatedState.session == null) {
        CoolToast.error(context, 'Could not sign in. Please try again.');
        return;
      }
    }

    final result = await ref
        .read(groupsProvider.notifier)
        .joinGroupByInviteCode(widget.inviteCode);

    if (!mounted) return;

    if (result == null) {
      final error =
          ref.read(groupJoinErrorProvider) ?? 'Could not join this group.';
      CoolToast.error(context, error);
      return;
    }

    final groupId = result.detail.group.id;
    if (groupId == null || groupId.isEmpty) {
      return;
    }

    if (result.didJoin) {
      await ref
          .read(engagementTrackerProvider)
          .trackInviteAccepted(
            inviteCode: widget.inviteCode,
            groupId: groupId,
            queryParameters: widget.referralParameters,
          );
      final referralInviteId = widget.referralParameters['ri']?.trim();
      if (referralInviteId != null && referralInviteId.isNotEmpty) {
        try {
          await ref
              .read(referralRepositoryProvider)
              .activateInvite(
                inviteId: referralInviteId,
                qualifyingEventType: 'group_joined',
                qualifyingEventId: groupId,
                inviterPoints: 100,
                inviteePoints: 40,
              );
          ref
              .read(activeReferralAttributionProvider.notifier)
              .clearIfMatches(referralInviteId);
        } catch (_) {
          // Joining the group should still succeed if referral activation fails.
        }
      }
    }

    if (!mounted) return;

    final message = result.didJoin
        ? 'You joined ${result.detail.group.name}.'
        : 'You are already a member of ${result.detail.group.name}.';
    CoolToast.success(context, message);
    context.go('/groups/$groupId');
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final theme = Theme.of(context);
    final detail = ref.watch(groupInvitePreviewProvider);
    final isPreviewLoading = ref.watch(groupInvitePreviewLoadingProvider);
    final previewError = ref.watch(groupInvitePreviewErrorProvider);
    final isJoining = ref.watch(groupJoinLoadingProvider);

    return CoolScreenBackground(
      showGlow: true,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          leading: IconButton(
            tooltip: context.l10n.back,
            onPressed: () => context.pop(),
            icon: Icon(Icons.arrow_back_rounded, color: colors.primaryText),
          ),
          title: Text(
            'Group invite',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: colors.primaryText,
            ),
          ),
        ),
        body: isPreviewLoading && detail == null
            ? const Padding(
                padding: EdgeInsets.fromLTRB(
                  CoolSpace.x4,
                  CoolSpace.x4,
                  CoolSpace.x4,
                  96,
                ),
                child: CoolSkeletonList(itemCount: 3),
              )
            : previewError != null && detail == null
            ? _InviteErrorState(
                error: previewError,
                onRetry: () => ref
                    .read(groupsProvider.notifier)
                    .loadInvitePreview(widget.inviteCode),
              )
            : detail == null
            ? _InviteErrorState(
                error: 'Invite code not found.',
                onRetry: () => ref
                    .read(groupsProvider.notifier)
                    .loadInvitePreview(widget.inviteCode),
              )
            : CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      CoolSpace.x4,
                      CoolSpace.x3,
                      CoolSpace.x4,
                      80,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Invite code ${widget.inviteCode.toUpperCase()}',
                            style: text.mono(
                              theme.textTheme.labelLarge,
                              fontWeight: FontWeight.w700,
                              color: colors.accent,
                            ),
                          ),
                          const SizedBox(height: CoolSpace.x4),
                          _InviteHeroCard(detail: detail),
                          const SizedBox(height: CoolSpace.x5),
                          _InviteStatusBanner(isMember: detail.isMember),
                          const SizedBox(height: CoolSpace.x5),
                          CoolButton(
                            label: detail.isMember
                                ? 'Open Group'
                                : 'Join Group',
                            isLoading: isJoining,
                            onTap: () => _handlePrimaryAction(detail),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _InviteHeroCard extends StatelessWidget {
  const _InviteHeroCard({required this.detail});

  final GroupDetail detail;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final theme = Theme.of(context);
    final group = detail.group;
    final amountLabel = _formatAmount(group.amount);
    final targetLabel = _formatAmount(group.targetAmount);
    final cadence = group.frequency?.trim().isNotEmpty == true
        ? groupFormatFrequency(group.frequency!)
        : 'Monthly';
    final memberCount = detail.members.isNotEmpty
        ? detail.members.length
        : group.memberCount;
    final isSaving = group.type == 'saving';
    final accent = isSaving ? colors.accent : colors.warning;
    final surface = isSaving ? colors.financialSurface : colors.teamSurface;

    return CoolCard(
      backgroundColor: surface,
      borderColor: colors.border,
      padding: const EdgeInsets.all(CoolSpace.x6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (isSaving)
                const StatusBadge.saving()
              else
                const StatusBadge.community(),
              const SizedBox(width: CoolSpace.x2),
              if (group.visibility == 'public')
                const StatusBadge.public()
              else
                const StatusBadge.private(),
            ],
          ),
          const SizedBox(height: CoolSpace.x4),
          Text(
            group.name,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: colors.primaryText,
            ),
          ),
          const SizedBox(height: CoolSpace.x3),
          Wrap(
            spacing: CoolSpace.x3,
            runSpacing: CoolSpace.x2,
            children: [
              GroupHeroInfoChip(
                icon: Icons.groups_2_outlined,
                label: memberCount == 1 ? '1 member' : '$memberCount members',
              ),
              GroupHeroInfoChip(
                icon: Icons.event_repeat_rounded,
                label: '$cadence contributions',
              ),
            ],
          ),
          const SizedBox(height: CoolSpace.x5),
          Text(
            'RWF $amountLabel raised',
            style: text.mono(
              theme.textTheme.displaySmall,
              fontWeight: FontWeight.w900,
              color: accent,
            ),
          ),
          const SizedBox(height: CoolSpace.x2),
          Text(
            'Target: RWF $targetLabel',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.secondaryText,
            ),
          ),
          if (group.description?.trim().isNotEmpty ?? false) ...[
            const SizedBox(height: CoolSpace.x4),
            Text(
              group.description!.trim(),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.secondaryText,
                height: 1.45,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _formatAmount(int value) {
    final s = value.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) {
        buf.write(',');
      }
      buf.write(s[i]);
    }
    return buf.toString();
  }
}

class _InviteStatusBanner extends StatelessWidget {
  const _InviteStatusBanner({required this.isMember});

  final bool isMember;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(CoolSpace.x4),
      decoration: BoxDecoration(
        color: isMember ? colors.cardSurface : colors.chipSelectedBackground,
        borderRadius: const BorderRadius.all(Radius.circular(CoolRadii.sm)),
        border: Border.all(
          color: isMember
              ? colors.border
              : colors.accent.withValues(alpha: 0.3),
        ),
      ),
      child: Text(
        isMember ? 'You are already a member.' : 'You will join this group.',
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: isMember ? colors.secondaryText : colors.primaryText,
          height: 1.4,
        ),
      ),
    );
  }
}

class _InviteErrorState extends StatelessWidget {
  const _InviteErrorState({required this.error, required this.onRetry});

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: CoolSpace.x6),
      child: CoolErrorView(
        message: error,
        onRetry: onRetry,
        icon: Icons.link_off_rounded,
      ),
    );
  }
}
