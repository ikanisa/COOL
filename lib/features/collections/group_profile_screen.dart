import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/theme/collect_motion.dart';
import '../../shared/models/collect_models.dart';
import '../../shared/repositories/collect_repository.dart';
import '../../shared/widgets/collect_components.dart';
import '../../shared/widgets/screen_scaffold.dart';

class GroupProfileScreen extends ConsumerStatefulWidget {
  const GroupProfileScreen({required this.collectionId, super.key});

  final String collectionId;

  @override
  ConsumerState<GroupProfileScreen> createState() => _GroupProfileScreenState();
}

class _GroupProfileScreenState extends ConsumerState<GroupProfileScreen> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _receiver = TextEditingController();
  final _receiverLabel = TextEditingController();
  final _imagePicker = ImagePicker();

  Uint8List? _imageBytes;
  String? _imageName;
  String? _imageMimeType;
  String _accentColorHex = CollectColors.brandPrimaryOptions.first.hex;
  String _cadence = 'monthly';
  bool _isPublic = false;
  bool _loaded = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _receiver.dispose();
    _receiverLabel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.read(collectRepositoryProvider.notifier);
    final collection = repo.collectionById(widget.collectionId);
    _loadOnce(collection);

    return ScreenScaffold(
      title: 'Group profile',
      subtitle: collection.title,
      bottomAction: BottomActionSurface(
        children: [
          CollectButton(
            label: _saving ? 'Saving' : 'Save changes',
            icon: CollectIcons.check,
            onPressed: _saving ? null : () => _save(collection),
            expand: true,
          ),
        ],
      ),
      children: [
        _GroupProfilePhotoCard(
          title: _name.text.trim().isEmpty ? collection.title : _name.text,
          accentColor: _selectedColor,
          imageBytes: _imageBytes,
          imageUrl: _imageBytes == null ? collection.imageUrl : null,
          onPick: _pickImage,
          onRemove: () => setState(() {
            _imageBytes = null;
            _imageName = null;
            _imageMimeType = null;
          }),
        ),
        FormSectionCard(
          errorMessage: _error,
          children: [
            CollectTextInput(
              controller: _name,
              label: 'Group name',
              textCapitalization: TextCapitalization.words,
              autocorrect: true,
            ),
            CollectTextInput(
              controller: _description,
              label: 'Description',
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              autocorrect: true,
            ),
            Material(
              color: context.collectColors.transparent,
              child: SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Public group'),
                value: _isPublic,
                onChanged: (value) => setState(() => _isPublic = value),
              ),
            ),
            _CadencePicker(
              selected: _cadence,
              onChanged: (value) => setState(() => _cadence = value),
            ),
            _ProfileColorPalette(
              selectedHex: _accentColorHex,
              onChanged: (value) => setState(() => _accentColorHex = value),
            ),
          ],
        ),
        FormSectionCard(
          title: 'Receiver MoMo',
          children: [
            CollectTextInput(
              controller: _receiver,
              label: 'MoMo number',
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.telephoneNumber],
            ),
            CollectTextInput(
              controller: _receiverLabel,
              label: 'Receiver name',
              textCapitalization: TextCapitalization.words,
              autocorrect: true,
            ),
          ],
        ),
      ],
    );
  }

  Color get _selectedColor {
    return CollectColors.brandPrimaryOptions
        .firstWhere(
          (option) => option.hex == _accentColorHex,
          orElse: () => CollectColors.brandPrimaryOptions.first,
        )
        .color;
  }

  void _loadOnce(CollectCollection collection) {
    if (_loaded) return;
    _loaded = true;
    _name.text = collection.title;
    _description.text = collection.description;
    _receiver.text = collection.receiverMomoNumber ?? '';
    _receiverLabel.text = collection.receiverDisplayLabel;
    _accentColorHex =
        collection.accentColorHex ??
        CollectColors.brandPrimaryOptions.first.hex;
    _cadence = collection.recurringCadence;
    _isPublic = collection.isPublic;
  }

  Future<void> _pickImage() async {
    try {
      final image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1800,
        imageQuality: 86,
      );
      if (image == null) return;
      final bytes = await image.readAsBytes();
      if (!mounted) return;
      setState(() {
        _imageBytes = bytes;
        _imageName = image.name;
        _imageMimeType = image.mimeType ?? _mimeTypeFromName(image.name);
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Image upload failed.');
    }
  }

  Future<void> _save(CollectCollection collection) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final imageUrl = _selectedImageDataUri() ?? collection.imageUrl;
      await ref
          .read(collectRepositoryProvider.notifier)
          .updateCollectionProfile(
            collectionId: collection.id,
            title: _name.text,
            description: _description.text,
            receiverMomoNumber: _receiver.text,
            receiverLabel: _receiverLabel.text,
            recurringCadence: _cadence,
            accentColorHex: _accentColorHex,
            imageUrl: imageUrl,
            isPublic: _isPublic,
          );
      if (!mounted) return;
      context.go('/groups/${collection.id}/manage');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error.toString();
      });
    }
  }

  String? _selectedImageDataUri() {
    final bytes = _imageBytes;
    if (bytes == null || bytes.isEmpty) return null;
    final mimeType =
        _imageMimeType ?? _mimeTypeFromName(_imageName ?? '') ?? 'image/jpeg';
    return 'data:$mimeType;base64,${base64Encode(bytes)}';
  }
}

