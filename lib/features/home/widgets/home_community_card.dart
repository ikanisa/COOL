part of 'home_sections.dart';

// ═══════════════════════════════════════════════════════════════
// Community card tone (color palette)
// ═══════════════════════════════════════════════════════════════

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

// ═══════════════════════════════════════════════════════════════
// Small community card sub-widgets
// ═══════════════════════════════════════════════════════════════

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

// ═══════════════════════════════════════════════════════════════
// Info panel (bottom of community card)
// ═══════════════════════════════════════════════════════════════

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
