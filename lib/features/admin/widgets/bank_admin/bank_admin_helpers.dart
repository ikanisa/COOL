import 'package:flutter/material.dart';

import '../../../../core/theme/cool_foundations.dart';

/// Shared helper widgets and functions for the Bank Admin screens.

EdgeInsets _bankInfoPillPadding() => CoolSpace.sectionPadding.copyWith(
  left: CoolSpace.x2 + 2,
  right: CoolSpace.x2 + 2,
  top: CoolSpace.x2,
  bottom: CoolSpace.x2,
);

EdgeInsets _bankStatusTagPadding() => CoolSpace.sectionPadding.copyWith(
  left: CoolSpace.x2 + 2,
  right: CoolSpace.x2 + 2,
  top: CoolSpace.x1 + 2,
  bottom: CoolSpace.x1 + 2,
);

const BorderRadius _bankInfoPillRadius = BorderRadius.all(
  Radius.circular(CoolRadii.xs),
);

const BorderRadius _bankStatusTagRadius = BorderRadius.all(
  Radius.circular(CoolRadii.pill),
);

String bankTitle(String raw) {
  if (raw.trim().isEmpty) return '-';
  return raw
      .split('_')
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}

String bankFileSafe(String raw) {
  return raw
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
}

bool bankIsConfirmedContributionStatus(String status) {
  return status == 'confirmed' || status == 'completed';
}

class BankInfoPill extends StatelessWidget {
  const BankInfoPill({required this.label, required this.value, super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);

    return Container(
      padding: _bankInfoPillPadding(),
      decoration: BoxDecoration(
        color: colors.cardSurfaceStrong.withValues(alpha: 0.72),
        borderRadius: _bankInfoPillRadius,
        border: Border.all(color: colors.border),
      ),
      child: Text(
        '$label: $value',
        style: theme.textTheme.labelSmall?.copyWith(
          color: colors.secondaryText,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class BankStatusTag extends StatelessWidget {
  const BankStatusTag({
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
    super.key,
  });

  final String label;
  final Color backgroundColor;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: _bankStatusTagPadding(),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: _bankStatusTagRadius,
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: foregroundColor,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

Color bankLoanStatusColor(BuildContext context, String status) {
  final colors = context.coolSemanticColors;
  switch (status) {
    case 'approved':
    case 'completed':
      return colors.success;
    case 'disbursed':
    case 'repaying':
      return colors.info;
    case 'defaulted':
      return colors.danger;
    case 'rejected':
      return colors.warning;
    default:
      return colors.neutral;
  }
}
