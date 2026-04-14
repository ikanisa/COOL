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

class _CircleActionButton extends StatelessWidget {
  const _CircleActionButton({
    required this.icon,
    required this.onTap,
    required this.tone,
  });

  final IconData icon;
  final VoidCallback onTap;
  final _CommunityCardTone tone;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(CoolRadii.pill),
        child: Ink(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [tone.actionStart, tone.actionEnd],
            ),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: 0.44)),
            boxShadow: [
              BoxShadow(
                color: Colors.white.withValues(alpha: 0.36),
                blurRadius: 10,
                offset: const Offset(-4, -4),
              ),
              BoxShadow(
                color: tone.shadow.withValues(alpha: 0.22),
                blurRadius: 20,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}

class _CommunityIconPill extends StatelessWidget {
  const _CommunityIconPill({
    required this.icon,
    required this.tone,
    required this.semanticLabel,
  });

  final IconData icon;
  final _CommunityCardTone tone;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.34),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.42)),
          boxShadow: [
            BoxShadow(
              color: Colors.white.withValues(alpha: 0.22),
              blurRadius: 6,
              offset: const Offset(-2, -2),
            ),
            BoxShadow(
              color: tone.shadow.withValues(alpha: 0.08),
              blurRadius: 10,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: 16, color: tone.textPrimary),
      ),
    );
  }
}

class _CommunityMetricChip extends StatelessWidget {
  const _CommunityMetricChip({
    required this.icon,
    required this.value,
    required this.semanticLabel,
    required this.tone,
  });

  final IconData icon;
  final String value;
  final String semanticLabel;
  final _CommunityCardTone tone;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.26),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.36)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: tone.actionStart),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: tone.textPrimary,
                  fontWeight: FontWeight.w700,
                  height: 1.0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommunitySoftBadge extends StatelessWidget {
  const _CommunitySoftBadge({required this.tone, required this.icon});

  final _CommunityCardTone tone;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.34),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.40)),
        boxShadow: [
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.26),
            blurRadius: 8,
            offset: const Offset(-3, -3),
          ),
          BoxShadow(
            color: tone.shadow.withValues(alpha: 0.10),
            blurRadius: 12,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Icon(icon, color: tone.actionStart, size: 20),
    );
  }
}

class _CommunityBackdropGlow extends StatelessWidget {
  const _CommunityBackdropGlow({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: color, blurRadius: 42, spreadRadius: 10),
          ],
        ),
      ),
    );
  }
}

class _CommunityCardTone {
  const _CommunityCardTone({
    required this.start,
    required this.middle,
    required this.end,
    required this.accent,
    required this.highlight,
    required this.border,
    required this.shadow,
    required this.panel,
    required this.textPrimary,
    required this.textSecondary,
    required this.actionStart,
    required this.actionEnd,
  });

  final Color start;
  final Color middle;
  final Color end;
  final Color accent;
  final Color highlight;
  final Color border;
  final Color shadow;
  final Color panel;
  final Color textPrimary;
  final Color textSecondary;
  final Color actionStart;
  final Color actionEnd;

