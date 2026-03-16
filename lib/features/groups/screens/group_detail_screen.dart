import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
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
import '../models/group_contribution.dart';
import '../models/group_detail.dart';
import '../providers/groups_provider.dart';

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
                style: GoogleFonts.dmSans(
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  color: AppColors.text,
                  height: 1.1,
                ),
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
                  icon: Icons.groups_2_outlined,
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
      subtitle: 'Select contacts to send',
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
      builder: (_) => _GroupMoreActionsSheet(
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
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Name
                  Text(
                    group.name,
                    style: GoogleFonts.dmSans(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Badges
                  Row(
                    children: [
                      if (group.type == 'saving')
                        const StatusBadge.saving()
                      else
                        const StatusBadge.community(),
                      const SizedBox(width: 6),
                      if (group.visibility == 'public')
                        const StatusBadge.public()
                      else
                        const StatusBadge.private(),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // Total amount
                  Text(
                    _formatAmount(group.amount),
                    style: GoogleFonts.dmMono(
                      fontSize: 36,
                      fontWeight: FontWeight.w700,
                      color: AppColors.accent,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Target: RWF ${_formatAmount(group.targetAmount)}',
                    style: GoogleFonts.dmSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      color: AppColors.text2,
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Progress bar
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 6,
                      backgroundColor: AppColors.surface3,
                      color: AppColors.accent,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Progress label
                  Text(
                    '$percent% reached',
                    style: GoogleFonts.dmSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: AppColors.text2,
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Member count + frequency chips (merged from Group Facts)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _HeroInfoChip(
                        icon: Icons.groups_2_outlined,
                        label: members.length == 1
                            ? '1 member'
                            : '${members.length} members',
                      ),
                      if (group.frequency != null &&
                          group.frequency!.isNotEmpty)
                        _HeroInfoChip(
                          icon: Icons.event_repeat_rounded,
                          label: _formatFrequency(group.frequency!),
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
              (c) => _ContributionRow(contribution: c),
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
      builder: (_) => _ContributeSheet(
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

  static String _formatAmount(int value) {
    final s = value.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  static String _formatFrequency(String value) {
    switch (value.trim().toLowerCase()) {
      case 'daily':
        return 'Daily';
      case 'weekly':
        return 'Weekly';
      default:
        return 'Monthly';
    }
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
      builder: (_) => _GroupSettingsSheet(
        detail: detail,
        onDismiss: () {
          ref.invalidate(groupDetailProvider(widget.groupId));
        },
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
// Facts card and more-actions sheet
// ═════════════════════════════════════════════════════════════════════════

// ═════════════════════════════════════════════════════════════════════════
// Hero info chip (inline in hero card)
// ═════════════════════════════════════════════════════════════════════════

class _HeroInfoChip extends StatelessWidget {
  const _HeroInfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface2.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.text2),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.dmSans(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.text2,
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupMoreActionsSheet extends StatelessWidget {
  const _GroupMoreActionsSheet({required this.onShare, required this.onInvite});

  final VoidCallback onShare;
  final VoidCallback onInvite;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border2,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'More actions',
                style: GoogleFonts.dmSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Keep sharing and invite',
                style: GoogleFonts.dmSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: AppColors.text2,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 20),
              CoolButton(
                label: 'Share / QR',
                variant: CoolButtonVariant.secondary,
                onTap: onShare,
              ),
              const SizedBox(height: 12),
              CoolButton(
                label: 'Invite from Contacts',
                variant: CoolButtonVariant.secondary,
                onTap: onInvite,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
// Contribution row
// ═════════════════════════════════════════════════════════════════════════

class _ContributionRow extends StatelessWidget {
  const _ContributionRow({required this.contribution});
  final GroupContribution contribution;

  @override
  Widget build(BuildContext context) {
    final dateLabel = contribution.createdAt != null
        ? DateFormat('d MMM y').format(contribution.createdAt!)
        : '';
    final contributorLabel =
        contribution.contributorName?.trim().isNotEmpty == true
        ? contribution.contributorName!.trim()
        : '#${contribution.userId.substring(0, 8.clamp(0, contribution.userId.length))}';

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          // Green arrow icon
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.download_rounded,
              size: 18,
              color: AppColors.text2,
            ),
          ),
          const SizedBox(width: 12),

          // Name + date
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$contributorLabel contributed',
                  style: GoogleFonts.dmSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  dateLabel,
                  style: GoogleFonts.dmSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: AppColors.text2,
                  ),
                ),
              ],
            ),
          ),

          // Amount
          Text(
            '+${_GroupDetailScreenState._formatAmount(contribution.amount)} RWF',
            style: GoogleFonts.dmMono(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.accent,
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
// Contribute bottom sheet
// ═════════════════════════════════════════════════════════════════════════

class _ContributeSheet extends ConsumerStatefulWidget {
  const _ContributeSheet({
    required this.groupId,
    required this.groupName,
    required this.monthlyAmount,
    required this.frequency,
    this.onSuccess,
  });

  final String groupId;
  final String groupName;
  final int monthlyAmount;
  final String frequency;
  final void Function(String groupId)? onSuccess;

  @override
  ConsumerState<_ContributeSheet> createState() => _ContributeSheetState();
}

class _ContributeSheetState extends ConsumerState<_ContributeSheet> {
  late final TextEditingController _amountController;
  int? _selectedMultiplier; // 0=half, 1=full, 2=double

  @override
  void initState() {
    super.initState();
    ref.read(groupsProvider.notifier).clearContributionState();
    _amountController = TextEditingController(
      text: widget.monthlyAmount.toString(),
    );
    _selectedMultiplier = 1;
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  void _selectAmount(int multiplierIndex) {
    final amounts = [
      widget.monthlyAmount ~/ 2,
      widget.monthlyAmount,
      widget.monthlyAmount * 2,
    ];
    setState(() {
      _selectedMultiplier = multiplierIndex;
      _amountController.text = amounts[multiplierIndex].toString();
    });
  }

  Future<void> _payViaMomo() async {
    final amount = int.tryParse(
      _amountController.text.replaceAll(',', '').trim(),
    );
    if (amount == null || amount <= 0) {
      CoolToast.error(context, 'Enter a valid contribution amount.');
      return;
    }

    final contribution = await ref
        .read(groupsProvider.notifier)
        .contribute(widget.groupId, amount);

    if (!mounted) return;

    if (contribution != null) {
      widget.onSuccess?.call(widget.groupId);
      Navigator.of(context).pop();
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(groupContributionLoadingProvider);
    final error = ref.watch(groupContributionErrorProvider);
    final half = widget.monthlyAmount ~/ 2;
    final full = widget.monthlyAmount;
    final double = widget.monthlyAmount * 2;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle bar
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border2,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Group name + monthly
              Text(
                widget.groupName,
                style: GoogleFonts.dmSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${_GroupDetailScreenState._formatFrequency(widget.frequency)}:'
                'RWF ${_GroupDetailScreenState._formatAmount(full)}',
                style: GoogleFonts.dmSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: AppColors.text2,
                ),
              ),
              const SizedBox(height: 20),

              // Amount input
              Text(
                'Amount',
                style: GoogleFonts.dmSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.text2,
                ),
              ),
              const SizedBox(height: 8),
              Semantics(
                textField: true,
                label: 'Contribution amount in Rwandan',
                hint: 'Enter amount',
                child: TextField(
                  controller: _amountController,
                  keyboardType: TextInputType.number,
                  style: GoogleFonts.dmMono(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppColors.accent,
                  ),
                  cursorColor: AppColors.accent,
                  decoration: InputDecoration(
                    prefix: Text(
                      'RWF',
                      style: GoogleFonts.dmSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w400,
                        color: AppColors.text3,
                      ),
                    ),
                    filled: true,
                    fillColor: AppColors.surface2,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: AppColors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: AppColors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: AppColors.accent,
                        width: 1.5,
                      ),
                    ),
                  ),
                  onChanged: (_) => setState(() => _selectedMultiplier = null),
                ),
              ),
              const SizedBox(height: 12),

              // Quick-select chips
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _AmountChip(
                    label: 'Half (${_formatK(half)})',
                    isSelected: _selectedMultiplier == 0,
                    onTap: () => _selectAmount(0),
                  ),
                  _AmountChip(
                    label: 'Full (${_formatK(full)})',
                    isSelected: _selectedMultiplier == 1,
                    onTap: () => _selectAmount(1),
                  ),
                  _AmountChip(
                    label: 'Double (${_formatK(double)})',
                    isSelected: _selectedMultiplier == 2,
                    onTap: () => _selectAmount(2),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Pay button
              CoolButton(
                label: 'Pay via MOMO',
                icon: Icons.phone_android_rounded,
                isLoading: isLoading,
                onTap: _payViaMomo,
              ),
              if (error != null) ...[
                const SizedBox(height: 12),
                Text(
                  error,
                  style: GoogleFonts.dmSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.red,
                  ),
                ),
              ],
              const SizedBox(height: 12),

              // USSD banner
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.yellow.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.yellow.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.phone_rounded, size: 16, color: AppColors.text2),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'You\'ll be redirected to',
                        style: GoogleFonts.dmSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          color: AppColors.yellow,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatK(int value) {
    if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(value % 1000 == 0 ? 0 : 1)}K';
    }
    return value.toString();
  }
}

// ── Quick-select amount chip ────────────────────────────────────────────

class _AmountChip extends StatelessWidget {
  const _AmountChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.accentGlow : AppColors.surface2,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: isSelected ? AppColors.accent : AppColors.border,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: GoogleFonts.dmSans(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isSelected ? AppColors.accent : AppColors.text2,
            ),
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
// Group Settings Sheet (admin / creator only)
// ═════════════════════════════════════════════════════════════════════════

class _GroupSettingsSheet extends ConsumerStatefulWidget {
  const _GroupSettingsSheet({required this.detail, this.onDismiss});

  final GroupDetail detail;
  final VoidCallback? onDismiss;

  @override
  ConsumerState<_GroupSettingsSheet> createState() =>
      _GroupSettingsSheetState();
}

class _GroupSettingsSheetState extends ConsumerState<_GroupSettingsSheet> {
  late TextEditingController _nameController;
  late TextEditingController _descController;
  late TextEditingController _targetController;
  late String _frequency;
  late String _visibility;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final group = widget.detail.group;
    _nameController = TextEditingController(text: group.name);
    _descController = TextEditingController(text: group.description ?? '');
    _targetController = TextEditingController(
      text: group.targetAmount.toString(),
    );
    _frequency = group.frequency ?? 'monthly';
    _visibility = group.visibility;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _targetController.dispose();
    super.dispose();
  }

  Future<void> _saveChanges() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      final groupId = widget.detail.group.id;
      if (groupId == null) return;

      final updates = <String, dynamic>{
        'name': _nameController.text.trim(),
        'description': _descController.text.trim(),
        'target_amount': int.tryParse(_targetController.text.trim()) ?? 0,
        'frequency': _frequency,
        'visibility': _visibility,
      };

      await ref
          .read(groupsProvider.notifier)
          .updateGroup(groupId, updates);

      widget.onDismiss?.call();
      if (mounted) {
        Navigator.of(context).pop();
        CoolToast.success(context, 'Group updated');
      }
    } catch (e) {
      if (mounted) {
        CoolToast.error(context, 'Failed to save: $e');
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = ref.read(currentUserProvider)?.id;
    final members = widget.detail.members;
    final admins = members.where((m) => m.isAdmin).toList();

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.75,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border2,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Title
                Text(
                  'Group Settings',
                  style: GoogleFonts.dmSans(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 24),

                // ── Name ──
                _SettingsLabel('Group name'),
                const SizedBox(height: 6),
                _SettingsInput(controller: _nameController),
                const SizedBox(height: 20),

                // ── Description ──
                _SettingsLabel('Description'),
                const SizedBox(height: 6),
                _SettingsInput(
                  controller: _descController,
                  maxLines: 3,
                  hint: 'Optional description',
                ),
                const SizedBox(height: 20),

                // ── Target amount ──
                _SettingsLabel('Target amount (RWF)'),
                const SizedBox(height: 6),
                _SettingsInput(
                  controller: _targetController,
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 20),

                // ── Frequency ──
                _SettingsLabel('Contribution frequency'),
                const SizedBox(height: 6),
                _FrequencySelector(
                  value: _frequency,
                  onChanged: (v) => setState(() => _frequency = v),
                ),
                const SizedBox(height: 20),

                // ── Visibility ──
                _SettingsLabel('Visibility'),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _SettingsToggle(
                      label: 'Private',
                      isSelected: _visibility == 'private',
                      onTap: () => setState(() => _visibility = 'private'),
                    ),
                    const SizedBox(width: 8),
                    _SettingsToggle(
                      label: 'Public',
                      isSelected: _visibility == 'public',
                      onTap: () => setState(() => _visibility = 'public'),
                    ),
                  ],
                ),
                const SizedBox(height: 28),

                // ── Admins ──
                _SettingsLabel(
                  'Admins (${admins.length})',
                ),
                const SizedBox(height: 8),
                ...admins.map(
                  (a) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        Icon(
                          Icons.admin_panel_settings_outlined,
                          size: 18,
                          color: AppColors.accent,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            a.displayName ?? '#${a.userId.substring(0, 6)}',
                            style: GoogleFonts.dmSans(
                              fontSize: 14,
                              color: AppColors.text,
                            ),
                          ),
                        ),
                        if (a.userId != currentUserId)
                          IconButton(
                            icon: Icon(
                              Icons.remove_circle_outline,
                              size: 18,
                              color: AppColors.red,
                            ),
                            onPressed: () {
                              // TODO: remove admin
                            },
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () {
                    // TODO: add admin — pick from members list
                  },
                  icon: Icon(
                    Icons.person_add_alt_1_rounded,
                    size: 18,
                    color: AppColors.accent,
                  ),
                  label: Text(
                    'Add admin',
                    style: GoogleFonts.dmSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.accent,
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // ── Save ──
                SizedBox(
                  width: double.infinity,
                  child: CoolButton(
                    label: 'Save changes',
                    isLoading: _isSaving,
                    onTap: _saveChanges,
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Tiny helper widgets for settings ──

class _SettingsLabel extends StatelessWidget {
  const _SettingsLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.dmSans(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: AppColors.text2,
        letterSpacing: 0.4,
      ),
    );
  }
}

class _SettingsInput extends StatelessWidget {
  const _SettingsInput({
    required this.controller,
    this.maxLines = 1,
    this.hint,
    this.keyboardType,
  });

  final TextEditingController controller;
  final int maxLines;
  final String? hint;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      style: GoogleFonts.dmSans(fontSize: 14, color: AppColors.text),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.dmSans(fontSize: 13, color: AppColors.text3),
        filled: true,
        fillColor: AppColors.surface2,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColors.accent, width: 1.5),
        ),
      ),
    );
  }
}

class _FrequencySelector extends StatelessWidget {
  const _FrequencySelector({
    required this.value,
    required this.onChanged,
  });

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    const options = ['daily', 'weekly', 'monthly'];
    return Row(
      children: [
        for (final opt in options) ...[
          _SettingsToggle(
            label: opt[0].toUpperCase() + opt.substring(1),
            isSelected: value == opt,
            onTap: () => onChanged(opt),
          ),
          if (opt != options.last) const SizedBox(width: 8),
        ],
      ],
    );
  }
}

class _SettingsToggle extends StatelessWidget {
  const _SettingsToggle({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.accentGlow : AppColors.surface2,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
            color: isSelected ? AppColors.accent : AppColors.border,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: GoogleFonts.dmSans(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isSelected ? AppColors.accent : AppColors.text2,
          ),
        ),
      ),
    );
  }
}
