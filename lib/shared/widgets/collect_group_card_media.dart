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
        CollectColors.publicBlack.withValues(alpha: 0.18),
        BlendMode.multiply,
      ),
      child: child,
    );
  }
}

class _GroupCoverScrim extends StatelessWidget {
  const _GroupCoverScrim();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const deep = CollectColors.publicBlack;
    final bottomAlpha = isDark ? 0.78 : 0.82;
    return ColoredBox(color: deep.withValues(alpha: bottomAlpha));
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
    final categoryIcon = collectionTypeIcon(collection.collectionType);
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
                Tooltip(
                  message: collection.collectionType.label,
                  child: Semantics(
                    label: '${collection.collectionType.label} group',
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.24),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: foreground.withValues(alpha: 0.18),
                        ),
                      ),
                      child: SizedBox.square(
                        dimension: compact ? 24 : 28,
                        child: Icon(
                          categoryIcon,
                          color: foreground,
                          size: compact ? 14 : 16,
                        ),
                      ),
                    ),
                  ),
                ),
                CollectSpacing.gap4,
                Text(
                  collection.title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: foreground,
                    fontWeight: CollectTypography.weightBold,
                    fontSize: compact
                        ? CollectTypography.sizeBodyCompact
                        : CollectTypography.sizeBodyLarge,
                    height: CollectTypography.leadingSolid,
                    letterSpacing: CollectTypography.trackingDefault,
                    shadows: [
                      Shadow(
                        color: CollectColors.publicBlack.withValues(
                          alpha: 0.88,
                        ),
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
    return ColoredBox(
      color: isDark ? colors.surfaceMuted : CollectColors.publicBlack,
    );
  }
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

Color _groupAccent(BuildContext context, CollectCollection collection) {
  final colors = context.collectColors;
  final selectedColor = _colorFromHex(collection.accentColorHex);
  if (selectedColor != null) return selectedColor;
  final palette = [
    colors.defaultGroupAccent,
    colors.brandSecondary,
    colors.brandSuccess,
    colors.priorityColor,
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
