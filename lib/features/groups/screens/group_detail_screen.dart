import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/config/deep_link_config.dart';
import '../../../core/providers/referral_providers.dart';
import '../../../core/status/cool_status_awarder.dart';
import '../../../core/status/models/cool_event.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_screen_background.dart';
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

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(groupDetailProvider(widget.groupId));
    final isActionLoading = ref.watch(
      groupsProvider.select((state) => state.isLoading),
    );

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: Text(
          'Group Detail',
          style: GoogleFonts.dmSans(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.text,
          ),
        ),
      ),
      body: CoolScreenBackground(
        primaryColor: AppColors.accent,
        secondaryColor: AppColors.blue,
        child: detailAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _buildErrorState(error.toString()),
          data: (detail) => detail == null
              ? _buildErrorState('Group not found.')
              : _buildContent(detail, isActionLoading),
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
      multiSelect: true,
      title: 'Invite to ${detail.group.name}',
      subtitle: 'Select contacts to send the invite link',
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

    final shareText =
        'Join ${group.name} on Cool! 🎉\n${shareUri.toString()}';
    await SharePlus.instance.share(ShareParams(text: shareText));
  }

  Widget _buildErrorState(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('⚠️', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 16),
            Text(
              'Something went wrong',
              style: GoogleFonts.dmSans(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.text2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              textAlign: TextAlign.center,
              style: GoogleFonts.dmSans(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: AppColors.text3,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: 160,
              child: CoolButton(
                label: 'Retry',
                onTap: () =>
                    ref.invalidate(groupDetailProvider(widget.groupId)),
              ),
            ),
          ],
        ),
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
    final visibleMembers = _showAllMembers ? members : members.take(4).toList();

    final custodianLabel = group.bankPartner != null
        ? '${group.bankPartner} Custodian'
        : group.momoNumber != null
        ? 'MOMO collection route'
        : group.type == 'saving'
        ? 'Saving group'
        : 'Community fund';

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
                    '$percent% reached · $custodianLabel',
                    style: GoogleFonts.dmSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: AppColors.text2,
                    ),
                  ),
                  if (group.frequency != null ||
                      (group.description?.trim().isNotEmpty ?? false)) ...[
                    const SizedBox(height: 10),
                    if (group.frequency != null && group.frequency!.isNotEmpty)
                      Text(
                        'Contribution cadence: ${_formatFrequency(group.frequency!)}',
                        style: GoogleFonts.dmSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppColors.text2,
                        ),
                      ),
                    if (group.description?.trim().isNotEmpty ?? false) ...[
                      const SizedBox(height: 6),
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

                  // MOMO note for community funds
                  if (group.type == 'community') ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.orange.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '📱 Community fund — MOMO destination',
                        style: GoogleFonts.dmSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: AppColors.orange,
                        ),
                      ),
                    ),
                  ],
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
              Expanded(
                child: CoolButton(
                  label: '🔗 Share / QR',
                  variant: CoolButtonVariant.secondary,
                  onTap: () => _openShareSheet(detail),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          CoolButton(
            label: '👥 Invite from Contacts',
            variant: CoolButtonVariant.secondary,
            onTap: () => _inviteFromContacts(detail),
          ),
          const SizedBox(height: 28),

          // ═══════════════════════════════════════════════════════
          // MEMBERS SECTION
          // ═══════════════════════════════════════════════════════
          SectionTitle(title: 'Members (${members.length})'),
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

          if (!_showAllMembers && members.length > 4) ...[
            const SizedBox(height: 8),
            Center(
              child: GestureDetector(
                onTap: () => setState(() => _showAllMembers = true),
                child: Text(
                  'Show all ${members.length} members',
                  style: GoogleFonts.dmSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.accent,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 28),

          // ═══════════════════════════════════════════════════════
          // CONTRIBUTIONS HISTORY
          // ═══════════════════════════════════════════════════════
          const SectionTitle(title: 'Contributions History'),
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
            ...contributions.map((c) => _ContributionRow(contribution: c)),
        ],
      ),
    );
  }

  void _showContributeSheet(BuildContext context, GroupDetail detail) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ContributeSheet(
        groupId: detail.group.id ?? '',
        groupName: detail.group.name,
        monthlyAmount: detail.group.monthlyContribution ?? 5000,
        frequency: detail.group.frequency ?? 'monthly',
        groupsNotifier: ref.read(groupsProvider.notifier),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'This group does not have a shareable invite code yet.',
            style: GoogleFonts.dmSans(color: AppColors.text),
          ),
          backgroundColor: AppColors.surface2,
        ),
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
      final error = ref.read(groupsProvider).error ?? 'Could not join group.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error,
            style: GoogleFonts.dmSans(color: AppColors.text),
          ),
          backgroundColor: AppColors.surface2,
        ),
      );
      return;
    }

    final message = result.didJoin
        ? 'You joined ${result.detail.group.name}.'
        : 'You are already a member of ${result.detail.group.name}.';
    ref.invalidate(groupDetailProvider(widget.groupId));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: GoogleFonts.dmSans(color: AppColors.text),
        ),
        backgroundColor: AppColors.surface2,
      ),
    );
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
      decoration: const BoxDecoration(
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
            child: const Text('📥', style: TextStyle(fontSize: 18)),
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

class _ContributeSheet extends StatefulWidget {
  const _ContributeSheet({
    required this.groupId,
    required this.groupName,
    required this.monthlyAmount,
    required this.frequency,
    required this.groupsNotifier,
    this.onSuccess,
  });

  final String groupId;
  final String groupName;
  final int monthlyAmount;
  final String frequency;
  final GroupsNotifier groupsNotifier;
  final void Function(String groupId)? onSuccess;

  @override
  State<_ContributeSheet> createState() => _ContributeSheetState();
}

class _ContributeSheetState extends State<_ContributeSheet> {
  late final TextEditingController _amountController;
  int? _selectedMultiplier; // 0=half, 1=full, 2=double
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
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
      setState(() => _error = 'Enter a valid contribution amount.');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    final contribution = await widget.groupsNotifier.contribute(
      widget.groupId,
      amount,
    );

    if (!mounted) return;

    if (contribution != null) {
      widget.onSuccess?.call(widget.groupId);
      Navigator.of(context).pop();
      return;
    }

    setState(() {
      _isLoading = false;
      _error = widget.groupsNotifier.currentError ?? 'Payment could not start.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final half = widget.monthlyAmount ~/ 2;
    final full = widget.monthlyAmount;
    final double = widget.monthlyAmount * 2;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
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
                '${_GroupDetailScreenState._formatFrequency(widget.frequency)}: '
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
              TextField(
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
                    'RWF  ',
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
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.border),
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
              const SizedBox(height: 12),

              // Quick-select chips
              Row(
                children: [
                  _AmountChip(
                    label: 'Half (${_formatK(half)})',
                    isSelected: _selectedMultiplier == 0,
                    onTap: () => _selectAmount(0),
                  ),
                  const SizedBox(width: 8),
                  _AmountChip(
                    label: 'Full (${_formatK(full)})',
                    isSelected: _selectedMultiplier == 1,
                    onTap: () => _selectAmount(1),
                  ),
                  const SizedBox(width: 8),
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
                isLoading: _isLoading,
                onTap: _payViaMomo,
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
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
                    const Text('📞', style: TextStyle(fontSize: 16)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'You\'ll be redirected to MOMO USSD to confirm payment. No card needed.',
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
