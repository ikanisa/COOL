import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../core/l10n/l10n.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/cool_foundations.dart';
import '../../../../shared/widgets/cool_async_view.dart';
import '../../../../shared/widgets/cool_card.dart';
import '../models/rs_models.dart';
import '../providers/rs_admin_provider.dart';
import '../widgets/rs_admin_shell.dart';

/// RS fan analytics dashboard.
class RsAdminAnalyticsScreen extends ConsumerWidget {
  const RsAdminAnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analyticsAsync = ref.watch(rsAdminFanAnalyticsProvider);
    final ordersAsync = ref.watch(rsAdminOrdersProvider);
    final membersAsync = ref.watch(rsAdminMembersProvider);

    final shopRevenueLabel = ordersAsync.whenOrNull(
      data: (orders) => _money(
        orders
            .where((order) => order.status != OrderStatus.cancelled)
            .fold<int>(0, (sum, order) => sum + order.total),
      ),
    );

    return RsAdminShell(
      title: context.l10n.analytics,
      subtitle:
          'Monitor revenue, supporter growth, and matchday performance from one executive scoreboard.',
      metrics: [
        RsAdminMetric(
          label: 'members',
          value:
              membersAsync.whenOrNull(data: (members) => '${members.length}') ??
              '...',
        ),
        RsAdminMetric(
          label: 'orders',
          value:
              ordersAsync.whenOrNull(data: (orders) => '${orders.length}') ??
              '...',
        ),
        RsAdminMetric(label: 'shop rev', value: shopRevenueLabel ?? '...'),
      ],
      child: CoolAsyncView<Map<String, dynamic>>(
        value: analyticsAsync,
        onRetry: () => ref.invalidate(rsAdminFanAnalyticsProvider),
        builder: (data) {
          final colors = context.coolSemanticColors;
          final moneyFmt = NumberFormat.decimalPattern('en_US');
          final ticketRevenue = (data['ticket_revenue'] as num?)?.toInt() ?? 0;
          final shopRevenue =
              ordersAsync.whenOrNull(
                data: (orders) => orders
                    .where((order) => order.status != OrderStatus.cancelled)
                    .fold<int>(0, (sum, order) => sum + order.total),
              ) ??
              0;
          final totalRevenue = ticketRevenue + shopRevenue;

          final tierCounts = <String, int>{
            'Blue': 0,
            'Silver': 0,
            'Gold': 0,
            'Platinum': 0,
          };
          membersAsync.whenOrNull(
            data: (members) {
              for (final member in members) {
                final tier =
                    member.tier.name[0].toUpperCase() +
                    member.tier.name.substring(1);
                tierCounts[tier] = (tierCounts[tier] ?? 0) + 1;
              }
            },
          );

          final metrics = <_MetricData>[
            _MetricData(
              label: 'Total Members',
              value: '${data['total_members'] ?? 0}',
              icon: Icons.people_alt_rounded,
              tone: colors.teamSurface,
            ),
            _MetricData(
              label: 'Active Memberships',
              value: '${data['active_memberships'] ?? 0}',
              icon: Icons.card_membership_rounded,
              tone: colors.proximitySurface,
            ),
            _MetricData(
              label: 'Tickets Sold',
              value: '${data['total_tickets_sold'] ?? 0}',
              icon: Icons.confirmation_number_rounded,
              tone: colors.routeSurface,
            ),
            _MetricData(
              label: 'Upcoming Matches',
              value: '${data['upcoming_matches'] ?? 0}',
              icon: Icons.calendar_month_rounded,
              tone: colors.operationalSurface,
            ),
            _MetricData(
              label: 'Membership Packages',
              value: '${data['membership_packages'] ?? 0}',
              icon: Icons.workspace_premium_rounded,
              tone: colors.analyticsSurface,
            ),
            _MetricData(
              label: 'Notifications Sent',
              value: '${data['notifications_sent'] ?? 0}',
              icon: Icons.notifications_active_rounded,
              tone: colors.contactSurface,
            ),
          ];

          return LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 560;
              final cardWidth = isWide
                  ? (constraints.maxWidth - CoolSpace.x3) / 2
                  : constraints.maxWidth;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CoolCard(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AppColors.rsBlue.withValues(alpha: 0.94),
                        const Color(0xFF041A39),
                      ],
                    ),
                    borderColor: AppColors.rsBlueBorder,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Executive Scoreboard',
                          style: GoogleFonts.barlow(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                            color: Colors.white.withValues(alpha: 0.76),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _money(totalRevenue),
                          style: GoogleFonts.barlowCondensed(
                            fontSize: 44,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            height: 0.92,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Total live platform revenue across ticketing and shop operations.',
                          style: GoogleFonts.dmSans(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.white.withValues(alpha: 0.84),
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _SignalPill(
                              label: 'Ticket Revenue',
                              value: '${moneyFmt.format(ticketRevenue)} RWF',
                              foreground: Colors.white,
                              background: Colors.white.withValues(alpha: 0.08),
                              border: Colors.white.withValues(alpha: 0.12),
                            ),
                            _SignalPill(
                              label: 'Shop Revenue',
                              value: '${moneyFmt.format(shopRevenue)} RWF',
                              foreground: Colors.white,
                              background: Colors.white.withValues(alpha: 0.08),
                              border: Colors.white.withValues(alpha: 0.12),
                            ),
                            _SignalPill(
                              label: 'Total Matches',
                              value: '${data['total_matches'] ?? 0}',
                              foreground: Colors.white,
                              background: Colors.white.withValues(alpha: 0.08),
                              border: Colors.white.withValues(alpha: 0.12),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: CoolSpace.x5),
                  Text(
                    'Operational Signals',
                    style: GoogleFonts.dmSans(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: colors.primaryText,
                    ),
                  ),
                  const SizedBox(height: CoolSpace.x3),
                  Wrap(
                    spacing: CoolSpace.x3,
                    runSpacing: CoolSpace.x3,
                    children: metrics
                        .map(
                          (metric) => SizedBox(
                            width: cardWidth,
                            child: _AnalyticsMetricCard(metric: metric),
                          ),
                        )
                        .toList(growable: false),
                  ),
                  const SizedBox(height: CoolSpace.x5),
                  Text(
                    'Members by Tier',
                    style: GoogleFonts.dmSans(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: colors.primaryText,
                    ),
                  ),
                  const SizedBox(height: CoolSpace.x3),
                  CoolCard(
                    backgroundColor: colors.teamSurface,
                    borderColor: colors.borderStrong,
                    child: Wrap(
                      spacing: CoolSpace.x3,
                      runSpacing: CoolSpace.x3,
                      children: tierCounts.entries
                          .map(
                            (entry) => _TierCountCard(
                              label: entry.key,
                              count: entry.value,
                            ),
                          )
                          .toList(growable: false),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _MetricData {
  const _MetricData({
    required this.label,
    required this.value,
    required this.icon,
    required this.tone,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color tone;
}

class _AnalyticsMetricCard extends StatelessWidget {
  const _AnalyticsMetricCard({required this.metric});

  final _MetricData metric;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    return CoolCard(
      backgroundColor: metric.tone,
      borderColor: colors.borderStrong,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.rsBlue.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(CoolRadii.lg),
              border: Border.all(
                color: AppColors.rsBlue.withValues(alpha: 0.2),
              ),
            ),
            alignment: Alignment.center,
            child: Icon(metric.icon, size: 22, color: AppColors.rsBlueLight),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  metric.label,
                  style: GoogleFonts.dmSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: colors.secondaryText,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  metric.value,
                  style: GoogleFonts.barlowCondensed(
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    color: colors.primaryText,
                    height: 0.95,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TierCountCard extends StatelessWidget {
  const _TierCountCard({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final color = switch (label) {
      'Blue' => AppColors.rsBlueLight,
      'Silver' => const Color(0xFFBFC6CF),
      'Gold' => AppColors.rsGold,
      'Platinum' => const Color(0xFFE7E3DD),
      _ => colors.secondaryText,
    };

    return Container(
      constraints: const BoxConstraints(minWidth: 132),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: colors.cardSurfaceStrong,
        borderRadius: BorderRadius.circular(CoolRadii.lg),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$count',
            style: GoogleFonts.barlowCondensed(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: colors.primaryText,
              height: 0.95,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _SignalPill extends StatelessWidget {
  const _SignalPill({
    required this.label,
    required this.value,
    required this.foreground,
    required this.background,
    required this.border,
  });

  final String label;
  final String value;
  final Color foreground;
  final Color background;
  final Color border;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Text(
        '$label: $value',
        style: GoogleFonts.dmSans(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: foreground,
        ),
      ),
    );
  }
}

String _money(int value) =>
    '${NumberFormat.decimalPattern('en_US').format(value)} RWF';
