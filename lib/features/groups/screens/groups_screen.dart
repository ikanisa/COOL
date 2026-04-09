import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/cool_search_field.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../../../shared/widgets/qr_share_sheet.dart';
import '../../../shared/widgets/tab_pill.dart';
import '../../auth/providers/auth_provider.dart';
import '../group_flow_utils.dart';
import '../models/group.dart';
import '../models/group_invite_preview.dart';
import '../providers/groups_provider.dart';

class GroupsScreen extends ConsumerStatefulWidget {
  const GroupsScreen({this.inviteCode, super.key});

  final String? inviteCode;

  @override
  ConsumerState<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends ConsumerState<GroupsScreen> {
  bool _showMine = true;
  bool _inviteBannerDismissed = false;
  bool _isJoining = false;
  String _publicSearch = '';

  Future<void> _refreshGroups() async {
    ref.read(groupsRefreshTickProvider.notifier).state++;
  }

  Future<void> _openCreateGroup() async {
    final groupId = await context.push<String>(AppRoutes.groupCreate);
    if (!mounted || groupId == null || groupId.isEmpty) {
      return;
    }

    context.push(AppRoutes.contributionCircleDetailLocation(groupId));
  }

  void _openGroup(Group group) {
    final groupId = group.id;
    if (groupId == null || groupId.isEmpty) {
      CoolToast.error(context, context.l10n.groupNotFound);
      return;
    }
    context.push(AppRoutes.contributionCircleDetailLocation(groupId));
  }

  void _contributeToGroup(Group group) {
    if (!groupHasContributionRoute(group)) {
      CoolToast.info(
        context,
        'This group has no payment route configured yet.',
      );
      _openGroup(group);
      return;
    }
    context.push(buildGroupContributionLocation(group));
  }

  Future<void> _inviteMembers(Group group) async {
    final inviteUrl = buildGroupInviteUrl(group);
    if (inviteUrl == null) {
      CoolToast.info(context, context.l10n.noInviteCodeYet);
      return;
    }

    await QrShareSheet.show(
      context,
      groupName: group.name,
      inviteUrl: inviteUrl,
      sheetTitle: context.l10n.inviteToGroup(group.name),
      shareText: context.l10n.joinGroupShareText(group.name, inviteUrl),
      analyticsTargetType: 'group_invite',
    );
  }

  Future<void> _joinPublicGroup(Group group) async {
    if (_isJoining) {
      return;
    }
    final user = ref.read(authProvider).user;
    if (user == null) {
      CoolToast.error(context, 'Complete your profile first.');
      return;
    }

    setState(() => _isJoining = true);
    try {
      final result = await ref.read(groupRepositoryProvider).joinPublicGroup(
        group: group,
        user: user,
      );
      ref.read(groupsRefreshTickProvider.notifier).state++;
      if (!mounted) {
        return;
      }
      CoolToast.success(
        context,
        result.isAlreadyMember
            ? context.l10n.alreadyMemberOf(group.name)
            : context.l10n.youJoinedGroup(group.name),
      );
      _openGroup(group);
    } catch (error) {
      if (mounted) {
        CoolToast.error(context, error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _isJoining = false);
      }
    }
  }

  Future<void> _acceptInvite(
    String inviteCode,
    GroupInvitePreview preview,
  ) async {
    if (_isJoining) {
      return;
    }
    if (preview.isMember) {
      _dismissInviteBanner(navigate: false);
      _openGroup(preview.group);
      return;
    }

    setState(() => _isJoining = true);
    try {
      final result = await ref
          .read(groupRepositoryProvider)
          .joinGroupViaInvite(inviteCode);
      if (!mounted) {
        return;
      }
      if (!result.isJoined) {
        throw StateError(result.message ?? context.l10n.couldNotJoinGroup);
      }

      ref.read(groupsRefreshTickProvider.notifier).state++;
      CoolToast.success(context, context.l10n.youJoinedGroup(preview.group.name));
      _dismissInviteBanner(navigate: false);
      _openGroup(preview.group);
    } catch (error) {
      if (mounted) {
        CoolToast.error(context, error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _isJoining = false);
      }
    }
  }

  void _dismissInviteBanner({bool navigate = true}) {
    setState(() => _inviteBannerDismissed = true);
    if (navigate) {
      context.go(AppRoutes.contributionCircles);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final textTheme = context.coolText;
    final colors = context.coolSemanticColors;
    final space = context.coolSpace;
    final inviteCode = widget.inviteCode?.trim();
    final groupsAsync = ref.watch(
      _showMine ? myGroupsProvider : publicGroupsSearchProvider(_publicSearch),
    );
    final myGroupIds = ref.watch(myGroupIdsProvider);
    final invitePreviewAsync =
        inviteCode == null || inviteCode.isEmpty || _inviteBannerDismissed
        ? null
        : ref.watch(groupInvitePreviewProvider(inviteCode));

    return Scaffold(
      backgroundColor: colors.appBackground,
      floatingActionButton: _showMine
          ? FloatingActionButton.extended(
              onPressed: _openCreateGroup,
              backgroundColor: colors.accent,
              foregroundColor: colors.accentForeground,
              icon: const Icon(Icons.add_rounded),
              label: Text(
                'CREATE',
                style: textTheme.mobiLabel(
                  color: colors.accentForeground,
                ).copyWith(fontWeight: FontWeight.w800),
              ),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _refreshGroups,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar(
              backgroundColor: colors.appBackground.withValues(alpha: 0.9),
              elevation: 0,
              pinned: true,
              title: Text(
                l10n.navGroups.toUpperCase(),
                style: textTheme.displayCondensed(null, letterSpacing: 1.2),
              ),
              actions: [
                const _DataPulseBadge().animate().fadeIn(),
                SizedBox(width: space.x4),
              ],
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: space.x4,
                  vertical: space.x3,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Create groups, invite members, and collect contributions in one place.',
                      style: textTheme.mobiLabel(color: colors.secondaryText),
                    ),
                    SizedBox(height: space.x3),
                    AnimatedSwitcher(
                      duration: CoolMotion.quick,
                      child: Row(
                        key: ValueKey<bool>(_showMine),
                        children: [
                          Expanded(
                            child: TabPill(
                              label: 'My Ledgers',
                              isActive: _showMine,
                              onTap: () => setState(() => _showMine = true),
                            ),
                          ),
                          SizedBox(width: space.x2),
                          Expanded(
                            child: TabPill(
                              label: 'Explore',
                              isActive: !_showMine,
                              onTap: () => setState(() => _showMine = false),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!_showMine) ...[
                      SizedBox(height: space.x3),
                      CoolSearchField(
                        hint: l10n.searchGroups,
                        onChanged: (value) {
                          setState(() => _publicSearch = value.trim());
                        },
                      ),
                    ],
                    if (invitePreviewAsync != null) ...[
                      SizedBox(height: space.x3),
                      invitePreviewAsync.when(
                        data: (preview) {
                          if (preview == null) {
                            return _InviteBanner(
                              title: 'Invite not found',
                              subtitle: 'This invite code is not active.',
                              actionLabel: 'DISMISS',
                              onAction: _dismissInviteBanner,
                              onDismiss: _dismissInviteBanner,
                            );
                          }
                          return _InviteBanner(
                            title: preview.group.name,
                            subtitle: preview.isMember
                                ? 'You already belong to this group.'
                                : '${preview.group.memberCount} members • ${preview.group.visibility.toUpperCase()}',
                            actionLabel: preview.isMember ? 'OPEN' : 'JOIN NOW',
                            onAction: () => _acceptInvite(inviteCode!, preview),
                            onDismiss: _dismissInviteBanner,
                            isLoading: _isJoining,
                          );
                        },
                        loading: () => const _InviteBannerLoading(),
                        error: (error, _) => _InviteBanner(
                          title: 'Invite could not be loaded',
                          subtitle: error.toString(),
                          actionLabel: 'DISMISS',
                          onAction: _dismissInviteBanner,
                          onDismiss: _dismissInviteBanner,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            groupsAsync.when(
              data: (groups) {
                if (groups.isEmpty) {
                  return SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyGroupsState(
                      title: _showMine
                          ? 'No groups yet'
                          : l10n.groupsEmptyPublicTitle,
                      message: _showMine
                          ? 'Create your first group or join a public one.'
                          : l10n.groupsEmptyPublicMessage,
                      actionLabel: _showMine ? 'CREATE GROUP' : null,
                      onAction: _showMine ? _openCreateGroup : null,
                    ),
                  );
                }

                return SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: space.x4),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final group = groups[index];
                      final isMember = myGroupIds.contains(group.id ?? '');
                      return Padding(
                        padding: EdgeInsets.only(bottom: space.x3),
                        child: _GroupLedgerCard(
                          group: group,
                          isMember: isMember,
                          isBusy: _isJoining,
                          onOpen: () => _openGroup(group),
                          onInvite: isMember ? () => _inviteMembers(group) : null,
                          onJoin: !isMember && group.visibility == 'public'
                              ? () => _joinPublicGroup(group)
                              : null,
                          onContribute: isMember
                              ? () => _contributeToGroup(group)
                              : null,
                        ),
                      );
                    }, childCount: groups.length),
                  ),
                );
              },
              loading: () => const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => SliverFillRemaining(
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.all(space.x4),
                    child: Text(
                      '${l10n.loadGroupsFailed}: $error',
                      textAlign: TextAlign.center,
                      style: textTheme.mobiLabel(color: colors.danger),
                    ),
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.paddingOf(context).bottom + 110,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupLedgerCard extends StatelessWidget {
  const _GroupLedgerCard({
    required this.group,
    required this.isMember,
    required this.isBusy,
    required this.onOpen,
    this.onInvite,
    this.onJoin,
    this.onContribute,
  });

  final Group group;
  final bool isMember;
  final bool isBusy;
  final VoidCallback onOpen;
  final VoidCallback? onInvite;
  final VoidCallback? onJoin;
  final VoidCallback? onContribute;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final textTheme = context.coolText;
    final space = context.coolSpace;
    final isPublic = group.visibility == 'public';
    final inviteable = onInvite != null;
    final canJoin = onJoin != null;
    final canContribute = onContribute != null;
    final hasRoute = groupHasContributionRoute(group);

    return Container(
      padding: EdgeInsets.all(space.x4),
      decoration: BoxDecoration(
        color: colors.cardSurface,
        borderRadius: BorderRadius.circular(CoolRadii.lg),
        border: Border.all(color: colors.border),
        boxShadow: CoolShadows.standard(Theme.of(context).brightness),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group.name,
                      style: textTheme.display(
                        null,
                        color: colors.primaryText,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: space.x1),
                    Text(
                      '${group.memberCount} members • ${group.country} • ${group.type == 'community' ? 'Community' : 'Saving'}',
                      style: textTheme.mobiLabel(color: colors.secondaryText),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isPublic
                      ? colors.info.withValues(alpha: 0.15)
                      : colors.warning.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(CoolRadii.sm),
                  border: Border.all(
                    color: isPublic
                        ? colors.info.withValues(alpha: 0.3)
                        : colors.warning.withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  isPublic ? 'PUBLIC' : 'PRIVATE',
                  style: textTheme.mobiLabel(
                    color: isPublic ? colors.info : colors.warning,
                  ),
                ),
              ),
            ],
          ),
          if ((group.description ?? '').trim().isNotEmpty) ...[
            SizedBox(height: space.x3),
            Text(
              group.description!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: textTheme.mobiLabel(color: colors.secondaryText),
            ),
          ],
          SizedBox(height: space.x3),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: space.x3,
              vertical: space.x2,
            ),
            decoration: BoxDecoration(
              color: colors.elevatedBackground,
              borderRadius: BorderRadius.circular(CoolRadii.md),
              border: Border.all(color: colors.divider),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'BALANCE',
                      style: textTheme.mobiLabel(color: colors.tertiaryText),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${group.amount} RWF',
                      style: textTheme.mono(null, color: colors.accentGold),
                    ),
                  ],
                ),
                if ((group.monthlyContribution ?? 0) > 0)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'MONTHLY',
                        style: textTheme.mobiLabel(color: colors.tertiaryText),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${group.monthlyContribution} RWF',
                        style: textTheme.mono(
                          null,
                          color: colors.secondaryText,
                        ),
                      ),
                    ],
                  )
                else if (group.targetAmount > 0)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'TARGET',
                        style: textTheme.mobiLabel(color: colors.tertiaryText),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${group.targetAmount} RWF',
                        style: textTheme.mono(
                          null,
                          color: colors.secondaryText,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          SizedBox(height: space.x3),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: isBusy && canJoin ? null : onOpen,
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.symmetric(vertical: space.x3),
                    side: BorderSide(color: colors.border),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(CoolRadii.md),
                    ),
                  ),
                  child: Text(inviteable ? 'OPEN / INVITE' : 'OPEN'),
                ),
              ),
              SizedBox(width: space.x2),
              Expanded(
                child: TextButton.icon(
                  onPressed: isBusy
                      ? null
                      : canJoin
                      ? onJoin
                      : inviteable
                      ? onInvite
                      : canContribute
                      ? onContribute
                      : onOpen,
                  icon: Icon(
                    canJoin
                        ? Icons.person_add_alt_1_rounded
                        : inviteable
                        ? Icons.ios_share_rounded
                        : hasRoute
                        ? Icons.payments_rounded
                        : Icons.arrow_forward_rounded,
                    color: colors.accentForeground,
                  ),
                  label: Text(
                    canJoin
                        ? 'JOIN'
                        : inviteable
                        ? 'INVITE'
                        : hasRoute && canContribute
                        ? 'CONTRIBUTE'
                        : 'DETAILS',
                    style: textTheme.mobiLabel(
                      color: colors.accentForeground,
                    ).copyWith(fontWeight: FontWeight.w800, letterSpacing: 1.1),
                  ),
                  style: TextButton.styleFrom(
                    backgroundColor: colors.accent,
                    padding: EdgeInsets.symmetric(vertical: space.x3),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(CoolRadii.md),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.1, end: 0.0);
  }
}

class _InviteBanner extends StatelessWidget {
  const _InviteBanner({
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onAction,
    required this.onDismiss,
    this.isLoading = false,
  });

  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onAction;
  final VoidCallback onDismiss;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final space = context.coolSpace;

