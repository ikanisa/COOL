part of 'collect_group_cards.dart';

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
