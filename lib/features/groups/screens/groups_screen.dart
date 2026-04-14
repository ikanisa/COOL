import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../core/utils/money_formatters.dart';
import '../../../core/utils/user_error.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_chip_bar.dart';
import '../../../shared/widgets/cool_empty_view.dart';
import '../../../shared/widgets/cool_floating_header_sliver.dart';
import '../../../shared/widgets/cool_icon_box.dart';

import '../../../shared/widgets/cool_screen_background.dart';
import '../../../shared/widgets/cool_search_field.dart';
import '../../../shared/widgets/cool_skeleton.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../../../shared/widgets/qr_share_sheet.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../auth/providers/auth_provider.dart';
import '../../auth/widgets/require_verified_user.dart';
import '../../profile/services/momo_setup_guard.dart';
import '../group_flow_utils.dart';
import '../models/group.dart';
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
  Timer? _searchDebounce;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  Future<void> _refreshGroups() async {
    ref.read(groupsRefreshTickProvider.notifier).state++;
  }

  Future<void> _openCreateGroup() async {
    final groupId = await context.push<String>(AppRoutes.groupCreate);
    if (!mounted || groupId == null || groupId.isEmpty) {
      return;
    }

    context.push(AppRoutes.groupDetailLocation(groupId));
  }

  void _openGroup(Group group) {
    final groupId = group.id;
    if (groupId == null || groupId.isEmpty) {
      CoolToast.error(context, context.l10n.groupNotFound);
      return;
    }
    context.push(AppRoutes.groupDetailLocation(groupId));
  }

  void _openInvitedGroupPreview(Group group, String inviteCode) {
    final groupId = group.id;
    if (groupId == null || groupId.isEmpty) {
      CoolToast.error(context, context.l10n.groupNotFound);
      return;
    }
    context.push(
      AppRoutes.groupDetailLocation(groupId, inviteCode: inviteCode),
    );
  }

  Future<void> _contributeToGroup(Group group) async {
    if (!groupHasContributionRoute(group)) {
      CoolToast.info(context, context.l10n.groupsPaymentRoutePendingInfo);
      _openGroup(group);
      return;
    }
    launchGroupContribution(context, group: group).then((ok) {
      if (!ok && mounted) {
        CoolToast.error(context, context.l10n.groupsLaunchMomoUssdError);
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

    if (!await requireVerifiedUser(
      context,
      ref,
      feature: WhatsAppProtectedFeature.groupJoin,
    )) {
      return;
    }

    if (!mounted) {
      return;
    }

    if (!await ensureMomoSetupForAction(
      context,
      ref,
      intent: MomoSetupIntent.joinGroup,
    )) {
      return;
    }

    if (!mounted) {
      return;
    }

    final user = ref.read(authProvider).user;
    if (user == null) {
      return;
    }

    setState(() => _isJoining = true);
    try {
      final result = await ref
          .read(groupRepositoryProvider)
          .joinPublicGroup(group: group, user: user);
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
        CoolToast.error(context, describeUserFacingError(error));
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
      context.go(AppRoutes.groups);
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
            ? FloatingActionButton(
                onPressed: _openCreateGroup,
                backgroundColor: colors.accent,
                foregroundColor: colors.accentForeground,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(CoolRadii.lg),
                ),
                child: const Icon(CoolIcons.add),
              )
            : null,
        body: RefreshIndicator(
          onRefresh: _refreshGroups,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              CoolFloatingHeaderSliver(
                leading: IconButton(
                  onPressed: () {
                    if (context.canPop()) {
                      context.pop();
                    } else {
                      context.go(AppRoutes.home);
                    }
                  },
                  tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                  icon: const Icon(CoolIcons.back),
                ),
                title: Text(
                  l10n.navGroups,
                  style: textTheme.headline(
                    Theme.of(context).textTheme.titleLarge,
                    fontWeight: FontWeight.w600,
                  ),
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
                    vertical: space.x2,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CoolChipBar(
                        items: [
                          CoolChipItem(
                            label: l10n.groupsMyLedgers,
                            isActive: _showMine,
                            onTap: () => setState(() => _showMine = true),
                          ),
                          CoolChipItem(
                            label: l10n.groupsExplore,
                            isActive: !_showMine,
                            onTap: () => setState(() => _showMine = false),
                          ),
                        ],
                      ),
                      if (!_showMine) ...[
                        SizedBox(height: space.x3),
                        CoolSearchField(
                          hint: l10n.searchGroups,
                          onChanged: (value) {
                            // PF-03: Debounce search input to avoid
                            // hammering Supabase on every keystroke.
                            _searchDebounce?.cancel();
                            _searchDebounce = Timer(
                              const Duration(milliseconds: 400),
                              () {
                                if (mounted) {
                                  setState(() => _publicSearch = value.trim());
                                }
                              },
                            );
                          },
                        ),
                      ],
                      if (invitePreviewAsync != null) ...[
                        SizedBox(height: space.x3),
                        invitePreviewAsync.when(
                          data: (preview) {
                            if (preview == null) {
                              return _InviteBanner(
                                title: l10n.groupsInviteNotFoundTitle,
                                subtitle: l10n.groupsInviteNotFoundMessage,
                                actionLabel: l10n.groupsDismissUpper,
                                onAction: _dismissInviteBanner,
                                onDismiss: _dismissInviteBanner,
                              );
                            }
                            return _InviteBanner(
                              title: preview.group.name,
                              subtitle: preview.isMember
                                  ? l10n.groupsAlreadyMember
                                  : l10n.memberCount(preview.group.memberCount),
                              actionLabel: l10n.groupsOpenUpper,
                              onAction: () {
                                if (preview.isMember) {
                                  _openGroup(preview.group);
                                  return;
                                }
                                _openInvitedGroupPreview(
                                  preview.group,
                                  inviteCode!,
                                );
                              },
                              onDismiss: _dismissInviteBanner,
                              isLoading: _isJoining,
                            );
                          },
                          loading: () => const _InviteBannerLoading(),
                          error: (error, _) => _InviteBanner(
                            title: l10n.groupsInviteErrorTitle,
                            subtitle: describeUserFacingError(error),
                            actionLabel: l10n.groupsDismissUpper,
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
                            ? l10n.groupsNoGroupsYetTitle
                            : l10n.groupsEmptyPublicTitle,
                        message: _showMine
                            ? l10n.groupsNoGroupsYetMessage
                            : l10n.groupsEmptyPublicMessage,
                        actionLabel: _showMine
                            ? l10n.groupCreateGroupUpper
                            : null,
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
                            onInvite: isMember
                                ? () => _inviteMembers(group)
                                : null,
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
                loading: () => SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: space.x4),
                  sliver: SliverList.list(
                    children: List.generate(
                      3,
                      (i) => Padding(
                        padding: EdgeInsets.only(bottom: space.x3),
                        child: const CoolSkeleton.card(),
                      ),
                    ),
                  ),
                ),
                error: (error, _) => SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.all(space.x4),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            CoolIcons.cloudOff,
                            size: 40,
                            color: colors.tertiaryText,
                          ),
                          SizedBox(height: space.x3),
                          Text(
                            describeUserFacingError(error),
                            textAlign: TextAlign.center,
                            style: textTheme.mobiLabel(
                              color: colors.secondaryText,
                            ),
                          ),
                          SizedBox(height: space.x4),
                          SizedBox(
                            width: 220,
                            child: CoolButton(
                              label: l10n.groupsTapToRetry,
                              onTap: _refreshGroups,
                              variant: CoolButtonVariant.secondary,
                            ),
                          ),
                        ],
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
