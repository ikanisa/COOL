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
import '../../../shared/widgets/cool_icon_box.dart';

import '../../../shared/widgets/cool_metric_row.dart';
import '../../../shared/widgets/cool_section_card.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../../../shared/widgets/core_detail_scaffold.dart';
import '../../../shared/widgets/member_row.dart';
import '../../../shared/widgets/share_card.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../../shared/widgets/transaction_status_chip.dart';
import '../../../core/utils/user_error.dart';
import '../../auth/providers/auth_provider.dart';
import '../../auth/widgets/require_verified_user.dart';
import '../../momo/models/momo_statement.dart';
import '../../momo/providers/momo_statement_providers.dart';
import '../../profile/services/momo_setup_guard.dart';
import '../group_flow_utils.dart';
import '../models/group.dart';
import '../models/group_member_preview.dart';
import '../providers/groups_provider.dart';
import '../widgets/transaction_allocation_sheet.dart';

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
      return _MissingGroupState(message: context.l10n.groupNotFound);
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
      return _MissingGroupState(
        message: describeUserFacingError(groupAsync.error!),
      );
    }

    if (resolvedGroup == null) {
      return _MissingGroupState(message: context.l10n.groupNotFound);
    }

    final groupId = resolvedGroup.id;
    if (groupId == null || groupId.trim().isEmpty) {
      return _MissingGroupState(message: context.l10n.groupNotFound);
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

class _GroupDetailBody extends StatelessWidget {
  const _GroupDetailBody({
    required this.group,
    required this.isMember,
    required this.isJoining,
    required this.inviteUrl,
    required this.ledgerAsync,
    required this.memberPreviewAsync,
    required this.canManageSettings,
    required this.canViewTransactions,
    required this.canViewMemberPreview,
    required this.isPreviewOnly,
    required this.onBack,
    required this.onJoin,
    required this.onOpenSettings,
    required this.onContribute,
  });

  final Group group;
  final bool isMember;
  final bool isJoining;
  final String? inviteUrl;
  final AsyncValue<MomoStatementPage<PayeePaymentLedgerEntry>> ledgerAsync;
  final AsyncValue<List<GroupMemberPreview>> memberPreviewAsync;
  final bool canManageSettings;
  final bool canViewTransactions;
  final bool canViewMemberPreview;
  final bool isPreviewOnly;
  final VoidCallback onBack;
  final VoidCallback? onJoin;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onContribute;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final text = context.coolText;
    final space = context.coolSpace;
    final currency = CoolCountryCatalog.resolve(
      country: group.country,
    ).currencyCode;
    final routeReady = groupHasContributionRoute(group);

    return CoreDetailScaffold(
      onBack: onBack,
      title: Text(
        group.name,
        style: text.displayCondensed(
          theme.textTheme.headlineSmall,
          fontWeight: FontWeight.w800,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Compact meta — type + member count only (visibility is redundant)
          Row(
            children: [
              StatusBadge(
                label: group.type == 'community'
                    ? context.l10n.community.toUpperCase()
                    : context.l10n.saving.toUpperCase(),
              ),
              SizedBox(width: space.x2),
              StatusBadge(label: '${group.memberCount}', emoji: '👥'),
            ],
          ),
          if ((group.description ?? '').trim().isNotEmpty) ...[
            SizedBox(height: space.x2),
            CoolExpandableSection(
              header: context.l10n.groupDescriptionHeader,
              initiallyExpanded: (group.description ?? '').trim().length < 80,
              child: Text(
                group.description!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.secondaryText,
                ),
              ),
            ),
          ],
        ],
      ),
      actions: canManageSettings
          ? <Widget>[
              IconButton(
                onPressed: onOpenSettings,
                icon: const Icon(CoolIcons.settings),
              ),
              const SizedBox(width: CoolSpace.x2),
            ]
          : null,
      child: ListView(
        padding: const EdgeInsets.only(bottom: CoolSpace.x7),
        children: [
          // ── Stats card — compact metrics ──────────────────────
          CoolSectionCard(
            children: [
              if (isPreviewOnly)
                const CoolMetricRow.mono(
                  label: 'Access',
                  value: 'INVITE PREVIEW',
                ),
              CoolMetricRow.mono(
                label: context.l10n.balance,
                value: '${formatWholeMoneyAmount(group.amount)} $currency',
              ),
              if (group.targetAmount > 0)
                CoolMetricRow.mono(
                  label: context.l10n.target,
                  value:
                      '${formatWholeMoneyAmount(group.targetAmount)} $currency',
                ),
              if ((group.monthlyContribution ?? 0) > 0)
                CoolMetricRow.mono(
                  label: context.l10n.contribution,
                  value:
                      '${formatWholeMoneyAmount(group.monthlyContribution ?? 0)} $currency',
                ),
            ],
          ),

          if (canViewMemberPreview && group.memberCount > 0) ...[
            SizedBox(height: space.x5),
            Text(
              context.l10n.membersPreview,
              style: text.display(
                theme.textTheme.titleLarge,
                color: colors.primaryText,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: space.x3),
            memberPreviewAsync.when(
              data: (members) {
                if (members.isEmpty) {
                  return CoolCard(
                    backgroundColor: colors.cardSurfaceStrong,
                    borderRadius: CoolRadii.xl,
                    child: Text(
                      context.l10n.groupsNoMembersYet,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.secondaryText,
                      ),
                    ),
                  );
                }

                return CoolSectionCard(
                  children: [
                    for (final member in members)
                      MemberRow(
                        userId: '',
                        displayName: member.displayName,
                        isAdmin: member.isAdmin,
                        isAnonymous: member.isAnonymous,
                        showContribution: false,
                      ),
                  ],
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => CoolCard(
                backgroundColor: colors.cardSurfaceStrong,
                borderRadius: CoolRadii.xl,
                child: Text(
                  context.l10n.groupsCouldNotLoadMembers,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.secondaryText,
                  ),
                ),
              ),
            ),
          ],

          SizedBox(height: space.x5),

          // ── CTA ──────────────────────────────────────────────
          if (isMember) ...[
            CoolButton(
              label: routeReady
                  ? context.l10n.groupsContributeWithMomoUpper
                  : context.l10n.groupsContributionRoutePendingUpper,
              onTap: routeReady ? onContribute : null,
              variant: routeReady
                  ? CoolButtonVariant.accent
                  : CoolButtonVariant.secondary,
            ),
            if (!routeReady) ...[
              SizedBox(height: space.x2),
              Text(
                context.l10n.groupsRoutePendingHint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.secondaryText,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            // B3: iOS manual verification notice
            if (routeReady && defaultTargetPlatform == TargetPlatform.iOS) ...[
              SizedBox(height: space.x3),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(CoolSpace.x4),
                decoration: BoxDecoration(
                  color: colors.info.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(CoolRadii.md),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(CoolIcons.info, size: 16, color: colors.info),
                        const SizedBox(width: CoolSpace.x2),
                        Expanded(
                          child: Text(
                            context.l10n.iosPaymentNoticeTitle,
                            style: context.coolText.headline(
                              theme.textTheme.labelMedium,
                              fontWeight: FontWeight.w700,
                              color: colors.info,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: CoolSpace.x2),
                    Text(
                      context.l10n.iosPaymentNoticeMessage,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ] else if (group.visibility == 'public')
            CoolButton(
              label: context.l10n.groupsJoinGroupUpper,
              onTap: isJoining ? null : onJoin,
              isLoading: isJoining,
            )
          else
            CoolCard(
              backgroundColor: colors.cardSurfaceStrong,
              borderRadius: CoolRadii.xl,
              child: Text(
                context.l10n.groupsInviteOnlyMessage,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.secondaryText,
                ),
              ),
            ),

          // ── Share card ───────────────────────────────────────
          if (inviteUrl != null && isMember) ...[
            SizedBox(height: space.x5),
            ShareCard(
              title: context.l10n.inviteToGroup(group.name),
              subtitle: context.l10n.groupsInviteShareSubtitle,
              shareUrl: inviteUrl!,
              shareText: context.l10n.joinGroupShareText(
                group.name,
                inviteUrl!,
              ),
              analyticsTargetType: 'group_invite',
            ),
          ],

          // ── Ledger section ───────────────────────────────────
          if (canViewTransactions) ...[
            SizedBox(height: space.x5),
            Text(
              context.l10n.ledgerTitle,
              style: text.display(
                theme.textTheme.titleLarge,
                color: colors.primaryText,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: space.x3),
            ledgerAsync.when(
              data: (page) {
                if (page.entries.isEmpty) {
                  return Column(
                    children: [
                      CoolCard(
                        backgroundColor: colors.cardSurfaceStrong,
                        borderRadius: CoolRadii.xl,
                        child: Text(
                          context.l10n.groupsNoPostedContributionsYet,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colors.secondaryText,
                          ),
                        ),
                      ),
                      SizedBox(height: space.x3),
                      _StatementsButton(groupId: group.id ?? ''),
                    ],
                  );
                }

                return CoolSectionCard(
                  cardPadding: const EdgeInsets.symmetric(
                    horizontal: CoolSpace.x4,
                    vertical: CoolSpace.x2,
                  ),
                  children: [
                    for (final entry in page.entries)
                      _LedgerTile(
                        entry: entry,
                        canManageAllocations: canManageSettings,
                        groupId: group.id ?? '',
                      ),
                    SizedBox(height: space.x2),
                    _StatementsButton(groupId: group.id ?? ''),
                  ],
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Column(
                children: [
                  CoolCard(
                    backgroundColor: colors.cardSurfaceStrong,
                    borderRadius: CoolRadii.xl,
                    child: Text(
                      context.l10n.groupsCouldNotLoadLedger,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.secondaryText,
                      ),
                    ),
                  ),
                  SizedBox(height: space.x3),
                  _StatementsButton(groupId: group.id ?? ''),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatementsButton extends StatelessWidget {
  const _StatementsButton({required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: CoolButton(
        label: context.l10n.groupsViewAllStatementsUpper,
        onTap: () => context.push(AppRoutes.groupStatementsLocation(groupId)),
        variant: CoolButtonVariant.secondary,
      ),
    );
  }
}

/// Ledger tile — clean icon-led row with amount + status.
class _LedgerTile extends StatelessWidget {
  const _LedgerTile({
    required this.entry,
    this.canManageAllocations = false,
    this.groupId = '',
  });

  final PayeePaymentLedgerEntry entry;
  final bool canManageAllocations;
  final String groupId;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final isAllocated = entry.payerUserId.trim().isNotEmpty;
    final statusLabel = isAllocated ? 'confirmed' : 'pending_review';

    return CoolCard(
      cardPadding: CoolCardPadding.md,
      onTap: canManageAllocations
          ? () => TransactionAllocationSheet.show(
              context,
              entry: entry,
              groupId: groupId,
            )
          : null,
      child: Row(
        children: [
          const CoolIconBox(icon: CoolIcons.payment),
          const SizedBox(width: CoolSpace.x4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  entry.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.headline(
                    Theme.of(context).textTheme.titleSmall,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${entry.payerName} • ${entry.occurredAt.toLocal().toString().split('.').first}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text
                      .mobiLabel(color: colors.secondaryText)
                      .copyWith(fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
          const SizedBox(width: CoolSpace.x3),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${formatWholeMoneyAmount(entry.amount)} ${entry.currency}',
                style: text.mono(null, color: colors.accentGold),
              ),
              const SizedBox(height: 4),
              TransactionStatusChip(status: statusLabel),
            ],
          ),
        ],
      ),
    );
  }
}

class _MissingGroupState extends StatelessWidget {
  const _MissingGroupState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    return CoreDetailScaffold(
      onBack: () {
        if (context.canPop()) {
          context.pop();
          return;
        }
        context.go(AppRoutes.groups);
      },
      title: Text(
        context.l10n.groupDetailTitle,
        style: context.coolText.displayCondensed(
          Theme.of(context).textTheme.headlineSmall,
          fontWeight: FontWeight.w800,
        ),
      ),
      child: Center(
        child: CoolCard(
          borderRadius: CoolRadii.xl,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: CoolSpace.x2),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CoolIconBox(
                  icon: CoolIcons.groupOff,
                  size: CoolIconBoxSize.lg,
                  variant: CoolIconBoxVariant.solid,
                ),
                const SizedBox(height: CoolSpace.x5),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.secondaryText,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: CoolSpace.x6),
                CoolButton(
                  label: context.l10n.goBack,
                  variant: CoolButtonVariant.secondary,
                  onTap: () {
                    if (context.canPop()) {
                      context.pop();
                      return;
                    }
                    context.go(AppRoutes.groups);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
