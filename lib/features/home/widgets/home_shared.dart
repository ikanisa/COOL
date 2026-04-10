import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/cool_card.dart';
import '../models/home_dashboard_data.dart';

String fmtAmt(int v) {
  final s = v.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

String fmtSignedAmt(int v) {
  if (v == 0) {
    return '0';
  }
  return '${v > 0 ? '+' : '-'}${fmtAmt(v.abs())}';
}

String formatOperationMeta(DateTime recordedAt, String type) {
  final now = DateTime.now();
  final today = DateUtils.dateOnly(now);
  final date = DateUtils.dateOnly(recordedAt);
  final normalizedType = _normalizeOperationType(type);
  final timeLabel = DateFormat('h:mm a').format(recordedAt).toUpperCase();

  if (date == today) {
    return 'TODAY, $timeLabel • $normalizedType';
  }

  if (date == today.subtract(const Duration(days: 1))) {
    return 'YESTERDAY, $timeLabel • $normalizedType';
  }

  final dateLabel = DateFormat('MMM d').format(recordedAt).toUpperCase();
  return '$dateLabel, $timeLabel • $normalizedType';
}

String summarizeMonthlyMovement(int amount) {
  if (amount == 0) {
    return 'NO CHANGE THIS MONTH';
  }
  return 'THIS MONTH ${fmtSignedAmt(amount)} RWF';
}

IconData operationIconFor(HomeDashboardTransaction transaction) {
  final title = transaction.title.toLowerCase();
  final type = transaction.type.toLowerCase();

  if (title.contains('contribution') || transaction.groupName != null) {
    return Icons.groups_rounded;
  }
  if (type.contains('debit')) {
    return Icons.north_east_rounded;
  }
  if (type.contains('credit') || transaction.isPositive) {
    return Icons.south_west_rounded;
  }
  if (type.contains('interest')) {
    return Icons.savings_rounded;
  }
  return Icons.sync_alt_rounded;
}

Color operationAccentFor(
  HomeDashboardTransaction transaction,
  CoolSemanticColors colors,
) {
  final title = transaction.title.toLowerCase();
  final type = transaction.type.toLowerCase();
  if (title.contains('contribution') || transaction.groupName != null) {
    return colors.accent;
  }
  if (type.contains('debit')) {
    return colors.danger;
  }
  if (type.contains('credit') || transaction.isPositive) {
    return colors.success;
  }
  return colors.warning;
}

String resolveDisplayName(String? officialName, String? fullName) {
  final official = officialName?.trim() ?? '';
  if (official.isNotEmpty) {
    return official;
  }

  final full = fullName?.trim() ?? '';
  if (full.isNotEmpty) {
    return full;
  }

  return 'Coool';
}

String initialsForName(String name) {
  final compact = name.trim();
  if (compact.isEmpty) {
    return 'CO';
  }

  final parts = compact.split(RegExp(r'\s+')).where((part) => part.isNotEmpty);
  final list = parts.toList(growable: false);
  if (list.isEmpty) {
    return 'CO';
  }
  if (list.length == 1) {
    return list.first.characters.take(2).toString().toUpperCase();
  }
  return '${list.first.characters.first}${list.last.characters.first}'
      .toUpperCase();
}

String memberCountLabel(int count) {
  if (count == 1) {
    return '1 MEMBER';
  }
  return '$count MEMBERS';
}

String _normalizeOperationType(String type) {
  final normalized = type.trim().toLowerCase();
  if (normalized.contains('debit')) {
    return 'TRANSFER';
  }
  if (normalized.contains('credit')) {
    return 'RECEIVED';
  }
  if (normalized.contains('deposit')) {
    return 'SAVING';
  }
  if (normalized.contains('interest')) {
    return 'INTEREST';
  }
  if (normalized.contains('payout')) {
    return 'PAYOUT';
  }
  return normalized.isEmpty ? 'ACTIVITY' : normalized.toUpperCase();
}

class HomeProgressBar extends StatelessWidget {
  const HomeProgressBar({
    super.key,
    required this.value,
    required this.barColor,
    this.barHeight = 4,
  });

  final double value;
  final Color barColor;
  final double barHeight;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          height: barHeight,
          width: constraints.maxWidth,
          decoration: BoxDecoration(
            // Surface shift instead of border
            color: colors.cardSurface,
            borderRadius: BorderRadius.circular(barHeight / 2),
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Container(
              width: constraints.maxWidth * value.clamp(0.0, 1.0),
              decoration: BoxDecoration(
                color: barColor,
                borderRadius: BorderRadius.circular(barHeight / 2),
                boxShadow: [
                  BoxShadow(
                    color: barColor.withValues(alpha: 0.4),
                    blurRadius: 4,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class HomeGlassCard extends StatelessWidget {
  const HomeGlassCard({super.key, required this.child, this.onTap});
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    return CoolCard(
      variant: CoolCardVariant.glass,
      cardPadding: CoolCardPadding.none,
      padding: const EdgeInsets.all(CoolSpace.x5),
      backgroundColor: colors.glassSurface,
      // No border per No-Line Rule
      borderColor: Colors.transparent,
      onTap: onTap,
      child: child,
    );
  }
}

class HomeAccentTag extends StatelessWidget {
  const HomeAccentTag({super.key, required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colors.accent.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(CoolRadii.sm),
        // No border per No-Line Rule
      ),
      child: Text(
        label,
        style: context.coolText.mono(
          Theme.of(context).textTheme.labelSmall,
          fontWeight: FontWeight.w800,
          color: colors.accent,
          letterSpacing: 1.0,
        ),
      ),
    );
  }
}
