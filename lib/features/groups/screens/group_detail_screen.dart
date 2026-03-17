import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';

import '../../auth/providers/auth_provider.dart';

import '../../../core/config/deep_link_config.dart';
import '../../../core/providers/app_access_provider.dart';
import '../../../core/providers/referral_providers.dart';
import '../../../core/status/cool_status_awarder.dart';
import '../../../core/status/models/cool_event.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/cool_async_view.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_empty_view.dart';
import '../../../shared/widgets/cool_skeleton.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_screen_background.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../../../shared/widgets/member_row.dart';
import '../../../shared/widgets/qr_share_sheet.dart';
import '../../../shared/widgets/contact_picker_sheet.dart';
import '../../../shared/widgets/section_title.dart';
import '../../../shared/widgets/status_badge.dart';
import '../models/group_detail.dart';
import '../providers/groups_provider.dart';
import '../widgets/group_detail/group_contribute_sheet.dart';
import '../widgets/group_detail/group_detail_helpers.dart';
import '../widgets/group_detail/group_settings_sheet.dart';

/// Detailed view of a single savings or community group.
///
/// Shows a hero card, contribute/share actions, members list,
/// and contribution history.
class GroupDetailScreen extends ConsumerStatefulWidget {
  const GroupDetailScreen({required this.groupId, super.key});
  final String groupId;

  @override
  ConsumerState<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends ConsumerState<GroupDetailScreen>
    with CoolStatusAwarder {
  bool _showAllMembers = false;
  bool _showAllContributions = false;

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(groupDetailProvider(widget.groupId));
    final isJoiningGroup = ref.watch(groupJoinLoadingProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        automaticallyImplyLeading: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => context.pop(),
          tooltip: 'Back',
          icon: Icon(Icons.arrow_back_rounded, color: AppColors.text),
        ),
        actions: [
          if (detailAsync.valueOrNull != null)
            _buildSettingsButton(context, detailAsync.value!),
        ],
      ),
      body: CoolScreenBackground(
        primaryColor: AppColors.accent,
        secondaryColor: AppColors.blue,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
              child: Text(
                'Group Detail',
                style: Theme.of(context).textTheme.displayLarge,
              ),
            ),
            Expanded(
              child: CoolAsyncView<GroupDetail?>(
                value: detailAsync,
                onRetry: () =>
                    ref.invalidate(groupDetailProvider(widget.groupId)),
                loadingWidget: const Padding(
                  padding: EdgeInsets.fromLTRB(18, 0, 18, 96),
                  child: CoolSkeletonList(itemCount: 4),
                ),
                emptyCheck: (detail) => detail == null,
                emptyWidget: const CoolEmptyView(
                  message: 'Group not found.',
                ),
                builder: (detail) => _buildContent(detail!, isJoiningGroup),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openShareSheet(GroupDetail detail) async {
    final group = detail.group;
    final baseUri = group.inviteCode != null && group.inviteCode!.isNotEmpty
        ? DeepLinkConfig.inviteUri(group.inviteCode!)
        : ((group.id?.isNotEmpty ?? false)
              ? DeepLinkConfig.groupDetailUri(group.id!)
              : Uri.https(DeepLinkConfig.host, '/groups'));

    var shareUri = baseUri;
    try {
      final inviteCode = group.inviteCode?.trim().isNotEmpty == true
          ? group.inviteCode!.trim().toUpperCase()
          : 'GROUP-${group.id ?? 'DETAIL'}';
      final referralLink = await ref
          .read(referralRepositoryProvider)
          .createInviteLink(
            inviteCode: inviteCode,
            baseUri: baseUri,
            shareChannel: 'qr_sheet',
            campaignId: 'group_captain',
          );
      shareUri = referralLink.uri;
    } catch (_) {
      // Fall back to a plain share URL if referral provisioning fails.
    }

    if (!mounted) {
      return;
    }

    await QrShareSheet.show(
      context,
      groupName: group.name,
      inviteUrl: shareUri.toString(),
      shareText: 'Join ${group.name} on Cool: ${shareUri.toString()}',
      analyticsTargetType: 'group_invite',
    );
  }

  Future<void> _inviteFromContacts(GroupDetail detail) async {
    final contacts = await ContactPickerSheet.show(
      context,
      appAccessService: ref.read(appAccessServiceProvider),
      multiSelect: true,
      title: 'Invite to ${detail.group.name}',
    );

    if (contacts.isEmpty || !mounted) return;

    // Resolve the invite URL
    final group = detail.group;
    final baseUri = group.inviteCode != null && group.inviteCode!.isNotEmpty
        ? DeepLinkConfig.inviteUri(group.inviteCode!)
        : ((group.id?.isNotEmpty ?? false)
              ? DeepLinkConfig.groupDetailUri(group.id!)
              : Uri.https(DeepLinkConfig.host, '/groups'));

    var shareUri = baseUri;
    try {
      final inviteCode = group.inviteCode?.trim().isNotEmpty == true
          ? group.inviteCode!.trim().toUpperCase()
          : 'GROUP-${group.id ?? 'DETAIL'}';
      final referralLink = await ref
          .read(referralRepositoryProvider)
          .createInviteLink(
            inviteCode: inviteCode,
            baseUri: baseUri,
            shareChannel: 'contacts',
            campaignId: 'group_captain',
          );
      shareUri = referralLink.uri;
    } catch (_) {
      // Fall back to plain URL.
    }

    if (!mounted) return;

    final shareText = 'Join ${group.name} on Cool! 🎉\n${shareUri.toString()}';
    await SharePlus.instance.share(ShareParams(text: shareText));
  }

  Future<void> _openMoreActions(GroupDetail detail) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => GroupMoreActionsSheet(
        onShare: () {
          Navigator.of(context).pop();
          _openShareSheet(detail);
        },
        onInvite: () {
          Navigator.of(context).pop();
          _inviteFromContacts(detail);
        },
      ),
    );
  }