class _GroupProfilePhotoCard extends StatelessWidget {
  const _GroupProfilePhotoCard({
    required this.title,
    required this.accentColor,
    required this.onPick,
    required this.onRemove,
    this.imageBytes,
    this.imageUrl,
  });

  final String title;
  final Color accentColor;
  final Uint8List? imageBytes;
  final String? imageUrl;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return CollectCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 1.9,
            child: Stack(
              fit: StackFit.expand,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        accentColor.withValues(alpha: 0.62),
                        colors.glassPanel,
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
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          colors.transparent,
                          colors.periwinklePaint.withValues(alpha: 0.78),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: CollectSpacing.x4,
                  right: CollectSpacing.x4,
                  bottom: CollectSpacing.x4,
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: colors.onImagePrimary,
                      fontWeight: FontWeight.w900,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(CollectSpacing.x3),
            child: Row(
              children: [
                Expanded(
                  child: CollectButton(
                    label: 'Upload image',
                    icon: CollectIcons.photo,
                    onPressed: onPick,
                    expand: true,
                  ),
                ),
                CollectSpacing.gapW12,
                IconButton.filledTonal(
                  tooltip: 'Remove image',
                  onPressed: onRemove,
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CadencePicker extends StatelessWidget {
  const _CadencePicker({required this.selected, required this.onChanged});

  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Recurring contribution',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        CollectSpacing.gap8,
        Wrap(
          spacing: CollectSpacing.x2,
          runSpacing: CollectSpacing.x2,
          children:
              const [
                    _CadenceOption(value: 'daily', label: 'Daily'),
                    _CadenceOption(value: 'weekly', label: 'Weekly'),
                    _CadenceOption(value: 'monthly', label: 'Monthly'),
                  ]
                  .map(
                    (option) => ChoiceChip(
                      label: Text(option.label),
                      selected: selected == option.value,
                      onSelected: (_) => onChanged(option.value),
                    ),
                  )
                  .toList(),
        ),
      ],
    );
  }
}

class _ProfileColorPalette extends StatelessWidget {
  const _ProfileColorPalette({
    required this.selectedHex,
    required this.onChanged,
  });

  final String selectedHex;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
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
              Builder(
                builder: (context) {
                  final selected = selectedHex == option.hex;
                  final selectedForeground =
                      option.color.computeLuminance() > 0.72
                      ? colors.textPrimary
                      : colors.onAccent;
                  return Semantics(
                    button: true,
                    selected: selected,
                    label: 'Group color',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(24),
                      onTap: () => onChanged(option.hex),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: option.color,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: selected
                                ? selectedForeground
                                : colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: SizedBox(
                          width: 42,
                          height: 42,
                          child: selected
                              ? Icon(
                                  Icons.check_rounded,
                                  color: selectedForeground,
                                )
                              : null,
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ],
    );
  }
}

class _CadenceOption {
  const _CadenceOption({required this.value, required this.label});

  final String value;
  final String label;
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
