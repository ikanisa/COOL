import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../shared/repositories/collect_repository.dart';
import '../../shared/widgets/collect_components.dart';
import '../../shared/widgets/screen_scaffold.dart';
import '../status/production_state_screens.dart';
import 'group_creation_platform.dart';

class CollectionCreateScreen extends ConsumerStatefulWidget {
  const CollectionCreateScreen({super.key});

  @override
  ConsumerState<CollectionCreateScreen> createState() =>
      _CollectionCreateScreenState();
}

class _CollectionCreateScreenState
    extends ConsumerState<CollectionCreateScreen> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _receiver = TextEditingController();
  final _imagePicker = ImagePicker();
  Uint8List? _groupImageBytes;
  String? _groupImageName;
  String? _groupImageMimeType;
  String _accentColorHex = _groupColorOptions.first.hex;
  bool _syncedProfileMomo = false;
  bool _creating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _title.addListener(_refreshPreview);
  }

  @override
  void dispose() {
    _title.removeListener(_refreshPreview);
    _title.dispose();
    _description.dispose();
    _receiver.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(collectRepositoryProvider).currentProfile;
    if (profile == null || profile.momoNumber?.trim().isNotEmpty != true) {
      return const ProfileReadinessScreen();
    }
    if (!_syncedProfileMomo &&
        _receiver.text.trim().isEmpty &&
        profile.momoNumber?.trim().isNotEmpty == true) {
      _receiver.text = profile.momoNumber!;
      _syncedProfileMomo = true;
    }
    final canCreate = canCreateGroupsOnThisPlatform();
    if (!canCreate) {
      return const IphoneCreateUnavailableScreen();
    }
    return ScreenScaffold(
      title: 'Create group',
      bottomAction: BottomActionSurface(
        children: [
          CollectButton(
            label: _creating ? 'Creating group' : 'Create group',
            icon: CollectIcons.check,
            onPressed: _creating ? null : _create,
            variant: CollectButtonVariant.primary,
            expand: true,
          ),
        ],
      ),
      children: [
        _CreateGroupPhotoCard(
          title: _title.text.trim(),
          accentColor: _selectedAccentColor,
          imageBytes: _groupImageBytes,
          onPick: _pickGroupImage,
          onRemove: _groupImageBytes == null
              ? null
              : () {
                  setState(() {
                    _groupImageBytes = null;
                    _groupImageName = null;
                    _groupImageMimeType = null;
                  });
                },
        ),
        _MobileCreatePanel(
          error: _error,
          children: [
            _MobileInputField(
              controller: _title,
              icon: CollectIcons.collections,
              label: 'Group name',
              textInputAction: TextInputAction.next,
              textCapitalization: TextCapitalization.words,
              autocorrect: true,
            ),
            _MobileInputField(
              controller: _description,
              icon: CollectIcons.info,
              label: 'Description',
              maxLines: 2,
              textInputAction: TextInputAction.newline,
              textCapitalization: TextCapitalization.sentences,
              autocorrect: true,
            ),
            _MobileInputField(
              controller: _receiver,
              icon: CollectIcons.momo,
              label: 'Receiver MoMo',
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.telephoneNumber],
            ),
            _GroupColorPalette(
              selectedHex: _accentColorHex,
              onChanged: (hex) => setState(() => _accentColorHex = hex),
            ),
          ],
        ),
      ],
    );
  }

  Color get _selectedAccentColor {
    return _groupColorOptions
        .firstWhere(
          (option) => option.hex == _accentColorHex,
          orElse: () => _groupColorOptions.first,
        )
        .color;
  }

  void _refreshPreview() {
    if (mounted) setState(() {});
  }

  Future<void> _pickGroupImage() async {
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
        _groupImageBytes = bytes;
        _groupImageName = image.name;
        _groupImageMimeType = image.mimeType ?? _mimeTypeFromName(image.name);
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Photo upload failed.';
      });
    }
  }

  Future<void> _create() async {
    final title = _title.text.trim();
    final receiver = _receiver.text.trim();
    if (title.isEmpty || receiver.isEmpty) {
      setState(() {
        _error = title.isEmpty ? 'Name required.' : 'MoMo number required.';
      });
      return;
    }
    setState(() {
      _creating = true;
      _error = null;
    });
    final smsAccessGranted = await ref
        .read(collectRepositoryProvider.notifier)
        .setSmsAccess(true);
    if (!smsAccessGranted) {
      if (!mounted) return;
      context.go('/permissions/sms-denied');
      return;
    }
    try {
      final collection = await ref
          .read(collectRepositoryProvider.notifier)
          .createCollection(
            title: title,
            description: _description.text,
            receiverMomoNumber: receiver,
            accentColorHex: _accentColorHex,
            imageUrl: _selectedImageDataUri(),
          );
      if (!mounted) return;
      context.go('/groups/${collection.id}/created');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _creating = false;
        _error = error.toString();
      });
    }
  }

  String? _selectedImageDataUri() {
    final bytes = _groupImageBytes;
    if (bytes == null || bytes.isEmpty) return null;
    final mimeType =
        _groupImageMimeType ??
        _mimeTypeFromName(_groupImageName ?? '') ??
        'image/jpeg';
    return 'data:$mimeType;base64,${base64Encode(bytes)}';
  }
}

