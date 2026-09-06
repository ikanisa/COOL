import 'package:flutter/material.dart';

import '../../app/theme/collect_colors.dart';
import '../../app/theme/collect_runtime_assets.dart';
import '../../app/theme/collect_typography.dart';

/// Public marketing composition only; member and operator UI stay in Inter.
class PublicMarketingHero extends StatelessWidget {
  const PublicMarketingHero({
    required this.title,
    required this.intro,
    required this.actions,
    super.key,
  });

  final String title;
  final String intro;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 720;
        final enlarged = MediaQuery.textScalerOf(context).scale(1) > 1.3;
        final highContrast = MediaQuery.highContrastOf(context);
        final copyEdge = ((650 + 48) / constraints.maxWidth).clamp(0.0, 1.0);
        const white = CollectColors.publicWhite;
        return ColoredBox(
          color: CollectColors.referenceAccountBlue,
          child: Stack(
            children: [
              if (!highContrast)
                Positioned.fill(
                  child: Image.asset(
                    CollectRuntimeAssets.marketingSky,
                    fit: BoxFit.cover,
                    excludeFromSemantics: true,
                  ),
                ),
              if (!highContrast)
                Positioned(
                  right: compact ? (constraints.maxWidth / 2) - 276 : -40,
                  bottom: compact ? 0 : -40,
                  width: compact ? 920 : 1250,
                  child: Image.asset(
                    CollectRuntimeAssets.marketingEditorial,
                    excludeFromSemantics: true,
                  ),
                ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: compact
                          ? Alignment.topCenter
                          : Alignment.centerLeft,
                      end: compact
                          ? Alignment.bottomCenter
                          : Alignment.centerRight,
                      colors: compact
                          ? [
                              CollectColors.publicHeroScrim.withValues(
                                alpha: 0.8,
                              ),
                              CollectColors.publicHeroScrim.withValues(
                                alpha: 0.68,
                              ),
                              CollectColors.publicHeroScrim.withValues(
                                alpha: 0.24,
                              ),
                              CollectColors.transparentColor,
                            ]
                          : [
                              CollectColors.publicHeroScrim.withValues(
                                alpha: 0.8,
                              ),
                              CollectColors.publicHeroScrim.withValues(
                                alpha: 0.68,
                              ),
                              CollectColors.transparentColor,
                            ],
                      stops: compact
                          ? const [0, 0.6, 0.82, 1]
                          : [0, copyEdge, 1],
                    ),
                  ),
                ),
              ),
              ConstrainedBox(
                constraints: BoxConstraints(minHeight: compact ? 1050 : 780),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    compact ? 20 : 48,
                    compact ? 48 : 112,
                    compact ? 20 : 48,
                    compact ? 480 : (enlarged ? 360 : 80),
                  ),
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: compact ? 430 : 650,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Semantics(
                            header: true,
                            child: Text(
                              title,
                              style: CollectTypography.marketingHeading(
                                white,
                                compact: compact,
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 520),
                            child: Text(
                              intro,
                              style: CollectTypography.marketingBody(white),
                            ),
                          ),
                          const SizedBox(height: 24),
                          Wrap(spacing: 12, runSpacing: 12, children: actions),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
