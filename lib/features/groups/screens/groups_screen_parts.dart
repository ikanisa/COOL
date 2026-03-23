part of 'groups_screen.dart';

class _GroupsHeroCard extends StatelessWidget {
  const _GroupsHeroCard({
    required this.activeView,
    required this.typeFilter,
    required this.visibilityFilter,
    required this.hasBankPartner,
    required this.createLabel,
    required this.onViewChanged,
    required this.onToggleType,
    required this.onToggleVisibility,
    this.onCreate,
  });

  final _GroupsView activeView;
  final _GroupTypeFilter typeFilter;
  final _GroupVisibilityFilter visibilityFilter;
  final bool hasBankPartner;
  final String createLabel;
  final ValueChanged<_GroupsView> onViewChanged;
  final ValueChanged<_GroupTypeFilter> onToggleType;
  final ValueChanged<_GroupVisibilityFilter> onToggleVisibility;
  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) {
    final isDiscover = activeView == _GroupsView.discover;

    return CoolGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TabPill(
                  label: context.l10n.myGroups,
                  isActive: !isDiscover,
                  onTap: () => onViewChanged(_GroupsView.mine),
                ),
              ),
              const SizedBox(width: CoolSpace.x3),
              Expanded(
                child: TabPill(
                  label: context.l10n.discover,
                  isActive: isDiscover,
                  onTap: () => onViewChanged(_GroupsView.discover),
                ),
              ),
            ],
          ),
          if (!isDiscover) ...[
            const SizedBox(height: CoolSpace.x6),
            Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                _FilterIconButton(
                  tooltip: context.l10n.savings,
                  icon: Icons.savings_outlined,
                  isActive: typeFilter == _GroupTypeFilter.saving,
                  onTap: () => onToggleType(_GroupTypeFilter.saving),
                  visible: hasBankPartner,
                ),
                const SizedBox(width: CoolSpace.x3),
                _FilterIconButton(
                  tooltip: context.l10n.peopleOutline,
                  icon: Icons.people_outline_rounded,
                  isActive: typeFilter == _GroupTypeFilter.community,
                  onTap: () => onToggleType(_GroupTypeFilter.community),
                ),
                const SizedBox(width: CoolSpace.x3),
                _FilterIconButton(
                  tooltip: context.l10n.lockOutline,
                  icon: Icons.lock_outline_rounded,
                  isActive:
                      visibilityFilter == _GroupVisibilityFilter.privateOnly,
                  onTap: () =>
                      onToggleVisibility(_GroupVisibilityFilter.privateOnly),
                ),
                const SizedBox(width: CoolSpace.x3),
                _FilterIconButton(
                  tooltip: 'Public',
                  icon: Icons.public_rounded,
                  isActive:
                      visibilityFilter == _GroupVisibilityFilter.publicOnly,
                  onTap: () =>
                      onToggleVisibility(_GroupVisibilityFilter.publicOnly),
                ),
              ],
            ),
          ],
          if (!isDiscover && onCreate != null) ...[
            const SizedBox(height: CoolSpace.x6),
            CoolButton(label: createLabel, onTap: onCreate!),
          ],
        ],
      ),
    );
  }
}

class _FilterIconButton extends StatelessWidget {
  const _FilterIconButton({
    required this.icon,
    required this.isActive,
    required this.onTap,
    this.tooltip,
    this.visible = true,
  });

  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;
  final String? tooltip;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    final colors = context.coolSemanticColors;
    final radii = context.coolRadii;
    return Semantics(
      button: true,
      label: tooltip ?? 'Filter',
      selected: isActive,
      child: Tooltip(
        message: tooltip ?? '',
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: CoolMotion.quick,
            width: CoolTapTargets.minimum,
            height: CoolTapTargets.minimum,
            decoration: BoxDecoration(
              color: isActive
                  ? colors.chipSelectedBackground
                  : colors.cardSurface,
              borderRadius: BorderRadius.all(Radius.circular(radii.sm)),
              border: Border.all(
                color: isActive ? colors.accent : colors.border,
                width: 1.5,
              ),
            ),
            child: Icon(
              icon,
              size: 22,
              color: isActive ? colors.accent : colors.tertiaryText,
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.isDiscover});

  final bool isDiscover;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return CoolStateView.empty(
      title: isDiscover ? l10n.groupsEmptyPublicTitle : l10n.noGroupsYet,
      message: isDiscover
          ? l10n.groupsEmptyPublicMessage
          : l10n.groupsEmptyPrivateMessage,
      icon: Icons.groups_2_outlined,
    );
  }
}

