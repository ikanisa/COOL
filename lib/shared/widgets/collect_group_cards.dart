import 'package:flutter/material.dart';

import '../../core/utils/money_format.dart';
import '../models/collect_models.dart';
import '../models/collect_group_cover.dart';
import 'collect_group_image.dart';
import 'collect_components.dart';

part 'collect_group_card_editorial.dart';
part 'collect_group_card_media.dart';
part 'collect_group_card_metrics.dart';

class GroupCard extends StatelessWidget {
  const GroupCard({
    required this.collection,
    required this.summary,
    this.onTap,
    this.primaryAction,
    this.variant = GroupCardVariant.owned,
    super.key,
  });

  final CollectCollection collection;
  final CollectionSummary summary;
  final VoidCallback? onTap;
  final Widget? primaryAction;
  final GroupCardVariant variant;

  @override
  Widget build(BuildContext context) {
    return _EditorialGroupCard(
      collection: collection,
      summary: summary,
      variant: variant,
      onTap: onTap,
      primaryAction: primaryAction,
    );
  }
}

enum GroupCardVariant { owned, publicDiscovery, compact, visual }

class GroupListPanel extends StatelessWidget {
  const GroupListPanel({
    required this.collections,
    required this.summaries,
    this.onGroupTap,
    super.key,
  });

  final List<CollectCollection> collections;
  final Map<String, CollectionSummary> summaries;
  final ValueChanged<CollectCollection>? onGroupTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final panel = CollectCard(
      padding: EdgeInsets.zero,
      emphasis: CollectCardEmphasis.normal,
      child: Column(
        children: [
          for (var index = 0; index < collections.length; index += 1) ...[
            _GroupListRow(
              collection: collections[index],
              summary:
                  summaries[collections[index].id] ??
                  const CollectionSummary(
                    amountRaisedRwf: 0,
                    supporterCount: 0,
                  ),
              onTap: onGroupTap == null
                  ? null
                  : () => onGroupTap!(collections[index]),
            ),
            if (index != collections.length - 1)
              Divider(
                height: 1,
                thickness: 1,
                indent: 76,
                color: colors.border.withValues(alpha: 0.54),
              ),
          ],
        ],
      ),
    );
    return RepaintBoundary(child: panel);
  }
}

class _GroupListRow extends StatelessWidget {
  const _GroupListRow({
    required this.collection,
    required this.summary,
    this.onTap,
  });

  final CollectCollection collection;
  final CollectionSummary summary;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final accent = _groupAccent(context, collection);
    final formattedAmount = formatCurrencyTotals(
      summary.totalsByCurrency,
      separator: '\n',
    );
    final row = Padding(
      padding: const EdgeInsets.fromLTRB(
        CollectSpacing.x3,
        CollectSpacing.x3,
        CollectSpacing.x3,
        CollectSpacing.x3,
      ),
      child: Row(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.18),
              shape: BoxShape.circle,
              border: Border.all(color: accent.withValues(alpha: 0.22)),
            ),
            child: SizedBox.square(
              dimension: 48,
              child: Icon(
                collectionTypeIcon(collection.collectionType),
                color: colors.textPrimary,
                size: 23,
              ),
            ),
          ),
          CollectSpacing.gapW12,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  collection.title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: CollectTypography.weightSemibold,
                    letterSpacing: CollectTypography.trackingDefault,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                CollectSpacing.gap4,
                Semantics(
                  label:
                      '${collection.collectionType.label}, '
                      '${summary.supporterCountSemantics}',
                  child: ExcludeSemantics(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          CollectSemanticIcons.forKeyword('members'),
                          size: 15,
                          color: colors.textSecondary,
                        ),
                        CollectSpacing.gapW4,
                        Text(
                          summary.supporterCountLabel,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: colors.textSecondary,
                                fontWeight: CollectTypography.weightRegular,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          CollectSpacing.gapW8,
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    formattedAmount,
                    style: CollectTypography.amountCompact(
                      colors.textPrimary,
                    ).copyWith(fontWeight: CollectTypography.weightSemibold),
                    maxLines: summary.totalsByCurrency.length.clamp(1, 2),
                  ),
                ),
                CollectSpacing.gap4,
                Icon(CollectIcons.chevron, size: 18, color: colors.textMuted),
              ],
            ),
          ),
        ],
      ),
    );
    final VoidCallback? handleTap = onTap == null
        ? null
        : () {
            CollectHaptics.selection();
            onTap!();
          };
    return Semantics(
      button: onTap != null,
      onTap: handleTap,
      label:
          '${collection.title}, $formattedAmount, '
          '${summary.supporterCountSemantics}',
      child: ExcludeSemantics(
        child: onTap == null ? row : InkWell(onTap: handleTap, child: row),
      ),
    );
  }
}

class CollectionSummaryCard extends StatelessWidget {
  const CollectionSummaryCard({
    required this.collection,
    required this.summary,
    this.onTap,
    super.key,
  });

  final CollectCollection collection;
  final CollectionSummary summary;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GroupCard(collection: collection, summary: summary, onTap: onTap);
  }
}
