import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/cool_async_view.dart';
import '../../../shared/widgets/cool_skeleton.dart';
import '../providers/admin_providers.dart';
import '../../../core/l10n/l10n.dart';

/// System-wide analytics dashboard for platform admins.
class SystemAnalyticsScreen extends ConsumerWidget {
  const SystemAnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analyticsAsync = ref.watch(platformAnalyticsProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        automaticallyImplyLeading: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          tooltip: context.l10n.back,
          icon: Icon(Icons.arrow_back_rounded, color: AppColors.text),
        ),
      ),
      body: CoolAsyncView<Map<String, dynamic>>(
        value: analyticsAsync,
        onRetry: () => ref.invalidate(platformAnalyticsProvider),
        loadingWidget: const Padding(
          padding: EdgeInsets.fromLTRB(18, 0, 18, 16),
          child: CoolSkeletonList(itemCount: 6),
        ),
        emptyCheck: (a) => a.isEmpty,
        builder: (data) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 32),
            children: [
              Text(
                'System Analytics',
                style: GoogleFonts.dmSans(
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  color: AppColors.text,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Platform-wide metrics at a glance',
                style: GoogleFonts.dmSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: AppColors.text3,
                ),
              ),
              const SizedBox(height: 24),

              // ── Core counts ────────────────────────────────────────
              const _SectionHeader('Core Counts'),
              const SizedBox(height: 12),
              _MetricGrid(metrics: [
                _Metric('Users', _fmt(data['total_users']),
                    Icons.person_rounded, AppColors.blue),
                _Metric('Real Users', _fmt(data['real_users']),
                    Icons.verified_user_rounded, Colors.green),
                _Metric('Mock Users', _fmt(data['mock_users']),
                    Icons.smart_toy_rounded, Colors.orange),
                _Metric('Admins', _fmt(data['total_admins']),
                    Icons.admin_panel_settings_rounded, Colors.purple),
                _Metric('Drivers', _fmt(data['total_drivers']),
                    Icons.directions_car_rounded, Colors.teal),
                _Metric('Partners', _fmt(data['total_partners']),
                    Icons.handshake_rounded, Colors.indigo),
                _Metric('Groups', _fmt(data['total_groups']),
                    Icons.group_rounded, AppColors.blue),
                _Metric('Trips', _fmt(data['total_trips']),
                    Icons.route_rounded, Colors.deepOrange),
              ]),
              const SizedBox(height: 28),

              // ── Growth ─────────────────────────────────────────────
              const _SectionHeader('Growth'),
              const SizedBox(height: 12),
              _MetricGrid(metrics: [
                _Metric('Signups (7d)', _fmt(data['signups_7d']),
                    Icons.trending_up_rounded, Colors.green),
                _Metric('Signups (30d)', _fmt(data['signups_30d']),
                    Icons.show_chart_rounded, AppColors.blue),
                _Metric('Trips (7d)', _fmt(data['trips_7d']),
                    Icons.local_taxi_rounded, Colors.deepOrange),
                _Metric('Active Partners', _fmt(data['active_partners']),
                    Icons.storefront_rounded, Colors.indigo),
              ]),
              const SizedBox(height: 28),

              // ── Role distribution ──────────────────────────────────
              const _SectionHeader('Admin Role Distribution'),
              const SizedBox(height: 12),
              _DistributionCard(
                data: _asStringIntMap(data['role_distribution']),
                emptyLabel: 'No roles assigned yet',
              ),
              const SizedBox(height: 28),

              // ── Event distribution ─────────────────────────────────
              const _SectionHeader('Event Distribution (30d)'),
              const SizedBox(height: 12),
              _DistributionCard(
                data: _asStringIntMap(data['event_distribution']),
                emptyLabel: 'No events recorded',
              ),
              const SizedBox(height: 28),

              // ── Audit ──────────────────────────────────────────────
              const _SectionHeader('Audit'),
              const SizedBox(height: 12),
              _MetricGrid(metrics: [
                _Metric('Admin Actions (7d)', _fmt(data['audit_actions_7d']),
                    Icons.history_rounded, Colors.amber),
              ]),
            ],
          );
        },
      ),
    );
  }

  static String _fmt(dynamic value) {
    if (value == null) return '—';
    if (value is num) return value.toInt().toString();
    return value.toString();
  }

  static Map<String, int> _asStringIntMap(dynamic value) {
    if (value is! Map) return {};
    return value.map((k, v) => MapEntry(
          k.toString(),
          v is num ? v.toInt() : int.tryParse(v.toString()) ?? 0,
        ));
  }
}

// ═══════════════════════════════════════════════════════════════
// Sub-widgets
// ═══════════════════════════════════════════════════════════════

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: GoogleFonts.dmSans(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: AppColors.text,
      ),
    );
  }
}

class _Metric {
  const _Metric(this.label, this.value, this.icon, this.color);
  final String label;
  final String value;
  final IconData icon;
  final Color color;
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.metrics});
  final List<_Metric> metrics;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 2.0,
      ),
      itemCount: metrics.length,
      itemBuilder: (context, index) {
        final m = metrics[index];
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: m.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(m.icon, size: 18, color: m.color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      m.value,
                      style: GoogleFonts.dmSans(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.text,
                      ),
                    ),
                    Text(
                      m.label,
                      style: GoogleFonts.dmSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: AppColors.text3,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DistributionCard extends StatelessWidget {
  const _DistributionCard({required this.data, required this.emptyLabel});
  final Map<String, int> data;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Text(
          emptyLabel,
          style: GoogleFonts.dmSans(
            fontSize: 13,
            fontWeight: FontWeight.w400,
            color: AppColors.text3,
          ),
        ),
      );
    }

    final total = data.values.fold<int>(0, (a, b) => a + b);
    final entries = data.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          for (final entry in entries) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    entry.key,
                    style: GoogleFonts.dmSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text,
                    ),
                  ),
                ),
                Text(
                  '${entry.value}',
                  style: GoogleFonts.dmSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: total > 0 ? entry.value / total : 0,
                minHeight: 6,
                backgroundColor: AppColors.border,
                valueColor:
                    const AlwaysStoppedAnimation<Color>(AppColors.blue),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}