  factory _CommunityCardTone.resolve(Group group) {
    final isSaving = group.type == 'saving';
    final isPrivate = group.visibility == 'private';

    if (isSaving && isPrivate) {
      return const _CommunityCardTone(
        start: Color(0xFFF7F0FF),
        middle: Color(0xFFE9E8FF),
        end: Color(0xFFD8F0FF),
        accent: Color(0xFF8D84FF),
        highlight: Color(0xFFD8D4FF),
        border: Color(0xD6FFFFFF),
        shadow: Color(0xFF8A8BE1),
        panel: Color(0xFFFDFBFF),
        textPrimary: Color(0xFF1B2042),
        textSecondary: Color(0xB31B2042),
        actionStart: Color(0xFF8B7DFF),
        actionEnd: Color(0xFF61AEFF),
      );
    }

    if (isSaving) {
      return const _CommunityCardTone(
        start: Color(0xFFEFFCF8),
        middle: Color(0xFFDDF9EF),
        end: Color(0xFFD7F0FF),
        accent: Color(0xFF3EC39E),
        highlight: Color(0xFFC5FAE7),
        border: Color(0xD4FFFFFF),
        shadow: Color(0xFF71C1C2),
        panel: Color(0xFFF9FFFD),
        textPrimary: Color(0xFF14333B),
        textSecondary: Color(0xB314333B),
        actionStart: Color(0xFF30BE98),
        actionEnd: Color(0xFF57A8F8),
      );
    }

    if (isPrivate) {
      return const _CommunityCardTone(
        start: Color(0xFFFFECEF),
        middle: Color(0xFFFCE5F6),
        end: Color(0xFFEFDFFF),
        accent: Color(0xFFD66AA5),
        highlight: Color(0xFFFFD4E5),
        border: Color(0xD4FFFFFF),
        shadow: Color(0xFFC78AB1),
        panel: Color(0xFFFFFBFE),
        textPrimary: Color(0xFF3B1A34),
        textSecondary: Color(0xB33B1A34),
        actionStart: Color(0xFFE06B97),
        actionEnd: Color(0xFFC67BFF),
      );
    }

    return const _CommunityCardTone(
      start: Color(0xFFFFF4DD),
      middle: Color(0xFFFFE7D7),
      end: Color(0xFFFFDFF2),
      accent: Color(0xFFFF9A62),
      highlight: Color(0xFFFFD9B9),
      border: Color(0xD6FFFFFF),
      shadow: Color(0xFFD39F8B),
      panel: Color(0xFFFFFCFA),
      textPrimary: Color(0xFF41251D),
      textSecondary: Color(0xB341251D),
      actionStart: Color(0xFFFF9B68),
      actionEnd: Color(0xFFF47AA7),
    );
  }
}

class _CommunityInfoPanel extends StatelessWidget {
  const _CommunityInfoPanel({
    required this.tone,
    required this.amountLabel,
    required this.amountStyle,
    required this.canQuickContribute,
    required this.group,
    required this.onQuickContribution,
  });

  final _CommunityCardTone tone;
  final String amountLabel;
  final TextStyle amountStyle;
  final bool canQuickContribute;
  final Group group;
  final VoidCallback onQuickContribution;

  @override
  Widget build(BuildContext context) {
    final secondaryMetric = _secondaryMetric(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 10, 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.24),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.42)),
        boxShadow: [
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.22),
            blurRadius: 8,
            offset: const Offset(-3, -3),
          ),
          BoxShadow(
            color: tone.shadow.withValues(alpha: 0.10),
            blurRadius: 16,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.28),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.34),
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        group.type == 'saving'
                            ? CoolIcons.walletOutlined
                            : CoolIcons.groupsFilled,
                        color: tone.actionStart,
                        size: 16,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        amountLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: amountStyle,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _CircleActionButton(
                icon: canQuickContribute ? CoolIcons.add : CoolIcons.forward,
                onTap: () {
                  HapticFeedback.selectionClick();
                  onQuickContribution();
                },
                tone: tone,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _CommunityMetricChip(
                  icon: CoolIcons.members,
                  value: '${group.memberCount}',
                  semanticLabel: memberCountLabel(context, group.memberCount),
                  tone: tone,
                ),
              ),
              if (secondaryMetric != null) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: _CommunityMetricChip(
                    icon: secondaryMetric.icon,
                    value: secondaryMetric.value,
                    semanticLabel: secondaryMetric.semanticLabel,
                    tone: tone,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  _CommunityMetricSpec? _secondaryMetric(BuildContext context) {
    if (group.targetAmount > 0) {
      final value = '${fmtAmt(group.targetAmount)} RWF';
      return _CommunityMetricSpec(
        icon: CoolIcons.trendUp,
        value: value,
        semanticLabel: 'Target $value',
      );
    }

    if ((group.monthlyContribution ?? 0) > 0) {
      final value = '${fmtAmt(group.monthlyContribution ?? 0)} RWF';
      return _CommunityMetricSpec(
        icon: CoolIcons.calendar,
        value: value,
        semanticLabel: 'Plan $value',
      );
    }

    return null;
  }
}

class _CommunityMetricSpec {
  const _CommunityMetricSpec({
    required this.icon,
    required this.value,
    required this.semanticLabel,
  });

  final IconData icon;
  final String value;
  final String semanticLabel;
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
