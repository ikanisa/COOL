import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
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
    final category = RsTheme.parseCategory(initiative.category.value.toLowerCase());
    final categoryColor = RsTheme.categoryColor(category);
    final contributorInitials = _buildContributorInitials(initiative);
    final visibleAvatars = contributorInitials.take(3).toList(growable: false);
    final overflowCount = math.max(
      0,
      initiative.supporterCount - visibleAvatars.length,
    );

    return Semantics(
      label: '${initiative.title}. '
          '${(initiative.progress * 100).round()}% funded. '
          '${initiative.supporterCount} supporters.',
      excludeSemantics: true,
      child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 24,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: RsTheme.categoryBackground(category),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    initiative.category.value.toUpperCase(),
                    style: GoogleFonts.barlow(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.1,
                      color: categoryColor,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  initiative.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.barlowCondensed(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    color: AppColors.rsWhite,
                    height: 0.95,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  initiative.description,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.barlow(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    height: 1.35,
                    color: AppColors.text2,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Raised: ${_formatRwf(initiative.raisedAmount)} of ${_formatRwf(initiative.targetAmount)}',
                        style: GoogleFonts.barlow(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.rsWhite,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '${(initiative.progress * 100).round()}%',
                      style: GoogleFonts.dmMono(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: categoryColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: SizedBox(
                    height: 6,
                    child: Stack(
                      children: [
                        Container(color: AppColors.surface3),
                        FractionallySizedBox(
                          widthFactor: initiative.progress,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  categoryColor.withValues(alpha: 0.78),
                                  categoryColor,
                                  AppColors.rsGoldLight,
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    SizedBox(
                      width: 72,
                      height: 28,
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
                                color: AppColors.surface3,
                                isOverflow: true,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${NumberFormat.decimalPattern('en').format(initiative.supporterCount)} supporters',
                        style: GoogleFonts.barlow(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text2,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
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
    return SizedBox(
      height: 38,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.rsBlue,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Center(
                child: Text(
                  'SUPPORT',
                  style: GoogleFonts.barlowCondensed(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppColors.rsWhite,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ),
          ),
        ),
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
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.surface2, width: 2),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: GoogleFonts.dmMono(
          fontSize: isOverflow ? 9 : 10,
          fontWeight: FontWeight.w700,
          color: AppColors.rsWhite,
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
    return AppColors.rsBlueMid;
  }
  return AppColors.rsGold;
}

String _formatRwf(int amount) {
  return '${NumberFormat.decimalPattern('en').format(amount)} RWF';
}
