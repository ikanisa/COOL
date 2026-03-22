import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/cool_palette.dart';

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
class BalanceCard extends StatelessWidget {
  const BalanceCard({
    required this.amount,
    required this.currency,
    required this.changeAmount,
    this.title = 'Available balance',
    this.subtitle = 'Institution-grade wallet controls',
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
    final palette = context.coolPalette;
    final isPositiveChange = changeAmount >= 0;

    return Semantics(
      label: '$title. ${_formatAmount(amount)} $currency.',
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF071B3C),
              const Color(0xFF0B274E),
              const Color(0xFF0E355F),
            ],
          ),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.28),
              blurRadius: 34,
              spreadRadius: -14,
              offset: const Offset(0, 24),
            ),
            BoxShadow(
              color: AppColors.rsBlue.withValues(alpha: 0.18),
              blurRadius: 24,
              spreadRadius: -12,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned(
              top: -40,
              right: -24,
              child: Container(
                width: 168,
                height: 168,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      Colors.white.withValues(alpha: 0.18),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: -54,
              left: -30,
              child: Container(
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      palette.accent.withValues(alpha: 0.24),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
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
                              style: GoogleFonts.dmSans(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.1,
                                color: Colors.white.withValues(alpha: 0.72),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              subtitle,
                              style: GoogleFonts.dmSans(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: Colors.white.withValues(alpha: 0.84),
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.14),
                          ),
                        ),
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.account_balance_wallet_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  Text(
                    currency,
                    style: GoogleFonts.dmMono(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.white.withValues(alpha: 0.68),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _formatAmount(amount),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.dmMono(
                      fontSize: 36,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      height: 1.08,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      _TrustPill(
                        icon: isPositiveChange
                            ? Icons.arrow_upward_rounded
                            : Icons.arrow_downward_rounded,
                        label:
                            '${isPositiveChange ? '+' : '-'}${_formatAmount(changeAmount)} $currency net movement',
                        backgroundColor: isPositiveChange
                            ? palette.accent.withValues(alpha: 0.16)
                            : palette.red.withValues(alpha: 0.16),
                        foregroundColor: isPositiveChange
                            ? Colors.white
                            : const Color(0xFFFFC5CE),
                      ),
                      const SizedBox(width: 8),
                      const _TrustPill(
                        icon: Icons.shield_outlined,
                        label: 'Protected',
                        backgroundColor: Color(0x163D8BFF),
                        foregroundColor: Colors.white,
                      ),
                    ],
                  ),
                  if (metrics.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.1),
                        ),
                      ),
                      child: Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          for (final metric in metrics)
                            _MetricTile(metric: metric),
                        ],
                      ),
                    ),
                  ],
                  if (actions.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final compact = constraints.maxWidth < 360;
                        if (compact) {
                          return Column(
                            children: [
                              for (var i = 0; i < actions.length; i++) ...[
                                _BalanceActionButton(action: actions[i]),
                                if (i != actions.length - 1)
                                  const SizedBox(height: 10),
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
                                const SizedBox(width: 10),
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
    return Material(
      color: action.isPrimary
          ? Colors.white
          : Colors.white.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: action.onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                action.icon,
                size: 18,
                color: action.isPrimary ? AppColors.darkBg : Colors.white,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  action.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.dmSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: action.isPrimary ? AppColors.darkBg : Colors.white,
                  ),
                ),
              ),
            ],
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
    final accent = metric.accentColor ?? Colors.white;
    return Container(
      constraints: const BoxConstraints(minWidth: 112),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            metric.label.toUpperCase(),
            style: GoogleFonts.dmSans(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.9,
              color: Colors.white.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            metric.value,
            style: GoogleFonts.dmMono(
              fontSize: 14,
              fontWeight: FontWeight.w700,
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: foregroundColor.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: foregroundColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.dmSans(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: foregroundColor,
            ),
          ),
        ],
      ),
    );
  }
}
