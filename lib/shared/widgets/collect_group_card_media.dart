part of 'collect_group_cards.dart';

class _GroupCoverMedia extends StatelessWidget {
  const _GroupCoverMedia({required this.collection});

  final CollectCollection collection;

  @override
  Widget build(BuildContext context) {
    final imageUrl = collection.imageUrl?.trim();
    if (imageUrl == null || imageUrl.isEmpty) {
      return _GeneratedGroupCover(collection: collection);
    }
    if (imageUrl.startsWith('data:image/')) {
      final bytes = _decodeDataImage(imageUrl);
      if (bytes == null) return _GeneratedGroupCover(collection: collection);
      return Image.memory(
        bytes,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
        frameBuilder: _fadeInImageFrame,
        errorBuilder: (context, error, stackTrace) =>
            _GeneratedGroupCover(collection: collection),
      );
    }
    return Image.network(
      imageUrl,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      frameBuilder: _fadeInImageFrame,
      loadingBuilder: (context, child, progress) => progress == null
          ? child
          : _GeneratedGroupCover(collection: collection),
      errorBuilder: (context, error, stackTrace) =>
          _GeneratedGroupCover(collection: collection),
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
    final seed = collection.id.codeUnits.fold<int>(
      0,
      (value, unit) => ((value * 31) + unit) & 0x7fffffff,
    );
    final asset = switch (collection.collectionType) {
      CollectionType.ikimina => _photos[seed % 2],
      CollectionType.sport || CollectionType.wedding => _photos[1],
      CollectionType.church => _photos[0],
      CollectionType.other => _photos[seed % _photos.length],
    };
    return Image.asset(
      asset,
      fit: BoxFit.cover,
      cacheWidth: 1200,
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
