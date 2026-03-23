import 'package:flutter/material.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_error_view.dart';
import '../../../shared/widgets/cool_skeleton.dart';

class OverviewLoadingCard extends StatelessWidget {
  const OverviewLoadingCard({this.useCard = true, super.key});

  final bool useCard;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    const content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CoolSkeleton(width: 120, height: 14, borderRadius: 7),
        SizedBox(height: 18),
        CoolSkeleton(width: double.infinity, height: 38, borderRadius: 12),
        SizedBox(height: 18),
        CoolSkeleton(width: double.infinity, height: 26, borderRadius: 13),
      ],
    );

    if (!useCard) {
      return content;
    }

    return CoolCard(backgroundColor: colors.elevatedBackground, child: content);
  }
}

class ActivityLoadingCard extends StatelessWidget {
  const ActivityLoadingCard({this.useCard = true, super.key});

  final bool useCard;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    const content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CoolSkeleton(width: double.infinity, height: 16, borderRadius: 8),
        SizedBox(height: CoolSpace.x3),
        CoolSkeleton(width: double.infinity, height: 16, borderRadius: 8),
        SizedBox(height: CoolSpace.x3),
        CoolSkeleton(width: 160, height: 16, borderRadius: 8),
      ],
    );

    if (!useCard) {
      return content;
    }

    return CoolCard(backgroundColor: colors.elevatedBackground, child: content);
  }
}

class OverviewErrorCard extends StatelessWidget {
  const OverviewErrorCard({
    required this.onRetry,
    this.useCard = true,
    super.key,
  });

  final VoidCallback onRetry;
  final bool useCard;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final content = CoolErrorView(
      subtitle: context.l10n.homeLoadErrorMessage,
      onRetry: onRetry,
      compact: true,
    );

    if (!useCard) {
      return content;
    }

    return CoolCard(backgroundColor: colors.elevatedBackground, child: content);
  }
}
