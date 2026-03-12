import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../shared/widgets/cool_skeleton.dart';

import '../../../core/config/deep_link_config.dart';
import '../../../core/providers/referral_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_screen_background.dart';
import '../../../shared/widgets/qr_share_sheet.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../../shared/widgets/tab_pill.dart';
import '../models/group.dart';
import '../providers/groups_provider.dart';

/// Groups listing screen with tab filters, a create-group banner,
/// and a filterable list of group cards.
class GroupsScreen extends ConsumerStatefulWidget {
  const GroupsScreen({super.key});

  @override
  ConsumerState<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends ConsumerState<GroupsScreen> {
  String _activeTab = 'All';

  @override
  void initState() {
    super.initState();
    // Trigger initial load from Supabase.
    Future.microtask(() => ref.read(groupsProvider.notifier).loadMyGroups());
  }

  Future<void> _onTabChanged(String tab) async {
    setState(() => _activeTab = tab);
    final notifier = ref.read(groupsProvider.notifier);

    if (tab.contains('Public')) {
      await notifier.loadPublicGroups();
      return;
    }

    if (tab.contains('Saving')) {
      await notifier.loadFilteredMyGroups(type: 'saving');
      return;
    }

    if (tab.contains('Community')) {
      await notifier.loadFilteredMyGroups(type: 'community');
      return;
    }

    if (tab.contains('Private')) {
      await notifier.loadFilteredMyGroups(visibility: 'private');
      return;
    }

    await notifier.loadMyGroups();
  }

  Future<void> _openShareSheet(Group group) async {
    final baseUri = group.inviteCode != null && group.inviteCode!.isNotEmpty
        ? DeepLinkConfig.inviteUri(group.inviteCode!)
        : ((group.id?.isNotEmpty ?? false)
              ? DeepLinkConfig.groupDetailUri(group.id!)
              : Uri.https(DeepLinkConfig.host, '/groups'));

    var shareUri = baseUri;
    try {
      final inviteCode = group.inviteCode?.trim().isNotEmpty == true
          ? group.inviteCode!.trim().toUpperCase()
          : 'GROUP-${group.id ?? 'DISCOVERY'}';
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

  Future<void> _refreshActiveTab() {
    return _onTabChanged(_activeTab);
  }

  @override
  Widget build(BuildContext context) {
    final groups = ref.watch(groupsListProvider);
    final isLoading = ref.watch(groupsListLoadingProvider);
    final error = ref.watch(groupsListErrorProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(
          'Groups',
          style: GoogleFonts.dmSans(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.text,
          ),
        ),
      ),
      body: CoolScreenBackground(
        child: isLoading && groups.isEmpty
            ? const Padding(
                padding: EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                child: CoolSkeletonList(),
              )
            : error != null && groups.isEmpty
            ? _ErrorState(error: error, onRetry: _refreshActiveTab)
            : RefreshIndicator(
                onRefresh: _refreshActiveTab,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
                      sliver: SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 8),
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: _tabs.map((t) {
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: TabPill(
                                      label: t,
                                      isActive: _activeTab == t,
                                      onTap: () => unawaited(_onTabChanged(t)),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                            const SizedBox(height: 20),
                            if (!_activeTab.contains('Public')) ...[
                              const _CreateGroupBanner(),
                              const SizedBox(height: 20),
                            ],
                          ],
                        ),
                      ),
                    ),
                    if (groups.isEmpty)
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(18, 0, 18, 96),
                        sliver: SliverToBoxAdapter(
                          child: _EmptyState(
                            isPublicCatalog: _activeTab.contains('Public'),
                          ),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(18, 0, 18, 96),
                        sliver: SliverList.separated(
                          itemCount: groups.length,
                          itemBuilder: (context, index) {
                            final group = groups[index];
                            return _GroupListItem(
                              group: group,
                              onShare: () => _openShareSheet(group),
                            );
                          },
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 12),
                        ),
                      ),
                  ],
                ),
              ),
      ),
    );
  }

  static const _tabs = [
    'All',
    'Saving',
    'Community',
    'Public',
    'Private',
  ];
}

// ═════════════════════════════════════════════════════════════════════════
// Create group banner (dashed border)
// ═════════════════════════════════════════════════════════════════════════

