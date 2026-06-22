import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../app/theme/collect_motion.dart';
import '../../core/utils/money_format.dart';
import '../models/collect_models.dart';
import 'collect_components.dart';

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
                        top: CollectSpacing.x3,
                        right: CollectSpacing.x3,
                        child: _PublicGlyph(accent: accent),
                      ),
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
    final accent = _groupAccent(context, collection);
    return CollectCard(
      onTap: onTap,
      emphasis: CollectCardEmphasis.compact,
      padding: const EdgeInsets.all(CollectSpacing.x3),
      accentColor: accent,
      backgroundGradient: _groupCardGradient(context, accent),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  collection.title,
                  style: Theme.of(context).textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                CollectSpacing.gap4,
                Text(
                  '${collection.collectionType.label} · ${formatRwf(summary.amountRaisedRwf)} · ${summary.supporterCount} members',
                  style: Theme.of(context).textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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

LinearGradient _groupCardGradient(BuildContext context, Color accent) {
  final colors = context.collectColors;
  final isDark = Theme.of(context).brightness == Brightness.dark;
  if (isDark) {
    final lead = Color.alphaBlend(
      accent.withValues(alpha: 0.18),
      CollectColors.referencePaymentsPurpleDeep,
    );
    final middle = Color.alphaBlend(
      colors.periwinklePaint.withValues(alpha: 0.10),
      CollectColors.referencePaymentsPurple,
    );
    final tail = Color.alphaBlend(
      colors.rosePaint.withValues(alpha: 0.08),
      CollectColors.referenceContentDark,
    );
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [lead, middle, tail],
      stops: const [0, 0.54, 1],
    );
  }
  final lead = Color.alphaBlend(
    accent.withValues(alpha: 0.24),
    colors.surfaceRaised,
  );
  final middle = Color.alphaBlend(
    colors.periwinklePaint.withValues(alpha: 0.12),
    colors.surfaceRaised,
  );
  final tail = Color.alphaBlend(
    colors.rosePaint.withValues(alpha: 0.16),
    colors.surfaceRaised,
  );
  return LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [lead, middle, tail],
    stops: const [0, 0.55, 1],
  );
}

BoxDecoration _groupFooterDecoration(BuildContext context) {
  final colors = context.collectColors;
  final isDark = Theme.of(context).brightness == Brightness.dark;
  if (isDark) {
    return BoxDecoration(
      color: CollectColors.referenceAssetNavy.withValues(alpha: 0.88),
      border: Border(
        top: BorderSide(color: colors.onImagePrimary.withValues(alpha: 0.20)),
      ),
    );
  }
  return BoxDecoration(
    color: colors.surfaceReadable.withValues(alpha: 0.88),
    border: Border(
      top: BorderSide(color: colors.textPrimary.withValues(alpha: 0.10)),
    ),
  );
}

class _GroupIconMetric extends StatelessWidget {
  const _GroupIconMetric({
    required this.icon,
    required this.value,
    required this.semanticLabel,
    required this.accent,
  });