  Widget _buildContent(GroupDetail detail, bool isLoading) {
    final group = detail.group;
    final members = detail.members;
    final contributions = detail.recentContributions;

    final progress = group.targetAmount > 0
        ? (group.amount / group.targetAmount).clamp(0.0, 1.0)
        : 0.0;
    final percent = (progress * 100).round();
    final isPrivate = group.visibility == 'private';
    final visibleMembers = _showAllMembers ? members : members.take(3).toList();
    final visibleContributions = _showAllContributions
        ? contributions
        : contributions.take(3).toList();


    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 96),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),

          // ═══════════════════════════════════════════════════════
          // HERO CARD
          // ═══════════════════════════════════════════════════════
          CoolCard(
            gradient: AppColors.cardGradient,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Name
                  Text(
                    group.name,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: AppColors.text,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Badges
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
                  const SizedBox(height: 24),

                  // Total amount
                  Text(
                    groupFormatAmount(group.amount),
                    style: Theme.of(context).textTheme.displayMedium?.copyWith(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w900,
                      fontFamily: GoogleFonts.dmMono().fontFamily,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Target: RWF ${groupFormatAmount(group.targetAmount)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 20),

                  // Progress bar
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 8,
                      backgroundColor: AppColors.surface3,
                      color: AppColors.accent,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Progress label
                  Text(
                    '$percent% reached',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.text2,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Member count + frequency chips (merged from Group Facts)
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      GroupHeroInfoChip(
                        icon: Icons.groups_2_outlined,
                        label: members.length == 1
                            ? '1 member'
                            : '${members.length} members',
                      ),
                      if (group.frequency != null &&
                          group.frequency!.isNotEmpty)
                        GroupHeroInfoChip(
                          icon: Icons.event_repeat_rounded,
                          label: groupFormatFrequency(group.frequency!),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ═══════════════════════════════════════════════════════
          // ACTION ROW
          // ═══════════════════════════════════════════════════════
          Row(
            children: [
              Expanded(
                child: detail.isMember
                    ? CoolButton(
                        label: '+ Contribute',
                        onTap: () => _showContributeSheet(context, detail),
                      )
                    : CoolButton(
                        label: 'Join Group',
                        isLoading: isLoading,
                        onTap: () => _joinGroup(detail),
                      ),
              ),
              const SizedBox(width: 12),
              CoolButton(
                label: 'More',
                icon: Icons.more_horiz_rounded,
                fullWidth: false,
                variant: CoolButtonVariant.secondary,
                onTap: () => _openMoreActions(detail),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const SizedBox(height: 16),

          // ═══════════════════════════════════════════════════════
          // MEMBERS SECTION
          // ═══════════════════════════════════════════════════════
          SectionTitle(
            title: 'Members (${members.length})',
            actionLabel: members.length > 3
                ? (_showAllMembers ? 'Show less' : 'Show all')
                : null,
            onAction: members.length > 3
                ? () => setState(() => _showAllMembers = !_showAllMembers)
                : null,
          ),
          const SizedBox(height: 12),

          ...visibleMembers.map((m) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: MemberRow(
                displayName: isPrivate ? m.displayName : null,
                userId: m.userId,
                isAdmin: m.isAdmin,
                contributionAmount: m.contributionAmount,
                isAnonymous: m.isAnonymous || !isPrivate,
              ),
            );
          }),

          const SizedBox(height: 28),

          // ═══════════════════════════════════════════════════════
          // CONTRIBUTIONS HISTORY
          // ═══════════════════════════════════════════════════════
          SectionTitle(
            title: 'Recent contributions',
            actionLabel: contributions.length > 3
                ? (_showAllContributions ? 'Show less' : 'Show all')
                : null,
            onAction: contributions.length > 3
                ? () => setState(
                    () => _showAllContributions = !_showAllContributions,
                  )
                : null,
          ),
          const SizedBox(height: 12),

          if (contributions.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'No contributions yet',
                  style: GoogleFonts.dmSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: AppColors.text3,
                  ),
                ),
              ),
            )
          else
            ...visibleContributions.map(
              (c) => GroupContributionRow(contribution: c),
            ),
        ],
      ),
    );
  }

  void _showContributeSheet(BuildContext context, GroupDetail detail) {
    ref.read(groupsProvider.notifier).clearContributionState();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => GroupContributeSheet(
        groupId: detail.group.id ?? '',
        groupName: detail.group.name,
        monthlyAmount: detail.group.monthlyContribution ?? 5000,
        frequency: detail.group.frequency ?? 'monthly',
        onSuccess: (groupId) {
          ref.invalidate(groupDetailProvider(widget.groupId));
          awardCoolPoints(
            ref,
            eventType: CoolEventType.groupContribution,
            sourceId: groupId,
            metadata: {'group': detail.group.name},
          );
        },
      ),
    );
  }

  Future<void> _joinGroup(GroupDetail detail) async {
    final inviteCode = detail.group.inviteCode;
    if (inviteCode == null || inviteCode.isEmpty) {
      CoolToast.info(
        context,
        'This group does not have a shareable invite code yet.',
      );
      return;
    }

    final result = await ref
        .read(groupsProvider.notifier)
        .joinGroupByInviteCode(inviteCode);

    if (!mounted) {
      return;
    }

    if (result == null) {
      final error = ref.read(groupJoinErrorProvider) ?? 'Could not join group.';
      CoolToast.error(context, error);
      return;
    }

    final message = result.didJoin
        ? 'You joined ${result.detail.group.name}.'
        : 'You are already a member of ${result.detail.group.name}.';
    ref.invalidate(groupDetailProvider(widget.groupId));
    CoolToast.success(context, message);
  }



  Widget _buildSettingsButton(
    BuildContext context,
    GroupDetail detail,
  ) {
    final currentUserId = ref.read(currentUserProvider)?.id;
    final isCreator = currentUserId != null &&
        currentUserId == detail.group.creatorId;
    final isAdmin = detail.members.any(
      (m) => m.userId == currentUserId && m.isAdmin,
    );

    if (!isCreator && !isAdmin) return const SizedBox.shrink();

    return IconButton(
      onPressed: () => _openGroupSettings(context, detail),
      icon: Icon(Icons.settings_outlined, color: AppColors.text2, size: 22),
      tooltip: 'Group settings',
    );
  }

  void _openGroupSettings(BuildContext context, GroupDetail detail) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => GroupSettingsSheet(
        detail: detail,
        onDismiss: () {
          ref.invalidate(groupDetailProvider(widget.groupId));
        },
      ),
    );
  }
}


