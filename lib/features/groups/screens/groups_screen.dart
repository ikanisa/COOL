import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/cool_screen_background.dart';
import '../../../shared/widgets/cool_search_field.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../../../shared/widgets/qr_share_sheet.dart';
import '../../../shared/widgets/tab_pill.dart';
import '../../auth/providers/auth_provider.dart';
import '../group_flow_utils.dart';
import '../models/group.dart';
import '../models/group_invite_preview.dart';
import '../providers/groups_provider.dart';

part 'groups_screen_sections.dart';

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
    launchGroupContribution(context, group: group).then((ok) {
      if (!ok && mounted) {
        CoolToast.error(
          context,
          'Could not launch MoMo USSD. Try dialing manually.',
        );
      }
    });
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

    return CoolScreenBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
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
      ),
    );
  }
}