class _GroupListItem extends StatelessWidget {
  const _GroupListItem({required this.group});

  final Group group;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final l10n = context.l10n;
    final progress = group.targetAmount > 0
        ? (group.amount / group.targetAmount).clamp(0.0, 1.0)
        : 0.0;
    final percent = (progress * 100).round();
    final accentColor = group.type == 'saving' ? colors.accent : colors.warning;

    return CoolCard(
      onTap: () {
        final id = group.id;
        if (id != null && id.isNotEmpty) {
          context.push('/groups/$id');
        }
      },
      child: Padding(
        padding: const EdgeInsets.all(CoolSpace.x6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${_formatAmount(group.amount)} RWF',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.mono(
                Theme.of(context).textTheme.headlineSmall,
                fontWeight: FontWeight.w800,
                color: accentColor,
              ),
            ),
            const SizedBox(height: CoolSpace.x3 - 2),
            Text(
              group.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: CoolSpace.x3 - 2),
            Wrap(
              spacing: CoolSpace.x2 - 2,
              runSpacing: CoolSpace.x2 - 2,
              children: [
                if (group.momoNumber != null &&
                    group.momoNumber!.trim().isNotEmpty)
                  _MetaChip(label: _shortenPhone(group.momoNumber!)),
                if (group.type == 'saving')
                  const StatusBadge.saving()
                else
                  const StatusBadge.community(),
                if (group.visibility == 'public')
                  const StatusBadge.public()
                else
                  const StatusBadge.private(),
              ],
            ),
            const SizedBox(height: CoolSpace.x2 - 2),
            Text(
              l10n.memberCount(group.memberCount),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.secondaryText),
            ),
            const SizedBox(height: CoolSpace.x5),
            ClipRRect(
              borderRadius: const BorderRadius.all(
                Radius.circular(CoolRadii.xs),
              ),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: colors.cardSurfaceStrong,
                color: accentColor,
              ),
            ),
            const SizedBox(height: CoolSpace.x3),
            Row(
              children: [
                Text(
                  '$percent% of target',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colors.tertiaryText,
                  ),
                ),
                const Spacer(),
                Icon(
                  Icons.arrow_forward_rounded,
                  color: colors.tertiaryText,
                  size: 20,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Shortens phone: "+250788123456" or "250788123456" → "0788123456".
  static String _shortenPhone(String phone) {
    final cleaned = phone.replaceAll(RegExp(r'[\s\-]'), '');
    if (cleaned.startsWith('+250')) return '0${cleaned.substring(4)}';
    if (cleaned.startsWith('250') && cleaned.length >= 12) {
      return '0${cleaned.substring(3)}';
    }
    return cleaned;
  }

  static String _formatAmount(int value) {
    final digits = value.toString();
    final buffer = StringBuffer();
    for (var index = 0; index < digits.length; index++) {
      if (index > 0 && (digits.length - index) % 3 == 0) {
        buffer.write(',');
      }
      buffer.write(digits[index]);
    }
    return buffer.toString();
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final radii = context.coolRadii;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: CoolSpace.x2,
        vertical: CoolSpace.x1,
      ),
      decoration: BoxDecoration(
        color: colors.cardSurfaceStrong,
        borderRadius: BorderRadius.all(Radius.circular(radii.xs / 2)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: colors.secondaryText,
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error, required this.onRetry});

  final String error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: CoolStateView.error(
          title: 'Load groups failed',
          message: error,
          actionLabel: 'Try again',
          action: () => unawaited(onRetry()),
        ),
      ),
    );
  }
}
