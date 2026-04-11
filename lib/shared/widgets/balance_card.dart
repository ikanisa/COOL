import 'package:flutter/material.dart';

import '../../core/theme/cool_foundations.dart';

class BalanceCardMetric {
  const BalanceCardMetric({
    required this.label,
    required this.value,
    this.accentColor,
  });

  final String label;
  final String value;
  final Color? accentColor;
}

class BalanceCardAction {
  const BalanceCardAction({
    required this.label,
    required this.icon,
    required this.onTap,
    this.isPrimary = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool isPrimary;
}

/// Authoritative wallet surface for balance, trust cues, and payment actions.
///
/// Uses a fixed dark gradient background (financial authority surface).
/// Text is always white-on-dark regardless of theme, per design intent.
class BalanceCard extends StatelessWidget {
  const BalanceCard({
    required this.amount,
    required this.currency,
    required this.changeAmount,
    this.title = 'Fan wallet balance',
    this.subtitle = 'Official payment channel for supporters',
    this.metrics = const <BalanceCardMetric>[],
    this.actions = const <BalanceCardAction>[],
    super.key,
  });

  final int amount;
  final String currency;
  final int changeAmount;
  final String title;
  final String subtitle;
  final List<BalanceCardMetric> metrics;
  final List<BalanceCardAction> actions;

  @override
  Widget build(BuildContext context) {
    final space = context.coolSpace;
    final radii = context.coolRadii;
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final theme = Theme.of(context);
    final isPositiveChange = changeAmount >= 0;

    return Semantics(
      label: '$title. ${_formatAmount(amount)} $currency.',
      child: Container(
        decoration: BoxDecoration(
          color: colors.financialSurface,
          borderRadius: BorderRadius.circular(radii.lg),
          border: Border.all(
            color: colors.borderStrong.withValues(alpha: 0.15),
          ),
          boxShadow: CoolShadows.floating(null, strength: 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned(
              top: -40,
              right: -24,
              child: Opacity(
                opacity: 0.18,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: colors.accentGradient,
                  ),
                  child: const SizedBox(width: 168, height: 168),
                ),
              ),
            ),
            Positioned(
              bottom: -54,
              left: -30,
              child: Opacity(
                opacity: 0.16,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: colors.shellGradient,
                  ),
                  child: const SizedBox(width: 180, height: 180),
                ),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        colors.highlightColor.withValues(alpha: 0.03),
                        Colors.transparent,
                        colors.shadowColor.withValues(alpha: 0.10),
                      ],
                      stops: const [0, 0.36, 1],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: space.sectionPadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title.toUpperCase(),
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1.1,
                                color: colors.secondaryText,
                              ),
                            ),
                            SizedBox(height: space.x2),
                            Text(
                              subtitle,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: colors.secondaryText,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(width: space.x3),
                      Container(
                        width: CoolTapTargets.minimum,
                        height: CoolTapTargets.minimum,
                        decoration: BoxDecoration(
                          color: colors.glassSurface,
                          borderRadius: BorderRadius.circular(radii.sm),
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.account_balance_wallet_rounded,
                          color: colors.primaryText,
                          size: 24,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: space.x5),
                  Text(
                    currency,
                    style: text.mono(
                      theme.textTheme.labelSmall,
                      fontWeight: FontWeight.w600,
                      color: colors.tertiaryText,
                    ),
                  ),
                  SizedBox(height: space.x2),
                  Text(
                    _formatAmount(amount),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.mono(
                      theme.textTheme.headlineMedium,
                      color: colors.primaryText,
                      fontWeight: FontWeight.w700,
                      height: 1.08,
                    ),
                  ),
                  SizedBox(height: space.x3),
                  Wrap(
                    spacing: space.x2,
                    runSpacing: space.x2,
                    children: [
                      _TrustPill(
                        icon: isPositiveChange
                            ? Icons.arrow_upward_rounded
                            : Icons.arrow_downward_rounded,
                        label:
                            '${isPositiveChange ? '+' : '-'}${_formatAmount(changeAmount)} $currency net movement',
                        backgroundColor: isPositiveChange
                            ? colors.chipSelectedBackground
                            : colors.danger.withValues(alpha: 0.16),
                        foregroundColor: isPositiveChange
                            ? colors.primaryText
                            : colors.danger,
                      ),
                      _TrustPill(
                        icon: Icons.shield_outlined,
                        label: 'Protected',
                        backgroundColor: colors.info.withValues(alpha: 0.12),
                        foregroundColor: colors.primaryText,
                      ),
                    ],
                  ),
                  if (metrics.isNotEmpty) ...[
                    SizedBox(height: space.x4),
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(space.x3),
                      decoration: BoxDecoration(
                        color: colors.glassSurface,
                        borderRadius: BorderRadius.circular(radii.md),
                      ),
                      child: Wrap(
                        spacing: space.x3,
                        runSpacing: space.x3,
                        children: [
                          for (final metric in metrics)
                            _MetricTile(metric: metric),
                        ],
                      ),
                    ),
                  ],
                  if (actions.isNotEmpty) ...[
                    SizedBox(height: space.x5),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final compact = constraints.maxWidth < 360;
                        if (compact) {
                          return Column(
                            children: [
                              for (var i = 0; i < actions.length; i++) ...[
                                _BalanceActionButton(action: actions[i]),
                                if (i != actions.length - 1)
                                  SizedBox(height: space.x3),
                              ],
                            ],
                          );
                        }

                        return Row(
                          children: [
                            for (var i = 0; i < actions.length; i++) ...[
                              Expanded(
                                child: _BalanceActionButton(action: actions[i]),
                              ),
                              if (i != actions.length - 1)
                                SizedBox(width: space.x3),
                            ],
                          ],
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatAmount(int value) {
    final source = value.abs().toString();
    final buffer = StringBuffer();
    if (value < 0) {
      buffer.write('-');
    }
    for (var index = 0; index < source.length; index++) {
      if (index > 0 && (source.length - index) % 3 == 0) {
        buffer.write(',');
      }
      buffer.write(source[index]);
    }
    return buffer.toString();
  }
}

class _BalanceActionButton extends StatelessWidget {
  const _BalanceActionButton({required this.action});

  final BalanceCardAction action;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final radii = context.coolRadii;
    final space = context.coolSpace;
    final theme = Theme.of(context);
    final backgroundColor = action.isPrimary
        ? colors.accent
        : colors.highlightColor.withValues(alpha: 0.05);
    final foregroundColor = action.isPrimary
        ? colors.highlightColor
        : colors.primaryText;

    return Material(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(radii.sm),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radii.sm),
        ),
        child: InkWell(
          onTap: action.onTap,
          borderRadius: BorderRadius.circular(radii.sm),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: CoolTapTargets.comfortable,
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: space.x3,
                vertical: space.x3,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(action.icon, size: 18, color: foregroundColor),
                  SizedBox(width: space.x2),
                  Flexible(
                    child: Text(
                      action.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.coolText.mono(
                        theme.textTheme.labelSmall,
                        fontWeight: FontWeight.w700,
                        color: foregroundColor,
                        letterSpacing: 0.8,
                      ),
                    ),
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

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.metric});

  final BalanceCardMetric metric;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final theme = Theme.of(context);
    final accent = metric.accentColor ?? colors.primaryText;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 112),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            metric.label.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w600,
              letterSpacing: 0.9,
              color: colors.secondaryText,
            ),
          ),
          SizedBox(height: context.coolSpace.x2),
          Text(
            metric.value,
            style: text.mono(
              theme.textTheme.labelLarge,
              fontWeight: FontWeight.w600,
              color: accent,
            ),
          ),
        ],
      ),
    );
  }
}

class _TrustPill extends StatelessWidget {
  const _TrustPill({
    required this.icon,
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  final IconData icon;
  final String label;
  final Color backgroundColor;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    final space = context.coolSpace;
    final radii = context.coolRadii;
    final theme = Theme.of(context);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: space.x3, vertical: space.x2),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(radii.pill),
        border: Border.all(color: foregroundColor.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: foregroundColor),
          SizedBox(width: space.x2),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: foregroundColor,
            ),
          ),
        ],
      ),
    );
  }
}
