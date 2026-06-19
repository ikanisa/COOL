import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../shared/providers/collect_app_state.dart';
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
  static const _lastStep = 3;

  final _title = TextEditingController();
  final _description = TextEditingController();
  final _receiverNumber = TextEditingController();
  final _receiverPayCode = TextEditingController();
  final _imagePicker = ImagePicker();
  Uint8List? _groupImageBytes;
  String? _groupImageName;
  String? _groupImageMimeType;
  String _accentColorHex = CollectColors.brandPrimaryOptions.first.hex;
  CollectMomoReceiverMode _receiverMode = CollectMomoReceiverMode.momoNumber;
  bool _syncedProfileMomo = false;
  bool _creating = false;
  int _step = 0;
  String? _error;

  TextEditingController get _activeReceiverController {
    return _receiverMode == CollectMomoReceiverMode.momoPayCode
        ? _receiverPayCode
        : _receiverNumber;
  }

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
    _receiverNumber.dispose();
    _receiverPayCode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(collectRepositoryProvider).currentProfile;
    if (profile == null || profile.momoNumber?.trim().isNotEmpty != true) {
      return const ProfileReadinessScreen();
    }
    if (!_syncedProfileMomo &&
        _receiverNumber.text.trim().isEmpty &&
        profile.momoNumber?.trim().isNotEmpty == true) {
      _receiverNumber.text = profile.momoNumber!;
      _syncedProfileMomo = true;
    }
    final canCreate = canCreateGroupsOnThisPlatform();
    if (!canCreate) {
      return const IphoneCreateUnavailableScreen();
    }
    return ScreenScaffold(
      title: 'Create group',
      showHeader: false,
      bottomAction: BottomActionSurface(
        children: [
          CollectButton(
            label: _creating
                ? 'Creating group'
                : _step == _lastStep
                ? 'Create group'
                : 'Continue',
            icon: _step == _lastStep
                ? CollectIcons.check
                : CollectIcons.arrowForward,
            onPressed: _creating
                ? null
                : () {
                    _primaryAction();
                  },
            variant: CollectButtonVariant.primary,
            expand: true,
          ),
          if (_step > 0)
            CollectButton(
              label: 'Back',
              icon: CollectIcons.chevron,
              onPressed: _creating ? null : () => setState(() => _step -= 1),
              variant: CollectButtonVariant.secondary,
              expand: true,
            ),
        ],
      ),
      children: [
        const CollectPlainPageHeader(title: 'Create group'),
        if (_step == 0) ...[
          _MobileCreatePanel(
            error: _error,
            children: [
              CollectMobileInputField(
                controller: _title,
                icon: CollectIcons.collections,
                label: 'Group name',
                textInputAction: TextInputAction.next,
                textCapitalization: TextCapitalization.words,
                autocorrect: true,
              ),
              CollectMobileInputField(
                controller: _description,
                icon: CollectIcons.info,
                label: 'Description',
                maxLines: 2,
                textInputAction: TextInputAction.newline,
                textCapitalization: TextCapitalization.sentences,
                autocorrect: true,
              ),
            ],
          ),
        ] else if (_step == 1) ...[
          _MobileCreatePanel(
            error: _error,
            children: [
              CollectMomoReceiverModeToggle(
                mode: _receiverMode,
                onChanged: (mode) => setState(() {
                  _receiverMode = mode;
                  _error = null;
                }),
              ),
              CollectMobileInputField(
                controller: _activeReceiverController,
                icon: _receiverMode == CollectMomoReceiverMode.momoPayCode
                    ? CollectIcons.qr
                    : CollectIcons.momo,
                label: _receiverMode == CollectMomoReceiverMode.momoPayCode
                    ? 'MoMo Pay code'
                    : 'Receiver MoMo',
                keyboardType:
                    _receiverMode == CollectMomoReceiverMode.momoPayCode
                    ? TextInputType.number
                    : TextInputType.phone,
                textInputAction: TextInputAction.done,
                autofillHints:
                    _receiverMode == CollectMomoReceiverMode.momoPayCode
                    ? null
                    : const [AutofillHints.telephoneNumber],
              ),
            ],
          ),
        ] else if (_step == 2) ...[
          _MobileCreatePanel(
            error: _error,
            children: [
              _GroupColorPalette(
                selectedHex: _accentColorHex,
                onChanged: (hex) => setState(() => _accentColorHex = hex),
              ),
            ],
          ),
          _CreateGroupPhotoRow(
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
        ] else ...[
          _CreateGroupReview(
            title: _title.text.trim(),
            description: _description.text.trim(),
            receiver: _receiverPreviewLabel,
            accentColor: _selectedAccentColor,
            hasPhoto: _groupImageBytes != null,
            error: _error,
          ),
        ],
      ],
    );
  }

  Color get _selectedAccentColor {
    return CollectColors.brandPrimaryOptions
        .firstWhere(
          (option) => option.hex == _accentColorHex,
          orElse: () => CollectColors.brandPrimaryOptions.first,
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

  Future<void> _primaryAction() async {
    if (_step == 0) {
      if (_title.text.trim().isEmpty) {
        setState(() => _error = 'Name required.');
        return;
      }
      setState(() {
        _step = 1;
        _error = null;
      });
      return;
    }
    if (_step == 1) {
      if (_normalizedReceiverValue().isEmpty) {
        setState(() => _error = _receiverErrorMessage);
        return;
      }
      setState(() {
        _step = 2;
        _error = null;
      });
      return;
    }
    if (_step < _lastStep) {
      setState(() {
        _step += 1;
        _error = null;
      });
      return;
    }
    await _create();
  }

  Future<void> _create() async {
    final title = _title.text.trim();
    final receiver = _normalizedReceiverValue();
    if (title.isEmpty || receiver.isEmpty) {
      setState(() {
        _error = title.isEmpty ? 'Name required.' : _receiverErrorMessage;
      });
      return;
    }
    try {
      final hasSmsAccess = await _ensureSmsAccessForGroupCreation();
      if (!hasSmsAccess || !mounted) return;
      setState(() {
        _creating = true;
        _error = null;
      });
      final collection = await ref
          .read(collectRepositoryProvider.notifier)
          .createCollection(
            title: title,
            description: _description.text,
            receiverMomoNumber: receiver,
            receiverLabel: _receiverDisplayLabel,
            receiverIsMomoPayCode:
                _receiverMode == CollectMomoReceiverMode.momoPayCode,
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

  Future<bool> _ensureSmsAccessForGroupCreation() async {
    final status = ref.read(smsPermissionStatusProvider);
    if (status == SmsPermissionStatus.granted ||
        status == SmsPermissionStatus.unavailable) {
      return true;
    }
    final granted = await ref
        .read(collectRepositoryProvider.notifier)
        .setSmsAccess(true);
    if (!mounted) return false;
    if (granted) return true;
    context.go('/permissions/sms-denied');
    return false;
  }

  String get _receiverDisplayLabel {
    return _receiverMode == CollectMomoReceiverMode.momoPayCode
        ? 'MoMo Pay code'
        : 'Primary MoMo receiver';
  }

  String get _receiverErrorMessage {
    return _receiverMode == CollectMomoReceiverMode.momoPayCode
        ? 'Use a 5 or 6 digit MoMo Pay code.'
        : 'MoMo number required.';
  }

  String get _receiverPreviewLabel {
    final value = _activeReceiverController.text.trim();
    if (value.isEmpty) return '';
    return _receiverMode == CollectMomoReceiverMode.momoPayCode
        ? 'MoMo Pay code $value'
        : value;
  }

  String _normalizedReceiverValue() {
    final value = _activeReceiverController.text.trim();
    if (value.isEmpty) return '';
    if (_receiverMode == CollectMomoReceiverMode.momoPayCode) {
      final digits = value.replaceAll(RegExp(r'\D'), '');
      return digits.length >= 5 && digits.length <= 6 ? digits : '';
    }
    return value;
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

class _CreateGroupReview extends StatelessWidget {
  const _CreateGroupReview({
    required this.title,
    required this.description,
    required this.receiver,
    required this.accentColor,
    required this.hasPhoto,
    this.error,
  });

  final String title;
  final String description;
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
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
                    fontWeight: FontWeight.w900,
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
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
