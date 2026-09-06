import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'collect_components.dart';

class CollectGroupPhoto {
  const CollectGroupPhoto(this.name, this.asset);

  final String name;
  final String asset;

  static const collection = [
    CollectGroupPhoto(
      'Community savings',
      'assets/marketing/rwanda/community-savings.png',
    ),
    CollectGroupPhoto(
      'Shared goals',
      'assets/marketing/rwanda/shared-goals.png',
    ),
    CollectGroupPhoto(
      'Everyday payments',
      'assets/marketing/rwanda/everyday-payments.png',
    ),
    CollectGroupPhoto(
      'Banking together',
      'assets/marketing/rwanda/banking-together.png',
    ),
    CollectGroupPhoto(
      'Kigali hills',
      'assets/marketing/rwanda/kigali-hills.png',
    ),
  ];
}

Future<XFile?> pickCollectGroupPhoto(
  BuildContext context, {
  required ImagePicker imagePicker,
}) async {
  final selection = await showModalBottomSheet<String>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    sheetAnimationStyle: CollectMotion.animationStyle(context),
    builder: (context) => const CollectGroupPhotoSheet(),
  );
  if (selection == null || !context.mounted) return null;
  if (selection == 'device-gallery') {
    return imagePicker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1800,
      imageQuality: 86,
    );
  }
  // Only bundled choices can reach the asset loader. Existing group media is
  // changed by the normal edit/save flow, never by opening this library.
  final photo = CollectGroupPhoto.collection.firstWhere(
    (photo) => photo.asset == selection,
  );
  final data = await rootBundle.load(photo.asset);
  return XFile.fromData(
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    mimeType: 'image/png',
    name: photo.asset.split('/').last,
  );
}

class CollectGroupPhotoSheet extends StatelessWidget {
  const CollectGroupPhotoSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return FractionallySizedBox(
      heightFactor: 0.88,
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        'Group photo',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close photo collection',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                children: [
                  CollectButton(
                    label: 'Choose your own photo',
                    icon: CollectIcons.photo,
                    expand: true,
                    onPressed: () =>
                        Navigator.of(context).pop('device-gallery'),
                  ),
                  CollectSpacing.gap24,
                  Text(
                    'Rwanda collection',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  CollectSpacing.gap8,
                  Text(
                    'Illustrative scenes for your group.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                  CollectSpacing.gap16,
                  for (final photo in CollectGroupPhoto.collection)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Semantics(
                        button: true,
                        label: 'Use ${photo.name} photo',
                        onTap: () => Navigator.of(context).pop(photo.asset),
                        excludeSemantics: true,
                        child: Material(
                          color: colors.surfaceMuted,
                          borderRadius: BorderRadius.circular(16),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            key: ValueKey('group-photo-${photo.name}'),
                            onTap: () => Navigator.of(context).pop(photo.asset),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                AspectRatio(
                                  aspectRatio: 3 / 2,
                                  child: Image.asset(
                                    photo.asset,
                                    fit: BoxFit.cover,
                                    cacheWidth: 960,
                                    excludeFromSemantics: true,
                                    errorBuilder:
                                        (context, error, stackTrace) => Icon(
                                          CollectIcons.photo,
                                          size: 48,
                                          color: colors.textSecondary,
                                        ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Text(
                                    photo.name,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
