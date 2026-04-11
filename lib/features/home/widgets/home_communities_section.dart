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
    final content = _buildContent(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HomeSectionHeader(
          title: 'Communities',
          trailing: HomeSectionActionPill(label: 'VIEW ALL', onTap: onViewAll),
        ),
        const SizedBox(height: CoolSpace.x4),
        content,
      ],
    );
  }

  Widget _buildContent(BuildContext context) {
    if (isLoading && groups.isEmpty) {
      return const CoolSkeletonRow(itemCount: 2, spacing: CoolSpace.x4);
    }

    if (error != null && groups.isEmpty) {
      return const SizedBox(
        height: 216,
        child: CoolErrorView(
          compact: true,
          subtitle: 'Communities failed to load.',
        ),
      );
    }

    if (groups.isEmpty) {
      return const SizedBox(
        height: 216,
        child: CoolEmptyView(
          compact: true,
          title: 'No communities yet',
          subtitle: 'Your savings circles will appear here.',
          icon: Icons.groups_outlined,
        ),
      );
    }

    return SizedBox(
      height: 230,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        clipBehavior: Clip.none,
        itemCount: groups.length > 8 ? 8 : groups.length,
        separatorBuilder: (_, index) => const SizedBox(width: CoolSpace.x4),
        itemBuilder: (context, index) {
          final group = groups[index];
          return _CommunityCard(
            group: group,
            onOpen: () => onOpenGroup(group),
            onQuickContribution: () => onQuickContribution(group),
          );
        },
      ),
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
    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;
    final canQuickContribute = groupHasContributionRoute(group);

    return SizedBox(
      width: 290,
      child: GestureDetector(
        onTap: onOpen,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(CoolRadii.xl),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[
                  colors.cardSurface,
                  colors.elevatedBackground,
                  colors.appBackground,
                ],
                stops: const <double>[0.0, 0.55, 1.0],
              ),
              borderRadius: BorderRadius.circular(CoolRadii.xl),
              boxShadow: CoolShadows.claymorphicCard(
                glowColor: colors.accent,
                strength: 0.9,
              ),
            ),
            child: Stack(
              children: [
                // Inner top-edge highlight
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: 56,
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(CoolRadii.xl),
                      ),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: <Color>[
                          colors.highlightColor,
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(CoolSpace.x6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              color: colors.accent.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(CoolRadii.md),
                            ),
                            alignment: Alignment.center,
                            child: Icon(
                              Icons.groups_2_outlined,
                              color: colors.accent,
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: CoolSpace.x3,
                              vertical: CoolSpace.x2,
                            ),
                            decoration: BoxDecoration(
                              color: colors.accent.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(CoolRadii.pill),
                            ),
                            child: Text(
                              memberCountLabel(group.memberCount),
                              style: context.coolText.mono(
                                theme.textTheme.labelSmall,
                                color: colors.accent,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.6,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      Text(
                        group.name.trim().isEmpty ? 'Community' : group.name.trim(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: context.coolText.headline(
                          theme.textTheme.headlineSmall,
                          color: colors.primaryText,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.7,
                          height: 1.0,
                        ),
                      ),
                      const SizedBox(height: CoolSpace.x5),
                      Text(
                        'TOTAL',
                        style: context.coolText.mono(
                          theme.textTheme.labelSmall,
                          color: colors.secondaryText,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.9,
                        ),
                      ),
                      const SizedBox(height: CoolSpace.x2),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${fmtAmt(group.amount)} RWF',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.coolText.display(
                                theme.textTheme.titleLarge,
                                color: colors.primaryText,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.8,
                              ),
                            ),
                          ),
                          const SizedBox(width: CoolSpace.x3),
                          _CircleActionButton(
                            icon: canQuickContribute
                                ? Icons.add_rounded
                                : Icons.arrow_forward_rounded,
                            onTap: () {
                              HapticFeedback.selectionClick();
                              onQuickContribution();
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
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
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            color: colors.cardSurfaceStrong,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: colors.primaryText, size: 24),
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
