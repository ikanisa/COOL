import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/config/deep_link_config.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/providers/app_access_provider.dart';
import '../../../core/providers/referral_providers.dart';
import '../../../core/status/cool_status_awarder.dart';
import '../../../core/status/models/cool_event.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/contact_picker_sheet.dart';
import '../../../shared/widgets/cool_async_view.dart';
import '../../../shared/widgets/cool_bottom_sheet.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_empty_view.dart';
import '../../../shared/widgets/cool_screen_background.dart';
import '../../../shared/widgets/cool_skeleton.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../../../shared/widgets/member_row.dart';
import '../../../shared/widgets/qr_share_sheet.dart';
import '../../../shared/widgets/section_title.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/group_detail.dart';
import '../providers/groups_provider.dart';
import '../widgets/group_detail/group_contribute_sheet.dart';
import '../widgets/group_detail/group_detail_helpers.dart';
import '../widgets/group_detail/group_hero_card.dart';
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

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final detailAsync = ref.watch(groupDetailProvider(widget.groupId));
    final isJoiningGroup = ref.watch(groupJoinLoadingProvider);

    return Scaffold(
      backgroundColor: colors.appBackground,
      appBar: AppBar(
        automaticallyImplyLeading: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => context.pop(),
          tooltip: context.l10n.back,
          icon: Icon(Icons.arrow_back_rounded, color: colors.primaryText),
        ),
        actions: [
          if (detailAsync.valueOrNull != null)
            _buildSettingsButton(context, detailAsync.value!),
        ],
      ),
      body: CoolScreenBackground(
        primaryColor: colors.accent,
        secondaryColor: colors.info,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                CoolSpace.x4,
                0,
                CoolSpace.x4,
                CoolSpace.x6,
              ),
              child: Text(
                context.l10n.groupDetailTitle,
                style: Theme.of(context).textTheme.displayLarge,
              ),
            ),
            Expanded(
              child: CoolAsyncView<GroupDetail?>(
                value: detailAsync,
                onRetry: () =>
                    ref.invalidate(groupDetailProvider(widget.groupId)),
                loadingWidget: const Padding(
                  padding: EdgeInsets.fromLTRB(
                    CoolSpace.x4,
                    0,
                    CoolSpace.x4,
                    96,
                  ),
                  child: CoolSkeletonList(itemCount: 4),
                ),
                emptyCheck: (detail) => detail == null,
                emptyWidget: CoolEmptyView(message: context.l10n.groupNotFound),
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

    if (!mounted) return;

    await QrShareSheet.show(
      context,
      groupName: group.name,
      inviteUrl: shareUri.toString(),
      shareText: context.l10n.joinGroupShareText(
        group.name,
        shareUri.toString(),
      ),
      analyticsTargetType: 'group_invite',
    );
  }

  Future<void> _inviteFromContacts(GroupDetail detail) async {
    final contacts = await ContactPickerSheet.show(
      context,
      appAccessService: ref.read(appAccessServiceProvider),
      multiSelect: true,
      title: context.l10n.inviteToGroup(detail.group.name),
    );

    if (contacts.isEmpty || !mounted) return;

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

    final shareText = context.l10n.joinGroupShareTextEmoji(
      group.name,
      shareUri.toString(),
    );
    await SharePlus.instance.share(ShareParams(text: shareText));
  }

  Future<void> _openMoreActions(GroupDetail detail) async {
    await showCoolBottomSheet<void>(
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
    final isPrivate = group.visibility == 'private';
    final visibleMembers = _showAllMembers ? members : members.take(3).toList();
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        CoolSpace.x4,
        CoolSpace.x2,
        CoolSpace.x4,
        96,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GroupHeroCard(group: group, members: members),
          const SizedBox(height: CoolSpace.x4),
          Row(
            children: [
              Expanded(
                child: detail.isMember
                    ? CoolButton(
                        label: '+ Contribute',
                        onTap: () => _showContributeSheet(context, detail),
                      )
                    : CoolButton(
                        label: context.l10n.joinGroup,
                        isLoading: isLoading,
                        onTap: () => _joinGroup(detail),
                      ),
              ),
              const SizedBox(width: CoolSpace.x3),
              CoolButton(
                label: context.l10n.more,
                icon: Icons.more_horiz_rounded,
                fullWidth: false,
                variant: CoolButtonVariant.secondary,
                onTap: () => _openMoreActions(detail),
              ),
            ],
          ),
          const SizedBox(height: CoolSpace.x4),
          SectionTitle(
            title: context.l10n.membersCount(members.length),
            actionLabel: members.length > 3
                ? (_showAllMembers
                      ? context.l10n.showLess
                      : context.l10n.showAll)
                : null,
            onAction: members.length > 3
                ? () => setState(() => _showAllMembers = !_showAllMembers)
                : null,
          ),
          const SizedBox(height: CoolSpace.x3),
          ...visibleMembers.map(
            (member) => Padding(
              padding: const EdgeInsets.only(bottom: CoolSpace.x1),
              child: MemberRow(
                displayName: isPrivate ? member.displayName : null,
                userId: member.userId,
                isAdmin: member.isAdmin,
                contributionAmount: member.contributionAmount,
                isAnonymous: member.isAnonymous || !isPrivate,
              ),
            ),
          ),
          const SizedBox(height: CoolSpace.x7),
          SectionTitle(
            title: context.l10n.recentContributions,
            actionLabel: contributions.length > 3 ? context.l10n.showAll : null,
            onAction: contributions.length > 3
                ? () => context.push('/groups/${group.id}/ledger')
                : null,
          ),
          const SizedBox(height: CoolSpace.x3),
          if (contributions.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: CoolSpace.x6),
              child: Center(
                child: Text(
                  context.l10n.noContributionsYet,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.tertiaryText,
                    height: 1.4,
                  ),
                ),
              ),
            )
          else
            ...contributions
                .take(3)
                .map(
                  (contribution) =>
                      GroupContributionRow(contribution: contribution),
                ),
        ],
      ),
    );
  }

  void _showContributeSheet(BuildContext context, GroupDetail detail) {
    ref.read(groupsProvider.notifier).clearContributionState();
    showCoolBottomSheet<void>(
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
      CoolToast.info(context, context.l10n.noInviteCodeYet);
      return;
    }

    final result = await ref
        .read(groupsProvider.notifier)
        .joinGroupByInviteCode(inviteCode);

    if (!mounted) return;

    if (result == null) {
      final error =
          ref.read(groupJoinErrorProvider) ?? context.l10n.couldNotJoinGroup;
      CoolToast.error(context, error);
      return;
    }

    final message = result.didJoin
        ? context.l10n.youJoinedGroup(result.detail.group.name)
        : context.l10n.alreadyMemberOf(result.detail.group.name);
    ref.invalidate(groupDetailProvider(widget.groupId));
    CoolToast.success(context, message);
  }

  Widget _buildSettingsButton(BuildContext context, GroupDetail detail) {
    final colors = context.coolSemanticColors;
    final currentUserId = ref.read(currentUserProvider)?.id;
    final isCreator =
        currentUserId != null && currentUserId == detail.group.creatorId;
    final isAdmin = detail.members.any(
      (member) => member.userId == currentUserId && member.isAdmin,
    );

    if (!isCreator && !isAdmin) return const SizedBox.shrink();

    return IconButton(
      onPressed: () => _openGroupSettings(context, detail),
      icon: Icon(
        Icons.settings_outlined,
        color: colors.secondaryText,
        size: 22,
      ),
      tooltip: context.l10n.groupSettings,
    );
  }

  void _openGroupSettings(BuildContext context, GroupDetail detail) {
    showCoolBottomSheet<void>(
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
