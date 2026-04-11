import 'package:flutter/material.dart';

import '../../core/theme/cool_foundations.dart';
import '../../core/utils/money_formatters.dart';
import 'cool_card.dart';
import 'status_badge.dart';

/// A horizontally-scrollable group card showing type, amount, progress,
/// and a member avatar stack.
///
/// Designed for use inside a horizontal [ListView] with a minimum width.
class GroupCard extends StatelessWidget {
  const GroupCard({
    required this.name,
    required this.type,
    required this.visibility,
    required this.amount,
    required this.memberCount,
    required this.targetAmount,
    required this.onTap,
    super.key,
  });

  final String name;
  final String type;
  final String visibility;
  final int amount;
  final int memberCount;
  final int targetAmount;
  final VoidCallback onTap;

  bool get _isSaving => type == 'saving';

  double get _progress =>
      targetAmount > 0 ? (amount / targetAmount).clamp(0.0, 1.0) : 0.0;

  Color _accentColor(CoolSemanticColors colors) =>
      _isSaving ? colors.accent : colors.warning;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final theme = Theme.of(context);
    final accent = _accentColor(colors);

    return Semantics(
      button: true,
      label:
          '$name. ${_isSaving ? 'Saving' : 'Community'} group. '
          '${formatWholeMoneyAmount(amount)} RWF. $memberCount members.',
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 200),
        child: CoolCard(
          onTap: onTap,
          padding: const EdgeInsets.all(CoolSpace.x5 - 2),
          backgroundColor: _isSaving
              ? colors.financialSurface
              : colors.teamSurface,
          borderRadius: CoolRadii.md,
          borderColor: colors.border,
          semanticsLabel: name,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  if (_isSaving)
                    const StatusBadge.saving()
                  else
                    const StatusBadge.community(),
                  const SizedBox(width: 6),
                  if (visibility == 'public')
                    const StatusBadge.public()
                  else
                    const StatusBadge.private(),
                ],
              ),
              const SizedBox(height: CoolSpace.x3),
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colors.primaryText,
                ),
              ),
              const SizedBox(height: CoolSpace.x2),
              Text(
                '${formatWholeMoneyAmount(amount)} RWF',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.mono(
                  theme.textTheme.headlineSmall,
                  fontWeight: FontWeight.w800,
                  color: accent,
                ),
              ),
              const SizedBox(height: CoolSpace.x3),
              ClipRRect(
                borderRadius: const BorderRadius.all(Radius.circular(2)),
                child: LinearProgressIndicator(
                  value: _progress,
                  minHeight: 4,
                  backgroundColor: colors.cardSurfaceStrong,
                  color: accent,
                ),
              ),
              const SizedBox(height: CoolSpace.x1),
              Text(
                'Target: ${formatWholeMoneyAmount(targetAmount)} RWF',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w500,
                  color: colors.tertiaryText,
                ),
              ),
              const SizedBox(height: CoolSpace.x3),
              _MemberAvatarStack(memberCount: memberCount, accentColor: accent),
            ],
          ),
        ),
      ),
    );
  }
}

class _MemberAvatarStack extends StatelessWidget {
  const _MemberAvatarStack({
    required this.memberCount,
    required this.accentColor,
  });

  final int memberCount;
  final Color accentColor;

  static const _size = 28.0;
  static const _overlap = 10.0;
  static const _maxVisible = 3;
  static const _initials = ['A', 'B', 'C'];

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final text = context.coolText;
    final visibleCount = memberCount.clamp(0, _maxVisible);
    final overflow = memberCount - _maxVisible;

    return SizedBox(
      height: _size,
      child: Row(
        children: [
          SizedBox(
            width: visibleCount > 0
                ? _size + (_overlap * (visibleCount - 1).clamp(0, _maxVisible))
                : 0,
            child: Stack(
              children: List.generate(visibleCount, (i) {
                return Positioned(
                  left: i * _overlap,
                  child: Container(
                    width: _size,
                    height: _size,
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                      border: Border.all(color: colors.cardSurface, width: 2),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      _initials[i],
                      style: text.mono(
                        theme.textTheme.labelSmall,
                        fontWeight: FontWeight.w700,
                        color: accentColor,
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
          if (overflow > 0) ...[
            const SizedBox(width: 6),
            Text(
              '+$overflow',
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w500,
                color: colors.tertiaryText,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
