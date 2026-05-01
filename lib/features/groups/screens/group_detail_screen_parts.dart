part of 'group_detail_screen.dart';

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
                      GroupStatementsButton(groupId: group.id ?? ''),
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
                      GroupLedgerTile(
                        entry: entry,
                        canManageAllocations: canManageSettings,
                        groupId: group.id ?? '',
                      ),
                    SizedBox(height: space.x2),
                    GroupStatementsButton(groupId: group.id ?? ''),
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
                  GroupStatementsButton(groupId: group.id ?? ''),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