    return Container(
      padding: EdgeInsets.all(space.x4),
      decoration: BoxDecoration(
        color: colors.cardSurfaceStrong,
        borderRadius: BorderRadius.circular(CoolRadii.lg),
        border: Border.all(color: colors.accent.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: text.display(
                    null,
                    color: colors.primaryText,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                onPressed: onDismiss,
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          Text(
            subtitle,
            style: text.mobiLabel(color: colors.secondaryText),
          ),
          SizedBox(height: space.x3),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: isLoading ? null : onAction,
              child: isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(actionLabel),
            ),
          ),
        ],
      ),
    );
  }
}

class _InviteBannerLoading extends StatelessWidget {
  const _InviteBannerLoading();

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    return Container(
      padding: const EdgeInsets.all(CoolSpace.x4),
      decoration: BoxDecoration(
        color: colors.cardSurface,
        borderRadius: BorderRadius.circular(CoolRadii.lg),
        border: Border.all(color: colors.border),
      ),
      child: const Center(child: CircularProgressIndicator()),
    );
  }
}

class _EmptyGroupsState extends StatelessWidget {
  const _EmptyGroupsState({
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final space = context.coolSpace;
    return Center(
      child: Padding(
        padding: EdgeInsets.all(space.x6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.groups_rounded, size: 48, color: colors.secondaryText),
            SizedBox(height: space.x3),
            Text(
              title,
              style: text.display(
                null,
                color: colors.primaryText,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: space.x2),
            Text(
              message,
              textAlign: TextAlign.center,
              style: text.mobiLabel(color: colors.secondaryText),
            ),
            if (actionLabel != null && onAction != null) ...[
              SizedBox(height: space.x4),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

class _DataPulseBadge extends StatefulWidget {
  const _DataPulseBadge();

  @override
  State<_DataPulseBadge> createState() => _DataPulseBadgeState();
}

class _DataPulseBadgeState extends State<_DataPulseBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final textTheme = context.coolText;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colors.appBackground,
        borderRadius: BorderRadius.circular(CoolRadii.pill),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _ctrl,
            builder: (context, _) {
              final opacity = 0.4 + (_ctrl.value * 0.6);
              return Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.success.withValues(alpha: opacity),
                  boxShadow: [
                    BoxShadow(
                      color: colors.success.withValues(alpha: opacity * 0.5),
                      blurRadius: 4,
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(width: 6),
          Text('LIVE', style: textTheme.mobiLabel(color: colors.success)),
        ],
      ),
    );
  }
}
