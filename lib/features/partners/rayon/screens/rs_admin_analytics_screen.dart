import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/cool_card.dart';
import '../providers/rs_admin_provider.dart';
import '../widgets/rs_admin_shell.dart';

/// RS Fan Analytics Dashboard — engagement overview, revenue, tier breakdown.
class RsAdminAnalyticsScreen extends ConsumerWidget {
  const RsAdminAnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analyticsAsync = ref.watch(rsAdminFanAnalyticsProvider);
    final ordersAsync = ref.watch(rsAdminOrdersProvider);
    final membersAsync = ref.watch(rsAdminMembersProvider);

    return RsAdminShell(
      title: 'Analytics',
      subtitle: 'Fan engagement & revenue overview',
      child: analyticsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (data) {
          final moneyFmt = NumberFormat.decimalPattern('en_US');

          // Safely compute shop revenue from orders
          final shopRevenue = ordersAsync.whenOrNull(
            data: (orders) => orders
                .where((o) => o.status.name != 'cancelled')
                .fold<int>(0, (sum, o) => sum + o.total),
          ) ?? 0;

          // Tier breakdown from members
          final tierCounts = <String, int>{
            'Blue': 0, 'Silver': 0, 'Gold': 0, 'Platinum': 0,
          };
          membersAsync.whenOrNull(
            data: (members) {
              for (final m in members) {
                final tier = m.tier.name[0].toUpperCase() + m.tier.name.substring(1);
                tierCounts[tier] = (tierCounts[tier] ?? 0) + 1;
              }
            },
          );

          final metrics = <_MetricData>[
            _MetricData(
              'Total Members',
              '${data['total_members'] ?? 0}',
              Icons.people_rounded,
            ),
            _MetricData(
              'Active Memberships',
              '${data['active_memberships'] ?? 0}',
              Icons.card_membership_rounded,
            ),
            _MetricData(
              'Tickets Sold',
              '${data['total_tickets_sold'] ?? 0}',
              Icons.confirmation_number_rounded,
            ),
            _MetricData(
              'Ticket Revenue',
              '${moneyFmt.format((data['ticket_revenue'] as num?)?.toInt() ?? 0)} RWF',
              Icons.account_balance_wallet_rounded,
            ),
            _MetricData(
              'Shop Revenue',
              '${moneyFmt.format(shopRevenue)} RWF',
              Icons.shopping_bag_rounded,
            ),
            _MetricData(
              'Total Matches',
              '${data['total_matches'] ?? 0}',
              Icons.sports_soccer_rounded,
            ),
            _MetricData(
              'Upcoming Matches',
              '${data['upcoming_matches'] ?? 0}',
              Icons.calendar_today_rounded,
            ),
            _MetricData(
              'Membership Packages',
              '${data['membership_packages'] ?? 0}',
              Icons.workspace_premium_rounded,
            ),
            _MetricData(
              'Notifications Sent',
              '${data['notifications_sent'] ?? 0}',
              Icons.notifications_rounded,
            ),
          ];

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // KPI grid
              ...metrics.map((metric) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: CoolCard(
                    borderColor: AppColors.border2,
                    child: Row(
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: AppColors.rsBlueGlow,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppColors.rsBlueBorder),
                          ),
                          alignment: Alignment.center,
                          child: Icon(metric.icon, size: 22, color: AppColors.rsBlueLight),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                metric.label,
                                style: GoogleFonts.barlow(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.text2,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                metric.value,
                                style: GoogleFonts.barlow(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.text,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),

              // Tier breakdown
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  'Members by Tier',
                  style: GoogleFonts.barlow(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              CoolCard(
                borderColor: AppColors.border2,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: tierCounts.entries.map((e) {
                    final icon = switch (e.key) {
                      'Blue' => Icons.favorite_rounded,
                      'Silver' => Icons.workspace_premium_rounded,
                      'Gold' => Icons.emoji_events_rounded,
                      'Platinum' => Icons.diamond_rounded,
                      _ => Icons.person,
                    };
                    final color = switch (e.key) {
                      'Blue' => AppColors.blue,
                      'Silver' => Colors.grey.shade400,
                      'Gold' => AppColors.rsGold,
                      'Platinum' => Colors.purple.shade300,
                      _ => AppColors.text2,
                    };
                    return Column(
                      children: [
                        Icon(icon, size: 24, color: color),
                        const SizedBox(height: 4),
                        Text(
                          '${e.value}',
                          style: GoogleFonts.barlow(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppColors.text,
                          ),
                        ),
                        Text(
                          e.key,
                          style: GoogleFonts.barlow(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: AppColors.text3,
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MetricData {
  const _MetricData(this.label, this.value, this.icon);
  final String label;
  final String value;
  final IconData icon;
}
