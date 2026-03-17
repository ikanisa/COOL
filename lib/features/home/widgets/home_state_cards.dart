import 'package:flutter/material.dart';

import '../../../../core/l10n/l10n.dart';
import '../../../../core/theme/cool_palette.dart';
import '../../../../shared/widgets/cool_card.dart';
import '../../../../shared/widgets/cool_error_view.dart';
import '../../../../shared/widgets/cool_skeleton.dart';

class OverviewLoadingCard extends StatelessWidget {
  const OverviewLoadingCard({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    return CoolCard(
      backgroundColor: palette.surface,
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CoolSkeleton(width: 120, height: 14, borderRadius: 7),
          SizedBox(height: 18),
          CoolSkeleton(width: double.infinity, height: 38, borderRadius: 12),
          SizedBox(height: 18),
          CoolSkeleton(width: double.infinity, height: 26, borderRadius: 13),
        ],
      ),
    );
  }
}

class ActivityLoadingCard extends StatelessWidget {
  const ActivityLoadingCard({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    return CoolCard(
      backgroundColor: palette.surface,
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CoolSkeleton(width: double.infinity, height: 16, borderRadius: 8),
          SizedBox(height: 12),
          CoolSkeleton(width: double.infinity, height: 16, borderRadius: 8),
          SizedBox(height: 12),
          CoolSkeleton(width: 160, height: 16, borderRadius: 8),
        ],
      ),
    );
  }
}

class OverviewErrorCard extends StatelessWidget {
  const OverviewErrorCard({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    return CoolCard(
      backgroundColor: palette.surface,
      child: CoolErrorView(
        subtitle: context.l10n.homeLoadErrorMessage,
        onRetry: onRetry,
        compact: true,
      ),
    );
  }
}
