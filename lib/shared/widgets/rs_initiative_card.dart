import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/cool_foundations.dart';
import '../../core/theme/rs_colors.dart';
import '../../features/partners/rayon/models/rs_models.dart';
import '../../features/partners/rayon/theme/rs_theme.dart';

class RsInitiativeCard extends StatelessWidget {
  const RsInitiativeCard({
    required this.initiative,
    required this.onSupportTap,
    this.onTap,
    super.key,
  });

  final RsInitiative initiative;
  final VoidCallback onSupportTap;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final space = context.coolSpace;
    final radii = context.coolRadii;
    final theme = Theme.of(context);
    final category = RsTheme.parseCategory(
      initiative.category.value.toLowerCase(),
    );
    final categoryColor = RsTheme.categoryColor(category);
    final contributorInitials = _buildContributorInitials(initiative);
    final visibleAvatars = contributorInitials.take(3).toList(growable: false);
    final overflowCount = math.max(
      0,
      initiative.supporterCount - visibleAvatars.length,
    );
    final progress = initiative.progress.clamp(0.0, 1.0).toDouble();

    return Semantics(
      label:
          '${initiative.title}.'
          '${(progress * 100).round()}% funded. '
          '${initiative.supporterCount} supporters.',
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(radii.md),
          child: Ink(
            decoration: BoxDecoration(
              gradient: RsColors.rsSupportGradient,
              borderRadius: BorderRadius.circular(radii.md),
              border: Border.all(color: colors.borderStrong),
              boxShadow: CoolShadows.floating(theme.brightness, strength: 0.34),
            ),
            child: Padding(
              padding: EdgeInsets.all(space.x4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: space.x2 + 2,
                      vertical: space.x1 + 2,
                    ),
                    decoration: BoxDecoration(
                      color: RsTheme.categoryBackground(category),
                      borderRadius: BorderRadius.circular(radii.pill),
                      border: Border.all(
                        color: categoryColor.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      initiative.category.value.toUpperCase(),
                      style: text.rayon(
                        theme.textTheme.labelSmall,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.1,
                        color: categoryColor,
                      ),
                    ),
                  ),
                  SizedBox(height: space.x2),
                  Text(
                    initiative.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: text.rayonCondensed(
                      theme.textTheme.headlineSmall,
                      fontWeight: FontWeight.w900,
                      color: RsColors.rsWhite,
                      height: 0.95,
                    ),
                  ),
                  SizedBox(height: space.x2),
                  Text(
                    initiative.description,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: text.rayon(
                      theme.textTheme.bodySmall,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                      color: colors.secondaryText,
                    ),
                  ),
                  SizedBox(height: space.x4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Raised: ${_formatRwf(initiative.raisedAmount)} of ${_formatRwf(initiative.targetAmount)}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: text.rayon(
                            theme.textTheme.labelSmall,
                            fontWeight: FontWeight.w600,
                            color: RsColors.rsWhite,
                          ),
                        ),
                      ),
                      SizedBox(width: space.x3),
                      Text(
                        '${(progress * 100).round()}%',
                        style: text.mono(
                          theme.textTheme.labelSmall,
                          fontWeight: FontWeight.w700,
                          color: categoryColor,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: space.x2),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(radii.pill),
                    child: SizedBox(
                      height: space.x1 + 2,
                      child: Stack(
                        children: [
                          DecoratedBox(
                            decoration: BoxDecoration(
                              color: colors.overlaySurface,
                            ),
                            child: const SizedBox.expand(),
                          ),
                          FractionallySizedBox(
                            widthFactor: progress,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    categoryColor.withValues(alpha: 0.78),
                                    categoryColor,
                                    RsColors.rsGoldLight,
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: space.x4),
                  Row(
                    children: [
                      SizedBox(
                        width: 84,
                        height: 32,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            for (
                              var index = 0;
                              index < visibleAvatars.length;
                              index++
                            )
                              Positioned(
                                left: index * 18,
                                child: _SupporterAvatar(
                                  label: visibleAvatars[index],
                                  color: _avatarColorForIndex(
                                    index,
                                    categoryColor,
                                  ),
                                ),
                              ),
                            if (overflowCount > 0)
                              Positioned(
                                left: visibleAvatars.length * 18,
                                child: _SupporterAvatar(
                                  label: '+$overflowCount',
                                  color: colors.overlaySurface,
                                  isOverflow: true,
                                ),
                              ),
                          ],
                        ),
                      ),
                      SizedBox(width: space.x2),
                      Expanded(
                        child: Text(
                          '${NumberFormat.decimalPattern('en').format(initiative.supporterCount)} supporters',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: text.rayon(
                            theme.textTheme.labelSmall,
                            fontWeight: FontWeight.w600,
                            color: colors.secondaryText,
                          ),
                        ),
                      ),
                      SizedBox(width: space.x3),
                      _SupportButton(onTap: onSupportTap),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SupportButton extends StatelessWidget {
  const _SupportButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radii = context.coolRadii;
    return SizedBox(
      height: CoolTapTargets.minimum,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RsColors.rsGoldGradient,
          borderRadius: BorderRadius.circular(radii.sm),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(radii.sm),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14),
              child: Center(child: _SupportButtonLabel()),
            ),
          ),
        ),
      ),
    );
  }
}

class _SupportButtonLabel extends StatelessWidget {
  const _SupportButtonLabel();

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final theme = Theme.of(context);
    return Text(
      'SUPPORT',
      style: text.rayonCondensed(
        theme.textTheme.labelLarge,
        fontWeight: FontWeight.w700,
        color: colors.primaryText,
        letterSpacing: 0.4,
      ),
    );
  }
}

class _SupporterAvatar extends StatelessWidget {
  const _SupporterAvatar({
    required this.label,
    required this.color,
    this.isOverflow = false,
  });

  final String label;
  final Color color;
  final bool isOverflow;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final theme = Theme.of(context);
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: colors.overlaySurface, width: 2),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: text.mono(
          theme.textTheme.labelSmall,
          fontWeight: FontWeight.w700,
          color: RsColors.rsWhite,
          letterSpacing: isOverflow ? -0.2 : null,
        ),
      ),
    );
  }
}

List<String> _buildContributorInitials(RsInitiative initiative) {
  const seedInitials = ['JM', 'AU', 'EN', 'CM', 'DN', 'TU'];
  final offset = initiative.title.hashCode.abs() % seedInitials.length;
  return List<String>.generate(
    math.min(3, initiative.supporterCount),
    (index) => seedInitials[(offset + index) % seedInitials.length],
  );
}

Color _avatarColorForIndex(int index, Color categoryColor) {
  if (index == 0) {
    return categoryColor;
  }
  if (index == 1) {
    return RsColors.rsBlueMid;
  }
  return RsColors.rsGold;
}

String _formatRwf(int amount) {
  return '${NumberFormat.decimalPattern('en').format(amount)} RWF';
}
