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
    final canQuickContribute = groupHasContributionRoute(group);

    return SizedBox(
      width: 290,
      child: GestureDetector(
        onTap: onOpen,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(36),
          child: DecoratedBox(
            decoration: BoxDecoration(
              // Claymorphic surface: layered dark gradient with soft tint
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[
                  Color(0xFF181C26),
                  HomeVisualPalette.surface,
                  Color(0xFF101420),
                ],
                stops: <double>[0.0, 0.55, 1.0],
              ),
              borderRadius: BorderRadius.circular(36),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.16),
                width: 1.0,
              ),
              boxShadow: CoolShadows.claymorphicCard(
                glowColor: HomeVisualPalette.active,
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
                        top: Radius.circular(36),
                      ),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: <Color>[
                          Colors.white.withValues(alpha: 0.10),
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
                              color: HomeVisualPalette.active.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(CoolRadii.md),
                              border: Border.all(
                                color: HomeVisualPalette.active.withValues(alpha: 0.20),
                              ),
                            ),
                            alignment: Alignment.center,
                            child: const Icon(
                              Icons.groups_2_outlined,
                              color: HomeVisualPalette.active,
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: CoolSpace.x3,
                              vertical: CoolSpace.x2,
                            ),
                            decoration: BoxDecoration(
                              color: HomeVisualPalette.active.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(CoolRadii.pill),
                              border: Border.all(
                                color: HomeVisualPalette.active.withValues(alpha: 0.18),
                              ),
                            ),
                            child: Text(
                              memberCountLabel(group.memberCount),
                              style: context.coolText.mono(
                                theme.textTheme.labelSmall,
                                color: HomeVisualPalette.active,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.6,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      // Space Grotesk — group names get headline authority
                      Text(
                        group.name.trim().isEmpty ? 'Community' : group.name.trim(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: context.coolText.headline(
                          theme.textTheme.headlineSmall,
                          color: HomeVisualPalette.textPrimary,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.7,
                          height: 1.0,
                        ),
                      ),
                      const SizedBox(height: CoolSpace.x5),
                      Text(
                        'TOTAL',
                        style: context.coolText.mono(
                          theme.textTheme.labelSmall,
                          color: HomeVisualPalette.textSecondary,
                          fontWeight: FontWeight.w800,
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
                                color: HomeVisualPalette.textPrimary,
                                fontWeight: FontWeight.w900,
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
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(CoolRadii.pill),
        child: Ink(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            shape: BoxShape.circle,
            border: Border.all(color: HomeVisualPalette.outlineStrong),
          ),
          child: Icon(icon, color: HomeVisualPalette.textPrimary, size: 24),
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
  final location = groupHasContributionRoute(group)
      ? buildGroupContributionLocation(group)
      : AppRoutes.contributionCircles;
  openQuickActionRoute(context, location);
}
