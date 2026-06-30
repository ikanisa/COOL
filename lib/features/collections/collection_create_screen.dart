import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/security/phone_normalizer.dart';
import '../../shared/providers/collect_app_state.dart';
import '../../shared/models/collect_models.dart';
import '../../shared/repositories/collect_repository.dart';
import '../../shared/widgets/collect_components.dart';
import '../../shared/widgets/screen_scaffold.dart';
import '../profile/profile_setup_screen.dart';
import '../status/native_permission_sheets.dart';
import 'group_creation_platform.dart';

part 'collection_create_widgets.dart';

class CollectionCreateScreen extends ConsumerStatefulWidget {
  const CollectionCreateScreen({super.key});

  @override
  ConsumerState<CollectionCreateScreen> createState() =>
      _CollectionCreateScreenState();
}

class _CollectionCreateScreenState
    extends ConsumerState<CollectionCreateScreen> {
  static const _lastStep = 4;

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
  CollectionType _collectionType = CollectionType.ikimina;
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
    _receiverNumber.addListener(_refreshPreview);
    _receiverPayCode.addListener(_refreshPreview);
  }

  @override
  void dispose() {
    _title.removeListener(_refreshPreview);
    _receiverNumber.removeListener(_refreshPreview);
    _receiverPayCode.removeListener(_refreshPreview);
    _title.dispose();
    _description.dispose();
    _receiverNumber.dispose();
    _receiverPayCode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(collectRepositoryProvider).currentProfile;
    if (profile == null) {
      return const ProfileSetupScreen();
    }
    if (!_syncedProfileMomo &&
        _receiverNumber.text.trim().isEmpty &&
        profile.momoNumber?.trim().isNotEmpty == true) {
      _receiverNumber.text = profile.momoNumber!;
      _syncedProfileMomo = true;
    }
    final canCreate = canCreateGroupsOnThisPlatform();
    if (!canCreate) {
      return const SizedBox.shrink();
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
            onPressed: _creating || !_canUsePrimaryAction
                ? null
                : _primaryAction,
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
                label: 'Description, optional',
                maxLines: 2,
                textInputAction: TextInputAction.newline,
                textCapitalization: TextCapitalization.sentences,
                autocorrect: true,
              ),
            ],
          ),
        ] else if (_step == 1) ...[
          _CollectionTypeGrid(
            selected: _collectionType,
            onChanged: (type) => setState(() {
              _collectionType = type;
              _error = null;
            }),
          ),
        ] else if (_step == 2) ...[
          _MobileCreatePanel(
            error: _error,
            children: [
              CollectMomoReceiverCard(
                mode: _receiverMode,
                onChanged: (mode) => setState(() {
                  _receiverMode = mode;
                  _error = null;
                }),
                numberController: _receiverNumber,
                codeController: _receiverPayCode,
                numberInputLabel: 'Receiver MoMo',
                codeInputLabel: 'MoMo code',
              ),
            ],
          ),
        ] else if (_step == 3) ...[
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
            collectionType: _collectionType,
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

  bool get _canUsePrimaryAction {
    if (_creating) return false;
    return switch (_step) {
      0 => _title.text.trim().isNotEmpty,
      1 => true,
      2 => _normalizedReceiverValue().isNotEmpty,
      3 => true,
      _ =>
        _title.text.trim().isNotEmpty && _normalizedReceiverValue().isNotEmpty,
    };
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
      setState(() {
        _step = 2;
        _error = null;
      });
      return;
    }
    if (_step == 2) {
      if (_normalizedReceiverValue().isEmpty) {
        setState(() => _error = _receiverErrorMessage);
        return;
      }
      setState(() {
        _step = 3;
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
            collectionType: _collectionType,
            categorySubtype: _defaultCategorySubtype(_collectionType),
            purposeLabel: _collectionType.shortPurpose,
            receiverMomoNumber: receiver,
            receiverLabel: _receiverDisplayLabel,
            receiverIsMomoPayCode:
                _receiverMode == CollectMomoReceiverMode.momoPayCode,
            accentColorHex: _accentColorHex,
            imageUrl: _selectedImageDataUri(),
          );
      if (!mounted) return;
      context.go('/groups/${collection.id}');
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
    await showSmsAccessSheet(context, onRetry: _create);
    return false;
  }

  String get _receiverDisplayLabel {
    return _receiverMode == CollectMomoReceiverMode.momoPayCode
        ? 'MoMo code'
        : 'Primary MoMo receiver';
  }

  String get _receiverErrorMessage {
    return _receiverMode == CollectMomoReceiverMode.momoPayCode
        ? 'Use a 5 or 6 digit MoMo code.'
        : 'Use an MTN MoMo number.';
  }

  String get _receiverPreviewLabel {
    final value = _activeReceiverController.text.trim();
    if (value.isEmpty) return '';
    return _receiverMode == CollectMomoReceiverMode.momoPayCode
        ? 'MoMo code $value'
        : value;
  }

  String _normalizedReceiverValue() {
    final value = _activeReceiverController.text.trim();
    if (value.isEmpty) return '';
    if (_receiverMode == CollectMomoReceiverMode.momoPayCode) {
      final digits = value.replaceAll(RegExp(r'\D'), '');
      return digits.length >= 5 && digits.length <= 6 ? digits : '';
    }
    return PhoneNormalizer.tryNormalizeMtnMomoLocal(value) ?? '';
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
