part of 'collect_components.dart';

class CollectBentoGrid extends StatelessWidget {
  const CollectBentoGrid({
    required this.primary,
    required this.top,
    required this.bottom,
    super.key,
  });

  final Widget primary;
  final Widget top;
  final Widget bottom;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        final compact = constraints.maxWidth < 340 || textScale > 1.15;
        if (compact) {
          return Column(
            children: [
              primary,
              CollectSpacing.gap12,
              top,
              CollectSpacing.gap12,
              bottom,
            ],
          );
        }
        return SizedBox(
          height: 236,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 6, child: primary),
              CollectSpacing.gapW12,
              Expanded(
                flex: 5,
                child: Column(
                  children: [
                    Expanded(child: top),
                    CollectSpacing.gap12,
                    Expanded(child: bottom),
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

class BentoMetricCell extends StatelessWidget {
  const BentoMetricCell({
    required this.label,
    required this.value,
    this.detail,
    this.icon = CollectIcons.dashboard,
    this.tone = CollectStatusTone.info,
    this.emphasis = false,
    super.key,
  });

  final String label;
  final String value;
  final String? detail;
  final IconData icon;
  final CollectStatusTone tone;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return CollectCard(
      emphasis: emphasis ? CollectCardEmphasis.hero : CollectCardEmphasis.flat,
      padding: EdgeInsets.all(emphasis ? CollectSpacing.x4 : CollectSpacing.x3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              emphasis
                  ? CollectToneIcon(icon: icon, tone: tone)
                  : _BentoToneIcon(icon: icon, tone: tone),
              CollectSpacing.gapW8,
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.labelMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: emphasis
                      ? CollectTypography.amountLarge(colors.textPrimary)
                      : Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                ),
              ),
              if (detail != null) ...[
                CollectSpacing.gap4,
                Text(
                  detail!,
                  style: Theme.of(context).textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _BentoToneIcon extends StatelessWidget {
  const _BentoToneIcon({required this.icon, required this.tone});

  final IconData icon;
  final CollectStatusTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.statusBackground(tone),
        borderRadius: CollectRadius.pillBorder,
      ),
      child: SizedBox.square(
        dimension: 30,
        child: Icon(icon, color: colors.statusForeground(tone), size: 17),
      ),
    );
  }
}

class QuickActionButton extends StatelessWidget {
  const QuickActionButton({
    required this.icon,
    required this.label,
    this.detail,
    this.onTap,
    this.tone = CollectStatusTone.info,
    super.key,
  });

  final IconData icon;
  final String label;
  final String? detail;
  final VoidCallback? onTap;
  final CollectStatusTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Semantics(
      button: true,
      container: true,
      explicitChildNodes: true,
      label: detail == null ? label : '$label, $detail',
      child: Material(
        color: colors.glassControl,
        borderRadius: CollectRadius.cardBorder,
        child: InkWell(
          borderRadius: CollectRadius.cardBorder,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 128, minWidth: 124),
            child: Padding(
              padding: const EdgeInsets.all(CollectSpacing.x4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CollectToneIcon(icon: icon, tone: tone),
                  CollectSpacing.gap12,
                  Text(
                    label,
                    style: Theme.of(context).textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class QuickActionRail extends StatelessWidget {
  const QuickActionRail({
    required this.children,
    this.semanticLabel = 'Quick actions',
    super.key,
  });

  final List<Widget> children;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return Semantics(
      container: true,
      label: semanticLabel,
      child: SizedBox(
        height: 152,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          padding: EdgeInsets.zero,
          itemCount: children.length,
          separatorBuilder: (_, _) => CollectSpacing.gapW12,
          itemBuilder: (context, index) =>
              SizedBox(width: 142, child: children[index]),
        ),
      ),
    );
  }
}

class InsightCard extends StatelessWidget {
  const InsightCard({
    required this.title,
    required this.message,
    this.icon = CollectIcons.tips,
    this.tone = CollectStatusTone.info,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final String title;
  final String message;
  final IconData icon;
  final CollectStatusTone tone;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return CollectCard(
      emphasis: CollectCardEmphasis.flat,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CollectToneIcon(icon: icon, tone: tone),
          CollectSpacing.gapW12,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (actionLabel != null) ...[
                  CollectSpacing.gap8,
                  CollectButton(
                    label: actionLabel!,
                    icon: CollectIcons.arrowForward,
                    onPressed: onAction,
                    variant: CollectButtonVariant.subtle,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
