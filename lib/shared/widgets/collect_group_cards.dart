import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/utils/money_format.dart';
import '../models/collect_models.dart';
import 'collect_components.dart';

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
    return switch (variant) {
      GroupCardVariant.publicDiscovery => _PublicDiscoveryGroupCard(
        collection: collection,
        summary: summary,
        onTap: onTap,
        primaryAction: primaryAction,
      ),
      GroupCardVariant.compact => _CompactGroupCard(
        collection: collection,
        summary: summary,
        onTap: onTap,
        primaryAction: primaryAction,
      ),
      GroupCardVariant.visual => _VisualGroupCard(
        collection: collection,
        summary: summary,
        onTap: onTap,
        primaryAction: primaryAction,
      ),
      GroupCardVariant.owned => _OwnedGroupCard(
        collection: collection,
        summary: summary,
        onTap: onTap,
        primaryAction: primaryAction,
      ),
    };
  }
}

enum GroupCardVariant { owned, publicDiscovery, compact, visual }

class _OwnedGroupCard extends StatelessWidget {
  const _OwnedGroupCard({
    required this.collection,
    required this.summary,
    this.onTap,
    this.primaryAction,
  });

  final CollectCollection collection;
  final CollectionSummary summary;
  final VoidCallback? onTap;
  final Widget? primaryAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final accent = _groupAccent(context, collection);
    return CollectCard(
      onTap: onTap,
      padding: CollectSpacing.cardPaddingComfortable,
      emphasis: CollectCardEmphasis.tonal,
      accentColor: accent,
      backgroundGradient: _groupCardGradient(context, accent),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CollectionTypeBadge(
                      type: collection.collectionType,
                      compact: true,
                      iconOnly: true,
                    ),
                    CollectSpacing.gap4,
                    Text(
                      collection.title,
                      style: Theme.of(context).textTheme.titleLarge,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              CollectSpacing.gapW12,
              _PrivacyGlyph(accent: accent),
            ],
          ),
          CollectSpacing.gap16,
          Row(
            children: [
              Expanded(
                child: _GroupIconMetric(
                  icon: CollectIcons.money,
                  value: formatRwf(summary.amountRaisedRwf),
                  semanticLabel:
                      'Total collected ${formatRwf(summary.amountRaisedRwf)}',
                  accent: accent,
                ),
              ),
              Expanded(
                child: _GroupIconMetric(
                  icon: CollectIcons.people,
                  value: '${summary.supporterCount}',
                  semanticLabel: '${summary.supporterCount} group members',
                  accent: colors.success,
                ),
              ),
              if (primaryAction != null)
                Expanded(child: Center(child: primaryAction!)),
            ],
          ),
        ],
      ),
    );
  }
}

class _PublicDiscoveryGroupCard extends StatelessWidget {
  const _PublicDiscoveryGroupCard({
    required this.collection,
    required this.summary,
    this.onTap,
    this.primaryAction,
  });

