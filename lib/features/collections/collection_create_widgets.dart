part of 'collection_create_screen.dart';

class _CreateGroupReview extends StatelessWidget {
  const _CreateGroupReview({
    required this.title,
    required this.description,
    required this.collectionTypeOption,
    required this.receiver,
    required this.accentColor,
    required this.hasPhoto,
    this.error,
  });

  final String title;
  final String description;
  final CollectionTypeCatalogItem collectionTypeOption;
  final String receiver;
  final Color accentColor;
  final bool hasPhoto;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return CollectCard(
      emphasis: CollectCardEmphasis.glow,
      accentColor: accentColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Review group', style: Theme.of(context).textTheme.titleLarge),
          CollectSpacing.gap12,
          CollectListTile(
            leading: collectionTypeIcon(collectionTypeOption.type),
            title: collectionTypeOption.label,
            subtitle: collectionTypeOption.shortPurpose,
          ),
          CollectListTile(
            leading: CollectIcons.collections,
            title: title.isEmpty ? 'Group name missing' : title,
            subtitle: description,
          ),
          CollectListTile(
            leading: CollectIcons.momo,
            title: receiver.isEmpty ? 'Receiver missing' : receiver,
          ),
          CollectListTile(
            leading: CollectIcons.photo,
            title: hasPhoto ? 'Group photo selected' : 'No group photo',
          ),
          if (error != null) ...[
            CollectSpacing.gap12,
            InfoSecurityBanner(
              title: 'Create failed',
              message: error!,
              tone: CollectStatusTone.danger,
            ),
          ],
        ],
      ),
    );
  }
}

class _CollectionTypeGrid extends StatelessWidget {
  const _CollectionTypeGrid({
    required this.selected,
    required this.options,
    required this.onChanged,
  });

  final CollectionType selected;
  final List<CollectionTypeCatalogItem> options;
  final ValueChanged<CollectionType> onChanged;

  @override
  Widget build(BuildContext context) {
    return CollectionTypeIconSelector(
      selected: selected,
      options: options,
      onChanged: onChanged,
    );
  }
}

class _GroupColorPalette extends StatelessWidget {
  const _GroupColorPalette({
    required this.selectedHex,
    required this.onChanged,
  });

  final String selectedHex;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Group color', style: Theme.of(context).textTheme.labelLarge),
        CollectSpacing.gap8,
        Wrap(
          spacing: CollectSpacing.x2,
          runSpacing: CollectSpacing.x2,
          children: [
            for (final option in CollectColors.brandPrimaryOptions)
              _ColorSwatchButton(
                option: option,
                selected: selectedHex == option.hex,
                onTap: () => onChanged(option.hex),
              ),
          ],
        ),
      ],
    );
  }
}

class _CreateGroupPhotoRow extends StatelessWidget {
  const _CreateGroupPhotoRow({
    required this.title,
    required this.accentColor,
    required this.imageBytes,
    required this.onPick,
    this.onRemove,
  });

  final String title;
  final Color accentColor;
  final Uint8List? imageBytes;
  final VoidCallback onPick;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final displayTitle = title.isEmpty ? 'Group image' : title;
    return CollectCard(
      emphasis: CollectCardEmphasis.flat,
      padding: const EdgeInsets.all(CollectSpacing.x3),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: SizedBox.square(
              dimension: 82,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          accentColor.withValues(alpha: 0.52),
                          colors.glassPanel.withValues(alpha: 0.76),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                  ),
                  if (imageBytes != null)
                    Image.memory(imageBytes!, fit: BoxFit.cover)
                  else
                    Icon(
                      CollectIcons.photo,
                      color: colors.onImagePrimary,
                      size: 30,
                    ),
                ],
              ),
            ),
          ),
          CollectSpacing.gapW16,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayTitle,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: CollectTypography.weightBold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                CollectSpacing.gap4,
                Text(
                  imageBytes == null
                      ? 'Optional group photo'
                      : 'Photo selected',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton.filledTonal(
            tooltip: imageBytes == null ? 'Add photo' : 'Change photo',
            onPressed: onPick,
            icon: const Icon(CollectIcons.photo),
          ),
          if (onRemove != null) ...[
            CollectSpacing.gapW8,
            IconButton.filledTonal(
              tooltip: 'Remove photo',
              onPressed: onRemove,
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ],
      ),
    );
  }
}

class _MobileCreatePanel extends StatelessWidget {
  const _MobileCreatePanel({required this.children, this.error});

  final List<Widget> children;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return CollectCard(
      emphasis: CollectCardEmphasis.flat,
      padding: const EdgeInsets.all(CollectSpacing.x4),
      child: Column(
        children: [
          for (var index = 0; index < children.length; index += 1) ...[
            children[index],
            if (index != children.length - 1) CollectSpacing.gap12,
          ],
          if (error != null) ...[
            CollectSpacing.gap12,
            InfoSecurityBanner(
              title: 'Create failed',
              message: error!,
              tone: CollectStatusTone.danger,
            ),
          ],
        ],
      ),
    );
  }
}

String? _mimeTypeFromName(String name) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.gif')) return 'image/gif';
  if (lower.endsWith('.heic') || lower.endsWith('.heif')) return 'image/heic';
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
  return null;
}

class _ColorSwatchButton extends StatelessWidget {
  const _ColorSwatchButton({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final CollectPaletteOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final selectedForeground = option.color.computeLuminance() > 0.72
        ? colors.textPrimary
        : colors.onAccent;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Group color ${option.hex}',
      child: Material(
        color: option.color,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 40,
            height: 40,
            child: selected
                ? Icon(CollectIcons.check, size: 20, color: selectedForeground)
                : null,
          ),
        ),
      ),
    );
  }
}
