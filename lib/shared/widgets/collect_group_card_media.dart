part of 'collect_group_cards.dart';

class _GroupCoverMedia extends StatelessWidget {
  const _GroupCoverMedia({required this.collection});

  final CollectCollection collection;

  @override
  Widget build(BuildContext context) {
    return CollectGroupImage(
      value: collection.imageUrl,
      fallback: _GeneratedGroupCover(collection: collection),
    );
  }
}

class _GroupCoverScrim extends StatelessWidget {
  const _GroupCoverScrim();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              CollectColors.publicBlack.withValues(
                alpha: MediaQuery.highContrastOf(context) ? 0.86 : 0.62,
              ),
              CollectColors.transparentColor,
            ],
            stops: const [0.12, 0.5],
          ),
        ),
      ),
    );
  }
}

/// Owner-requested Rwanda editorial defaults are presentation only: they never
/// replace an uploaded photo or write invented group media into stored records.
class _GeneratedGroupCover extends StatelessWidget {
  const _GeneratedGroupCover({required this.collection});

  final CollectCollection collection;

  static const _photos = [
    'assets/marketing/rwanda/community-savings.png',
    'assets/marketing/rwanda/shared-goals.png',
    'assets/marketing/rwanda/everyday-payments.png',
    'assets/marketing/rwanda/banking-together.png',
    'assets/marketing/rwanda/kigali-hills.png',
  ];

  @override
  Widget build(BuildContext context) {
    final cover = CollectGroupCover.fallbackFor(collection);
    final asset = cover?.asset ?? _photos.last;
    return Image.asset(
      asset,
      fit: BoxFit.cover,
      cacheWidth: 768,
      alignment: Alignment(
        (cover?.focalX ?? .5) * 2 - 1,
        (cover?.focalY ?? .5) * 2 - 1,
      ),
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      errorBuilder: (context, error, stackTrace) => ColoredBox(
        color: CollectGroupCardTokens.footerInk,
        child: Icon(
          collectionTypeIcon(collection.collectionType),
          color: context.collectColors.onImagePrimary,
          size: 48,
        ),
      ),
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
  final selectedColor = _colorFromHex(
    CollectColors.groupColorHexForDisplay(collection.accentColorHex),
  );
  if (selectedColor != null) return selectedColor;
  const palette = CollectColors.groupAccentColors;
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