class _CreateGroupBanner extends StatelessWidget {
  const _CreateGroupBanner();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/groups/create'),
      child: CustomPaint(
        painter: _DashedBorderPainter(
          color: AppColors.accent,
          radius: 20,
          dashWidth: 6,
          dashGap: 4,
        ),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 18),
          decoration: BoxDecoration(
            color: AppColors.accentGlow,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  '＋',
                  style: GoogleFonts.dmSans(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: AppColors.accent,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Create a New Group',
                style: GoogleFonts.dmSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Saving or Community',
                textAlign: TextAlign.center,
                style: GoogleFonts.dmSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: AppColors.text2,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({this.isPublicCatalog = false});

  final bool isPublicCatalog;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          const Icon(Icons.people_alt_outlined, size: 32, color: AppColors.text3),
          const SizedBox(height: 12),
          Text(
            isPublicCatalog ? 'No public groups found' : 'No groups yet',
            style: GoogleFonts.dmSans(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isPublicCatalog
                ? 'Pull to refresh or check your groups.'
                : 'Create a group or browse public ones.',
            textAlign: TextAlign.center,
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: AppColors.text2,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
// Dashed border painter
// ═════════════════════════════════════════════════════════════════════════

class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter({
    required this.color,
    required this.radius,
    required this.dashWidth,
    required this.dashGap,
  });

  final Color color;
  final double radius;
  final double dashWidth;
  final double dashGap;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );

    final path = Path()..addRRect(rrect);
    final metrics = path.computeMetrics().first;
    final totalLength = metrics.length;

    double distance = 0;
    while (distance < totalLength) {
      final end = (distance + dashWidth).clamp(0.0, totalLength);
      final segment = metrics.extractPath(distance, end);
      canvas.drawPath(segment, paint);
      distance += dashWidth + dashGap;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color;
}

// ═════════════════════════════════════════════════════════════════════════
// Group list item
// ═════════════════════════════════════════════════════════════════════════

class _GroupListItem extends StatelessWidget {
  const _GroupListItem({required this.group, this.onShare});
  final Group group;
  final VoidCallback? onShare;

  @override
  Widget build(BuildContext context) {
    final progress = group.targetAmount > 0
        ? (group.amount / group.targetAmount).clamp(0.0, 1.0)
        : 0.0;

    final meta = group.bankPartner != null
        ? 'Bank custodian · ${group.bankPartner}'
        : group.momoNumber != null
        ? 'MOMO route · ${group.momoNumber}'
        : group.type == 'saving'
        ? 'Saving group'
        : 'Community fund';

    return CoolCard(
      onTap: () {
        final id = group.id;
        if (id != null) context.push('/groups/$id');
      },
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top row: badges + amount
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
                const Spacer(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _formatAmount(group.amount),
                      style: GoogleFonts.dmMono(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: group.type == 'saving'
                            ? AppColors.accent
                            : AppColors.orange,
                      ),
                    ),
                    Text(
                      'raised',
                      style: GoogleFonts.dmSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w400,
                        color: AppColors.text3,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Group name
            Text(
              group.name,
              style: GoogleFonts.dmSans(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 4),

            // Meta info
            Text(
              '$meta · ${group.memberCount} members',
              style: GoogleFonts.dmSans(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: AppColors.text2,
              ),
            ),
            const SizedBox(height: 12),

            // Progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 4,
                backgroundColor: AppColors.surface3,
                color: group.type == 'saving'
                    ? AppColors.accent
                    : AppColors.orange,
              ),
            ),
            const SizedBox(height: 14),

            // Footer: member count + share button
            Row(
              children: [
                Text(
                  '${group.memberCount} members',
                  style: GoogleFonts.dmSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text3,
                  ),
                ),
                const Spacer(),

                // Share button
                GestureDetector(
                  onTap: onShare,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surface3,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.link_rounded, size: 14, color: AppColors.text2),
                        const SizedBox(width: 5),
                        Text(
                          'Share',
                          style: GoogleFonts.dmSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: AppColors.text2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
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
}

// ═════════════════════════════════════════════════════════════════════════
// Error state
// ═════════════════════════════════════════════════════════════════════════

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error, required this.onRetry});
  final String error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.warning_amber_rounded, size: 40, color: AppColors.orange),
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
                onTap: () => unawaited(onRetry()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
