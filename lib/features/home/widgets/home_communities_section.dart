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
    final canQuickContribute = groupHasContributionRoute(group);
    final tone = _CommunityCardTone.resolve(group);
    final theme = Theme.of(context);
    final title = group.name.trim().isEmpty
        ? context.l10n.homeCommunityFallbackName
        : group.name.trim();
    final typeLabel = group.type == 'saving'
        ? context.l10n.saving.toUpperCase()
        : context.l10n.community.toUpperCase();
    final visibilityLabel = group.visibility == 'private'
        ? context.l10n.private.toUpperCase()
        : context.l10n.public.toUpperCase();
    final amountLabel = '${fmtAmt(group.amount)} RWF';
    final subtitle = _subtitle;

    return Semantics(
      button: true,
      label:
          '$title. $typeLabel. $visibilityLabel. $amountLabel. ${memberCountLabel(context, group.memberCount)}.',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onOpen,
              borderRadius: BorderRadius.circular(30),
              splashColor: Colors.white.withValues(alpha: 0.10),
              highlightColor: Colors.transparent,
              child: Ink(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [tone.start, tone.middle, tone.end],
                    stops: const [0.0, 0.58, 1.0],
                  ),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: tone.border),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.white.withValues(alpha: 0.58),
                      blurRadius: 10,
                      offset: const Offset(-4, -4),
                    ),
                    BoxShadow(
                      color: tone.shadow.withValues(alpha: 0.18),
                      blurRadius: 26,
                      offset: const Offset(0, 16),
                    ),
                  ],
                ),
                child: SizedBox(
                  height: 242,
                  child: Stack(
                    children: [
                      Positioned(
                        top: -28,
                        right: -24,
                        child: _CommunityBackdropGlow(
                          size: 144,
                          color: Colors.white.withValues(alpha: 0.22),
                        ),
                      ),
                      Positioned(
                        bottom: -42,
                        left: -24,
                        child: _CommunityBackdropGlow(
                          size: 132,
                          color: tone.highlight.withValues(alpha: 0.28),
                        ),
                      ),
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.white.withValues(alpha: 0.32),
                                Colors.white.withValues(alpha: 0.12),
                                Colors.transparent,
                              ],
                              stops: const [0.0, 0.28, 0.84],
                            ),
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _CommunitySoftBadge(
                                  tone: tone,
                                  icon: group.type == 'saving'
                                      ? CoolIcons.savings
                                      : CoolIcons.groupsFilled,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      _CommunityIconPill(
                                        icon: group.type == 'saving'
                                            ? CoolIcons.trendUp
                                            : CoolIcons.groupsFilled,
                                        tone: tone,
                                        semanticLabel: typeLabel,
                                      ),
                                      const SizedBox(width: 8),
                                      _CommunityIconPill(
                                        icon: group.visibility == 'private'
                                            ? CoolIcons.lock
                                            : CoolIcons.shieldOutline,
                                        tone: tone,
                                        semanticLabel: visibilityLabel,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    maxLines: subtitle == null ? 3 : 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: context.coolText.headline(
                                      theme.textTheme.titleLarge,
                                      color: tone.textPrimary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  if (subtitle != null) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      subtitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            color: tone.textSecondary,
                                            height: 1.2,
                                            fontWeight: FontWeight.w500,
                                          ),
                                    ),
                                  ],
                                  const Spacer(),
                                  _CommunityInfoPanel(
                                    tone: tone,
                                    amountLabel: amountLabel,
                                    amountStyle: context.coolText.display(
                                      theme.textTheme.titleLarge,
                                      color: tone.textPrimary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                    canQuickContribute: canQuickContribute,
                                    group: group,
                                    onQuickContribution: onQuickContribution,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String? get _subtitle {
    final trimmedDescription = group.description?.trim() ?? '';
    if (trimmedDescription.isNotEmpty) {
      return trimmedDescription;
    }
    return null;
  }
}

void openCommunityGroup(BuildContext context, Group group) {
  final groupId = group.id?.trim() ?? '';
  if (groupId.isEmpty) {
    context.push(AppRoutes.groups);
    return;
  }

  context.push(AppRoutes.groupDetailLocation(groupId));
}

void openCommunityContribution(
  BuildContext context,
  Group group, {
  Set<String> memberGroupIds = const <String>{},
}) {
  final groupId = group.id?.trim() ?? '';
  final isMember = groupId.isNotEmpty && memberGroupIds.contains(groupId);
  if (group.type == 'saving' && !isMember) {
    openCommunityGroup(context, group);
    return;
  }
  if (!groupHasContributionRoute(group)) {
    openCommunityGroup(context, group);
    return;
  }
  launchGroupContribution(context, group: group);
}
