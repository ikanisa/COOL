import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/cool_palette.dart';
import '../../../../core/utils/intl_locale.dart';
import '../../../../shared/widgets/cool_card.dart';
import '../models/home_dashboard_data.dart';

class RecentActivityCard extends StatelessWidget {
  const RecentActivityCard({
    super.key,
    required this.activityCount,
    required this.recentTransactions,
  });

  final int activityCount;
  final List<HomeDashboardTransaction> recentTransactions;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    final localeName = resolveIntlLocale(context);
    final displayed = recentTransactions.take(3).toList();

    return CoolCard(
      backgroundColor: palette.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Recent Activity',
                style: GoogleFonts.dmSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: palette.text,
                ),
              ),
              if (activityCount > 3)
                GestureDetector(
                  onTap: () {
                    // Navigate to full statements
                    context.push(AppRoutes.momo);
                  },
                  child: Text(
                    'See All',
                    style: GoogleFonts.dmSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: palette.accent,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (displayed.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No recent activity',
                style: GoogleFonts.dmSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: palette.text3,
                ),
              ),
            )
          else
            Column(
              children: [
                for (var i = 0; i < displayed.length; i++) ...[
                  if (i > 0)
                    Divider(height: 24, thickness: 1, color: palette.border),
                  _TransactionRow(tx: displayed[i], localeName: localeName),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

class _TransactionRow extends StatelessWidget {
  const _TransactionRow({required this.tx, required this.localeName});

  final HomeDashboardTransaction tx;
  final String localeName;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    final isCredit = tx.isPositive;
    final amountColor = isCredit ? const Color(0xFF22C55E) : palette.text;
    final amountString = signedCurrency(
      tx.signedAmount,
      localeName,
      tx.currency,
    );

    return Semantics(
      label:
          '${tx.title}, ${isCredit ? 'Received' : 'Paid'} ${signedSpokenCurrency(tx.signedAmount, localeName, tx.currency)} on ${DateFormat.yMd(localeName).format(tx.recordedAt)}',
      child: ExcludeSemantics(
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: palette.surface2,
                shape: BoxShape.circle,
                border: Border.all(color: palette.border),
              ),
              alignment: Alignment.center,
              child: Icon(
                isCredit
                    ? Icons.arrow_downward_rounded
                    : Icons.arrow_upward_rounded,
                size: 18,
                color: isCredit ? const Color(0xFF22C55E) : palette.text3,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tx.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.dmSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: palette.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    DateFormat.yMd(localeName).format(tx.recordedAt),
                    style: GoogleFonts.dmSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: palette.text3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              amountString,
              style: GoogleFonts.dmSans(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: amountColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String formatCurrency(
  int amount,
  String localeName, [
  String currency = 'RWF',
]) {
  return '${NumberFormat.decimalPattern(localeName).format(amount)} $currency';
}

String signedCurrency(
  int amount,
  String localeName, [
  String currency = 'RWF',
]) {
  final prefix = amount >= 0 ? '+' : '-';
  return '$prefix${formatCurrency(amount.abs(), localeName, currency)}';
}

String spokenCurrency(
  int amount,
  String localeName, [
  String currency = 'RWF',
]) {
  final spokenCurrency = switch (currency) {
    'RWF' => 'Rwandan francs',
    _ => currency,
  };
  return '${NumberFormat.decimalPattern(localeName).format(amount)} $spokenCurrency';
}

String signedSpokenCurrency(
  int amount,
  String localeName, [
  String currency = 'RWF',
]) {
  final direction = amount >= 0 ? 'plus' : 'minus';
  return '$direction ${spokenCurrency(amount.abs(), localeName, currency)}';
}
