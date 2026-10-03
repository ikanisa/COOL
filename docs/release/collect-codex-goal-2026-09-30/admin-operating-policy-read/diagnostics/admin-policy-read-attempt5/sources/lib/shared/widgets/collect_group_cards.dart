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
  final CollectionSummary? summary;
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
              summary: summaries[collections[index].id],
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

/// Lazy equivalent of [GroupListPanel] for ScreenScaffold.sliver.
///
/// Never wrap this in a shrink-wrapped list or a box-to-sliver adapter.
/// Filtering, sorting, membership checks and financial values stay with the
/// caller; only near-viewport rows are built by the existing lazy card.
class GroupListSliver extends StatelessWidget {
  const GroupListSliver({
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
    return CollectSliverCardList(
      itemCount: collections.length,
      padding: EdgeInsets.zero,
      emphasis: CollectCardEmphasis.normal,
      itemBuilder: (context, index) {
        final collection = collections[index];
        return _GroupListRow(
          key: ValueKey('group-list-${collection.id}'),
          collection: collection,
          summary: summaries[collection.id],
          onTap: onGroupTap == null ? null : () => onGroupTap!(collection),
        );
      },
      separatorBuilder: (context, index) => Divider(
        height: 1,
        thickness: 1,
        indent: 76,
        color: context.collectColors.border.withValues(alpha: 0.54),
      ),
    );
  }
}

class _GroupListRow extends StatelessWidget {
  const _GroupListRow({
    required this.collection,
    required this.summary,
    this.onTap,
    super.key,
  });

  final CollectCollection collection;
  final CollectionSummary? summary;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final accent = _groupAccent(context, collection);
    // Missing data is not a measured zero. A local copy permits sound
    // null promotion without asserting that a public nullable field is present.
    final currentSummary = summary;
    final formattedAmount = currentSummary == null
        ? 'Not available'
        : formatCurrencyTotals(
            currentSummary.totalsByCurrency,
            separator: '\n',
          );
    final countLabel = currentSummary?.supporterCountLabel ?? '—';
    final countSemantics =
        currentSummary?.supporterCountSemantics ??
        'Contributor count unavailable';
    final amountSemantics = currentSummary == null
        ? 'Group total unavailable'
        : formattedAmount;
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
                      '$countSemantics',
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
                          countLabel,
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
                if (currentSummary == null)
                  Text(
                    formattedAmount,
                    softWrap: true,
                    textAlign: TextAlign.end,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.textSecondary,
                    ),
                  )
                else
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      formattedAmount,
                      style: CollectTypography.amountCompact(
                        colors.textPrimary,
                      ).copyWith(fontWeight: CollectTypography.weightSemibold),
                      maxLines: currentSummary.totalsByCurrency.length.clamp(
                        1,
                        2,
                      ),
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
          '${collection.title}, $amountSemantics, '
          '$countSemantics',
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