  final IconData icon;
  final String value;
  final String semanticLabel;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final metricColor = isDark ? colors.onImagePrimary : colors.textPrimary;
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final compactLargeText = textScale > 1.3;
    final textStyle = compactLargeText
        ? Theme.of(context).textTheme.labelMedium?.copyWith(
            color: metricColor,
            fontWeight: FontWeight.w900,
          )
        : Theme.of(context).textTheme.titleSmall?.copyWith(
            color: metricColor,
            fontWeight: FontWeight.w900,
          );
    return Semantics(
      label: semanticLabel,
      child: ExcludeSemantics(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: accent, size: compactLargeText ? 18 : 22),
            SizedBox(height: compactLargeText ? 2 : CollectSpacing.x1),
            Text(
              value,
              style: textStyle,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupCoverMedia extends StatelessWidget {
  const _GroupCoverMedia({required this.collection});

  final CollectCollection collection;

  @override
  Widget build(BuildContext context) {
    final imageUrl = collection.imageUrl?.trim();
    if (imageUrl != null && imageUrl.isNotEmpty) {
      final dataImageBytes = _decodeDataImage(imageUrl);
      if (dataImageBytes != null) {
        return _GroupCoverImageTone(
          child: Image.memory(
            dataImageBytes,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            filterQuality: FilterQuality.medium,
            frameBuilder: _fadeInImageFrame,
            errorBuilder: (context, error, stackTrace) =>
                _GeneratedGroupCover(collection: collection),
          ),
        );
      }
      return _GroupCoverImageTone(
        child: Image.network(
          imageUrl,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
          frameBuilder: _fadeInImageFrame,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return _GeneratedGroupCover(collection: collection);
          },
          errorBuilder: (context, error, stackTrace) =>
              _GeneratedGroupCover(collection: collection),
        ),
      );
    }
    return _GeneratedGroupCover(collection: collection);
  }
}

class _GroupCoverImageTone extends StatelessWidget {
  const _GroupCoverImageTone({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (Theme.of(context).brightness != Brightness.dark) return child;
    return ColorFiltered(
      colorFilter: ColorFilter.mode(
        CollectColors.referencePaymentsPurpleDeep.withValues(alpha: 0.28),
        BlendMode.multiply,
      ),
      child: child,
    );
  }
}

class _GroupCoverScrim extends StatelessWidget {
  const _GroupCoverScrim({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final deep = isDark
        ? CollectColors.referencePaymentsPurpleDeep
        : CollectColors.inkPrimary;
    final topAlpha = isDark ? 0.18 : 0.22;
    final midAlpha = isDark ? 0.38 : 0.42;
    final bottomAlpha = isDark ? 0.78 : 0.82;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            deep.withValues(alpha: topAlpha),
            Color.alphaBlend(
              accent.withValues(alpha: isDark ? 0.08 : 0.06),
              deep.withValues(alpha: midAlpha),
            ),
            deep.withValues(alpha: bottomAlpha),
          ],
          stops: const [0, 0.52, 1],
        ),
      ),
    );
  }
}

Widget _fadeInImageFrame(
  BuildContext context,
  Widget child,
  int? frame,
  bool wasSynchronouslyLoaded,
) {
  if (wasSynchronouslyLoaded) return child;
  return AnimatedOpacity(
    opacity: frame == null ? 0 : 1,
    duration: CollectMotion.duration(context, CollectMotion.medium),
    curve: CollectMotion.standard,
    child: child,
  );
}

Uint8List? _decodeDataImage(String value) {
  if (!value.startsWith('data:image/')) return null;
  final comma = value.indexOf(',');
  if (comma == -1 || comma == value.length - 1) return null;
  try {
    return base64Decode(value.substring(comma + 1));
  } catch (_) {
    return null;
  }
}

class _GroupCoverTitleOverlay extends StatelessWidget {
  const _GroupCoverTitleOverlay({
    required this.collection,
    required this.accent,
    this.compact = false,
  });