const _groupColorOptions = [
  _GroupColorOption('#8885F0', Color(0xFF8885F0)),
  _GroupColorOption('#D38B96', Color(0xFFD38B96)),
  _GroupColorOption('#FF5E43', Color(0xFFFF5E43)),
  _GroupColorOption('#3CD070', Color(0xFF3CD070)),
  _GroupColorOption('#FFD5DE', Color(0xFFFFD5DE)),
  _GroupColorOption('#DAD7FF', Color(0xFFDAD7FF)),
];

class _GroupColorOption {
  const _GroupColorOption(this.hex, this.color);

  final String hex;
  final Color color;
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
            for (final option in _groupColorOptions)
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

class _CreateGroupPhotoCard extends StatelessWidget {
  const _CreateGroupPhotoCard({
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
    final displayTitle = title.isEmpty ? 'Group photo' : title;
    return CollectCard(
      padding: EdgeInsets.zero,
      emphasis: CollectCardEmphasis.glow,
      accentColor: accentColor,
      onTap: onPick,
      child: ClipRRect(
        borderRadius: CollectRadius.cardLargeBorder,
        child: SizedBox(
          height: 156,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (imageBytes == null)
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Color.alphaBlend(
                          accentColor.withValues(alpha: 0.34),
                          colors.surfaceRaised,
                        ),
                        Color.alphaBlend(
                          accentColor.withValues(alpha: 0.10),
                          colors.surface,
                        ),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                )
              else
                Image.memory(imageBytes!, fit: BoxFit.cover),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        colors.surface.withValues(alpha: 0.05),
                        colors.surface.withValues(alpha: 0.78),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
              ),
              Positioned(
                right: -18,
                top: -24,
                child: Icon(
                  CollectIcons.photo,
                  size: 122,
                  color: accentColor.withValues(alpha: 0.18),
                ),
              ),
              if (onRemove != null)
                Positioned(
                  top: CollectSpacing.x3,
                  right: CollectSpacing.x3,
                  child: IconButton.filledTonal(
                    tooltip: 'Remove photo',
                    onPressed: onRemove,
                    icon: const Icon(Icons.close_rounded),
                  ),
                ),
              Positioned(
                left: CollectSpacing.x4,
                right: CollectSpacing.x4,
                bottom: CollectSpacing.x4,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.surface.withValues(alpha: 0.76),
                    borderRadius: CollectRadius.panelBorder,
                    border: Border.all(
                      color: accentColor.withValues(alpha: 0.22),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(CollectSpacing.x3),
                    child: Row(
                      children: [
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: accentColor.withValues(alpha: 0.16),
                            borderRadius: CollectRadius.mdBorder,
                          ),
                          child: SizedBox.square(
                            dimension: 46,
                            child: Icon(
                              CollectIcons.photo,
                              color: accentColor,
                              size: 25,
                            ),
                          ),
                        ),
                        CollectSpacing.gapW12,
                        Expanded(
                          child: Text(
                            displayTitle,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        CollectSpacing.gapW8,
                        Text(
                          imageBytes == null ? 'Add' : 'Change',
                          style: Theme.of(
                            context,
                          ).textTheme.labelLarge?.copyWith(color: accentColor),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
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
      padding: const EdgeInsets.all(CollectSpacing.x2),
      emphasis: CollectCardEmphasis.tonal,
      child: Column(
        children: [
          for (var index = 0; index < children.length; index += 1) ...[
            children[index],
            if (index != children.length - 1) CollectSpacing.gap8,
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

class _MobileInputField extends StatelessWidget {
  const _MobileInputField({
    required this.controller,
    required this.icon,
    required this.label,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.maxLines = 1,
    this.textCapitalization = TextCapitalization.none,
    this.autocorrect = false,
  });

  final TextEditingController controller;
  final IconData icon;
  final String label;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final int maxLines;
  final TextCapitalization textCapitalization;
  final bool autocorrect;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceRaised.withValues(alpha: 0.78),
        borderRadius: CollectRadius.controlBorder,
        border: Border.all(color: colors.border.withValues(alpha: 0.64)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: CollectSpacing.x3,
          vertical: CollectSpacing.x1,
        ),
        child: Row(
          crossAxisAlignment: maxLines > 1
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.center,
          children: [
            Padding(
              padding: EdgeInsets.only(
                top: maxLines > 1 ? CollectSpacing.x2 : 0,
              ),
              child: Icon(icon, color: colors.textSecondary, size: 22),
            ),
            CollectSpacing.gapW12,
            Expanded(
              child: TextField(
                controller: controller,
                keyboardType: keyboardType,
                textInputAction:
                    textInputAction ??
                    (maxLines > 1
                        ? TextInputAction.newline
                        : TextInputAction.next),
                autofillHints: autofillHints,
                maxLines: maxLines,
                textCapitalization: textCapitalization,
                autocorrect: autocorrect,
                decoration: InputDecoration(
                  labelText: label,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
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

  final _GroupColorOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
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
                ? Icon(CollectIcons.check, size: 20, color: colors.surface)
                : null,
          ),
        ),
      ),
    );
  }
}
