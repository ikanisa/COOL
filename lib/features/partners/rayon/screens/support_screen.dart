import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/rs_colors.dart';
import '../../../../core/theme/rs_text_styles.dart';
import '../../../../shared/widgets/cool_card.dart';
import '../../../../shared/widgets/cool_screen_background.dart';
import '../../../../shared/widgets/cool_skeleton.dart';
import '../../../../shared/widgets/rs_initiative_card.dart';

import '../rayon_payment.dart';
import '../../providers/rayon_sports_provider.dart';
import '../../widgets/partner_navigation.dart';

class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        final initiativesAsync = ref.watch(rayonInitiativesProvider);
        final summaryAsync = ref.watch(rayonInitiativesSummaryProvider);
        final paymentRoute = ref.watch(rayonPaymentRouteProvider).valueOrNull;

        return Scaffold(
          backgroundColor: AppColors.bg,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            leading: buildPartnerBackButton(
              context,
              fallbackLocation: AppRoutes.rayonHome,
            ),
            title: Text(
              'Support Club',
              style: RsTextStyles.sectionTitle(color: RsColors.rsWhite),
            ),
            actions: buildPartnerAppBarActions(context),
          ),
          body: CoolScreenBackground(
            primaryColor: RsColors.rsBlue,
            secondaryColor: RsColors.rsGold,
            child: SafeArea(
              top: false,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        _SupportIntroCard(
                          summary: summaryAsync.valueOrNull,
                          paymentRoute: paymentRoute,
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'Active Causes',
                          style: RsTextStyles.sectionTitle(
                            color: RsColors.rsWhite,
                          ),
                        ),
                        const SizedBox(height: 14),
                      ]),
                    ),
                  ),
                  ...initiativesAsync.when(
                    loading: () => <Widget>[
                      const SliverPadding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        sliver: SliverToBoxAdapter(child: CoolSkeletonList()),
                      ),
                    ],
                    error: (error, stackTrace) => <Widget>[
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        sliver: SliverToBoxAdapter(
                          child: _StateCard(
                            icon: Icons.warning_amber_rounded,
                            title: 'Unable to load initiatives',
                            subtitle: 'Pull to retry or check your connection.',
                            actionLabel: 'Retry',
                            onTap: () =>
                                ref.invalidate(rayonInitiativesProvider),
                          ),
                        ),
                      ),
                    ],
                    data: (initiatives) {
                      if (initiatives.isEmpty) {
                        return const <Widget>[
                          SliverPadding(
                            padding: EdgeInsets.symmetric(horizontal: 16),
                            sliver: SliverToBoxAdapter(
                              child: _EmptyInitiativesState(),
                            ),
                          ),
                        ];
                      }

                      return <Widget>[
                        SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate((
                              context,
                              index,
                            ) {
                              final initiative = initiatives[index];
                              return Padding(
                                padding: EdgeInsets.only(
                                  bottom: index == initiatives.length - 1
                                      ? 0
                                      : 14,
                                ),
                                child: RsInitiativeCard(
                                  initiative: initiative,
                                  onTap: () => context.push(
                                    '/partners/rayon-sports/support/${initiative.id}',
                                  ),
                                  onSupportTap: () => context.push(
                                    '/partners/rayon-sports/support/${initiative.id}',
                                  ),
                                ),
                              );
                            }, childCount: initiatives.length),
                          ),
                        ),
                      ];
                    },
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 96)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SupportIntroCard extends StatelessWidget {
  const _SupportIntroCard({required this.summary, this.paymentRoute});

  final RayonInitiativesSummary? summary;
  final PartnerPaymentRoute? paymentRoute;

  @override
  Widget build(BuildContext context) {
    return CoolCard(
      borderColor: AppColors.border2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Back club causes.',
            style: GoogleFonts.barlowCondensed(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: RsColors.rsWhite,
              height: 1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            paymentRoute == null
                ? 'Checkout opens once partner payment routing is active.'
                : 'Support club projects through ${paymentRoute!.providerLabel}.',
            style: GoogleFonts.barlow(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppColors.text2,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _SummaryMetric(
                  value: summary == null
                      ? '--'
                      : _formatRwf(summary!.totalRaised),
                  label: 'Raised',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SummaryMetric(
                  value: summary == null
                      ? '--'
                      : _compactCount(summary!.totalSupporters),
                  label: 'Supporters',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SummaryMetric(
                  value: summary == null ? '--' : '${summary!.activeCauses}',
                  label: 'Causes',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: GoogleFonts.dmMono(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: RsColors.rsWhite,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: GoogleFonts.barlow(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: AppColors.text3,
          ),
        ),
      ],
    );
  }
}

class _EmptyInitiativesState extends StatelessWidget {
  const _EmptyInitiativesState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36),
      child: Center(
        child: Column(
          children: [
            Icon(
              Icons.stadium_rounded,
              size: 52,
              color: AppColors.rsWhite.withValues(alpha: 0.8),
            ),
            const SizedBox(height: 14),
            Text(
              'No active initiatives right now',
              style: RsTextStyles.sectionTitle(color: RsColors.rsWhite),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Check back soon',
              style: GoogleFonts.barlow(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.text2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StateCard extends StatelessWidget {
  const _StateCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return CoolCard(
      borderColor: AppColors.border2,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            Icon(icon, size: 42, color: AppColors.text2),
            const SizedBox(height: 10),
            Text(
              title,
              style: RsTextStyles.sectionTitle(color: RsColors.rsWhite),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: GoogleFonts.barlow(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.text2,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            TextButton(
              onPressed: onTap,
              child: Text(
                actionLabel,
                style: GoogleFonts.barlow(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.accent,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatRwf(int amount) {
  return 'RWF ${NumberFormat.decimalPattern('en').format(amount)}';
}

String _compactCount(int count) {
  if (count >= 1000000) {
    return NumberFormat.compact(locale: 'en').format(count);
  }
  if (count >= 1000) {
    return NumberFormat.compact(locale: 'en').format(count);
  }
  return '$count';
}
