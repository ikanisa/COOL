import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/auth/auth_user_contact.dart';
import '../../../core/providers/engagement_providers.dart';
import '../../../core/providers/referral_providers.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_error_view.dart';
import '../../../shared/widgets/cool_skeleton.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/group_detail.dart';
import '../providers/groups_provider.dart';
import '../../../core/l10n/l10n.dart';

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
  String get _inviteRoute => Uri(
    path: AppRoutes.inviteLocation(widget.inviteCode),
    queryParameters: widget.referralParameters.isEmpty
        ? null
        : widget.referralParameters,
  ).toString();

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
      context.go(AppRoutes.otpLocation(redirect: _inviteRoute));
      return;
    }

    if (authState.user == null) {
      context.go(
        AppRoutes.registerLocation(
          phone: authSessionPhone(authState.session),
          redirect: _inviteRoute,
        ),
      );
      return;
    }

    final result = await ref
        .read(groupsProvider.notifier)
        .joinGroupByInviteCode(widget.inviteCode);

    if (!mounted) {
      return;
    }

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

    if (!mounted) {
      return;
    }

    final message = result.didJoin
        ? 'You joined ${result.detail.group.name}.'
        : 'You are already a member of ${result.detail.group.name}.';
    CoolToast.success(context, message);
    context.go('/groups/$groupId');
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(groupInvitePreviewProvider);
    final isPreviewLoading = ref.watch(groupInvitePreviewLoadingProvider);
    final previewError = ref.watch(groupInvitePreviewErrorProvider);
    final isJoining = ref.watch(groupJoinLoadingProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        leading: IconButton(
          tooltip: context.l10n.back,
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: Text(
          'Group Invite',
          style: GoogleFonts.dmSans(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.text,
          ),
        ),
      ),
      body: isPreviewLoading && detail == null
          ? const Padding(
              padding: EdgeInsets.fromLTRB(18, 16, 18, 96),
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
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 80),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Invite code ${widget.inviteCode.toUpperCase()}',
                          style: GoogleFonts.dmMono(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.accent,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _InviteHeroCard(detail: detail),
                        const SizedBox(height: 20),
                        if (!detail.isMember)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: AppColors.accentGlow,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: AppColors.accent),
                            ),
                            child: Text(
                              'You\'ll join this group',
                              style: GoogleFonts.dmSans(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: AppColors.text,
                                height: 1.45,
                              ),
                            ),
                          )
                        else
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: AppColors.surface2,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Text(
                              'You\'re already a member.',
                              style: GoogleFonts.dmSans(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: AppColors.text2,
                              ),
                            ),
                          ),
                        const SizedBox(height: 20),
                        CoolButton(
                          label: detail.isMember ? 'Open Group' : 'Join Group',
                          isLoading: isJoining,
                          onTap: () => _handlePrimaryAction(detail),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _InviteHeroCard extends StatelessWidget {
  const _InviteHeroCard({required this.detail});

  final GroupDetail detail;

  @override
  Widget build(BuildContext context) {
    final group = detail.group;
    final amountLabel = _formatAmount(group.amount);
    final targetLabel = _formatAmount(group.targetAmount);
    final cadence = group.frequency?.trim().isNotEmpty == true
        ? group.frequency!.trim()
        : 'Monthly';

    final memberCount = detail.members.isNotEmpty
        ? detail.members.length
        : group.memberCount;

    return CoolCard(
      gradient: AppColors.cardGradient,
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (group.type == 'saving')
                    const StatusBadge.saving()
                else
                    const StatusBadge.community(),
                const SizedBox(width: 8),
                if (group.visibility == 'public')
                    const StatusBadge.public()
                else
                    const StatusBadge.private(),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              group.name,
              style: GoogleFonts.dmSans(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '$memberCount members · $cadence contributions',
              style: GoogleFonts.dmSans(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.text2,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'RWF $amountLabel raised',
              style: GoogleFonts.dmMono(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: group.type == 'saving'
                    ? AppColors.accent
                    : AppColors.orange,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Target: RWF $targetLabel',
              style: GoogleFonts.dmSans(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: AppColors.text2,
              ),
            ),
            if (group.description?.trim().isNotEmpty ?? false) ...[
              const SizedBox(height: 14),
              Text(
                group.description!.trim(),
                style: GoogleFonts.dmSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: AppColors.text2,
                  height: 1.45,
                ),
              ),
            ],
          ],
        ),
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

class _InviteErrorState extends StatelessWidget {
  const _InviteErrorState({required this.error, required this.onRetry});

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: CoolErrorView(
        message: error,
        onRetry: onRetry,
        icon: Icons.link_off_rounded,
      ),
    );
  }
}