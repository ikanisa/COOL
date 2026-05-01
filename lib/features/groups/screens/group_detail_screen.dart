import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/country_catalog.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../core/utils/money_formatters.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_expandable_section.dart';

import '../../../shared/widgets/cool_metric_row.dart';
import '../../../shared/widgets/cool_section_card.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../../../shared/widgets/core_detail_scaffold.dart';
import '../../../shared/widgets/member_row.dart';
import '../../../shared/widgets/share_card.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../../core/utils/user_error.dart';
import 'group_detail_widgets.dart';
import '../../auth/providers/auth_provider.dart';
import '../../auth/widgets/require_verified_user.dart';
import '../../momo/models/momo_statement.dart';
import '../../momo/providers/momo_statement_providers.dart';
import '../../profile/services/momo_setup_guard.dart';
import '../group_flow_utils.dart';
import '../models/group.dart';
import '../models/group_member_preview.dart';
import '../providers/groups_provider.dart';

part 'group_detail_screen_parts.dart';

class GroupDetailScreen extends ConsumerStatefulWidget {
  const GroupDetailScreen({required this.groupId, this.inviteCode, super.key});

  final String groupId;
  final String? inviteCode;

  @override
  ConsumerState<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends ConsumerState<GroupDetailScreen> {
  bool _isJoining = false;

  Future<void> _joinGroup(Group group) async {
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

    final user = ref.read(authProvider).user;
    if (user == null) {
      return;
    }

    setState(() => _isJoining = true);
    try {
      final repository = ref.read(groupRepositoryProvider);
      final result =
          group.visibility == 'private' &&
              (widget.inviteCode?.trim().isNotEmpty ?? false)
          ? await repository.joinGroupViaInvite(widget.inviteCode!.trim())
          : await repository.joinPublicGroup(group: group, user: user);
      ref.read(groupsRefreshTickProvider.notifier).state++;
      // Invalidate detail + access so the screen refreshes immediately.
      ref.invalidate(groupDetailProvider(widget.groupId));
      ref.invalidate(groupAccessProvider(widget.groupId));
      if (widget.inviteCode?.trim().isNotEmpty ?? false) {
        ref.invalidate(groupInvitePreviewProvider(widget.inviteCode!.trim()));
      }
      if (!mounted) {
        return;
      }
      CoolToast.success(
        context,
        result.isAlreadyMember
            ? context.l10n.alreadyMemberOf(group.name)
            : context.l10n.youJoinedGroup(group.name),
      );
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

  Future<void> _contributeToGroup(Group group) async {
    if (!groupHasContributionRoute(group)) {
      CoolToast.info(context, context.l10n.groupsPaymentRoutePendingInfo);
      return;
    }

    final launched = await launchGroupContribution(context, group: group);
    if (!launched && mounted) {
      CoolToast.error(context, context.l10n.groupsLaunchMomoUssdError);
    }
  }

  @override
  Widget build(BuildContext context) {
    final groupAsync = ref.watch(groupDetailProvider(widget.groupId));
    final accessAsync = ref.watch(groupAccessProvider(widget.groupId));
    final myGroupIds = ref.watch(myGroupIdsProvider);
    final normalizedInviteCode = widget.inviteCode?.trim();
    final invitePreviewAsync =
        normalizedInviteCode == null || normalizedInviteCode.isEmpty
        ? const AsyncData(null)
        : ref.watch(groupInvitePreviewProvider(normalizedInviteCode));

    // Guard against empty groupId propagated from route parameters.
    if (widget.groupId.trim().isEmpty) {
      return MissingGroupState(message: context.l10n.groupNotFound);
    }

    final invitePreview = invitePreviewAsync.valueOrNull;
    final inviteGroup = invitePreview?.group;
    final resolvedGroup =
        groupAsync.valueOrNull ??
        ((inviteGroup?.id?.trim() ?? '') == widget.groupId.trim()
            ? inviteGroup
            : null);
    final access = accessAsync.valueOrNull;
    final isPreviewOnly =
        groupAsync.valueOrNull == null && resolvedGroup != null;

    if (groupAsync.isLoading && resolvedGroup == null) {
      return const CoreDetailScaffold(
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (groupAsync.hasError && resolvedGroup == null) {
      return MissingGroupState(
        message: describeUserFacingError(groupAsync.error!),
      );
    }

    if (resolvedGroup == null) {
      return MissingGroupState(message: context.l10n.groupNotFound);
    }

    final groupId = resolvedGroup.id;
    if (groupId == null || groupId.trim().isEmpty) {
      return MissingGroupState(message: context.l10n.groupNotFound);
    }

    final isMember = access?.isMember ?? myGroupIds.contains(groupId);
    final canManageSettings = access?.canManageSettings ?? false;
    final canViewTransactions = access?.canViewTransactions ?? false;
    final canViewMemberPreview =
        resolvedGroup.visibility == 'public' || access != null;
    final memberPreviewAsync = canViewMemberPreview
        ? ref.watch(groupMemberPreviewProvider(widget.groupId))
        : const AsyncData(<GroupMemberPreview>[]);
    final ledgerAsync = canViewTransactions
        ? ref.watch(
            groupTransactionFeedProvider(
              GroupPaymentLedgerQuery(
                groupId: groupId,
                statementQuery: const MomoStatementQuery(limit: 10),
              ),
            ),
          )
        : const AsyncData(MomoStatementPage<PayeePaymentLedgerEntry>());
    final inviteUrl = buildGroupInviteUrl(resolvedGroup);

    return _GroupDetailBody(
      group: resolvedGroup,
      isMember: isMember,
      isJoining: _isJoining,
      inviteUrl: inviteUrl,
      ledgerAsync: ledgerAsync,
      memberPreviewAsync: memberPreviewAsync,
      canManageSettings: canManageSettings,
      canViewTransactions: canViewTransactions,
      canViewMemberPreview: canViewMemberPreview,
      isPreviewOnly: isPreviewOnly,
      onBack: () {
        if (context.canPop()) {
          context.pop();
          return;
        }
        context.go(AppRoutes.groups);
      },
      onJoin: isMember ? null : () => _joinGroup(resolvedGroup),
      onOpenSettings: canManageSettings
          ? () => context.push(AppRoutes.groupSettingsLocation(groupId))
          : null,
      onContribute: isMember ? () => _contributeToGroup(resolvedGroup) : null,
    );
  }
}
