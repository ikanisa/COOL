import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/cool_card.dart';
import '../../widgets/partner_navigation.dart';

class RsAdminMetric {
  const RsAdminMetric({required this.label, required this.value});

  final String label;
  final String value;
}

class RsAdminShell extends StatelessWidget {
  const RsAdminShell({
    required this.title,
    required this.subtitle,
    required this.child,
    this.metrics = const <RsAdminMetric>[],
    this.controls,
    this.floatingActionButton,
    this.expandBody = true,
    this.fallbackLocation = AppRoutes.adminRayon,
    super.key,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final List<RsAdminMetric> metrics;
  final Widget? controls;
  final Widget? floatingActionButton;
  final bool expandBody;
  final String fallbackLocation;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: buildPartnerBackButton(
          context,
          fallbackLocation: fallbackLocation,
          color: Colors.white,
        ),
        actions: buildPartnerAppBarActions(context, homeColor: Colors.white),
      ),
      floatingActionButton: floatingActionButton,
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 96),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.barlowCondensed(
                  fontSize: 42,
                  fontWeight: FontWeight.w900,
                  color: AppColors.rsWhite,
                  height: 1.0,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 24),
              CoolCard(
                borderColor: AppColors.border2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      subtitle,
                      style: GoogleFonts.barlow(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppColors.text2,
                        height: 1.45,
                      ),
                    ),
                    if (metrics.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: metrics
                            .map(
                              (metric) => _MetricChip(
                                label: metric.label,
                                value: metric.value,
                              ),
                            )
                            .toList(growable: false),
                      ),
                    ],
                  ],
                ),
              ),
              if (controls != null) ...[const SizedBox(height: 16), controls!],
              const SizedBox(height: 24),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border2),
      ),
      child: Text(
        '$value $label',
        style: GoogleFonts.dmMono(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppColors.rsBluePale,
        ),
      ),
    );
  }
}
