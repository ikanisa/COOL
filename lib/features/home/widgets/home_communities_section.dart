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
    final signalIcon = _signalIconForGroup();
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
    final subtitle = _subtitle(context);

    return Semantics(
      button: true,
      label:
          '$title. $typeLabel. $visibilityLabel. $amountLabel. ${memberCountLabel(context, group.memberCount)}.',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onOpen,
              borderRadius: BorderRadius.circular(32),
              splashColor: Colors.white.withValues(alpha: 0.10),
              highlightColor: Colors.transparent,
              child: Ink(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [tone.start, tone.middle, tone.end],
                    stops: const [0.0, 0.56, 1.0],
                  ),
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(color: tone.border),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.white.withValues(alpha: 0.72),
                      blurRadius: 14,
                      offset: const Offset(-5, -5),
                    ),
                    BoxShadow(
                      color: tone.shadow.withValues(alpha: 0.22),
                      blurRadius: 30,
                      offset: const Offset(0, 18),
                    ),
                    BoxShadow(
                      color: tone.shadow.withValues(alpha: 0.10),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: SizedBox(
                  height: 280,
                  child: Stack(
                    children: [
                      Positioned(
                        top: -42,
                        right: -10,
                        child: _GlowOrb(
                          size: 138,
                          color: Colors.white.withValues(alpha: 0.42),
                        ),
                      ),
                      Positioned(
                        bottom: -54,
                        left: -16,
                        child: _GlowOrb(
                          size: 156,
                          color: tone.highlight.withValues(alpha: 0.44),
                        ),
                      ),
                      Positioned(
                        top: 20,
                        left: 18,
                        child: _CommunitySoftBadge(
                          tone: tone,
                          icon: group.type == 'saving'
                              ? CoolIcons.savings
                              : CoolIcons.groupsFilled,
                        ),
                      ),
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.white.withValues(alpha: 0.44),
                                Colors.white.withValues(alpha: 0.18),
                                Colors.transparent,
                              ],
                              stops: const [0.0, 0.30, 0.84],
                            ),
                            borderRadius: BorderRadius.circular(32),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 18, 18, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(width: 54),
                                Expanded(
                                  child: Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      _CommunityGlassPill(
                                        label: typeLabel,
                                        icon: group.type == 'saving'
                                            ? CoolIcons.trendUp
                                            : CoolIcons.groupsFilled,
                                        tone: tone,
                                      ),
                                      _CommunityGlassPill(
                                        label: visibilityLabel,
                                        icon: group.visibility == 'private'
                                            ? CoolIcons.lock
                                            : CoolIcons.shieldOutline,
                                        tone: tone,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: CoolSpace.x3),
                                _CommunitySignalOrb(
                                  tone: tone,
                                  icon: signalIcon,
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Expanded(
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: context.coolText.headline(
                                        theme.textTheme.headlineSmall,
                                        color: tone.textPrimary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: CoolSpace.x2),
                                    Text(
                                      subtitle,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            color: tone.textSecondary,
                                            height: 1.28,
                                            fontWeight: FontWeight.w500,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            _CommunityInfoPanel(
                              tone: tone,
                              amountLabel: amountLabel,
                              amountStyle: context.coolText.display(
                                theme.textTheme.headlineSmall,
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
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _subtitle(BuildContext context) {
    final trimmedDescription = group.description?.trim() ?? '';
    if (trimmedDescription.isNotEmpty) {
      return trimmedDescription;
    }

    final parts = <String>[memberCountLabel(context, group.memberCount)];
    if (group.type == 'saving' &&
        (group.frequency?.trim().isNotEmpty ?? false)) {
      parts.add(group.frequency!.replaceAll('_', ' ').toUpperCase());
    } else if (group.visibility == 'private') {
      parts.add(context.l10n.private);
    } else {
      parts.add(context.l10n.public);
    }
    return parts.join(' • ');
  }

  IconData _signalIconForGroup() {
    if (group.visibility == 'private') {
      return CoolIcons.lock;
    }
    if (group.type == 'saving') {
      return CoolIcons.trendUp;
    }
    return CoolIcons.groupsFilled;
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
          width: 54,
          height: 54,
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
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }
}

class _CommunityGlassPill extends StatelessWidget {
  const _CommunityGlassPill({
    required this.label,
    required this.icon,
    required this.tone,
  });

  final String label;
  final IconData icon;
  final _CommunityCardTone tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.58),
            tone.panel.withValues(alpha: 0.46),
          ],
        ),
        borderRadius: BorderRadius.circular(CoolRadii.pill),
        border: Border.all(color: Colors.white.withValues(alpha: 0.52)),
        boxShadow: [
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.28),
            blurRadius: 8,
            offset: const Offset(-2, -2),
          ),
          BoxShadow(
            color: tone.shadow.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: tone.textPrimary),
          const SizedBox(width: 6),
          Text(
            label,
            style: context.coolText.mono(
              Theme.of(context).textTheme.labelSmall,
              color: tone.textPrimary,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.85,
            ),
          ),
        ],
      ),
    );
  }
}

class _CommunityMetricChip extends StatelessWidget {
  const _CommunityMetricChip({
    required this.label,
    required this.value,
    required this.tone,
  });

  final String label;
  final String value;
  final _CommunityCardTone tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: tone.panel.withValues(alpha: 0.76),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.50)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: context.coolText.mono(
              Theme.of(context).textTheme.labelSmall,
              color: tone.textSecondary,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: tone.textPrimary,
              fontWeight: FontWeight.w700,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

class _CommunitySignalOrb extends StatelessWidget {
  const _CommunitySignalOrb({required this.tone, required this.icon});

  final _CommunityCardTone tone;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white, tone.panel.withValues(alpha: 0.92)],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.54)),
        boxShadow: [
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.34),
            blurRadius: 10,
            offset: const Offset(-3, -3),
          ),
          BoxShadow(
            color: tone.shadow.withValues(alpha: 0.12),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Icon(icon, color: tone.actionStart, size: 20),
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
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.86),
            tone.panel.withValues(alpha: 0.74),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.60)),
        boxShadow: [
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.44),
            blurRadius: 10,
            offset: const Offset(-4, -4),
          ),
          BoxShadow(
            color: tone.shadow.withValues(alpha: 0.14),
            blurRadius: 14,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Icon(icon, color: tone.actionStart, size: 20),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.size, required this.color});

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
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 10, 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.86),
            tone.panel.withValues(alpha: 0.72),
          ],
        ),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.white.withValues(alpha: 0.58)),
        boxShadow: [
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.36),
            blurRadius: 12,
            offset: const Offset(-4, -4),
          ),
          BoxShadow(
            color: tone.shadow.withValues(alpha: 0.12),
            blurRadius: 18,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(amountLabel, style: amountStyle),
                const SizedBox(height: CoolSpace.x2),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _CommunityMetricChip(
                      label: 'MEMBERS',
                      value: '${group.memberCount}',
                      tone: tone,
                    ),
                    if (group.targetAmount > 0)
                      _CommunityMetricChip(
                        label: 'TARGET',
                        value: '${fmtAmt(group.targetAmount)} RWF',
                        tone: tone,
                      )
                    else if ((group.monthlyContribution ?? 0) > 0)
                      _CommunityMetricChip(
                        label: 'PLAN',
                        value: '${fmtAmt(group.monthlyContribution ?? 0)} RWF',
                        tone: tone,
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: CoolSpace.x3),
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
    );
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

void openCommunityContribution(BuildContext context, Group group) {
  if (!groupHasContributionRoute(group)) {
    openCommunityGroup(context, group);
    return;
  }
  launchGroupContribution(context, group: group);
}
