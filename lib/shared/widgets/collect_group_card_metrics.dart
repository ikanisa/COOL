part of 'collect_group_cards.dart';

class _GroupEditorialDetails extends StatelessWidget {
  const _GroupEditorialDetails({
    required this.collection,
    required this.summary,
    this.primaryAction,
  });

  final CollectCollection collection;
  final CollectionSummary summary;
  final Widget? primaryAction;

  @override
  Widget build(BuildContext context) {
    final foreground = context.collectColors.onImagePrimary;
    const ink = CollectGroupCardTokens.footerInk;
    final topInk = ink.withValues(
      alpha: MediaQuery.highContrastOf(context) ? 1 : 0.94,
    );
    // The fade follows the content height, so even a long enlarged title is
    // backed by dark ink. The photo above remains visible at every text scale.
    return CustomPaint(
      painter: _GroupCaptionScrim(topInk),
      child: Padding(
        padding: CollectGroupCardTokens.padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              collection.title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: foreground,
                fontSize: CollectGroupCardTokens.titleSize,
                fontWeight: CollectTypography.weightBold,
                height: CollectGroupCardTokens.titleLeading,
              ),
            ),
            CollectSpacing.gap4,
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _GroupEditorialMetric(
                        icon: CollectIcons.money,
                        value: formatCurrencyTotals(
                          summary.totalsByCurrency,
                          separator: '\n',
                        ),
                        semanticLabel:
                            'Total collected ${formatCurrencyTotals(summary.totalsByCurrency, separator: ", ")}',
                      ),
                      CollectSpacing.gap4,
                      _GroupEditorialMetric(
                        icon: CollectIcons.people,
                        value: summary.supporterCountLabel,
                        semanticLabel: summary.supporterCountSemantics,
                      ),
                    ],
                  ),
                ),
                if (primaryAction != null) ...[
                  CollectSpacing.gapW12,
                  primaryAction!,
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A single painted fade avoids a seam where translucent rectangles meet.
class _GroupCaptionScrim extends CustomPainter {
  const _GroupCaptionScrim(this.topInk);

  final Color topInk;

  @override
  void paint(Canvas canvas, Size size) {
    const fade = CollectGroupCardTokens.fadeHeight;
    final rect = Rect.fromLTWH(0, -fade, size.width, size.height + fade);
    final gradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        topInk.withValues(alpha: 0),
        topInk,
        CollectGroupCardTokens.footerInk,
      ],
      stops: [0, fade / rect.height, 1],
    );
    canvas.drawRect(rect, Paint()..shader = gradient.createShader(rect));
  }

  @override
  bool shouldRepaint(_GroupCaptionScrim oldDelegate) =>
      oldDelegate.topInk != topInk;
}

class _GroupEditorialMetric extends StatelessWidget {
  const _GroupEditorialMetric({
    required this.icon,
    required this.value,
    required this.semanticLabel,
  });

  final IconData icon;
  final String value;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final color = context.collectColors.onImagePrimary.withValues(alpha: 0.86);
    return Semantics(
      label: semanticLabel,
      child: ExcludeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(icon, size: 16, color: color),
            ),
            CollectSpacing.gapW8,
            Expanded(
              child: Text(
                value,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: color,
                  fontSize: CollectGroupCardTokens.metadataSize,
                  height: CollectGroupCardTokens.metadataLeading,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
