part of 'group_profile_screen.dart';

class _GroupProfileMediaRow extends StatelessWidget {
  const _GroupProfileMediaRow({
    required this.title,
    required this.accentColor,
    required this.onPick,
    this.onRemove,
    this.imageBytes,
    this.imageUrl,
  });

  final String title;
  final Color accentColor;
  final Uint8List? imageBytes;
  final String? imageUrl;
  final VoidCallback onPick;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final hasImage = imageBytes != null || _imageProviderUrl(imageUrl) != null;
    final titleText = title.trim().isEmpty ? 'Group' : title.trim();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.glassControl,
        borderRadius: CollectRadius.cardBorder,
        border: Border.all(color: colors.glassBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(CollectSpacing.x3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Semantics(
              image: true,
              label: hasImage ? 'Group image' : 'Group image placeholder',
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: SizedBox.square(
                  dimension: 76,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              accentColor.withValues(alpha: 0.62),
                              colors.glassPanel.withValues(alpha: 0.82),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                      ),
                      if (imageBytes != null)
                        Image.memory(
                          imageBytes!,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                          filterQuality: FilterQuality.medium,
                          frameBuilder: _fadeInGroupProfileImage,
                        )
                      else if (_imageProviderUrl(imageUrl) case final url?)
                        Image.network(
                          url,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                          filterQuality: FilterQuality.medium,
                          frameBuilder: _fadeInGroupProfileImage,
                          loadingBuilder: (context, child, loadingProgress) =>
                              loadingProgress == null
                              ? child
                              : const SizedBox.shrink(),
                          errorBuilder: (context, error, stackTrace) =>
                              const SizedBox.shrink(),
                        ),
                      if (!hasImage)
                        Center(
                          child: Text(
                            titleText.characters.first.toUpperCase(),
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(
                                  color: colors.onImagePrimary,
                                  fontWeight: CollectTypography.weightSemibold,
                                ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            CollectSpacing.gapW12,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titleText,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: colors.textPrimary,
                      fontWeight: CollectTypography.weightSemibold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            CollectSpacing.gapW8,
            IconButton(
              tooltip: 'Upload image',
              onPressed: onPick,
              icon: const Icon(CollectIcons.photo),
              style: IconButton.styleFrom(
                backgroundColor: colors.glassPanel,
                foregroundColor: colors.textPrimary,
                fixedSize: const Size.square(CollectSpacing.iconTarget),
              ),
            ),
            if (onRemove != null) ...[
              CollectSpacing.gapW4,
              IconButton(
                tooltip: 'Remove image',
                onPressed: onRemove,
                icon: const Icon(Icons.close_rounded),
                style: IconButton.styleFrom(
                  backgroundColor: colors.glassPanel,
                  foregroundColor: colors.textPrimary,
                  fixedSize: const Size.square(CollectSpacing.iconTarget),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String? _mimeTypeFromName(String name) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
  return null;
}

Widget _fadeInGroupProfileImage(
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

String? _imageProviderUrl(String? value) {
  if (value == null || value.trim().isEmpty || value.startsWith('data:')) {
    return null;
  }
  return value;
}