  final CollectCollection collection;
  final Color accent;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final foreground = colors.onImagePrimary;
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? CollectSpacing.x1 : 0,
      ),
      child: Align(
        alignment: Alignment.bottomLeft,
        child: FractionallySizedBox(
          widthFactor: compact ? 0.92 : 0.86,
          alignment: Alignment.bottomLeft,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? CollectSpacing.x2 : CollectSpacing.x3,
              vertical: compact ? 5 : 7,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  collection.collectionType.label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: foreground.withValues(alpha: 0.88),
                    fontWeight: FontWeight.w900,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                CollectSpacing.gap4,
                Text(
                  collection.title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w900,
                    fontSize: compact ? 15 : 18,
                    height: 1.0,
                    letterSpacing: 0,
                    shadows: [
                      Shadow(
                        color: CollectColors.referencePaymentsPurpleDeep
                            .withValues(alpha: 0.88),
                        offset: const Offset(0, 1),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GeneratedGroupCover extends StatelessWidget {
  const _GeneratedGroupCover({required this.collection});

  final CollectCollection collection;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final coverScrim = isDark
        ? CollectColors.referencePaymentsPurpleDeep
        : CollectColors.inkPrimary;
    final topAlpha = isDark ? 0.16 : 0.16;
    final bottomAlpha = isDark ? 0.62 : 0.70;
    final chipFill = isDark
        ? CollectColors.referenceContentDark.withValues(alpha: 0.88)
        : colors.surfaceReadable.withValues(alpha: 0.92);
    final chipBorder = isDark
        ? colors.onImagePrimary.withValues(alpha: 0.18)
        : colors.textPrimary.withValues(alpha: 0.12);
    final chipText = isDark ? colors.onImagePrimary : colors.textPrimary;
    final asset = _generatedGroupAsset(collection);
    return Stack(
      fit: StackFit.expand,
      children: [
        _GroupCoverImageTone(
          child: Image.asset(
            asset,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            filterQuality: FilterQuality.medium,
            frameBuilder: _fadeInImageFrame,
            errorBuilder: (context, error, stackTrace) => DecoratedBox(
              decoration: BoxDecoration(gradient: colors.screenGradient),
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                coverScrim.withValues(alpha: topAlpha),
                coverScrim.withValues(alpha: bottomAlpha),
              ],
            ),
          ),
        ),
        Positioned(
          left: CollectSpacing.x3,
          top: CollectSpacing.x3,
          child: Tooltip(
            message: collection.isPublic ? 'Public group' : 'Private group',
            child: Semantics(
              label: collection.isPublic ? 'Public group' : 'Private group',
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: chipFill,
                  shape: BoxShape.circle,
                  border: Border.all(color: chipBorder),
                ),
                child: SizedBox.square(
                  dimension: 34,
                  child: Icon(
                    collection.isPublic
                        ? CollectIcons.public
                        : CollectIcons.privacy,
                    size: 18,
                    color: collection.isPublic ? colors.success : chipText,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

String _generatedGroupAsset(CollectCollection collection) {
  final key = '${collection.id} ${collection.slug} ${collection.title}'
      .toLowerCase();
  if (key.contains('qr') ||
      key.contains('share') ||
      key.contains('invite') ||
      key.contains('link')) {
    return 'assets/brand/generated/collect_visual_qr_share.png';
  }
  if (key.contains('pay') ||
      key.contains('momo') ||
      key.contains('treasury') ||
      key.contains('fund')) {
    return 'assets/brand/generated/collect_visual_momo_signal.png';
  }
  return 'assets/brand/generated/collect_visual_group_momentum.png';
}

class _PrivacyGlyph extends StatelessWidget {
  const _PrivacyGlyph({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Receiver details stay private',
      child: Semantics(
        label: 'Receiver details stay private',
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.10),
            shape: BoxShape.circle,
          ),
          child: SizedBox(
            width: 38,
            height: 38,
            child: Icon(CollectIcons.shield, color: accent, size: 19),
          ),
        ),
      ),
    );
  }
}

class _PublicGlyph extends StatelessWidget {
  const _PublicGlyph({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Public group',
      child: Semantics(
        label: 'Public group',
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.10),
            shape: BoxShape.circle,
          ),
          child: SizedBox(
            width: 38,
            height: 38,
            child: Icon(CollectIcons.public, color: accent, size: 19),
          ),
        ),
      ),
    );
  }
}

Color _groupAccent(BuildContext context, CollectCollection collection) {
  final colors = context.collectColors;
  final selectedColor = _colorFromHex(collection.accentColorHex);
  if (selectedColor != null) return selectedColor;
  final palette = [
    colors.brandPrimary,
    colors.brandSecondary,
    colors.brandAction,
    colors.brandSuccess,
  ];
  final key = '${collection.id}${collection.title}';
  final index =
      key.codeUnits.fold<int>(0, (sum, unit) => sum + unit) % palette.length;
  return palette[index];
}

Color? _colorFromHex(String? hex) {
  final clean = hex?.trim().replaceFirst('#', '');
  if (clean == null || clean.length != 6) return null;
  final value = int.tryParse(clean, radix: 16);
  if (value == null) return null;
  return Color(int.parse('ff$clean', radix: 16));
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
