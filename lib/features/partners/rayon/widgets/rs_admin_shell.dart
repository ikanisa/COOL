import 'package:flutter/material.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/cool_foundations.dart';
import '../../../../core/theme/rs_colors.dart';
import '../../../../shared/widgets/cool_card.dart';
import '../../../../shared/widgets/cool_screen_background.dart';
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
    final theme = Theme.of(context);

    return CoolScreenBackground(
      primaryColor: RsColors.rsBlue,
      secondaryColor: RsColors.rsGold,
      showGlow: false,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: buildPartnerBackButton(
            context,
            fallbackLocation: fallbackLocation,
            color: RsColors.rsWhite,
          ),
          actions: buildPartnerAppBarActions(
            context,
            homeColor: RsColors.rsWhite,
          ),
        ),
        floatingActionButton: floatingActionButton,
        body: SafeArea(
          top: false,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final maxWidth = expandBody
                  ? CoolResponsive.maxContentWidthForWidth(constraints.maxWidth)
                  : 840.0;
              final horizontalPadding =
                  CoolResponsive.horizontalPaddingForWidth(
                    constraints.maxWidth,
                  );

              return SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  0,
                  horizontalPadding,
                  112,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxWidth),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'RAYON SPORTS COMMAND',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: Colors.white.withValues(alpha: 0.72),
                            letterSpacing: 0.6,
                          ),
                        ),
                        const SizedBox(height: CoolSpace.x3),
                        Text(
                          title,
                          style: context.coolText.rayonCondensed(
                            const TextStyle(fontSize: 44),
                            fontWeight: FontWeight.w900,
                            color: RsColors.rsWhite,
                            height: 0.94,
                            letterSpacing: 0.1,
                          ),
                        ),
                        const SizedBox(height: CoolSpace.x6),
                        CoolCard(
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Color(0xFF05172F),
                              Color(0xFF0A2550),
                              Color(0xFF11376A),
                            ],
                          ),
                          borderColor: RsColors.rsBlueBorder,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                subtitle,
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.88),
                                ),
                              ),
                              if (metrics.isNotEmpty) ...[
                                const SizedBox(height: CoolSpace.x6),
                                Wrap(
                                  spacing: CoolSpace.x3,
                                  runSpacing: CoolSpace.x3,
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
                        if (controls != null) ...[
                          const SizedBox(height: CoolSpace.x5),
                          controls!,
                        ],
                        const SizedBox(height: CoolSpace.x6),
                        child,
                      ],
                    ),
                  ),
                ),
              );
            },
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
      constraints: const BoxConstraints(minWidth: 112),
      padding: const EdgeInsets.symmetric(
        horizontal: CoolSpace.x4,
        vertical: CoolSpace.x4,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(CoolRadii.md),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: context.coolText.mono(
              const TextStyle(fontSize: 20),
              fontWeight: FontWeight.w800,
              color: RsColors.rsGoldLight,
            ),
          ),
          const SizedBox(height: CoolSpace.x1),
          Text(
            label.toUpperCase(),
            style: context.coolText.rayon(
              const TextStyle(fontSize: 13),
              fontWeight: FontWeight.w700,
              color: Colors.white.withValues(alpha: 0.78),
            ),
          ),
        ],
      ),
    );
  }
}
