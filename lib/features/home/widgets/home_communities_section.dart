part of 'home_sections.dart';

class HomeCommunitiesSection extends StatelessWidget {
  const HomeCommunitiesSection({
    required this.groups,
    required this.isLoading,
    required this.error,
    required this.onViewAll,
    required this.onOpenGroup,
    required this.onQuickContribution,
    super.key,
  });

  final List<Group> groups;
  final bool isLoading;
  final Object? error;
  final VoidCallback onViewAll;
  final ValueChanged<Group> onOpenGroup;
  final ValueChanged<Group> onQuickContribution;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final content = _buildContent(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HomeSectionHeader(
          title: l10n.homeCommunitiesTitle,
          trailing: HomeSectionActionPill(
            label: l10n.viewAll,
            onTap: onViewAll,
          ),
        ),
        const SizedBox(height: CoolSpace.x3),
        content,
      ],
    );
  }

  Widget _buildContent(BuildContext context) {
    if (isLoading && groups.isEmpty) {
      return Column(
        children: [
          CoolListTile.skeleton(),
          const SizedBox(height: CoolSpace.x2),
          CoolListTile.skeleton(),
          const SizedBox(height: CoolSpace.x2),
          CoolListTile.skeleton(),
        ],
      );
    }

    if (error != null && groups.isEmpty) {
      return CoolErrorView(
        compact: true,
        subtitle: context.l10n.homeCommunitiesLoadFailed,
      );
    }

    if (groups.isEmpty) {
      return CoolEmptyView(
        compact: true,
        title: context.l10n.homeNoCommunitiesYet,
        subtitle: context.l10n.homeCommunitiesEmptySubtitle,
        icon: CoolIcons.groupsOutlined,
      );
    }

    return Column(
      children: [
        for (final (index, group) in groups.take(3).indexed) ...[
          _CommunityCard(
            group: group,
            onOpen: () => onOpenGroup(group),
            onQuickContribution: () => onQuickContribution(group),
          ),
          if (index < groups.take(3).length - 1)
            const SizedBox(height: CoolSpace.x2),
        ],
      ],
    );
  }
}

class _CommunityCard extends StatelessWidget {
  const _CommunityCard({
    required this.group,
    required this.onOpen,
    required this.onQuickContribution,
  });

  final Group group;
  final VoidCallback onOpen;
  final VoidCallback onQuickContribution;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final canQuickContribute = groupHasContributionRoute(group);

    return CoolCard(
      onTap: onOpen,
      cardPadding: CoolCardPadding.md,
      child: Row(
        children: [
          CoolIconBox(
            icon: CoolIcons.groups,
            accent: colors.accent,
          ),
          const SizedBox(width: CoolSpace.x4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  group.name.trim().isEmpty
                      ? context.l10n.homeCommunityFallbackName
                      : group.name.trim(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.coolText.headline(
                    Theme.of(context).textTheme.titleSmall,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  memberCountLabel(context, group.memberCount),
                  style: context.coolText
                      .mobiLabel(color: colors.secondaryText)
                      .copyWith(fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
          const SizedBox(width: CoolSpace.x3),
          Text(
            '${fmtAmt(group.amount)} RWF',
            style: context.coolText.display(
              Theme.of(context).textTheme.titleMedium,
              color: colors.primaryText,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: CoolSpace.x2),
          _CircleActionButton(
            icon: canQuickContribute
                ? CoolIcons.add
                : CoolIcons.forward,
            onTap: () {
              HapticFeedback.selectionClick();
              onQuickContribution();
            },
          ),
        ],
      ),
    );
  }
}

class _CircleActionButton extends StatelessWidget {
  const _CircleActionButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(CoolRadii.pill),
        child: Ink(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: colors.cardSurfaceStrong,
            shape: BoxShape.circle,
            border: Border.all(color: colors.border),
          ),
          child: Icon(icon, color: colors.primaryText, size: 18),
        ),
      ),
    );
  }
}

void openCommunityGroup(BuildContext context, Group group) {
  final groupId = group.id?.trim() ?? '';
  if (groupId.isEmpty) {
    context.push(AppRoutes.contributionCircles);
    return;
  }

  context.push(AppRoutes.contributionCircleDetailLocation(groupId));
}

void openCommunityContribution(BuildContext context, Group group) {
  if (!groupHasContributionRoute(group)) {
    openCommunityGroup(context, group);
    return;
  }
  launchGroupContribution(context, group: group);
}