  final CollectCollection collection;
  final CollectionSummary summary;
  final VoidCallback? onTap;
  final Widget? primaryAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final accent = _groupAccent(context, collection);
    const coverHeight = 124.0;
    return CollectCard(
      onTap: onTap,
      padding: EdgeInsets.zero,
      emphasis: CollectCardEmphasis.glow,
      accentColor: accent,
      backgroundGradient: _groupCardGradient(context, accent),
      child: ClipRRect(
        borderRadius: CollectRadius.cardLargeBorder,
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: coverHeight,
                  width: double.infinity,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _GroupCoverMedia(collection: collection),
                      _GroupCoverScrim(accent: accent),
                      Positioned(
                        left: CollectSpacing.x3,
                        right: CollectSpacing.x3,
                        bottom: CollectSpacing.x3,
                        child: _GroupCoverTitleOverlay(
                          collection: collection,
                          accent: accent,
                          compact: true,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: DecoratedBox(
                    decoration: _groupFooterDecoration(context),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        CollectSpacing.x3,
                        CollectSpacing.x1,
                        CollectSpacing.x3,
                        CollectSpacing.x2,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            flex: 2,
                            child: _GroupIconMetric(
                              icon: CollectIcons.money,
                              value: formatRwf(summary.amountRaisedRwf),
                              semanticLabel:
                                  'Total collected ${formatRwf(summary.amountRaisedRwf)}',
                              accent: accent,
                            ),
                          ),
                          Expanded(
                            child: _GroupIconMetric(
                              icon: CollectIcons.people,
                              value: '${summary.supporterCount}',
                              semanticLabel:
                                  '${summary.supporterCount} group members',
                              accent: colors.success,
                            ),
                          ),
                          if (primaryAction != null)
                            SizedBox(
                              width: 48,
                              child: Center(child: primaryAction!),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactGroupCard extends StatelessWidget {
  const _CompactGroupCard({
    required this.collection,
    required this.summary,
    this.onTap,
    this.primaryAction,
  });

  final CollectCollection collection;
  final CollectionSummary summary;
  final VoidCallback? onTap;
  final Widget? primaryAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final accent = _groupAccent(context, collection);
    return CollectCard(
      onTap: onTap,
      emphasis: CollectCardEmphasis.normal,
      padding: const EdgeInsets.all(CollectSpacing.x4),
      accentColor: accent,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: SizedBox.square(
              dimension: 64,
              child: Icon(
                collectionTypeIcon(collection.collectionType),
                color: colors.onImagePrimary,
                size: 30,
              ),
            ),
          ),
          CollectSpacing.gapW16,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  collection.title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                ),
                CollectSpacing.gap4,
                _GroupMetaIconRow(
                  collection: collection,
                  summary: summary,
                  accent: accent,
                ),
              ],
            ),
          ),
          CollectSpacing.gapW12,
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 104),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    formatRwf(summary.amountRaisedRwf),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                    ),
                    maxLines: 1,
                  ),
                ),
                CollectSpacing.gap4,
                Icon(
                  CollectIcons.chevron,
                  color: colors.textSecondary.withValues(alpha: 0.84),
                ),
              ],
            ),
          ),
          if (primaryAction != null) ...[CollectSpacing.gapW12, primaryAction!],
        ],
      ),
    );
  }
}

class _VisualGroupCard extends StatelessWidget {
  const _VisualGroupCard({
    required this.collection,
    required this.summary,
    this.onTap,
    this.primaryAction,
  });

  final CollectCollection collection;
  final CollectionSummary summary;
  final VoidCallback? onTap;
  final Widget? primaryAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final accent = _groupAccent(context, collection);
    const coverHeight = 136.0;
    return CollectCard(
      onTap: onTap,
      padding: EdgeInsets.zero,
      emphasis: CollectCardEmphasis.glow,
      accentColor: accent,
      backgroundGradient: _groupCardGradient(context, accent),
      child: ClipRRect(
        borderRadius: CollectRadius.cardLargeBorder,
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: coverHeight,
                  width: double.infinity,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _GroupCoverMedia(collection: collection),
                      _GroupCoverScrim(accent: accent),
                      Positioned(
                        left: CollectSpacing.x4,
                        right: CollectSpacing.x4,
                        bottom: CollectSpacing.x4,
                        child: _GroupCoverTitleOverlay(
                          collection: collection,
                          accent: accent,
                        ),
                      ),
                    ],
                  ),
                ),
                DecoratedBox(
                  decoration: _groupFooterDecoration(context),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      CollectSpacing.x4,
                      CollectSpacing.x2,
                      CollectSpacing.x4,
                      CollectSpacing.x4,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: _GroupIconMetric(
                            icon: CollectIcons.money,
                            value: formatRwf(summary.amountRaisedRwf),
                            semanticLabel:
                                'Total collected ${formatRwf(summary.amountRaisedRwf)}',
                            accent: accent,
                          ),
                        ),
                        Expanded(
                          child: _GroupIconMetric(
                            icon: CollectIcons.people,
                            value: '${summary.supporterCount}',
                            semanticLabel:
                                '${summary.supporterCount} group members',
                            accent: colors.success,
                          ),
                        ),
                        if (primaryAction != null)
                          Expanded(child: Center(child: primaryAction!)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
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
